"""Execute a reconcile plan: build the merged project, archive everything else, prove it.

Three guarantees, in order of importance:

1. **Nothing is lost.** Every version that is not adopted -- superseded or merely held --
   is written out in full before anything else happens. The archive is complete before
   the first output file exists, so an interrupted run still loses nothing.
2. **Nothing broken is written.** Every assembled file is parsed before it is kept. A
   file that will not parse falls back to a whole-file copy of its base variant, and
   says so, rather than emitting plausible-looking rubbish.
3. **The result is checked, not claimed.** The output is re-scanned from disk and every
   adopted symbol is confirmed present with a matching structural hash. A merge that
   reports success without that pass is a merge you have to audit by hand.
"""

from __future__ import annotations

import ast
import datetime as _dt
import json
import shutil
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

from .ledger import Ledger
from .normalize import normalize
from .scanner import scan_source
from .variants import (
    ADOPTED,
    ARCHIVED,
    CONFLICT,
    HELD,
    SAME_AS_ADOPTED,
    ReconcilePlan,
    Slot,
    Version,
)

ARCHIVE_DIR = ".coagulate/archive"
MANIFEST = ".coagulate/MANIFEST.json"
REPORT = ".coagulate/RECONCILE_REPORT.txt"


@dataclass
class FileBuild:
    """How one output file was assembled."""

    path: str
    base_variant: str = ""
    contributors: dict[str, int] = field(default_factory=dict)
    whole_copy: bool = False
    spliced: int = 0
    appended: int = 0
    imports_added: list[str] = field(default_factory=list)
    conflicts_marked: int = 0
    ok: bool = True
    note: str = ""

    def describe(self) -> str:
        how = "copied whole" if self.whole_copy else (
            f"spliced {self.spliced}, appended {self.appended}"
        )
        mark = "" if self.ok else "  !! " + self.note
        extra = f", +{len(self.imports_added)} imports" if self.imports_added else ""
        if self.conflicts_marked:
            extra += f", {self.conflicts_marked} conflict(s) flagged in-file"
        return f"  {self.path:<52} base={self.base_variant[:26]:<26} {how}{extra}{mark}"


@dataclass
class Verification:
    """The post-write proof."""

    checked: int = 0
    present: int = 0
    missing: list[str] = field(default_factory=list)
    mismatched: list[str] = field(default_factory=list)
    unparsable: list[str] = field(default_factory=list)
    archive_verified: int = 0
    archive_missing: list[str] = field(default_factory=list)
    files_expected: int = 0
    files_present: int = 0
    files_missing: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not (self.missing or self.mismatched or self.unparsable
                    or self.archive_missing or self.files_missing)

    def render(self) -> str:
        verdict = (
            "PASS -- every adopted symbol is in the output, and every archived "
            "version is readable back off disk"
            if self.ok else
            "FAIL -- do not delete the source folders; see the detail below"
        )
        out = [
            "VERIFICATION", "-" * 78,
            f"  source files expected in output    : {self.files_expected}",
            f"  source files actually present      : {self.files_present}",
            f"  source files missing               : {len(self.files_missing)}",
            f"  adopted symbols expected in output : {self.checked}",
            f"  found with matching structure      : {self.present}",
            f"  missing from output                : {len(self.missing)}",
            f"  present but structurally different : {len(self.mismatched)}",
            f"  output files that will not parse   : {len(self.unparsable)}",
            f"  archived versions re-read from disk: {self.archive_verified}",
            f"  archived versions unreadable       : {len(self.archive_missing)}",
            "",
            f"  RESULT: {verdict}",
        ]
        for label, items in (("FILES MISSING", self.files_missing),
                             ("MISSING", self.missing),
                             ("MISMATCHED", self.mismatched),
                             ("UNPARSABLE", self.unparsable),
                             ("ARCHIVE UNREADABLE", self.archive_missing)):
            if items:
                out += ["", f"  {label}:"] + [f"    {i}" for i in items[:25]]
                if len(items) > 25:
                    out.append(f"    ... and {len(items) - 25} more")
        return "\n".join(out)


