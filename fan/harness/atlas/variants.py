"""Reconcile N divergent copies of the same project into one, provably losing nothing.

The situation this exists for: the same project lives in nine folders. Some are old,
one was used for real iteration last week, several contain a change that exists nowhere
else. A diff tool compares two at a time and tells you about lines. That is the wrong
unit and the wrong arity.

This module works in **symbols across all variants at once**. For every logical symbol
it collects each variant's version, classifies how they differ, and decides -- or
refuses to decide and says so. The output is a plan in which *every version of every
symbol in every variant* is accounted for by exactly one disposition. That accounting
is the proof that nothing was lost, and it is checked, not asserted.
"""

from __future__ import annotations

import datetime as _dt
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

from .normalize import (
    DIVERGED,
    FORMATTING,
    IDENTICAL,
    RENAMED,
    Normalized,
    normalize,
    relate,
    sha,
)
from .scanner import SKIP_DIR_NAMES
from .similar import Entry, load_entries

# --- slot statuses ----------------------------------------------------------------
UNANIMOUS = "unanimous"    # every variant agrees byte for byte
COSMETIC = "cosmetic"      # differ only in formatting or docstrings
STRUCTURAL = "structural"  # same shape, renamed locals or changed literals
CONFLICT = "conflict"      # materially different implementations
UNIQUE = "unique"          # present in only some variants

STATUS_ORDER = [CONFLICT, UNIQUE, STRUCTURAL, COSMETIC, UNANIMOUS]

# --- dispositions (the accounting categories) -------------------------------------
ADOPTED = "adopted"          # this version is the one that goes to the output
SAME_AS_ADOPTED = "same"     # byte-identical to the adopted version; nothing lost
ARCHIVED = "archived"        # differs from adopted; full copy preserved in the attic
HELD = "held"                # unresolved conflict; nothing written, source untouched

# --- selection policies -----------------------------------------------------------
NEWEST = "newest"
RICHEST = "richest"
LEAD = "lead"


@dataclass
class Variant:
    """One folder in a variant family."""

    name: str
    root: Path
    project_id: int
    mtime: float = 0.0
    file_count: int = 0
    symbol_count: int = 0

    @property
    def when(self) -> str:
        if not self.mtime:
            return "unknown"
        return _dt.datetime.fromtimestamp(self.mtime).strftime("%Y-%m-%d %H:%M")


@dataclass
class Family:
    """A set of folders judged to be copies of the same project."""

    key: str
    variants: list[Variant] = field(default_factory=list)
    path_overlap: float = 0.0
    shape_overlap: float = 0.0
    shared_paths: int = 0

    @property
    def size(self) -> int:
        return len(self.variants)

    @property
    def newest(self) -> Variant:
        return max(self.variants, key=lambda v: v.mtime)

    def describe(self) -> str:
        return (
            f"{self.key}  ({self.size} variants, {self.shared_paths} shared files, "
            f"path overlap {self.path_overlap:.0%}, code overlap {self.shape_overlap:.0%})"
        )


@dataclass
class Version:
    """One variant's version of an aligned symbol."""

    variant: str
    entry: Entry
    disposition: str = ""
    note: str = ""
    attic_path: str = ""

    @property
    def mtime(self) -> float:
        return self.entry.mtime


@dataclass
class Slot:
    """One logical symbol, aligned across every variant that has it."""

    key: str
    name: str
    path: str
    versions: list[Version] = field(default_factory=list)
    status: str = UNANIMOUS
    chosen: Version | None = None
    reason: str = ""
    distinct: int = 1

    @property
    def present_in(self) -> list[str]:
        return [v.variant for v in self.versions]

    @property
    def missing_from(self) -> list[str]:
        return []

    @property
    def needs_review(self) -> bool:
        return self.status == CONFLICT and self.chosen is None


