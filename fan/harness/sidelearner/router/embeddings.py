"""Embeddings: provider-backed when available, deterministic local hash fallback."""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Optional

import numpy as np

from ..utils import sha1_hex, tokenize


class Embedder(ABC):
    """Turns text into unit vectors for kNN routing and graph retrieval."""

    dim: int = 256

    @abstractmethod
    def embed_texts(self, texts: list[str]) -> np.ndarray:
        """Return (N, dim) float32 array."""

    def embed_text(self, text: str) -> np.ndarray:
        return self.embed_texts([text])[0]


class TokenHashEmbedder(Embedder):
    """Deterministic, model-free embedding: hashed token projection.

    No model required — routes and retrieves well enough for short
    task/intent text, and is fully reproducible across restarts.
    """

    dim = 256

    def __init__(self, dim: int = 256) -> None:
        self.dim = dim

    def embed_texts(self, texts: list[str]) -> np.ndarray:
        out = np.zeros((len(texts), self.dim), dtype=np.float32)
        for row, text in enumerate(texts):
            vec = out[row]
            seen: set[str] = set()
            for tok in tokenize(text):
                if tok in seen:
                    continue
                seen.add(tok)
                h = int(sha1_hex(tok)[:16], 16)
                sign = 1.0 if (h >> 63) & 1 else -1.0
                vec[h % self.dim] += sign
            norm = float(np.linalg.norm(vec))
            if norm > 0:
                vec /= norm
        return out


class ProviderEmbedder(Embedder):
    """Wraps a provider with embedding capability; caches by text hash."""

    def __init__(self, provider, batch: int = 16) -> None:
        self.provider = provider
        self.batch = batch
        self.cache: dict[str, Optional[np.ndarray]] = {}
        self.dim = 0

    def embed_texts(self, texts: list[str]) -> np.ndarray:
        results: list[np.ndarray] = []
        missing: list[tuple[int, str]] = []
        for i, text in enumerate(texts):
            key = sha1_hex(text)
            if key in self.cache and self.cache[key] is not None:
                results.append(self.cache[key])
            else:
                results.append(None)  # type: ignore[arg-type]
                missing.append((i, text))
        if missing:
            for start in range(0, len(missing), self.batch):
                group = missing[start : start + self.batch]
                vecs = self.provider.embed([t for _, t in group])
                if not vecs:
                    for i, _ in group:
                        self.cache[sha1_hex(missing[i][1])] = None
                    raise RuntimeError("provider embed returned no vectors")
                for (i, text), vec in zip(group, vecs):
                    arr = np.asarray(vec, dtype=np.float32)
                    norm = float(np.linalg.norm(arr))
                    if norm > 0:
                        arr = arr / norm
                    self.cache[sha1_hex(text)] = arr
                    results[i] = arr
        matrix = np.vstack([np.zeros(self.dim, dtype=np.float32) if r is None else r for r in results])
        return matrix


def get_embedder(registry=None, prefer: str = "auto") -> Embedder:
    """Build the best available embedder: provider if healthy, else local hash."""
    if prefer != "hash" and registry is not None:
        provider = registry.embedder()
        if provider is not None:
            return ProviderEmbedder(provider)
    return TokenHashEmbedder()
