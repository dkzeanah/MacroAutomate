"""Fan's self-trained embedding model ("fan-ri-256").

No downloads, no GPU: a 256-dimension distributional model trained on exactly
what has been ingested.

* Every root has a fixed sparse *index vector* (8 signed positions chosen by a
  hash), so the model is deterministic and needs no stored vocabulary.
* A root's *lexical* vector sums the index vectors of the root and its character
  trigrams, so ``dome``/``domes``/``geodesicdome`` land close together.
* A root's *context* vector is learned by Random Indexing (Kanerva/Sahlgren):
  each time it appears, the index vectors of nearby roots are added. Roots used
  in similar contexts ("strut", "hub", "frequency" near "dome") converge.
* A sentence vector is the IDF-weighted sum of its roots' combined vectors.

Context vectors keep improving as more is ingested; elements are re-embedded
when the model has moved on (``Model.version``).
"""
from __future__ import annotations

import hashlib
import math
import struct
from array import array

DIM = 256
NONZERO = 8
MODEL = "fan-ri-256-v1"
WINDOW = 4

_index_cache: dict[str, tuple] = {}


def index_vector(feature: str) -> tuple:
    """((position, sign), ...) - deterministic sparse ternary vector."""
    cached = _index_cache.get(feature)
    if cached is not None:
        return cached
    digest = hashlib.blake2b(feature.encode("utf-8"), digest_size=2 * NONZERO + 2).digest()
    pairs, used = [], set()
    for i in range(NONZERO):
        position = (digest[2 * i] | (digest[2 * i + 1] << 8)) % DIM
        while position in used:
            position = (position + 1) % DIM
        used.add(position)
        pairs.append((position, 1.0 if (digest[-1] >> (i % 8)) & 1 else -1.0))
    result = tuple(pairs)
    if len(_index_cache) < 500000:
        _index_cache[feature] = result
    return result


def zeros() -> list:
    return [0.0] * DIM


def add_sparse(target: list, sparse: tuple, weight: float) -> None:
    for position, sign in sparse:
        target[position] += sign * weight


def add_dense(target: list, source, weight: float) -> None:
    for i in range(DIM):
        target[i] += source[i] * weight


def norm(vector) -> float:
    return math.sqrt(sum(v * v for v in vector))


def normalize(vector) -> list:
    length = norm(vector)
    return [v / length for v in vector] if length else list(vector)


def dot(a, b) -> float:
    return sum(x * y for x, y in zip(a, b))


def cosine(a, b) -> float:
    la, lb = norm(a), norm(b)
    return dot(a, b) / (la * lb) if la and lb else 0.0


def pack(vector) -> bytes:
    return struct.pack(f"<{DIM}f", *vector)


def unpack(blob: bytes) -> list:
    if not blob:
        return zeros()
    if len(blob) == DIM * 2:
        return list(struct.unpack(f"<{DIM}e", blob))
    return list(array("f", blob)) if len(blob) == DIM * 4 else list(struct.unpack(f"<{len(blob) // 4}f", blob))


def pack_half(vector) -> bytes:
    """Context vectors are stored at half precision (512 bytes per root)."""
    peak = max((abs(v) for v in vector), default=0.0)
    scale = 60000.0 / peak if peak > 60000 else 1.0
    return struct.pack(f"<{DIM}e", *(v * scale for v in vector))


def lexical(root: str) -> list:
    vector = zeros()
    add_sparse(vector, index_vector("r:" + root), 1.0)
    padded = f"<{root}>"
    grams = [padded[i:i + 3] for i in range(len(padded) - 2)]
    if grams:
        weight = 0.6 / math.sqrt(len(grams))
        for gram in grams:
            add_sparse(vector, index_vector("g:" + gram), weight)
    return vector


class Model:
    """Root vectors (lexical + learned context) and sentence embeddings.

    ``contexts`` maps root -> context vector (dense list); ``df`` maps root ->
    number of elements containing it, used for IDF weights and for how much the
    learned context is trusted.
    """

    def __init__(self, contexts: dict | None = None, df: dict | None = None, total: int = 0):
        self.contexts = contexts if contexts is not None else {}
        self.df = df if df is not None else {}
        self.total = total
        self._root_cache: dict[str, list] = {}

    @property
    def version(self) -> str:
        # Coarse corpus size bucket: embeddings refresh as the model grows.
        bucket = int(math.log2(self.total + 1))
        return f"{MODEL}:{bucket}"

    def idf(self, root: str) -> float:
        return math.log((self.total + 1) / (self.df.get(root, 0) + 0.5)) + 0.1

    def learn(self, roots: list[str]) -> None:
        """Random Indexing update for one sentence's roots."""
        if len(self._root_cache) > 50000:
            self._root_cache.clear()
        for i, root in enumerate(roots):
            context = self.contexts.get(root)
            if context is None:
                context = self.contexts[root] = zeros()
            lo, hi = max(0, i - WINDOW), min(len(roots), i + WINDOW + 1)
            for j in range(lo, hi):
                if j != i and roots[j] != root:
                    add_sparse(context, index_vector("r:" + roots[j]), 1.0 / abs(i - j))
            self._root_cache.pop(root, None)

    def root_vector(self, root: str) -> list:
        cached = self._root_cache.get(root)
        if cached is not None:
            return cached
        vector = normalize(lexical(root))
        context = self.contexts.get(root)
        if context is not None:
            evidence = self.df.get(root, 0)
            trust = 1.1 * min(1.0, evidence / 4.0)
            if trust > 0:
                add_dense(vector, normalize(context), trust)
        vector = normalize(vector)
        self._root_cache[root] = vector
        return vector

    def embed(self, roots: list[str]) -> list:
        vector = zeros()
        if not roots:
            return vector
        counts: dict[str, int] = {}
        for root in roots:
            counts[root] = counts.get(root, 0) + 1
        for root, count in counts.items():
            add_dense(vector, self.root_vector(root), self.idf(root) * (1 + math.log(count)))
        return normalize(vector)

    def centroid(self, weighted_roots: list[tuple[str, float]]) -> list:
        vector = zeros()
        for root, weight in weighted_roots:
            add_dense(vector, self.root_vector(root), weight)
        return normalize(vector)