@dataclass
class ResidueVersion:
    """One variant's module-level content for a file, outside any symbol."""

    variant: str
    imports: tuple[str, ...] = ()
    statements: tuple[str, ...] = ()
    docstring: str = ""

    @property
    def digest(self) -> str:
        return sha("|".join(self.imports) + "##" + "|".join(self.statements))


@dataclass
class ResidueSlot:
    """The part of a file that is not inside any symbol.

    Imports, module docstrings, ``logger = getLogger(...)``, ``if __name__`` blocks.
    Tracking only symbols means a branch whose entire change was adding one import
    reads as "no differences" -- and the merge then silently drops the import and
    produces code that breaks at runtime. This slot is what closes that hole.
    """

    path: str
    by_variant: dict[str, ResidueVersion] = field(default_factory=dict)
    status: str = UNANIMOUS

    @property
    def distinct(self) -> int:
        return len({v.digest for v in self.by_variant.values()})

    @property
    def imports_union(self) -> list[str]:
        """Every import any variant needs, merged per module.

        Merging at the *name* level rather than the statement level matters: three
        variants of ``from typing import ...`` differing by one name must become one
        statement with all the names, not three overlapping statements.
        """
        return merge_imports(
            [s for version in self.by_variant.values() for s in version.imports]
        )

    def import_diffs(self) -> dict[str, list[str]]:
        """The individual imported names each variant is missing."""
        everything = _import_names(
            [s for version in self.by_variant.values() for s in version.imports]
        )
        out: dict[str, list[str]] = {}
        for name, version in self.by_variant.items():
            mine = _import_names(list(version.imports))
            missing = sorted(everything - mine)
            if missing:
                out[name] = missing
        return out

    @property
    def statements_differ(self) -> bool:
        return len({"|".join(v.statements) for v in self.by_variant.values()}) > 1


@dataclass
class AssetSlot:
    """A non-source file (config, asset, doc) aligned across variants."""

    path: str
    by_variant: dict[str, tuple[Path, str]] = field(default_factory=dict)  # variant -> (file, hash)
    status: str = UNANIMOUS
    chosen_variant: str = ""
    reason: str = ""

    @property
    def distinct(self) -> int:
        return len({h for _p, h in self.by_variant.values()})


