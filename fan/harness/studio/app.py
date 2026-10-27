"""Harness Studio -- one window over the whole system.

Every capability that used to live in a separate script is a tab here: the context map,
the symbol index, the write gate, ingestion, condensing, the ledger, the legacy harness
launchers, and the LLM export.
"""

from __future__ import annotations

import sys
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, ttk

if __package__ in (None, ""):  # allow `python studio/app.py`
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from atlas.store import Store
from studio.widgets import UI, UI_BOLD, Job

TABS = [
    ("guide", "Guide", "What this is, how it works, how to use it"),
    ("automation", "Learning & Automation", "Live automater targets, retained evidence and reusable tools"),
    ("atlas", "Atlas", "Buckets, projects, sweep and classification"),
    ("index", "Index", "Symbol browser, slices, call edges, impact"),
    ("gate", "Write Gate", "Dedupe, budget and placement before you add code"),
    ("create", "Create", "New projects, new symbols, paste code, absorb a project"),
    ("ingest", "Ingest", "Hot folder, ZIPs, mass documents, fan-out and run"),
    ("condense", "Condense", "Collapse projects into classes.py and functions.py"),
    ("coagulate", "Coagulate", "Reconcile duplicate project folders; find duplicated code"),
    ("ledger", "Ledger", "History, backups, restore and the attic"),
    ("harness", "Harness", "Run your absorbed tools and the built-in launchers"),
    ("export", "Export", "ATLAS.md, INDEX.md, LLM_GUIDE.md and token budgets"),
]


class Context:
    """Everything the tabs share: the store, the workspace, and UI callbacks."""

    def __init__(self, app: "StudioApp") -> None:
        self.app = app
        self.store: Store = app.store
        self.workspace: Path = app.workspace
        self.job: Job = app.job

    def status(self, message: str, kind: str = "info") -> None:
        self.app.set_status(message, kind)

    def refresh_counts(self) -> None:
        self.app.refresh_counts()

    def goto(self, tab_key: str) -> None:
        self.app.select_tab(tab_key)

    def broadcast(self, event: str) -> None:
        """Tell every tab that shared state changed (a new index, a new project)."""
        for tab in self.app.tabs.values():
            handler = getattr(tab, "on_" + event, None)
            if handler:
                try:
                    handler()
                except Exception as exc:
                    print(f"[{tab.__class__.__name__}] {event}: {exc}", file=sys.stderr)


