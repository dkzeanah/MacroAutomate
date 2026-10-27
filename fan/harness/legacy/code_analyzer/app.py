"""
Python Code Analyzer Manager
A full-screen friendly Tkinter + SQLite project for analyzing, storing, running,
learning from, and iteratively refining Python code projects.

Optional Ollama support:
    Install Ollama, pull a model, then start Ollama locally.
    Example:
        ollama pull llama3.1
        ollama serve

Run:
    python app.py
"""

from __future__ import annotations

import ast
import contextlib
import dataclasses
import datetime as dt
import json
import os
import queue
import sqlite3
import subprocess
import sys
import threading
import traceback
import urllib.error
import urllib.request
from pathlib import Path
from tkinter import Tk, StringVar, BooleanVar, IntVar, Menu, END, BOTH, LEFT, RIGHT, X, Y, VERTICAL, HORIZONTAL, filedialog, messagebox
from tkinter import ttk
from tkinter.scrolledtext import ScrolledText
from typing import Any, Iterable

APP_NAME = "Python Code Analyzer Manager"
DB_PATH = Path(__file__).with_name("code_analyzer_manager.sqlite3")
RUNS_DIR = Path(__file__).with_name("runs")
RUNS_DIR.mkdir(exist_ok=True)


@dataclasses.dataclass(slots=True)
class AnalysisResult:
    project_name: str
    root_path: str
    files: list[dict[str, Any]]
    objects: list[dict[str, Any]]
    imports: list[dict[str, Any]]
    hotkeys: list[dict[str, Any]]
    workflows: list[dict[str, Any]]
    database_elements: list[dict[str, Any]]
    commands: list[str]
    overview: str
    demo_script: str
    next_steps: str
    generated_at: str