@dataclass
class CoagulateResult:
    plan: ReconcilePlan
    destination: Path
    builds: list[FileBuild] = field(default_factory=list)
    assets_written: int = 0
    archived: int = 0
    assets_archived: int = 0
    verification: Verification = field(default_factory=Verification)
    ledger_id: int = 0
    dry_run: bool = True

    @property
    def files_written(self) -> int:
        return len(self.builds)

    def render(self) -> str:
        ok, balance = self.plan.balanced()
        head = "DRY RUN -- nothing written" if self.dry_run else f"WROTE {self.destination}"
        out = [
            "=" * 78, f"COAGULATE  {self.plan.family.key}", "=" * 78, head, "",
            f"  source files assembled : {self.files_written}",
            f"  non-source files copied: {self.assets_written}",
            f"  symbol versions archived: {self.archived}",
            f"  non-source files archived: {self.assets_archived}",
            f"  accounting balance     : {'OK' if ok else 'FAILED'} -- {balance}",
            f"  ledger entry           : #{self.ledger_id}" if self.ledger_id else "",
            "",
        ]
        failed = [b for b in self.builds if not b.ok]
        if failed:
            out += [f"FILES THAT NEEDED A FALLBACK ({len(failed)})", "-" * 78]
            out += [b.describe() for b in failed]
            out.append("")
        if not self.dry_run:
            out += [self.verification.render(), ""]
        if self.plan.conflicts:
            out += [
                f"{len(self.plan.conflicts)} CONFLICT(S) WERE HELD, NOT MERGED",
                "-" * 78,
                "  Their source folders are untouched and every version is in the archive.",
                "  Resolve with --policy lead --lead <variant>, or edit them by hand.",
                "",
            ]
        return "\n".join(line for line in out if line != "")


# ----------------------------------------------------------------------- archiving

def _archive_all(plan: ReconcilePlan, destination: Path, dry_run: bool) -> int:
    """Write every non-adopted version to the archive before anything else happens."""
    root = destination / ARCHIVE_DIR
    count = 0
    for slot in plan.slots:
        for version in slot.versions:
            if version.disposition == ADOPTED:
                continue
            if version.disposition == SAME_AS_ADOPTED:
                continue  # byte-identical to what was kept; there is nothing to preserve
            stem = slot.path.rsplit(".", 1)[0].replace("/", "__").replace("\\", "__")
            safe_name = slot.name.replace(".", "-")
            target = root / version.variant / f"{stem}#{safe_name}.py"
            version.attic_path = target.relative_to(destination).as_posix()
            count += 1
            if dry_run:
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            header = [
                f"# ARCHIVED by atlas coagulate on "
                f"{_dt.datetime.now().isoformat(timespec='seconds')}",
                f"# variant   : {version.variant}",
                f"# original  : {slot.path}  L{version.entry.line_start}-"
                f"{version.entry.line_end}",
                f"# symbol    : {slot.name}",
                f"# status    : {slot.status} / {version.disposition}",
                f"# adopted   : {slot.chosen.variant if slot.chosen else '(none -- held)'}",
                "# This copy exists so the merge loses nothing. Do not delete it.",
                "",
            ]
            target.write_text("\n".join(header) + version.entry.code + "\n",
                              encoding="utf-8")
    return count


# ------------------------------------------------------------------ file assembly

def _imports_of(code: str) -> list[str]:
    try:
        tree = ast.parse(code)
    except SyntaxError:
        return []
    out = []
    for node in tree.body:
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            try:
                out.append(ast.unparse(node))
            except Exception:
                continue
    return out


