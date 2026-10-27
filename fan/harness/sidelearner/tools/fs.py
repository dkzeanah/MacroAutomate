"""Filesystem tools, sandboxed to configured roots (Codex workspace-write style)."""
from __future__ import annotations

import logging
import re
from pathlib import Path
from typing import Any, Optional

log = logging.getLogger("sidelearner.tools.fs")


class FsSandbox:
    """Resolves paths inside configured roots; writes never escape the roots."""

    def __init__(self, roots: list[str], max_read_bytes: int = 1_000_000) -> None:
        self.roots = [Path(r).resolve() for r in roots]
        self.max_read_bytes = max_read_bytes

    def _resolve(self, path: str, for_write: bool = False) -> Path:
        p = Path(path).expanduser()
        if p.is_absolute():
            resolved = p.resolve()
            if not any(resolved == r or r in resolved.parents for r in self.roots):
                raise PermissionError(f"path outside sandbox roots {self.roots}: {path}")
            return resolved
        if for_write:
            return (self.roots[0] / p).resolve()
        for root in self.roots:
            candidate = (root / p).resolve()
            if candidate.exists():
                return candidate
        return (self.roots[0] / p).resolve()

    def ok(self, text: str, **data) -> dict:
        return {"ok": True, "text": text, **data}


def build(sandbox: FsSandbox) -> dict[str, Any]:
    """Return the tool functions bound to a sandbox."""
    max_bytes = sandbox.max_read_bytes

    def read_text(path: str, max_chars: int = 8000) -> dict:
        target = sandbox._resolve(path)
        if not target.exists():
            return {"ok": False, "text": f"file not found: {path}"}
        if target.stat().st_size > max_bytes:
            return {"ok": False, "text": f"file too large ({target.stat().st_size} bytes > {max_bytes})"}
        try:
            text = target.read_text(encoding="utf-8", errors="replace")
        except Exception as exc:  # noqa: BLE001
            return {"ok": False, "text": f"read failed: {exc}"}
        clipped = text[:max_chars]
        return sandbox.ok(
            f"read {path} ({len(text)} chars, showing {len(clipped)}):\n{clipped}",
            file=str(target),
            chars=len(text),
            content=text,
            truncated=len(text) > max_chars,
        )

    def write_text(path: str, content: str, append: bool = False, mkdirs: bool = True) -> dict:
        target = sandbox._resolve(path, for_write=True)
        if mkdirs:
            target.parent.mkdir(parents=True, exist_ok=True)
        mode = "a" if append else "w"
        with open(target, mode, encoding="utf-8") as fh:
            fh.write(content)
        return sandbox.ok(f"wrote {len(content)} chars to {target}", file=str(target), written=[str(target)])

    def edit(path: str, old: str, new: str, replace_all: bool = False) -> dict:
        """Targeted literal replacement inside a text file."""
        target = sandbox._resolve(path, for_write=True)
        if not target.exists():
            return {"ok": False, "text": f"file not found: {path}"}
        text = target.read_text(encoding="utf-8", errors="replace")
        count = text.count(old)
        if count == 0:
            return {"ok": False, "text": "old_string not found in file"}
        if count > 1 and not replace_all:
            return {"ok": False, "text": f"old_string appears {count} times; set replace_all=true or make it unique"}
        text = text.replace(old, new) if replace_all else text.replace(old, new, 1)
        target.write_text(text, encoding="utf-8")
        return sandbox.ok(f"edited {path} ({count} occurrence(s) replaced)", file=str(target), written=[str(target)])

    def list_dir(path: str = ".", max_depth: int = 1, limit: int = 200) -> dict:
        target = sandbox._resolve(path)
        if not target.exists():
            return {"ok": False, "text": f"directory not found: {path}"}
        entries = []
        if max_depth <= 1:
            for item in sorted(target.iterdir()):
                entries.append(
                    {
                        "name": item.name,
                        "type": "dir" if item.is_dir() else "file",
                        "size": item.stat().st_size if item.is_file() else None,
                    }
                )
        else:
            for item in sorted(target.rglob("*")):
                if len(item.relative_to(target).parts) > max_depth:
                    continue
                entries.append(
                    {
                        "name": str(item.relative_to(target)),
                        "type": "dir" if item.is_dir() else "file",
                        "size": item.stat().st_size if item.is_file() else None,
                    }
                )
        clipped = entries[:limit]
        lines = "\n".join(f"{'D' if e['type'] == 'dir' else ' '} {e['name']}" for e in clipped)
        return sandbox.ok(f"{len(clipped)} entries in {path}:\n{lines}", entries=clipped, total=len(entries))

    def glob(pattern: str, limit: int = 200) -> dict:
        root = sandbox.roots[0]
        hits = sorted(root.glob(pattern))
        clipped = hits[:limit]
        return sandbox.ok(
            f"{len(clipped)} matches for {pattern}:\n" + "\n".join(str(h.relative_to(root)) for h in clipped),
            matches=[str(h.relative_to(root)) for h in clipped],
            total=len(hits),
        )

    def grep(path: str = ".", pattern: str = "", max_hits: int = 40, include: Optional[str] = None) -> dict:
        target = sandbox._resolve(path)
        if not target.exists():
            return {"ok": False, "text": f"path not found: {path}"}
        try:
            rx = re.compile(pattern)
        except re.error as exc:
            return {"ok": False, "text": f"bad regex: {exc}"}
        hits: list[dict] = []
        files = [target] if target.is_file() else sorted(target.rglob("*"))
        for f in files:
            if not f.is_file() or f.stat().st_size > max_bytes:
                continue
            if include and not f.match(include):
                continue
            if any(part.startswith((".git", ".venv", "node_modules", "__pycache__")) for part in f.parts):
                continue
            try:
                text = f.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            rel = str(f.relative_to(target)) if target.is_dir() else f.name
            for i, line in enumerate(text.splitlines(), 1):
                if rx.search(line):
                    hits.append({"file": rel, "line": i, "text": line[:300]})
                    if len(hits) >= max_hits:
                        break
            if len(hits) >= max_hits:
                break
        lines = "\n".join(f"{h['file']}:{h['line']}: {h['text']}" for h in hits)
        return sandbox.ok(f"{len(hits)} matches for /{pattern}/:\n{lines}", hits=hits)

    def mkdir(path: str) -> dict:
        target = sandbox._resolve(path, for_write=True)
        target.mkdir(parents=True, exist_ok=True)
        return sandbox.ok(f"created directory {target}", created=[str(target)])

    def stat(path: str) -> dict:
        target = sandbox._resolve(path)
        if not target.exists():
            return {"ok": False, "text": f"not found: {path}"}
        st = target.stat()
        return sandbox.ok(
            f"{path}: {'dir' if target.is_dir() else 'file'}, {st.st_size} bytes, mtime {st.st_mtime}",
            size=st.st_size,
            is_dir=target.is_dir(),
            exists=True,
        )

    def copy(src: str, dst: str) -> dict:
        source = sandbox._resolve(src)
        dest = sandbox._resolve(dst, for_write=True)
        if not source.exists():
            return {"ok": False, "text": f"source not found: {src}"}
        import shutil

        if source.is_dir():
            shutil.copytree(source, dest, dirs_exist_ok=True)
        else:
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, dest)
        return sandbox.ok(f"copied {src} -> {dst}", written=[str(dest)])

    def move(src: str, dst: str) -> dict:
        source = sandbox._resolve(src)
        dest = sandbox._resolve(dst, for_write=True)
        if not source.exists():
            return {"ok": False, "text": f"source not found: {src}"}
        dest.parent.mkdir(parents=True, exist_ok=True)
        source.rename(dest)
        return sandbox.ok(f"moved {src} -> {dst}", written=[str(dest)])

    def delete(path: str) -> dict:
        target = sandbox._resolve(path, for_write=True)
        if not target.exists():
            return {"ok": False, "text": f"not found: {path}"}
        if target.is_dir():
            import shutil

            shutil.rmtree(target)
        else:
            target.unlink()
        return sandbox.ok(f"deleted {path}")

    return {
        "read_text": read_text,
        "write_text": write_text,
        "edit": edit,
        "list_dir": list_dir,
        "glob": glob,
        "grep": grep,
        "mkdir": mkdir,
        "stat": stat,
        "copy": copy,
        "move": move,
        "delete": delete,
    }


