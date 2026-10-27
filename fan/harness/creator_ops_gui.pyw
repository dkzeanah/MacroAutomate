#!/usr/bin/env python3
"""Desktop control room for the creator operations companion suite."""

from __future__ import annotations

import json
import os
import queue
import subprocess
import sys
import threading
import tkinter as tk
from dataclasses import asdict, replace
from datetime import datetime
from pathlib import Path
from tkinter import filedialog, messagebox, scrolledtext, ttk
from typing import Any, Callable

import creator_ops as ops
import ollama_preprompt as orchestrator


GUIDE_TEXT = """START HERE

1. Install and start Ollama. Pull at least one text model, such as qwen3:8b.
2. Open Content Studio, choose a topic, add your goal and source URLs, then click Generate local brief.
3. Edit the brief. Ollama's output is planning help, not a factual source.
4. Supply your own image/video/audio. This suite does not generate creator media.
5. Save, review every claim, then click Human approve current draft.
6. Add official API accounts under Queue & Accounts. Store only the name of the environment variable containing each access token.
7. Schedule an approved draft. Preview due packages before enabling any live API write.
8. Record aggregate results under Metrics & Experiments. Use experiments to compare framing, not unrelated claims.

PUBLISHING SAFETY

Dry-run is the default. Live publishing requires CREATOR_OPS_LIVE_PUBLISH=1 in the environment before this app starts, a current human approval, an enabled account, a due schedule, and a credential in the account's token environment variable. Facebook support is Pages only. Instagram requires a professional account and a public creator-owned image URL. TikTok requires an approved Content Posting API application; unaudited clients are generally restricted to private visibility.

The suite does not automate personal profiles, browser interfaces, fake forum posts, engagement rings, impersonation, or person-level commenter tracking. You may paste observations from material you are authorized to use, but store only aggregate themes and sentiment.

DEEPSEEK

The paid review button sends the current local brief to DeepSeek Harness only after confirmation. The API key typed here is kept in memory for this window and is not written to SQLite. Local brief generation, scheduling, dry-run packages, metrics, and insights do not require DeepSeek.

DATA

The SQLite database defaults to your local application-data directory. Access tokens are never stored in it. Back up the database if the planning history matters to you. The deployment guide beside this script contains platform setup and Windows Task Scheduler instructions.
"""


