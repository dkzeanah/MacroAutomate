from __future__ import annotations

import tkinter as tk
from tkinter import ttk


TAB_HELP: dict[str, tuple[str, str]] = {
    "setup": (
        "Setup & Models",
        """PURPOSE
This is the control center for preparing Ollama and confirming that your computer can run the recommended local models.

HOW TO USE IT
1. Apply the recommended Ollama environment settings.
2. Restart Ollama after changing those settings.
3. Test the Ollama API.
4. Install the Python and Playwright dependencies when needed.
5. Pull one or all recommended models.
6. Refresh the installed-model list and inspect currently loaded models.

WHAT IT DOES
It configures conservative memory behavior for a system with limited VRAM:
- OLLAMA_MAX_LOADED_MODELS=1
- OLLAMA_NUM_PARALLEL=1
- OLLAMA_CONTEXT_LENGTH=8192

It also distinguishes between Ollama being installed, the Ollama server being reachable, a model being downloaded, and a model being loaded into RAM or VRAM.

WHAT IT DEMONSTRATES
A useful local AI system can route work to specialized models instead of forcing one model to do everything. The primary model handles general work, the coder handles source code, vision models inspect images, the reasoning model handles difficult planning, and the embedding model creates searchable memory.""",
    ),
    "model_lab": (
        "Model Lab",
        """PURPOSE
This is the direct testing area for every installed Ollama model. Use it to compare general text, coding, reasoning, vision, prompt behavior, and speed.

HOW TO USE IT
1. Choose a model.
2. Set temperature and context length.
3. Optionally attach an image for a vision-capable model.
4. Enter a system instruction describing how the model should behave.
5. Enter the actual user prompt.
6. Click Send prompt or press Ctrl+Enter.

WHAT THE CONTROLS MEAN
- Model: chooses the Ollama model receiving the request.
- Temperature: low values are more repeatable; higher values are more varied.
- Context: maximum working context requested from Ollama. Larger values consume more memory.
- System instruction: persistent behavioral instruction for the request.
- User prompt: the task or question.
- Optional image: sends one image to a vision-capable model.

WHAT IT DOES
It sends a native Ollama /api/chat request and reports elapsed time, input tokens, output tokens, and approximate output speed.

WHAT IT DEMONSTRATES
Different local models have different strengths. Model selection, prompt wording, context size, and temperature all affect quality, speed, and memory use.""",
    ),
    "rag": (
        "Memory / RAG",
        """PURPOSE
This tab gives the local assistant searchable memory over your own files. RAG means Retrieval-Augmented Generation.

HOW TO USE IT
1. Add files or folders containing resumes, project notes, work history, source code, or other reference material.
2. Build or update the index.
3. Enter a question.
4. Use Search sources to inspect raw matching excerpts.
5. Use Ask with context to retrieve excerpts and have a model answer from them.

WHAT IT DOES
The tab reads supported files, divides them into chunks, embeds each chunk with embeddinggemma, stores vectors in SQLite, embeds your question, compares vectors using cosine similarity, and retrieves the closest passages.

SEARCH SOURCES VS ASK WITH CONTEXT
Search sources is for auditing retrieval. Ask with context adds a grounded generation step and asks the selected text model to cite the retrieved source numbers.

WHAT IT DEMONSTRATES
Private local knowledge can be updated without retraining a model. Retrieval provides evidence; generation turns that evidence into a readable answer. The model should not invent information that the retrieved sources do not contain.""",
    ),
    "profile": (
        "Verified Profile",
        """PURPOSE
This tab stores trusted facts that the application assistant is allowed to use. It is the structured source of truth for identity, contact details, links, work history, education, resume path, skills, certifications, target roles, and verified facts.

HOW TO USE IT
1. Review the profile JSON on the left.
2. Use Load bundled 2026 resume profile to restore the profile seeded from Donovan's supplied resume.
3. Correct or complete facts that you can personally verify.
4. Choose the resume file.
5. Validate and save.
6. Review mapping rules on the right.

WHAT IT DOES
It separates trusted structured data from generated language. Empty values are skipped. Invalid JSON is rejected. Manual-only keywords prevent consequential or sensitive questions from being treated as ordinary autofill fields.

SAFE ALIASES
Aliases connect labels such as First Name, Given Name, and FName to one verified profile field.

MANUAL-ONLY RULES
Salary, authorization, sponsorship, demographics, disability, criminal history, consent, certification, and signatures remain manual even when a field label resembles a safe alias.

WHAT IT DEMONSTRATES
Reliable automation requires a source-of-truth database, explicit uncertainty, and a boundary between verified facts, generated prose, and decisions that belong to the user.""",
    ),
    "ats": (
        "ATS Resume Scanner",
        """PURPOSE
This is a local ATS-style resume analyzer. It simulates common automated screening operations without claiming to reproduce any employer's proprietary system.

HOW TO USE IT
1. Choose a PDF resume.
2. Paste the exact job description for one role.
3. Click Analyze resume.
4. Review the score breakdown, matched terms, missing terms, warnings, and improvement tips.
5. Optionally ask the local model for a grounded critique.
6. Export the report when you want a record of the analysis.

WHAT IT DOES
The deterministic scanner extracts PDF text and measures contact detection, recognizable sections, technical-skill coverage, job-description keyword alignment, quantified impact, action-oriented language, PDF extractability, readability, and length. It never decides whether a person should be hired.

WHAT IT DEMONSTRATES
Automated screening is largely an information-retrieval and ranking problem: can the document be parsed, does it contain the requested language, and is there evidence supporting the match? The best way to improve is not keyword stuffing; it is truthful alignment between the job description and clear evidence in the resume.

IMPORTANT
Scores are diagnostic estimates. Different employers and ATS products use different rules, configurations, and human review processes.""",
    ),
    "application": (
        "Application Assistant",
        """PURPOSE
This is the browser automation part of the program. It opens a dedicated browser profile, inspects application forms, proposes verified values, and fills only reviewed safe fields.

HOW TO USE IT
1. Save the Verified Profile.
2. Start the dedicated browser.
3. Navigate to a job application.
4. Log in manually when needed.
5. Open the application form and click Inspect page.
6. Review every detected field and status.
7. Apply selected safe fields or all safe fields.
8. Manually answer sensitive, legal, uncertain, or consequential questions.
9. Review and submit the application yourself in the browser.

STATUS MEANINGS
- Safe: matched a non-empty verified ordinary profile value.
- Manual: sensitive, legal, compensation, authorization, attestation, checkbox, or radio field.
- Missing: the profile field was recognized but is empty.
- Unknown: no confident mapping was found.
- Ignored: hidden, disabled, read-only, password, or button control.

WHAT IT DOES
It combines DOM inspection, deterministic aliases, safety rules, optional AI drafting, explicit review, and Playwright browser automation. The program never presses the final submit button.

WHAT IT DEMONSTRATES
AI works best as one component of a controlled automation system. Deterministic code performs known actions, the model assists with language, and the user remains responsible for consequential decisions.""",
    ),
    "visual": (
        "Visual Synthesis Lab",
        """PURPOSE
This tab accepts up to ten related reference images, analyzes them with an Ollama vision model, identifies shared patterns and useful differences, synthesizes a new generation prompt, and sends that prompt to a local ComfyUI server to create an eleventh image.

HOW TO USE IT
1. Start Ollama and install a vision model such as qwen3-vl:4b.
2. Start a local ComfyUI server, normally at http://127.0.0.1:8188.
3. Add between one and ten related images.
4. Describe what the new image should accomplish rather than asking for a copy.
5. Refresh the checkpoint list and choose a checkpoint that exists in ComfyUI.
6. Analyze references.
7. Review or edit the synthesized prompt.
8. Generate the eleventh image.

WHAT IT DOES
The default pipeline performs conceptual reference learning rather than model training. Each image is independently described by a vision model. A text model combines the observations into a novel prompt that preserves recurring design language while requesting a new composition. ComfyUI performs the actual diffusion generation.

WHAT IT DEMONSTRATES
A multimodel AI workflow can use perception, synthesis, and generation as separate stages. The vision model extracts information, the language model plans a new concept, and the diffusion model renders it.

LIMITATION
The default workflow does not retrain a model or directly condition on reference-image embeddings. Advanced IP-Adapter, ControlNet, LoRA, or custom ComfyUI workflows can be added later for stronger visual-reference adherence.""",
    ),
    "logs": (
        "Logs",
        """PURPOSE
This tab records what the program is doing and is the first place to inspect when an operation appears to fail.

HOW TO USE IT
Review the latest entries after model downloads, API tests, RAG indexing, browser operations, ATS scans, image analysis, or generation. Copy the log when reporting an issue. Open the logs folder to inspect persistent daily files.

WHAT IT DOES
It records command starts, streamed command output, exit codes, Ollama status, model requests, indexing progress, browser navigation, form inspection, autofill operations, screenshots, ATS results, visual-synthesis progress, and errors.

WHAT IT DEMONSTRATES
Automation needs observability. Logs distinguish between an action that never started, one that is still running, one that completed, and one that failed because of a dependency, model, file, API, browser, or website problem.

USEFUL ERROR REPORT
Include what you clicked, what you expected, what happened, the final 20-50 log lines, and any traceback or dialog text.""",
    ),
}

