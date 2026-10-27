#!/usr/bin/env pythonw
"""Parameter-free desktop GUI for the Ollama-to-DeepSeek preflight example.

The GUI imports ``ollama_preprompt`` from the same directory. Tkinter owns all
widgets on the main thread; model discovery and model calls run on one guarded
background worker and report results through a polled queue. A window cannot
close while a Harness run owns resources. An Ollama server started by this GUI
is stopped and reaped before the window exits.
"""

from __future__ import annotations

import importlib.util
import json
import os
import queue
import shutil
import subprocess
import sys
import threading
import time
import tkinter as tk
from dataclasses import asdict, dataclass
from pathlib import Path
from tkinter import filedialog, messagebox, scrolledtext, ttk
from typing import Any, Callable, Literal

import ollama_preprompt as core


AUTO_MODEL = "Auto-select"
SAME_CRITIC = "Same as planner"
NO_CRITIC = "Disabled"
ROUTES: dict[str, Literal["auto", "local", "deepseek"]] = {
    "Automatic": "auto",
    "Local only": "local",
    "Always DeepSeek": "deepseek",
}
HANDOFFS: dict[str, Literal["compact", "verified"]] = {
    "Compact audited brief": "compact",
    "Verified brief + original": "verified",
}

HELP_TEXT = """What this window does

This is a desktop companion for DeepSeek Harness. It does not add a page or controls to the DeepSeek Harness Web app. It uses Ollama locally to plan, clarify, and audit each request, then calls the public DeepSeek Harness Python SDK only when the selected route requires it.

First-time setup

1. Open Ollama_DeepSeek_GUI.bat; no command-line parameters are required.
2. Install Ollama and at least one text-generation model.
3. Use Start Ollama here, or start the normal Ollama application.
4. Use Install / update Harness SDK on the Connection tab. It installs the SDK into the Python environment running this window.
5. Enter a DeepSeek API key on the Connection tab, or provide DEEPSEEK_API_KEY in the process environment. The key field is never saved or included in results.
6. Refresh models, enter a task, and select Run.

Cost controls

Automatic routes complete, low-risk requests locally. Repository work, tool use, missing context, low confidence, or a rejected fidelity audit escalates to DeepSeek.

Local only never calls DeepSeek. It returns the best answer Ollama can provide without claiming to inspect files or run tools.

Always DeepSeek still uses Ollama for the preflight, then hands the task to DeepSeek Harness.

Plan only never calls DeepSeek. For a paid route it displays the exact handoff that would be sent.

Compact audited brief minimizes DeepSeek input. If the critic rejects the brief, the original request is included automatically. Verified brief + original always includes the original request as authoritative.

Safety and lifecycle

Only one background operation runs at a time. The window stays open until that operation finishes so the Harness subprocess can close cleanly. If this GUI starts Ollama, it stops that owned server when the window closes. An Ollama server that was already running is not stopped.
"""


@dataclass(frozen=True, slots=True)
class RunSettings:
    """Validated GUI values needed by one background execution."""

    prompt: str
    ollama_url: str
    planner_model: str | None
    critic_model: str | None
    route: Literal["auto", "local", "deepseek"]
    handoff_mode: Literal["compact", "verified"]
    plan_only: bool
    confidence_threshold: float
    deepseek_provider: str
    deepseek_model: str
    deepseek_api_key: str | None
    deepseek_base_url: str | None
    max_tokens: int
    workspace: Path
    session_root: Path


@dataclass(frozen=True, slots=True)
class RunOutcome:
    """Display-safe result; credentials are never represented here."""

    response: str
    route: Literal["local", "deepseek"]
    planner_model: str
    critic_model: str | None
    decision: core.PlannerDecision
    audit: core.PlanAudit | None
    handoff: str
    plan_only: bool
    deepseek: core.DeepSeekResult | None


