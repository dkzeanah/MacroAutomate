"""Tests for structural dedupe and variant coagulation.

The property under test throughout is the one the feature exists for: **nothing is
lost**. Every test that merges anything asserts the accounting balances and that the
output really contains what the plan said it would -- checked by re-reading disk, not
by trusting the plan.
"""

from __future__ import annotations

import ast
import datetime as _dt
import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from atlas import coagulate as coagulatemod
from atlas import similar as similarmod
from atlas import variants as variantsmod
from atlas.index import build_project_index, to_rows
from atlas.normalize import (
    DIVERGED, FORMATTING, IDENTICAL, RENAMED, UNRELATED, normalize, relate,
)
from atlas.store import Store
from atlas.variants import CONFLICT, UNANIMOUS, UNIQUE, merge_imports

BASE = '''\
"""Shared module."""

import os
from typing import Optional, List


def clamp(value, low, high):
    """Constrain a value."""
    return max(low, min(high, value))


class Engine:
    """Does the work."""

    def __init__(self, speed=1.0):
        self.speed = speed

    def run(self, ticks):
        total = 0
        for i in range(ticks):
            total += self.speed
        return total
'''

# Variant B: clamp renamed locals, Engine.run identical, plus a unique function.
VARIANT_B = '''\
"""Shared module."""

import os
from typing import Optional, List


def clamp(amount, lower, upper):
    """Constrain a value."""
    return max(lower, min(upper, amount))


class Engine:
    """Does the work."""

    def __init__(self, speed=1.0):
        self.speed = speed

    def run(self, ticks):
        total = 0
        for i in range(ticks):
            total += self.speed
        return total


def only_in_b(x):
    """This exists nowhere else."""
    return x * 2
'''

# Variant C: Engine.run materially different, and one extra import.
VARIANT_C = '''\
"""Shared module."""

import os
import json
from typing import Optional, List, Tuple


def clamp(value, low, high):
    """Constrain a value."""
    return max(low, min(high, value))


class Engine:
    """Does the work."""

    def __init__(self, speed=1.0):
        self.speed = speed

    def run(self, ticks):
        return sum(self.speed * (1.1 ** n) for n in range(ticks))
'''

INIT_ONLY = "from .core import Engine\n"


@pytest.fixture()
def workspace(tmp_path: Path) -> Path:
    return tmp_path / "ws"


@pytest.fixture()
def family_store(tmp_path: Path, workspace: Path):
    """Three variants of one project, indexed, with staggered modification times."""
    sources = {"v_old": BASE, "v_mid": VARIANT_B, "v_new": VARIANT_C}
    roots = {}
    for offset, (name, body) in enumerate(sources.items()):
        root = tmp_path / name
        (root / "pkg").mkdir(parents=True)
        (root / "pkg" / "core.py").write_text(body, encoding="utf-8")
        (root / "pkg" / "__init__.py").write_text(INIT_ONLY, encoding="utf-8")
        (root / "README.md").write_text(f"# {name}\n", encoding="utf-8")
        stamp = _dt.datetime(2026, 1, 1 + offset).timestamp()
        for path in root.rglob("*"):
            if path.is_file():
                os.utime(path, (stamp, stamp))
        roots[name] = root

    workspace.mkdir(parents=True, exist_ok=True)
    store = Store(workspace)
    for name, root in roots.items():
        index = build_project_index(root, name=name, bucket="codetool")
        files, symbols = to_rows(index)
        project_id = store.upsert_project(
            name, root, bucket="codetool", symbol_count=index.symbol_count,
            file_count=index.file_count, line_count=index.line_count,
        )
        store.replace_index(project_id, files, symbols)
    yield store, roots
    store.close()


# --------------------------------------------------------------------- normalize

def test_renamed_locals_hash_identically() -> None:
    a = normalize("def f(x, y):\n    return x + y\n", "f")
    b = normalize("def f(alpha, beta):\n    return alpha + beta\n", "f")
    assert a.shape_hash == b.shape_hash
    assert relate(a, b)[0] == RENAMED


