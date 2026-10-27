"""AST normalization: decide when two pieces of code are *the same thing*.

Lexical comparison cannot tell you that. Two functions can be byte-identical in intent
and share almost no characters, or differ by one renamed loop variable and look
completely different to a diff. So this module reduces code to a canonical shape and
hashes that.

Four levels of identity, cheapest first. Each is a strictly weaker claim than the last:

    exact      byte-for-byte identical
    text       identical after comments, docstrings and formatting are stripped
    shape      identical after local names are alpha-renamed and literals erased
    near       shape token streams overlap above a threshold (see similar.py)

``shape`` is the one that matters for coagulation: it catches the same function copied
into nine folders and lightly re-styled in each, which no diff tool will tell you is
one function.
"""

from __future__ import annotations

import ast
import builtins
import hashlib
import re
import textwrap
from dataclasses import dataclass, field

BUILTIN_NAMES = frozenset(dir(builtins))

# Names bound inside a symbol are renamed; everything else is API surface and kept.
# Scope handling is deliberately flat -- one binding table for the whole symbol rather
# than a proper scope stack. For deciding "is this the same function", that trades a
# rare false merge in deeply nested closures for a large simplification.
_BINDING_NODES = (
    ast.Name, ast.arg, ast.alias, ast.ExceptHandler, ast.NamedExpr,
)

SHINGLE_K = 4


def sha(text: str, length: int = 12) -> str:
    return hashlib.sha1(text.encode("utf-8", "ignore")).hexdigest()[:length]


@dataclass
class Normalized:
    """Every identity signal for one piece of code."""

    exact_hash: str = ""
    text_hash: str = ""
    shape_hash: str = ""
    tokens: tuple[str, ...] = ()
    shingles: frozenset[str] = frozenset()
    calls: frozenset[str] = frozenset()
    attributes: frozenset[str] = frozenset()
    literals: tuple[str, ...] = ()
    node_count: int = 0
    line_count: int = 0
    error: str = ""

    @property
    def ok(self) -> bool:
        return not self.error and bool(self.shape_hash)

    def jaccard(self, other: "Normalized") -> float:
        """Shingle overlap -- resilient to insertions, unlike a line diff."""
        if not self.shingles or not other.shingles:
            return 0.0
        intersection = len(self.shingles & other.shingles)
        union = len(self.shingles | other.shingles)
        return intersection / union if union else 0.0

    def call_overlap(self, other: "Normalized") -> float:
        """How much of what one calls, the other calls too."""
        if not self.calls and not other.calls:
            return 1.0
        if not self.calls or not other.calls:
            return 0.0
        return len(self.calls & other.calls) / len(self.calls | other.calls)


# --------------------------------------------------------------------- text level

_COMMENT = re.compile(r"#.*$", re.MULTILINE)


def strip_docstrings(tree: ast.AST) -> ast.AST:
    """Drop every docstring in place.

    A docstring is documentation, not structure. Leaving them in means the same
    function documented in one copy and undocumented in another hashes differently,
    which is exactly the false negative coagulation cannot afford.
    """
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef,
                                 ast.Module)):
            continue
        body = getattr(node, "body", None)
        if (
            body
            and isinstance(body[0], ast.Expr)
            and isinstance(getattr(body[0], "value", None), ast.Constant)
            and isinstance(body[0].value.value, str)
        ):
            node.body = body[1:] or [ast.Pass()]
    return tree


def strip_surface(code: str) -> str:
    """Remove comments, docstrings and all formatting variance.

    What survives is what the interpreter would care about. Two files that differ only
    in style hash identically here.
    """
    try:
        tree = ast.parse(textwrap.dedent(code))
    except SyntaxError:
        # Fall back to a lexical strip so unparsable code still gets a stable hash.
        stripped = _COMMENT.sub("", code)
        return "\n".join(line.strip() for line in stripped.splitlines() if line.strip())

    try:
        return ast.unparse(ast.fix_missing_locations(strip_docstrings(tree)))
    except Exception:
        return code.strip()


# -------------------------------------------------------------------- shape level