class CreatorOpsGui(ttk.Frame):
    """Tk dashboard that keeps creator approval visible in every publish path."""

    def __init__(self, root: tk.Tk, *, database_path: Path | None = None) -> None:
        super().__init__(root, padding=10)
        self.root = root
        self.root.title("Ollama + DeepSeek Creator Operations")
        self.root.geometry("1180x820")
        self.root.minsize(980, 680)
        self.grid(sticky="nsew")
        root.columnconfigure(0, weight=1)
        root.rowconfigure(0, weight=1)
        self.columnconfigure(0, weight=1)
        self.rowconfigure(1, weight=1)

        self.database_path = database_path or ops.default_database_path()
        self.store = ops.CreatorStore(self.database_path)
        self.events: queue.Queue[tuple[str, str, object]] = queue.Queue()
        self.active_job: str | None = None
        self.current_brief: ops.ContentBrief | None = None
        self.current_content_id: int | None = None
        self.topic_rows: dict[str, Any] = {}
        self.content_rows: dict[str, Any] = {}
        self.account_rows: dict[str, Any] = {}
        self.destination_rows: dict[str, Any] = {}
        self.status_var = tk.StringVar(value=f"Ready — data: {self.database_path}")

        self._build_header()
        self.notebook = ttk.Notebook(self)
        self.notebook.grid(row=1, column=0, sticky="nsew", pady=(10, 8))
        self.dashboard_tab = ttk.Frame(self.notebook, padding=12)
        self.studio_tab = ttk.Frame(self.notebook, padding=12)
        self.queue_tab = ttk.Frame(self.notebook, padding=12)
        self.metrics_tab = ttk.Frame(self.notebook, padding=12)
        self.guide_tab = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(self.dashboard_tab, text="Dashboard & Topics")
        self.notebook.add(self.studio_tab, text="Content Studio")
        self.notebook.add(self.queue_tab, text="Queue & Accounts")
        self.notebook.add(self.metrics_tab, text="Metrics & Experiments")
        self.notebook.add(self.guide_tab, text="Setup & Guide")
        self._build_dashboard()
        self._build_studio()
        self._build_queue()
        self._build_metrics()
        self._build_guide()
        ttk.Label(self, textvariable=self.status_var, anchor="w").grid(row=2, column=0, sticky="ew")
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)
        self.root.after(75, self._poll_events)
        self.refresh_all()

    def _build_header(self) -> None:
        header = ttk.Frame(self)
        header.grid(row=0, column=0, sticky="ew")
        header.columnconfigure(0, weight=1)
        ttk.Label(header, text="Creator Operations", font=("Segoe UI", 18, "bold")).grid(row=0, column=0, sticky="w")
        ttk.Label(
            header,
            text="Local-first briefs • human approval • official APIs • aggregate learning",
        ).grid(row=1, column=0, sticky="w")
        self.refresh_button = ttk.Button(header, text="Refresh all", command=self.refresh_all)
        self.refresh_button.grid(row=0, column=1, rowspan=2, padx=(12, 0))

    def _build_dashboard(self) -> None:
        tab = self.dashboard_tab
        tab.columnconfigure(0, weight=1)
        tab.rowconfigure(2, weight=2)
        tab.rowconfigure(4, weight=1)
        self.summary_var = tk.StringVar()
        ttk.Label(tab, textvariable=self.summary_var, font=("Segoe UI", 11, "bold")).grid(row=0, column=0, sticky="ew")
        ttk.Label(
            tab,
            text="Ten starter topics inferred from your supplied interests. Edit the generated draft; the topic is not a claim or script.",
            wraplength=1050,
        ).grid(row=1, column=0, sticky="w", pady=(8, 10))
        self.topic_tree = ttk.Treeview(
            tab,
            columns=("topic", "value", "tension", "safety"),
            show="headings",
            selectmode="browse",
        )
        for name, label, width in (
            ("topic", "Topic", 260),
            ("value", "Audience value", 270),
            ("tension", "Honest tension", 280),
            ("safety", "Publishing guardrail", 300),
        ):
            self.topic_tree.heading(name, text=label)
            self.topic_tree.column(name, width=width, minwidth=140, stretch=True)
        self.topic_tree.grid(row=2, column=0, sticky="nsew")
        scroll = ttk.Scrollbar(tab, orient=tk.VERTICAL, command=self.topic_tree.yview)
        scroll.grid(row=2, column=1, sticky="ns")
        self.topic_tree.configure(yscrollcommand=scroll.set)
        research = ttk.LabelFrame(
            tab,
            text="Authorized research inbox — aggregate themes only",
            padding=8,
        )
        research.grid(row=3, column=0, columnspan=2, sticky="ew", pady=(10, 8))
        research.columnconfigure(1, weight=1)
        research.columnconfigure(3, weight=1)
        self.research_topic_var = tk.StringVar()
        self.research_url_var = tk.StringVar()
        self.research_type_var = tk.StringVar(value="official article")
        self.research_sentiment_var = tk.StringVar(value="mixed")
        self.research_rights_var = tk.StringVar(value="Public source reviewed manually")
        ttk.Label(research, text="Topic").grid(row=0, column=0, sticky="w")
        self.research_topic_combo = ttk.Combobox(research, textvariable=self.research_topic_var, state="readonly")
        self.research_topic_combo.grid(row=0, column=1, sticky="ew", padx=(5, 10))
        ttk.Label(research, text="Source URL").grid(row=0, column=2, sticky="w")
        ttk.Entry(research, textvariable=self.research_url_var).grid(row=0, column=3, sticky="ew", padx=(5, 10))
        ttk.Label(research, text="Source type").grid(row=1, column=0, sticky="w", pady=(6, 0))
        ttk.Combobox(
            research,
            textvariable=self.research_type_var,
            values=("official article", "public analytics", "authorized export", "creator note", "manual trend sample"),
        ).grid(row=1, column=1, sticky="ew", padx=(5, 10), pady=(6, 0))
        ttk.Label(research, text="Aggregate sentiment").grid(row=1, column=2, sticky="w", pady=(6, 0))
        ttk.Combobox(
            research,
            textvariable=self.research_sentiment_var,
            values=("positive", "mixed", "negative", "unknown"),
            state="readonly",
        ).grid(row=1, column=3, sticky="ew", padx=(5, 10), pady=(6, 0))
        ttk.Label(research, text="Aggregate themes / recurring questions").grid(row=2, column=0, sticky="nw", pady=(6, 0))
        self.research_notes_text = tk.Text(research, height=3, wrap=tk.WORD)
        self.research_notes_text.grid(row=2, column=1, sticky="ew", padx=(5, 10), pady=(6, 0))
        ttk.Label(research, text="Rights / authorization basis").grid(row=2, column=2, sticky="nw", pady=(6, 0))
        rights_frame = ttk.Frame(research)
        rights_frame.grid(row=2, column=3, sticky="ew", padx=(5, 10), pady=(6, 0))
        rights_frame.columnconfigure(0, weight=1)
        ttk.Entry(rights_frame, textvariable=self.research_rights_var).grid(row=0, column=0, sticky="ew")
        ttk.Button(rights_frame, text="Record", command=self._add_observation).grid(row=0, column=1, padx=(8, 0))
        self.observation_tree = ttk.Treeview(
            tab,
            columns=("captured", "topic", "type", "sentiment", "notes", "rights"),
            show="headings",
        )
        for name, label, width in (
            ("captured", "Captured", 145), ("topic", "Topic", 190), ("type", "Source type", 110),
            ("sentiment", "Sentiment", 75), ("notes", "Aggregate themes", 310), ("rights", "Authorization", 210),
        ):
            self.observation_tree.heading(name, text=label)
            self.observation_tree.column(name, width=width, stretch=name in {"notes", "rights"})
        self.observation_tree.grid(row=4, column=0, columnspan=2, sticky="nsew")

    def _build_studio(self) -> None:
        tab = self.studio_tab
        tab.columnconfigure(1, weight=1)
        tab.columnconfigure(3, weight=1)
        tab.rowconfigure(8, weight=1)

        self.topic_var = tk.StringVar()
        self.format_var = tk.StringVar(value="short video")
        self.goal_var = tk.StringVar(value="Teach one useful idea and invite a substantive response.")
        self.ollama_url_var = tk.StringVar(value=ops.DEFAULT_OLLAMA_URL)
        self.model_var = tk.StringVar()
        self.deepseek_key_var = tk.StringVar()
        self.deepseek_base_var = tk.StringVar(value=os.environ.get("DEEPSEEK_BASE_URL", ""))
        self.deepseek_model_var = tk.StringVar(value="deepseek-chat")
        self.deepseek_provider_var = tk.StringVar(value="deepseek")

        ttk.Label(tab, text="Topic").grid(row=0, column=0, sticky="w")
        self.topic_combo = ttk.Combobox(tab, textvariable=self.topic_var, state="readonly")
        self.topic_combo.grid(row=0, column=1, sticky="ew", padx=(8, 14))
        ttk.Label(tab, text="Format").grid(row=0, column=2, sticky="w")
        ttk.Combobox(
            tab,
            textvariable=self.format_var,
            values=("short video", "long video", "text post", "carousel", "photo post", "live outline"),
            state="readonly",
        ).grid(row=0, column=3, sticky="ew", padx=(8, 0))
        ttk.Label(tab, text="Creator goal").grid(row=1, column=0, sticky="w", pady=(8, 0))
        ttk.Entry(tab, textvariable=self.goal_var).grid(row=1, column=1, columnspan=3, sticky="ew", padx=(8, 0), pady=(8, 0))

        ttk.Label(tab, text="Source URLs (one per line)").grid(row=2, column=0, sticky="nw", pady=(8, 0))
        self.sources_text = tk.Text(tab, height=3, wrap=tk.WORD)
        self.sources_text.grid(row=2, column=1, sticky="ew", padx=(8, 14), pady=(8, 0))
        ttk.Label(tab, text="Creator notes / experience").grid(row=2, column=2, sticky="nw", pady=(8, 0))
        self.notes_text = tk.Text(tab, height=3, wrap=tk.WORD)
        self.notes_text.grid(row=2, column=3, sticky="ew", padx=(8, 0), pady=(8, 0))

        connection = ttk.LabelFrame(tab, text="Local AI and optional paid review", padding=8)
        connection.grid(row=3, column=0, columnspan=4, sticky="ew", pady=(10, 8))
        connection.columnconfigure(1, weight=1)
        connection.columnconfigure(3, weight=1)
        ttk.Label(connection, text="Ollama URL").grid(row=0, column=0, sticky="w")
        ttk.Entry(connection, textvariable=self.ollama_url_var).grid(row=0, column=1, sticky="ew", padx=(6, 12))
        ttk.Label(connection, text="Model").grid(row=0, column=2, sticky="w")
        self.model_combo = ttk.Combobox(connection, textvariable=self.model_var, state="readonly")
        self.model_combo.grid(row=0, column=3, sticky="ew", padx=(6, 8))
        self.models_button = ttk.Button(connection, text="Find models", command=self._refresh_models)
        self.models_button.grid(row=0, column=4)
        ttk.Label(connection, text="DeepSeek key (not saved)").grid(row=1, column=0, sticky="w", pady=(8, 0))
        ttk.Entry(connection, textvariable=self.deepseek_key_var, show="•").grid(row=1, column=1, sticky="ew", padx=(6, 12), pady=(8, 0))
        ttk.Label(connection, text="Base URL (optional)").grid(row=1, column=2, sticky="w", pady=(8, 0))
        ttk.Entry(connection, textvariable=self.deepseek_base_var).grid(row=1, column=3, sticky="ew", padx=(6, 8), pady=(8, 0))

        actions = ttk.Frame(tab)
        actions.grid(row=4, column=0, columnspan=4, sticky="ew")
        self.generate_button = ttk.Button(actions, text="Generate local brief", command=self._generate_brief)
        self.generate_button.pack(side=tk.LEFT)
        self.save_button = ttk.Button(actions, text="Save draft", command=self._save_draft)
        self.save_button.pack(side=tk.LEFT, padx=8)
        self.approve_button = ttk.Button(actions, text="Human approve current draft", command=self._approve_draft)
        self.approve_button.pack(side=tk.LEFT)
        self.review_button = ttk.Button(actions, text="DeepSeek review (paid)", command=self._deepseek_review)
        self.review_button.pack(side=tk.LEFT, padx=8)
        ttk.Button(actions, text="New / clear", command=self._clear_studio).pack(side=tk.RIGHT)

        ttk.Label(tab, text="Saved draft").grid(row=5, column=0, sticky="w", pady=(8, 0))
        self.content_var = tk.StringVar()
        self.content_combo = ttk.Combobox(tab, textvariable=self.content_var, state="readonly")
        self.content_combo.grid(row=5, column=1, columnspan=2, sticky="ew", padx=(8, 8), pady=(8, 0))
        self.content_combo.bind("<<ComboboxSelected>>", lambda _event: self._load_selected_content())
        ttk.Button(tab, text="Load", command=self._load_selected_content).grid(row=5, column=3, sticky="w", pady=(8, 0))

        self.title_var = tk.StringVar()
        self.experiment_var = tk.StringVar()
        self.variant_var = tk.StringVar()
        self.media_url_var = tk.StringVar()
        ttk.Label(tab, text="Title").grid(row=6, column=0, sticky="w", pady=(8, 0))
        ttk.Entry(tab, textvariable=self.title_var).grid(row=6, column=1, sticky="ew", padx=(8, 14), pady=(8, 0))
        ttk.Label(tab, text="Experiment / variant").grid(row=6, column=2, sticky="w", pady=(8, 0))
        exp_frame = ttk.Frame(tab)
        exp_frame.grid(row=6, column=3, sticky="ew", pady=(8, 0))
        exp_frame.columnconfigure(0, weight=1)
        exp_frame.columnconfigure(1, weight=1)
        ttk.Entry(exp_frame, textvariable=self.experiment_var).grid(row=0, column=0, sticky="ew", padx=(8, 4))
        ttk.Entry(exp_frame, textvariable=self.variant_var).grid(row=0, column=1, sticky="ew", padx=(4, 0))

        ttk.Label(tab, text="Public creator-media URL").grid(row=7, column=0, sticky="w", pady=(8, 0))
        ttk.Entry(tab, textvariable=self.media_url_var).grid(row=7, column=1, columnspan=3, sticky="ew", padx=(8, 0), pady=(8, 0))

        editor = ttk.Panedwindow(tab, orient=tk.HORIZONTAL)
        editor.grid(row=8, column=0, columnspan=4, sticky="nsew", pady=(8, 0))
        left = ttk.Frame(editor)
        right = ttk.Frame(editor)
        editor.add(left, weight=1)
        editor.add(right, weight=1)
        left.columnconfigure(0, weight=1)
        left.rowconfigure(1, weight=1)
        right.columnconfigure(0, weight=1)
        right.rowconfigure(1, weight=1)
        ttk.Label(left, text="Editable brief JSON").grid(row=0, column=0, sticky="w")
        self.brief_text = scrolledtext.ScrolledText(left, wrap=tk.WORD, font=("Consolas", 10))
        self.brief_text.grid(row=1, column=0, sticky="nsew")
        ttk.Label(right, text="DeepSeek review / research notes").grid(row=0, column=0, sticky="w")
        self.research_text = scrolledtext.ScrolledText(right, wrap=tk.WORD, font=("Segoe UI", 10))
        self.research_text.grid(row=1, column=0, sticky="nsew")

    def _build_queue(self) -> None:
        tab = self.queue_tab
        tab.columnconfigure(0, weight=1)
        tab.rowconfigure(2, weight=1)
        account = ttk.LabelFrame(tab, text="Official API account reference (no token values)", padding=8)
        account.grid(row=0, column=0, sticky="ew")
        for index in range(8):
            account.columnconfigure(index, weight=1 if index in {1, 3, 5, 7} else 0)
        self.account_platform_var = tk.StringVar(value="facebook")
        self.account_name_var = tk.StringVar()
        self.account_remote_var = tk.StringVar()
        self.account_token_env_var = tk.StringVar(value="FACEBOOK_PAGE_ACCESS_TOKEN")
        ttk.Label(account, text="Platform").grid(row=0, column=0, sticky="w")
        ttk.Combobox(account, textvariable=self.account_platform_var, values=ops.PLATFORMS, state="readonly", width=12).grid(row=0, column=1, sticky="ew", padx=(5, 10))
        ttk.Label(account, text="Display name").grid(row=0, column=2, sticky="w")
        ttk.Entry(account, textvariable=self.account_name_var).grid(row=0, column=3, sticky="ew", padx=(5, 10))
        ttk.Label(account, text="Platform account ID").grid(row=0, column=4, sticky="w")
        ttk.Entry(account, textvariable=self.account_remote_var).grid(row=0, column=5, sticky="ew", padx=(5, 10))
        ttk.Label(account, text="Token env name").grid(row=0, column=6, sticky="w")
        ttk.Entry(account, textvariable=self.account_token_env_var).grid(row=0, column=7, sticky="ew", padx=(5, 10))
        ttk.Button(account, text="Add account", command=self._add_account).grid(row=0, column=8)

        scheduling = ttk.LabelFrame(tab, text="Schedule approved content", padding=8)
        scheduling.grid(row=1, column=0, sticky="ew", pady=(10, 8))
        scheduling.columnconfigure(1, weight=2)
        scheduling.columnconfigure(3, weight=2)
        self.schedule_content_var = tk.StringVar()
        self.schedule_account_var = tk.StringVar()
        self.schedule_time_var = tk.StringVar(value=datetime.now().astimezone().replace(microsecond=0).isoformat(timespec="minutes"))
        ttk.Label(scheduling, text="Content").grid(row=0, column=0, sticky="w")
        self.schedule_content_combo = ttk.Combobox(scheduling, textvariable=self.schedule_content_var, state="readonly")
        self.schedule_content_combo.grid(row=0, column=1, sticky="ew", padx=(5, 10))
        ttk.Label(scheduling, text="Account").grid(row=0, column=2, sticky="w")
        self.schedule_account_combo = ttk.Combobox(scheduling, textvariable=self.schedule_account_var, state="readonly")
        self.schedule_account_combo.grid(row=0, column=3, sticky="ew", padx=(5, 10))
        ttk.Label(scheduling, text="Local ISO time").grid(row=0, column=4, sticky="w")
        ttk.Entry(scheduling, textvariable=self.schedule_time_var, width=28).grid(row=0, column=5, sticky="ew", padx=(5, 10))
        ttk.Button(scheduling, text="Schedule", command=self._schedule).grid(row=0, column=6)
        self.preview_button = ttk.Button(scheduling, text="Preview due", command=lambda: self._process_due(False))
        self.preview_button.grid(row=1, column=5, sticky="e", pady=(8, 0))
        self.publish_button = ttk.Button(scheduling, text="Publish due now", command=lambda: self._process_due(True))
        self.publish_button.grid(row=1, column=6, pady=(8, 0))

        self.queue_tree = ttk.Treeview(
            tab,
            columns=("id", "when", "platform", "account", "title", "status", "remote", "error"),
            show="headings",
        )
        for name, label, width in (
            ("id", "ID", 45), ("when", "Scheduled (UTC)", 160), ("platform", "Platform", 80),
            ("account", "Account", 110), ("title", "Content", 240), ("status", "Status", 80),
            ("remote", "Remote ID", 120), ("error", "Last error", 220),
        ):
            self.queue_tree.heading(name, text=label)
            self.queue_tree.column(name, width=width, stretch=name in {"title", "error"})
        self.queue_tree.grid(row=2, column=0, sticky="nsew")
        self.publish_output = scrolledtext.ScrolledText(tab, height=7, wrap=tk.WORD, font=("Consolas", 9))
        self.publish_output.grid(row=3, column=0, sticky="ew", pady=(8, 0))

    def _build_metrics(self) -> None:
        tab = self.metrics_tab
        tab.columnconfigure(0, weight=1)
        tab.rowconfigure(2, weight=1)
        tab.rowconfigure(4, weight=1)
        form = ttk.LabelFrame(tab, text="Append aggregate observation", padding=8)
        form.grid(row=0, column=0, sticky="ew")
        self.metric_destination_var = tk.StringVar()
        self.metric_vars = {name: tk.StringVar(value="0") for name in ("reach", "views", "likes", "comments", "shares", "saves", "clicks", "follower_delta", "revenue")}
        ttk.Label(form, text="Destination").grid(row=0, column=0, sticky="w")
        self.metric_destination_combo = ttk.Combobox(form, textvariable=self.metric_destination_var, state="readonly", width=48)
        self.metric_destination_combo.grid(row=0, column=1, columnspan=3, sticky="ew", padx=(5, 10))
        for index, name in enumerate(self.metric_vars):
            row = 1 + index // 5
            column = (index % 5) * 2
            ttk.Label(form, text=name.replace("_", " ").title()).grid(row=row, column=column, sticky="w", pady=(6, 0))
            ttk.Entry(form, textvariable=self.metric_vars[name], width=10).grid(row=row, column=column + 1, sticky="ew", padx=(4, 10), pady=(6, 0))
        ttk.Button(form, text="Record metrics", command=self._record_metrics).grid(row=2, column=10, sticky="e", pady=(6, 0))
        ttk.Label(
            tab,
            text="A/B insight uses the latest observation per destination. Compare the same topic, offer, and distribution window; change one framing variable at a time.",
            wraplength=1000,
        ).grid(row=1, column=0, sticky="w", pady=(10, 8))
        self.insight_tree = ttk.Treeview(
            tab,
            columns=("experiment", "variant", "samples", "exposure", "engagements", "rate", "clicks", "followers", "revenue"),
            show="headings",
        )
        for name, label, width in (
            ("experiment", "Experiment", 170), ("variant", "Variant", 90), ("samples", "Samples", 65),
            ("exposure", "Exposure", 80), ("engagements", "Engagements", 90), ("rate", "Rate", 70),
            ("clicks", "Clicks", 65), ("followers", "Followers", 70), ("revenue", "Revenue", 80),
        ):
            self.insight_tree.heading(name, text=label)
            self.insight_tree.column(name, width=width, stretch=name == "experiment")
        self.insight_tree.grid(row=2, column=0, sticky="nsew")
        ttk.Label(
            tab,
            text="Topic performance uses the same latest aggregate snapshots. It identifies candidates for another test, not a guaranteed viral topic.",
            wraplength=1000,
        ).grid(row=3, column=0, sticky="w", pady=(10, 8))
        self.topic_performance_tree = ttk.Treeview(
            tab,
            columns=("topic", "samples", "exposure", "engagements", "rate", "shares", "saves", "followers", "revenue"),
            show="headings",
        )
        for name, label, width in (
            ("topic", "Topic", 260), ("samples", "Samples", 65), ("exposure", "Exposure", 80),
            ("engagements", "Engagements", 90), ("rate", "Rate", 70), ("shares", "Shares", 65),
            ("saves", "Saves", 65), ("followers", "Followers", 70), ("revenue", "Revenue", 80),
        ):
            self.topic_performance_tree.heading(name, text=label)
            self.topic_performance_tree.column(name, width=width, stretch=name == "topic")
        self.topic_performance_tree.grid(row=4, column=0, sticky="nsew")

    def _build_guide(self) -> None:
        self.guide_tab.columnconfigure(0, weight=1)
        self.guide_tab.rowconfigure(0, weight=1)
        text = scrolledtext.ScrolledText(self.guide_tab, wrap=tk.WORD, font=("Segoe UI", 10), padx=10, pady=10)
        text.grid(row=0, column=0, sticky="nsew")
        text.insert("1.0", GUIDE_TEXT)
        text.configure(state=tk.DISABLED)
        actions = ttk.Frame(self.guide_tab)
        actions.grid(row=1, column=0, sticky="ew", pady=(8, 0))
        ttk.Button(actions, text="Open data folder", command=self._open_data_folder).pack(side=tk.LEFT)
        ttk.Button(actions, text="Choose creator media file", command=self._choose_media).pack(side=tk.LEFT, padx=8)
        live = "ENABLED" if os.environ.get("CREATOR_OPS_LIVE_PUBLISH") == "1" else "disabled (dry-run)"
        ttk.Label(actions, text=f"Live publishing: {live}").pack(side=tk.RIGHT)

    def refresh_all(self) -> None:
        """Reload database-backed controls and summaries."""
        summary = self.store.dashboard_summary()
        self.summary_var.set(
            "Drafts {drafts}  •  Approved {approved}  •  Scheduled {scheduled}  •  Published {published}  •  "
            "Views {views:,}  •  Engagements {engagements:,}  •  Follower Δ {follower_delta:+,}  •  Revenue ${revenue:,.2f}".format(**summary)
        )
        self._clear_tree(self.topic_tree)
        self.topic_rows.clear()
        topic_labels = []
        for row in self.store.list_topics():
            label = f"{row['id']} — {row['name']}"
            topic_labels.append(label)
            self.topic_rows[label] = row
            self.topic_tree.insert("", tk.END, values=(row["name"], row["audience_value"], row["honest_tension"], row["safety_notes"]))
        self.topic_combo.configure(values=topic_labels)
        self.research_topic_combo.configure(values=topic_labels)
        if topic_labels and self.topic_var.get() not in topic_labels:
            self.topic_var.set(topic_labels[0])
        if topic_labels and self.research_topic_var.get() not in topic_labels:
            self.research_topic_var.set(topic_labels[0])
        self._clear_tree(self.observation_tree)
        for row in self.store.list_observations():
            self.observation_tree.insert(
                "",
                tk.END,
                values=(row["captured_at"], row["topic_name"] or "Unassigned", row["source_type"], row["aggregate_sentiment"], row["notes"], row["source_rights"]),
            )

        content_labels = []
        self.content_rows.clear()
        for row in self.store.list_content():
            label = f"{row['id']} — [{row['status']}] {row['title']}"
            content_labels.append(label)
            self.content_rows[label] = row
        self.content_combo.configure(values=content_labels)
        self.schedule_content_combo.configure(values=content_labels)

        account_labels = []
        self.account_rows.clear()
        for row in self.store.list_accounts(enabled_only=True):
            label = f"{row['id']} — {row['platform']} / {row['display_name']}"
            account_labels.append(label)
            self.account_rows[label] = row
        self.schedule_account_combo.configure(values=account_labels)

        self._clear_tree(self.queue_tree)
        destination_labels = []
        self.destination_rows.clear()
        for row in self.store.list_destinations():
            label = f"{row['id']} — {row['platform']} / {row['title']}"
            destination_labels.append(label)
            self.destination_rows[label] = row
            self.queue_tree.insert("", tk.END, values=(row["id"], row["scheduled_for"], row["platform"], row["display_name"], row["title"], row["status"], row["remote_post_id"] or "", row["last_error"]))
        self.metric_destination_combo.configure(values=destination_labels)
        if destination_labels and self.metric_destination_var.get() not in destination_labels:
            self.metric_destination_var.set(destination_labels[0])
        self._refresh_insights()
        self.status_var.set(f"Refreshed — data: {self.database_path}")

    def _refresh_models(self) -> None:
        url = self.ollama_url_var.get().strip()
        def work() -> list[str]:
            client = orchestrator.OllamaClient(url, timeout_seconds=10, retries=0)
            return sorted(
                name for item in client.list_models()
                if (name := orchestrator._model_name(item)) is not None and orchestrator._is_text_model(name)
            )
        self._start_job("models", work)

    def _generate_brief(self) -> None:
        topic = self.topic_rows.get(self.topic_var.get())
        if topic is None:
            messagebox.showerror("Topic required", "Choose a topic first.", parent=self.root)
            return
        model = self.model_var.get().strip()
        if not model:
            messagebox.showerror("Model required", "Click Find models and choose an Ollama text model.", parent=self.root)
            return
        sources = self._lines(self.sources_text)
        def work() -> ops.ContentBrief:
            client = orchestrator.OllamaClient(self.ollama_url_var.get().strip(), timeout_seconds=180, retries=1)
            return ops.generate_brief(
                client=client,
                model=model,
                topic=topic,
                creator_goal=self.goal_var.get(),
                requested_format=self.format_var.get(),
                creator_notes=self.notes_text.get("1.0", tk.END),
                source_urls=sources,
            )
        self._start_job("generate", work)

    def _brief_from_editor(self) -> ops.ContentBrief:
        try:
            payload = json.loads(self.brief_text.get("1.0", tk.END))
        except json.JSONDecodeError as exc:
            raise ValueError(f"Editable brief is not valid JSON: {exc}") from exc
        if not isinstance(payload, dict):
            raise ValueError("Editable brief JSON must be an object.")
        brief = ops.validate_brief(payload)
        title = self.title_var.get().strip() or brief.title
        content_format = self.format_var.get().strip() or brief.format
        return replace(brief, title=title, format=content_format)

    def _save_draft(self) -> None:
        try:
            brief = self._brief_from_editor()
            topic = self.topic_rows.get(self.topic_var.get())
            if topic is None:
                raise ValueError("Choose a topic.")
            if self.current_content_id is None:
                self.current_content_id = self.store.create_content(
                    topic_id=int(topic["id"]),
                    brief=brief,
                    creator_notes=self.notes_text.get("1.0", tk.END),
                    source_urls=self._lines(self.sources_text),
                    media_url=self.media_url_var.get(),
                    experiment_key=self.experiment_var.get(),
                    variant_label=self.variant_var.get(),
                    research_notes=self.research_text.get("1.0", tk.END),
                )
            else:
                self.store.update_content(
                    self.current_content_id,
                    title=brief.title,
                    hook=brief.hook,
                    thesis=brief.thesis,
                    opposing_view=brief.opposing_view,
                    practical_value=brief.practical_value,
                    call_to_action=brief.call_to_action,
                    safety_check=brief.safety_check,
                    format=brief.format,
                    creator_notes=self.notes_text.get("1.0", tk.END),
                    research_notes=self.research_text.get("1.0", tk.END),
                    experiment_key=self.experiment_var.get(),
                    variant_label=self.variant_var.get(),
                    variant_a_hook=brief.variant_a_hook,
                    variant_b_hook=brief.variant_b_hook,
                    evidence_needed_json=json.dumps(brief.evidence_needed, ensure_ascii=False),
                    talking_points_json=json.dumps(brief.talking_points, ensure_ascii=False),
                    source_urls_json=json.dumps(self._lines(self.sources_text), ensure_ascii=False),
                    media_url=self.media_url_var.get(),
                )
            self.title_var.set(brief.title)
            self.current_brief = brief
            self.refresh_all()
            self.status_var.set(f"Draft {self.current_content_id} saved. Approval is still required.")
        except Exception as exc:
            messagebox.showerror("Cannot save", str(exc), parent=self.root)

    def _approve_draft(self) -> None:
        if self.current_content_id is None:
            messagebox.showerror("Save first", "Save the current brief before approval.", parent=self.root)
            return
        if not messagebox.askyesno(
            "Confirm human approval",
            "Have you checked every factual claim, source, caption, audience implication, and creator-owned media asset? Editing after approval will require approval again.",
            parent=self.root,
        ):
            return
        try:
            self.store.approve_content(self.current_content_id)
            self.refresh_all()
            self.status_var.set(f"Draft {self.current_content_id} approved by the creator.")
        except Exception as exc:
            messagebox.showerror("Cannot approve", str(exc), parent=self.root)

    def _deepseek_review(self) -> None:
        try:
            brief = self._brief_from_editor()
        except Exception as exc:
            messagebox.showerror("Brief required", str(exc), parent=self.root)
            return
        key = self.deepseek_key_var.get().strip() or os.environ.get("DEEPSEEK_API_KEY")
        if not key:
            messagebox.showerror("API key required", "Enter a DeepSeek key or set DEEPSEEK_API_KEY.", parent=self.root)
            return
        if not messagebox.askyesno(
            "Paid DeepSeek review",
            "Send this locally prepared brief and its source URLs to DeepSeek Harness? This can consume paid API tokens.",
            parent=self.root,
        ):
            return
        prompt = ops.deepseek_review_prompt(brief, self._lines(self.sources_text))
        workspace = Path(__file__).resolve().parents[2]
        sessions = ops.default_database_path().parent / "deepseek-sessions"
        def work() -> orchestrator.DeepSeekResult:
            return orchestrator.run_deepseek(
                prompt,
                provider=self.deepseek_provider_var.get(),
                model=self.deepseek_model_var.get(),
                max_tokens=2500,
                workspace=workspace,
                session_root=sessions,
                session_id=None,
                cordis=None,
                timeout_seconds=900,
                api_key=key,
                base_url=self.deepseek_base_var.get().strip() or None,
            )
        self._start_job("deepseek", work)

    def _load_selected_content(self) -> None:
        row = self.content_rows.get(self.content_var.get())
        if row is None:
            return
        topic_label = next((label for label, topic in self.topic_rows.items() if topic["id"] == row["topic_id"]), "")
        self.topic_var.set(topic_label)
        self.current_content_id = int(row["id"])
        brief = ops.ContentBrief(
            title=row["title"], hook=row["hook"], thesis=row["thesis"], opposing_view=row["opposing_view"],
            practical_value=row["practical_value"], evidence_needed=tuple(json.loads(row["evidence_needed_json"])),
            talking_points=tuple(json.loads(row["talking_points_json"])), call_to_action=row["call_to_action"],
            safety_check=row["safety_check"], format=row["format"], variant_a_hook=row["variant_a_hook"] or row["hook"], variant_b_hook=row["variant_b_hook"] or row["hook"],
        )
        self.current_brief = brief
        self.title_var.set(row["title"])
        self.format_var.set(row["format"])
        self.experiment_var.set(row["experiment_key"])
        self.variant_var.set(row["variant_label"])
        self.media_url_var.set(row["media_url"])
        self._replace(self.brief_text, ops.brief_as_json(brief))
        self._replace(self.notes_text, row["creator_notes"])
        self._replace(self.sources_text, "\n".join(json.loads(row["source_urls_json"])))
        self._replace(self.research_text, row["research_notes"])
        self.status_var.set(f"Loaded content {row['id']} ({row['status']}).")

    def _clear_studio(self) -> None:
        self.current_content_id = None
        self.current_brief = None
        self.content_var.set("")
        self.title_var.set("")
        self.experiment_var.set("")
        self.variant_var.set("")
        self.media_url_var.set("")
        for widget in (self.brief_text, self.research_text, self.sources_text, self.notes_text):
            self._replace(widget, "")
        self.status_var.set("New draft ready.")

    def _add_account(self) -> None:
        try:
            self.store.add_account(
                platform=self.account_platform_var.get(),
                display_name=self.account_name_var.get(),
                handle="",
                remote_id=self.account_remote_var.get(),
                token_env=self.account_token_env_var.get(),
            )
            self.account_name_var.set("")
            self.account_remote_var.set("")
            self.refresh_all()
        except Exception as exc:
            messagebox.showerror("Cannot add account", str(exc), parent=self.root)

    def _add_observation(self) -> None:
        topic = self.topic_rows.get(self.research_topic_var.get())
        try:
            self.store.add_observation(
                topic_id=int(topic["id"]) if topic is not None else None,
                source_url=self.research_url_var.get(),
                source_type=self.research_type_var.get(),
                notes=self.research_notes_text.get("1.0", tk.END),
                aggregate_sentiment=self.research_sentiment_var.get(),
                source_rights=self.research_rights_var.get(),
            )
            self.research_url_var.set("")
            self._replace(self.research_notes_text, "")
            self.refresh_all()
        except Exception as exc:
            messagebox.showerror("Cannot record research", str(exc), parent=self.root)

    def _schedule(self) -> None:
        content = self.content_rows.get(self.schedule_content_var.get())
        account = self.account_rows.get(self.schedule_account_var.get())
        if content is None or account is None:
            messagebox.showerror("Selection required", "Choose approved content and an account.", parent=self.root)
            return
        try:
            destination_id = self.store.schedule_content(
                content_id=int(content["id"]), account_id=int(account["id"]), scheduled_for=self.schedule_time_var.get()
            )
            self.refresh_all()
            self.status_var.set(f"Destination {destination_id} scheduled. Dry-run remains the default.")
        except Exception as exc:
            messagebox.showerror("Cannot schedule", str(exc), parent=self.root)

    def _process_due(self, requested_live: bool) -> None:
        configured_live = os.environ.get("CREATOR_OPS_LIVE_PUBLISH") == "1"
        if requested_live and not configured_live:
            messagebox.showerror(
                "Live publishing disabled",
                "Set CREATOR_OPS_LIVE_PUBLISH=1 before starting the app. This cannot be enabled from inside the GUI.",
                parent=self.root,
            )
            return
        if requested_live and not messagebox.askyesno(
            "Publish due content",
            "Send every due, approved queue item through its official platform API now?",
            parent=self.root,
        ):
            return
        def work() -> list[ops.PublishResult]:
            with ops.CreatorStore(self.database_path) as worker_store:
                return ops.OfficialPublisher(worker_store, live=requested_live).process_due()
        self._start_job("publish" if requested_live else "preview", work)

    def _record_metrics(self) -> None:
        destination = self.destination_rows.get(self.metric_destination_var.get())
        if destination is None:
            messagebox.showerror("Destination required", "Choose a destination.", parent=self.root)
            return
        try:
            self.store.add_metric(int(destination["id"]), **{name: value.get() for name, value in self.metric_vars.items()})
            self.refresh_all()
        except Exception as exc:
            messagebox.showerror("Cannot record metrics", str(exc), parent=self.root)

    def _refresh_insights(self) -> None:
        self._clear_tree(self.insight_tree)
        for item in self.store.experiment_insights():
            self.insight_tree.insert("", tk.END, values=(item["experiment_key"], item["variant_label"], item["samples"], item["exposure"], item["engagements"], f"{item['engagement_rate']:.2%}", item["clicks"], item["follower_delta"], f"${item['revenue']:.2f}"))
        self._clear_tree(self.topic_performance_tree)
        for item in self.store.topic_performance():
            self.topic_performance_tree.insert(
                "",
                tk.END,
                values=(item["topic_name"], item["samples"], item["exposure"], item["engagements"], f"{item['engagement_rate']:.2%}", item["shares"], item["saves"], item["follower_delta"], f"${item['revenue']:.2f}"),
            )

    def _start_job(self, name: str, target: Callable[[], object]) -> None:
        if self.active_job is not None:
            self.status_var.set("Wait for the current operation to finish.")
            return
        self.active_job = name
        self._set_busy(True)
        self.status_var.set({"models": "Finding Ollama models…", "generate": "Generating a local brief…", "deepseek": "Running paid DeepSeek review…", "preview": "Preparing due packages…", "publish": "Publishing due items…"}[name])
        def dispatch() -> None:
            try:
                result = target()
            except BaseException as exc:
                self.events.put(("error", name, exc))
            else:
                self.events.put(("done", name, result))
        threading.Thread(target=dispatch, name=f"creator-ops-{name}", daemon=True).start()

    def _poll_events(self) -> None:
        try:
            while True:
                kind, name, payload = self.events.get_nowait()
                self._handle_event(kind, name, payload)
        except queue.Empty:
            pass
        self.root.after(75, self._poll_events)

    def _handle_event(self, kind: str, name: str, payload: object) -> None:
        self.active_job = None
        self._set_busy(False)
        if kind == "error":
            self.status_var.set(f"Failed: {payload}")
            messagebox.showerror("Operation failed", str(payload), parent=self.root)
            self.refresh_all()
            return
        if name == "models":
            names = payload if isinstance(payload, list) else []
            self.model_combo.configure(values=names)
            if names:
                self.model_var.set(self.model_var.get() if self.model_var.get() in names else names[0])
            self.status_var.set(f"Found {len(names)} Ollama text model(s).")
        elif name == "generate":
            if not isinstance(payload, ops.ContentBrief):
                raise TypeError("Local model returned an unexpected result.")
            self.current_brief = payload
            self.current_content_id = None
            self.title_var.set(payload.title)
            self._replace(self.brief_text, ops.brief_as_json(payload))
            self.status_var.set("Local brief ready. Edit, source-check, and save it before approval.")
        elif name == "deepseek":
            if not isinstance(payload, orchestrator.DeepSeekResult):
                raise TypeError("DeepSeek Harness returned an unexpected result.")
            self._replace(self.research_text, payload.response)
            self.status_var.set(f"Paid review complete — session {payload.session_id}.")
        elif name in {"preview", "publish"}:
            results = payload if isinstance(payload, list) else []
            rendered = [asdict(item) if isinstance(item, ops.PublishResult) else item for item in results]
            self._replace(self.publish_output, json.dumps(rendered, ensure_ascii=False, indent=2))
            self.refresh_all()
            self.status_var.set(f"{len(results)} due item(s) {'published' if name == 'publish' else 'prepared as dry-run packages'}.")

    def _set_busy(self, busy: bool) -> None:
        state = tk.DISABLED if busy else tk.NORMAL
        for button in (self.refresh_button, self.models_button, self.generate_button, self.review_button, self.preview_button, self.publish_button):
            button.configure(state=state)

    def _open_data_folder(self) -> None:
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        if os.name == "nt":
            os.startfile(self.database_path.parent)  # type: ignore[attr-defined]
        else:
            subprocess.Popen(["xdg-open", str(self.database_path.parent)])

    def _choose_media(self) -> None:
        selected = filedialog.askopenfilename(parent=self.root, title="Choose creator-owned media")
        if selected:
            self.root.clipboard_clear()
            self.root.clipboard_append(selected)
            self.status_var.set("Media path copied. Hosting/upload remains creator-controlled; paste a public URL into the saved content record when required.")

    def _on_close(self) -> None:
        if self.active_job is not None:
            messagebox.showwarning("Operation running", "Wait for the current operation to finish before closing.", parent=self.root)
            return
        self.store.close()
        self.root.destroy()

    @staticmethod
    def _lines(widget: tk.Text) -> list[str]:
        return [line.strip() for line in widget.get("1.0", tk.END).splitlines() if line.strip()]

    @staticmethod
    def _replace(widget: tk.Text, value: str) -> None:
        widget.delete("1.0", tk.END)
        widget.insert("1.0", value)

    @staticmethod
    def _clear_tree(tree: ttk.Treeview) -> None:
        children = tree.get_children()
        if children:
            tree.delete(*children)


def main() -> None:
    """Open the creator operations dashboard without CLI configuration."""
    root = tk.Tk()
    CreatorOpsGui(root)
    root.mainloop()


if __name__ == "__main__":
    main()
