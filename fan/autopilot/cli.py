"""Job entry point used by lib/Autopilot.ahk.

    python -m fan.autopilot.cli <job-dir>/request.json

The request names a ``mode``; the answer is written atomically to
``result.json`` next to it (``status.json`` shows progress). The process always
writes a result, even on failure, so the app never waits on a silent job.
"""
from __future__ import annotations

import json
import os
import sys
import time
import traceback
from datetime import datetime
from pathlib import Path

from . import VERSION, compiler, portal, routines
from .catalog import Catalog, validate
from .llm import ChatClient, resolve_key


def atomic_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + ".tmp")
    with temp.open("w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, separators=(",", ":"))
        handle.flush()
        os.fsync(handle.fileno())
    for attempt in range(20):
        try:
            os.replace(temp, path)
            return
        except PermissionError:  # the app may be reading the previous file
            if attempt == 19:
                raise
            time.sleep(0.05)


def run(request: dict, job_dir: Path) -> dict:
    mode = request.get("mode", "")
    status = job_dir / "status.json"
    atomic_json(status, {"phase": "running", "mode": mode, "at": time.time()})
    if mode == "routines":
        now = datetime.strptime(request["now"], "%Y-%m-%d %H:%M:%S") if request.get("now") else None
        result = routines.find_routines(request["db"], lookback_days=int(request.get("lookback_days", 30)), now=now,
                                        excluded=request.get("excluded") or [],
                                        min_occurrences=int(request.get("min_occurrences", 3)),
                                        limit=int(request.get("limit", 25)))
    elif mode == "compile":
        catalog = Catalog(request.get("catalog"), request.get("context"))
        client = None
        if request.get("compile_mode", "auto") != "offline":
            key, _ = resolve_key()
            if key:
                client = ChatClient(request.get("endpoint") or "https://api.deepseek.com", request.get("model") or "deepseek-v4-pro",
                                    key=key, budget_usd=request.get("budget_usd"), prices=_prices(request.get("prices")))
        result = compiler.compile_description(request.get("description", ""), catalog, request.get("context") or {},
                                              client=client, mode=request.get("compile_mode", "auto"))
    elif mode == "validate":
        catalog = Catalog(request.get("catalog"), request.get("context"))
        steps, report = validate(request.get("steps") or [], catalog)
        result = {"ok": report.ok, "steps": steps, "validation": report.as_dict()}
    elif mode == "portal_template":
        result = portal.login_workflow(request.get("profile") or {})
    elif mode == "portal_validate":
        clean, errors, warnings = portal.validate_profile(request.get("profile") or {})
        result = {"ok": not errors, "profile": clean, "errors": errors, "warnings": warnings}
    elif mode == "portal_report":
        result = portal.build_report(request["run_dir"], reveal_typed=bool(request.get("reveal_typed")))
    elif mode == "sop_build":
        from . import sop
        result = sop.build(request)
    else:
        result = {"ok": False, "error": f"Unknown Autopilot mode '{mode}'"}
    result.setdefault("mode", mode)
    result["version"] = VERSION
    return result


def _prices(value) -> dict:
    prices = {}
    for model, pair in (value or {}).items():
        try:
            prices[str(model)] = (float(pair["in"]), float(pair["out"]))
        except (KeyError, TypeError, ValueError):
            continue
    return prices


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 1:
        print("usage: python -m fan.autopilot.cli <request.json>", file=sys.stderr)
        return 2
    request_path = Path(argv[0])
    job_dir = request_path.parent
    try:
        request = json.loads(request_path.read_text(encoding="utf-8-sig"))
        result = run(request, job_dir)
    except Exception as error:  # every failure is reported to the app, never swallowed
        result = {"ok": False, "error": f"{type(error).__name__}: {error}",
                  "trace": traceback.format_exc(limit=6)[-2000:], "version": VERSION}
    atomic_json(job_dir / "result.json", result)
    atomic_json(job_dir / "status.json", {"phase": "complete", "ok": bool(result.get("ok")), "at": time.time()})
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