def register_fs_tools(registry, config) -> FsSandbox:
    """Register all fs tools on the registry; returns the sandbox."""
    from .registry import ToolSpec

    sandbox = FsSandbox(
        roots=config.get("tools.fs.roots", ["."]),
        max_read_bytes=int(config.get("tools.fs.max_read_bytes", 1_000_000)),
    )
    funcs = build(sandbox)
    specs = [
        ToolSpec("fs.read_text", "Read a text file (sandboxed).", {"path": "str", "max_chars": "int"}, funcs["read_text"], "low", "fs", True),
        ToolSpec("fs.write_text", "Write or append a text file.", {"path": "str", "content": "str", "append": "bool", "mkdirs": "bool"}, funcs["write_text"], "medium", "fs", False),
        ToolSpec("fs.edit", "Targeted literal replacement in a text file.", {"path": "str", "old": "str", "new": "str", "replace_all": "bool"}, funcs["edit"], "medium", "fs", False),
        ToolSpec("fs.list_dir", "List a directory.", {"path": "str", "max_depth": "int"}, funcs["list_dir"], "low", "fs", True),
        ToolSpec("fs.glob", "Glob for paths.", {"pattern": "str"}, funcs["glob"], "low", "fs", True),
        ToolSpec("fs.grep", "Regex search across files.", {"path": "str", "pattern": "str", "max_hits": "int", "include": "str"}, funcs["grep"], "low", "fs", True),
        ToolSpec("fs.mkdir", "Create a directory.", {"path": "str"}, funcs["mkdir"], "low", "fs", False),
        ToolSpec("fs.stat", "Stat a path.", {"path": "str"}, funcs["stat"], "low", "fs", True),
        ToolSpec("fs.copy", "Copy a file or directory.", {"src": "str", "dst": "str"}, funcs["copy"], "medium", "fs", False),
        ToolSpec("fs.move", "Move/rename a file or directory.", {"src": "str", "dst": "str"}, funcs["move"], "medium", "fs", False),
        ToolSpec("fs.delete", "Delete a file or directory.", {"path": "str"}, funcs["delete"], "high", "fs", False),
    ]
    registry.register_many(specs)
    return sandbox