@dataclass
class ReconcilePlan:
    """What coagulation will do, and the accounting that proves it loses nothing."""

    family: Family
    slots: list[Slot] = field(default_factory=list)
    residues: list[ResidueSlot] = field(default_factory=list)
    assets: list[AssetSlot] = field(default_factory=list)
    policy: str = NEWEST
    lead: str = ""
    problems: list[str] = field(default_factory=list)

    @property
    def residue_conflicts(self) -> list[ResidueSlot]:
        """Files whose module-level code differs beyond imports, which merge additively."""
        return [r for r in self.residues if r.statements_differ]

    @property
    def import_gaps(self) -> list[tuple[str, str, list[str]]]:
        """(path, variant, missing imports) -- what a whole-file copy would have dropped."""
        out: list[tuple[str, str, list[str]]] = []
        for residue in self.residues:
            for variant, missing in residue.import_diffs().items():
                if missing:
                    out.append((residue.path, variant, missing))
        return out

    # ------------------------------------------------------------------ accounting
    @property
    def total_versions(self) -> int:
        """Every version of every symbol in every variant. The denominator."""
        return sum(len(slot.versions) for slot in self.slots)

    def accounting(self) -> dict[str, int]:
        tally: dict[str, int] = defaultdict(int)
        for slot in self.slots:
            for version in slot.versions:
                tally[version.disposition or "unassigned"] += 1
        return dict(tally)

    def balanced(self) -> tuple[bool, str]:
        """Every version must have exactly one disposition. This is the proof."""
        tally = self.accounting()
        accounted = sum(tally.values())
        unassigned = tally.get("unassigned", 0)
        if unassigned:
            return False, f"{unassigned} version(s) have no disposition"
        if accounted != self.total_versions:
            return False, (
                f"accounted {accounted} != {self.total_versions} versions present"
            )
        return True, f"all {accounted} versions accounted for"

    def by_status(self, status: str) -> list[Slot]:
        return [s for s in self.slots if s.status == status]

    @property
    def conflicts(self) -> list[Slot]:
        return [s for s in self.slots if s.needs_review]

    # ---------------------------------------------------------------------- render
    def render(self, limit: int = 24) -> str:
        ok, message = self.balanced()
        counts = {status: len(self.by_status(status)) for status in STATUS_ORDER}
        tally = self.accounting()

        out = [
            "RECONCILE PLAN", "=" * 78,
            f"family      {self.family.key}",
            f"variants    {self.family.size}",
        ]
        for variant in sorted(self.family.variants, key=lambda v: -v.mtime):
            marker = "  <- newest" if variant is self.family.newest else ""
            out.append(
                f"              {variant.name[:46]:<46} {variant.when}  "
                f"{variant.symbol_count:>4} sym{marker}"
            )
        out += [
            f"policy      {self.policy}" + (f" (lead: {self.lead})" if self.lead else ""),
            "",
            "SYMBOL SLOTS", "-" * 78,
            f"  {counts[UNANIMOUS]:>5}  unanimous    every variant agrees byte for byte",
            f"  {counts[COSMETIC]:>5}  cosmetic     differ only in formatting or docstrings",
            f"  {counts[STRUCTURAL]:>5}  structural   same shape, renamed locals or changed literals",
            f"  {counts[UNIQUE]:>5}  unique       exists in only some variants -- all adopted",
            f"  {counts[CONFLICT]:>5}  conflict     materially different implementations",
            "",
            "DISPOSITION OF EVERY VERSION", "-" * 78,
            f"  {tally.get(ADOPTED, 0):>5}  adopted      written to the output",
            f"  {tally.get(SAME_AS_ADOPTED, 0):>5}  same         byte-identical to adopted; nothing lost",
            f"  {tally.get(ARCHIVED, 0):>5}  archived     differs; full copy preserved in the attic",
            f"  {tally.get(HELD, 0):>5}  held         unresolved; source left untouched",
            f"  {'-' * 5}",
            f"  {sum(tally.values()):>5}  total, against {self.total_versions} present",
            "",
            f"  BALANCE: {'OK -- ' if ok else 'FAILED -- '}{message}",
            "",
        ]

        gaps = self.import_gaps
        if self.residues:
            out += [
                "MODULE-LEVEL CONTENT (outside any symbol)", "-" * 78,
                f"  {len(self.residues)} files examined for imports, module docstrings "
                f"and loose statements",
                f"  {len(gaps)} file/variant pairs are missing an import another variant has",
                f"  {len(self.residue_conflicts)} files differ in module-level statements",
                "",
            ]
            if gaps:
                out.append("  IMPORTS THAT A WHOLE-FILE COPY WOULD HAVE DROPPED:")
                for path, variant, missing in gaps[:limit]:
                    out.append(f"    {path}  ({variant[:34]}) lacks: {', '.join(missing)[:80]}")
                if len(gaps) > limit:
                    out.append(f"    ... and {len(gaps) - limit} more")
                out.append("  These are merged additively, so the output gets all of them.")
                out.append("")
            for residue in self.residue_conflicts[:limit]:
                out.append(f"    module statements differ: {residue.path}")
            if self.residue_conflicts:
                out.append("")

        if self.assets:
            differing = [a for a in self.assets if a.distinct > 1]
            out += [
                "NON-SOURCE FILES", "-" * 78,
                f"  {len(self.assets)} distinct paths, {len(differing)} differ between variants",
                "",
            ]

        if self.conflicts:
            out += [f"CONFLICTS NEEDING A DECISION ({len(self.conflicts)})", "-" * 78]
            for slot in self.conflicts[:limit]:
                out.append(f"  {slot.path}#{slot.name}   {slot.distinct} distinct versions")
                for version in sorted(slot.versions, key=lambda v: -v.mtime):
                    out.append(
                        f"      {version.variant[:40]:<40} {version.entry.lines:>4}L  "
                        f"{_when(version.mtime)}"
                    )
            if len(self.conflicts) > limit:
                out.append(f"  ... and {len(self.conflicts) - limit} more")
            out.append("")

        unique = self.by_status(UNIQUE)
        if unique:
            out += [
                f"ONLY-IN-ONE-VARIANT ({len(unique)}) -- these are why you cannot just "
                f"keep the newest folder", "-" * 78,
            ]
            for slot in unique[:limit]:
                out.append(
                    f"  {slot.path}#{slot.name}   only in: "
                    f"{', '.join(v[:34] for v in slot.present_in)}"
                )
            if len(unique) > limit:
                out.append(f"  ... and {len(unique) - limit} more")
            out.append("")

        if self.problems:
            out += ["PROBLEMS", "-" * 78] + [f"  ! {p}" for p in self.problems[:20]]
        return "\n".join(out)


