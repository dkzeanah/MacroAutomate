"""Job entry point for the knowledge base and document inbox (used by lib\\KnowledgeBase.ahk).

    python -m fan.knowledge.cli <job-dir>/request.json

Like fan.autopilot.cli: one ``mode`` per request, the answer is always written
atomically to result.json, progress to status.json.
"""
from __future__ import annotations

import json
import sys
import time
import traceback
from pathlib import Path

from fan.autopilot.cli import atomic_json

from . import VERSION, intake, model
from .ingest import Knowledge

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB = ROOT / "data" / "knowledge" / "knowledge.sqlite"


def run(request: dict, job_dir: Path) -> dict:
    mode = request.get("mode", "")
    status_path = job_dir / "status.json"
    atomic_json(status_path, {"phase": "running", "mode": mode, "at": time.time()})
    deadline = time.time() + float(request["max_seconds"]) if request.get("max_seconds") else None
    knowledge = Knowledge(request.get("db") or DEFAULT_DB, prefer_extension=request.get("vector_extension", True))
    try:
        def progress(report):
            atomic_json(status_path, {"phase": "running", "mode": mode, "scanned": report["scanned"],
                                      "new_elements": report["new_elements"], "at": time.time()})

        if mode == "kb_status":
            result = {"ok": True, "stats": knowledge.store.stats(), "heads": model.head_list(knowledge.store)}
        elif mode == "kb_ingest":
            report = knowledge.ingest(request.get("paths") or [], request.get("folders") or [],
                                      recursive=request.get("recursive", True), origin=request.get("origin", "manual"),
                                      ocr=request.get("ocr", True), force=request.get("force", False),
                                      progress=progress, deadline=deadline)
            result = {"ok": True, **report, "heads": model.head_list(knowledge.store)}
        elif mode == "kb_text":
            outcome = knowledge.ingest_text(request["text"], request.get("title", "Text"), origin=request.get("origin", "text"))
            result = {"ok": True, **outcome, "stats": knowledge.store.stats()}
        elif mode == "kb_head":
            result = {"ok": True, "head_id": int(request["head_id"]),
                      "elements": model.head_detail(knowledge.store, int(request["head_id"]), int(request.get("limit", 300)), int(request.get("offset", 0)))}
        elif mode == "kb_search":
            head = request.get("head_id")
            found = knowledge.search(request.get("query", ""), int(request.get("k", 20)), int(head) if head not in (None, "", -1) else None)
            result = {"ok": True, "query": request.get("query", ""), "elements": [model._brief(e) for e in found]}
        elif mode == "kb_ask":
            result = {"ok": True, **model.ask(knowledge, request.get("question", ""), int(request.get("k", 8)))}
        elif mode == "kb_rediscover":
            result = {"ok": True, **knowledge.rediscover(), "heads": model.head_list(knowledge.store), "stats": knowledge.store.stats()}
        elif mode == "kb_rename":
            if request.get("unlock"):
                knowledge.unlock_head(int(request["head_id"]))
            else:
                knowledge.rename_head(int(request["head_id"]), request.get("name", ""))
            result = {"ok": True, "heads": model.head_list(knowledge.store)}
        elif mode == "kb_sources":
            rows = knowledge.db.execute("SELECT id, path, title, kind, status, error, elements, pages, method, origin, updated "
                                        "FROM source ORDER BY updated DESC LIMIT ?", (int(request.get("limit", 500)),)).fetchall()
            result = {"ok": True, "sources": [dict(r) for r in rows]}
        elif mode == "kb_forget_source":
            knowledge.forget_source(int(request["source_id"]))
            result = {"ok": True, "stats": knowledge.store.stats()}
        elif mode == "kb_export":
            result = model.export_pack(knowledge.store, request.get("out_dir") or (ROOT / "data" / "knowledge" / "export"))
        elif mode == "intake_scan":
            report = intake.scan(knowledge, request.get("folders") or [], use_ai=bool(request.get("use_ai")), request=request, deadline=deadline)
            result = {"ok": True, **report, "records_list": intake.records(knowledge, limit=300)}
        elif mode == "intake_records":
            result = {"ok": True, "records_list": intake.records(knowledge, request.get("status", ""), int(request.get("limit", 300)))}
        elif mode == "intake_update":
            intake.update_record(knowledge, int(request["record_id"]), fields=request.get("fields"), status=request.get("status"),
                                 note=request.get("note"))
            result = {"ok": True, "records_list": intake.records(knowledge, limit=300)}
        elif mode == "intake_export":
            result = intake.export_csv(knowledge, request.get("out_dir") or (ROOT / "data" / "intake" / "exports"),
                                       only_new=request.get("only_new", True))
            result["records_list"] = intake.records(knowledge, limit=300)
        elif mode == "intake_variables":
            row = next((r for r in intake.records(knowledge, limit=100000) if r["id"] == int(request["record_id"])), None)
            if row is None:
                raise ValueError("Record not found")
            result = {"ok": True, "variables": intake.workflow_variables(row), "record": row}
        else:
            result = {"ok": False, "error": f"Unknown knowledge mode '{mode}'"}
    finally:
        knowledge.close()
    result.setdefault("mode", mode)
    result["version"] = VERSION
    return result


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 1:
        print("usage: python -m fan.knowledge.cli <request.json>", file=sys.stderr)
        return 2
    request_path = Path(argv[0])
    job_dir = request_path.parent
    try:
        request = json.loads(request_path.read_text(encoding="utf-8-sig"))
        result = run(request, job_dir)
    except Exception as error:
        result = {"ok": False, "error": f"{type(error).__name__}: {error}", "trace": traceback.format_exc(limit=6)[-2000:],
                  "version": VERSION}
    atomic_json(job_dir / "result.json", result)
    atomic_json(job_dir / "status.json", {"phase": "complete", "ok": bool(result.get("ok")), "at": time.time()})
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