def execute_task(
    settings: RunSettings,
    progress: Callable[[str], None] = lambda _message: None,
) -> RunOutcome:
    """Execute one GUI request without accessing Tkinter objects."""
    client = core.OllamaClient(
        settings.ollama_url,
        timeout_seconds=600,
        retries=2,
    )
    progress("Discovering Ollama models…")
    records = client.list_models()
    try:
        running = client.list_running_models()
    except core.OllamaError:
        running = []
    planner_model = core.resolve_model(records, settings.planner_model, running)
    critic_model = None
    if settings.critic_model is not None:
        critic_model = core.resolve_model(
            records,
            settings.critic_model or planner_model,
            running,
        )

    orchestrator = core.OllamaPrepromptOrchestrator(
        client,
        planner_model=planner_model,
        critic_model=critic_model,
        num_ctx=8192,
        keep_alive="10m",
        confidence_threshold=settings.confidence_threshold,
    )
    progress(f"Planning locally with {planner_model}…")
    decision = orchestrator.plan(settings.prompt, settings.workspace)
    if critic_model is not None:
        progress(f"Auditing handoff with {critic_model}…")
    audit = orchestrator.audit(settings.prompt, decision)
    route = orchestrator.select_route(settings.route, decision, audit)
    handoff = orchestrator.build_handoff(
        settings.prompt,
        decision,
        audit,
        settings.handoff_mode,
    )

    if settings.plan_only:
        response = (
            orchestrator.local_response(decision, audit)
            if route == "local"
            else handoff
        )
        if route == "local" and not response:
            response = orchestrator.answer_locally(settings.prompt)
        return RunOutcome(
            response=response,
            route=route,
            planner_model=planner_model,
            critic_model=critic_model,
            decision=decision,
            audit=audit,
            handoff=handoff,
            plan_only=True,
            deepseek=None,
        )

    if route == "local":
        progress("Completing locally without a DeepSeek call…")
        response = orchestrator.local_response(decision, audit)
        if not response:
            response = orchestrator.answer_locally(settings.prompt)
        deepseek = None
    else:
        progress("Running the audited task through DeepSeek Harness…")
        deepseek = core.run_deepseek(
            handoff,
            provider=settings.deepseek_provider,
            model=settings.deepseek_model,
            max_tokens=settings.max_tokens,
            workspace=settings.workspace,
            session_root=settings.session_root,
            session_id=None,
            cordis=None,
            timeout_seconds=None,
            api_key=settings.deepseek_api_key,
            base_url=settings.deepseek_base_url,
        )
        response = deepseek.response

    return RunOutcome(
        response=response,
        route=route,
        planner_model=planner_model,
        critic_model=critic_model,
        decision=decision,
        audit=audit,
        handoff=handoff,
        plan_only=False,
        deepseek=deepseek,
    )