def _when(mtime: float) -> str:
    if not mtime:
        return "unknown"
    return _dt.datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")


# ------------------------------------------------------------- family detection

def _relative_paths(root: Path, limit: int = 4000) -> set[str]:
    out: set[str] = set()
    stack = [root]
    while stack and len(out) < limit:
        current = stack.pop()
        try:
            entries = list(current.iterdir())
        except OSError:
            continue
        for entry in entries:
            try:
                if entry.is_dir():
                    if entry.name in SKIP_DIR_NAMES or entry.name.startswith("."):
                        continue
                    stack.append(entry)
                elif entry.is_file():
                    out.add(entry.relative_to(root).as_posix())
            except OSError:
                continue
    return out


def detect_families(
    store,
    project_ids: list[int] | None = None,
    min_path_overlap: float = 0.45,
    min_shape_overlap: float = 0.30,
) -> list[Family]:
    """Group indexed projects into families of copies of the same project.

    Two signals, because either alone is fooled: path overlap catches a straight copy,
    and shape overlap catches a copy whose tree was reorganised or folder renamed.
    """
    projects = [
        p for p in store.projects()
        if (project_ids is None or p.id in project_ids) and not p.external
    ]
    if len(projects) < 2:
        return []

    profiles: dict[int, tuple] = {}
    for project in projects:
        root = Path(project.root)
        if not root.exists():
            continue
        paths = _relative_paths(root)
        shapes = {
            row["body_hash"]
            for row in store.many(
                "SELECT body_hash FROM symbols WHERE project_id = ?", (project.id,)
            )
        }
        newest = 0.0
        for row in store.many(
            "SELECT path FROM files WHERE project_id = ?", (project.id,)
        ):
            try:
                newest = max(newest, (root / row["path"]).stat().st_mtime)
            except OSError:
                continue
        profiles[project.id] = (project, paths, shapes, newest)

    union = {}
    families: dict[int, list] = defaultdict(list)
    scores: dict[tuple[int, int], tuple[float, float, int]] = {}

    ids = list(profiles)
    for i, left_id in enumerate(ids):
        for right_id in ids[i + 1 :]:
            _lp, left_paths, left_shapes, _lm = profiles[left_id]
            _rp, right_paths, right_shapes, _rm = profiles[right_id]

            shared_paths = len(left_paths & right_paths)
            path_overlap = (
                shared_paths / min(len(left_paths), len(right_paths))
                if left_paths and right_paths else 0.0
            )
            shape_overlap = (
                len(left_shapes & right_shapes) / min(len(left_shapes), len(right_shapes))
                if left_shapes and right_shapes else 0.0
            )
            if path_overlap >= min_path_overlap or shape_overlap >= min_shape_overlap:
                scores[(left_id, right_id)] = (path_overlap, shape_overlap, shared_paths)
                union.setdefault(left_id, left_id)
                root_left = _find(union, left_id)
                union.setdefault(right_id, right_id)
                union[_find(union, right_id)] = root_left

    for project_id in union:
        families[_find(union, project_id)].append(project_id)

    out: list[Family] = []
    for members in families.values():
        if len(members) < 2:
            continue
        variants = []
        for project_id in members:
            project, paths, shapes, newest = profiles[project_id]
            variants.append(Variant(
                name=project.name, root=Path(project.root), project_id=project.id,
                mtime=newest, file_count=len(paths), symbol_count=project.symbol_count,
            ))
        pairs = [
            scores[k] for k in scores
            if k[0] in members and k[1] in members
        ]
        out.append(Family(
            key=_family_key([v.name for v in variants]),
            variants=sorted(variants, key=lambda v: -v.mtime),
            path_overlap=max((p[0] for p in pairs), default=0.0),
            shape_overlap=max((p[1] for p in pairs), default=0.0),
            shared_paths=max((p[2] for p in pairs), default=0),
        ))
    out.sort(key=lambda f: -f.size)
    return out


