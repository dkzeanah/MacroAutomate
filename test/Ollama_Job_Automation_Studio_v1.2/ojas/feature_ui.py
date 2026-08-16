from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import time
import tkinter as tk
from datetime import datetime
from pathlib import Path
from tkinter import filedialog, messagebox, ttk
from typing import Any

from .core import AtomicJSON, open_folder
from .resume_ats import (
    ATSReport,
    analyze_resume,
    build_ai_resume_prompt,
    donovan_seed_profile,
    extract_pdf_text,
    profile_metrics,
)
from .visual_synthesis import (
    ComfyUIClient,
    analyze_references,
    build_txt2img_workflow,
    synthesize_generation_prompt,
)


class ATSMixin:
    def _build_ats_tab(self) -> None:
        self.ats_tab.grid_rowconfigure(0, weight=1)
        self.ats_tab.grid_columnconfigure(0, weight=1)

        outer = ttk.Frame(self.ats_tab, padding=8)
        outer.grid(row=0, column=0, sticky="nsew")
        outer.grid_rowconfigure(2, weight=1)
        outer.grid_columnconfigure(0, weight=1)

        input_frame = ttk.LabelFrame(outer, text="Resume and target role", padding=7)
        input_frame.grid(row=0, column=0, sticky="ew")
        input_frame.grid_columnconfigure(1, weight=1)

        ttk.Label(input_frame, text="Resume PDF").grid(row=0, column=0, sticky="w")
        self.ats_resume_path_var = tk.StringVar(value=str(self.bundled_resume_path))
        ttk.Entry(input_frame, textvariable=self.ats_resume_path_var).grid(
            row=0, column=1, sticky="ew", padx=(5, 5)
        )
        ttk.Button(
            input_frame,
            text="Browse",
            command=self.choose_ats_resume,
            style="Tool.TButton",
        ).grid(row=0, column=2, sticky="ew")

        ttk.Label(input_frame, text="Target role").grid(
            row=1, column=0, sticky="w", pady=(6, 0)
        )
        self.ats_target_role_var = tk.StringVar(value="Embedded Software Developer")
        ttk.Entry(input_frame, textvariable=self.ats_target_role_var).grid(
            row=1, column=1, columnspan=2, sticky="ew", padx=(5, 0), pady=(6, 0)
        )

        ttk.Label(
            input_frame,
            text="Paste the exact job description for the most useful keyword alignment score.",
        ).grid(row=2, column=0, columnspan=3, sticky="w", pady=(7, 2))
        job_scroll, self.ats_job_text = self._scrolled_text(input_frame, height=4)
        job_scroll.grid(row=3, column=0, columnspan=3, sticky="ew")

        actions = ttk.Frame(outer)
        actions.grid(row=1, column=0, sticky="ew", pady=(6, 6))
        self._button_grid(
            actions,
            [
                ("Analyze resume", self.analyze_ats_resume),
                ("AI grounded critique", self.request_ats_ai_critique),
                ("Load Donovan resume profile", self.load_bundled_resume_profile),
                ("Export report JSON", self.export_ats_report),
                ("Open resume", self.open_ats_resume),
                ("Clear job description", lambda: self.ats_job_text.delete("1.0", "end")),
            ],
            columns=3,
            primary_index=0,
        )

        paned = ttk.Panedwindow(outer, orient="horizontal")
        paned.grid(row=2, column=0, sticky="nsew")

        score_frame = ttk.LabelFrame(paned, text="ATS-style score breakdown", padding=6)
        detail_frame = ttk.LabelFrame(paned, text="Findings, missing terms, and improvement tips", padding=6)
        score_frame.grid_rowconfigure(1, weight=1)
        score_frame.grid_columnconfigure(0, weight=1)
        detail_frame.grid_rowconfigure(0, weight=1)
        detail_frame.grid_columnconfigure(0, weight=1)
        paned.add(score_frame, weight=2)
        paned.add(detail_frame, weight=3)

        self.ats_score_var = tk.StringVar(value="Overall score: not analyzed")
        ttk.Label(score_frame, textvariable=self.ats_score_var, style="Title.TLabel").grid(
            row=0, column=0, sticky="ew", pady=(0, 5)
        )

        metric_tree_frame = ttk.Frame(score_frame)
        metric_tree_frame.grid(row=1, column=0, sticky="nsew")
        metric_tree_frame.grid_rowconfigure(0, weight=1)
        metric_tree_frame.grid_columnconfigure(0, weight=1)
        self.ats_metric_tree = ttk.Treeview(
            metric_tree_frame,
            columns=("score", "status", "explanation"),
            show="tree headings",
            selectmode="browse",
            height=5,
        )
        self.ats_metric_tree.heading("#0", text="Metric")
        self.ats_metric_tree.heading("score", text="Score")
        self.ats_metric_tree.heading("status", text="Status")
        self.ats_metric_tree.heading("explanation", text="Explanation")
        self.ats_metric_tree.column("#0", width=190, minwidth=130)
        self.ats_metric_tree.column("score", width=80, minwidth=70, anchor="center")
        self.ats_metric_tree.column("status", width=80, minwidth=70, anchor="center")
        self.ats_metric_tree.column("explanation", width=430, minwidth=220)
        metric_y = ttk.Scrollbar(
            metric_tree_frame, orient="vertical", command=self.ats_metric_tree.yview
        )
        metric_x = ttk.Scrollbar(
            metric_tree_frame, orient="horizontal", command=self.ats_metric_tree.xview
        )
        self.ats_metric_tree.configure(yscrollcommand=metric_y.set, xscrollcommand=metric_x.set)
        self.ats_metric_tree.grid(row=0, column=0, sticky="nsew")
        metric_y.grid(row=0, column=1, sticky="ns")
        metric_x.grid(row=1, column=0, sticky="ew")
        self.ats_metric_tree.tag_configure("Good", background="#eaf8ed")
        self.ats_metric_tree.tag_configure("Review", background="#fff7cc")
        self.ats_metric_tree.tag_configure("Weak", background="#ffe7e7")

        detail_scroll, self.ats_result_text = self._scrolled_text(detail_frame, height=8)
        detail_scroll.grid(row=0, column=0, sticky="nsew")

        self.ats_status_var = tk.StringVar(
            value="Scanner is diagnostic only; it does not reproduce a specific employer's proprietary ATS."
        )
        ttk.Label(outer, textvariable=self.ats_status_var).grid(
            row=3, column=0, sticky="ew", pady=(5, 0)
        )

    def choose_ats_resume(self) -> None:
        path = filedialog.askopenfilename(
            title="Choose resume PDF",
            filetypes=[("PDF documents", "*.pdf"), ("All files", "*.*")],
        )
        if path:
            self.ats_resume_path_var.set(path)

    def analyze_ats_resume(self) -> None:
        path = self.ats_resume_path_var.get().strip()
        if not path:
            messagebox.showinfo("Choose a resume", "Choose a PDF resume first.")
            return
        job_description = self.ats_job_text.get("1.0", "end").strip()
        self.ats_status_var.set("Extracting and analyzing resume...")
        self.set_status("Running ATS-style resume scan...")
        threading.Thread(
            target=self._ats_analysis_worker,
            args=(path, job_description),
            daemon=True,
        ).start()

    def _ats_analysis_worker(self, path: str, job_description: str) -> None:
        try:
            text, pages, _page_texts = extract_pdf_text(path)
            report = analyze_resume(text, pages=pages, job_description=job_description)
            self.events.put({"kind": "ats_result", "report": report, "path": path})
        except Exception as exc:
            self.events.put(
                {"kind": "ats_error", "error": f"{type(exc).__name__}: {exc}"}
            )

    def _display_ats_report(self, report: ATSReport) -> None:
        self.ats_report = report
        self.ats_score_var.set(
            f"Overall diagnostic score: {report.overall_score:.1f}/100   |   "
            f"{report.pages} pages   |   {report.words} words"
        )
        for iid in self.ats_metric_tree.get_children():
            self.ats_metric_tree.delete(iid)
        for index, metric in enumerate(report.metrics):
            self.ats_metric_tree.insert(
                "",
                "end",
                iid=f"metric-{index}",
                text=metric.name,
                values=(
                    f"{metric.score:.1f}/{metric.maximum:.0f}",
                    metric.status,
                    metric.explanation,
                ),
                tags=(metric.status,),
            )

        lines = [
            "IMPORTANT",
            "This is a transparent local ATS-style diagnostic, not a prediction of whether an employer will interview or hire you.",
            "",
            "DETECTED SKILLS",
            ", ".join(report.detected_skills) or "None detected",
            "",
            "MATCHED JOB-DESCRIPTION TERMS",
            ", ".join(report.matched_keywords) or "No job description supplied or no matches detected",
            "",
            "MISSING OR WEAKLY REPRESENTED TERMS",
            ", ".join(report.missing_keywords) or "None identified",
            "",
            "WARNINGS",
        ]
        lines.extend(f"- {item}" for item in report.warnings or ["No major warnings detected."])
        lines.extend(["", "TIPS FOR EXCELLING IN AUTOMATED SCREENING"])
        lines.extend(f"- {item}" for item in report.tips)
        lines.extend(
            [
                "",
                "PROFILE METRICS",
                json.dumps(profile_metrics(self.profile, report), indent=2),
            ]
        )
        self.ats_result_text.delete("1.0", "end")
        self.ats_result_text.insert("1.0", "\n".join(lines))
        self.ats_status_var.set("ATS-style analysis complete. Review the evidence, not only the total score.")
        self.set_status("ATS scan complete")

    def request_ats_ai_critique(self) -> None:
        if not getattr(self, "ats_report", None):
            messagebox.showinfo("Analyze first", "Run Analyze resume before requesting an AI critique.")
            return
        prompt = build_ai_resume_prompt(
            self.ats_report,
            target_role=self.ats_target_role_var.get().strip(),
        )
        self.ats_status_var.set("Requesting grounded local-model critique...")
        self.set_status("Generating resume critique...")
        self._chat_worker(
            model=self.chat_model_var.get().strip() or "qwen3.5:4b",
            prompt=prompt,
            system=(
                "You are a careful resume editor. Use only supplied resume evidence. "
                "Do not make hiring decisions or invent qualifications."
            ),
            image_path="",
            temperature=0.15,
            num_ctx=16384,
            event_kind="ats_ai",
        )

    def export_ats_report(self) -> None:
        report = getattr(self, "ats_report", None)
        if not report:
            messagebox.showinfo("Nothing to export", "Analyze a resume first.")
            return
        path = filedialog.asksaveasfilename(
            title="Export ATS-style report",
            defaultextension=".json",
            initialfile="resume_ats_report.json",
            filetypes=[("JSON", "*.json")],
        )
        if path:
            Path(path).write_text(
                json.dumps(report.to_dict(), indent=2, ensure_ascii=False),
                encoding="utf-8",
            )
            self.log(f"Exported ATS report to {path}")

    def open_ats_resume(self) -> None:
        path = Path(self.ats_resume_path_var.get().strip()).expanduser()
        if not path.exists():
            messagebox.showerror("Resume not found", str(path))
            return
        if os.name == "nt":
            os.startfile(path)  # type: ignore[attr-defined]
        elif sys.platform == "darwin":
            subprocess.Popen(["open", str(path)])
        else:
            subprocess.Popen(["xdg-open", str(path)])

    def load_bundled_resume_profile(self) -> None:
        if not self.bundled_resume_path.exists():
            messagebox.showerror("Bundled resume missing", str(self.bundled_resume_path))
            return
        if not messagebox.askyesno(
            "Load seeded resume profile",
            "Replace the profile editor with a structured profile seeded only from the supplied 2026 resume?\n\n"
            "You must review it before using it. Missing URLs, address, authorization, salary, and other facts remain blank.",
        ):
            return
        profile = donovan_seed_profile(self.bundled_resume_path)
        self.profile = profile
        self.profile_text.delete("1.0", "end")
        self.profile_text.insert("1.0", json.dumps(profile, indent=2, ensure_ascii=False))
        AtomicJSON.save(self.paths.profile_json, profile)
        if hasattr(self, "profile_resume_metrics_var"):
            try:
                text, pages, _ = extract_pdf_text(self.bundled_resume_path)
                report = analyze_resume(text, pages=pages)
                metrics = profile_metrics(profile, report)
                self.profile_resume_metrics_var.set(
                    "Resume profile: "
                    f"{metrics['skills']} skills, {metrics['work_history_entries']} work entries, "
                    f"{metrics['education_entries']} education entries, {metrics['resume_pages']} pages, "
                    f"baseline diagnostic {metrics['ats_baseline_score']:.1f}/100"
                )
            except Exception:
                pass
        self.log("Loaded structured profile seeded from bundled DonovanZeanahResume-2026.pdf")
        messagebox.showinfo(
            "Profile loaded",
            "The resume-seeded profile is now saved and displayed. Review every field before application use.",
        )

    def handle_ats_event(self, event: dict[str, Any]) -> bool:
        kind = event.get("kind")
        if kind == "ats_result":
            self._display_ats_report(event["report"])
            self.log(
                f"ATS scan complete for {event.get('path')}: "
                f"{event['report'].overall_score:.1f}/100"
            )
            return True
        if kind == "ats_error":
            self.ats_status_var.set("ATS scan failed")
            self.set_status("ATS scan failed")
            self.log(f"ATS ERROR: {event.get('error')}")
            messagebox.showerror("ATS scanner error", event.get("error", "Unknown error"))
            return True
        if kind == "ats_ai":
            content = event["response"].get("message", {}).get("content", "")
            existing = self.ats_result_text.get("1.0", "end").rstrip()
            self.ats_result_text.delete("1.0", "end")
            self.ats_result_text.insert(
                "1.0",
                existing + "\n\n===== GROUNDED LOCAL-MODEL CRITIQUE =====\n" + content,
            )
            self.ats_status_var.set("Grounded AI critique complete")
            self.set_status("Ready")
            return True
        if kind == "ats_ai_error":
            self.ats_status_var.set("AI critique failed")
            self.set_status("AI critique failed")
            messagebox.showerror("Resume critique failed", event.get("error", "Unknown error"))
            return True
        return False