TAB_ORDER = [
    "setup",
    "model_lab",
    "rag",
    "profile",
    "ats",
    "application",
    "visual",
    "logs",
]


class TabHelpMixin:
    def show_current_tab_help(self) -> None:
        try:
            index = self.notebook.index(self.notebook.select())
        except Exception:
            index = 0
        key = TAB_ORDER[index] if 0 <= index < len(TAB_ORDER) else "setup"
        self.show_tab_help(key)

    def show_tab_help(self, key: str) -> None:
        title, content = TAB_HELP.get(key, ("About this tab", "No description is available."))
        window = tk.Toplevel(self.root)
        window.title(f"About: {title}")
        window.geometry("780x720")
        window.minsize(560, 420)
        window.transient(self.root)
        window.grid_rowconfigure(0, weight=1)
        window.grid_columnconfigure(0, weight=1)

        frame = ttk.Frame(window, padding=10)
        frame.grid(row=0, column=0, sticky="nsew")
        frame.grid_rowconfigure(1, weight=1)
        frame.grid_columnconfigure(0, weight=1)

        ttk.Label(frame, text=title, style="Title.TLabel").grid(row=0, column=0, sticky="w")

        text_frame, text = self._scrolled_text(frame, wrap="word", height=30)
        text_frame.grid(row=1, column=0, sticky="nsew", pady=(8, 8))
        text.insert("1.0", content)
        text.configure(state="disabled")

        buttons = ttk.Frame(frame)
        buttons.grid(row=2, column=0, sticky="ew")
        buttons.grid_columnconfigure(0, weight=1)
        buttons.grid_columnconfigure(1, weight=1)

        def copy_description() -> None:
            self.root.clipboard_clear()
            self.root.clipboard_append(content)

        ttk.Button(buttons, text="Copy description", command=copy_description).grid(
            row=0, column=0, sticky="ew", padx=(0, 4)
        )
        ttk.Button(buttons, text="Close", command=window.destroy).grid(
            row=0, column=1, sticky="ew", padx=(4, 0)
        )