def _find(union: dict, item):
    while union[item] != item:
        union[item] = union[union[item]]
        item = union[item]
    return item


def _family_key(names: list[str]) -> str:
    """The longest common prefix of the variant names, or the shortest name."""
    if not names:
        return "family"
    prefix = names[0]
    for name in names[1:]:
        while prefix and not name.startswith(prefix):
            prefix = prefix[:-1]
    prefix = prefix.rstrip("-_. ")
    return prefix if len(prefix) >= 4 else min(names, key=len)


# --------------------------------------------------------------------- alignment

def align(
    store,
    family: Family,
    policy: str = NEWEST,
    lead: str = "",
    include_assets: bool = True,
) -> ReconcilePlan:
    """Align every symbol across every variant and decide what wins."""
    plan = ReconcilePlan(family=family, policy=policy, lead=lead)

    by_variant: dict[str, list[Entry]] = {}
    for variant in family.variants:
        entries, problems = load_entries(store, [variant.project_id], min_lines=1)
        by_variant[variant.name] = entries
        plan.problems.extend(f"{variant.name}: {p}" for p in problems)

    # Primary alignment: same file path, same qualified name.
    slots: dict[str, Slot] = {}
    for variant_name, entries in by_variant.items():
        for entry in entries:
            key = f"{entry.path}#{entry.name}"
            slot = slots.get(key)
            if slot is None:
                slot = Slot(key=key, name=entry.name, path=entry.path)
                slots[key] = slot
            slot.versions.append(Version(variant=variant_name, entry=entry))

    # Secondary alignment: a symbol that moved to a different file still counts as the
    # same symbol. Match leftovers by identical shape hash and leaf name.
    _merge_moved(slots)

    for slot in slots.values():
        _classify(slot, len(family.variants))
        _choose(slot, policy, lead, family)
    plan.slots = sorted(
        slots.values(),
        key=lambda s: (STATUS_ORDER.index(s.status), s.path, s.name),
    )

    plan.residues = _align_residue(family)
    if include_assets:
        plan.assets = _align_assets(family)
    return plan


def _merge_moved(slots: dict[str, Slot]) -> None:
    """Fold single-variant slots into an existing slot when the code is the same.

    A file moved into a subpackage in one variant would otherwise look like a deletion
    plus an unrelated addition, and the merge would keep both copies.
    """
    singles = [s for s in slots.values() if len(s.versions) == 1]
    by_shape: dict[tuple[str, str], list[Slot]] = defaultdict(list)
    for slot in singles:
        shape = slot.versions[0].entry.norm.shape_hash
        if shape:
            by_shape[(shape, slot.name.rsplit(".", 1)[-1])].append(slot)

    for group in by_shape.values():
        if len(group) < 2:
            continue
        variants = {s.versions[0].variant for s in group}
        if len(variants) < 2:
            continue  # same variant twice is real duplication, not a move
        keeper = group[0]
        for other in group[1:]:
            keeper.versions.extend(other.versions)
            for version in other.versions:
                version.note = f"moved from {other.path}"
            slots.pop(other.key, None)


