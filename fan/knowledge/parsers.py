"""Extract text from documents into located blocks.

Each parser returns ``[(locator, text), ...]`` where locator is a page, sheet/row
or paragraph reference used for citations. Office formats are read directly
from their XML (no Office or third-party library required). PDFs use pypdf when
installed, then a built-in reader for simple PDFs, then Windows OCR (scans).
"""
from __future__ import annotations

import csv
import email
import email.policy
import html
import io
import json
import os
import re
import shutil
import subprocess
import tempfile
import zipfile
import zlib
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[2]
OCR_SCRIPT = ROOT / "lib" / "WindowsOCR.ps1"
PDF_OCR_SCRIPT = Path(__file__).with_name("pdf_ocr.ps1")
TEXT_EXT = {".txt", ".md", ".markdown", ".log", ".ini", ".cfg", ".yaml", ".yml", ".ahk", ".py", ".js", ".ts", ".ps1",
            ".bat", ".sql", ".xml", ".srt", ".vtt", ".tex", ".rst"}
SUPPORTED = TEXT_EXT | {".pdf", ".docx", ".docm", ".dotx", ".xlsx", ".xlsm", ".pptx", ".odt", ".ods", ".odp", ".csv",
                        ".tsv", ".json", ".html", ".htm", ".eml", ".rtf", ".doc", ".xls", ".png", ".jpg", ".jpeg",
                        ".tif", ".tiff", ".bmp", ".gif"}
MAX_BYTES = 80 * 1024 * 1024
W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
S = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
A = "{http://schemas.openxmlformats.org/drawingml/2006/main}"


class ParseError(RuntimeError):
    pass


def supported(path: str | Path) -> bool:
    return Path(path).suffix.lower() in SUPPORTED


def extract(path: str | Path, *, ocr: bool = True, max_pages: int = 400) -> dict:
    """{"blocks": [(locator, text)], "kind": ..., "pages": n, "method": ..., "title": ...}."""
    path = Path(path)
    if not path.is_file():
        raise ParseError(f"File not found: {path}")
    if path.stat().st_size > MAX_BYTES:
        raise ParseError(f"File is larger than {MAX_BYTES // (1024 * 1024)} MB")
    ext = path.suffix.lower()
    if ext == ".pdf":
        return _pdf(path, ocr, max_pages)
    if ext in (".docx", ".docm", ".dotx"):
        return _result("docx", _docx(path), "office-xml")
    if ext in (".xlsx", ".xlsm"):
        return _result("xlsx", _xlsx(path), "office-xml")
    if ext == ".pptx":
        return _result("pptx", _pptx(path), "office-xml")
    if ext in (".odt", ".ods", ".odp"):
        return _result(ext[1:], _odf(path), "opendocument")
    if ext in (".csv", ".tsv"):
        return _result("csv", _csv(path), "csv")
    if ext == ".json":
        return _result("json", _json(path), "json")
    if ext in (".html", ".htm"):
        return _result("html", [("document", html_to_text(read_text(path)))], "html")
    if ext == ".eml":
        return _result("email", _eml(path), "email")
    if ext == ".rtf":
        return _result("rtf", [("document", rtf_to_text(read_text(path)))], "rtf")
    if ext in (".doc", ".xls"):
        return _legacy_office(path)
    if ext in (".png", ".jpg", ".jpeg", ".tif", ".tiff", ".bmp", ".gif"):
        if not ocr:
            raise ParseError("Images need OCR, which is turned off")
        return _result("image", [("image", ocr_image(path))], "windows-ocr")
    return _result("text", [("document", read_text(path))], "text")


def _result(kind, blocks, method, pages=0):
    blocks = [(str(loc), text) for loc, text in blocks if text and text.strip()]
    return {"kind": kind, "blocks": blocks, "pages": pages or len(blocks), "method": method}


