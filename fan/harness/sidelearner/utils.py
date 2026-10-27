"""Shared utilities: logging, time, text, math, retry, threading helpers."""
from __future__ import annotations

import hashlib
import json
import logging
import math
import re
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Iterable, Iterator, Optional

_FENCE_RE = re.compile(r"```(?:json|JSON)?\s*(.*?)```", re.DOTALL)


def utcnow() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def now_ms() -> int:
    return int(time.time() * 1000)


def setup_logging(level: str = "INFO", logfile: Optional[Path] = None) -> None:
    """Configure root logging; call once at startup."""
    handlers: list[logging.Handler] = [logging.StreamHandler(sys.stderr)]
    if logfile:
        logfile.parent.mkdir(parents=True, exist_ok=True)
        handlers.append(logging.FileHandler(logfile, encoding="utf-8"))
    logging.basicConfig(
        level=getattr(logging, level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
        handlers=handlers,
    )
    # Keep third-party libs quiet-ish.
    for noisy in ("urllib3", "httpx", "openai", "httpcore", "PIL"):
        logging.getLogger(noisy).setLevel(logging.WARNING)


def sha1_hex(data: bytes | str) -> str:
    if isinstance(data, str):
        data = data.encode("utf-8", errors="replace")
    return hashlib.sha1(data).hexdigest()


def cosine(a: Iterable[float], b: Iterable[float]) -> float:
    """Cosine similarity between two vectors (lists/arrays)."""
    import numpy as np  # local import keeps core light if unused

    va, vb = np.asarray(a, dtype=np.float64), np.asarray(b, dtype=np.float64)
    if va.shape != vb.shape or va.size == 0:
        return 0.0
    denom = float(np.linalg.norm(va) * np.linalg.norm(vb))
    if denom == 0.0:
        return 0.0
    return float(np.dot(va, vb) / denom)


def chunk_text(text: str, size: int = 1200, overlap: int = 120) -> list[str]:
    """Split text into overlapping chunks (by characters, then rounded to lines)."""
    text = text.strip()
    if not text or len(text) <= size:
        return [text] if text else []
    chunks: list[str] = []
    start = 0
    while start < len(text):
        end = min(start + size, len(text))
        if end < len(text):
            # Try to break at a newline near the end for cleaner chunks.
            nl = text.rfind("\n", start + size // 2, end)
            if nl > start:
                end = nl + 1
        chunks.append(text[start:end].strip())
        if end >= len(text):
            break
        start = max(start + 1, end - overlap)
    return [c for c in chunks if c]


_TOKEN_RE = re.compile(r"[a-z0-9][a-z0-9_\-]{1,}")


def _stem(tok: str) -> str:
    """Tiny English stemmer: enough to map plurals/gerunds to base forms."""
    if len(tok) > 5 and tok.endswith("ing"):
        tok = tok[:-3]
    if len(tok) > 4 and tok.endswith("ies"):
        tok = tok[:-3] + "y"
    elif len(tok) > 4 and tok.endswith("es") and not tok.endswith(("sses", "xes", "ches", "shes")):
        tok = tok[:-2]
    elif len(tok) > 3 and tok.endswith("s") and not tok.endswith("ss"):
        tok = tok[:-1]
    return tok


def tokenize(text: str) -> list[str]:
    """Lowercase stemmed tokens, including camelCase splits."""
    text = re.sub(r"([a-z])([A-Z])", r"\1 \2", text or "")
    return [_stem(tok) for tok in _TOKEN_RE.findall(text.lower())]


def jaccard(tokens_a: Iterable[str], tokens_b: Iterable[str]) -> float:
    a, b = set(tokens_a), set(tokens_b)
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def json_loads_lenient(text: str) -> Any:
    """Parse JSON, tolerating markdown fences and stray text around it."""
    if not text:
        raise ValueError("empty text")
    text = text.strip()
    m = _FENCE_RE.search(text)
    if m:
        text = m.group(1).strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        # Try the outermost {...} or [...] span.
        for opener, closer in (("{", "}"), ("[", "]")):
            s, e = text.find(opener), text.rfind(closer)
            if 0 <= s < e:
                try:
                    return json.loads(text[s : e + 1])
                except json.JSONDecodeError:
                    pass
        raise


def bounded_retry(
    fn: Callable[[], Any],
    retries: int = 2,
    delay: float = 0.5,
    backoff: float = 2.0,
    exceptions: tuple[type[BaseException], ...] = (Exception,),
    log: Optional[logging.Logger] = None,
) -> Any:
    """Retry fn() a bounded number of times on the given exceptions."""
    attempt = 0
    wait = delay
    while True:
        try:
            return fn()
        except exceptions as exc:  # noqa: BLE001
            attempt += 1
            if attempt > retries:
                raise
            if log:
                log.warning("retry %d/%d after %r", attempt, retries, exc)
            time.sleep(wait)
            wait *= backoff


def run_thread(
    target: Callable[..., Any],
    name: str,
    daemon: bool = True,
    args: tuple = (),
    kwargs: Optional[dict] = None,
) -> threading.Thread:
    t = threading.Thread(target=target, name=name, daemon=daemon, args=args, kwargs=kwargs or {})
    t.start()
    return t


def clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def deep_merge(base: dict, override: dict) -> dict:
    """Recursively merge override into base (dicts merged, everything else replaced)."""
    out = dict(base)
    for key, value in (override or {}).items():
        if key in out and isinstance(out[key], dict) and isinstance(value, dict):
            out[key] = deep_merge(out[key], value)
        else:
            out[key] = value
    return out


def expand_env(value: Any) -> Any:
    """Expand ${VAR}/$VAR environment references in strings (recursively)."""
    import os

    if isinstance(value, str):
        return os.path.expandvars(value)
    if isinstance(value, dict):
        return {k: expand_env(v) for k, v in value.items()}
    if isinstance(value, list):
        return [expand_env(v) for v in value]
    return value


def format_bytes(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.1f}{unit}"
        n /= 1024
    return f"{n:.1f}GB"


def sliding(iterable: Iterable, size: int) -> Iterator[tuple]:
    it = iter(iterable)
    window: list = []
    for item in it:
        window.append(item)
        if len(window) == size:
            yield tuple(window)
            window.pop(0)