def _assemble(
    path: str,
    adopted: list[tuple[Slot, Version]],
    variant_files: dict[str, Path],
    missing_imports: list[str] | None = None,
    held: list[Slot] | None = None,
) -> tuple[str | None, FileBuild]:
    """Build one output file from the versions adopted for it.

    The common case -- every symbol in this file came from one variant -- is close to a
    whole-file copy, which preserves the module docstring and module-level code exactly.
    Splicing only happens when the file genuinely draws from more than one variant.

    ``missing_imports`` is applied either way. A branch whose entire contribution was
    adding one import has no differing symbol, so a pure whole-file copy would drop it
    and produce code that breaks at runtime.
    """
    build = FileBuild(path=path)
    contributors: dict[str, int] = defaultdict(int)
    for _slot, version in adopted:
        contributors[version.variant] += 1
    build.contributors = dict(contributors)

    if not contributors:
        # A file that defines no symbols -- almost always a package __init__ or a pure
        # constants module. It still has to reach the output.
        if not variant_files:
            build.ok = False
            build.note = "no variant has this file on disk"
            return None, build
        contributors = {
            max(variant_files, key=lambda v: _mtime(variant_files[v])): 0
        }
        build.contributors = {}
        build.note = "no symbols; copied with merged imports"

    base_variant = max(contributors, key=lambda v: (contributors[v],
                                                    _mtime(variant_files.get(v))))
    build.base_variant = base_variant
    base_path = variant_files.get(base_variant)
    if base_path is None or not base_path.exists():
        build.ok = False
        build.note = "base file missing on disk"
        return None, build

    base_text = base_path.read_text(encoding="utf-8", errors="replace")

    foreign = [(s, v) for s, v in adopted if v.variant != base_variant]
    if not foreign:
        needed = [i for i in (missing_imports or [])
                  if i not in set(_imports_of(base_text))]
        if not needed and not held:
            build.whole_copy = True
            return base_text, build
        lines = base_text.splitlines()
        if held:
            build.conflicts_marked = _mark_conflicts(lines, path, held, base_variant)
        if needed:
            insert_at = _after_docstring(lines)
            lines[insert_at:insert_at] = (
                ["# --- imports merged by atlas coagulate ---"] + needed
            )
            build.imports_added = needed
        build.whole_copy = True
        assembled = "\n".join(lines) + "\n"
        try:
            ast.parse(assembled)
        except SyntaxError as exc:
            build.ok = False
            build.note = f"annotation broke the file (line {exc.lineno}); copied base whole"
            return base_text, build
        return assembled, build

    # Splice: replace the base's span for each foreign symbol, bottom up so earlier
    # line numbers stay valid, and append anything the base does not have.
    base_scan = scan_source(base_path, path)
    base_spans = {s.name: (s.line_start, s.line_end) for s in base_scan.symbols}
    lines = base_text.splitlines()

    replacements = []
    appends = []
    for slot, version in foreign:
        span = base_spans.get(slot.name)
        if span:
            replacements.append((span, version.entry.code))
        else:
            appends.append(version.entry.code)

    for (start, end), code in sorted(replacements, key=lambda r: -r[0][0]):
        lines[start - 1 : end] = code.splitlines()
        build.spliced += 1

    if appends:
        lines.append("")
        for code in appends:
            lines.append("")
            lines.extend(code.splitlines())
            build.appended += 1

    # A spliced symbol may need an import its new home lacks.
    have = set(_imports_of("\n".join(lines)))
    needed: list[str] = []
    for statement in missing_imports or []:
        if statement not in have and statement not in needed:
            needed.append(statement)
    for _slot, version in foreign:
        source_file = variant_files.get(version.variant)
        if source_file is None or not source_file.exists():
            continue
        for statement in _imports_of(
            source_file.read_text(encoding="utf-8", errors="replace")
        ):
            if statement not in have and statement not in needed:
                needed.append(statement)
    # Flag held conflicts before the imports go in, so the marker lands on the symbol
    # rather than being shifted by the inserted import block.
    if held:
        build.conflicts_marked = _mark_conflicts(lines, path, held, base_variant)

    if needed:
        insert_at = _after_docstring(lines)
        block = ["# --- imports merged by atlas coagulate ---"] + needed
        lines[insert_at:insert_at] = block
        build.imports_added = needed

    assembled = "\n".join(lines) + "\n"
    try:
        ast.parse(assembled)
    except SyntaxError as exc:
        build.ok = False
        build.note = (
            f"assembled file would not parse (line {exc.lineno}: {exc.msg}); "
            f"kept {base_variant} whole instead -- the other versions are in the archive"
        )
        return base_text, build
    return assembled, build


def _mark_conflicts(
    lines: list[str], path: str, held: list[Slot], base_variant: str
) -> int:
    """Annotate every unresolved conflict in an output file, in place.

    A held conflict still ends up with *some* version in the output -- whatever the
    base variant had. Leaving that unmarked would turn "no decision was made" into a
    silent decision, which is the failure this whole tool exists to prevent. So the
    file says so, at the exact line, and names where the alternatives are kept.
    """
    marked = 0
    # Locate the symbols in the file as it now stands, then annotate bottom-up.
    try:
        tree = ast.parse("\n".join(lines))
    except SyntaxError:
        return 0
    spans: dict[str, int] = {}

    def walk(node, prefix=""):
        for child in ast.iter_child_nodes(node):
            if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                qualified = prefix + child.name
                start = min(
                    [child.lineno] + [d.lineno for d in child.decorator_list]
                )
                spans[qualified] = start
                walk(child, qualified + ".")

    walk(tree)

    for slot in sorted(held, key=lambda s: -spans.get(s.name, 0)):
        start = spans.get(slot.name)
        if not start:
            continue
        indent = " " * (len(lines[start - 1]) - len(lines[start - 1].lstrip()))
        block = [
            f"{indent}# !!! ATLAS COAGULATE -- UNRESOLVED CONFLICT: {slot.name}",
            f"{indent}# {len(slot.versions)} variants implement this differently. "
            f"The version below is from:",
            f"{indent}#   {base_variant}",
            f"{indent}# Every version is preserved in full at:",
        ]
        for version in sorted(slot.versions, key=lambda v: -v.mtime):
            where = version.attic_path or "(this one)"
            block.append(
                f"{indent}#   {version.entry.lines:>4}L  {version.variant[:44]}  ->  {where}"
            )
        block.append(
            f"{indent}# Review, pick one, then delete this block. "
            f"Nothing was discarded."
        )
        lines[start - 1 : start - 1] = block
        marked += 1
    return marked