def test_docstring_only_change_is_formatting() -> None:
    a = normalize('def f(x):\n    """One."""\n    return x\n', "f")
    b = normalize('def f(x):\n    """Completely different words."""\n    return x\n', "f")
    assert relate(a, b)[0] == FORMATTING


def test_docstrings_do_not_break_structural_equality() -> None:
    """A documented copy and an undocumented copy are still the same function."""
    a = normalize('def f(x):\n    """Doc."""\n    return x * 2\n', "f")
    b = normalize("def f(x):\n    return x * 2\n", "f")
    assert a.shape_hash == b.shape_hash


def test_added_logic_is_not_a_match() -> None:
    a = normalize("def f(x):\n    return x * 2\n", "f")
    b = normalize("def f(x):\n    if x < 0:\n        raise ValueError(x)\n    return x * 2\n", "f")
    assert relate(a, b)[0] in {DIVERGED, UNRELATED}


def test_identical_is_identical() -> None:
    code = "def f(x):\n    return x\n"
    assert relate(normalize(code, "f"), normalize(code, "f"))[0] == IDENTICAL


def test_unparsable_code_does_not_raise() -> None:
    result = normalize("def broken(:\n", "broken")
    assert result.error and not result.ok


def test_different_literals_still_share_a_shape() -> None:
    a = normalize("def f():\n    return retry(3)\n", "f")
    b = normalize("def f():\n    return retry(99)\n", "f")
    assert a.shape_hash == b.shape_hash
    assert a.literals != b.literals, "the actual values must still be recoverable"


# ----------------------------------------------------------------- import merging

def test_merge_imports_unions_names_per_module() -> None:
    merged = merge_imports([
        "from typing import Optional, List",
        "from typing import List, Tuple",
        "import os",
        "import os",
    ])
    assert "import os" in merged
    assert merged.count("import os") == 1
    typing_line = next(m for m in merged if m.startswith("from typing"))
    assert typing_line == "from typing import List, Optional, Tuple"


def test_merge_imports_keeps_star_separate() -> None:
    merged = merge_imports(["from m import *", "from m import thing"])
    assert "from m import *" in merged
    assert "from m import thing" in merged


# -------------------------------------------------------------------- clustering

def test_clustering_prefers_the_strongest_relation(family_store) -> None:
    """Byte-identical copies must report IDENTICAL, not a weaker later-pass verdict."""
    store, _roots = family_store
    entries, _problems = similarmod.load_entries(store, min_lines=1)
    clusters = similarmod.cluster(entries)
    engine = [c for c in clusters if c.members[0].leaf == "Engine"]
    assert engine, "Engine is copied across variants and must cluster"
    assert engine[0].relation == IDENTICAL
    assert engine[0].lossless


def test_trivial_shapes_do_not_cluster(family_store) -> None:
    """A one-line body matches half of any codebase; clustering it is noise."""
    store, _roots = family_store
    entries, _ = similarmod.load_entries(store, min_lines=1)
    clusters = similarmod.cluster(entries, min_nodes=999)
    assert all(c.relation == IDENTICAL for c in clusters), (
        "with structural matching disabled only byte-equality may cluster"
    )


# ------------------------------------------------------------- family detection

def test_family_detection_groups_the_variants(family_store) -> None:
    store, roots = family_store
    families = variantsmod.detect_families(store)
    assert len(families) == 1
    assert families[0].size == 3
    assert {v.name for v in families[0].variants} == set(roots)


def test_newest_variant_is_identified(family_store) -> None:
    store, _roots = family_store
    family = variantsmod.detect_families(store)[0]
    assert family.newest.name == "v_new"


# ------------------------------------------------------------------- alignment

def test_plan_accounting_always_balances(family_store) -> None:
    store, _roots = family_store
    family = variantsmod.detect_families(store)[0]
    plan = variantsmod.align(store, family)
    ok, message = plan.balanced()
    assert ok, message
    assert plan.total_versions == sum(len(s.versions) for s in plan.slots)


def test_unique_symbol_is_kept(family_store) -> None:
    """`only_in_b` exists in one variant. Losing it is the failure mode."""
    store, _roots = family_store
    family = variantsmod.detect_families(store)[0]
    plan = variantsmod.align(store, family)
    unique = [s for s in plan.slots if s.name == "only_in_b"]
    assert unique, "the only-in-one-variant symbol must appear as a slot"
    assert unique[0].status == UNIQUE
    assert unique[0].chosen is not None, "it must be adopted, not dropped"


