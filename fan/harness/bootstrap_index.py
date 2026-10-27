"""Index this workspace's own sub-projects into the Atlas map.

Run once after cloning or merging. It registers each part of the harness as its own
project so the map describes the workspace accurately rather than as one giant blob.
Safe to re-run: indexing is idempotent, and it replaces rather than duplicates.
"""

from __future__ import annotations

import datetime as _dt
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from atlas.index import build_project_index, to_rows
from atlas.store import Store

WORKSPACE = Path(__file__).resolve().parent

# (relative path, project name, bucket, priority, external, summary)
PARTS: list[tuple[str, str, str, int, bool, str]] = [
    ("atlas", "atlas", "codetool", 95, False,
     "the context map engine: scan, index, slice, gate, condense, fan-out"),
    ("studio", "harness-studio", "codetool", 92, False,
     "the unified Tk interface over every part of the system"),
    ("sidelearner", "sidelearner", "agent", 90, False,
     "self-hosted agent harness: perception, memory twin, router, skills, tools"),
    ("Ollama_Job_Automation_Studio_v1.2", "ojas", "career", 70, False,
     "job automation studio: resume/ATS scoring, RAG, visual synthesis"),
    ("legacy/code_analyzer", "code-analyzer", "codetool", 60, False,
     "the original AST analyzer this system grew out of"),
    ("legacy/ollama_preprompt", "ollama-preprompt", "agent", 55, False,
     "pre-prompt and pre-context builders for local models"),
    ("tests", "harness-tests", "codetool", 40, False,
     "the test suite for sidelearner and atlas"),
]

# Subtrees that are their own projects, so the root project must not re-scan them.
ROOT_EXCLUDE = {
    "atlas", "studio", "sidelearner", "Ollama_Job_Automation_Studio_v1.2",
    "legacy", "tests", "condensed", "coagulated", "projects", "vault", "docs",
    "scaffold_test",
}


def main() -> int:
    store = Store(WORKSPACE)
    stamp = _dt.datetime.now().strftime("%Y-%m-%d %H:%M")
    total_symbols = 0

    entries = [
        (WORKSPACE / rel, name, bucket, priority, external, summary, None)
        for rel, name, bucket, priority, external, summary in PARTS
    ]
    # The workspace root itself holds the Creator Ops tools as loose modules.
    entries.append(
        (WORKSPACE, "creator-ops", "contentops", 75, False,
         "content pipeline: briefs, drafts, review queue, metrics", ROOT_EXCLUDE)
    )

    for root, name, bucket, priority, external, summary, exclude in entries:
        if not root.exists():
            print(f"skip  {name:<18} ({root} not present)")
            continue
        index = build_project_index(
            root, name=name, bucket=bucket, external=external, exclude=exclude
        )
        if not index.symbol_count:
            print(f"skip  {name:<18} (no indexable symbols)")
            continue
        files, symbols = to_rows(index)
        project_id = store.upsert_project(
            name, root, bucket=bucket, priority=priority,
            external=1 if external else 0, summary=summary,
            verdict=index.verdict.explain(), file_count=index.file_count,
            line_count=index.line_count, symbol_count=index.symbol_count,
            indexed_at=stamp,
        )
        store.replace_index(project_id, files, symbols)
        total_symbols += index.symbol_count
        print(f"index {name:<18} @{bucket:<11} "
              f"{index.file_count:>3} files  {index.line_count:>6} lines  "
              f"{index.symbol_count:>4} symbols")
        for path, error in index.errors[:3]:
            print(f"      ! {path}: {error}")

    counts = store.counts()
    print(f"\nworkspace map: {counts['projects']} projects, {counts['symbols']} symbols, "
          f"{counts['lines']:,} lines across {counts['buckets']} buckets")
    store.log("bootstrap", detail=f"indexed {len(PARTS) + 1} workspace parts")
    store.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
