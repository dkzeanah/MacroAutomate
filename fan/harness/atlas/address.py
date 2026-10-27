"""Canonical symbol addresses.

An address is the single token an agent quotes to ask for code. It survives edits
because it carries no line numbers -- those live in the index, which is regenerated.

    @bucket/project:rel/path.py#Class.method
    @bucket/project:rel/path.py#function
    @bucket/project:rel/path.py
    @bucket/project
    @bucket
"""

from __future__ import annotations

import re
from dataclasses import dataclass

_ADDRESS_RE = re.compile(
    r"^@(?P<bucket>[a-z0-9][a-z0-9-]*)"
    r"(?:/(?P<project>[^:#\s]+))?"
    r"(?::(?P<path>[^#\s]+))?"
    r"(?:#(?P<symbol>[A-Za-z_][A-Za-z0-9_.]*))?$"
)


class AddressError(ValueError):
    """Raised when a string is not a well-formed address."""


@dataclass(frozen=True)
class Address:
    """A parsed, canonical address. Compare and hash by value."""

    bucket: str
    project: str | None = None
    path: str | None = None
    symbol: str | None = None

    # ---------------------------------------------------------------- construction
    @classmethod
    def parse(cls, raw: str) -> "Address":
        text = (raw or "").strip()
        if not text:
            raise AddressError("empty address")
        if not text.startswith("@"):
            text = "@" + text
        match = _ADDRESS_RE.match(text)
        if not match:
            raise AddressError(f"malformed address: {raw!r}")
        data = match.groupdict()
        path = data["path"]
        if path:
            path = path.replace("\\", "/").lstrip("./")
        return cls(
            bucket=data["bucket"],
            project=data["project"],
            path=path,
            symbol=data["symbol"],
        )

    @classmethod
    def build(
        cls,
        bucket: str,
        project: str | None = None,
        path: str | None = None,
        symbol: str | None = None,
    ) -> "Address":
        if path:
            path = str(path).replace("\\", "/").lstrip("./")
        return cls(bucket=bucket, project=project, path=path, symbol=symbol)

    # ------------------------------------------------------------------- rendering
    def __str__(self) -> str:
        out = "@" + self.bucket
        if self.project:
            out += "/" + self.project
        if self.path:
            out += ":" + self.path
        if self.symbol:
            out += "#" + self.symbol
        return out

    # -------------------------------------------------------------------- geometry
    @property
    def level(self) -> str:
        """How deep this address points: bucket / project / file / symbol."""
        if self.symbol:
            return "symbol"
        if self.path:
            return "file"
        if self.project:
            return "project"
        return "bucket"

    @property
    def owner(self) -> str | None:
        """For ``Class.method`` returns ``Class``; for a bare function returns None."""
        if self.symbol and "." in self.symbol:
            return self.symbol.rsplit(".", 1)[0]
        return None

    @property
    def leaf(self) -> str | None:
        """The final name component of the symbol."""
        if not self.symbol:
            return None
        return self.symbol.rsplit(".", 1)[-1]

    def to_file(self) -> "Address":
        """Drop the symbol, keeping the enclosing file."""
        return Address(self.bucket, self.project, self.path, None)

    def to_project(self) -> "Address":
        return Address(self.bucket, self.project, None, None)

    def with_symbol(self, symbol: str) -> "Address":
        return Address(self.bucket, self.project, self.path, symbol)


def is_address(raw: str) -> bool:
    """True when ``raw`` parses as an address. Never raises."""
    try:
        Address.parse(raw)
    except AddressError:
        return False
    return True


def shorten(address: Address | str, relative_to: Address | str | None = None) -> str:
    """Render ``address`` with any prefix shared with ``relative_to`` stripped.

    Used inside an index file, where bucket and project are implied by the header,
    so an edge can be written as ``loop.plan`` instead of the full address.
    """
    addr = address if isinstance(address, Address) else Address.parse(address)
    if relative_to is None:
        return str(addr)
    base = relative_to if isinstance(relative_to, Address) else Address.parse(relative_to)
    if addr.bucket != base.bucket:
        return str(addr)
    if addr.project != base.project:
        return str(addr).split("/", 1)[-1]
    if addr.path != base.path:
        return (addr.path or "") + ("#" + addr.symbol if addr.symbol else "")
    return addr.symbol or (addr.path or "")
