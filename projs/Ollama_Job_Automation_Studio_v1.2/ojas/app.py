from __future__ import annotations

import json
import os
import queue
import shutil
import subprocess
import sys
import threading
import time
import tkinter as tk
from datetime import datetime
from pathlib import Path
from tkinter import filedialog, messagebox, simpledialog, ttk
from typing import Any

from .browser import BrowserWorker, FieldMapper
from .core import (
    AtomicJSON,
    AppPaths,
    CommandRunner,
    EnvironmentManager,
    MODEL_CATALOG,
    RECOMMENDED_ENV,
    default_profile,
    default_rules,
    open_folder,
    system_report,
    which_ollama,
)
from .ollama_api import OllamaClient
from .rag import RAGStore
from .feature_ui import ATSMixin, VisualSynthesisMixin
from .resume_ats import analyze_resume, donovan_seed_profile, extract_pdf_text, profile_is_effectively_blank, profile_metrics
from .tab_help import TabHelpMixin


class OllamaJobAutomationStudio(TabHelpMixin, ATSMixin, VisualSynthesisMixin):
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("Ollama Job Automation Studio")
        self.root.geometry("1450x900")
        self.root.minsize(900, 600)
        self._is_fullscreen = False
    
        self.paths = AppPaths.create()
        self.project_root = Path(__file__).resolve().parent.parent
        self.bundled_resume_path = self.project_root / "sample_data" / "DonovanZeanahResume-2026.pdf"
        self.events: queue.Queue[dict[str, Any]] = queue.Queue()
        self.client = OllamaClient()
        self.rag = RAGStore(self.paths.rag_db, self.client)
        self.command_runner = CommandRunner(self.events.put)
        self.browser = BrowserWorker(self.events, self.paths.browser_profile)
        self.browser.start()
    
        initial_profile = (
            donovan_seed_profile(self.bundled_resume_path)
            if self.bundled_resume_path.exists()
            else default_profile()
        )
        self.profile = AtomicJSON.load(self.paths.profile_json, initial_profile)
        if self.bundled_resume_path.exists() and profile_is_effectively_blank(self.profile):
            self.profile = donovan_seed_profile(self.bundled_resume_path)
            AtomicJSON.save(self.paths.profile_json, self.profile)
        self.rules = AtomicJSON.load(self.paths.rules_json, default_rules())
        if not self.paths.profile_json.exists():
            AtomicJSON.save(self.paths.profile_json, self.profile)
        if not self.paths.rules_json.exists():
            AtomicJSON.save(self.paths.rules_json, self.rules)
    
        self.installed_models: list[str] = []
        self.form_mappings: list[dict[str, Any]] = []
        self.form_mapping_by_iid: dict[str, dict[str, Any]] = {}
        self.rag_sources: list[Path] = []
        self.chat_history: list[dict[str, str]] = []
        self.ats_report = None
    
        self._build_style()
        self._build_ui()
        self._configure_shortcuts()
        self._load_profile_editor()
        self._load_rules_editor()
        self._refresh_system_report()
        self._refresh_rag_stats()
        self._poll_events()
        self._async_refresh_ollama()
    
        # Maximize after all widgets exist so every pane receives a useful size.
        self.root.after_idle(self._maximize_window)
    
    def _build_style(self) -> None:
        style = ttk.Style()
        for theme in ("vista", "clam"):
            if theme in style.theme_names():
                style.theme_use(theme)
                break
        style.configure("Title.TLabel", font=("Segoe UI", 15, "bold"))
        style.configure("Header.TLabel", font=("Segoe UI", 11, "bold"))
        style.configure("Danger.TLabel", foreground="#9b1c1c")
        style.configure("Success.TLabel", foreground="#176b2c")
        style.configure("Primary.TButton", font=("Segoe UI", 10, "bold"), padding=(12, 7))
        style.configure("Tool.TButton", padding=(8, 5))
        style.configure("Treeview", rowheight=24)
        style.configure("Treeview.Heading", font=("Segoe UI", 9, "bold"))
    
    def _build_ui(self) -> None:
        self.root.grid_rowconfigure(1, weight=1)
        self.root.grid_columnconfigure(0, weight=1)
    
        top = ttk.Frame(self.root, padding=(12, 7))
        top.grid(row=0, column=0, sticky="ew")
        top.grid_columnconfigure(1, weight=1)
    
        ttk.Label(
            top,
            text="Ollama Job Automation Studio",
            style="Title.TLabel",
        ).grid(row=0, column=0, sticky="w")
    
        self.status_var = tk.StringVar(value="Ready")
        ttk.Label(top, textvariable=self.status_var).grid(
            row=0, column=1, sticky="e", padx=(12, 8)
        )
        ttk.Button(
            top,
            text="Maximize",
            style="Tool.TButton",
            command=self._maximize_window,
        ).grid(row=0, column=2, padx=3)
        ttk.Button(
            top,
            text="Full Screen  F11",
            style="Tool.TButton",
            command=self._toggle_fullscreen,
        ).grid(row=0, column=3, padx=3)
        ttk.Button(
            top,
            text="About this tab",
            style="Primary.TButton",
            command=self.show_current_tab_help,
        ).grid(row=0, column=4, padx=(6, 3))
    
        self.notebook = ttk.Notebook(self.root)
        self.notebook.grid(
            row=1,
            column=0,
            sticky="nsew",
            padx=8,
            pady=(0, 8),
        )
    
        self.setup_tab = ttk.Frame(self.notebook)
        self.chat_tab = ttk.Frame(self.notebook)
        self.rag_tab = ttk.Frame(self.notebook)
        self.profile_tab = ttk.Frame(self.notebook)
        self.ats_tab = ttk.Frame(self.notebook)
        self.apply_tab = ttk.Frame(self.notebook)
        self.visual_tab = ttk.Frame(self.notebook)
        self.logs_tab = ttk.Frame(self.notebook)
    
        self.notebook.add(self.setup_tab, text="1. Setup & Models")
        self.notebook.add(self.chat_tab, text="2. Model Lab")
        self.notebook.add(self.rag_tab, text="3. Memory / RAG")
        self.notebook.add(self.profile_tab, text="4. Verified Profile")
        self.notebook.add(self.ats_tab, text="5. ATS Resume Scanner")
        self.notebook.add(self.apply_tab, text="6. Application Assistant")
        self.notebook.add(self.visual_tab, text="7. Visual Synthesis")
        self.notebook.add(self.logs_tab, text="8. Logs")
    
        self._build_setup_tab()
        self._build_chat_tab()
        self._build_rag_tab()
        self._build_profile_tab()
        self._build_ats_tab()
        self._build_apply_tab()
        self._build_visual_tab()
        self._build_logs_tab()
    
    @staticmethod
    def _text(parent: tk.Widget, **kwargs: Any) -> tk.Text:
        return tk.Text(
            parent,
            wrap=kwargs.pop("wrap", "word"),
            undo=True,
            font=("Consolas", 10),
            **kwargs,
        )
    
    def _scrolled_text(
        self,
        parent: tk.Widget,
        *,
        wrap: str = "word",
        height: int = 6,
    ) -> tuple[ttk.Frame, tk.Text]:
        frame = ttk.Frame(parent)
        frame.grid_rowconfigure(0, weight=1)
        frame.grid_columnconfigure(0, weight=1)
    
        text = self._text(frame, wrap=wrap, height=height)
        vertical = ttk.Scrollbar(frame, orient="vertical", command=text.yview)
        text.configure(yscrollcommand=vertical.set)
    
        text.grid(row=0, column=0, sticky="nsew")
        vertical.grid(row=0, column=1, sticky="ns")
    
        if wrap == "none":
            horizontal = ttk.Scrollbar(frame, orient="horizontal", command=text.xview)
            text.configure(xscrollcommand=horizontal.set)
            horizontal.grid(row=1, column=0, sticky="ew")
    
        return frame, text
    
    @staticmethod
    def _button_grid(
        parent: tk.Widget,
        buttons: list[tuple[str, Any]],
        *,
        columns: int = 3,
        primary_index: int | None = None,
    ) -> None:
        columns = max(1, columns)
        for column in range(columns):
            parent.grid_columnconfigure(column, weight=1, uniform="button-grid")
        for index, (label, command) in enumerate(buttons):
            row, column = divmod(index, columns)
            style = "Primary.TButton" if index == primary_index else "Tool.TButton"
            ttk.Button(
                parent,
                text=label,
                command=command,
                style=style,
            ).grid(
                row=row,
                column=column,
                sticky="ew",
                padx=3,
                pady=3,
            )
    
    def _configure_shortcuts(self) -> None:
        self.root.bind("<F11>", lambda _event: self._toggle_fullscreen())
        self.root.bind("<Escape>", lambda _event: self._leave_fullscreen())
        self.root.bind("<Control-Return>", self._primary_action)
        self.root.bind("<Control-KP_Enter>", self._primary_action)
        for number in range(1, 9):
            self.root.bind(
                f"<Control-Key-{number}>",
                lambda _event, index=number - 1: self._select_tab(index),
            )
    
    def _select_tab(self, index: int) -> str:
        if 0 <= index < len(self.notebook.tabs()):
            self.notebook.select(index)
        return "break"
    
    def _primary_action(self, _event: tk.Event | None = None) -> str:
        index = self.notebook.index(self.notebook.select())
        if index == 1:
            self.send_chat()
        elif index == 2:
            self.ask_rag()
        elif index == 3:
            self.save_profile()
        elif index == 4:
            self.analyze_ats_resume()
        elif index == 5:
            self.inspect_browser()
        elif index == 6:
            self.generate_visual_image()
        return "break"
    
    def _maximize_window(self) -> None:
        self._leave_fullscreen()
        try:
            self.root.state("zoomed")
        except tk.TclError:
            try:
                self.root.attributes("-zoomed", True)
            except tk.TclError:
                screen_width = self.root.winfo_screenwidth()
                screen_height = self.root.winfo_screenheight()
                self.root.geometry(f"{screen_width}x{screen_height}+0+0")
    
    def _toggle_fullscreen(self) -> None:
        self._is_fullscreen = not self._is_fullscreen
        self.root.attributes("-fullscreen", self._is_fullscreen)
    
    def _leave_fullscreen(self) -> None:
        if self._is_fullscreen:
            self._is_fullscreen = False
            self.root.attributes("-fullscreen", False)
    
    @staticmethod
    def _responsive_wrap(label: ttk.Label, padding: int = 30) -> None:
        def update(event: tk.Event) -> None:
            label.configure(wraplength=max(260, event.width - padding))
    
        label.master.bind("<Configure>", update, add="+")
    
    def _build_setup_tab(self) -> None:
        self.setup_tab.grid_rowconfigure(0, weight=1)
        self.setup_tab.grid_columnconfigure(0, weight=1)
    
        container = ttk.Panedwindow(self.setup_tab, orient="horizontal")
        container.grid(row=0, column=0, sticky="nsew", padx=7, pady=7)
    
        left = ttk.Frame(container, padding=6)
        right = ttk.Frame(container, padding=6)
        left.grid_rowconfigure(2, weight=1)
        left.grid_columnconfigure(0, weight=1)
        right.grid_rowconfigure(1, weight=1)
        right.grid_columnconfigure(0, weight=1)
    
        container.add(left, weight=2)
        container.add(right, weight=3)
    
        env_frame = ttk.LabelFrame(left, text="Recommended Ollama environment", padding=7)
        env_frame.grid(row=0, column=0, sticky="ew")
        env_frame.grid_columnconfigure(1, weight=1)
        for row_index, (key, value) in enumerate(RECOMMENDED_ENV.items()):
            ttk.Label(env_frame, text=key).grid(
                row=row_index, column=0, sticky="w", padx=(0, 8), pady=2
            )
            ttk.Label(env_frame, text=value).grid(
                row=row_index, column=1, sticky="w", pady=2
            )
        ttk.Button(
            env_frame,
            text="Apply recommended settings",
            command=self.apply_environment,
            style="Primary.TButton",
        ).grid(
            row=len(RECOMMENDED_ENV),
            column=0,
            columnspan=2,
            sticky="ew",
            pady=(7, 0),
        )
    
        tools = ttk.LabelFrame(left, text="Setup tools", padding=5)
        tools.grid(row=1, column=0, sticky="ew", pady=(7, 7))
        self._button_grid(
            tools,
            [
                ("Test Ollama API", self._async_refresh_ollama),
                ("Start Ollama server", self.start_ollama_server),
                ("Install Python dependencies", self.install_dependencies),
                ("Install Playwright Chromium", self.install_playwright),
                ("Open application data", lambda: open_folder(self.paths.root)),
                ("Refresh hardware report", self._refresh_system_report),
                ("Run built-in self tests", self.run_self_tests),
            ],
            columns=2,
        )
    
        report_frame = ttk.LabelFrame(left, text="System report", padding=5)
        report_frame.grid(row=2, column=0, sticky="nsew")
        report_frame.grid_rowconfigure(0, weight=1)
        report_frame.grid_columnconfigure(0, weight=1)
        report_scroll, self.system_text = self._scrolled_text(
            report_frame, wrap="none", height=12
        )
        report_scroll.grid(row=0, column=0, sticky="nsew")
    
        ttk.Label(
            right,
            text="Recommended model set",
            style="Header.TLabel",
        ).grid(row=0, column=0, sticky="w")
    
        tree_frame = ttk.Frame(right)
        tree_frame.grid(row=1, column=0, sticky="nsew", pady=(5, 6))
        tree_frame.grid_rowconfigure(0, weight=1)
        tree_frame.grid_columnconfigure(0, weight=1)
    
        columns = ("installed", "model", "role", "description")
        self.model_tree = ttk.Treeview(
            tree_frame,
            columns=columns,
            show="headings",
            selectmode="extended",
        )
        vertical = ttk.Scrollbar(tree_frame, orient="vertical", command=self.model_tree.yview)
        horizontal = ttk.Scrollbar(tree_frame, orient="horizontal", command=self.model_tree.xview)
        self.model_tree.configure(
            yscrollcommand=vertical.set,
            xscrollcommand=horizontal.set,
        )
        self.model_tree.grid(row=0, column=0, sticky="nsew")
        vertical.grid(row=0, column=1, sticky="ns")
        horizontal.grid(row=1, column=0, sticky="ew")
    
        self.model_tree.heading("installed", text="Installed")
        self.model_tree.heading("model", text="Model")
        self.model_tree.heading("role", text="Role")
        self.model_tree.heading("description", text="Purpose")
        self.model_tree.column("installed", width=75, minwidth=65, anchor="center", stretch=False)
        self.model_tree.column("model", width=175, minwidth=145)
        self.model_tree.column("role", width=140, minwidth=110)
        self.model_tree.column("description", width=440, minwidth=260)
    
        for item in MODEL_CATALOG:
            self.model_tree.insert(
                "",
                "end",
                iid=item["name"],
                values=("No", item["name"], item["role"], item["description"]),
            )
    
        model_actions = ttk.Frame(right)
        model_actions.grid(row=2, column=0, sticky="ew")
        self._button_grid(
            model_actions,
            [
                ("Pull selected", self.pull_selected_models),
                ("Pull all recommended", self.pull_all_models),
                ("Refresh installed", self._async_refresh_ollama),
                ("Show loaded models", self.show_loaded_models),
            ],
            columns=2,
            primary_index=1,
        )
    
        self.ollama_status_var = tk.StringVar(value="Ollama status: not checked")
        ttk.Label(
            right,
            textvariable=self.ollama_status_var,
        ).grid(row=3, column=0, sticky="ew", pady=(5, 0))
    
    def _build_chat_tab(self) -> None:
        self.chat_tab.grid_rowconfigure(0, weight=1)
        self.chat_tab.grid_columnconfigure(0, weight=1)
    
        outer = ttk.Frame(self.chat_tab, padding=8)
        outer.grid(row=0, column=0, sticky="nsew")
        outer.grid_rowconfigure(2, weight=1)
        outer.grid_columnconfigure(0, weight=1)
    
        controls = ttk.LabelFrame(outer, text="Model request", padding=7)
        controls.grid(row=0, column=0, sticky="ew")
        controls.grid_columnconfigure(1, weight=1)
        controls.grid_columnconfigure(5, weight=1)
    
        ttk.Label(controls, text="Model").grid(row=0, column=0, sticky="w")
        self.chat_model_var = tk.StringVar(value="qwen3.5:4b")
        self.chat_model_combo = ttk.Combobox(
            controls,
            textvariable=self.chat_model_var,
            values=[m["name"] for m in MODEL_CATALOG],
        )
        self.chat_model_combo.grid(
            row=0, column=1, sticky="ew", padx=(5, 12)
        )
    
        ttk.Label(controls, text="Temperature").grid(row=0, column=2, sticky="w")
        self.temperature_var = tk.DoubleVar(value=0.2)
        ttk.Spinbox(
            controls,
            textvariable=self.temperature_var,
            from_=0.0,
            to=2.0,
            increment=0.1,
            width=8,
        ).grid(row=0, column=3, sticky="w", padx=(5, 12))
    
        ttk.Label(controls, text="Context").grid(row=0, column=4, sticky="w")
        self.context_var = tk.IntVar(value=8192)
        ttk.Combobox(
            controls,
            textvariable=self.context_var,
            values=[2048, 4096, 8192, 12288, 16384],
            width=12,
        ).grid(row=0, column=5, sticky="ew", padx=(5, 0))
    
        ttk.Label(controls, text="Optional image").grid(
            row=1, column=0, sticky="w", pady=(7, 0)
        )
        self.image_path_var = tk.StringVar()
        ttk.Entry(
            controls,
            textvariable=self.image_path_var,
        ).grid(
            row=1,
            column=1,
            columnspan=3,
            sticky="ew",
            padx=(5, 12),
            pady=(7, 0),
        )
        ttk.Button(
            controls,
            text="Browse image",
            command=self.choose_chat_image,
            style="Tool.TButton",
        ).grid(row=1, column=4, sticky="ew", pady=(7, 0))
        ttk.Button(
            controls,
            text="Clear image",
            command=lambda: self.image_path_var.set(""),
            style="Tool.TButton",
        ).grid(row=1, column=5, sticky="ew", padx=(5, 0), pady=(7, 0))
    
        actions = ttk.Frame(outer)
        actions.grid(row=1, column=0, sticky="ew", pady=(6, 6))
        self._button_grid(
            actions,
            [
                ("▶ Send prompt  (Ctrl+Enter)", self.send_chat),
                ("Clear prompt", lambda: self.user_prompt_text.delete("1.0", "end")),
                ("Clear response", lambda: self.chat_response_text.delete("1.0", "end")),
                ("Copy response", self.copy_chat_response),
            ],
            columns=4,
            primary_index=0,
        )
    
        paned = ttk.Panedwindow(outer, orient="vertical")
        paned.grid(row=2, column=0, sticky="nsew")
    
        prompt_frame = ttk.LabelFrame(paned, text="Prompts", padding=6)
        response_frame = ttk.LabelFrame(paned, text="Model response", padding=6)
        prompt_frame.grid_rowconfigure(3, weight=1)
        prompt_frame.grid_columnconfigure(0, weight=1)
        response_frame.grid_rowconfigure(0, weight=1)
        response_frame.grid_columnconfigure(0, weight=1)
    
        paned.add(prompt_frame, weight=2)
        paned.add(response_frame, weight=3)
    
        ttk.Label(prompt_frame, text="System instruction").grid(
            row=0, column=0, sticky="w"
        )
        system_scroll, self.system_prompt_text = self._scrolled_text(
            prompt_frame, height=3
        )
        system_scroll.grid(row=1, column=0, sticky="ew", pady=(2, 6))
        self.system_prompt_text.insert(
            "1.0",
            "Use only supplied facts. State uncertainty. Do not invent credentials, dates, "
            "employment history, education, legal status, or personal details.",
        )
    
        ttk.Label(
            prompt_frame,
            text="User prompt — type your request here, then press Send or Ctrl+Enter",
            style="Header.TLabel",
        ).grid(row=2, column=0, sticky="w")
        prompt_scroll, self.user_prompt_text = self._scrolled_text(
            prompt_frame, height=8
        )
        prompt_scroll.grid(row=3, column=0, sticky="nsew", pady=(2, 0))
        self.user_prompt_text.focus_set()
    
        response_scroll, self.chat_response_text = self._scrolled_text(
            response_frame, height=12
        )
        response_scroll.grid(row=0, column=0, sticky="nsew")
        self.chat_metrics_var = tk.StringVar(value="")
        ttk.Label(
            response_frame,
            textvariable=self.chat_metrics_var,
        ).grid(row=1, column=0, sticky="ew", pady=(5, 0))
    
    def _build_rag_tab(self) -> None:
        self.rag_tab.grid_rowconfigure(0, weight=1)
        self.rag_tab.grid_columnconfigure(0, weight=1)
    
        outer = ttk.Frame(self.rag_tab, padding=8)
        outer.grid(row=0, column=0, sticky="nsew")
        outer.grid_rowconfigure(2, weight=1)
        outer.grid_columnconfigure(0, weight=1)
    
        top = ttk.LabelFrame(outer, text="Knowledge sources", padding=6)
        top.grid(row=0, column=0, sticky="ew")
        top.grid_rowconfigure(0, weight=1)
        top.grid_columnconfigure(0, weight=1)
    
        list_frame = ttk.Frame(top)
        list_frame.grid(row=0, column=0, sticky="nsew")
        list_frame.grid_rowconfigure(0, weight=1)
        list_frame.grid_columnconfigure(0, weight=1)
    
        self.rag_source_list = tk.Listbox(
            list_frame,
            height=5,
            selectmode="extended",
            exportselection=False,
        )
        source_scroll = ttk.Scrollbar(
            list_frame,
            orient="vertical",
            command=self.rag_source_list.yview,
        )
        self.rag_source_list.configure(yscrollcommand=source_scroll.set)
        self.rag_source_list.grid(row=0, column=0, sticky="nsew")
        source_scroll.grid(row=0, column=1, sticky="ns")
    
        source_buttons = ttk.Frame(top)
        source_buttons.grid(row=0, column=1, sticky="nsew", padx=(7, 0))
        self._button_grid(
            source_buttons,
            [
                ("Add files", self.add_rag_files),
                ("Add folder", self.add_rag_folder),
                ("Remove selected", self.remove_rag_sources),
                ("Build / update index", self.build_rag_index),
                ("Clear index", self.clear_rag_index),
                ("Open data folder", lambda: open_folder(self.paths.data)),
            ],
            columns=2,
            primary_index=3,
        )
    
        self.rag_stats_var = tk.StringVar()
        ttk.Label(
            outer,
            textvariable=self.rag_stats_var,
        ).grid(row=1, column=0, sticky="ew", pady=(5, 4))
    
        query_frame = ttk.LabelFrame(
            outer,
            text="Semantic search and grounded answer",
            padding=7,
        )
        query_frame.grid(row=2, column=0, sticky="nsew")
        query_frame.grid_rowconfigure(2, weight=1)
        query_frame.grid_columnconfigure(1, weight=1)
    
        ttk.Label(query_frame, text="Question").grid(row=0, column=0, sticky="w")
        self.rag_query_var = tk.StringVar()
        rag_entry = ttk.Entry(query_frame, textvariable=self.rag_query_var)
        rag_entry.grid(
            row=0,
            column=1,
            columnspan=3,
            sticky="ew",
            padx=(5, 0),
        )
    
        ttk.Label(query_frame, text="Answer model").grid(
            row=1, column=0, sticky="w", pady=(6, 0)
        )
        self.rag_answer_model_var = tk.StringVar(value="qwen3.5:4b")
        ttk.Combobox(
            query_frame,
            textvariable=self.rag_answer_model_var,
            values=[m["name"] for m in MODEL_CATALOG if m["role"] != "Memory / RAG"],
        ).grid(row=1, column=1, sticky="ew", padx=(5, 7), pady=(6, 0))
    
        ttk.Button(
            query_frame,
            text="Search sources",
            command=self.search_rag,
            style="Tool.TButton",
        ).grid(row=1, column=2, sticky="ew", padx=3, pady=(6, 0))
        ttk.Button(
            query_frame,
            text="Ask with context  (Ctrl+Enter)",
            command=self.ask_rag,
            style="Primary.TButton",
        ).grid(row=1, column=3, sticky="ew", padx=(3, 0), pady=(6, 0))
    
        result_scroll, self.rag_results_text = self._scrolled_text(
            query_frame, height=14
        )
        result_scroll.grid(
            row=2,
            column=0,
            columnspan=4,
            sticky="nsew",
            pady=(7, 0),
        )
    
    def _build_profile_tab(self) -> None:
        self.profile_tab.grid_rowconfigure(0, weight=1)
        self.profile_tab.grid_columnconfigure(0, weight=1)
    
        paned = ttk.Panedwindow(self.profile_tab, orient="horizontal")
        paned.grid(row=0, column=0, sticky="nsew", padx=7, pady=7)
    
        left = ttk.LabelFrame(paned, text="Verified profile JSON", padding=7)
        right = ttk.LabelFrame(paned, text="Mapping rules JSON", padding=7)
        left.grid_rowconfigure(2, weight=1)
        left.grid_columnconfigure(0, weight=1)
        right.grid_rowconfigure(1, weight=1)
        right.grid_columnconfigure(0, weight=1)
    
        paned.add(left, weight=3)
        paned.add(right, weight=2)
    
        warning = ttk.Label(
            left,
            text=(
                "Only save information you can verify. Empty values are skipped. "
                "Sensitive and legal questions are never automatically answered."
            ),
            style="Danger.TLabel",
        )
        warning.grid(row=0, column=0, sticky="ew")
        self._responsive_wrap(warning)

        self.profile_resume_metrics_var = tk.StringVar(value="Resume metrics: calculating...")
        ttk.Label(left, textvariable=self.profile_resume_metrics_var).grid(
            row=1, column=0, sticky="ew", pady=(4, 0)
        )
    
        profile_scroll, self.profile_text = self._scrolled_text(
            left, wrap="none", height=20
        )
        profile_scroll.grid(row=2, column=0, sticky="nsew", pady=(6, 5))
    
        profile_buttons = ttk.Frame(left)
        profile_buttons.grid(row=3, column=0, sticky="ew")
        self._button_grid(
            profile_buttons,
            [
                ("Validate & save  (Ctrl+Enter)", self.save_profile),
                ("Reload profile", self._load_profile_editor),
                ("Choose resume", self.choose_resume),
                ("Load bundled 2026 resume profile", self.load_bundled_resume_profile),
                ("Open ATS scanner", lambda: self.notebook.select(self.ats_tab)),
                ("Open data folder", lambda: open_folder(self.paths.data)),
            ],
            columns=2,
            primary_index=0,
        )
    
        rules_help = ttk.Label(
            right,
            text=(
                "Aliases determine ordinary safe-field mappings. "
                "Manual-only keywords override every alias."
            ),
        )
        rules_help.grid(row=0, column=0, sticky="ew")
        self._responsive_wrap(rules_help)
    
        rules_scroll, self.rules_text = self._scrolled_text(
            right, wrap="none", height=20
        )
        rules_scroll.grid(row=1, column=0, sticky="nsew", pady=(6, 5))
    
        rules_buttons = ttk.Frame(right)
        rules_buttons.grid(row=2, column=0, sticky="ew")
        self._button_grid(
            rules_buttons,
            [
                ("Validate & save rules", self.save_rules),
                ("Reload rules", self._load_rules_editor),
                ("Restore defaults", self.restore_default_rules),
            ],
            columns=2,
            primary_index=0,
        )
    
    def _build_apply_tab(self) -> None:
        self.apply_tab.grid_rowconfigure(0, weight=1)
        self.apply_tab.grid_columnconfigure(0, weight=1)
    
        outer = ttk.Frame(self.apply_tab, padding=7)
        outer.grid(row=0, column=0, sticky="nsew")
        outer.grid_rowconfigure(2, weight=1)
        outer.grid_columnconfigure(0, weight=1)
    
        safety = ttk.LabelFrame(outer, text="Safety boundary", padding=6)
        safety.grid(row=0, column=0, sticky="ew")
        safety_label = ttk.Label(
            safety,
            text=(
                "This assistant fills only reviewed, ordinary fields from your verified profile. "
                "It never submits an application. Sensitive, legal, authorization, compensation, "
                "attestation, checkbox, radio, and uncertain fields remain manual."
            ),
            style="Danger.TLabel",
        )
        safety_label.pack(fill="x")
        self._responsive_wrap(safety_label)
    
        browser_controls = ttk.LabelFrame(
            outer,
            text="Dedicated employment browser",
            padding=6,
        )
        browser_controls.grid(row=1, column=0, sticky="ew", pady=(6, 6))
        browser_controls.grid_columnconfigure(1, weight=1)
    
        ttk.Label(browser_controls, text="Browser").grid(row=0, column=0, sticky="w")
        self.browser_choice_var = tk.StringVar(value="chrome")
        ttk.Combobox(
            browser_controls,
            textvariable=self.browser_choice_var,
            values=["chrome", "chromium"],
            state="readonly",
            width=14,
        ).grid(row=0, column=1, sticky="w", padx=(5, 8))
    
        ttk.Button(
            browser_controls,
            text="Start browser",
            command=self.start_browser,
            style="Primary.TButton",
        ).grid(row=0, column=2, sticky="ew", padx=3)
        ttk.Button(
            browser_controls,
            text="Close browser",
            command=self.stop_browser,
            style="Tool.TButton",
        ).grid(row=0, column=3, sticky="ew", padx=3)
    
        ttk.Label(browser_controls, text="Job URL").grid(
            row=1, column=0, sticky="w", pady=(6, 0)
        )
        self.job_url_var = tk.StringVar()
        ttk.Entry(
            browser_controls,
            textvariable=self.job_url_var,
        ).grid(
            row=1,
            column=1,
            columnspan=3,
            sticky="ew",
            padx=(5, 3),
            pady=(6, 0),
        )
    
        browser_actions = ttk.Frame(browser_controls)
        browser_actions.grid(
            row=2,
            column=0,
            columnspan=4,
            sticky="ew",
            pady=(5, 0),
        )
        self._button_grid(
            browser_actions,
            [
                ("Navigate", self.navigate_browser),
                ("Inspect page  (Ctrl+Enter)", self.inspect_browser),
                ("Save screenshot", self.browser_screenshot),
            ],
            columns=3,
            primary_index=1,
        )
    
        tree_frame = ttk.Frame(outer)
        tree_frame.grid(row=2, column=0, sticky="nsew")
        tree_frame.grid_rowconfigure(0, weight=1)
        tree_frame.grid_columnconfigure(0, weight=1)
    
        columns = ("status", "label", "type", "source", "proposed", "confidence", "reason")
        self.form_tree = ttk.Treeview(
            tree_frame,
            columns=columns,
            show="headings",
            selectmode="extended",
        )
        vertical = ttk.Scrollbar(tree_frame, orient="vertical", command=self.form_tree.yview)
        horizontal = ttk.Scrollbar(tree_frame, orient="horizontal", command=self.form_tree.xview)
        self.form_tree.configure(
            yscrollcommand=vertical.set,
            xscrollcommand=horizontal.set,
        )
        self.form_tree.grid(row=0, column=0, sticky="nsew")
        vertical.grid(row=0, column=1, sticky="ns")
        horizontal.grid(row=1, column=0, sticky="ew")
    
        headings = {
            "status": "Status",
            "label": "Detected field",
            "type": "Type",
            "source": "Profile source",
            "proposed": "Proposed value",
            "confidence": "Confidence",
            "reason": "Reason",
        }
        widths = {
            "status": 80,
            "label": 275,
            "type": 75,
            "source": 130,
            "proposed": 230,
            "confidence": 80,
            "reason": 360,
        }
        for column in columns:
            self.form_tree.heading(column, text=headings[column])
            self.form_tree.column(
                column,
                width=widths[column],
                minwidth=65,
                stretch=True,
            )
    
        self.form_tree.tag_configure("safe", background="#eaf8ed")
        self.form_tree.tag_configure("manual", background="#fff0e0")
        self.form_tree.tag_configure("missing", background="#fff7cc")
        self.form_tree.tag_configure("unknown", background="#f2f2f2")
        self.form_tree.tag_configure("ignored", foreground="#777777")
    
        actions = ttk.LabelFrame(outer, text="Reviewed field actions", padding=4)
        actions.grid(row=3, column=0, sticky="ew", pady=(5, 0))
        self._button_grid(
            actions,
            [
                ("Apply selected safe fields", self.apply_selected_fields),
                ("Apply all safe fields", self.apply_all_safe_fields),
                ("Focus selected field", self.focus_selected_field),
                ("Copy proposed value", self.copy_selected_proposal),
                ("AI draft for selected field", self.ai_draft_selected_field),
                ("Export inspection JSON", self.export_inspection),
            ],
            columns=3,
            primary_index=0,
        )
    
        self.browser_status_var = tk.StringVar(value="Browser not started")
        ttk.Label(
            outer,
            textvariable=self.browser_status_var,
        ).grid(row=4, column=0, sticky="ew", pady=(4, 0))
    
    def _build_logs_tab(self) -> None:
        self.logs_tab.grid_rowconfigure(0, weight=1)
        self.logs_tab.grid_columnconfigure(0, weight=1)
    
        frame = ttk.Frame(self.logs_tab, padding=7)
        frame.grid(row=0, column=0, sticky="nsew")
        frame.grid_rowconfigure(0, weight=1)
        frame.grid_columnconfigure(0, weight=1)
    
        log_scroll, self.log_text = self._scrolled_text(
            frame, wrap="none", height=20
        )
        log_scroll.grid(row=0, column=0, sticky="nsew")
    
        row = ttk.Frame(frame)
        row.grid(row=1, column=0, sticky="ew", pady=(5, 0))
        self._button_grid(
            row,
            [
                ("Clear log", lambda: self.log_text.delete("1.0", "end")),
                ("Copy log", self.copy_log),
                ("Open logs folder", lambda: open_folder(self.paths.logs)),
            ],
            columns=3,
        )
    
    def log(self, text: str) -> None:
        timestamp = datetime.now().strftime("%H:%M:%S")
        line = f"[{timestamp}] {text}\n"
        self.log_text.insert("end", line)
        self.log_text.see("end")
        log_path = self.paths.logs / f"{datetime.now():%Y-%m-%d}.log"
        try:
            with log_path.open("a", encoding="utf-8") as handle:
                handle.write(line)
        except OSError:
            pass

    def set_status(self, text: str) -> None:
        self.status_var.set(text)

    def _refresh_system_report(self) -> None:
        self.system_text.delete("1.0", "end")
        self.system_text.insert("1.0", system_report())

    def apply_environment(self) -> None:
        try:
            values = EnvironmentManager.apply_recommended()
            self._refresh_system_report()
            self.log(f"Applied environment settings: {values}")
            messagebox.showinfo(
                "Settings applied",
                "Recommended Ollama settings were saved for your user account and this process.\n\n"
                "Restart Ollama so the server reloads them.",
            )
        except Exception as exc:
            messagebox.showerror("Environment error", str(exc))

    def run_self_tests(self) -> None:
        self.command_runner.run(
            [sys.executable, str(self.project_root / "self_test.py")],
            name="Built-in self tests",
            cwd=self.project_root,
        )

    def start_ollama_server(self) -> None:
        executable = which_ollama()
        if not executable:
            messagebox.showerror(
                "Ollama not found",
                "Install Ollama and ensure ollama.exe is available on PATH.",
            )
            return
        self.command_runner.run(
            [executable, "serve"],
            name="ollama serve",
            env=os.environ.copy(),
        )

    def install_dependencies(self) -> None:
        command = [
            sys.executable,
            "-m",
            "pip",
            "install",
            "--upgrade",
            "playwright",
            "pypdf",
            "pillow",
        ]
        self.command_runner.run(command, name="Install Python dependencies")

    def install_playwright(self) -> None:
        self.command_runner.run(
            [sys.executable, "-m", "playwright", "install", "chromium"],
            name="Install Playwright Chromium",
        )

    def pull_selected_models(self) -> None:
        selected = list(self.model_tree.selection())
        if not selected:
            messagebox.showinfo("Select models", "Select one or more model rows first.")
            return
        self._pull_models(selected)

    def pull_all_models(self) -> None:
        self._pull_models([item["name"] for item in MODEL_CATALOG])

    def _pull_models(self, models: list[str]) -> None:
        executable = which_ollama()
        if not executable:
            messagebox.showerror("Ollama not found", "ollama.exe is not on PATH.")
            return
        for model in models:
            self.command_runner.run([executable, "pull", model], name=f"Pull {model}")

    def _async_refresh_ollama(self) -> None:
        self.set_status("Checking Ollama...")
        threading.Thread(target=self._refresh_ollama_worker, daemon=True).start()

    def _refresh_ollama_worker(self) -> None:
        try:
            models = self.client.list_models()
            running = self.client.running_models()
            self.events.put(
                {
                    "kind": "ollama_refreshed",
                    "models": models,
                    "running": running,
                }
            )
        except Exception as exc:
            self.events.put({"kind": "ollama_error", "error": str(exc)})

    def show_loaded_models(self) -> None:
        threading.Thread(target=self._show_loaded_worker, daemon=True).start()

    def _show_loaded_worker(self) -> None:
        try:
            running = self.client.running_models()
            self.events.put({"kind": "show_loaded", "running": running})
        except Exception as exc:
            self.events.put({"kind": "ollama_error", "error": str(exc)})

    def choose_chat_image(self) -> None:
        path = filedialog.askopenfilename(
            title="Choose image",
            filetypes=[
                ("Images", "*.png *.jpg *.jpeg *.webp *.bmp *.gif"),
                ("All files", "*.*"),
            ],
        )
        if path:
            self.image_path_var.set(path)

    def send_chat(self) -> None:
        model = self.chat_model_var.get().strip()
        prompt = self.user_prompt_text.get("1.0", "end").strip()
        system = self.system_prompt_text.get("1.0", "end").strip()
        if not model or not prompt:
            messagebox.showinfo("Missing request", "Choose a model and enter a prompt.")
            return
        self.chat_response_text.delete("1.0", "end")
        self.chat_response_text.insert("1.0", "Generating...")
        self.set_status(f"Running {model}...")
        threading.Thread(
            target=self._chat_worker,
            kwargs={
                "model": model,
                "prompt": prompt,
                "system": system,
                "image_path": self.image_path_var.get().strip(),
                "temperature": float(self.temperature_var.get()),
                "num_ctx": int(self.context_var.get()),
                "event_kind": "chat_result",
            },
            daemon=True,
        ).start()

    def _chat_worker(
        self,
        *,
        model: str,
        prompt: str,
        system: str,
        image_path: str,
        temperature: float,
        num_ctx: int,
        event_kind: str,
        extra: dict[str, Any] | None = None,
    ) -> None:
        started = time.perf_counter()
        try:
            response = self.client.chat(
                model=model,
                prompt=prompt,
                system=system,
                image_path=image_path,
                temperature=temperature,
                num_ctx=num_ctx,
            )
            self.events.put(
                {
                    "kind": event_kind,
                    "response": response,
                    "elapsed": time.perf_counter() - started,
                    "extra": extra or {},
                }
            )
        except Exception as exc:
            self.events.put(
                {
                    "kind": f"{event_kind}_error",
                    "error": f"{type(exc).__name__}: {exc}",
                    "extra": extra or {},
                }
            )

    def clear_chat(self) -> None:
        self.user_prompt_text.delete("1.0", "end")
        self.chat_response_text.delete("1.0", "end")
        self.image_path_var.set("")
        self.chat_metrics_var.set("")

    def copy_chat_response(self) -> None:
        text = self.chat_response_text.get("1.0", "end").strip()
        self.root.clipboard_clear()
        self.root.clipboard_append(text)

    def add_rag_files(self) -> None:
        paths = filedialog.askopenfilenames(title="Choose files to index")
        for name in paths:
            path = Path(name)
            if path not in self.rag_sources:
                self.rag_sources.append(path)
                self.rag_source_list.insert("end", str(path))

    def add_rag_folder(self) -> None:
        name = filedialog.askdirectory(title="Choose folder to index")
        if name:
            path = Path(name)
            if path not in self.rag_sources:
                self.rag_sources.append(path)
                self.rag_source_list.insert("end", str(path))

    def remove_rag_sources(self) -> None:
        selected = list(self.rag_source_list.curselection())
        for index in reversed(selected):
            self.rag_source_list.delete(index)
            del self.rag_sources[index]

    def build_rag_index(self) -> None:
        if not self.rag_sources:
            messagebox.showinfo("No sources", "Add files or folders first.")
            return
        self.rag_results_text.delete("1.0", "end")
        self.set_status("Building RAG index...")
        threading.Thread(target=self._build_rag_worker, daemon=True).start()

    def _build_rag_worker(self) -> None:
        def progress(text: str) -> None:
            self.events.put({"kind": "rag_progress", "text": text})

        try:
            result = self.rag.index_files(
                self.rag_sources,
                model="embeddinggemma",
                progress=progress,
            )
            self.events.put({"kind": "rag_indexed", "result": result})
        except Exception as exc:
            self.events.put({"kind": "rag_error", "error": f"{type(exc).__name__}: {exc}"})

    def _refresh_rag_stats(self) -> None:
        stats = self.rag.stats()
        self.rag_stats_var.set(
            f"Index: {stats['documents']} documents, {stats['chunks']} embedded chunks"
        )

    def clear_rag_index(self) -> None:
        if messagebox.askyesno("Clear index", "Delete every indexed document and vector?"):
            self.rag.clear()
            self._refresh_rag_stats()
            self.rag_results_text.delete("1.0", "end")

    def search_rag(self) -> None:
        query = self.rag_query_var.get().strip()
        if not query:
            return
        self.rag_results_text.delete("1.0", "end")
        self.set_status("Searching embeddings...")
        threading.Thread(target=self._search_rag_worker, args=(query, False), daemon=True).start()

    def ask_rag(self) -> None:
        query = self.rag_query_var.get().strip()
        if not query:
            return
        self.rag_results_text.delete("1.0", "end")
        self.set_status("Retrieving context...")
        threading.Thread(target=self._search_rag_worker, args=(query, True), daemon=True).start()

    def _search_rag_worker(self, query: str, ask: bool) -> None:
        try:
            hits = self.rag.search(query, model="embeddinggemma", limit=8)
            if not ask:
                self.events.put({"kind": "rag_search_result", "query": query, "hits": hits})
                return
            context_parts = []
            for index, hit in enumerate(hits, start=1):
                context_parts.append(
                    f"[SOURCE {index}: {hit.path} | chunk {hit.chunk_index} | "
                    f"similarity {hit.score:.4f}]\n{hit.text}"
                )
            context = "\n\n".join(context_parts)
            prompt = (
                f"QUESTION:\n{query}\n\nRETRIEVED SOURCES:\n{context}\n\n"
                "Answer only from the retrieved sources. Cite sources inline as [SOURCE N]. "
                "When the sources do not contain an answer, say exactly what is missing."
            )
            self._chat_worker(
                model=self.rag_answer_model_var.get().strip(),
                prompt=prompt,
                system=(
                    "You are a grounded retrieval assistant. Never invent facts. "
                    "Use only the supplied sources and preserve uncertainty."
                ),
                image_path="",
                temperature=0.1,
                num_ctx=8192,
                event_kind="rag_answer",
                extra={"query": query, "hits": hits},
            )
        except Exception as exc:
            self.events.put({"kind": "rag_error", "error": f"{type(exc).__name__}: {exc}"})

    def _load_profile_editor(self) -> None:
        self.profile = AtomicJSON.load(self.paths.profile_json, default_profile())
        self.profile_text.delete("1.0", "end")
        self.profile_text.insert("1.0", json.dumps(self.profile, indent=2, ensure_ascii=False))
        self._refresh_profile_resume_metrics()

    def _refresh_profile_resume_metrics(self) -> None:
        if not hasattr(self, "profile_resume_metrics_var"):
            return
        resume_path = Path(
            str(self.profile.get("documents", {}).get("resume_path", "") or self.bundled_resume_path)
        ).expanduser()
        try:
            text, pages, _ = extract_pdf_text(resume_path)
            report = analyze_resume(text, pages=pages)
            metrics = profile_metrics(self.profile, report)
            self.profile_resume_metrics_var.set(
                "Resume profile: "
                f"{metrics['skills']} skills, {metrics['work_history_entries']} work entries, "
                f"{metrics['education_entries']} education entries, {metrics['resume_pages']} pages, "
                f"{metrics['resume_words']} words, baseline diagnostic {metrics['ats_baseline_score']:.1f}/100"
            )
        except Exception as exc:
            metrics = profile_metrics(self.profile)
            self.profile_resume_metrics_var.set(
                "Profile metrics: "
                f"{metrics['skills']} skills, {metrics['work_history_entries']} work entries; "
                f"resume scan unavailable ({exc})"
            )

    def _load_rules_editor(self) -> None:
        self.rules = AtomicJSON.load(self.paths.rules_json, default_rules())
        self.rules_text.delete("1.0", "end")
        self.rules_text.insert("1.0", json.dumps(self.rules, indent=2, ensure_ascii=False))

    def save_profile(self) -> None:
        try:
            data = json.loads(self.profile_text.get("1.0", "end"))
            if not isinstance(data, dict):
                raise ValueError("Profile root must be a JSON object.")
            AtomicJSON.save(self.paths.profile_json, data)
            self.profile = data
            self._refresh_profile_resume_metrics()
            self.log(f"Saved verified profile to {self.paths.profile_json}")
            messagebox.showinfo("Profile saved", "Profile JSON is valid and saved.")
        except Exception as exc:
            messagebox.showerror("Invalid profile JSON", str(exc))

    def save_rules(self) -> None:
        try:
            data = json.loads(self.rules_text.get("1.0", "end"))
            if not isinstance(data, dict):
                raise ValueError("Rules root must be a JSON object.")
            AtomicJSON.save(self.paths.rules_json, data)
            self.rules = data
            self.log(f"Saved mapping rules to {self.paths.rules_json}")
            messagebox.showinfo("Rules saved", "Mapping rules are valid and saved.")
        except Exception as exc:
            messagebox.showerror("Invalid rules JSON", str(exc))

    def restore_default_rules(self) -> None:
        if messagebox.askyesno("Restore defaults", "Replace the mapping rules with defaults?"):
            self.rules = default_rules()
            AtomicJSON.save(self.paths.rules_json, self.rules)
            self._load_rules_editor()

    def choose_resume(self) -> None:
        path = filedialog.askopenfilename(
            title="Choose verified resume",
            filetypes=[
                ("Documents", "*.pdf *.doc *.docx *.txt"),
                ("All files", "*.*"),
            ],
        )
        if not path:
            return
        try:
            data = json.loads(self.profile_text.get("1.0", "end"))
            data.setdefault("documents", {})["resume_path"] = path
            self.profile_text.delete("1.0", "end")
            self.profile_text.insert("1.0", json.dumps(data, indent=2, ensure_ascii=False))
        except Exception as exc:
            messagebox.showerror("Profile JSON error", str(exc))

    def start_browser(self) -> None:
        self.browser.send("start", browser=self.browser_choice_var.get())
        self.browser_status_var.set("Starting dedicated browser...")

    def navigate_browser(self) -> None:
        url = self.job_url_var.get().strip()
        if not url:
            return
        self.browser.send("navigate", url=url)
        self.browser_status_var.set(f"Navigating to {url}...")

    def inspect_browser(self) -> None:
        if not self.save_profile_silently():
            return
        self.browser.send("inspect")
        self.browser_status_var.set("Inspecting visible form controls...")

    def save_profile_silently(self) -> bool:
        try:
            data = json.loads(self.profile_text.get("1.0", "end"))
            AtomicJSON.save(self.paths.profile_json, data)
            self.profile = data
            rules = json.loads(self.rules_text.get("1.0", "end"))
            AtomicJSON.save(self.paths.rules_json, rules)
            self.rules = rules
            return True
        except Exception as exc:
            messagebox.showerror("Invalid profile or rules JSON", str(exc))
            return False

    def browser_screenshot(self) -> None:
        path = self.paths.downloads / f"job-page-{datetime.now():%Y%m%d-%H%M%S}.png"
        self.browser.send("screenshot", path=str(path))

    def stop_browser(self) -> None:
        if self.browser.is_alive():
            self.browser.send("close")
        self.browser_status_var.set("Closing browser...")

    def _populate_form_tree(self, fields: list[dict[str, Any]]) -> None:
        mapper = FieldMapper(self.profile, self.rules)
        self.form_mappings = mapper.map_all(fields)
        self.form_mapping_by_iid.clear()
        for iid in self.form_tree.get_children():
            self.form_tree.delete(iid)
        for index, mapping in enumerate(self.form_mappings):
            iid = f"field-{index}"
            self.form_mapping_by_iid[iid] = mapping
            label = (
                mapping.get("label")
                or mapping.get("placeholder")
                or mapping.get("name")
                or mapping.get("id")
                or "(unlabeled)"
            )
            proposed = mapping.get("proposed", "")
            if mapping.get("type") == "file" and proposed:
                proposed = str(Path(str(proposed)).name)
            self.form_tree.insert(
                "",
                "end",
                iid=iid,
                values=(
                    mapping.get("status", ""),
                    str(label)[:180],
                    mapping.get("type", ""),
                    mapping.get("source", ""),
                    str(proposed)[:180],
                    f"{float(mapping.get('confidence', 0)):.2f}",
                    mapping.get("reason", ""),
                ),
                tags=(mapping.get("status", "unknown"),),
            )
        counts: dict[str, int] = {}
        for mapping in self.form_mappings:
            counts[mapping["status"]] = counts.get(mapping["status"], 0) + 1
        self.browser_status_var.set(
            "Inspected "
            + str(len(self.form_mappings))
            + " fields — "
            + ", ".join(f"{key}: {value}" for key, value in sorted(counts.items()))
        )

    def selected_mappings(self) -> list[dict[str, Any]]:
        return [
            self.form_mapping_by_iid[iid]
            for iid in self.form_tree.selection()
            if iid in self.form_mapping_by_iid
        ]

    def apply_selected_fields(self) -> None:
        mappings = [m for m in self.selected_mappings() if m.get("status") == "safe"]
        if not mappings:
            messagebox.showinfo("No safe fields", "Select one or more rows marked safe.")
            return
        if not messagebox.askyesno(
            "Apply reviewed fields",
            f"Fill {len(mappings)} selected safe field(s) in the browser?\n\n"
            "Review the page afterward. This does not submit anything.",
        ):
            return
        for mapping in mappings:
            self.browser.send("fill", mapping=mapping)

    def apply_all_safe_fields(self) -> None:
        mappings = [m for m in self.form_mappings if m.get("status") == "safe"]
        if not mappings:
            messagebox.showinfo("No safe fields", "No safe profile mappings are available.")
            return
        preview = "\n".join(
            f"• {m.get('label') or m.get('name')}: {m.get('source')}"
            for m in mappings[:20]
        )
        if len(mappings) > 20:
            preview += f"\n• ...and {len(mappings) - 20} more"
        if not messagebox.askyesno(
            "Apply all safe fields",
            f"Fill these {len(mappings)} fields?\n\n{preview}\n\n"
            "The final submit button is never clicked.",
        ):
            return
        for mapping in mappings:
            self.browser.send("fill", mapping=mapping)

    def focus_selected_field(self) -> None:
        mappings = self.selected_mappings()
        if len(mappings) != 1:
            messagebox.showinfo("Select one", "Select exactly one field.")
            return
        self.browser.send("focus", mapping=mappings[0])

    def copy_selected_proposal(self) -> None:
        mappings = self.selected_mappings()
        if len(mappings) != 1:
            messagebox.showinfo("Select one", "Select exactly one field.")
            return
        value = str(mappings[0].get("proposed", ""))
        self.root.clipboard_clear()
        self.root.clipboard_append(value)

    def ai_draft_selected_field(self) -> None:
        mappings = self.selected_mappings()
        if len(mappings) != 1:
            messagebox.showinfo("Select one", "Select exactly one field.")
            return
        mapping = mappings[0]
        if mapping.get("status") == "manual":
            messagebox.showwarning(
                "Manual field",
                "This field is classified as sensitive/legal/manual and is not sent to the model.",
            )
            return
        field_type = mapping.get("type")
        if field_type not in {"text", "textarea", "url", "search", "email", "tel"}:
            messagebox.showinfo("Unsupported field", "AI drafting is for ordinary text fields only.")
            return
        question = (
            mapping.get("label")
            or mapping.get("placeholder")
            or mapping.get("name")
            or mapping.get("id")
        )
        profile_json = json.dumps(self.profile, ensure_ascii=False, indent=2)
        prompt = (
            f"APPLICATION FIELD:\n{question}\n\nVERIFIED PROFILE:\n{profile_json}\n\n"
            "Draft a concise answer for the application field. Use only facts explicitly present "
            "in the verified profile. Do not infer dates, credentials, experience, legal status, "
            "salary, demographics, authorization, or anything missing. If the profile does not "
            "support an answer, output exactly: NEEDS MANUAL ANSWER"
        )
        self.set_status("Drafting from verified profile...")
        self._chat_worker(
            model=self.chat_model_var.get().strip() or "qwen3.5:4b",
            prompt=prompt,
            system=(
                "You draft user-controlled job application text from verified facts only. "
                "Never fabricate or decide whether the user is qualified."
            ),
            image_path="",
            temperature=0.1,
            num_ctx=8192,
            event_kind="field_draft",
            extra={"mapping": mapping},
        )

    def export_inspection(self) -> None:
        if not self.form_mappings:
            messagebox.showinfo("Nothing to export", "Inspect a page first.")
            return
        path = filedialog.asksaveasfilename(
            title="Export inspection",
            defaultextension=".json",
            initialfile="job_form_inspection.json",
            filetypes=[("JSON", "*.json")],
        )
        if path:
            Path(path).write_text(
                json.dumps(self.form_mappings, indent=2, ensure_ascii=False),
                encoding="utf-8",
            )

    def copy_log(self) -> None:
        text = self.log_text.get("1.0", "end").strip()
        self.root.clipboard_clear()
        self.root.clipboard_append(text)

    def _poll_events(self) -> None:
        try:
            while True:
                event = self.events.get_nowait()
                self._handle_event(event)
        except queue.Empty:
            pass
        self.root.after(100, self._poll_events)

    def _handle_event(self, event: dict[str, Any]) -> None:
        if self.handle_ats_event(event):
            return
        if self.handle_visual_event(event):
            return
        kind = event.get("kind", "")
        if event.get("source") == "browser":
            self._handle_browser_event(event)
            return

        if kind == "command_started":
            self.log(f"Started {event['name']}: {' '.join(event['command'])}")
            self.set_status(event["name"])
        elif kind == "command_output":
            self.log(f"{event['name']}: {event['text']}")
        elif kind == "command_finished":
            self.log(f"{event['name']} finished with code {event['return_code']}")
            self.set_status("Ready")
            self._async_refresh_ollama()
        elif kind == "command_error":
            self.log(f"{event['name']} ERROR: {event['error']}")
            self.set_status("Command failed")
        elif kind == "ollama_refreshed":
            models = event["models"]
            running = event["running"]
            self.installed_models = [str(m.get("name", "")) for m in models]
            installed_bases = {name.split(":")[0] for name in self.installed_models}
            for item in MODEL_CATALOG:
                name = item["name"]
                installed = (
                    name in self.installed_models
                    or name.split(":")[0] in installed_bases
                )
                self.model_tree.set(name, "installed", "Yes" if installed else "No")
            model_values = sorted(set(self.installed_models + [m["name"] for m in MODEL_CATALOG]))
            self.chat_model_combo["values"] = model_values
            if hasattr(self, "visual_vision_combo"):
                self.visual_vision_combo["values"] = model_values
            if hasattr(self, "visual_text_combo"):
                self.visual_text_combo["values"] = model_values
            self.ollama_status_var.set(
                f"Ollama online — {len(models)} installed, {len(running)} currently loaded"
            )
            self.set_status("Ollama online")
            self.log(f"Ollama online; installed models: {', '.join(self.installed_models) or 'none'}")
        elif kind == "ollama_error":
            self.ollama_status_var.set(f"Ollama unavailable — {event['error']}")
            self.set_status("Ollama unavailable")
            self.log(f"Ollama error: {event['error']}")
        elif kind == "show_loaded":
            running = event["running"]
            if not running:
                messagebox.showinfo("Loaded models", "No models are currently loaded.")
            else:
                lines = []
                for item in running:
                    size_vram = item.get("size_vram", 0) / (1024 ** 3)
                    lines.append(
                        f"{item.get('name')} — VRAM {size_vram:.2f} GiB — "
                        f"expires {item.get('expires_at', '')}"
                    )
                messagebox.showinfo("Loaded models", "\n".join(lines))
        elif kind == "chat_result":
            response = event["response"]
            content = response.get("message", {}).get("content", "")
            thinking = response.get("message", {}).get("thinking", "")
            output = content
            if thinking:
                output = f"[Thinking returned by model]\n{thinking}\n\n[Answer]\n{content}"
            self.chat_response_text.delete("1.0", "end")
            self.chat_response_text.insert("1.0", output)
            eval_count = response.get("eval_count", 0)
            eval_duration = response.get("eval_duration", 0)
            tokens_per_second = (
                eval_count / (eval_duration / 1_000_000_000)
                if eval_count and eval_duration
                else 0
            )
            self.chat_metrics_var.set(
                f"Elapsed {event['elapsed']:.2f}s | prompt tokens "
                f"{response.get('prompt_eval_count', 0)} | output tokens {eval_count} | "
                f"{tokens_per_second:.2f} tokens/s"
            )
            self.set_status("Ready")
        elif kind == "chat_result_error":
            self.chat_response_text.delete("1.0", "end")
            self.chat_response_text.insert("1.0", event["error"])
            self.set_status("Model request failed")
        elif kind == "rag_progress":
            self.rag_results_text.insert("end", event["text"] + "\n")
            self.rag_results_text.see("end")
        elif kind == "rag_indexed":
            self.rag_results_text.insert(
                "end", "\nFinished:\n" + json.dumps(event["result"], indent=2)
            )
            self._refresh_rag_stats()
            self.set_status("RAG index updated")
        elif kind == "rag_search_result":
            self.rag_results_text.delete("1.0", "end")
            hits = event["hits"]
            for number, hit in enumerate(hits, start=1):
                self.rag_results_text.insert(
                    "end",
                    f"===== RESULT {number} | similarity {hit.score:.4f} =====\n"
                    f"{hit.path} | chunk {hit.chunk_index}\n\n{hit.text}\n\n",
                )
            self.set_status("Search complete")
        elif kind == "rag_answer":
            response = event["response"]
            answer = response.get("message", {}).get("content", "")
            self.rag_results_text.delete("1.0", "end")
            self.rag_results_text.insert("1.0", answer + "\n\n===== RETRIEVED SOURCES =====\n")
            for number, hit in enumerate(event["extra"].get("hits", []), start=1):
                self.rag_results_text.insert(
                    "end",
                    f"\n[SOURCE {number}] {hit.path} | chunk {hit.chunk_index} | "
                    f"similarity {hit.score:.4f}\n",
                )
            self.set_status("Grounded answer complete")
        elif kind in {"rag_error", "rag_answer_error"}:
            self.rag_results_text.insert("end", "\nERROR: " + event["error"])
            self.set_status("RAG failed")
        elif kind == "field_draft":
            content = event["response"].get("message", {}).get("content", "").strip()
            mapping = event["extra"]["mapping"]
            if content == "NEEDS MANUAL ANSWER" or not content:
                messagebox.showwarning(
                    "Manual answer needed",
                    "The verified profile does not support an answer for this field.",
                )
            else:
                approved = messagebox.askyesno(
                    "Review AI draft",
                    f"Field:\n{mapping.get('label') or mapping.get('name')}\n\n"
                    f"Draft:\n{content}\n\nApply this reviewed draft to the browser field?",
                )
                if approved:
                    revised = simpledialog.askstring(
                        "Edit before applying",
                        "Edit the answer if needed:",
                        initialvalue=content,
                        parent=self.root,
                    )
                    if revised is not None:
                        reviewed = dict(mapping)
                        reviewed["proposed"] = revised
                        reviewed["source"] = "AI draft reviewed by user"
                        reviewed["status"] = "safe"
                        self.browser.send("fill", mapping=reviewed)
            self.set_status("Ready")
        elif kind == "field_draft_error":
            messagebox.showerror("Draft failed", event["error"])
            self.set_status("Draft failed")

    def _handle_browser_event(self, event: dict[str, Any]) -> None:
        kind = event.get("kind")
        if kind == "started":
            self.browser_status_var.set("Dedicated browser started")
            self.log("Dedicated employment browser started")
        elif kind == "navigated":
            self.job_url_var.set(event.get("url", ""))
            self.browser_status_var.set(f"Loaded: {event.get('title', '')}")
            self.log(f"Browser navigated to {event.get('url')}")
        elif kind == "inspected":
            self.job_url_var.set(event.get("url", ""))
            self._populate_form_tree(event.get("fields", []))
            self.log(f"Inspected {len(event.get('fields', []))} visible form controls")
        elif kind == "filled":
            self.browser_status_var.set(
                f"Filled reviewed field from {event.get('source')}"
            )
            self.log(
                f"Filled browser field from {event.get('source')}: {event.get('value')}"
            )
        elif kind == "focused":
            self.browser_status_var.set("Focused selected field")
        elif kind == "screenshot_saved":
            self.browser_status_var.set(f"Screenshot saved: {event.get('path')}")
            self.log(f"Browser screenshot saved: {event.get('path')}")
        elif kind == "error":
            self.browser_status_var.set("Browser error")
            self.log(f"Browser ERROR: {event.get('message')}")
            messagebox.showerror("Browser error", event.get("message", "Unknown error"))
        elif kind == "stopped":
            self.browser_status_var.set("Browser stopped")
            self.log("Dedicated browser stopped")

    def on_close(self) -> None:
        try:
            if self.browser.is_alive():
                self.browser.send("shutdown")
                self.browser.join(timeout=3)
        except Exception:
            pass
        self.command_runner.terminate_all()
        self.root.destroy()