def _mtime(path: Path | None) -> float:
    try:
        return path.stat().st_mtime if path else 0.0
    except OSError:
        return 0.0


def _after_docstring(lines: list[str]) -> int:
    """Line index just past a module docstring and any __future__ import."""
    text = "\n".join(lines)
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return 0
    index = 0
    for node in tree.body:
        if isinstance(node, ast.Expr) and isinstance(
            getattr(node, "value", None), ast.Constant
        ) and isinstance(node.value.value, str):
            index = node.end_lineno or index
        elif isinstance(node, ast.ImportFrom) and node.module == "__future__":
            index = node.end_lineno or index
        else:
            break
    return index


# -------------------------------------------------------------------- the executor

def execute(
    store,
    plan: ReconcilePlan,
    destination: Path,
    dry_run: bool = True,
    copy_assets: bool = True,
) -> CoagulateResult:
    """Materialize the reconciled project, archiving everything it does not adopt."""
    destination = Path(destination)
    result = CoagulateResult(plan=plan, destination=destination, dry_run=dry_run)

    balanced, message = plan.balanced()
    if not balanced:
        result.verification.missing.append(f"plan does not balance: {message}")
        return result

    if not dry_run:
        destination.mkdir(parents=True, exist_ok=True)

    # 1. Archive first: an interrupted run must still have lost nothing.
    result.archived = _archive_all(plan, destination, dry_run)

    # 2. Group adopted versions by output file.
    by_path: dict[str, list[tuple[Slot, Version]]] = defaultdict(list)
    for slot in plan.slots:
        if slot.chosen is None:
            continue
        by_path[slot.path].append((slot, slot.chosen))

    variant_roots = {v.name: v.root for v in plan.family.variants}
    residue_by_path = {r.path: r for r in plan.residues}

    # Every source file in any variant must appear in the output, including ones that
    # define no symbols at all. Package `__init__.py` files are usually pure imports;
    # driving the output purely off adopted symbols silently omits them and leaves a
    # merged tree that will not import.
    for path in residue_by_path:
        by_path.setdefault(path, [])

    for path, adopted in sorted(by_path.items()):
        variant_files = {
            name: root / path for name, root in variant_roots.items()
            if (root / path).exists()
        }
        # A symbol that moved carries its own origin path.
        for slot, version in adopted:
            candidate = variant_roots[version.variant] / version.entry.path
            if candidate.exists():
                variant_files.setdefault(version.variant, candidate)

        residue = residue_by_path.get(path)
        union_imports = residue.imports_union if residue else []
        held_here = [s for s in plan.slots if s.path == path and s.needs_review]
        content, build = _assemble(
            path, adopted, variant_files, union_imports, held_here
        )
        result.builds.append(build)
        if content is None or dry_run:
            continue
        target = destination / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")

    # 3. Non-source files: newest wins, differing copies preserved beside the archive.
    if copy_assets:
        for asset in plan.assets:
            chosen = asset.by_variant.get(asset.chosen_variant)
            if not chosen:
                continue
            result.assets_written += 1
            if dry_run:
                continue
            target = destination / asset.path
            target.parent.mkdir(parents=True, exist_ok=True)
            try:
                shutil.copy2(chosen[0], target)
            except OSError:
                result.assets_written -= 1
                continue
            if asset.distinct > 1:
                for variant_name, (source, digest) in asset.by_variant.items():
                    if variant_name == asset.chosen_variant:
                        continue
                    keep = destination / ARCHIVE_DIR / variant_name / asset.path
                    keep.parent.mkdir(parents=True, exist_ok=True)
                    try:
                        shutil.copy2(source, keep)
                        result.assets_archived += 1
                    except OSError:
                        pass

    # 4. Prove it.
    if not dry_run:
        result.verification = verify(plan, destination)
        _write_manifest(plan, result, destination)
        ledger = Ledger(store)
        result.ledger_id = store.log(
            "coagulate",
            detail=f"{plan.family.key}: {plan.family.size} variants -> {destination}",
            payload={
                "variants": [v.name for v in plan.family.variants],
                "accounting": plan.accounting(),
                "files": result.files_written,
                "archived": result.archived,
                "verified": result.verification.ok,
            },
        )
    return result


