"""Tokens, word roots, sentences and complexity.

Roots unify the different spellings of one idea so they count together:
``Dome``, ``domes``, ``doming``, ``GeodesicDome``, ``geodesic-domes`` and
``www.domes.com`` all contribute to the roots ``dome`` (and ``geodesic``).
"""
from __future__ import annotations

import hashlib
import math
import re
from urllib.parse import urlparse

STOPWORDS = frozenset("""
a about above after again against all almost also although always am among an and another any anyone anything are
around as at away back be became because become been before being below between both but by can cannot could did
do does doing done down during each either else enough etc even ever every few for from further get gets getting
give given go goes going gone got had has have having he her here hers herself him himself his how however i if in
into is it its itself just keep know known last least less let like likely made make makes many may me might more
most much must my myself near need needs neither never new next no nor not now of off often on once one only onto
or other others otherwise our ours ourselves out over own per perhaps please put quite rather really said same say
says see seem seems several shall she should since so some something sometimes soon still such take than that the
their theirs them themselves then there therefore these they thing things this those though through thus to too
toward under until up upon us use used uses using very via was way we well were what whatever when where whether
which while who whole whom whose why will with within without would yet you your yours yourself yourselves
page pages figure fig table chapter section copyright reserved rights www http https com org net html pdf doc
one two three four five six seven eight nine ten first second third also however example examples e g ie eg
""".split())
DOMAIN_NOISE = {"www", "com", "org", "net", "gov", "edu", "io", "co", "uk", "us", "info", "biz", "html", "htm",
                "php", "aspx", "index", "home", "http", "https", "en", "amp"}
ABBREVIATIONS = {"mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc", "e.g", "i.e", "fig", "no", "inc",
                 "ltd", "co", "corp", "dept", "approx", "est", "min", "max", "u.s", "jan", "feb", "mar", "apr", "jun",
                 "jul", "aug", "sep", "sept", "oct", "nov", "dec", "vol", "pp", "ch", "sec"}

URL = re.compile(r"\b(?:https?://|www\.)[^\s<>\"')]+|\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:com|org|net|gov|edu|io|co|info)(?:/[^\s<>\"')]*)?", re.I)
EMAIL = re.compile(r"\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b")
WORD = re.compile(r"[A-Za-z][A-Za-z0-9'’]*(?:[-_][A-Za-z0-9]+)*|\d+(?:[.,:/]\d+)*%?")
CAMEL = re.compile(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])")
VOWEL = re.compile(r"[aeiouy]")


def stem(word: str) -> str:
    """A deliberately light English stemmer: plurals, -ing, -ed, -ly, -er.

    Conservative so unrelated words are not merged; display names come from the
    most frequent surface form, so roots never need to be readable themselves.
    """
    w = word.lower().replace("’", "'")
    if w.endswith("'s"):
        w = w[:-2]
    w = w.strip("'")
    if len(w) <= 3 or not w.isalpha():
        return w
    if w.endswith("ies") and len(w) > 4:
        w = w[:-3] + "y"
    elif w.endswith("sses"):
        w = w[:-2]
    elif w.endswith(("ches", "shes", "xes", "zes")):
        w = w[:-2]
    elif w.endswith("s") and not w.endswith(("ss", "us", "is", "ous")):
        w = w[:-1]
    for suffix, minimum in (("ingly", 4), ("edly", 4), ("ing", 3), ("ed", 3), ("ly", 4), ("ness", 4), ("ers", 4), ("er", 4)):
        if w.endswith(suffix) and len(w) - len(suffix) >= minimum and VOWEL.search(w[:-len(suffix)]):
            base = w[:-len(suffix)]
            if len(base) >= 4 and base[-1] == base[-2] and base[-1] not in "lsz":
                base = base[:-1]  # running -> run, planned -> plan
            elif suffix in ("ing", "ed") and len(base) == 3 and base[-1] not in "aeiouywx" and base[-2] in "aeiou" and base[0] not in "aeiou":
                base = base + "e"  # making -> make, domed -> dome (not fixing -> fixe, opening -> opene)
            w = base
            break
    return w


def url_words(url: str) -> list[str]:
    """``https://www.geodesic-domes.com/kits/StarterKit`` -> geodesic, domes, kits, Starter, Kit."""
    if not url.lower().startswith(("http://", "https://")):
        url = "http://" + url
    parsed = urlparse(url)
    labels = [p for p in (parsed.hostname or "").split(".") if p and p not in DOMAIN_NOISE]
    words = []
    for part in labels + re.split(r"[/_.\-?=&#+]+", parsed.path or ""):
        if part and part.lower() not in DOMAIN_NOISE and not part.isdigit():
            words.extend(split_compound(part))
    return words