class VisualSynthesisMixin:
    def _build_visual_tab(self) -> None:
        self.visual_tab.grid_rowconfigure(0, weight=1)
        self.visual_tab.grid_columnconfigure(0, weight=1)
    
        self.visual_images: list[Path] = []
        self.visual_analyses: list[dict[str, str]] = []
        self.visual_prompt_data: dict[str, str] = {}
        self.visual_preview_photo = None
        self.visual_output_path: Path | None = None
    
        outer = ttk.Frame(self.visual_tab, padding=8)
        outer.grid(row=0, column=0, sticky="nsew")
        outer.grid_rowconfigure(2, weight=1)
        outer.grid_columnconfigure(0, weight=1)
    
        settings = ttk.LabelFrame(outer, text="Reference analysis and generation settings", padding=7)
        settings.grid(row=0, column=0, sticky="ew")
        for column in (1, 3, 5):
            settings.grid_columnconfigure(column, weight=1)
    
        ttk.Label(settings, text="Vision model").grid(row=0, column=0, sticky="w")
        self.visual_vision_model_var = tk.StringVar(value="qwen3-vl:4b")
        self.visual_vision_combo = ttk.Combobox(
            settings,
            textvariable=self.visual_vision_model_var,
            values=["qwen3-vl:4b", "granite3.2-vision:2b"],
        )
        self.visual_vision_combo.grid(row=0, column=1, sticky="ew", padx=(5, 10))
    
        ttk.Label(settings, text="Synthesis model").grid(row=0, column=2, sticky="w")
        self.visual_text_model_var = tk.StringVar(value="qwen3.5:4b")
        self.visual_text_combo = ttk.Combobox(
            settings,
            textvariable=self.visual_text_model_var,
            values=["qwen3.5:4b", "qwen2.5-coder:7b", "deepseek-r1:7b"],
        )
        self.visual_text_combo.grid(row=0, column=3, sticky="ew", padx=(5, 10))
    
        ttk.Label(settings, text="ComfyUI URL").grid(row=0, column=4, sticky="w")
        self.comfy_url_var = tk.StringVar(value="http://127.0.0.1:8188")
        ttk.Entry(settings, textvariable=self.comfy_url_var).grid(
            row=0, column=5, sticky="ew", padx=(5, 0)
        )
    
        ttk.Label(settings, text="Checkpoint").grid(row=1, column=0, sticky="w", pady=(6, 0))
        self.comfy_checkpoint_var = tk.StringVar()
        self.comfy_checkpoint_combo = ttk.Combobox(
            settings,
            textvariable=self.comfy_checkpoint_var,
            values=[],
        )
        self.comfy_checkpoint_combo.grid(
            row=1, column=1, columnspan=3, sticky="ew", padx=(5, 10), pady=(6, 0)
        )
        ttk.Button(
            settings,
            text="Refresh checkpoints",
            command=self.refresh_comfy_checkpoints,
            style="Tool.TButton",
        ).grid(row=1, column=4, sticky="ew", pady=(6, 0))
        ttk.Button(
            settings,
            text="Test ComfyUI",
            command=self.test_comfyui,
            style="Tool.TButton",
        ).grid(row=1, column=5, sticky="ew", padx=(5, 0), pady=(6, 0))
    
        dimensions = ttk.Frame(settings)
        dimensions.grid(row=2, column=0, columnspan=6, sticky="ew", pady=(6, 0))
        for column in range(10):
            dimensions.grid_columnconfigure(column, weight=1)
        self.visual_width_var = tk.IntVar(value=512)
        self.visual_height_var = tk.IntVar(value=512)
        self.visual_steps_var = tk.IntVar(value=20)
        self.visual_cfg_var = tk.DoubleVar(value=7.0)
        self.visual_seed_var = tk.IntVar(value=-1)
        pairs = [
            ("Width", self.visual_width_var),
            ("Height", self.visual_height_var),
            ("Steps", self.visual_steps_var),
            ("CFG", self.visual_cfg_var),
            ("Seed (-1=random)", self.visual_seed_var),
        ]
        for index, (label, variable) in enumerate(pairs):
            ttk.Label(dimensions, text=label).grid(row=0, column=index * 2, sticky="e", padx=(4, 2))
            ttk.Entry(dimensions, textvariable=variable, width=10).grid(
                row=0, column=index * 2 + 1, sticky="ew", padx=(2, 4)
            )
    
        actions = ttk.Frame(outer)
        actions.grid(row=1, column=0, sticky="ew", pady=(6, 6))
        self._button_grid(
            actions,
            [
                ("Add reference images", self.add_visual_images),
                ("Remove selected", self.remove_visual_images),
                ("Analyze references", self.analyze_visual_references),
                ("Generate 11th image", self.generate_visual_image),
                ("Open output folder", self.open_visual_output_folder),
                ("Clear session", self.clear_visual_session),
            ],
            columns=3,
            primary_index=3,
        )
    
        main_frame = ttk.Frame(outer)
        main_frame.grid(row=2, column=0, sticky="nsew")
        main_frame.grid_rowconfigure(1, weight=1)
        main_frame.grid_columnconfigure(0, weight=1)
    
        references = ttk.LabelFrame(main_frame, text="Up to 10 reference images", padding=5)
        references.grid(row=0, column=0, sticky="ew", pady=(0, 5))
        references.grid_rowconfigure(0, weight=1)
        references.grid_columnconfigure(0, weight=1)
        ref_frame = ttk.Frame(references)
        ref_frame.grid(row=0, column=0, sticky="nsew")
        ref_frame.grid_rowconfigure(0, weight=1)
        ref_frame.grid_columnconfigure(0, weight=1)
        self.visual_image_listbox = tk.Listbox(
            ref_frame,
            height=2,
            selectmode="extended",
            exportselection=False,
        )
        ref_y = ttk.Scrollbar(ref_frame, orient="vertical", command=self.visual_image_listbox.yview)
        ref_x = ttk.Scrollbar(ref_frame, orient="horizontal", command=self.visual_image_listbox.xview)
        self.visual_image_listbox.configure(yscrollcommand=ref_y.set, xscrollcommand=ref_x.set)
        self.visual_image_listbox.grid(row=0, column=0, sticky="nsew")
        ref_y.grid(row=0, column=1, sticky="ns")
        ref_x.grid(row=1, column=0, sticky="ew")
        self.visual_count_var = tk.StringVar(value="0 / 10 images")
        ttk.Label(references, textvariable=self.visual_count_var).grid(
            row=1, column=0, sticky="ew", pady=(3, 0)
        )
        lower = ttk.Frame(main_frame)
        lower.grid(row=1, column=0, sticky="nsew")
        lower.grid_rowconfigure(0, weight=1)
        lower.grid_columnconfigure(0, weight=3)
        lower.grid_columnconfigure(1, weight=2)
        middle = ttk.LabelFrame(lower, text="Goal, analyses, and synthesized prompt", padding=6)
        right = ttk.LabelFrame(lower, text="Generated image preview", padding=6)
        middle.grid(row=0, column=0, sticky="nsew", padx=(0, 4))
        right.grid(row=0, column=1, sticky="nsew", padx=(4, 0))
        middle.grid_rowconfigure(7, weight=1)
        middle.grid_columnconfigure(0, weight=1)
        right.grid_rowconfigure(0, weight=1)
        right.grid_columnconfigure(0, weight=1)
    
        ttk.Label(middle, text="What should the new image accomplish?").grid(
            row=0, column=0, sticky="w"
        )
        self.visual_goal_text = tk.Text(middle, height=3, wrap="word", font=("Segoe UI", 10))
        self.visual_goal_text.grid(row=1, column=0, sticky="ew", pady=(2, 4))
        self.visual_goal_text.insert(
            "1.0",
            "Create a novel image that preserves the shared visual language of the references while using a new composition and a clearly distinct focal idea.",
        )
    
        ttk.Label(middle, text="Negative prompt / exclusions").grid(row=2, column=0, sticky="w")
        self.visual_negative_var = tk.StringVar(
            value="blurry, low resolution, illegible text, duplicate composition, watermark"
        )
        ttk.Entry(middle, textvariable=self.visual_negative_var).grid(
            row=3, column=0, sticky="ew", pady=(2, 4)
        )
    
        ttk.Label(middle, text="Editable positive generation prompt").grid(
            row=4, column=0, sticky="w"
        )
        positive_scroll, self.visual_positive_text = self._scrolled_text(middle, height=4)
        positive_scroll.grid(row=5, column=0, sticky="ew", pady=(2, 4))
    
        ttk.Label(middle, text="Reference analyses and design summary").grid(
            row=6, column=0, sticky="w"
        )
        result_scroll, self.visual_result_text = self._scrolled_text(middle, height=8)
        result_scroll.grid(row=7, column=0, sticky="nsew", pady=(2, 0))
    
        self.visual_preview_label = ttk.Label(
            right,
            text="The generated eleventh image will appear here.",
            anchor="center",
            justify="center",
        )
        self.visual_preview_label.grid(row=0, column=0, sticky="nsew")
        self.visual_output_var = tk.StringVar(value="No image generated")
        ttk.Label(right, textvariable=self.visual_output_var).grid(
            row=1, column=0, sticky="ew", pady=(5, 0)
        )
    
        self.visual_status_var = tk.StringVar(
            value="Pipeline: Ollama vision analysis -> Ollama prompt synthesis -> local ComfyUI generation."
        )
        ttk.Label(outer, textvariable=self.visual_status_var).grid(
            row=3, column=0, sticky="ew", pady=(5, 0)
        )
    
    def add_visual_images(self) -> None:
        remaining = 10 - len(self.visual_images)
        if remaining <= 0:
            messagebox.showinfo("Maximum reached", "The session already contains 10 images.")
            return
        paths = filedialog.askopenfilenames(
            title=f"Choose up to {remaining} reference images",
            filetypes=[
                ("Images", "*.png *.jpg *.jpeg *.webp *.bmp *.gif"),
                ("All files", "*.*"),
            ],
        )
        for name in paths:
            path = Path(name).expanduser().resolve()
            if path not in self.visual_images and len(self.visual_images) < 10:
                self.visual_images.append(path)
                self.visual_image_listbox.insert("end", str(path))
        self.visual_count_var.set(f"{len(self.visual_images)} / 10 images")

    def remove_visual_images(self) -> None:
        selected = list(self.visual_image_listbox.curselection())
        for index in reversed(selected):
            self.visual_image_listbox.delete(index)
            del self.visual_images[index]
        self.visual_count_var.set(f"{len(self.visual_images)} / 10 images")
        self.visual_analyses = []
        self.visual_prompt_data = {}

    def clear_visual_session(self) -> None:
        self.visual_images.clear()
        self.visual_image_listbox.delete(0, "end")
        self.visual_count_var.set("0 / 10 images")
        self.visual_analyses = []
        self.visual_prompt_data = {}
        self.visual_result_text.delete("1.0", "end")
        self.visual_positive_text.delete("1.0", "end")
        self.visual_output_path = None
        self.visual_preview_photo = None
        self.visual_preview_label.configure(
            image="", text="The generated eleventh image will appear here."
        )
        self.visual_output_var.set("No image generated")

    def test_comfyui(self) -> None:
        url = self.comfy_url_var.get().strip()
        self.visual_status_var.set("Testing ComfyUI connection...")
        threading.Thread(target=self._test_comfy_worker, args=(url,), daemon=True).start()

    def _test_comfy_worker(self, url: str) -> None:
        try:
            data = ComfyUIClient(url).test()
            self.events.put({"kind": "comfy_test", "ok": True, "data": data})
        except Exception as exc:
            self.events.put(
                {"kind": "comfy_test", "ok": False, "error": f"{type(exc).__name__}: {exc}"}
            )

    def refresh_comfy_checkpoints(self) -> None:
        url = self.comfy_url_var.get().strip()
        self.visual_status_var.set("Reading ComfyUI checkpoints...")
        threading.Thread(target=self._checkpoint_worker, args=(url,), daemon=True).start()

    def _checkpoint_worker(self, url: str) -> None:
        try:
            checkpoints = ComfyUIClient(url).checkpoints()
            self.events.put({"kind": "comfy_checkpoints", "checkpoints": checkpoints})
        except Exception as exc:
            self.events.put(
                {"kind": "visual_error", "error": f"{type(exc).__name__}: {exc}"}
            )

    def _visual_snapshot(self) -> dict[str, Any] | None:
        if not self.visual_images:
            messagebox.showinfo("Add images", "Add between 1 and 10 reference images first.")
            return None
        missing = [str(path) for path in self.visual_images if not path.exists()]
        if missing:
            messagebox.showerror("Missing images", "\n".join(missing))
            return None
        return {
            "images": list(self.visual_images),
            "vision_model": self.visual_vision_model_var.get().strip(),
            "text_model": self.visual_text_model_var.get().strip(),
            "goal": self.visual_goal_text.get("1.0", "end").strip(),
            "negative": self.visual_negative_var.get().strip(),
            "positive_prompt": self.visual_positive_text.get("1.0", "end").strip(),
            "comfy_url": self.comfy_url_var.get().strip(),
            "checkpoint": self.comfy_checkpoint_var.get().strip(),
            "width": int(self.visual_width_var.get()),
            "height": int(self.visual_height_var.get()),
            "steps": int(self.visual_steps_var.get()),
            "cfg": float(self.visual_cfg_var.get()),
            "seed": int(self.visual_seed_var.get()),
        }

    def analyze_visual_references(self) -> None:
        snapshot = self._visual_snapshot()
        if not snapshot:
            return
        self.visual_status_var.set("Analyzing references with the selected vision model...")
        self.set_status("Analyzing reference images...")
        threading.Thread(
            target=self._visual_analysis_worker,
            args=(snapshot,),
            daemon=True,
        ).start()

    def _visual_analysis_worker(self, snapshot: dict[str, Any]) -> None:
        def progress(message: str) -> None:
            self.events.put({"kind": "visual_progress", "message": message})

        try:
            analyses = analyze_references(
                self.client,
                snapshot["images"],
                vision_model=snapshot["vision_model"],
                goal=snapshot["goal"],
                progress=progress,
            )
            prompt_data = synthesize_generation_prompt(
                self.client,
                analyses,
                text_model=snapshot["text_model"],
                goal=snapshot["goal"],
                negative_prompt=snapshot["negative"],
            )
            self.events.put(
                {
                    "kind": "visual_analyzed",
                    "analyses": analyses,
                    "prompt_data": prompt_data,
                }
            )
        except Exception as exc:
            self.events.put(
                {"kind": "visual_error", "error": f"{type(exc).__name__}: {exc}"}
            )

    def generate_visual_image(self) -> None:
        snapshot = self._visual_snapshot()
        if not snapshot:
            return
        # An edited positive prompt takes precedence over the prior synthesized prompt.
        if snapshot.get("positive_prompt"):
            snapshot["prompt_data"] = {
                "positive_prompt": snapshot["positive_prompt"],
                "negative_prompt": snapshot["negative"],
                "design_summary": self.visual_prompt_data.get(
                    "design_summary", "User-edited prompt"
                ),
            }
        elif self.visual_prompt_data.get("positive_prompt"):
            snapshot["prompt_data"] = dict(self.visual_prompt_data)
        self.visual_status_var.set("Preparing the eleventh image...")
        self.set_status("Generating new image...")
        threading.Thread(
            target=self._visual_generate_worker,
            args=(snapshot,),
            daemon=True,
        ).start()

    def _visual_generate_worker(self, snapshot: dict[str, Any]) -> None:
        def progress(message: str) -> None:
            self.events.put({"kind": "visual_progress", "message": message})

        try:
            prompt_data = snapshot.get("prompt_data")
            analyses = list(self.visual_analyses)
            if not prompt_data:
                analyses = analyze_references(
                    self.client,
                    snapshot["images"],
                    vision_model=snapshot["vision_model"],
                    goal=snapshot["goal"],
                    progress=progress,
                )
                prompt_data = synthesize_generation_prompt(
                    self.client,
                    analyses,
                    text_model=snapshot["text_model"],
                    goal=snapshot["goal"],
                    negative_prompt=snapshot["negative"],
                )
            positive = str(prompt_data.get("positive_prompt", "")).strip()
            negative = str(prompt_data.get("negative_prompt", snapshot["negative"])).strip()
            if not positive:
                raise ValueError("The synthesized positive prompt is empty.")

            progress("Submitting synthesized prompt to ComfyUI...")
            workflow = build_txt2img_workflow(
                checkpoint=snapshot["checkpoint"],
                positive_prompt=positive,
                negative_prompt=negative,
                width=snapshot["width"],
                height=snapshot["height"],
                steps=snapshot["steps"],
                cfg=snapshot["cfg"],
                seed=snapshot["seed"],
            )
            comfy = ComfyUIClient(snapshot["comfy_url"])
            prompt_id = comfy.queue_workflow(workflow)
            progress(f"ComfyUI queued prompt {prompt_id}")
            descriptors = comfy.wait_for_images(prompt_id, progress=progress)
            output_dir = self.paths.downloads / "visual_synthesis"
            output_name = f"synthesis-{datetime.now():%Y%m%d-%H%M%S}.png"
            output_path = comfy.download_image(descriptors[0], output_dir / output_name)
            self.events.put(
                {
                    "kind": "visual_generated",
                    "path": str(output_path),
                    "analyses": analyses,
                    "prompt_data": prompt_data,
                    "prompt_id": prompt_id,
                }
            )
        except Exception as exc:
            self.events.put(
                {"kind": "visual_error", "error": f"{type(exc).__name__}: {exc}"}
            )

    def _render_visual_analysis(self) -> None:
        lines = []
        for index, item in enumerate(self.visual_analyses, start=1):
            lines.extend(
                [
                    f"===== REFERENCE {index}: {Path(item['image']).name} =====",
                    item["analysis"],
                    "",
                ]
            )
        if self.visual_prompt_data:
            lines.extend(
                [
                    "===== DESIGN SUMMARY =====",
                    self.visual_prompt_data.get("design_summary", ""),
                ]
            )
            self.visual_positive_text.delete("1.0", "end")
            self.visual_positive_text.insert(
                "1.0", self.visual_prompt_data.get("positive_prompt", "")
            )
            if self.visual_prompt_data.get("negative_prompt"):
                self.visual_negative_var.set(
                    self.visual_prompt_data.get("negative_prompt", "")
                )
        self.visual_result_text.delete("1.0", "end")
        self.visual_result_text.insert("1.0", "\n".join(lines))

    def _show_visual_preview(self, path: Path) -> None:
        try:
            from PIL import Image, ImageTk
        except ImportError:
            self.visual_preview_label.configure(
                text=f"Generated image saved to:\n{path}\n\nInstall Pillow for in-app preview."
            )
            return
        image = Image.open(path)
        image.thumbnail((650, 650))
        self.visual_preview_photo = ImageTk.PhotoImage(image)
        self.visual_preview_label.configure(image=self.visual_preview_photo, text="")

    def open_visual_output_folder(self) -> None:
        open_folder(self.paths.downloads / "visual_synthesis")

    def handle_visual_event(self, event: dict[str, Any]) -> bool:
        kind = event.get("kind")
        if kind == "visual_progress":
            message = str(event.get("message", ""))
            self.visual_status_var.set(message)
            self.log(f"Visual synthesis: {message}")
            return True
        if kind == "visual_analyzed":
            self.visual_analyses = event.get("analyses", [])
            self.visual_prompt_data = event.get("prompt_data", {})
            self._render_visual_analysis()
            self.visual_status_var.set(
                "Reference analysis and prompt synthesis complete. Review the prompt, then generate."
            )
            self.set_status("Visual analysis complete")
            self.log(f"Analyzed {len(self.visual_analyses)} visual references")
            return True
        if kind == "visual_generated":
            self.visual_analyses = event.get("analyses", [])
            self.visual_prompt_data = event.get("prompt_data", {})
            self.visual_output_path = Path(event["path"])
            self._render_visual_analysis()
            self._show_visual_preview(self.visual_output_path)
            self.visual_output_var.set(str(self.visual_output_path))
            self.visual_status_var.set("Eleventh image generated successfully.")
            self.set_status("Image generation complete")
            self.log(
                f"Generated visual synthesis image {self.visual_output_path} "
                f"from ComfyUI prompt {event.get('prompt_id')}"
            )
            return True
        if kind == "visual_error":
            error = str(event.get("error", "Unknown error"))
            self.visual_status_var.set("Visual synthesis failed")
            self.set_status("Visual synthesis failed")
            self.log(f"Visual synthesis ERROR: {error}")
            messagebox.showerror("Visual synthesis error", error)
            return True
        if kind == "comfy_test":
            if event.get("ok"):
                self.visual_status_var.set("ComfyUI is reachable.")
                self.log("ComfyUI connection test passed")
                messagebox.showinfo("ComfyUI", "ComfyUI is reachable at the configured URL.")
            else:
                error = str(event.get("error", "Unknown error"))
                self.visual_status_var.set("ComfyUI connection failed")
                self.log(f"ComfyUI test ERROR: {error}")
                messagebox.showerror("ComfyUI connection failed", error)
            return True
        if kind == "comfy_checkpoints":
            checkpoints = list(event.get("checkpoints", []))
            self.comfy_checkpoint_combo["values"] = checkpoints
            if checkpoints and not self.comfy_checkpoint_var.get().strip():
                self.comfy_checkpoint_var.set(checkpoints[0])
            self.visual_status_var.set(f"Found {len(checkpoints)} ComfyUI checkpoint(s).")
            self.log(f"Loaded {len(checkpoints)} ComfyUI checkpoints")
            if not checkpoints:
                messagebox.showwarning(
                    "No checkpoints found",
                    "ComfyUI is reachable, but no CheckpointLoaderSimple models were reported.",
                )
            return True
        return False
