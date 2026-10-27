"""Constants and vocabulary for the Context Map format.

Everything in Atlas that a third party has to agree with lives here. If you change a
value in this module you have changed the wire format, and ``SPEC_VERSION`` must move
with it. See ``docs/CONTEXT_MAP_SPEC.md`` for the prose.
"""

from __future__ import annotations

SPEC_VERSION = "1.0"

# --- symbol kinds -----------------------------------------------------------------
KIND_CLASS = "C"
KIND_FUNC = "F"
KIND_PRIVATE = "f"
KIND_ASYNC = "A"
KIND_CONST = "K"

KIND_NAMES = {
    KIND_CLASS: "class",
    KIND_FUNC: "function",
    KIND_PRIVATE: "private",
    KIND_ASYNC: "async",
    KIND_CONST: "constant",
}

# --- flags ------------------------------------------------------------------------
FLAG_OBSOLETE = "X"
FLAG_UNTESTED = "!"
FLAG_HOT = "*"
FLAG_EXTERNAL = "e"

FLAG_NAMES = {
    FLAG_OBSOLETE: "superseded, retained in attic",
    FLAG_UNTESTED: "no test references this symbol",
    FLAG_HOT: "changed recently or frequently",
    FLAG_EXTERNAL: "vendored third-party code, do not edit",
}

# --- edge markers -----------------------------------------------------------------
EDGE_OUT = ">"   # this symbol calls these
EDGE_IN = "<"    # these symbols call this one
EDGE_NONE = "-"

# --- in-file mirror comment -------------------------------------------------------
MIRROR_PREFIX = "# @atlas"

# --- layout -----------------------------------------------------------------------
ATLAS_DIR = ".atlas"
ATTIC_DIR = "attic"
BACKUP_DIR = "backups"
DB_NAME = "atlas.sqlite3"
ATLAS_MD = "ATLAS.md"
INDEX_MD = "INDEX.md"
LLM_GUIDE_MD = "LLM_GUIDE.md"

# --- budgets ----------------------------------------------------------------------
# A symbol longer than this must be split before the rule engine will place it.
DEFAULT_MAX_SYMBOL_LINES = 80
# A condensed file longer than this gets a second section file.
DEFAULT_MAX_FILE_LINES = 2000
# Rough characters-per-token for budget estimates. Deliberately conservative.
CHARS_PER_TOKEN = 3.6

# --- scanning ---------------------------------------------------------------------
SKIP_DIR_NAMES = {
    ".git", ".hg", ".svn", "__pycache__", ".venv", "venv", "env",
    "node_modules", ".pytest_cache", ".mypy_cache", ".ruff_cache",
    "dist", "build", "site-packages", ".tox", ".idea", ".vscode",
    ATLAS_DIR, ".next", ".cache", "htmlcov", ".eggs",
}

SOURCE_SUFFIXES = {".py", ".pyw"}

# Files larger than this are indexed by name only; they are almost never source.
MAX_SOURCE_BYTES = 2_000_000


def token_estimate(text: str) -> int:
    """Conservative token count for a blob of text."""
    return int(len(text) / CHARS_PER_TOKEN) + 1