class StudioApp(tk.Tk):
    def __init__(self, workspace: Path) -> None:
        super().__init__()
        self.workspace = Path(workspace).resolve()
        self.store = Store(self.workspace)
        self.title(f"Harness Studio  --  {self.workspace}")
        self._fit_to_screen()
        self.minsize(1000, 640)

        self._fullscreen = False
        self.job = Job(self)
        self.context = Context(self)
        self.tabs: dict[str, object] = {}

        self._configure_style()
        self._build_menu()
        self._build_layout()
        self._bind_keys()

        self.protocol("WM_DELETE_WINDOW", self._on_close)
        self.after(120, self._first_load)

    # ------------------------------------------------------------------- chrome
    def _fit_to_screen(self) -> None:
        """Open as large as the display allows, without running off it.

        A fixed 1680x1000 pushed the bottom panes under the taskbar on smaller
        screens, which hid the edges pane -- the one thing this tool is for.
        """
        screen_w = self.winfo_screenwidth()
        screen_h = self.winfo_screenheight()
        width = min(1720, max(1000, screen_w - 80))
        height = min(1040, max(640, screen_h - 120))
        x = max(0, (screen_w - width) // 2)
        y = max(0, (screen_h - height) // 3)
        self.geometry(f"{width}x{height}+{x}+{y}")

    def _configure_style(self) -> None:
        style = ttk.Style(self)
        for candidate in ("vista", "clam", "default"):
            if candidate in style.theme_names():
                style.theme_use(candidate)
                break
        style.configure("Treeview", rowheight=19, font=("Consolas", 9))
        style.configure("Treeview.Heading", font=UI_BOLD)
        style.configure("TNotebook.Tab", padding=(14, 6), font=UI)
        style.configure("Status.TLabel", font=("Consolas", 9))
        style.configure("Head.TLabel", font=("Segoe UI", 11, "bold"))

    def _build_menu(self) -> None:
        menubar = tk.Menu(self)

        file_menu = tk.Menu(menubar, tearoff=0)
        file_menu.add_command(label="Open workspace folder", command=self._open_workspace)
        file_menu.add_command(label="Export LLM pack\tCtrl+E",
                              command=lambda: self.select_tab("export"))
        file_menu.add_separator()
        file_menu.add_command(label="Quit", command=self._on_close)
        menubar.add_cascade(label="File", menu=file_menu)

        view_menu = tk.Menu(menubar, tearoff=0)
        view_menu.add_command(label="Fullscreen\tF11", command=self.toggle_fullscreen)
        view_menu.add_separator()
        for key, label, _blurb in TABS:
            view_menu.add_command(label=label, command=lambda k=key: self.select_tab(k))
        menubar.add_cascade(label="View", menu=view_menu)

        help_menu = tk.Menu(menubar, tearoff=0)
        help_menu.add_command(label="Context Map spec", command=self._show_spec)
        help_menu.add_command(label="Keyboard shortcuts", command=self._show_keys)
        menubar.add_cascade(label="Help", menu=help_menu)

        self.configure(menu=menubar)

    def _build_layout(self) -> None:
        header = ttk.Frame(self, padding=(10, 6, 10, 2))
        header.pack(side=tk.TOP, fill=tk.X)
        ttk.Label(header, text="HARNESS STUDIO", style="Head.TLabel").pack(side=tk.LEFT)
        self.counts_var = tk.StringVar(value="loading ...")
        ttk.Label(header, textvariable=self.counts_var,
                  font=("Consolas", 9), foreground="#4a4a4a").pack(side=tk.LEFT, padx=16)
        self.hint_var = tk.StringVar(value="")
        ttk.Label(header, textvariable=self.hint_var, font=UI,
                  foreground="#6a6a6a").pack(side=tk.RIGHT)

        self.notebook = ttk.Notebook(self)
        self.notebook.pack(side=tk.TOP, fill=tk.BOTH, expand=True, padx=6, pady=(2, 0))
        self.notebook.bind("<<NotebookTabChanged>>", self._tab_changed)

        status = ttk.Frame(self, padding=(8, 3))
        status.pack(side=tk.BOTTOM, fill=tk.X)
        self.status_var = tk.StringVar(value="Ready")
        self.status_label = ttk.Label(status, textvariable=self.status_var,
                                      style="Status.TLabel")
        self.status_label.pack(side=tk.LEFT)
        self.progress = ttk.Progressbar(status, mode="indeterminate", length=160)
        self.progress.pack(side=tk.RIGHT)

        self._build_tabs()

    def _build_tabs(self) -> None:
        from studio.tabs import (
            atlas_tab, coagulate_tab, condense_tab, create_tab, export_tab,
            gate_tab, guide_tab, harness_tab, index_tab, ingest_tab, ledger_tab,
        )

        builders = {
            "guide": guide_tab.GuideTab,
            "automation": gate_tab.AutomationTab,
            "atlas": atlas_tab.AtlasTab,
            "index": index_tab.IndexTab,
            "gate": gate_tab.GateTab,
            "create": create_tab.CreateTab,
            "ingest": ingest_tab.IngestTab,
            "condense": condense_tab.CondenseTab,
            "coagulate": coagulate_tab.CoagulateTab,
            "ledger": ledger_tab.LedgerTab,
            "harness": harness_tab.HarnessTab,
            "export": export_tab.ExportTab,
        }
        self._tab_order: list[str] = []
        for key, label, blurb in TABS:
            frame = ttk.Frame(self.notebook)
            self.notebook.add(frame, text=label)
            self._tab_order.append(key)
            try:
                tab = builders[key](frame, self.context)
                tab.blurb = blurb
                self.tabs[key] = tab
            except Exception as exc:
                import traceback
                traceback.print_exc()
                ttk.Label(frame, text=f"{label} failed to load:\n\n{exc}",
                          foreground="#b32020", padding=20,
                          font=("Consolas", 9)).pack(anchor="nw")

    def _bind_keys(self) -> None:
        self.bind("<F11>", lambda e: self.toggle_fullscreen())
        self.bind("<Escape>", lambda e: self.toggle_fullscreen(False))
        self.bind("<Control-e>", lambda e: self.select_tab("export"))
        self.bind("<Control-f>", lambda e: self.select_tab("index"))
        self.bind("<Control-g>", lambda e: self.select_tab("gate"))
        self.bind("<Control-i>", lambda e: self.select_tab("ingest"))
        # Only 1-9 exist as keysyms, so beyond the ninth tab the View menu is the way.
        for number, key in enumerate(k for k, _l, _b in TABS[:9]):
            self.bind(f"<Control-Key-{number + 1}>", lambda e, k=key: self.select_tab(k))

    # -------------------------------------------------------------------- state
    def _first_load(self) -> None:
        self.refresh_counts()
        self._tab_changed()
        self.set_status("Ready. New here? Open the Guide tab. F11 fullscreen.")

    def refresh_counts(self) -> None:
        try:
            counts = self.store.counts()
        except Exception as exc:
            self.counts_var.set(f"store error: {exc}")
            return
        self.counts_var.set(
            f"{counts['projects']} projects | {counts['buckets']} buckets | "
            f"{counts['files']} files | {counts['symbols']} symbols | "
            f"{counts['lines']:,} lines"
        )

    def set_status(self, message: str, kind: str = "info") -> None:
        colours = {"info": "#333333", "good": "#0a7d28",
                   "warn": "#b35c00", "bad": "#b32020"}
        self.status_var.set(message)
        self.status_label.configure(foreground=colours.get(kind, "#333333"))
        if kind == "busy":
            self.progress.start(12)
        else:
            self.progress.stop()

    def select_tab(self, key: str) -> None:
        if key in self._tab_order:
            self.notebook.select(self._tab_order.index(key))

    def _tab_changed(self, _event=None) -> None:
        try:
            index = self.notebook.index(self.notebook.select())
        except tk.TclError:
            return
        key = self._tab_order[index] if index < len(self._tab_order) else ""
        if key == getattr(self, "_last_shown_tab", None):
            return
        self._last_shown_tab = key
        blurb = next((b for k, _l, b in TABS if k == key), "")
        self.hint_var.set(blurb)
        tab = self.tabs.get(key)
        handler = getattr(tab, "on_show", None) or getattr(tab, "on_refresh", None)
        if handler:
            try:
                handler()
            except Exception as exc:
                print(f"on_show {key}: {exc}", file=sys.stderr)

    def toggle_fullscreen(self, value: bool | None = None) -> None:
        self._fullscreen = (not self._fullscreen) if value is None else value
        self.attributes("-fullscreen", self._fullscreen)

    # --------------------------------------------------------------------- help
    def _open_workspace(self) -> None:
        import subprocess
        try:
            if sys.platform == "win32":
                subprocess.Popen(["explorer", str(self.workspace)])
            elif sys.platform == "darwin":
                subprocess.Popen(["open", str(self.workspace)])
            else:
                subprocess.Popen(["xdg-open", str(self.workspace)])
        except OSError as exc:
            messagebox.showerror("Open folder", str(exc))

    def _show_spec(self) -> None:
        spec = self.workspace / "docs" / "CONTEXT_MAP_SPEC.md"
        self._show_text("Context Map Specification",
                        spec.read_text(encoding="utf-8") if spec.exists()
                        else "docs/CONTEXT_MAP_SPEC.md not found")

    def _show_keys(self) -> None:
        self._show_text(
            "Keyboard",
            "F11         fullscreen\n"
            "Esc         leave fullscreen\n"
            "Ctrl+1..8   switch tab\n"
            "Ctrl+F      Index tab\n"
            "Ctrl+G      Write Gate tab\n"
            "Ctrl+I      Ingest tab\n"
            "Ctrl+E      Export tab\n"
            "\nIn tables: double-click opens, right-click copies.",
        )

    def _show_text(self, title: str, body: str) -> None:
        window = tk.Toplevel(self)
        window.title(title)
        window.geometry("900x700")
        from studio.widgets import TextPane
        pane = TextPane(window, wrap=tk.WORD)
        pane.pack(fill=tk.BOTH, expand=True, padx=8, pady=8)
        pane.set(body)

    def _on_close(self) -> None:
        try:
            self.store.close()
        finally:
            self.destroy()


def main(argv: list[str] | None = None) -> int:
    args = list(argv if argv is not None else sys.argv[1:])
    workspace = Path(args[0]) if args else Path(__file__).resolve().parent.parent
    app = StudioApp(workspace)
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
