from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path


def check(name: str, condition: bool, details: str = "") -> None:
    if not condition:
        raise AssertionError(f"{name} failed. {details}")
    print(f"PASS  {name}" + (f" - {details}" if details else ""))


def main() -> int:
    parser = argparse.ArgumentParser(description="Ollama Job Automation Studio self-test")
    parser.add_argument("--live", action="store_true", help="also test local Ollama and ComfyUI services")
    parser.add_argument("--comfy-url", default="http://127.0.0.1:8188")
    args = parser.parse_args()

    root = Path(__file__).resolve().parent
    sys.path.insert(0, str(root))

    import tkinter
    from ojas.browser import FieldMapper
    from ojas.core import MODEL_CATALOG, default_rules
    from ojas.ollama_api import OllamaClient
    from ojas.rag import RAGStore
    from ojas.resume_ats import (
        analyze_resume,
        donovan_seed_profile,
        extract_pdf_text,
        profile_metrics,
    )
    from ojas.tab_help import TAB_HELP, TAB_ORDER
    from ojas.visual_synthesis import ComfyUIClient, build_txt2img_workflow

    check("Tkinter import", hasattr(tkinter, "Tk"))
    check("Recommended model catalog", len(MODEL_CATALOG) >= 6, f"{len(MODEL_CATALOG)} models")
    check("Tab help coverage", set(TAB_ORDER) <= set(TAB_HELP), f"{len(TAB_HELP)} descriptions")

    resume = root / "sample_data" / "DonovanZeanahResume-2026.pdf"
    text, pages, _ = extract_pdf_text(resume)
    check("Bundled resume exists", resume.exists(), str(resume))
    check("Resume PDF extraction", pages == 4 and len(text) > 5000, f"{pages} pages, {len(text)} chars")

    report = analyze_resume(text, pages=pages)
    check("ATS report metrics", len(report.metrics) == 8, f"score={report.overall_score}")
    check("Resume contact detection", report.metrics[0].score >= 7.5)
    check("Resume skill detection", len(report.detected_skills) >= 20, f"{len(report.detected_skills)} skills")

    profile = donovan_seed_profile(resume)
    metrics = profile_metrics(profile, report)
    check("Resume profile seed", profile["identity"]["first_name"] == "Donovan")
    check("Work history seed", metrics["work_history_entries"] >= 4)
    check("Missing facts not invented", not profile["links"]["linkedin"] and not profile["links"]["github"])

    mapper = FieldMapper(profile, default_rules())
    safe = mapper.map_field(
        {
            "label": "First Name", "name": "first_name", "id": "", "placeholder": "",
            "aria_label": "", "autocomplete": "given-name", "type": "text", "tag": "input",
            "disabled": False, "read_only": False,
        }
    )
    manual = mapper.map_field(
        {
            "label": "Desired salary", "name": "salary", "id": "", "placeholder": "",
            "aria_label": "", "autocomplete": "", "type": "text", "tag": "input",
            "disabled": False, "read_only": False,
        }
    )
    check("Safe form mapping", safe["status"] == "safe" and safe["proposed"] == "Donovan")
    check("Sensitive form blocking", manual["status"] == "manual")

    chunks = RAGStore.chunk_text("Header\n\n" + "content " * 1000)
    check("RAG chunking", len(chunks) >= 2, f"{len(chunks)} chunks")

    workflow = build_txt2img_workflow(
        checkpoint="test.safetensors",
        positive_prompt="a novel workshop robot",
        negative_prompt="blurry",
        width=513,
        height=519,
        steps=20,
        cfg=7.0,
        seed=123,
    )
    check("ComfyUI workflow graph", workflow["4"]["inputs"]["ckpt_name"] == "test.safetensors")
    check("Image dimensions normalized", workflow["5"]["inputs"]["width"] % 8 == 0)

    if args.live:
        models = OllamaClient().list_models()
        check("Live Ollama API", isinstance(models, list), f"{len(models)} installed models")
        comfy = ComfyUIClient(args.comfy_url)
        comfy.test()
        check("Live ComfyUI API", True, args.comfy_url)
        checkpoints = comfy.checkpoints()
        check("ComfyUI checkpoint discovery", bool(checkpoints), f"{len(checkpoints)} checkpoints")

    print("\nALL REQUESTED SELF-TESTS PASSED")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"\nFAIL  {type(exc).__name__}: {exc}", file=sys.stderr)
        raise