def test_material_difference_becomes_a_conflict(family_store) -> None:
    store, _roots = family_store
    family = variantsmod.detect_families(store)[0]
    plan = variantsmod.align(store, family)
    run = next(s for s in plan.slots if s.name == "Engine.run")
    assert run.status == CONFLICT
    assert run.chosen is None, "a conflict must not be silently resolved"


def test_conflicts_are_not_auto_resolved_under_newest(family_store) -> None:
    store, _roots = family_store
    family = variantsmod.detect_families(store)[0]
    plan = variantsmod.align(store, family, policy="newest")
    assert plan.conflicts, "newest must hold conflicts rather than guess"


def test_lead_policy_resolves_conflicts(family_store) -> None:
    store, _roots = family_store
    family = variantsmod.detect_families(store)[0]
    plan = variantsmod.align(store, family, policy="lead", lead="v_new")
    run = next(s for s in plan.slots if s.name == "Engine.run")
    assert run.chosen is not None
    assert run.chosen.variant == "v_new"


def test_import_only_difference_is_detected(family_store) -> None:
    """The bug this closes: a variant whose only change is an added import."""
    store, _roots = family_store
    family = variantsmod.detect_families(store)[0]
    plan = variantsmod.align(store, family)
    gaps = plan.import_gaps
    assert gaps, "an import present in only one variant must be reported"
    missing = {name for _p, _v, names in gaps for name in names}
    assert any("Tuple" in m for m in missing)
    assert any("json" in m for m in missing)


# ------------------------------------------------------------------- coagulation

def test_coagulate_writes_every_file_including_symbol_free_ones(family_store, tmp_path) -> None:
    """`__init__.py` has no symbols. Driving output off symbols alone omits it."""
    store, _roots = family_store
    family = variantsmod.detect_families(store)[0]
    plan = variantsmod.align(store, family, policy="lead", lead="v_new")
    destination = tmp_path / "merged"
    result = coagulatemod.execute(store, plan, destination, dry_run=False)

    assert (destination / "pkg" / "core.py").exists()
    assert (destination / "pkg" / "__init__.py").exists(), (
        "a file with no symbols must still reach the output"
    )
    assert result.verification.files_missing == []


def test_coagulate_verification_passes_and_is_real(family_store, tmp_path) -> None:
    store, _roots = family_store
    family = variantsmod.detect_families(store)[0]
    plan = variantsmod.align(store, family, policy="lead", lead="v_new")
    destination = tmp_path / "merged"
    result = coagulatemod.execute(store, plan, destination, dry_run=False)

    assert result.verification.ok, result.verification.render()
    assert result.verification.checked > 0
    assert result.verification.present == result.verification.checked


def test_no_symbol_from_any_variant_is_lost(family_store, tmp_path) -> None:
    """The whole promise, checked independently of the plan's own bookkeeping."""
    store, roots = family_store
    family = variantsmod.detect_families(store)[0]
    plan = variantsmod.align(store, family, policy="lead", lead="v_new")
    destination = tmp_path / "merged"
    coagulatemod.execute(store, plan, destination, dry_run=False)

    def names(root: Path) -> set[str]:
        found = set()
        for path in root.rglob("*.py"):
            if ".coagulate" in path.parts:
                continue
            try:
                tree = ast.parse(path.read_text(encoding="utf-8"))
            except SyntaxError:
                continue
            rel = path.relative_to(root).as_posix()

            def walk(node, prefix=""):
                for child in ast.iter_child_nodes(node):
                    if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef,
                                          ast.ClassDef)):
                        found.add(f"{rel}#{prefix}{child.name}")
                        walk(child, f"{prefix}{child.name}.")

            walk(tree)
        return found

    source_names: set[str] = set()
    for root in roots.values():
        source_names |= names(root)
    assert not (source_names - names(destination)), (
        f"lost: {sorted(source_names - names(destination))}"
    )


