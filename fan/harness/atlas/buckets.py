"""The twenty buckets, and the scored classifier that assigns a project to one.

Classification is evidence-based, never a bare guess: every result carries the signals
that fired, the score, and the runner-up, so a wrong call can be seen and overridden
rather than silently inherited.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

from .spec import SKIP_DIR_NAMES

# Signals are weighted by where they were found. A dependency in requirements.txt is
# far stronger evidence than the same word appearing once in a README.
W_DEPENDENCY = 5.0
W_FILENAME = 3.0
W_DIRNAME = 3.0
W_IMPORT = 2.5
W_PROJECT_NAME = 4.0
W_TEXT = 0.6


@dataclass(frozen=True)
class Bucket:
    key: str
    title: str
    blurb: str
    # Words that, seen anywhere, point at this bucket.
    terms: tuple[str, ...] = ()
    # Python/JS package names whose presence is strong evidence.
    deps: tuple[str, ...] = ()
    # File extensions characteristic of the bucket.
    suffixes: tuple[str, ...] = ()
    max_symbol_lines: int = 80


BUCKETS: tuple[Bucket, ...] = (
    Bucket(
        "agent", "Agent & LLM Harness",
        "LLM harnesses, agent loops, providers, MCP, tool routers",
        terms=("agent", "harness", "llm", "prompt", "ollama", "anthropic", "openai",
               "mcp", "chatgpt", "deepseek", "completion", "inference", "rag",
               "embedding", "tool call", "sidelearner", "claude"),
        deps=("openai", "anthropic", "ollama", "langchain", "llama-cpp-python",
              "transformers", "tiktoken", "mcp"),
    ),
    Bucket(
        "codetool", "Code Tooling",
        "code analysis, indexing, refactoring, project management",
        terms=("analyzer", "analyser", "ast", "refactor", "lint", "codebase",
               "parser", "symbol", "index", "codemap", "atlas", "consolidat",
               "code analyzer", "static analysis"),
        deps=("astroid", "libcst", "rope", "pylint", "ruff", "tree-sitter"),
    ),
    Bucket(
        "desktop-auto", "Desktop Automation",
        "AutoHotkey, window/explorer automation, hotkeys, macros",
        terms=("autohotkey", "ahk", "hotkey", "macro", "explorer", "window",
               "shortcut", "sendkeys", "keyboard", "clipboard", "tray"),
        deps=("pyautogui", "pywin32", "keyboard", "pynput", "pygetwindow"),
        suffixes=(".ahk",),
    ),
    Bucket(
        "web-auto", "Web Automation",
        "browser automation, scraping, extensions, selenium/playwright",
        terms=("selenium", "playwright", "scrape", "crawler", "chrome extension",
               "webdriver", "puppeteer", "manifest.json", "findtext", "bookmarklet"),
        deps=("selenium", "playwright", "beautifulsoup4", "bs4", "scrapy",
              "requests-html", "httpx"),
    ),
    Bucket(
        "sim3d", "3D & Simulation",
        "3D/graphics/geometry/CAD/ModernGL/dome and shell structures",
        terms=("dome", "geodesic", "moderngl", "opengl", "mesh", "vertex", "shader",
               "cad", "stl", "geometry", "render", "blender", "trajectory",
               "simulation", "3d", "polyhedron", "tessellat"),
        deps=("moderngl", "pyopengl", "trimesh", "numpy-stl", "pyglet", "vpython",
              "cadquery", "open3d", "pygame"),
        suffixes=(".stl", ".obj", ".glsl"),
    ),
    Bucket(
        "embedded", "Embedded & Firmware",
        "ESP32, Arduino, firmware, device probes, serial",
        terms=("esp32", "esp8266", "arduino", "firmware", "micropython", "gpio",
               "i2c", "spi", "uart", "serial", "sketch", "platformio", "stm32",
               "raspberry"),
        deps=("pyserial", "serial", "esptool", "adafruit"),
        suffixes=(".ino", ".hex"),
    ),
    Bucket(
        "vehicle", "Vehicle & Avionics",
        "automotive, CAN bus, OBD, hybrid systems, avionics",
        terms=("can bus", "canbus", "obd", "prius", "toyota", "hybrid", "ecu",
               "avionics", "vehicle", "automotive", "dbc", "j1939", "torque",
               "inverter", "battery pack"),
        deps=("python-can", "cantools", "obd", "pyobd"),
        suffixes=(".dbc",),
    ),
    Bucket(
        "datatool", "Data & Drive Tooling",
        "file/drive analyzers, dedupe, search indexes, organization",
        terms=("everything sdk", "drive analyzer", "dedupe", "duplicate", "organiz",
               "file index", "checksum", "hash", "inventory", "catalog", "sweep",
               "disk", "folder scan"),
        deps=("watchdog", "send2trash", "xxhash"),
    ),
    Bucket(
        "media", "Media Processing",
        "audio/video/image processing, recording, transcoding",
        terms=("ffmpeg", "audio", "video", "transcode", "waveform", "spectrogram",
               "record", "mixdown", "codec", "thumbnail", "subtitle", "caption",
               "whisper", "earbud", "microphone"),
        deps=("ffmpeg-python", "moviepy", "pydub", "sounddevice", "soundcard",
              "opencv-python", "opencv-python-headless", "pillow", "imageio",
              "faster-whisper", "mss"),
        suffixes=(".mp4", ".wav", ".mp3"),
    ),
    Bucket(
        "docgen", "Document Generation",
        "PDF, documents, printing, reports, publishing",
        terms=("pdf", "docx", "latex", "report", "invoice", "printing", "typeset",
               "markdown export", "ebook", "epub", "book", "flatten"),
        deps=("reportlab", "pypdf", "pypdf2", "fpdf", "python-docx", "weasyprint",
              "pdfplumber", "openpyxl"),
        suffixes=(".pdf", ".docx", ".tex"),
    ),
    Bucket(
        "career", "Career & Job Search",
        "resume/ATS, job search automation, applications",
        terms=("resume", "ats", "cover letter", "job", "applicant", "recruiter",
               "linkedin", "indeed", "interview", "cv", "hiring", "vacancy"),
    ),
    Bucket(
        "contentops", "Creator Operations",
        "creator operations, social publishing, marketing pipelines",
        terms=("creator", "content", "social", "publish", "youtube", "tiktok",
               "instagram", "engagement", "audience", "brief", "campaign",
               "editorial", "schedule post", "creator_ops"),
    ),
    Bucket(
        "osint", "OSINT & Research",
        "research, intelligence gathering, investigation workbenches",
        terms=("osint", "intelligence", "investigation", "recon", "footprint",
               "whois", "breach", "darkweb", "threat", "evergreen"),
        deps=("shodan", "censys", "theharvester"),
    ),
    Bucket(
        "game", "Games & Bots",
        "games, bots, simulations of play",
        terms=("game", "battle", "bot", "player", "sprite", "arena", "score",
               "level", "enemy", "roguelike", "chess", "baittlebots"),
        deps=("pygame", "arcade", "pyglet"),
    ),
    Bucket(
        "datasci", "Data Science",
        "ML, notebooks, statistics, data visualization",
        terms=("dataset", "model train", "regression", "classifier", "notebook",
               "matplotlib", "pandas", "statistic", "forecast", "cluster",
               "neural", "tensor"),
        deps=("pandas", "numpy", "scikit-learn", "sklearn", "matplotlib", "seaborn",
              "scipy", "torch", "tensorflow", "jupyter", "plotly"),
        suffixes=(".ipynb", ".csv"),
    ),
    Bucket(
        "webapp", "Web Applications",
        "servers, APIs, FastAPI/Flask/frontends",
        terms=("fastapi", "flask", "django", "endpoint", "rest api", "route",
               "server", "frontend", "react", "vue", "websocket", "http server",
               "uvicorn"),
        deps=("fastapi", "flask", "django", "uvicorn", "starlette", "aiohttp",
              "gunicorn", "jinja2"),
        suffixes=(".jsx", ".tsx", ".vue"),
    ),
    Bucket(
        "sysadmin", "System & Packaging",
        "installers, packaging, environment setup, portable apps, backups",
        terms=("installer", "setup", "bootstrap", "portable", "backup", "deploy",
               "packaging", "pyinstaller", "registry", "service", "scheduler",
               "batch", "powershell", "provision"),
        deps=("pyinstaller", "cx-freeze", "nuitka", "setuptools", "poetry"),
        suffixes=(".bat", ".ps1", ".msi"),
    ),
    Bucket(
        "electronics", "Electronics",
        "circuits, schematics, EDA, electrical study material",
        terms=("circuit", "schematic", "resistor", "capacitor", "voltage", "ohm",
               "breadboard", "kicad", "pcb", "multimeter", "keyestudio", "shield",
               "relay", "transistor"),
        suffixes=(".sch", ".kicad_pcb"),
    ),
    Bucket(
        "knowledge", "Knowledge & Study",
        "notes, study guides, learning material, reference",
        terms=("study guide", "notes", "flashcard", "curriculum", "lesson",
               "tutorial", "glossary", "reference", "cheatsheet", "quiz",
               "learning"),
    ),
    Bucket(
        "misc", "Unclassified",
        "unclassified - requires human review",
    ),
)

BY_KEY: dict[str, Bucket] = {b.key: b for b in BUCKETS}
MISC = BY_KEY["misc"]


@dataclass
class Verdict:
    """The outcome of classifying one project, with its evidence."""

    bucket: str
    score: float
    runner_up: str | None = None
    runner_up_score: float = 0.0
    signals: list[str] = field(default_factory=list)

    @property
    def confident(self) -> bool:
        """True when the winner clearly beat the field, not just edged it."""
        if self.score < 6.0:
            return False
        if self.runner_up_score <= 0:
            return True
        return self.score >= self.runner_up_score * 1.5

    def explain(self) -> str:
        head = f"{self.bucket} ({self.score:.1f})"
        if self.runner_up:
            head += f" over {self.runner_up} ({self.runner_up_score:.1f})"
        if not self.confident:
            head += " [low confidence]"
        if self.signals:
            head += " :: " + ", ".join(self.signals[:6])
        return head


# ------------------------------------------------------------------ evidence gather

_DEP_LINE = re.compile(r"^\s*([A-Za-z0-9._-]+)")


def _read_head(path: Path, limit: int = 20000) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="ignore")[:limit]
    except OSError:
        return ""


def gather_evidence(root: Path, max_files: int = 400) -> dict[str, object]:
    """Collect the raw material a classification is built from.

    Deliberately shallow and bounded: this runs over hundreds of desktop folders,
    so it reads names first and content only where content is cheap and telling.
    """
    names: list[str] = []
    dirs: list[str] = []
    suffixes: list[str] = []
    deps: set[str] = set()
    text_parts: list[str] = [root.name.replace("_", " ").replace("-", " ")]
    seen = 0

    for path in _walk(root, max_files):
        seen += 1
        rel = path.relative_to(root)
        names.append(path.name.lower())
        suffixes.append(path.suffix.lower())
        for part in rel.parts[:-1]:
            dirs.append(part.lower())

        low = path.name.lower()
        if low in {"requirements.txt", "requirements-core.txt", "requirements-full.txt",
                   "pyproject.toml", "setup.py", "package.json", "environment.yml"}:
            deps |= _parse_deps(path)
            text_parts.append(_read_head(path, 4000))
        elif low.endswith(".md") and len(text_parts) < 12:
            text_parts.append(_read_head(path, 6000))
        elif path.suffix.lower() in {".py", ".pyw"} and len(text_parts) < 30:
            text_parts.append(_read_head(path, 3000))

    return {
        "names": names,
        "dirs": dirs,
        "suffixes": suffixes,
        "deps": deps,
        "text": "\n".join(text_parts).lower(),
        "file_count": seen,
    }


def _walk(root: Path, max_files: int):
    """Yield up to ``max_files`` interesting files, skipping vendor/noise trees."""
    count = 0
    stack = [root]
    while stack and count < max_files:
        current = stack.pop()
        try:
            entries = list(current.iterdir())
        except OSError:
            continue
        for entry in entries:
            if count >= max_files:
                return
            try:
                if entry.is_dir():
                    if entry.name.lower() in SKIP_DIR_NAMES or entry.name.startswith("."):
                        continue
                    stack.append(entry)
                elif entry.is_file():
                    count += 1
                    yield entry
            except OSError:
                continue


def _parse_deps(path: Path) -> set[str]:
    text = _read_head(path, 8000)
    found: set[str] = set()
    if path.name == "package.json":
        for match in re.finditer(r'"([A-Za-z0-9@._/-]+)"\s*:\s*"[^"]*"', text):
            found.add(match.group(1).lower().lstrip("@").split("/")[0])
        return found
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        match = _DEP_LINE.match(line.strip('"\', '))
        if match:
            found.add(match.group(1).lower())
    return found


# ---------------------------------------------------------------------- classify

def classify(root: Path, evidence: dict[str, object] | None = None) -> Verdict:
    """Assign ``root`` to one of the twenty buckets, with evidence."""
    ev = evidence if evidence is not None else gather_evidence(root)
    names = ev["names"]           # type: ignore[index]
    dirs = ev["dirs"]             # type: ignore[index]
    suffixes = set(ev["suffixes"])  # type: ignore[arg-type]
    deps = ev["deps"]             # type: ignore[index]
    text = ev["text"]             # type: ignore[index]
    project_name = root.name.lower().replace("_", " ").replace("-", " ")

    name_blob = " ".join(names)
    dir_blob = " ".join(dirs)

    scores: dict[str, float] = {}
    evidence_by_bucket: dict[str, list[str]] = {}

    for bucket in BUCKETS:
        if bucket.key == "misc":
            continue
        score = 0.0
        signals: list[str] = []

        for dep in bucket.deps:
            if dep in deps:  # type: ignore[operator]
                score += W_DEPENDENCY
                signals.append(f"dep:{dep}")

        for suffix in bucket.suffixes:
            if suffix in suffixes:
                score += W_FILENAME
                signals.append(f"ext:{suffix}")

        for term in bucket.terms:
            hit = False
            if term in project_name:
                score += W_PROJECT_NAME
                signals.append(f"name:{term}")
                hit = True
            if term in name_blob:
                score += W_FILENAME
                if not hit:
                    signals.append(f"file:{term}")
                hit = True
            if term in dir_blob:
                score += W_DIRNAME
                if not hit:
                    signals.append(f"dir:{term}")
                hit = True
            if not hit and term in text:  # type: ignore[operator]
                occurrences = min(text.count(term), 5)  # type: ignore[union-attr]
                score += W_TEXT * occurrences
                signals.append(f"text:{term}")

        if score > 0:
            scores[bucket.key] = score
            evidence_by_bucket[bucket.key] = signals

    if not scores:
        return Verdict("misc", 0.0, signals=["no signals matched"])

    ranked = sorted(scores.items(), key=lambda kv: kv[1], reverse=True)
    top_key, top_score = ranked[0]
    runner_key, runner_score = (ranked[1] if len(ranked) > 1 else (None, 0.0))

    return Verdict(
        bucket=top_key,
        score=top_score,
        runner_up=runner_key,
        runner_up_score=runner_score,
        signals=evidence_by_bucket.get(top_key, []),
    )


def bucket_titles() -> list[tuple[str, str, str]]:
    """(key, title, blurb) for every bucket, in declaration order."""
    return [(b.key, b.title, b.blurb) for b in BUCKETS]