def _classify(slot: Slot, family_size: int) -> None:
    """Decide how this symbol's versions relate across variants."""
    norms = [v.entry.norm for v in slot.versions]
    slot.distinct = len({n.exact_hash for n in norms})

    if len(slot.versions) < family_size:
        slot.status = UNIQUE
        return
    if slot.distinct == 1:
        slot.status = UNANIMOUS
        return

    weakest = IDENTICAL
    rank = {IDENTICAL: 4, FORMATTING: 3, RENAMED: 2, DIVERGED: 1}
    for i, left in enumerate(norms):
        for right in norms[i + 1 :]:
            relation, _confidence = relate(left, right)
            if rank.get(relation, 0) < rank.get(weakest, 0):
                weakest = relation

    slot.status = {
        IDENTICAL: UNANIMOUS,
        FORMATTING: COSMETIC,
        RENAMED: STRUCTURAL,
    }.get(weakest, CONFLICT)


def _choose(slot: Slot, policy: str, lead: str, family: Family) -> None:
    """Pick the winning version and assign a disposition to every version.

    A conflict is never resolved silently. The default is to hold it, because guessing
    which of two real implementations you meant is exactly the way this loses work.
    """
    if slot.status == CONFLICT and policy != LEAD:
        for version in slot.versions:
            version.disposition = HELD
            version.note = version.note or "conflict: needs a decision"
        slot.reason = "materially different implementations -- held for review"
        return

    if policy == LEAD and lead:
        preferred = [v for v in slot.versions if v.variant == lead]
        winner = preferred[0] if preferred else max(slot.versions, key=lambda v: v.mtime)
        slot.reason = (
            f"lead variant {lead}" if preferred
            else f"not in lead {lead}; took newest ({winner.variant})"
        )
    elif policy == RICHEST:
        winner = max(slot.versions, key=lambda v: (v.entry.lines, v.mtime))
        slot.reason = f"most complete ({winner.entry.lines}L)"
    else:
        winner = max(slot.versions, key=lambda v: (v.mtime, v.entry.lines))
        slot.reason = f"newest ({_when(winner.mtime)})"

    slot.chosen = winner
    winner.disposition = ADOPTED
    for version in slot.versions:
        if version is winner:
            continue
        if version.entry.norm.exact_hash == winner.entry.norm.exact_hash:
            version.disposition = SAME_AS_ADOPTED
        else:
            version.disposition = ARCHIVED


# ------------------------------------------------------------------------ assets

def _import_names(statements: list[str]) -> set[str]:
    """Every name an import block brings into scope, as ``module.name`` keys."""
    import ast

    names: set[str] = set()
    for statement in statements:
        try:
            node = ast.parse(statement).body[0]
        except (SyntaxError, IndexError):
            continue
        if isinstance(node, ast.Import):
            for alias in node.names:
                names.add(f"{alias.name}" + (f" as {alias.asname}" if alias.asname else ""))
        elif isinstance(node, ast.ImportFrom):
            module = "." * (node.level or 0) + (node.module or "")
            for alias in node.names:
                label = alias.name + (f" as {alias.asname}" if alias.asname else "")
                names.add(f"{module}.{label}")
    return names


def merge_imports(statements: list[str]) -> list[str]:
    """Collapse a pile of import statements into the minimal equivalent set.

    ``from typing import Any, Dict`` plus ``from typing import Dict, Tuple`` becomes
    one ``from typing import Any, Dict, Tuple`` rather than both originals.
    """
    import ast

    plain: list[str] = []
    seen_plain: set[str] = set()
    grouped: dict[tuple[int, str], list[str]] = {}
    order: list[tuple[int, str]] = []

    for statement in statements:
        try:
            node = ast.parse(statement).body[0]
        except (SyntaxError, IndexError):
            continue
        if isinstance(node, ast.Import):
            for alias in node.names:
                rendered = alias.name + (f" as {alias.asname}" if alias.asname else "")
                if rendered not in seen_plain:
                    seen_plain.add(rendered)
                    plain.append(f"import {rendered}")
        elif isinstance(node, ast.ImportFrom):
            key = (node.level or 0, node.module or "")
            if key not in grouped:
                grouped[key] = []
                order.append(key)
            for alias in node.names:
                rendered = alias.name + (f" as {alias.asname}" if alias.asname else "")
                if rendered not in grouped[key]:
                    grouped[key].append(rendered)

    out = list(plain)
    for level, module in order:
        names = grouped[(level, module)]
        # `import *` cannot be combined with named imports on one line.
        if "*" in names:
            out.append(f"from {'.' * level}{module} import *")
            names = [n for n in names if n != "*"]
            if not names:
                continue
        out.append(f"from {'.' * level}{module} import " + ", ".join(sorted(names)))
    return out


