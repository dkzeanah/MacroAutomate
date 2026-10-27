#!/usr/bin/env python3
"""Process due creator-operations queue items without CLI parameters.

The worker is suitable for Windows Task Scheduler. It prints JSONL for an
operator log. The default is a non-mutating dry run; live API writes require
``CREATOR_OPS_LIVE_PUBLISH=1`` in the scheduled task's environment.
"""

from __future__ import annotations

import json
import sys
from dataclasses import asdict

import creator_ops as ops


def main() -> int:
    """Process due items from the per-user database and report each result."""
    try:
        results = ops.process_due_queue()
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False))
        return 1
    if not results:
        print(json.dumps({"ok": True, "processed": 0}, ensure_ascii=False))
        return 0
    for result in results:
        print(json.dumps({"ok": result.success, **asdict(result)}, ensure_ascii=False))
    return 0 if all(result.success for result in results) else 1


if __name__ == "__main__":
    sys.exit(main())
