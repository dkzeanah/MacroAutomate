#!/usr/bin/env python3
"""Thin bridge: call the avideditor ("Cutline") sidecar's analysis functions
from the MacroAutomate /fan app without the stdio protocol.

Usage:
    python cutline_bridge.py <sidecar_python_dir> <method> <params_json> <out_json>

  <sidecar_python_dir>  the avideditor "python" folder (contains the `sidecar`
                        package). Must be run with avideditor's own venv python
                        so OpenCV / numpy / av are importable.
  <method>              analyze | transcribe | capabilities
  <params_json>         file with the request params, e.g. {"path": "C:/clip.mp4"}
  <out_json>            where the result is written: {"ok", "result", "error"}

Only the sidecar's module functions (which RETURN dicts) are used, so no
newline-delimited protocol or background server is involved.
"""

from __future__ import annotations

import json
import sys


def main() -> int:
    if len(sys.argv) < 5:
        sys.stderr.write("usage: cutline_bridge.py <python_dir> <method> <params_json> <out_json>\n")
        return 2
    py_dir, method, params_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    sys.path.insert(0, py_dir)

    result = None
    err = None
    params = {}
    try:
        with open(params_path, "r", encoding="utf-8") as fh:
            params = json.load(fh)
    except Exception as exc:  # noqa: BLE001
        err = f"params read failed: {exc}"

    if err is None:
        try:
            if method == "analyze":
                from sidecar import analyze
                result = analyze.analyze(params["path"], use_cache=bool(params.get("use_cache", True)))
            elif method == "transcribe":
                from sidecar import transcribe
                result = transcribe.transcribe(
                    params["path"],
                    model_name=params.get("model", "base"),
                    use_cache=bool(params.get("use_cache", True)),
                )
            elif method == "capabilities":
                from sidecar import server
                result = server.capabilities()
            else:
                err = f"unsupported bridge method: {method}"
        except Exception as exc:  # noqa: BLE001
            err = f"{type(exc).__name__}: {exc}"

    try:
        with open(out_path, "w", encoding="utf-8") as fh:
            json.dump({"ok": err is None, "result": result, "error": err}, fh, default=str)
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(f"out write failed: {exc}\n")
        return 1
    return 0 if err is None else 0  # errors are reported in the JSON, not the exit code


if __name__ == "__main__":
    sys.exit(main())
