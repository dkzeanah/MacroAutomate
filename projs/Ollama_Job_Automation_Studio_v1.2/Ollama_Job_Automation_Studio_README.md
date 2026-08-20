# Ollama Job Automation Studio 1.2

A local Windows-oriented Python GUI for managing Ollama models, testing text and
vision models, indexing private documents, maintaining a verified applicant
profile, running an ATS-style resume diagnostic, assisting with reviewed job-form
autofill, and creating a new image from up to ten visual references.

## Main features

- Recommended Ollama memory settings:
  - `OLLAMA_MAX_LOADED_MODELS=1`
  - `OLLAMA_NUM_PARALLEL=1`
  - `OLLAMA_CONTEXT_LENGTH=8192`
- Model pulling, API checks, GPU/RAM diagnostics, and local model testing.
- Text, coding, reasoning, vision, and embedding workflows.
- SQLite RAG index for resumes, notes, source code, and documents.
- Resume-seeded verified profile based on the included
  `sample_data/DonovanZeanahResume-2026.pdf`.
- Local ATS-style PDF scanner with deterministic metrics and an optional grounded
  Ollama critique.
- Playwright job-application form inspection and reviewed autofill.
- Visual Synthesis Lab:
  - Up to ten reference images.
  - Ollama vision analysis.
  - Ollama prompt synthesis.
  - Local ComfyUI generation of an eleventh image.
- A detailed **About this tab** pop-out for every tab.
- Built-in source and logic self-tests.

## Safety behavior

The application never clicks a final application submit button.

It fills only ordinary fields that map to non-empty values in the verified
profile. It leaves sensitive, demographic, medical, veteran, disability,
work-authorization, visa, salary, criminal-history, legal-attestation, consent,
checkbox, radio, and uncertain fields for manual review.

AI-drafted text is displayed for review before it can be inserted. Resume scan
scores are diagnostic estimates, not hiring predictions.

## Install

1. Install Ollama and confirm `ollama` works in PowerShell.
2. Extract this project.
3. Double-click `install_windows.bat`.
4. Double-click `run_windows.bat`.

PowerShell alternative:

```powershell
cd path\to\ollama_job_automation_studio
python -m pip install -r requirements.txt
python -m playwright install chromium
python main.py
```

Dependencies installed by the project:

- Playwright
- pypdf
- Pillow

## First-use sequence

1. Open **Setup & Models**.
2. Click **Apply recommended settings**.
3. Restart Ollama.
4. Pull the recommended models.
5. Click **Run built-in self tests**.
6. Open **Verified Profile** and review the resume-seeded JSON.
7. Use **ATS Resume Scanner** with one exact job description.
8. Use **Model Lab** to compare models.
9. Use **Memory / RAG** to index work history, resumes, projects, and notes.
10. Use **Application Assistant** for reviewed form filling.
11. Use **Visual Synthesis** after starting a local ComfyUI server.

## Resume-seeded profile

On a new installation, an effectively blank profile is populated from the
included 2026 resume. The seed includes explicit resume facts such as name,
contact information, skills, work history, education, certification, projects,
and target-role interests.

The seed intentionally does **not** invent:

- Address
- Exact LinkedIn URL
- Exact GitHub profile URL
- Work authorization
- Visa status
- Salary
- Demographic information
- Any credential or metric not stated in the resume

Use **Load bundled 2026 resume profile** to restore the seed manually.

## ATS Resume Scanner

The scanner extracts PDF text and produces a transparent score from:

- Contact and professional-link detection
- Recognizable sections
- Technical-skill coverage
- Job-description keyword alignment
- Quantified impact statements
- Action-oriented language
- PDF extractability and readability
- Length

Paste the exact job description before scanning. The optional AI critique is
instructed to preserve truth and avoid inventing qualifications.

## Visual Synthesis and ComfyUI

The Visual Synthesis tab uses three stages:

1. A selected Ollama vision model analyzes each reference image.
2. A selected Ollama text model combines the observations into a novel prompt.
3. A local ComfyUI server runs a standard text-to-image workflow.

Typical local ComfyUI URL:

```text
http://127.0.0.1:8188
```

The tab reads checkpoint names from ComfyUI. Choose a checkpoint before
pressing **Generate 11th image**.

Defaults are conservative for a 6 GB GPU:

- 512 x 512
- 20 steps
- Batch size 1
- Euler sampler
- One generated image

The default workflow uses conceptual reference analysis. It does not retrain a
model and does not apply IP-Adapter, ControlNet, or LoRA reference conditioning.
Those can be introduced later through a custom ComfyUI workflow.

## Built-in self-test

From the project directory:

```powershell
python self_test.py
```

This tests imports, tab-help coverage, PDF extraction, ATS metrics, profile
seeding, safe/manual form mapping, RAG chunking, and ComfyUI workflow creation.

Test local services too:

```powershell
python self_test.py --live
```

The live test expects Ollama and ComfyUI to already be running.

## Responsive controls

- `F11`: toggle true full-screen mode.
- `Esc`: leave full-screen mode.
- `Ctrl+1` through `Ctrl+8`: switch tabs.
- `Ctrl+Enter`: primary action for the current work tab.
- **About this tab**: opens a detailed description for the selected tab.

Essential buttons are outside resizeable panes, text areas and tables include
scrollbars, and wide button groups wrap into multiple rows.

## Data storage

Application state is stored under:

```text
%LOCALAPPDATA%\OllamaJobAutomationStudio
```

The profile JSON is local plaintext. Do not store passwords, Social Security
numbers, medical information, API secrets, or other unnecessary sensitive data.

## Recommended model set

- `qwen3.5:4b` - primary agent and prompt synthesis
- `qwen2.5-coder:7b` - coding
- `granite3.2-vision:2b` - document vision
- `qwen3-vl:4b` - advanced visual analysis
- `deepseek-r1:7b` - reasoning fallback
- `embeddinggemma` - embeddings and RAG

## Troubleshooting

- If Ollama is unavailable, start the Ollama desktop app or click **Start Ollama server**.
- Restart Ollama after applying environment settings.
- If Playwright reports a missing browser, click **Install Playwright Chromium**.
- If visual generation fails, use **Test ComfyUI**, refresh checkpoints, and inspect **Logs**.
- If the resume scanner returns little text, the PDF may be image-only and require OCR before scanning.
- Copy the final 20-50 log lines when reporting a failure.