def split_compound(token: str) -> list[str]:
    parts = []
    for chunk in re.split(r"[-_]+", token):
        parts.extend(p for p in CAMEL.split(chunk) if p)
    return parts or [token]


def surface_tokens(text: str) -> list[str]:
    """Words in reading order, with URLs and emails expanded into their words."""
    out: list[str] = []
    position = 0
    for match in URL.finditer(text):
        out.extend(_words(text[position:match.start()]))
        out.extend(url_words(match.group(0)))
        position = match.end()
    out.extend(_words(text[position:]))
    return out


def _words(text: str) -> list[str]:
    text = EMAIL.sub(lambda m: " " + m.group(0).split("@")[1].split(".")[0] + " ", text)
    words = []
    for token in WORD.findall(text):
        words.extend(split_compound(token) if any(c in token for c in "-_") or CAMEL.search(token) else [token])
    return words


class RootNormalizer:
    """Maps surface words to roots, splitting run-together compounds by known roots.

    ``known`` is the corpus lexicon (root -> frequency). ``geodesicdome`` is split
    into ``geodesic`` + ``dome`` when both are known roots and the whole word is not.
    """

    def __init__(self, known: dict[str, int] | None = None, min_known: int = 2):
        self.known = known or {}
        self.min_known = min_known
        self.cache: dict[str, list[str]] = {}

    def roots(self, word: str) -> list[str]:
        key = word.lower()
        if key in self.cache:
            return self.cache[key]
        if key.isdigit() or len(key) < 2:
            result = []
        else:
            base = stem(key)
            result = [base]
            if len(key) >= 8 and key.isalpha() and self.known.get(base, 0) < self.min_known:
                split = self._split(key)
                if split:
                    result = split
        result = [r for r in result if len(r) >= 3 and r not in STOPWORDS]
        if len(self.cache) < 200000:
            self.cache[key] = result
        return result

    def _split(self, word: str) -> list[str] | None:
        best, best_score = None, 0
        for cut in range(3, len(word) - 2):
            left, right = stem(word[:cut]), stem(word[cut:])
            score = min(self.known.get(left, 0), self.known.get(right, 0))
            if score >= self.min_known and score > best_score and left not in STOPWORDS and right not in STOPWORDS:
                best, best_score = [left, right], score
        return best

    def text_roots(self, text: str) -> tuple[list[str], list[str]]:
        """(roots in order, the surface word each root came from)."""
        roots, forms = [], []
        for word in surface_tokens(text):
            for root in self.roots(word):
                roots.append(root)
                forms.append(word.lower())
        return roots, forms


# ─── sentences ────────────────────────────────────────────────────────────────

SENTENCE_END = re.compile(r"(?<=[.!?…])[\"')\]]*\s+(?=[\"'(\[]?[A-Z0-9•\-*])")
BULLET = re.compile(r"^\s*(?:[-*•▪◦]|\d{1,3}[.)]|[a-z][.)])\s+")
BOILERPLATE = re.compile(r"(?i)^(page \d+( of \d+)?|all rights reserved|copyright ©?|confidential|printed on|\d+\s*/\s*\d+)$")


def split_sentences(text: str, max_chars: int = 480) -> list[str]:
    """Sentence-ish units: prose sentences, bullet items and short headings.

    Abbreviations (Dr., e.g., U.S.) do not end sentences; very long sentences are
    cut at ; : or , so each element stays one idea.
    """
    text = text.replace("\r\n", "\n").replace("\r", "\n").replace("­", "")
    text = re.sub(r"(\w)-\n(\w)", r"\1\2", text)  # re-join hyphenated line breaks
    units: list[str] = []
    for block in re.split(r"\n\s*\n", text):
        lines = [l.strip() for l in block.split("\n") if l.strip()]
        if not lines:
            continue
        merged: list[str] = []
        for line in lines:
            if BULLET.match(line) or not merged:
                merged.append(BULLET.sub("", line))
            elif merged[-1].endswith((".", "!", "?", ":")) and line[:1].isupper():
                merged.append(line)
            elif len(merged[-1]) < 60 and not merged[-1].endswith((",", ";")) and line[:1].isupper() and len(lines) > 1 and _looks_heading(merged[-1]):
                merged.append(line)
            else:
                merged[-1] = merged[-1] + " " + line
        for paragraph in merged:
            units.extend(_split_paragraph(paragraph, max_chars))
    return [u for u in (re.sub(r"\s+", " ", u).strip() for u in units) if u and not BOILERPLATE.match(u)]


