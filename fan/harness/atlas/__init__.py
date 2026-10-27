"""Atlas -- a context map for codebases.

The premise: reading a project to understand it is the most expensive thing an LLM does,
and almost all of that cost is waste. Atlas replaces "read the files" with a three-tier
map -- one small atlas, one index per project, and byte-exact slices fetched by address --
so an agent can understand and extend a codebase without ever opening a whole file.

Start here:

    from atlas import Store, build_project_index, to_rows

    store = Store(Path("."))
    index = build_project_index(Path("some/project"))
    store.replace_index(store.upsert_project(index.name, index.root), *to_rows(index))

Then ``atlas find``, ``atlas get``, ``atlas gate`` from the CLI, or the Studio GUI.
See ``docs/CONTEXT_MAP_SPEC.md`` for the format itself.
"""

from __future__ import annotations

from .address import Address, AddressError, is_address
from .buckets import BUCKETS, BY_KEY, Verdict, bucket_titles, classify
from .index import ProjectIndex, build_project_index, render_atlas_md, render_index_md, to_rows
from .ledger import Ledger
from .rules import FindResult, GateReport, Placement, find, gate, plan_insert
from .scanner import FileScan, Symbol, scan_project, scan_source
from .slicer import Slice, SliceError, expand, get, impact
from .spec import SPEC_VERSION
from .store import ProjectRow, Store

__version__ = "1.0.0"
__spec_version__ = SPEC_VERSION

__all__ = [
    "Address", "AddressError", "is_address",
    "BUCKETS", "BY_KEY", "Verdict", "bucket_titles", "classify",
    "ProjectIndex", "build_project_index", "render_atlas_md", "render_index_md", "to_rows",
    "Ledger",
    "FindResult", "GateReport", "Placement", "find", "gate", "plan_insert",
    "FileScan", "Symbol", "scan_project", "scan_source",
    "Slice", "SliceError", "expand", "get", "impact",
    "ProjectRow", "Store",
    "SPEC_VERSION", "__version__",
]