def test_every_output_file_parses(family_store, tmp_path) -> None:
    store, _roots = family_store
    family = variantsmod.detect_families(store)[0]
    plan = variantsmod.align(store, family, policy="lead", lead="v_new")
    destination = tmp_path / "merged"
    coagulatemod.execute(store, plan, destination, dry_run=False)
    for path in destination.rglob("*.py"):
        if ".coagulate" in path.parts:
            continue
        ast.parse(path.read_text(encoding="utf-8"))  # raises on failure


def test_merged_imports_reach_the_output(family_store, tmp_path) -> None:
    store, _roots = family_store
    family = variantsmod.detect_families(store)[0]
    plan = variantsmod.align(store, family, policy="lead", lead="v_old")
    destination = tmp_path / "merged"
    coagulatemod.execute(store, plan, destination, dry_run=False)

    text = (destination / "pkg" / "core.py").read_text(encoding="utf-8")
    tree = ast.parse(text)
    imported = {
        alias.name
        for node in tree.body if isinstance(node, (ast.Import, ast.ImportFrom))
        for alias in node.names
    }
    # `Tuple` and `json` exist only in v_new, but v_old is the lead.
    assert "Tuple" in imported, "an import from a non-lead variant was dropped"
    assert "json" in imported


def test_superseded_versions_are_archived_and_readable(family_store, tmp_path) -> None:
    store, _roots = family_store
    family = variantsmod.detect_families(store)[0]
    plan = variantsmod.align(store, family, policy="lead", lead="v_new")
    destination = tmp_path / "merged"
    result = coagulatemod.execute(store, plan, destination, dry_run=False)

    assert result.archived > 0
    assert result.verification.archive_verified == result.archived
    assert result.verification.archive_missing == []
    for slot in plan.slots:
        for version in slot.versions:
            if version.attic_path:
                body = (destination / version.attic_path).read_text(encoding="utf-8")
                assert "ARCHIVED by atlas coagulate" in body


def test_dry_run_writes_nothing(family_store, tmp_path) -> None:
    store, _roots = family_store
    family = variantsmod.detect_families(store)[0]
    plan = variantsmod.align(store, family)
    destination = tmp_path / "merged"
    result = coagulatemod.execute(store, plan, destination, dry_run=True)
    assert result.dry_run
    assert not destination.exists() or not any(destination.rglob("*.py"))


def test_source_folders_are_never_modified(family_store, tmp_path) -> None:
    store, roots = family_store
    before = {
        path: path.read_bytes()
        for root in roots.values() for path in root.rglob("*") if path.is_file()
    }
    family = variantsmod.detect_families(store)[0]
    plan = variantsmod.align(store, family, policy="lead", lead="v_new")
    coagulatemod.execute(store, plan, tmp_path / "merged", dry_run=False)
    for path, content in before.items():
        assert path.read_bytes() == content, f"{path} was modified"


def test_held_conflict_is_flagged_in_the_output_file(family_store, tmp_path) -> None:
    """A held conflict still writes *some* version; it must say so, at that line."""
    store, _roots = family_store
    family = variantsmod.detect_families(store)[0]
    plan = variantsmod.align(store, family, policy="newest")
    destination = tmp_path / "merged"
    coagulatemod.execute(store, plan, destination, dry_run=False)

    text = (destination / "pkg" / "core.py").read_text(encoding="utf-8")
    assert "UNRESOLVED CONFLICT" in text
    assert "Engine.run" in text
    ast.parse(text)  # the marker must not break the file


def test_manifest_records_the_whole_accounting(family_store, tmp_path) -> None:
    import json

    store, _roots = family_store
    family = variantsmod.detect_families(store)[0]
    plan = variantsmod.align(store, family, policy="lead", lead="v_new")
    destination = tmp_path / "merged"
    coagulatemod.execute(store, plan, destination, dry_run=False)

    manifest = json.loads(
        (destination / coagulatemod.MANIFEST).read_text(encoding="utf-8")
    )
    assert manifest["balanced"] is True
    assert manifest["verification"]["passed"] is True
    assert sum(manifest["accounting"].values()) == manifest["total_versions"]
    assert len(manifest["symbols"]) == len(plan.slots)