class _Canonicalizer(ast.NodeVisitor):
    """Emit a canonical token stream for an AST, with local names alpha-renamed."""

    def __init__(self, own_name: str = "") -> None:
        self.own_name = own_name.rsplit(".", 1)[-1]
        self.tokens: list[str] = []
        self.bindings: dict[str, str] = {}
        self.calls: set[str] = set()
        self.attributes: set[str] = set()
        self.literals: list[str] = []
        self.node_count = 0

    # -- binding table
    def collect_bindings(self, tree: ast.AST) -> None:
        """Pre-pass: every name bound anywhere in this symbol gets a slot."""
        for node in ast.walk(tree):
            if isinstance(node, ast.arg):
                self._bind(node.arg)
            elif isinstance(node, ast.Name) and isinstance(node.ctx, (ast.Store, ast.Del)):
                self._bind(node.id)
            elif isinstance(node, ast.ExceptHandler) and node.name:
                self._bind(node.name)
            elif isinstance(node, ast.alias):
                self._bind((node.asname or node.name).split(".")[0])
            elif isinstance(node, (ast.Global, ast.Nonlocal)):
                for name in node.names:
                    self._bind(name)

    def _bind(self, name: str) -> str:
        if name in {"self", "cls"}:
            return name  # receiver names are structural, not incidental
        if name not in self.bindings:
            self.bindings[name] = f"v{len(self.bindings)}"
        return self.bindings[name]

    def _render_name(self, name: str) -> str:
        if name == self.own_name:
            return "SELF"
        if name in self.bindings:
            return self.bindings[name]
        if name in BUILTIN_NAMES:
            return f"B:{name}"
        return f"G:{name}"  # free/global: real API surface, kept verbatim

    # -- emission
    def emit(self, token: str) -> None:
        self.tokens.append(token)

    def generic_visit(self, node: ast.AST) -> None:
        self.node_count += 1
        self.emit(type(node).__name__)
        super().generic_visit(node)

    def visit_Name(self, node: ast.Name) -> None:
        self.node_count += 1
        self.emit("N:" + self._render_name(node.id))

    def visit_arg(self, node: ast.arg) -> None:
        self.node_count += 1
        self.emit("A:" + self._render_name(node.arg))
        if node.annotation is not None:
            self.emit("ann")
            self.visit(node.annotation)

    def visit_Attribute(self, node: ast.Attribute) -> None:
        self.node_count += 1
        self.attributes.add(node.attr)
        self.emit("At:" + node.attr)
        self.visit(node.value)

    def visit_Constant(self, node: ast.Constant) -> None:
        self.node_count += 1
        # The type is structural; the value is usually incidental tuning.
        self.emit("L:" + type(node.value).__name__)
        self.literals.append(repr(node.value)[:40])

    def visit_Call(self, node: ast.Call) -> None:
        self.node_count += 1
        target = _call_target(node)
        if target:
            self.calls.add(target)
        self.emit("C:" + (target or "?"))
        self.visit(node.func)
        for arg in node.args:
            self.visit(arg)
        for keyword in node.keywords:
            self.emit("kw:" + (keyword.arg or "**"))
            self.visit(keyword.value)

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        self._function(node, "Def")

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
        self._function(node, "AsyncDef")

    def _function(self, node, label: str) -> None:
        self.node_count += 1
        name = "SELF" if node.name == self.own_name else f"F:{node.name}"
        self.emit(f"{label}:{name}")
        for decorator in node.decorator_list:
            self.emit("dec")
            self.visit(decorator)
        self.visit(node.args)
        if node.returns is not None:
            self.emit("ret")
            self.visit(node.returns)
        for statement in node.body:
            self.visit(statement)

    def visit_ClassDef(self, node: ast.ClassDef) -> None:
        self.node_count += 1
        name = "SELF" if node.name == self.own_name else f"K:{node.name}"
        self.emit("Class:" + name)
        for base in node.bases:
            self.visit(base)
        for statement in node.body:
            self.visit(statement)


def _call_target(node: ast.Call) -> str | None:
    func = node.func
    if isinstance(func, ast.Name):
        return func.id
    if isinstance(func, ast.Attribute):
        return func.attr
    return None


def _shingles(tokens: tuple[str, ...], k: int = SHINGLE_K) -> frozenset[str]:
    if len(tokens) < k:
        return frozenset(["|".join(tokens)]) if tokens else frozenset()
    return frozenset(
        "|".join(tokens[i : i + k]) for i in range(len(tokens) - k + 1)
    )


def normalize(code: str, own_name: str = "") -> Normalized:
    """Reduce one symbol's source to every identity signal we can compute."""
    raw = code or ""
    result = Normalized(
        exact_hash=sha(raw),
        line_count=len(raw.splitlines()),
    )

    dedented = textwrap.dedent(raw)
    result.text_hash = sha(strip_surface(dedented))

    try:
        tree = ast.parse(dedented)
    except SyntaxError as exc:
        result.error = f"unparsable: {exc.msg}"
        return result

    strip_docstrings(tree)
    canon = _Canonicalizer(own_name)
    canon.collect_bindings(tree)
    canon.visit(tree)

    tokens = tuple(canon.tokens)
    result.tokens = tokens
    result.shape_hash = sha("|".join(tokens))
    result.shingles = _shingles(tokens)
    result.calls = frozenset(canon.calls)
    result.attributes = frozenset(canon.attributes)
    result.literals = tuple(canon.literals[:40])
    result.node_count = canon.node_count
    return result


def normalize_file(path, own_name: str = "") -> Normalized:
    """Normalize a whole file. Unreadable files return a Normalized carrying the error."""
    from pathlib import Path

    try:
        return normalize(Path(path).read_text(encoding="utf-8", errors="replace"), own_name)
    except OSError as exc:
        return Normalized(error=f"unreadable: {exc}")


# ------------------------------------------------------------------ relationships

IDENTICAL = "identical"        # byte for byte
FORMATTING = "formatting"      # same code, different style/comments
RENAMED = "renamed"            # same shape, different local names or literals
NEAR = "near"                  # substantially overlapping shape
DIVERGED = "diverged"          # related but materially different
UNRELATED = "unrelated"


def relate(left: Normalized, right: Normalized, near_threshold: float = 0.72) -> tuple[str, float]:
    """Classify how two normalized symbols relate, with a confidence 0-1.

    The ordering matters: the strongest true claim wins, so a caller can trust that
    ``IDENTICAL`` really means identical and act on it without re-checking.
    """
    if left.exact_hash and left.exact_hash == right.exact_hash:
        return IDENTICAL, 1.0
    if left.text_hash and left.text_hash == right.text_hash:
        return FORMATTING, 0.99
    if left.shape_hash and left.shape_hash == right.shape_hash:
        return RENAMED, 0.95
    if not (left.ok and right.ok):
        return UNRELATED, 0.0

    overlap = left.jaccard(right)
    if overlap >= near_threshold:
        return NEAR, overlap
    if overlap >= 0.35 or left.call_overlap(right) >= 0.6:
        return DIVERGED, overlap
    return UNRELATED, overlap


#: Relationships where no information is lost by keeping only one copy.
LOSSLESS = frozenset({IDENTICAL, FORMATTING})