class Database:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.connection = sqlite3.connect(self.path)
        self.connection.row_factory = sqlite3.Row
        self.connection.execute("PRAGMA foreign_keys = ON")
        self.initialize()

    def initialize(self) -> None:
        schema = """
        CREATE TABLE IF NOT EXISTS projects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            root_path TEXT NOT NULL UNIQUE,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            notes TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS source_files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            relative_path TEXT NOT NULL,
            absolute_path TEXT NOT NULL,
            language TEXT NOT NULL DEFAULT 'python',
            content TEXT NOT NULL,
            sha_hint TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(project_id, relative_path)
        );
        CREATE TABLE IF NOT EXISTS analysis_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            summary TEXT NOT NULL,
            json_payload TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS objects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            file_path TEXT NOT NULL,
            object_type TEXT NOT NULL,
            name TEXT NOT NULL,
            line INTEGER NOT NULL DEFAULT 0,
            signature TEXT NOT NULL DEFAULT '',
            docstring TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS commands (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            label TEXT NOT NULL,
            command TEXT NOT NULL,
            working_dir TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS hotkeys (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            binding TEXT NOT NULL,
            action TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS workflows (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            steps_json TEXT NOT NULL,
            notes TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS llm_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
        self.connection.executescript(schema)
        self.connection.commit()
        self.seed_defaults()

    def seed_defaults(self) -> None:
        now = utc_now()
        defaults = [
            ("Analyze Project", "<Control-r>", "analyze_project"),
            ("Run Selected File", "<F5>", "run_selected_file"),
            ("Open Project", "<Control-o>", "open_project"),
            ("Save Notes", "<Control-s>", "save_notes"),
            ("Toggle Fullscreen", "<F11>", "toggle_fullscreen"),
        ]
        existing = self.scalar("SELECT COUNT(*) FROM hotkeys WHERE project_id IS NULL")
        if existing == 0:
            self.connection.executemany(
                "INSERT INTO hotkeys(project_id,name,binding,action,enabled,created_at) VALUES(NULL,?,?,?,?,?)",
                [(name, binding, action, 1, now) for name, binding, action in defaults],
            )
            self.connection.commit()
        self.execute("INSERT OR IGNORE INTO settings(key,value) VALUES('ollama_url','http://localhost:11434/api/generate')")
        self.execute("INSERT OR IGNORE INTO settings(key,value) VALUES('ollama_model','llama3.1')")
        self.execute("INSERT OR IGNORE INTO settings(key,value) VALUES('theme','clam')")
        self.connection.commit()

    def execute(self, sql: str, params: Iterable[Any] = ()) -> sqlite3.Cursor:
        cur = self.connection.execute(sql, tuple(params))
        self.connection.commit()
        return cur

    def many(self, sql: str, params: Iterable[Any] = ()) -> list[sqlite3.Row]:
        return list(self.connection.execute(sql, tuple(params)).fetchall())

    def one(self, sql: str, params: Iterable[Any] = ()) -> sqlite3.Row | None:
        return self.connection.execute(sql, tuple(params)).fetchone()

    def scalar(self, sql: str, params: Iterable[Any] = ()) -> Any:
        row = self.connection.execute(sql, tuple(params)).fetchone()
        return None if row is None else row[0]

    def upsert_project(self, root: Path) -> int:
        now = utc_now()
        name = root.name or str(root)
        existing = self.one("SELECT id FROM projects WHERE root_path=?", (str(root),))
        if existing:
            self.execute("UPDATE projects SET name=?, updated_at=? WHERE id=?", (name, now, existing["id"]))
            return int(existing["id"])
        cur = self.execute(
            "INSERT INTO projects(name,root_path,created_at,updated_at) VALUES(?,?,?,?)",
            (name, str(root), now, now),
        )
        return int(cur.lastrowid)

    def set_setting(self, key: str, value: str) -> None:
        self.execute("INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, value))

    def get_setting(self, key: str, default: str = "") -> str:
        value = self.scalar("SELECT value FROM settings WHERE key=?", (key,))
        return default if value is None else str(value)


def utc_now() -> str:
    return dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat()


def safe_read(path: Path) -> str:
    for encoding in ("utf-8", "utf-8-sig", "cp1252", "latin-1"):
        with contextlib.suppress(Exception):
            return path.read_text(encoding=encoding)
    return ""


def function_signature(node: ast.FunctionDef | ast.AsyncFunctionDef) -> str:
    args = []
    for arg in node.args.posonlyargs + node.args.args:
        args.append(arg.arg)
    if node.args.vararg:
        args.append("*" + node.args.vararg.arg)
    for arg in node.args.kwonlyargs:
        args.append(arg.arg)
    if node.args.kwarg:
        args.append("**" + node.args.kwarg.arg)
    return f"{node.name}({', '.join(args)})"


class CodeAnalyzer:
    def __init__(self, db: Database) -> None:
        self.db = db

    def analyze_project(self, root: Path) -> AnalysisResult:
        project_id = self.db.upsert_project(root)
        now = utc_now()
        self.db.execute("DELETE FROM source_files WHERE project_id=?", (project_id,))
        self.db.execute("DELETE FROM objects WHERE project_id=?", (project_id,))
        py_files = [p for p in root.rglob("*.py") if self._should_include(p)]
        files: list[dict[str, Any]] = []
        objects: list[dict[str, Any]] = []
        imports: list[dict[str, Any]] = []
        hotkeys: list[dict[str, Any]] = []
        workflows: list[dict[str, Any]] = []
        db_elements: list[dict[str, Any]] = []

        for path in sorted(py_files):
            rel = str(path.relative_to(root))
            content = safe_read(path)
            self.db.execute(
                "INSERT INTO source_files(project_id,relative_path,absolute_path,content,created_at,updated_at) VALUES(?,?,?,?,?,?)",
                (project_id, rel, str(path), content, now, now),
            )
            file_record = {"path": rel, "lines": content.count("\n") + 1, "characters": len(content)}
            try:
                tree = ast.parse(content, filename=rel)
                file_record["parse_status"] = "ok"
                parsed = self._parse_tree(project_id, rel, tree, content)
                objects.extend(parsed["objects"])
                imports.extend(parsed["imports"])
                hotkeys.extend(parsed["hotkeys"])
                workflows.extend(parsed["workflows"])
                db_elements.extend(parsed["database_elements"])
            except SyntaxError as exc:
                file_record["parse_status"] = f"syntax error: line {exc.lineno}: {exc.msg}"
            files.append(file_record)

        commands = self._infer_commands(root, files, imports)
        overview = self._build_overview(root, files, objects, imports, db_elements, hotkeys, workflows)
        demo_script = self._build_demo_script(root, files, objects, commands, workflows)
        next_steps = self._build_next_steps(files, objects, db_elements, hotkeys)
        result = AnalysisResult(
            project_name=root.name,
            root_path=str(root),
            files=files,
            objects=objects,
            imports=imports,
            hotkeys=hotkeys,
            workflows=workflows,
            database_elements=db_elements,
            commands=commands,
            overview=overview,
            demo_script=demo_script,
            next_steps=next_steps,
            generated_at=now,
        )
        self.db.execute(
            "INSERT INTO analysis_runs(project_id,summary,json_payload,created_at) VALUES(?,?,?,?)",
            (project_id, overview[:4000], json.dumps(dataclasses.asdict(result), indent=2), now),
        )
        self._store_default_commands(project_id, root, commands)
        return result

    def _should_include(self, path: Path) -> bool:
        blocked = {".venv", "venv", "env", "__pycache__", ".git", "node_modules", "build", "dist"}
        return not any(part in blocked for part in path.parts)

    def _parse_tree(self, project_id: int, rel: str, tree: ast.AST, content: str) -> dict[str, list[dict[str, Any]]]:
        objects: list[dict[str, Any]] = []
        imports: list[dict[str, Any]] = []
        hotkeys: list[dict[str, Any]] = []
        workflows: list[dict[str, Any]] = []
        database_elements: list[dict[str, Any]] = []
        lines = content.splitlines()

        for node in ast.walk(tree):
            if isinstance(node, ast.ClassDef):
                item = {
                    "file": rel,
                    "type": "class",
                    "name": node.name,
                    "line": node.lineno,
                    "signature": node.name,
                    "docstring": ast.get_docstring(node) or "",
                    "methods": [n.name for n in node.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))],
                }
                objects.append(item)
                self._insert_object(project_id, item)
            elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                item = {
                    "file": rel,
                    "type": "async_function" if isinstance(node, ast.AsyncFunctionDef) else "function",
                    "name": node.name,
                    "line": node.lineno,
                    "signature": function_signature(node),
                    "docstring": ast.get_docstring(node) or "",
                }
                objects.append(item)
                self._insert_object(project_id, item)
                lname = node.name.lower()
                if any(word in lname for word in ("run", "execute", "process", "pipeline", "workflow", "analyze", "load", "save")):
                    workflows.append({"file": rel, "name": node.name, "line": node.lineno, "reason": "name suggests workflow/control flow"})
            elif isinstance(node, ast.Import):
                for alias in node.names:
                    imports.append({"file": rel, "module": alias.name, "line": node.lineno})
            elif isinstance(node, ast.ImportFrom):
                imports.append({"file": rel, "module": node.module or "", "line": node.lineno})
            elif isinstance(node, ast.Call):
                call_text = ast.get_source_segment(content, node) or ""
                lowered = call_text.lower()
                if ".bind(" in lowered or "keyboard" in lowered or "hotkey" in lowered:
                    hotkeys.append({"file": rel, "line": getattr(node, "lineno", 0), "snippet": call_text[:240]})
                if any(term in lowered for term in ("sqlite3.connect", "create table", "sqlalchemy", "cursor.execute", ".execute(")):
                    database_elements.append({"file": rel, "line": getattr(node, "lineno", 0), "snippet": call_text[:300]})
        for index, line in enumerate(lines, start=1):
            low = line.lower()
            if "create table" in low or "foreign key" in low or "primary key" in low:
                database_elements.append({"file": rel, "line": index, "snippet": line.strip()[:300]})
        return {"objects": objects, "imports": imports, "hotkeys": hotkeys, "workflows": workflows, "database_elements": database_elements}

    def _insert_object(self, project_id: int, item: dict[str, Any]) -> None:
        self.db.execute(
            "INSERT INTO objects(project_id,file_path,object_type,name,line,signature,docstring) VALUES(?,?,?,?,?,?,?)",
            (project_id, item["file"], item["type"], item["name"], item["line"], item["signature"], item["docstring"]),
        )

    def _infer_commands(self, root: Path, files: list[dict[str, Any]], imports: list[dict[str, Any]]) -> list[str]:
        commands = ["python --version", "python -m venv .venv"]
        if os.name == "nt":
            commands.append(r".venv\Scripts\activate")
        else:
            commands.append("source .venv/bin/activate")
        req = root / "requirements.txt"
        pyproject = root / "pyproject.toml"
        if req.exists():
            commands.append("python -m pip install -r requirements.txt")
        elif pyproject.exists():
            commands.append("python -m pip install -e .")
        else:
            third_party = sorted({i["module"].split(".")[0] for i in imports if i["module"].split(".")[0] not in sys.stdlib_module_names})
            if third_party:
                commands.append("python -m pip install " + " ".join(third_party[:20]))
        candidates = [f["path"] for f in files if Path(f["path"]).name in ("app.py", "main.py", "run.py")]
        if candidates:
            commands.append(f"python {candidates[0]}")
        else:
            commands.append("python path/to/entry_file.py")
        commands.extend(["python -m compileall .", "python -m unittest discover -v"])
        return commands

    def _store_default_commands(self, project_id: int, root: Path, commands: list[str]) -> None:
        self.db.execute("DELETE FROM commands WHERE project_id=?", (project_id,))
        for index, command in enumerate(commands, start=1):
            self.db.execute(
                "INSERT INTO commands(project_id,label,command,working_dir,created_at) VALUES(?,?,?,?,?)",
                (project_id, f"Command {index}", command, str(root), utc_now()),
            )

    def _build_overview(self, root: Path, files: list[dict[str, Any]], objects: list[dict[str, Any]], imports: list[dict[str, Any]], db_elements: list[dict[str, Any]], hotkeys: list[dict[str, Any]], workflows: list[dict[str, Any]]) -> str:
        classes = [o for o in objects if o["type"] == "class"]
        functions = [o for o in objects if "function" in o["type"]]
        modules = sorted({i["module"].split(".")[0] for i in imports if i["module"]})
        return (
            f"Project: {root.name}\n"
            f"Files analyzed: {len(files)}\n"
            f"Classes found: {len(classes)}\n"
            f"Functions/methods found: {len(functions)}\n"
            f"Imports used: {', '.join(modules[:40]) if modules else 'none detected'}\n"
            f"Hotkey/UI bindings detected: {len(hotkeys)}\n"
            f"Workflow-like functions detected: {len(workflows)}\n"
            f"Database-related elements detected: {len(db_elements)}\n\n"
            "Mechanism overview:\n"
            "1. Entry files start the app or script.\n"
            "2. Imports show external dependencies and standard-library mechanisms.\n"
            "3. Classes define durable objects and state containers.\n"
            "4. Functions define actions, transformations, workflows, and command handlers.\n"
            "5. Database elements define the persistent data picture.\n"
            "6. Hotkeys and menus expose user-facing control paths.\n"
        )

    def _build_demo_script(self, root: Path, files: list[dict[str, Any]], objects: list[dict[str, Any]], commands: list[str], workflows: list[dict[str, Any]]) -> str:
        important = objects[:20]
        workflow_lines = [f"- {w['name']} in {w['file']} line {w['line']}: {w['reason']}" for w in workflows[:20]]
        object_lines = [f"- {o['type']} {o['signature']} in {o['file']} line {o['line']}" for o in important]
        command_lines = [f"    {c}" for c in commands]
        return (
            f"DEMONSTRATION SCRIPT FOR {root.name}\n\n"
            "1. Explain the goal of the project in one sentence.\n"
            "2. Show the project root and point out the main Python entry file.\n"
            "3. Run the setup commands:\n" + "\n".join(command_lines) + "\n\n"
            "4. Walk through the important objects:\n" + ("\n".join(object_lines) if object_lines else "- No objects detected.") + "\n\n"
            "5. Walk through workflow functions:\n" + ("\n".join(workflow_lines) if workflow_lines else "- No workflow-like functions detected.") + "\n\n"
            "6. Run the app/script and narrate what changes on screen, in files, or in the database.\n"
            "7. Show the next extension phase and explain how a beginner can modify one safe function first.\n"
        )

    def _build_next_steps(self, files: list[dict[str, Any]], objects: list[dict[str, Any]], db_elements: list[dict[str, Any]], hotkeys: list[dict[str, Any]]) -> str:
        steps = [
            "Add or improve README setup instructions.",
            "Add tests around the most important workflow functions.",
            "Create a clear app entry point if none exists.",
            "Add comments/docstrings to objects that have no documentation.",
        ]
        if db_elements:
            steps.append("Generate an ERD-style database map from detected tables and SQL calls.")
        if hotkeys:
            steps.append("Document all hotkeys in a help menu and allow rebinding from the GUI.")
        if len(files) > 20:
            steps.append("Add package-level diagrams so beginners can understand the architecture by folder.")
        return "\n".join(f"- {s}" for s in steps)


class OllamaClient:
    def __init__(self, db: Database) -> None:
        self.db = db

    def generate(self, prompt: str, system: str = "You are a strict senior Python code reviewer.") -> str:
        url = self.db.get_setting("ollama_url", "http://localhost:11434/api/generate")
        model = self.db.get_setting("ollama_model", "llama3.1")
        payload = json.dumps({"model": model, "system": system, "prompt": prompt, "stream": False}).encode("utf-8")
        req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"}, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=120) as response:
                data = json.loads(response.read().decode("utf-8"))
                return str(data.get("response", "")).strip()
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            return f"Ollama unavailable or returned invalid data: {exc}\n\nInstall/start Ollama or change Settings > Ollama URL/model."

    def self_review(self, analysis: AnalysisResult, rounds: int = 2) -> str:
        current = json.dumps(dataclasses.asdict(analysis), indent=2)[:16000]
        transcript: list[str] = []
        for round_index in range(1, rounds + 1):
            prompt = (
                "Review this Python project analysis. Find missing insights, risk areas, beginner explanations, "
                "database/data-picture improvements, setup command gaps, and next extension phases. "
                "Return concise actionable findings.\n\n"
                f"ROUND {round_index}\n{current}"
            )
            response = self.generate(prompt)
            transcript.append(f"===== LLM SELF-REVIEW ROUND {round_index} =====\n{response}")
            current = response
        return "\n\n".join(transcript)


class SortableTable(ttk.Frame):
    def __init__(self, master: Any, columns: list[str], headings: list[str] | None = None) -> None:
        super().__init__(master)
        self.columns = columns
        self.sort_reverse: dict[str, bool] = {}
        self.tree = ttk.Treeview(self, columns=columns, show="headings")
        self.vsb = ttk.Scrollbar(self, orient=VERTICAL, command=self.tree.yview)
        self.hsb = ttk.Scrollbar(self, orient=HORIZONTAL, command=self.tree.xview)
        self.tree.configure(yscrollcommand=self.vsb.set, xscrollcommand=self.hsb.set)
        self.tree.grid(row=0, column=0, sticky="nsew")
        self.vsb.grid(row=0, column=1, sticky="ns")
        self.hsb.grid(row=1, column=0, sticky="ew")
        self.grid_rowconfigure(0, weight=1)
        self.grid_columnconfigure(0, weight=1)
        for col, heading in zip(columns, headings or columns, strict=False):
            self.tree.heading(col, text=heading, command=lambda c=col: self.sort_by(c))
            self.tree.column(col, width=180, minwidth=80, stretch=True)
        self.menu = Menu(self, tearoff=False)
        self.menu.add_command(label="Copy selected row", command=self.copy_selected)
        self.menu.add_command(label="Delete selected row from view", command=self.delete_selected_from_view)
        self.tree.bind("<Button-3>", self.show_menu)

    def set_rows(self, rows: list[dict[str, Any]]) -> None:
        self.tree.delete(*self.tree.get_children())
        for row in rows:
            values = [str(row.get(col, "")) for col in self.columns]
            self.tree.insert("", END, values=values)

    def sort_by(self, column: str) -> None:
        items = [(self.tree.set(item, column), item) for item in self.tree.get_children("")]
        reverse = self.sort_reverse.get(column, False)
        def key(value: tuple[str, str]) -> Any:
            text = value[0]
            with contextlib.suppress(ValueError):
                return float(text)
            return text.lower()
        for index, (_, item) in enumerate(sorted(items, key=key, reverse=reverse)):
            self.tree.move(item, "", index)
        self.sort_reverse[column] = not reverse

    def selected_values(self) -> list[str]:
        selected = self.tree.selection()
        if not selected:
            return []
        return list(self.tree.item(selected[0], "values"))

    def show_menu(self, event: Any) -> None:
        iid = self.tree.identify_row(event.y)
        if iid:
            self.tree.selection_set(iid)
        self.menu.tk_popup(event.x_root, event.y_root)

    def copy_selected(self) -> None:
        values = self.selected_values()
        if values:
            self.clipboard_clear()
            self.clipboard_append("\t".join(values))

    def delete_selected_from_view(self) -> None:
        for item in self.tree.selection():
            self.tree.delete(item)


class App(Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(APP_NAME)
        self.geometry("1500x900")
        self.minsize(1000, 650)
        self.db = Database(DB_PATH)
        self.analyzer = CodeAnalyzer(self.db)
        self.ollama = OllamaClient(self.db)
        self.project_id: int | None = None
        self.project_root: Path | None = None
        self.current_analysis: AnalysisResult | None = None
        self.output_queue: queue.Queue[str] = queue.Queue()
        self.fullscreen = BooleanVar(value=False)
        self.status = StringVar(value="Ready")
        self.ollama_model = StringVar(value=self.db.get_setting("ollama_model", "llama3.1"))
        self.ollama_url = StringVar(value=self.db.get_setting("ollama_url", "http://localhost:11434/api/generate"))
        self._configure_style()
        self._build_menu()
        self._build_layout()
        self._bind_hotkeys()
        self.after(200, self._drain_output_queue)

    def _configure_style(self) -> None:
        style = ttk.Style(self)
        with contextlib.suppress(Exception):
            style.theme_use(self.db.get_setting("theme", "clam"))
        style.configure("Treeview", rowheight=28)
        style.configure("TButton", padding=6)
        style.configure("TLabel", padding=3)

    def _build_menu(self) -> None:
        menubar = Menu(self)
        file_menu = Menu(menubar, tearoff=False)
        file_menu.add_command(label="Open Project Folder", command=self.open_project)
        file_menu.add_command(label="Analyze Project", command=self.analyze_project)
        file_menu.add_separator()
        file_menu.add_command(label="Exit", command=self.destroy)
        menubar.add_cascade(label="File", menu=file_menu)
        run_menu = Menu(menubar, tearoff=False)
        run_menu.add_command(label="Run Selected File", command=self.run_selected_file)
        run_menu.add_command(label="Run Custom Command", command=self.run_custom_command)
        menubar.add_cascade(label="Run", menu=run_menu)
        ai_menu = Menu(menubar, tearoff=False)
        ai_menu.add_command(label="LLM Self Review", command=self.llm_self_review)
        ai_menu.add_command(label="Save Ollama Settings", command=self.save_ollama_settings)
        menubar.add_cascade(label="AI", menu=ai_menu)
        view_menu = Menu(menubar, tearoff=False)
        view_menu.add_command(label="Toggle Fullscreen", command=self.toggle_fullscreen)
        menubar.add_cascade(label="View", menu=view_menu)
        self.config(menu=menubar)

    def _build_layout(self) -> None:
        root = ttk.Frame(self)
        root.pack(fill=BOTH, expand=True)
        toolbar = ttk.Frame(root)
        toolbar.pack(fill=X, padx=8, pady=6)
        ttk.Button(toolbar, text="Open Project", command=self.open_project).pack(side=LEFT, padx=3)
        ttk.Button(toolbar, text="Analyze", command=self.analyze_project).pack(side=LEFT, padx=3)
        ttk.Button(toolbar, text="Run File", command=self.run_selected_file).pack(side=LEFT, padx=3)
        ttk.Button(toolbar, text="LLM Self Review", command=self.llm_self_review).pack(side=LEFT, padx=3)
        ttk.Label(toolbar, text="Ollama Model").pack(side=LEFT, padx=(18, 3))
        ttk.Entry(toolbar, textvariable=self.ollama_model, width=16).pack(side=LEFT)
        ttk.Label(toolbar, text="URL").pack(side=LEFT, padx=(10, 3))
        ttk.Entry(toolbar, textvariable=self.ollama_url, width=42).pack(side=LEFT)
        ttk.Button(toolbar, text="Save", command=self.save_ollama_settings).pack(side=LEFT, padx=3)

        main = ttk.PanedWindow(root, orient=HORIZONTAL)
        main.pack(fill=BOTH, expand=True, padx=8, pady=4)
        left = ttk.Frame(main)
        right = ttk.Frame(main)
        main.add(left, weight=1)
        main.add(right, weight=3)

        self.file_table = SortableTable(left, ["path", "lines", "parse_status"], ["File", "Lines", "Status"])
        self.file_table.pack(fill=BOTH, expand=True)
        self.file_table.tree.bind("<<TreeviewSelect>>", lambda _e: self.load_selected_file())

        self.tabs = ttk.Notebook(right)
        self.tabs.pack(fill=BOTH, expand=True)
        self.source_text = self._add_text_tab("Source")
        self.overview_text = self._add_text_tab("Overview")
        self.demo_text = self._add_text_tab("Demo Script")
        self.next_text = self._add_text_tab("Next Steps")
        self.console_text = self._add_text_tab("Runner Console")
        self.llm_text = self._add_text_tab("LLM Insights")

        self.objects_table = SortableTable(self.tabs, ["type", "name", "file", "line", "signature"], ["Type", "Name", "File", "Line", "Signature"])
        self.tabs.add(self.objects_table, text="Objects")
        self.db_table = SortableTable(self.tabs, ["file", "line", "snippet"], ["File", "Line", "Database Snippet"])
        self.tabs.add(self.db_table, text="Data Picture")
        self.hotkey_table = SortableTable(self.tabs, ["name", "binding", "action", "enabled"], ["Name", "Binding", "Action", "Enabled"])
        self.tabs.add(self.hotkey_table, text="Hotkeys")
        self.command_table = SortableTable(self.tabs, ["label", "command", "working_dir"], ["Label", "Command", "Working Dir"])
        self.tabs.add(self.command_table, text="Commands")

        bottom = ttk.Frame(root)
        bottom.pack(fill=X, padx=8, pady=4)
        ttk.Label(bottom, textvariable=self.status).pack(side=LEFT)

    def _add_text_tab(self, title: str) -> ScrolledText:
        frame = ttk.Frame(self.tabs)
        text = ScrolledText(frame, wrap="word", undo=True, font=("Consolas", 11))
        text.pack(fill=BOTH, expand=True)
        self.tabs.add(frame, text=title)
        menu = Menu(text, tearoff=False)
        menu.add_command(label="Copy", command=lambda t=text: t.event_generate("<<Copy>>"))
        menu.add_command(label="Select All", command=lambda t=text: (t.tag_add("sel", "1.0", END), t.focus_set()))
        menu.add_command(label="Clear", command=lambda t=text: (t.delete("1.0", END)))
        text.bind("<Button-3>", lambda event, m=menu: m.tk_popup(event.x_root, event.y_root))
        return text

    def _bind_hotkeys(self) -> None:
        action_map = {
            "analyze_project": self.analyze_project,
            "run_selected_file": self.run_selected_file,
            "open_project": self.open_project,
            "save_notes": self.save_notes,
            "toggle_fullscreen": self.toggle_fullscreen,
        }
        for row in self.db.many("SELECT * FROM hotkeys WHERE enabled=1"):
            action = action_map.get(row["action"])
            if action:
                self.bind_all(row["binding"], lambda _e, a=action: a())

    def open_project(self) -> None:
        folder = filedialog.askdirectory(title="Select Python project folder")
        if not folder:
            return
        self.project_root = Path(folder)
        self.project_id = self.db.upsert_project(self.project_root)
        self.status.set(f"Opened: {self.project_root}")
        self.analyze_project()

    def analyze_project(self) -> None:
        if self.project_root is None:
            folder = filedialog.askdirectory(title="Select Python project folder")
            if not folder:
                return
            self.project_root = Path(folder)
            self.project_id = self.db.upsert_project(self.project_root)
        self.status.set("Analyzing project...")
        threading.Thread(target=self._analyze_worker, daemon=True).start()

    def _analyze_worker(self) -> None:
        assert self.project_root is not None
        try:
            result = self.analyzer.analyze_project(self.project_root)
            self.current_analysis = result
            self.output_queue.put("__ANALYSIS_DONE__")
        except Exception:
            self.output_queue.put(traceback.format_exc())

    def _render_analysis(self) -> None:
        result = self.current_analysis
        if result is None:
            return
        self.file_table.set_rows(result.files)
        self.objects_table.set_rows(result.objects)
        self.db_table.set_rows(result.database_elements)
        self.overview_text.delete("1.0", END)
        self.overview_text.insert(END, result.overview)
        self.demo_text.delete("1.0", END)
        self.demo_text.insert(END, result.demo_script)
        self.next_text.delete("1.0", END)
        self.next_text.insert(END, result.next_steps)
        commands = self.db.many("SELECT label, command, working_dir FROM commands WHERE project_id=?", (self.project_id,)) if self.project_id else []
        self.command_table.set_rows([dict(row) for row in commands])
        hotkeys = self.db.many("SELECT name,binding,action,enabled FROM hotkeys")
        self.hotkey_table.set_rows([dict(row) for row in hotkeys])
        self.status.set(f"Analysis complete: {len(result.files)} files, {len(result.objects)} objects")

    def load_selected_file(self) -> None:
        if self.project_root is None:
            return
        values = self.file_table.selected_values()
        if not values:
            return
        path = self.project_root / values[0]
        self.source_text.delete("1.0", END)
        self.source_text.insert(END, safe_read(path))
        self.tabs.select(0)

    def run_selected_file(self) -> None:
        if self.project_root is None:
            messagebox.showwarning(APP_NAME, "Open a project first.")
            return
        values = self.file_table.selected_values()
        if not values:
            messagebox.showwarning(APP_NAME, "Select a Python file first.")
            return
        path = self.project_root / values[0]
        self._run_command([sys.executable, str(path)], cwd=self.project_root)

    def run_custom_command(self) -> None:
        if self.project_root is None:
            messagebox.showwarning(APP_NAME, "Open a project first.")
            return
        values = self.command_table.selected_values()
        if not values:
            messagebox.showwarning(APP_NAME, "Select a command from the Commands tab.")
            return
        self._run_command(values[1], cwd=Path(values[2] or self.project_root), shell=True)

    def _run_command(self, command: str | list[str], cwd: Path, shell: bool = False) -> None:
        self.console_text.delete("1.0", END)
        self.console_text.insert(END, f"Running: {command}\nWorking dir: {cwd}\n\n")
        self.tabs.select(self.console_text.master)
        threading.Thread(target=self._run_worker, args=(command, cwd, shell), daemon=True).start()

    def _run_worker(self, command: str | list[str], cwd: Path, shell: bool) -> None:
        try:
            process = subprocess.Popen(command, cwd=str(cwd), shell=shell, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            assert process.stdout is not None
            for line in process.stdout:
                self.output_queue.put(line)
            process.wait()
            self.output_queue.put(f"\nProcess exited with code {process.returncode}\n")
        except Exception:
            self.output_queue.put(traceback.format_exc())

    def llm_self_review(self) -> None:
        if self.current_analysis is None:
            messagebox.showwarning(APP_NAME, "Analyze a project first.")
            return
        self.save_ollama_settings()
        self.llm_text.delete("1.0", END)
        self.llm_text.insert(END, "Starting local Ollama self-review...\n")
        self.tabs.select(self.llm_text.master)
        threading.Thread(target=self._llm_worker, daemon=True).start()

    def _llm_worker(self) -> None:
        assert self.current_analysis is not None
        response = self.ollama.self_review(self.current_analysis, rounds=2)
        self.output_queue.put("__LLM_DONE__" + response)

    def save_ollama_settings(self) -> None:
        self.db.set_setting("ollama_model", self.ollama_model.get().strip() or "llama3.1")
        self.db.set_setting("ollama_url", self.ollama_url.get().strip() or "http://localhost:11434/api/generate")
        self.status.set("Saved Ollama settings")

    def save_notes(self) -> None:
        self.status.set("Notes are saved automatically in analysis/database records.")

    def toggle_fullscreen(self) -> None:
        self.fullscreen.set(not self.fullscreen.get())
        self.attributes("-fullscreen", self.fullscreen.get())

    def _drain_output_queue(self) -> None:
        try:
            while True:
                text = self.output_queue.get_nowait()
                if text == "__ANALYSIS_DONE__":
                    self._render_analysis()
                elif text.startswith("__LLM_DONE__"):
                    self.llm_text.delete("1.0", END)
                    self.llm_text.insert(END, text.replace("__LLM_DONE__", "", 1))
                    self.status.set("LLM self-review complete")
                else:
                    self.console_text.insert(END, text)
                    self.console_text.see(END)
        except queue.Empty:
            pass
        self.after(200, self._drain_output_queue)


def main() -> None:
    app = App()
    app.mainloop()


if __name__ == "__main__":
    main()