class OrchestratorGui(ttk.Frame):
    """Tkinter controller with serialized background work."""

    def __init__(self, root: tk.Tk) -> None:
        super().__init__(root, padding=14)
        self.root = root
        self.events: queue.Queue[tuple[str, str, object]] = queue.Queue()
        self.worker: threading.Thread | None = None
        self.active_job: str | None = None
        self.owned_ollama: subprocess.Popen[bytes] | None = None
        self._configure_window()
        self._create_variables()
        self._build()
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)
        self.root.bind("<Control-Return>", lambda _event: self._run_clicked())
        self.root.bind("<F5>", lambda _event: self._refresh_models())
        self.root.after(75, self._poll_events)
        self.root.after(250, self._refresh_models)

    def _configure_window(self) -> None:
        self.root.title("Ollama → DeepSeek Harness")
        self.root.geometry("1120x820")
        self.root.minsize(900, 680)
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)
        self.grid(row=0, column=0, sticky="nsew")
        self.columnconfigure(0, weight=1)
        self.rowconfigure(1, weight=1)
        style = ttk.Style(self.root)
        if "vista" in style.theme_names():
            style.theme_use("vista")
        style.configure("Title.TLabel", font=("Segoe UI", 18, "bold"))
        style.configure("Subtitle.TLabel", font=("Segoe UI", 10))
        style.configure("Status.TLabel", font=("Segoe UI", 10, "bold"))

    def _create_variables(self) -> None:
        self.status_var = tk.StringVar(value="Starting…")
        self.ollama_status_var = tk.StringVar(value="Ollama: checking")
        self.planner_var = tk.StringVar(value=AUTO_MODEL)
        self.critic_var = tk.StringVar(value=SAME_CRITIC)
        self.route_var = tk.StringVar(value="Automatic")
        self.handoff_var = tk.StringVar(value="Compact audited brief")
        self.plan_only_var = tk.BooleanVar(value=False)
        self.confidence_var = tk.StringVar(value="0.82")
        self.ollama_url_var = tk.StringVar(
            value=os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")
        )
        self.deepseek_provider_var = tk.StringVar(
            value=os.environ.get("DEEPSEEK_PROVIDER", "deepseek-official")
        )
        self.deepseek_model_var = tk.StringVar(
            value=os.environ.get("DSH_MODEL", "deepseek-v4-flash")
        )
        self.deepseek_base_url_var = tk.StringVar(
            value=os.environ.get("DEEPSEEK_BASE_URL", "")
        )
        self.deepseek_key_var = tk.StringVar()
        self.show_key_var = tk.BooleanVar(value=False)
        self.max_tokens_var = tk.StringVar(
            value=os.environ.get("DEEPSEEK_MAX_TOKENS", "8192")
        )
        repository_root = Path(__file__).resolve().parents[2]
        self.workspace_var = tk.StringVar(value=str(repository_root))
        self.session_root_var = tk.StringVar(value=str(repository_root / ".dsh-sessions"))

    def _build(self) -> None:
        header = ttk.Frame(self)
        header.grid(row=0, column=0, sticky="ew", pady=(0, 10))
        header.columnconfigure(0, weight=1)
        ttk.Label(header, text="Ollama → DeepSeek Harness", style="Title.TLabel").grid(
            row=0, column=0, sticky="w"
        )
        ttk.Label(
            header,
            text="Local planning and fidelity checks before paid agent work",
            style="Subtitle.TLabel",
        ).grid(row=1, column=0, sticky="w")
        ttk.Label(header, textvariable=self.ollama_status_var, style="Status.TLabel").grid(
            row=0, column=1, rowspan=2, sticky="e"
        )

        notebook = ttk.Notebook(self)
        notebook.grid(row=1, column=0, sticky="nsew")
        self.run_tab = ttk.Frame(notebook, padding=12)
        self.connection_tab = ttk.Frame(notebook, padding=12)
        self.help_tab = ttk.Frame(notebook, padding=12)
        notebook.add(self.run_tab, text="Run")
        notebook.add(self.connection_tab, text="Connection")
        notebook.add(self.help_tab, text="Setup & Help")
        self._build_run_tab()
        self._build_connection_tab()
        self._build_help_tab()

        status = ttk.Frame(self)
        status.grid(row=2, column=0, sticky="ew", pady=(10, 0))
        status.columnconfigure(0, weight=1)
        ttk.Label(status, textvariable=self.status_var).grid(row=0, column=0, sticky="w")
        self.progress = ttk.Progressbar(status, mode="indeterminate", length=150)
        self.progress.grid(row=0, column=1, sticky="e")

    def _build_run_tab(self) -> None:
        self.run_tab.columnconfigure(0, weight=1)
        self.run_tab.rowconfigure(4, weight=1)

        prompt_box = ttk.LabelFrame(self.run_tab, text="Task", padding=8)
        prompt_box.grid(row=0, column=0, sticky="nsew")
        prompt_box.columnconfigure(0, weight=1)
        self.prompt_text = scrolledtext.ScrolledText(
            prompt_box,
            height=9,
            wrap=tk.WORD,
            font=("Segoe UI", 10),
        )
        self.prompt_text.grid(row=0, column=0, sticky="nsew")

        settings = ttk.LabelFrame(self.run_tab, text="Routing and cost", padding=8)
        settings.grid(row=1, column=0, sticky="ew", pady=(10, 0))
        for column in range(8):
            settings.columnconfigure(column, weight=1 if column % 2 else 0)
        ttk.Label(settings, text="Planner").grid(row=0, column=0, sticky="w")
        self.planner_combo = ttk.Combobox(
            settings,
            textvariable=self.planner_var,
            values=(AUTO_MODEL,),
            state="readonly",
        )
        self.planner_combo.grid(row=0, column=1, sticky="ew", padx=(6, 14))
        ttk.Label(settings, text="Critic").grid(row=0, column=2, sticky="w")
        self.critic_combo = ttk.Combobox(
            settings,
            textvariable=self.critic_var,
            values=(SAME_CRITIC, NO_CRITIC),
            state="readonly",
        )
        self.critic_combo.grid(row=0, column=3, sticky="ew", padx=(6, 14))
        ttk.Label(settings, text="Route").grid(row=0, column=4, sticky="w")
        ttk.Combobox(
            settings,
            textvariable=self.route_var,
            values=tuple(ROUTES),
            state="readonly",
        ).grid(row=0, column=5, sticky="ew", padx=(6, 14))
        ttk.Label(settings, text="Confidence").grid(row=0, column=6, sticky="w")
        ttk.Entry(settings, textvariable=self.confidence_var, width=8).grid(
            row=0, column=7, sticky="ew", padx=(6, 0)
        )

        ttk.Label(settings, text="Handoff").grid(row=1, column=0, sticky="w", pady=(8, 0))
        ttk.Combobox(
            settings,
            textvariable=self.handoff_var,
            values=tuple(HANDOFFS),
            state="readonly",
        ).grid(row=1, column=1, columnspan=3, sticky="ew", padx=(6, 14), pady=(8, 0))
        ttk.Label(settings, text="Max paid tokens").grid(
            row=1, column=4, sticky="w", pady=(8, 0)
        )
        ttk.Entry(settings, textvariable=self.max_tokens_var).grid(
            row=1, column=5, sticky="ew", padx=(6, 14), pady=(8, 0)
        )
        ttk.Checkbutton(
            settings,
            text="Plan only (never call DeepSeek)",
            variable=self.plan_only_var,
        ).grid(row=1, column=6, columnspan=2, sticky="w", pady=(8, 0))

        actions = ttk.Frame(self.run_tab)
        actions.grid(row=2, column=0, sticky="ew", pady=10)
        self.run_button = ttk.Button(actions, text="Run  (Ctrl+Enter)", command=self._run_clicked)
        self.run_button.pack(side=tk.LEFT)
        ttk.Button(actions, text="Copy result", command=self._copy_result).pack(
            side=tk.LEFT, padx=(8, 0)
        )
        ttk.Button(actions, text="Clear", command=self._clear).pack(side=tk.LEFT, padx=(8, 0))

        result_notebook = ttk.Notebook(self.run_tab)
        result_notebook.grid(row=4, column=0, sticky="nsew")
        answer_frame = ttk.Frame(result_notebook, padding=5)
        details_frame = ttk.Frame(result_notebook, padding=5)
        result_notebook.add(answer_frame, text="Result")
        result_notebook.add(details_frame, text="Plan details")
        for frame in (answer_frame, details_frame):
            frame.columnconfigure(0, weight=1)
            frame.rowconfigure(0, weight=1)
        self.result_text = scrolledtext.ScrolledText(
            answer_frame,
            wrap=tk.WORD,
            font=("Segoe UI", 10),
        )
        self.result_text.grid(row=0, column=0, sticky="nsew")
        self.details_text = scrolledtext.ScrolledText(
            details_frame,
            wrap=tk.WORD,
            font=("Consolas", 9),
        )
        self.details_text.grid(row=0, column=0, sticky="nsew")

    def _build_connection_tab(self) -> None:
        self.connection_tab.columnconfigure(1, weight=1)
        row = 0
        ttk.Label(self.connection_tab, text="Ollama URL").grid(row=row, column=0, sticky="w")
        ttk.Entry(self.connection_tab, textvariable=self.ollama_url_var).grid(
            row=row, column=1, sticky="ew", padx=8
        )
        self.start_button = ttk.Button(
            self.connection_tab,
            text="Start Ollama",
            command=self._start_ollama,
        )
        self.start_button.grid(row=row, column=2, padx=(0, 8))
        self.refresh_button = ttk.Button(
            self.connection_tab,
            text="Refresh models  (F5)",
            command=self._refresh_models,
        )
        self.refresh_button.grid(row=row, column=3)

        row += 1
        ttk.Separator(self.connection_tab).grid(
            row=row, column=0, columnspan=4, sticky="ew", pady=14
        )
        row += 1
        ttk.Label(self.connection_tab, text="DeepSeek provider").grid(
            row=row, column=0, sticky="w"
        )
        ttk.Entry(self.connection_tab, textvariable=self.deepseek_provider_var).grid(
            row=row, column=1, columnspan=3, sticky="ew", padx=8
        )
        row += 1
        ttk.Label(self.connection_tab, text="DeepSeek model").grid(
            row=row, column=0, sticky="w", pady=(8, 0)
        )
        ttk.Entry(self.connection_tab, textvariable=self.deepseek_model_var).grid(
            row=row, column=1, columnspan=3, sticky="ew", padx=8, pady=(8, 0)
        )
        row += 1
        ttk.Label(self.connection_tab, text="DeepSeek base URL (optional)").grid(
            row=row, column=0, sticky="w", pady=(8, 0)
        )
        ttk.Entry(self.connection_tab, textvariable=self.deepseek_base_url_var).grid(
            row=row, column=1, columnspan=3, sticky="ew", padx=8, pady=(8, 0)
        )
        row += 1
        ttk.Label(self.connection_tab, text="DeepSeek API key (not saved)").grid(
            row=row, column=0, sticky="w", pady=(8, 0)
        )
        self.key_entry = ttk.Entry(
            self.connection_tab,
            textvariable=self.deepseek_key_var,
            show="•",
        )
        self.key_entry.grid(row=row, column=1, columnspan=2, sticky="ew", padx=8, pady=(8, 0))
        ttk.Checkbutton(
            self.connection_tab,
            text="Show",
            variable=self.show_key_var,
            command=self._toggle_key,
        ).grid(row=row, column=3, sticky="w", pady=(8, 0))

        row += 1
        ttk.Separator(self.connection_tab).grid(
            row=row, column=0, columnspan=4, sticky="ew", pady=14
        )
        row += 1
        ttk.Label(self.connection_tab, text="Harness workspace").grid(
            row=row, column=0, sticky="w"
        )
        ttk.Entry(self.connection_tab, textvariable=self.workspace_var).grid(
            row=row, column=1, columnspan=2, sticky="ew", padx=8
        )
        ttk.Button(
            self.connection_tab,
            text="Browse…",
            command=lambda: self._choose_directory(self.workspace_var),
        ).grid(row=row, column=3)
        row += 1
        ttk.Label(self.connection_tab, text="Session storage").grid(
            row=row, column=0, sticky="w", pady=(8, 0)
        )
        ttk.Entry(self.connection_tab, textvariable=self.session_root_var).grid(
            row=row, column=1, columnspan=2, sticky="ew", padx=8, pady=(8, 0)
        )
        ttk.Button(
            self.connection_tab,
            text="Browse…",
            command=lambda: self._choose_directory(self.session_root_var),
        ).grid(row=row, column=3, pady=(8, 0))

        row += 1
        self.check_button = ttk.Button(
            self.connection_tab,
            text="Check setup",
            command=self._check_setup,
        )
        self.check_button.grid(row=row, column=0, sticky="w", pady=(18, 0))
        self.install_button = ttk.Button(
            self.connection_tab,
            text="Install / update Harness SDK",
            command=self._install_sdk,
        )
        self.install_button.grid(row=row, column=1, sticky="w", padx=8, pady=(18, 0))
        self.setup_report = scrolledtext.ScrolledText(
            self.connection_tab,
            height=10,
            wrap=tk.WORD,
            font=("Segoe UI", 10),
        )
        self.setup_report.grid(
            row=row + 1,
            column=0,
            columnspan=4,
            sticky="nsew",
            pady=(8, 0),
        )
        self.connection_tab.rowconfigure(row + 1, weight=1)

    def _build_help_tab(self) -> None:
        self.help_tab.columnconfigure(0, weight=1)
        self.help_tab.rowconfigure(0, weight=1)
        help_text = scrolledtext.ScrolledText(
            self.help_tab,
            wrap=tk.WORD,
            font=("Segoe UI", 10),
            padx=10,
            pady=10,
        )
        help_text.grid(row=0, column=0, sticky="nsew")
        help_text.insert("1.0", HELP_TEXT)
        help_text.configure(state=tk.DISABLED)

    def _run_clicked(self) -> None:
        try:
            settings = self._collect_settings()
        except ValueError as exc:
            messagebox.showerror("Cannot run", str(exc), parent=self.root)
            return
        self._replace_text(self.result_text, "")
        self._replace_text(self.details_text, "")
        self._start_job("run", lambda: execute_task(settings, self._post_progress))

    def _collect_settings(self) -> RunSettings:
        prompt = self.prompt_text.get("1.0", tk.END).strip()
        if not prompt:
            raise ValueError("Enter a task on the Run tab.")
        if len(prompt) > core.MAX_INPUT_CHARS:
            raise ValueError(f"Task exceeds {core.MAX_INPUT_CHARS} characters.")
        try:
            confidence = float(self.confidence_var.get())
        except ValueError as exc:
            raise ValueError("Confidence must be a number between 0 and 1.") from exc
        if not 0 <= confidence <= 1:
            raise ValueError("Confidence must be between 0 and 1.")
        try:
            max_tokens = int(self.max_tokens_var.get())
        except ValueError as exc:
            raise ValueError("Max paid tokens must be a positive whole number.") from exc
        if max_tokens <= 0:
            raise ValueError("Max paid tokens must be positive.")
        workspace = Path(self.workspace_var.get()).expanduser().resolve()
        if not workspace.is_dir():
            raise ValueError(f"Harness workspace is not a directory: {workspace}")
        session_root = Path(self.session_root_var.get()).expanduser().resolve()
        planner_value = self.planner_var.get()
        critic_value = self.critic_var.get()
        planner = None if planner_value == AUTO_MODEL else planner_value
        if critic_value == NO_CRITIC:
            critic: str | None = None
        elif critic_value == SAME_CRITIC:
            critic = ""
        else:
            critic = critic_value
        provider = self.deepseek_provider_var.get().strip()
        model = self.deepseek_model_var.get().strip()
        if not provider or not model:
            raise ValueError("DeepSeek provider and model cannot be empty.")
        return RunSettings(
            prompt=prompt,
            ollama_url=self.ollama_url_var.get().strip(),
            planner_model=planner,
            critic_model=critic,
            route=ROUTES[self.route_var.get()],
            handoff_mode=HANDOFFS[self.handoff_var.get()],
            plan_only=self.plan_only_var.get(),
            confidence_threshold=confidence,
            deepseek_provider=provider,
            deepseek_model=model,
            deepseek_api_key=self.deepseek_key_var.get().strip() or None,
            deepseek_base_url=self.deepseek_base_url_var.get().strip() or None,
            max_tokens=max_tokens,
            workspace=workspace,
            session_root=session_root,
        )

    def _refresh_models(self) -> None:
        url = self.ollama_url_var.get().strip()

        def work() -> dict[str, Any]:
            client = core.OllamaClient(url, timeout_seconds=10, retries=0)
            records = client.list_models()
            try:
                running = client.list_running_models()
            except core.OllamaError:
                running = []
            names = sorted(
                name
                for item in records
                if (name := core._model_name(item)) is not None and core._is_text_model(name)
            )
            running_names = [
                name for item in running if (name := core._model_name(item)) is not None
            ]
            return {"names": names, "running": running_names}

        self._start_job("models", work)

    def _check_setup(self) -> None:
        url = self.ollama_url_var.get().strip()
        entered_key = bool(self.deepseek_key_var.get().strip())

        def work() -> dict[str, Any]:
            try:
                client = core.OllamaClient(url, timeout_seconds=10, retries=0)
                records = client.list_models()
                names = [
                    name
                    for item in records
                    if (name := core._model_name(item)) is not None
                ]
                ollama = f"Ready ({len(names)} installed models)"
            except Exception as exc:
                ollama = f"Not ready: {exc}"
            sdk = "Installed" if importlib.util.find_spec("deepseek_harness") else "Missing"
            key = "Available" if entered_key or os.environ.get("DEEPSEEK_API_KEY") else "Missing"
            return {"ollama": ollama, "sdk": sdk, "key": key}

        self._start_job("check", work)

    def _start_ollama(self) -> None:
        url = self.ollama_url_var.get().strip()

        def work() -> dict[str, Any]:
            client = core.OllamaClient(url, timeout_seconds=2, retries=0)
            try:
                records = client.list_models()
                return {"process": None, "records": records, "already_running": True}
            except core.OllamaError:
                pass
            executable = shutil.which("ollama") or shutil.which("ollama.exe")
            if executable is None:
                raise core.OllamaError("Ollama executable was not found on PATH.")
            creation_flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
            process = subprocess.Popen(
                [executable, "serve"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                creationflags=creation_flags,
            )
            try:
                deadline = time.monotonic() + 20
                while time.monotonic() < deadline:
                    try:
                        records = client.list_models()
                        return {
                            "process": process if process.poll() is None else None,
                            "records": records,
                            "already_running": False,
                        }
                    except core.OllamaError:
                        if process.poll() is not None:
                            break
                        time.sleep(0.4)
                raise core.OllamaError("Ollama did not become ready within 20 seconds.")
            except BaseException:
                self._stop_process(process)
                raise

        self._start_job("start", work)

    def _install_sdk(self) -> None:
        def work() -> dict[str, str]:
            creation_flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
            try:
                result = subprocess.run(
                    [
                        sys.executable,
                        "-m",
                        "pip",
                        "install",
                        "--upgrade",
                        "deepseek-harness-sdk",
                    ],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=900,
                    creationflags=creation_flags,
                    check=False,
                )
            except subprocess.TimeoutExpired as exc:
                raise RuntimeError("Harness SDK installation timed out after 15 minutes.") from exc
            if result.returncode != 0:
                raise RuntimeError(
                    f"Harness SDK installation failed with exit code {result.returncode}."
                )
            importlib.invalidate_caches()
            return {"sdk": "Installed or updated successfully."}

        if not messagebox.askyesno(
            "Install Harness SDK",
            "Download and install or update deepseek-harness-sdk in the Python environment running this window?",
            parent=self.root,
        ):
            return
        self._start_job("install", work)

    def _start_job(self, name: str, target: Callable[[], object]) -> None:
        if self.active_job is not None:
            self.status_var.set("Wait for the current operation to finish.")
            return
        self.active_job = name
        self._set_busy(True)
        self.status_var.set(
            {
                "run": "Preparing request…",
                "models": "Refreshing Ollama models…",
                "check": "Checking setup…",
                "start": "Starting Ollama…",
                "install": "Installing the DeepSeek Harness SDK…",
            }[name]
        )

        def dispatch() -> None:
            try:
                result = target()
            except BaseException as exc:
                self.events.put(("error", name, exc))
            else:
                self.events.put(("done", name, result))

        self.worker = threading.Thread(target=dispatch, name=f"ollama-gui-{name}", daemon=True)
        self.worker.start()

    def _post_progress(self, message: str) -> None:
        self.events.put(("progress", "run", message))

    def _poll_events(self) -> None:
        try:
            while True:
                kind, name, payload = self.events.get_nowait()
                try:
                    self._handle_event(kind, name, payload)
                except Exception as exc:
                    messagebox.showerror("GUI update failed", str(exc), parent=self.root)
        except queue.Empty:
            pass
        self.root.after(75, self._poll_events)

    def _handle_event(self, kind: str, name: str, payload: object) -> None:
        if kind == "progress":
            self.status_var.set(str(payload))
            return
        self.active_job = None
        self.worker = None
        self._set_busy(False)
        if kind == "error":
            if name in {"models", "start"}:
                self.ollama_status_var.set("Ollama: unavailable")
            self.status_var.set(f"Failed: {payload}")
            if name != "models":
                messagebox.showerror("Operation failed", str(payload), parent=self.root)
            return
        if name == "models":
            result = self._expect_dict(payload)
            self._apply_models(result["names"], result["running"])
            self.status_var.set("Ollama models refreshed.")
        elif name == "check":
            result = self._expect_dict(payload)
            report = (
                f"Ollama: {result['ollama']}\n"
                f"DeepSeek Harness SDK: {result['sdk']}\n"
                f"DeepSeek API key: {result['key']}\n\n"
                "A missing API key affects only DeepSeek routes. Local-only and plan-only work remain available."
            )
            self._replace_text(self.setup_report, report)
            self.status_var.set("Setup check complete.")
        elif name == "start":
            result = self._expect_dict(payload)
            process = result.get("process")
            if isinstance(process, subprocess.Popen):
                self.owned_ollama = process
            records = result["records"]
            names = [
                model_name
                for item in records
                if isinstance(item, dict)
                and (model_name := core._model_name(item)) is not None
                and core._is_text_model(model_name)
            ]
            self._apply_models(sorted(names), [])
            self.status_var.set(
                "Ollama was already running."
                if result["already_running"]
                else "Ollama started and is ready."
            )
        elif name == "install":
            result = self._expect_dict(payload)
            self._replace_text(self.setup_report, str(result["sdk"]))
            self.status_var.set(str(result["sdk"]))
        elif name == "run":
            if not isinstance(payload, RunOutcome):
                raise TypeError("run worker returned an unexpected result")
            self._render_outcome(payload)

    def _render_outcome(self, outcome: RunOutcome) -> None:
        self._replace_text(self.result_text, outcome.response)
        details = {
            "route": outcome.route,
            "plan_only": outcome.plan_only,
            "planner_model": outcome.planner_model,
            "critic_model": outcome.critic_model,
            "decision": asdict(outcome.decision),
            "audit": asdict(outcome.audit) if outcome.audit is not None else None,
            "handoff": outcome.handoff if outcome.route == "deepseek" else None,
            "deepseek": asdict(outcome.deepseek) if outcome.deepseek is not None else None,
        }
        self._replace_text(self.details_text, json.dumps(details, ensure_ascii=False, indent=2))
        suffix = "plan only" if outcome.plan_only else "complete"
        self.status_var.set(f"Route: {outcome.route} — {suffix}.")

    def _apply_models(self, names: object, running: object) -> None:
        if not isinstance(names, list) or not all(isinstance(item, str) for item in names):
            raise TypeError("model refresh returned invalid names")
        running_names = running if isinstance(running, list) else []
        self.planner_combo.configure(values=(AUTO_MODEL, *names))
        self.critic_combo.configure(values=(SAME_CRITIC, NO_CRITIC, *names))
        if self.planner_var.get() not in {AUTO_MODEL, *names}:
            self.planner_var.set(AUTO_MODEL)
        if self.critic_var.get() not in {SAME_CRITIC, NO_CRITIC, *names}:
            self.critic_var.set(SAME_CRITIC)
        running_label = f" — running: {', '.join(running_names)}" if running_names else ""
        self.ollama_status_var.set(f"Ollama: ready ({len(names)} text models){running_label}")

    @staticmethod
    def _expect_dict(payload: object) -> dict[str, Any]:
        if not isinstance(payload, dict):
            raise TypeError("worker returned an unexpected result")
        return payload

    def _set_busy(self, busy: bool) -> None:
        state = tk.DISABLED if busy else tk.NORMAL
        for button in (
            self.run_button,
            self.refresh_button,
            self.check_button,
            self.start_button,
            self.install_button,
        ):
            button.configure(state=state)
        if busy:
            self.progress.start(12)
        else:
            self.progress.stop()

    def _toggle_key(self) -> None:
        self.key_entry.configure(show="" if self.show_key_var.get() else "•")

    def _choose_directory(self, variable: tk.StringVar) -> None:
        selected = filedialog.askdirectory(
            parent=self.root,
            initialdir=variable.get() or str(Path.cwd()),
        )
        if selected:
            variable.set(selected)

    def _copy_result(self) -> None:
        content = self.result_text.get("1.0", tk.END).strip()
        if not content:
            self.status_var.set("There is no result to copy.")
            return
        self.root.clipboard_clear()
        self.root.clipboard_append(content)
        self.status_var.set("Result copied to the clipboard.")

    def _clear(self) -> None:
        if self.active_job is not None:
            self.status_var.set("Wait for the current operation to finish.")
            return
        self.prompt_text.delete("1.0", tk.END)
        self._replace_text(self.result_text, "")
        self._replace_text(self.details_text, "")
        self.status_var.set("Cleared.")

    @staticmethod
    def _replace_text(widget: tk.Text, value: str) -> None:
        widget.delete("1.0", tk.END)
        widget.insert("1.0", value)

    def _on_close(self) -> None:
        if self.active_job is not None:
            messagebox.showwarning(
                "Operation still running",
                "Wait for the current operation to finish so its model and Harness processes can close cleanly.",
                parent=self.root,
            )
            return
        if self.owned_ollama is not None:
            self.status_var.set("Stopping the Ollama server started by this window…")
            self.root.update_idletasks()
            self._stop_process(self.owned_ollama)
            self.owned_ollama = None
        self.root.destroy()

    @staticmethod
    def _stop_process(process: subprocess.Popen[bytes]) -> None:
        if process.poll() is not None:
            return
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def main() -> None:
    """Open the desktop application without command-line configuration."""
    root = tk.Tk()
    OrchestratorGui(root)
    root.mainloop()


if __name__ == "__main__":
    main()