def read_text(path: Path) -> str:
    raw = path.read_bytes()
    if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
        return raw.decode("utf-16", "replace")
    for encoding in ("utf-8-sig", "cp1252"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    return raw.decode("latin-1", "replace")


# ─── Office Open XML ───────────────────────────────────────────────────────────

def _zip_xml(archive: zipfile.ZipFile, name: str):
    try:
        return ElementTree.fromstring(archive.read(name))
    except KeyError:
        return None


def _docx(path: Path) -> list:
    blocks, buffer, part = [], [], 1
    with zipfile.ZipFile(path) as archive:
        names = ["word/document.xml"] + sorted(n for n in archive.namelist() if re.match(r"word/(header|footer|footnotes|endnotes)\d*\.xml", n))
        for name in names:
            root = _zip_xml(archive, name)
            if root is None:
                continue
            for paragraph in root.iter(W + "p"):
                pieces = []
                for node in paragraph.iter():
                    if node.tag == W + "t" and node.text:
                        pieces.append(node.text)
                    elif node.tag in (W + "tab",):
                        pieces.append("\t")
                    elif node.tag in (W + "br", W + "cr"):
                        pieces.append("\n")
                text = "".join(pieces).strip()
                if text:
                    buffer.append(text)
                if sum(len(t) for t in buffer) > 3000:
                    blocks.append((f"part {part}", "\n".join(buffer)))
                    buffer, part = [], part + 1
    if buffer:
        blocks.append((f"part {part}", "\n".join(buffer)))
    return blocks


def _col_index(ref: str) -> int:
    letters = re.match(r"[A-Z]+", ref or "")
    value = 0
    for char in letters.group(0) if letters else "":
        value = value * 26 + ord(char) - 64
    return max(0, value - 1)


def _xlsx(path: Path) -> list:
    blocks = []
    with zipfile.ZipFile(path) as archive:
        shared = []
        root = _zip_xml(archive, "xl/sharedStrings.xml")
        if root is not None:
            for item in root.iter(S + "si"):
                shared.append("".join(t.text or "" for t in item.iter(S + "t")))
        names = {}
        workbook = _zip_xml(archive, "xl/workbook.xml")
        rels = _zip_xml(archive, "xl/_rels/workbook.xml.rels")
        targets = {}
        if rels is not None:
            for rel in rels:
                targets[rel.get("Id")] = rel.get("Target", "")
        if workbook is not None:
            for sheet in workbook.iter(S + "sheet"):
                rid = sheet.get("{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id")
                target = targets.get(rid, "")
                target = target.lstrip("/")
                names["xl/" + target if not target.startswith("xl/") else target] = sheet.get("name", "Sheet")
        sheet_files = sorted(n for n in archive.namelist() if re.match(r"xl/worksheets/sheet\d+\.xml", n))
        for name in sheet_files:
            root = _zip_xml(archive, name)
            if root is None:
                continue
            title = names.get(name, Path(name).stem)
            rows = []
            for row in root.iter(S + "row"):
                cells = {}
                for cell in row.iter(S + "c"):
                    kind, value = cell.get("t", ""), None
                    v = cell.find(S + "v")
                    if kind == "s" and v is not None and v.text and v.text.isdigit() and int(v.text) < len(shared):
                        value = shared[int(v.text)]
                    elif kind == "inlineStr":
                        value = "".join(t.text or "" for t in cell.iter(S + "t"))
                    elif v is not None:
                        value = v.text
                    if value not in (None, ""):
                        cells[_col_index(cell.get("r", ""))] = str(value)
                if cells:
                    width = max(cells) + 1
                    rows.append([cells.get(i, "") for i in range(width)])
            blocks.extend(_table_blocks(title, rows))
    return blocks


def _table_blocks(title: str, rows: list[list[str]]) -> list:
    """Tables become one sentence per row, labelled with its header ("Item: Dome kit; Price: 120")."""
    if not rows:
        return []
    header = rows[0]
    has_header = len(rows) > 1 and all(h and not re.fullmatch(r"[\d.,$%-]+", h) for h in header if h) and sum(1 for h in header if h) >= 2
    out = []
    for index, row in enumerate(rows[1:] if has_header else rows, 2 if has_header else 1):
        if has_header:
            pairs = [f"{header[i].strip()}: {value.strip()}" for i, value in enumerate(row) if value.strip() and i < len(header) and header[i].strip()]
            text = "; ".join(pairs)
        else:
            text = " | ".join(v.strip() for v in row if v.strip())
        if text:
            out.append((f"{title} row {index}", text.rstrip(".") + "."))
    return out


def _pptx(path: Path) -> list:
    blocks = []
    with zipfile.ZipFile(path) as archive:
        slides = sorted((n for n in archive.namelist() if re.match(r"ppt/slides/slide\d+\.xml", n)),
                        key=lambda n: int(re.search(r"(\d+)", Path(n).stem).group(1)))
        for name in slides:
            root = _zip_xml(archive, name)
            if root is None:
                continue
            paragraphs = []
            for paragraph in root.iter(A + "p"):
                text = "".join(t.text or "" for t in paragraph.iter(A + "t")).strip()
                if text:
                    paragraphs.append(text)
            if paragraphs:
                blocks.append((f"slide {Path(name).stem[5:]}", "\n".join(paragraphs)))
    return blocks


def _odf(path: Path) -> list:
    with zipfile.ZipFile(path) as archive:
        root = _zip_xml(archive, "content.xml")
    if root is None:
        return []
    text_ns = "{urn:oasis:names:tc:opendocument:xmlns:text:1.0}"
    paragraphs = []
    for node in root.iter():
        if node.tag in (text_ns + "p", text_ns + "h"):
            text = "".join(node.itertext()).strip()
            if text:
                paragraphs.append(text)
    return [("document", "\n".join(paragraphs))]


def _csv(path: Path) -> list:
    text = read_text(path)
    try:
        dialect = csv.Sniffer().sniff(text[:4096], delimiters=",;\t|")
    except csv.Error:
        dialect = csv.excel_tab if path.suffix.lower() == ".tsv" else csv.excel
    rows = [row for row in csv.reader(io.StringIO(text), dialect) if any(c.strip() for c in row)]
    return _table_blocks(path.stem, rows[:20000])


def _json(path: Path) -> list:
    data = json.loads(read_text(path))
    lines = []

    def walk(value, trail):
        if len(lines) > 20000:
            return
        if isinstance(value, dict):
            for key, item in value.items():
                walk(item, trail + [str(key)])
        elif isinstance(value, list):
            for item in value:
                walk(item, trail)
        elif isinstance(value, str) and len(value.split()) >= 3:
            lines.append(value)
        elif value is not None and trail:
            lines.append(f"{' '.join(trail[-2:])}: {value}.")
    walk(data, [])
    return [("document", "\n\n".join(lines))]


def _eml(path: Path) -> list:
    message = email.message_from_bytes(path.read_bytes(), policy=email.policy.default)
    header = "\n".join(f"{k}: {message[k]}" for k in ("From", "To", "Date", "Subject") if message[k])
    body = message.get_body(preferencelist=("plain", "html"))
    content = ""
    if body is not None:
        content = body.get_content()
        if body.get_content_type() == "text/html":
            content = html_to_text(content)
    return [("header", header), ("body", content)]


def html_to_text(markup: str) -> str:
    markup = re.sub(r"(?is)<(script|style|noscript|svg|head)\b.*?</\1>", " ", markup)
    markup = re.sub(r"(?i)<br\s*/?>|</(p|div|li|h[1-6]|tr|section|article)>", "\n", markup)
    markup = re.sub(r"(?s)<[^>]+>", " ", markup)
    return re.sub(r"[ \t]+", " ", html.unescape(markup))


def rtf_to_text(rtf: str) -> str:
    rtf = re.sub(r"\\par[d]?\b", "\n", rtf)
    rtf = re.sub(r"\\'([0-9a-f]{2})", lambda m: bytes([int(m.group(1), 16)]).decode("cp1252", "replace"), rtf)
    rtf = re.sub(r"\\u(-?\d+)\??", lambda m: chr(int(m.group(1)) % 65536), rtf)
    rtf = re.sub(r"\{\\\*[^{}]*\}|\\[a-z]+-?\d* ?|[{}]", "", rtf)
    return rtf


def _legacy_office(path: Path) -> dict:
    """Binary .doc/.xls: Word/Excel through COM when installed, else text runs from the file."""
    try:
        import win32com.client  # type: ignore
        app_name = "Word.Application" if path.suffix.lower() == ".doc" else "Excel.Application"
        app = win32com.client.DispatchEx(app_name)
        app.Visible = False
        app.DisplayAlerts = False
        try:
            if app_name.startswith("Word"):
                document = app.Documents.Open(str(path.resolve()), ReadOnly=True, AddToRecentFiles=False)
                text = document.Content.Text
                document.Close(False)
                return _result("doc", [("document", text)], "word-com")
            book = app.Workbooks.Open(str(path.resolve()), ReadOnly=True)
            blocks = []
            for sheet in book.Worksheets:
                values = sheet.UsedRange.Value or ()
                rows = [[("" if v is None else str(v)) for v in (row if isinstance(row, tuple) else (row,))]
                        for row in (values if isinstance(values, tuple) else ((values,),))]
                blocks.extend(_table_blocks(sheet.Name, rows))
            book.Close(False)
            return _result("xls", blocks, "excel-com")
        finally:
            app.Quit()
    except Exception:
        pass
    raw = path.read_bytes()
    runs = re.findall(rb"(?:[\x20-\x7e]\x00){4,}", raw)
    text = "\n".join(r.decode("utf-16-le", "ignore") for r in runs)
    if len(text) < 200:
        text = "\n".join(r.decode("cp1252", "ignore") for r in re.findall(rb"[\x20-\x7e\r\n\t]{6,}", raw))
    return _result(path.suffix[1:].lower(), [("document", text)], "binary-text")


# ─── PDF ───────────────────────────────────────────────────────────────────────

def _pdf(path: Path, ocr: bool, max_pages: int) -> dict:
    pages, method = [], ""
    try:
        import pypdf  # type: ignore
        reader = pypdf.PdfReader(str(path))
        if reader.is_encrypted:
            try:
                reader.decrypt("")
            except Exception:
                raise ParseError("The PDF is password protected")
        for index, page in enumerate(reader.pages[:max_pages], 1):
            try:
                pages.append((f"page {index}", page.extract_text() or ""))
            except Exception:
                pages.append((f"page {index}", ""))
        method = "pypdf"
    except ImportError:
        pages, method = builtin_pdf_text(path.read_bytes()), "builtin-pdf"
    text_chars = sum(len(t.strip()) for _, t in pages)
    if (not pages or text_chars < 40 * max(1, len(pages))) and ocr:
        try:
            scanned = ocr_pdf(path, max_pages)
            if sum(len(t.strip()) for _, t in scanned) > text_chars:
                pages, method = scanned, "windows-ocr"
        except ParseError:
            if not text_chars:
                raise
    return _result("pdf", pages, method, pages=len(pages))


def builtin_pdf_text(data: bytes) -> list:
    """Text from simple, unencrypted PDFs: Flate streams and Tj/TJ string operators.

    A fallback only; it does not interpret font encodings, so pypdf or OCR is
    preferred when available.
    """
    texts = []
    for match in re.finditer(rb"<<(.*?)>>\s*stream\r?\n(.*?)\r?\nendstream", data, re.S):
        header, body = match.group(1), match.group(2)
        if b"/FlateDecode" in header:
            try:
                body = zlib.decompress(body)
            except zlib.error:
                continue
        elif b"/Filter" in header:
            continue
        if b"BT" not in body:
            continue
        pieces = []
        for chunk in re.findall(rb"BT(.*?)ET", body, re.S):
            for literal in re.findall(rb"\((?:\\.|[^\\)])*\)\s*Tj|\[(?:.*?)\]\s*TJ|T\*|Td|TD", chunk, re.S):
                if literal in (b"T*",) or literal.endswith((b"Td", b"TD")):
                    pieces.append("\n")
                    continue
                for string in re.findall(rb"\(((?:\\.|[^\\)])*)\)", literal):
                    pieces.append(_pdf_string(string))
        if pieces:
            texts.append("".join(pieces))
    return [(f"page {i}", t) for i, t in enumerate(texts, 1)]


def _pdf_string(raw: bytes) -> str:
    out = bytearray()
    i = 0
    escapes = {b"n": b"\n", b"r": b"\r", b"t": b"\t", b"b": b"\b", b"f": b"\f", b"(": b"(", b")": b")", b"\\": b"\\"}
    while i < len(raw):
        char = raw[i:i + 1]
        if char == b"\\" and i + 1 < len(raw):
            nxt = raw[i + 1:i + 2]
            octal = re.match(rb"[0-7]{1,3}", raw[i + 1:i + 4])
            if octal:
                out.append(int(octal.group(0), 8) & 0xFF)
                i += 1 + len(octal.group(0))
                continue
            out += escapes.get(nxt, nxt)
            i += 2
            continue
        out += char
        i += 1
    return out.decode("cp1252", "replace")


# ─── OCR (Windows.Media.Ocr through PowerShell) ────────────────────────────────

def _powershell() -> str:
    return shutil.which("powershell.exe") or shutil.which("pwsh.exe") or "powershell.exe"


def ocr_image(path: Path, timeout: int = 120) -> str:
    if os.name != "nt" or not OCR_SCRIPT.is_file():
        raise ParseError("Windows OCR is not available")
    with tempfile.TemporaryDirectory(prefix="fan-ocr-") as folder:
        out = Path(folder) / "ocr.txt"
        done = subprocess.run([_powershell(), "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(OCR_SCRIPT),
                               "-X", "0", "-Y", "0", "-Width", "1", "-Height", "1", "-OutputPath", str(out),
                               "-InputPath", str(path), "-Scale", "1.5"],
                              capture_output=True, text=True, timeout=timeout, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        if not out.is_file():
            raise ParseError("OCR failed: " + (done.stderr or done.stdout)[-300:].strip())
        return _decode_ocr(out.read_text(encoding="utf-8-sig", errors="replace"))


def _decode_ocr(output: str) -> str:
    import base64
    for line in output.splitlines():
        if line.startswith("TEXT\t"):
            return base64.b64decode(line[5:]).decode("utf-8", "replace")
    return ""


def ocr_pdf(path: Path, max_pages: int = 60, timeout: int = 900) -> list:
    if os.name != "nt" or not PDF_OCR_SCRIPT.is_file():
        raise ParseError("Windows PDF OCR is not available")
    with tempfile.TemporaryDirectory(prefix="fan-pdfocr-") as folder:
        out = Path(folder) / "pages.txt"
        done = subprocess.run([_powershell(), "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(PDF_OCR_SCRIPT),
                               "-InputPath", str(path.resolve()), "-OutputPath", str(out), "-MaxPages", str(max_pages)],
                              capture_output=True, text=True, timeout=timeout, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        if not out.is_file():
            raise ParseError("PDF OCR failed: " + (done.stderr or done.stdout)[-300:].strip())
        import base64
        pages = []
        for line in out.read_text(encoding="utf-8-sig", errors="replace").splitlines():
            parts = line.split("\t")
            if len(parts) == 2 and parts[0].isdigit():
                pages.append((f"page {parts[0]}", base64.b64decode(parts[1]).decode("utf-8", "replace")))
        return pages