def extract_residue(path: Path) -> ResidueVersion | None:
    """Pull the module-level content of one file: imports, docstring, loose statements."""
    import ast

    try:
        text = path.read_text(encoding="utf-8", errors="replace")
        tree = ast.parse(text)
    except (OSError, SyntaxError):
        return None

    imports: list[str] = []
    statements: list[str] = []
    docstring = ast.get_docstring(tree) or ""

    for index, node in enumerate(tree.body):
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            try:
                imports.append(ast.unparse(node))
            except Exception:
                continue
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            continue  # these are symbols, tracked as slots
        else:
            if index == 0 and docstring:
                continue  # the module docstring, already captured
            try:
                statements.append(ast.unparse(node))
            except Exception:
                continue
    return ResidueVersion(
        variant="", imports=tuple(sorted(imports)),
        statements=tuple(statements), docstring=docstring[:200],
    )


def _align_residue(family: Family) -> list[ResidueSlot]:
    """Compare every file's module-level content across variants."""
    slots: dict[str, ResidueSlot] = {}
    for variant in family.variants:
        for relative in _relative_paths(variant.root):
            if not relative.endswith((".py", ".pyw")):
                continue
            residue = extract_residue(variant.root / relative)
            if residue is None:
                continue
            residue.variant = variant.name
            slots.setdefault(relative, ResidueSlot(path=relative))
            slots[relative].by_variant[variant.name] = residue

    for slot in slots.values():
        if slot.distinct == 1:
            slot.status = UNANIMOUS
        elif len(slot.by_variant) < family.size:
            slot.status = UNIQUE
        elif slot.statements_differ:
            slot.status = CONFLICT
        else:
            slot.status = STRUCTURAL  # imports only, and those merge additively
    return sorted(slots.values(), key=lambda s: s.path)


_ASSET_SKIP_SUFFIX = {".pyc", ".pyo", ".log", ".sqlite3", ".db"}


def _align_assets(family: Family) -> list[AssetSlot]:
    """Align non-Python files so configs, docs and data are not silently dropped."""
    slots: dict[str, AssetSlot] = {}
    for variant in family.variants:
        for relative in _relative_paths(variant.root):
            if relative.endswith((".py", ".pyw")):
                continue
            path = variant.root / relative
            if path.suffix.lower() in _ASSET_SKIP_SUFFIX:
                continue
            try:
                if path.stat().st_size > 4_000_000:
                    continue
                digest = sha(path.read_bytes().decode("utf-8", "replace"))
            except OSError:
                continue
            slot = slots.setdefault(relative, AssetSlot(path=relative))
            slot.by_variant[variant.name] = (path, digest)

    for slot in slots.values():
        if slot.distinct == 1:
            slot.status = UNANIMOUS
        elif len(slot.by_variant) < family.size:
            slot.status = UNIQUE
        else:
            slot.status = CONFLICT
        newest = max(
            slot.by_variant.items(),
            key=lambda kv: kv[1][0].stat().st_mtime if kv[1][0].exists() else 0,
        )
        slot.chosen_variant = newest[0]
        slot.reason = "newest copy" if slot.distinct > 1 else "identical everywhere"
    return sorted(slots.values(), key=lambda s: s.path)