def _looks_heading(line: str) -> bool:
    return not line.endswith(".") and len(line.split()) <= 8


def _split_paragraph(paragraph: str, max_chars: int) -> list[str]:
    pieces, start = [], 0
    for match in SENTENCE_END.finditer(paragraph):
        before = paragraph[start:match.start()].rstrip()
        last = re.search(r"([A-Za-z][A-Za-z.]*)[.]$", before)
        if last and (last.group(1).lower().rstrip(".") in ABBREVIATIONS or len(last.group(1)) == 1):
            continue
        pieces.append(paragraph[start:match.start()])
        start = match.end()
    pieces.append(paragraph[start:])
    out = []
    for piece in pieces:
        piece = piece.strip()
        while len(piece) > max_chars:
            cut = max(piece.rfind(sep, 0, max_chars) for sep in ("; ", ": ", ", "))
            cut = cut if cut > max_chars // 3 else max_chars
            out.append(piece[:cut + 1].strip())
            piece = piece[cut + 1:].strip()
        if piece:
            out.append(piece)
    return out


def is_element(sentence: str, roots: list[str]) -> bool:
    """Worth keeping as a knowledge element: enough words and at least two ideas."""
    words = sentence.split()
    if len(words) < 4 or len(set(roots)) < 2:
        return False
    letters = sum(c.isalpha() for c in sentence)
    return letters >= 0.45 * len(sentence)


def fingerprint(sentence: str) -> str:
    """Identity for de-duplication: case, spacing and punctuation insensitive."""
    norm = re.sub(r"[^a-z0-9]+", " ", sentence.lower()).strip()
    return hashlib.sha1(norm.encode("utf-8")).hexdigest()


# ─── complexity ───────────────────────────────────────────────────────────────

DEFINITION = re.compile(r"(?i)^(?:an?\s+|the\s+)?[\w\s\-]{2,40}?\b(?:is|are|was|were)\s+(?:an?|the|one|any|used|called|defined|known)\b"
                        r"|\brefers? to\b|\b(?:is|are) defined as\b|\bmeans\b|\bis (?:also )?(?:called|known as)\b")
TECHNICAL = re.compile(r"\d|[=+<>^%/\\{}\[\]()]|\b[A-Z][a-z]?\d\b|\b\w+_\w+\b|\b[a-z]+[A-Z]\w*\b|\b[A-Z]{2,}\b")


def syllables(word: str) -> int:
    word = word.lower()
    groups = re.findall(r"[aeiouy]+", word)
    count = len(groups) - (1 if word.endswith("e") and len(groups) > 1 and not word.endswith("le") else 0)
    return max(1, count)


def complexity(sentence: str, roots: list[str], idf: dict[str, float], max_idf: float) -> tuple[float, int, bool]:
    """(score 0..1, level 1..5, is_definition).

    Blends reading grade (Flesch-Kincaid), how rare the sentence's ideas are in
    the corpus, and technical density (numbers, formulas, code-like tokens).
    """
    words = re.findall(r"[A-Za-z]+", sentence)
    if not words:
        return 0.0, 1, False
    syllable_count = sum(syllables(w) for w in words)
    grade = 0.39 * len(words) + 11.8 * syllable_count / len(words) - 15.59  # one sentence
    grade_part = min(1.0, max(0.0, grade / 18))
    content = [idf.get(r, max_idf) for r in set(roots)]
    rarity = (sum(content) / len(content)) / max_idf if content and max_idf else 0.5
    tokens = sentence.split()
    technical = min(1.0, sum(1 for t in tokens if TECHNICAL.search(t)) / max(1, len(tokens)) * 2)
    definitional = bool(DEFINITION.search(sentence[:160]))
    score = 0.45 * grade_part + 0.35 * min(1.0, rarity) + 0.20 * technical - (0.08 if definitional else 0)
    score = min(1.0, max(0.0, score))
    level = 1 + min(4, int(score * 5))
    return round(score, 4), level, definitional


def idf_table(df: dict[str, int], total: int) -> tuple[dict[str, float], float]:
    total = max(1, total)
    table = {root: math.log((total + 1) / (count + 0.5)) for root, count in df.items()}
    return table, math.log(total + 1) + 0.7