# ---------------------------------------------------------------------- verifying

def verify(plan: ReconcilePlan, destination: Path) -> Verification:
    """Re-read the output from disk and confirm every adopted symbol survived."""
    report = Verification()
    destination = Path(destination)

    # File coverage first. Symbol-level checking alone cannot see a file that vanished
    # entirely, because a file with no symbols contributes nothing to check.
    expected_paths = {r.path for r in plan.residues}
    expected_paths |= {s.path for s in plan.slots}
    report.files_expected = len(expected_paths)
    for path in sorted(expected_paths):
        if (destination / path).exists():
            report.files_present += 1
        else:
            report.files_missing.append(path)

    scanned: dict[str, dict[str, str]] = {}
    for slot in plan.slots:
        if slot.chosen is None:
            continue
        report.checked += 1
        target = destination / slot.path
        if slot.path not in scanned:
            if not target.exists():
                scanned[slot.path] = {}
            else:
                scan = scan_source(target, slot.path)
                if scan.error:
                    report.unparsable.append(f"{slot.path}: {scan.error}")
                    scanned[slot.path] = {}
                else:
                    text = target.read_text(encoding="utf-8", errors="replace")
                    lines = text.splitlines()
                    scanned[slot.path] = {
                        symbol.name: normalize(
                            "\n".join(lines[symbol.line_start - 1 : symbol.line_end]),
                            symbol.name,
                        ).shape_hash
                        for symbol in scan.symbols
                    }

        found = scanned[slot.path]
        if slot.name not in found:
            report.missing.append(f"{slot.path}#{slot.name}")
            continue
        expected = slot.chosen.entry.norm.shape_hash
        if expected and found[slot.name] != expected:
            report.mismatched.append(
                f"{slot.path}#{slot.name} (adopted from {slot.chosen.variant})"
            )
            continue
        report.present += 1

    # Every archived version must be readable back out.
    for slot in plan.slots:
        for version in slot.versions:
            if not version.attic_path:
                continue
            path = destination / version.attic_path
            if path.exists() and path.stat().st_size > 0:
                report.archive_verified += 1
            else:
                report.archive_missing.append(version.attic_path)
    return report


def _write_manifest(plan: ReconcilePlan, result: CoagulateResult, destination: Path) -> None:
    """Machine-readable proof, written beside the merged tree."""
    manifest = {
        "generated": _dt.datetime.now().isoformat(timespec="seconds"),
        "family": plan.family.key,
        "policy": plan.policy,
        "lead": plan.lead,
        "variants": [
            {"name": v.name, "root": str(v.root), "modified": v.when,
             "symbols": v.symbol_count}
            for v in plan.family.variants
        ],
        "accounting": plan.accounting(),
        "total_versions": plan.total_versions,
        "balanced": plan.balanced()[0],
        "verification": {
            "checked": result.verification.checked,
            "present": result.verification.present,
            "missing": result.verification.missing,
            "mismatched": result.verification.mismatched,
            "unparsable": result.verification.unparsable,
            "archive_verified": result.verification.archive_verified,
            "archive_missing": result.verification.archive_missing,
            "passed": result.verification.ok,
        },
        "symbols": [
            {
                "path": slot.path,
                "name": slot.name,
                "status": slot.status,
                "adopted_from": slot.chosen.variant if slot.chosen else None,
                "reason": slot.reason,
                "versions": [
                    {"variant": v.variant, "disposition": v.disposition,
                     "lines": v.entry.lines, "archive": v.attic_path or None}
                    for v in slot.versions
                ],
            }
            for slot in plan.slots
        ],
    }
    target = destination / MANIFEST
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    (destination / REPORT).write_text(
        plan.render(limit=10_000) + "\n\n" + result.render(), encoding="utf-8"
    )
