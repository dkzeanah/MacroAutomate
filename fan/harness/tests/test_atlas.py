"""Tests for the Atlas context-map engine.

The properties worth guarding are the ones the whole design rests on:
addresses round-trip, spans point at the code they claim, the hash catches staleness,
a MISS is trustworthy, and nothing is ever destroyed.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from atlas import condense, fanout, graph, rules, slicer
from atlas.address import Address, AddressError, is_address
from atlas.buckets import classify
from atlas.index import build_project_index, format_index_line, to_rows
from atlas.ledger import Ledger
from atlas.scanner import scan_source
from atlas.store import Store

SAMPLE = '''\
"""A small module used by the tests."""

import math

MAX_TRIES = 3


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    """Constrain value to the inclusive range."""
    return max(low, min(high, value))


def retry_backoff(fn, tries: int = MAX_TRIES, delay: float = 0.5):
    """Retry fn with an exponentially growing delay."""
    wait = delay
    for attempt in range(tries):
        try:
            return fn()
        except Exception:
            wait = wait * 2
    raise RuntimeError("exhausted")


class Solver:
    """Solves things, slowly."""

    def __init__(self, tolerance: float = 1e-6) -> None:
        self.tolerance = tolerance

    def solve(self, value: float) -> float:
        """Normalise then clamp."""
        return clamp(math.sqrt(abs(value)))

    def _internal(self) -> None:
        pass
'''


@pytest.fixture()
def project(tmp_path: Path) -> Path:
    root = tmp_path / "sampleproj"
    root.mkdir()
    (root / "core.py").write_text(SAMPLE, encoding="utf-8")
    (root / "requirements.txt").write_text("numpy>=1.24\n", encoding="utf-8")
    return root


@pytest.fixture()
def store(tmp_path: Path, project: Path) -> Store:
    workspace = tmp_path / "ws"
    workspace.mkdir()
    store = Store(workspace)
    index = build_project_index(project, name="sampleproj", bucket="codetool")
    files, symbols = to_rows(index)
    project_id = store.upsert_project(
        "sampleproj", project, bucket="codetool",
        file_count=index.file_count, line_count=index.line_count,
        symbol_count=index.symbol_count,
    )
    store.replace_index(project_id, files, symbols)
    yield store
    store.close()


# ------------------------------------------------------------------------ address

@pytest.mark.parametrize("raw", [
    "@agent/side:reason/loop.py#Loop.step",
    "@agent/side:reason/loop.py#step",
    "@agent/side:reason/loop.py",
    "@agent/side",
    "@agent",
])
def test_address_round_trips(raw: str) -> None:
    assert str(Address.parse(raw)) == raw


def test_address_levels_and_parts() -> None:
    addr = Address.parse("@agent/side:reason/loop.py#Loop.step")
    assert addr.level == "symbol"
    assert addr.owner == "Loop"
    assert addr.leaf == "step"
    assert str(addr.to_file()) == "@agent/side:reason/loop.py"
    assert str(addr.to_project()) == "@agent/side"


def test_malformed_addresses_rejected() -> None:
    for bad in ["", "not an address", "@Bad Bucket/x", "@a/b:c#1nvalid"]:
        assert not is_address(bad)
    with pytest.raises(AddressError):
        Address.parse("")


def test_backslash_paths_normalised() -> None:
    assert Address.parse("@a/b:sub\\file.py#X").path == "sub/file.py"


# ------------------------------------------------------------------------ scanner

def test_scanner_finds_every_kind(project: Path) -> None:
    scan = scan_source(project / "core.py", "core.py")
    assert not scan.error
    names = {s.name for s in scan.symbols}
    assert {"clamp", "retry_backoff", "Solver", "Solver.solve",
            "Solver._internal", "MAX_TRIES"} <= names


def test_scanner_spans_bound_the_symbol(project: Path) -> None:
    lines = (project / "core.py").read_text(encoding="utf-8").splitlines()
    scan = scan_source(project / "core.py", "core.py")
    for symbol in scan.symbols:
        span = "\n".join(lines[symbol.line_start - 1 : symbol.line_end])
        if symbol.kind in {"C", "F", "f", "A"}:
            assert symbol.leaf in span, f"{symbol.name} not inside its own span"


def test_scanner_signature_keeps_annotations(project: Path) -> None:
    scan = scan_source(project / "core.py", "core.py")
    clamp = next(s for s in scan.symbols if s.name == "clamp")
    assert clamp.signature == "clamp(value: float, low: float=0.0, high: float=1.0) -> float"


def test_scanner_survives_syntax_errors(tmp_path: Path) -> None:
    broken = tmp_path / "broken.py"
    broken.write_text("def oops(:\n    pass\n", encoding="utf-8")
    scan = scan_source(broken, "broken.py")
    assert scan.error and "syntax error" in scan.error
    assert scan.symbols == []


# -------------------------------------------------------------------------- graph

def test_graph_builds_both_directions(project: Path) -> None:
    index = build_project_index(project, name="p", bucket="codetool")
    solve = next(s for s in index.symbols if s.name == "Solver.solve")
    assert any("clamp" in c for c in solve.calls), "forward edge missing"
    clamp = next(s for s in index.symbols if s.name == "clamp")
    assert any("solve" in c for c in clamp.called_by), "reverse edge missing"


def test_graph_ignores_self_recursion(tmp_path: Path) -> None:
    source = tmp_path / "r.py"
    source.write_text("def loop(n):\n    return loop(n - 1) if n else 0\n", encoding="utf-8")
    scan = scan_source(source, "r.py")
    resolved = graph.build([scan])
    key = "r.py::loop"
    assert key not in resolved.outs(key)


# ------------------------------------------------------------------------ buckets

def test_classification_carries_its_evidence(project: Path) -> None:
    verdict = classify(project)
    assert verdict.bucket
    assert isinstance(verdict.signals, list)
    assert verdict.explain()


def test_classification_uses_dependencies(tmp_path: Path) -> None:
    root = tmp_path / "webthing"
    root.mkdir()
    (root / "requirements.txt").write_text("fastapi\nuvicorn\n", encoding="utf-8")
    (root / "server.py").write_text("from fastapi import FastAPI\n", encoding="utf-8")
    assert classify(root).bucket == "webapp"


# --------------------------------------------------------------------- index line

def test_index_line_caps_runaway_edges() -> None:
    line = format_index_line(
        "F", 10, 20, "abcd", "f(x)",
        calls=[f"mod.Class.callee{i}" for i in range(40)],
        called_by=[f"mod.Class.caller{i}" for i in range(40)],
    )
    # Uncapped this would be thousands of characters; that was a real regression.
    assert len(line) < 300
    assert "+35" in line and "+36" in line


def test_index_line_trims_long_signature() -> None:
    line = format_index_line("F", 1, 2, "abcd", "f(" + "a: int, " * 60 + ")", [], [])
    # The signature is truncated in place; the edge markers still follow it.
    assert "...)" in line
    assert len(line) < 220
    assert line.rstrip().endswith("<-")


def test_index_line_drops_redundant_class_segment() -> None:
    line = format_index_line("F", 1, 2, "aaaa", "x()", ["autonomy.Engine.tick"], [])
    assert ">autonomy.tick" in line


# ------------------------------------------------------------------------ slicing

def test_slice_returns_only_the_symbol(store: Store) -> None:
    piece = slicer.get(store, "@codetool/sampleproj:core.py#clamp")
    assert "def clamp" in piece.code
    assert "def retry_backoff" not in piece.code
    assert not piece.stale


def test_slice_carries_its_own_map(store: Store) -> None:
    rendered = slicer.get(store, "@codetool/sampleproj:core.py#clamp").render()
    assert "# @atlas @codetool/sampleproj:core.py#clamp" in rendered
    assert ">" in rendered and "<" in rendered


def test_slice_detects_a_stale_index(store: Store, project: Path) -> None:
    target = project / "core.py"
    target.write_text("# a new first line\n" + target.read_text(encoding="utf-8"),
                      encoding="utf-8")
    assert slicer.get(store, "@codetool/sampleproj:core.py#clamp").stale


def test_unknown_address_raises(store: Store) -> None:
    with pytest.raises(slicer.SliceError):
        slicer.get(store, "@codetool/sampleproj:core.py#does_not_exist")
    with pytest.raises(slicer.SliceError):
        slicer.get(store, "@codetool/sampleproj:core.py")  # file level, not a slice


def test_get_many_respects_the_budget(store: Store) -> None:
    addresses = [
        "@codetool/sampleproj:core.py#clamp",
        "@codetool/sampleproj:core.py#retry_backoff",
        "@codetool/sampleproj:core.py#Solver",
    ]
    pieces, skipped, used = slicer.get_many(store, addresses, budget_tokens=1)
    assert len(pieces) == 1, "budget must stop after the first slice"
    assert len(skipped) == 2
    assert used > 0


# ---------------------------------------------------------------- the dedupe gate

def test_find_hits_an_existing_symbol(store: Store) -> None:
    result = rules.find(store, "retry with exponential backoff")
    assert result.hit
    assert "retry_backoff" in result.matches[0].address


def test_miss_is_authoritative_and_says_so(store: Store) -> None:
    result = rules.find(store, "encode a video to h264")
    assert not result.hit
    rendered = result.render()
    assert "MISS" in rendered and "SAFE TO CREATE" in rendered
    assert result.searched > 0


def test_shared_verb_alone_is_not_a_match(store: Store) -> None:
    # `Solver.solve` must not match this just because both mention solving nothing.
    assert not rules.find(store, "parse a CAN bus DBC file").hit


def test_budget_gate_refuses_oversized_symbols() -> None:
    assert rules.check_budget(20, "agent").ok
    too_big = rules.check_budget(400, "agent")
    assert not too_big.ok and "ceiling" in too_big.message
    assert not rules.check_budget(0, "agent").ok


def test_one_incidental_noun_is_not_a_duplicate(store: Store) -> None:
    # "solve" exists as Solver.solve, but nothing here solves sudoku.
    assert not rules.find(store, "solve a sudoku puzzle grid").hit


def test_placement_picks_a_real_file_and_line(store: Store) -> None:
    placement = rules.plan_insert(store, "clamp_to_unit", 12, bucket="codetool")
    assert placement.ok
    assert placement.file_path == "core.py"
    assert placement.insert_at_line > 0


def test_placement_refuses_rather_than_choosing_arbitrarily(store: Store) -> None:
    """With no lexical pull and no scope, any choice is a guess -- so refuse.

    This regressed once: the small-file tie-break silently sent unrelated code into
    whichever toy project happened to be smallest.
    """
    placement = rules.plan_insert(store, "zzz_unrelated_thing", 10)
    assert not placement.ok
    assert "arbitrary" in placement.reason
    assert "--bucket" in placement.reason


def test_placement_accepts_once_a_bucket_is_given(store: Store) -> None:
    assert rules.plan_insert(store, "zzz_unrelated_thing", 10, bucket="codetool").ok


def test_suggested_home_never_points_at_vendored_code(tmp_path: Path, project: Path) -> None:
    workspace = tmp_path / "ws2"
    workspace.mkdir()
    store = Store(workspace)
    index = build_project_index(project, name="vendored", bucket="codetool", external=True)
    files, symbols = to_rows(index)
    project_id = store.upsert_project("vendored", project, bucket="codetool", external=1)
    store.replace_index(project_id, files, symbols)
    try:
        result = rules.find(store, "encode a video stream to h264")
        assert not result.hit
        assert result.suggestion == "", "must not propose writing into external code"
    finally:
        store.close()


def test_gate_blocks_a_duplicate(store: Store) -> None:
    report = rules.gate(store, "retry_backoff", "retry with exponential backoff", 15)
    assert not report.allowed, "an existing symbol must not pass the gate"
    assert report.find_result.hit


def test_gate_allows_something_genuinely_new(store: Store) -> None:
    report = rules.gate(store, "encode_h264", "encode a video stream to h264", 20,
                        bucket="codetool")
    assert report.allowed
    assert "PROCEED" in report.render()


# ------------------------------------------------------------------------ ledger

def test_nothing_is_lost_on_retire(store: Store) -> None:
    ledger = Ledger(store)
    address = "@codetool/sampleproj:core.py#clamp"
    attic_file = ledger.retire(address, "def clamp(): ...", replaced_by="@x/y:z.py#c2")
    assert attic_file.exists()
    body = attic_file.read_text(encoding="utf-8")
    assert "RETIRED" in body and "def clamp" in body
    row = store.symbol_by_address(address)
    assert "X" in row["flags"], "a retired symbol keeps a tombstone in the index"


def test_backup_and_restore_round_trip(store: Store, project: Path) -> None:
    ledger = Ledger(store)
    target = store.workspace / "live.py"
    target.write_text("original\n", encoding="utf-8")

    backup = ledger.snapshot([target], "test", "before edit")
    target.write_text("clobbered\n", encoding="utf-8")

    preview = ledger.restore(backup.ledger_id, dry_run=True)
    assert any("would restore" in line for line in preview)
    assert target.read_text(encoding="utf-8") == "clobbered\n", "dry run must not write"

    ledger.restore(backup.ledger_id, dry_run=False)
    assert target.read_text(encoding="utf-8") == "original\n"


# ------------------------------------------------------------------------ fanout

def test_fanout_reads_fence_titles_and_path_comments() -> None:
    document = (
        'Intro\n\n```python title="pkg/a.py"\nA = 1\n```\n\n'
        "Then:\n\n```python\n# file: pkg/b.py\nB = 2\n```\n"
    )
    plan = fanout.parse_document(document)
    paths = {p.path for p in plan.pieces}
    assert paths == {"pkg/a.py", "pkg/b.py"}
    assert all(p.confidence >= 0.85 for p in plan.pieces)


def test_fanout_flags_invalid_python() -> None:
    plan = fanout.parse_document('```python title="bad.py"\ndef (\n```\n')
    assert plan.pieces[0].valid_python is False
    assert any("not valid Python" in w for w in plan.warnings)


def test_fanout_keeps_repeated_paths_as_revisions() -> None:
    document = (
        '```python title="x.py"\nV = 1\n```\n'
        '```python title="x.py"\nV = 2\n```\n'
    )
    plan = fanout.parse_document(document)
    assert len(plan.pieces) == 2
    assert {p.path for p in plan.pieces} == {"x.py", "x.v2.py"}


def test_fanout_refuses_paths_that_escape(tmp_path: Path) -> None:
    plan = fanout.FanoutPlan(pieces=[fanout.Piece("../../evil.py", "X = 1")])
    report = fanout.commit(plan, tmp_path / "dest")
    assert any("REFUSED" in line for line in report)
    assert not (tmp_path / "evil.py").exists()


def test_fanout_commit_keeps_the_prior_file(tmp_path: Path) -> None:
    destination = tmp_path / "dest"
    destination.mkdir()
    (destination / "a.py").write_text("old\n", encoding="utf-8")
    fanout.commit(fanout.FanoutPlan(pieces=[fanout.Piece("a.py", "new\n")]), destination)
    assert (destination / "a.py").read_text(encoding="utf-8") == "new\n"
    assert (destination / "a.py.prior").read_text(encoding="utf-8") == "old\n"


# ---------------------------------------------------------------------- condense

def test_condensed_spans_point_at_the_right_code(store: Store) -> None:
    import re

    result = condense.condense(store)
    for text in (result.classes_text, result.functions_text):
        lines = text.splitlines()
        entries = [
            (int(m.group(1)), int(m.group(2)), m.group(3))
            for m in (re.match(r"\s+L(\d+)-(\d+)\s+(\S+)\s+<-", ln) for ln in lines)
            if m
        ]
        assert entries, "the generated map must not be empty"
        for start, end, name in entries:
            span = "\n".join(lines[start - 1 : end])
            leaf = name.rsplit(".", 1)[-1]
            assert re.search(rf"\b(class|def)\s+{re.escape(leaf)}\b", span), (
                f"{name} span L{start}-{end} does not contain its own definition"
            )


def test_condense_skips_stale_spans_rather_than_lying(store: Store, project: Path) -> None:
    target = project / "core.py"
    target.write_text("# shifted\n" * 5 + target.read_text(encoding="utf-8"),
                      encoding="utf-8")
    result = condense.condense(store)
    assert any("STALE" in item for item in result.skipped)
