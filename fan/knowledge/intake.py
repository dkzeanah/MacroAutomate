"""Document inbox: watched folders -> knowledge base + structured office records.

Every new or changed file in a watched folder is ingested into the knowledge
base and also read as an office document: its type is recognised (invoice,
receipt, purchase order, statement, quote, contract, resume, letter, form) and
the usual fields are extracted. Records can be exported to CSV per type and
handed to a data-entry workflow as $var.<field> variables.

Extraction is local pattern matching. When ``use_ai`` is on, the document text
is also sent to the configured model to fill fields the patterns missed; AI
values are marked as such so a person can check them.
"""
from __future__ import annotations

import csv
import json
import re
from datetime import datetime
from pathlib import Path

from .ingest import Knowledge
from .store import now, safe_json

SCHEMA = """
CREATE TABLE IF NOT EXISTS intake_record (
    id INTEGER PRIMARY KEY, source_id INTEGER UNIQUE, path TEXT, title TEXT, doc_type TEXT, confidence REAL,
    fields TEXT, field_sources TEXT DEFAULT '{}', status TEXT DEFAULT 'new', folder TEXT, received TEXT, updated TEXT,
    note TEXT DEFAULT '');
"""

DOC_TYPES = {
    "invoice": ["invoice", "bill to", "amount due", "invoice number", "invoice #", "due date", "remit", "balance due", "net 30"],
    "receipt": ["receipt", "paid", "thank you for your purchase", "payment received", "change due", "cashier", "transaction"],
    "purchase_order": ["purchase order", "p.o.", "po number", "po #", "ship to", "vendor", "order date", "requisition"],
    "statement": ["statement", "account summary", "previous balance", "statement date", "ending balance", "beginning balance"],
    "quote": ["quote", "quotation", "estimate", "valid until", "proposal", "estimated"],
    "contract": ["agreement", "hereinafter", "party", "parties", "term of", "signature", "witness", "governing law"],
    "resume": ["experience", "education", "skills", "resume", "curriculum vitae", "references", "employment"],
    "letter": ["dear", "sincerely", "regards", "to whom it may concern"],
    "form": ["please print", "signature", "date of birth", "applicant", "check one", "office use only"],
}
MONEY = r"(?:[$€£]\s?)?-?\d{1,3}(?:[,\s]\d{3})*(?:\.\d{2})|(?:[$€£]\s?)\d+(?:\.\d{2})?"
DATE_PATTERNS = [
    (r"\b(\d{4})-(\d{1,2})-(\d{1,2})\b", "ymd"),
    (r"\b(\d{1,2})/(\d{1,2})/(\d{2,4})\b", "mdy"),
    (r"\b(\d{1,2})-(\d{1,2})-(\d{2,4})\b", "mdy"),
    (r"\b(\d{1,2})\.(\d{1,2})\.(\d{4})\b", "dmy"),
    (r"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})\b", "Mdy"),
    (r"\b(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?,?\s+(\d{4})\b", "dMy"),
]
MONTHS = {m: i for i, m in enumerate(["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"], 1)}
MONTHS["sept"] = 9
FIELD_ORDER = ["doc_type", "number", "date", "due_date", "vendor", "customer", "total", "subtotal", "tax", "currency",
               "terms", "email", "phone", "po_number", "title"]


def ensure_schema(knowledge: Knowledge) -> None:
    knowledge.db.executescript(SCHEMA)


def classify(text: str) -> tuple[str, float]:
    lowered = text.lower()
    scores = {}
    for kind, words in DOC_TYPES.items():
        score = sum(2 if w in lowered[:1500] else 1 for w in words if w in lowered)
        if kind in lowered[:300]:
            score += 3
        scores[kind] = score
    best = max(scores, key=scores.get)
    total = sum(scores.values())
    if scores[best] < 2:
        return "other", 0.2
    return best, round(min(0.98, scores[best] / max(1, total) + 0.15), 2)


def parse_date(text: str) -> str:
    for pattern, order in DATE_PATTERNS:
        match = re.search(pattern, text, re.I)
        if not match:
            continue
        a, b, c = match.groups()
        try:
            if order == "ymd":
                y, m, d = int(a), int(b), int(c)
            elif order == "mdy":
                m, d, y = int(a), int(b), int(c)
                if m > 12 and d <= 12:
                    m, d = d, m
            elif order == "dmy":
                d, m, y = int(a), int(b), int(c)
            elif order == "Mdy":
                m, d, y = MONTHS[a.lower()[:4] if a.lower().startswith("sept") else a.lower()[:3]], int(b), int(c)
            else:
                d, m, y = int(a), MONTHS[b.lower()[:4] if b.lower().startswith("sept") else b.lower()[:3]], int(c)
            if y < 100:
                y += 2000
            return datetime(y, m, d).strftime("%Y-%m-%d")
        except (ValueError, KeyError):
            continue
    return ""


def _amount(text: str) -> float | None:
    match = re.search(MONEY, text)
    if not match:
        return None
    value = re.sub(r"[^\d.\-]", "", match.group(0).replace(" ", ""))
    try:
        return round(float(value), 2)
    except ValueError:
        return None


def _labelled(lines: list[str], labels: str, getter, window: int = 1):
    """A value on the line with the label, or on the next line or two."""
    pattern = re.compile(labels, re.I)
    for index, line in enumerate(lines):
        match = pattern.search(line)
        if not match:
            continue
        value = getter(line[match.end():])
        if value not in (None, ""):
            return value
        for follow in lines[index + 1:index + 1 + window]:
            value = getter(follow)
            if value not in (None, ""):
                return value
    return None


def extract_fields(text: str, title: str = "") -> tuple[dict, dict]:
    """(fields, how each field was found)."""
    lines = [l.strip() for l in text.replace("\r", "").split("\n") if l.strip()]
    doc_type, confidence = classify(text)
    fields: dict = {"doc_type": doc_type, "title": title}
    how: dict = {"doc_type": f"keywords ({int(confidence * 100)}%)"}

    def ident(chunk):
        match = re.search(r"[:#\s]*([A-Z0-9][A-Z0-9\-/]{2,24})\b", chunk.strip(), re.I)
        if match and re.search(r"\d", match.group(1)):
            return match.group(1)
        return None

    number = _labelled(lines, r"\b(invoice|receipt|order|quote|quotation|estimate|statement|reference|ref|document)\s*(no\.?|number|num|#)", ident)
    if number:
        fields["number"], how["number"] = number, "label"
    po = _labelled(lines, r"\b(p\.?\s?o\.?|purchase order)\s*(no\.?|number|#)?", ident)
    if po:
        fields["po_number"], how["po_number"] = po, "label"
    due = _labelled(lines, r"\b(due date|payment due|due by|due on|pay by)\b", parse_date)
    if due:
        fields["due_date"], how["due_date"] = due, "label"
    issued = _labelled(lines, r"\b(invoice date|date of issue|issue date|order date|statement date|receipt date|date)\b(?!\s*of birth)", parse_date)
    if issued and issued != due:
        fields["date"], how["date"] = issued, "label"
    elif not issued:
        any_date = parse_date(text)
        if any_date and any_date != due:
            fields["date"], how["date"] = any_date, "first date in the document"

    total = _labelled(lines, r"\b(amount due|balance due|total due|grand total|total amount|amount payable|total)\b", _amount)
    if total is not None:
        fields["total"], how["total"] = total, "label"
    else:
        amounts = [a for a in (_amount(m.group(0)) for m in re.finditer(MONEY, text)) if a is not None]
        if amounts:
            fields["total"], how["total"] = max(amounts), "largest amount"
    subtotal = _labelled(lines, r"\bsub\s?-?total\b", _amount)
    if subtotal is not None:
        fields["subtotal"], how["subtotal"] = subtotal, "label"
    tax = _labelled(lines, r"\b(sales tax|tax|vat|gst|hst)\b", _amount)
    if tax is not None and tax != fields.get("total"):
        fields["tax"], how["tax"] = tax, "label"
    currency = "EUR" if "€" in text else "GBP" if "£" in text else "USD" if "$" in text or "usd" in text.lower() else ""
    if currency:
        fields["currency"] = currency
    terms = re.search(r"\b(net\s?\d{1,3}|due on receipt|cod|2/10 net 30)\b", text, re.I)
    if terms:
        fields["terms"], how["terms"] = terms.group(1).upper().replace("  ", " "), "pattern"

    emails = list(dict.fromkeys(re.findall(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+", text)))
    if emails:
        fields["email"] = emails[0]
    phone = re.search(r"(?:\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]\d{4}\b", text)
    if phone:
        fields["phone"] = phone.group(0)

    vendor = _labelled(lines, r"^\s*(from|vendor|supplier|seller|sold by|payable to|remit to)\s*:?", lambda c: c.strip(" :") or None)
    if vendor:
        fields["vendor"], how["vendor"] = vendor[:80], "label"
    else:
        for line in lines[:6]:
            if len(line) > 2 and not re.search(r"\d{3}|invoice|receipt|statement|quote|order|page|date", line, re.I) and len(line.split()) <= 7:
                fields["vendor"], how["vendor"] = line[:80], "letterhead (first line)"
                break
        if "vendor" not in fields and emails:
            fields["vendor"], how["vendor"] = emails[0].split("@")[1].split(".")[0].capitalize(), "email domain"
    customer = _labelled(lines, r"\b(bill to|billed to|sold to|customer|client|ship to)\b\s*:?", lambda c: c.strip(" :") or None, window=1)
    if customer:
        fields["customer"], how["customer"] = customer[:80], "label"
    return fields, how


def ai_fields(text: str, fields: dict, request: dict) -> tuple[dict, dict]:
    """Fill missing fields with the model (opt-in). Returns (added fields, how)."""
    from fan.autopilot.llm import ChatClient, resolve_key
    key, _ = resolve_key()
    if not key:
        return {}, {}
    client = ChatClient(request.get("endpoint") or "https://api.deepseek.com", request.get("model") or "deepseek-v4-pro",
                        key=key, budget_usd=request.get("budget_usd"))
    wanted = [f for f in FIELD_ORDER if f not in fields and f not in ("title",)]
    if not wanted:
        return {}, {}
    prompt = ("Extract these fields from the office document below. Reply with one JSON object using only these keys, "
              f"and null when a value is not present: {', '.join(wanted)}. Dates as YYYY-MM-DD, amounts as numbers.\n\n"
              "<<<\n" + text[:7000] + "\n>>>")
    completion = client.complete([{"role": "system", "content": "You read invoices, receipts and office forms. Never guess a value that is not in the text."},
                                  {"role": "user", "content": prompt}], max_tokens=500)
    from fan.autopilot.compiler import parse_json
    data = parse_json(completion.text)
    added = {k: v for k, v in data.items() if k in wanted and v not in (None, "", [])}
    return added, {k: "AI (check it)" for k in added}


def scan(knowledge: Knowledge, folders: list[str], *, use_ai: bool = False, request: dict | None = None,
         deadline: float | None = None) -> dict:
    """Ingest new files from the watched folders and create office records for them."""
    ensure_schema(knowledge)
    report = knowledge.ingest(folders=folders, recursive=True, origin="inbox", deadline=deadline, keep_text=True)
    created = []
    for item in report["ingested"]:
        text = item.pop("text", "") or ""
        if item.get("status") not in ("ok", "empty"):
            continue
        if not text.strip():
            text = _source_text(knowledge, item["source_id"], item["path"])
        if not text.strip():
            continue
        fields, how = extract_fields(text, item["title"])
        if use_ai:
            try:
                added, added_how = ai_fields(text, fields, request or {})
                fields.update(added)
                how.update(added_how)
            except Exception as error:  # never lose the record because the model failed
                how["ai_error"] = f"{type(error).__name__}: {error}"[:200]
        folder = str(Path(item["path"]).parent)
        stamp = now()
        knowledge.db.execute("INSERT INTO intake_record(source_id,path,title,doc_type,confidence,fields,field_sources,status,folder,received,updated) "
                             "VALUES(?,?,?,?,?,?,?,'new',?,?,?) ON CONFLICT(source_id) DO UPDATE SET path=excluded.path, title=excluded.title, "
                             "doc_type=excluded.doc_type, confidence=excluded.confidence, fields=excluded.fields, "
                             "field_sources=excluded.field_sources, status='new', updated=excluded.updated",
                             (item["source_id"], item["path"], item["title"], fields["doc_type"], classify(text)[1],
                              json.dumps(fields), json.dumps(how), folder, stamp, stamp))
        created.append({"title": item["title"], "doc_type": fields["doc_type"], "fields": fields})
    knowledge.db.commit()
    report["records"] = created
    return report


def _source_text(knowledge: Knowledge, source_id: int, path: str) -> str:
    """The document's text in order (re-read from the file so tables and layout survive)."""
    from . import parsers
    try:
        return "\n".join(text for _, text in parsers.extract(path)["blocks"])
    except Exception:
        rows = knowledge.db.execute("SELECT e.text FROM element e JOIN element_source es ON es.element_id=e.id "
                                    "WHERE es.source_id=? ORDER BY e.id", (source_id,)).fetchall()
        return "\n".join(r[0] for r in rows)


def records(knowledge: Knowledge, status: str = "", limit: int = 300) -> list[dict]:
    ensure_schema(knowledge)
    sql = "SELECT * FROM intake_record" + (" WHERE status=?" if status else "") + " ORDER BY received DESC, id DESC LIMIT ?"
    rows = knowledge.db.execute(sql, ((status, limit) if status else (limit,))).fetchall()
    out = []
    for row in rows:
        item = dict(row)
        item["fields"] = safe_json(row["fields"], {})
        item["field_sources"] = safe_json(row["field_sources"], {})
        out.append(item)
    return out


def update_record(knowledge: Knowledge, record_id: int, *, fields: dict | None = None, status: str | None = None, note: str | None = None) -> None:
    ensure_schema(knowledge)
    row = knowledge.db.execute("SELECT fields, field_sources FROM intake_record WHERE id=?", (record_id,)).fetchone()
    if not row:
        raise ValueError("Record not found")
    if fields is not None:
        current, how = safe_json(row["fields"], {}), safe_json(row["field_sources"], {})
        for key, value in fields.items():
            key = re.sub(r"[^A-Za-z0-9_]", "_", str(key))[:40]
            if value in (None, ""):
                current.pop(key, None)
            else:
                current[key] = value
                how[key] = "edited by you"
        knowledge.db.execute("UPDATE intake_record SET fields=?, field_sources=?, updated=? WHERE id=?",
                             (json.dumps(current), json.dumps(how), now(), record_id))
    if status:
        if status not in ("new", "exported", "entered", "ignored"):
            raise ValueError("Unknown status")
        knowledge.db.execute("UPDATE intake_record SET status=?, updated=? WHERE id=?", (status, now(), record_id))
    if note is not None:
        knowledge.db.execute("UPDATE intake_record SET note=? WHERE id=?", (note[:500], record_id))
    knowledge.db.commit()


def export_csv(knowledge: Knowledge, out_dir: str | Path, *, only_new: bool = True) -> dict:
    """One CSV per document type; exported records are marked so they are not exported twice."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    rows = records(knowledge, "new" if only_new else "", 100000)
    by_type: dict[str, list[dict]] = {}
    for row in rows:
        by_type.setdefault(row["doc_type"] or "other", []).append(row)
    files = []
    for doc_type, items in by_type.items():
        path = out_dir / f"{doc_type}.csv"
        keys = [k for k in FIELD_ORDER if any(k in r["fields"] for r in items)]
        keys += sorted({k for r in items for k in r["fields"]} - set(keys))
        existing_header = []
        if path.exists():
            with path.open(newline="", encoding="utf-8-sig") as handle:
                existing_header = next(csv.reader(handle), [])
        header = existing_header + [k for k in ["received", "file"] + keys if k not in existing_header] if existing_header else ["received", "file"] + keys
        rewrite = existing_header and header != existing_header
        if rewrite:  # widen an existing file to the new columns
            with path.open(newline="", encoding="utf-8-sig") as handle:
                old = list(csv.DictReader(handle))
            with path.open("w", newline="", encoding="utf-8-sig") as handle:
                writer = csv.DictWriter(handle, fieldnames=header)
                writer.writeheader()
                writer.writerows(old)
        with path.open("a" if path.exists() else "w", newline="", encoding="utf-8-sig") as handle:
            writer = csv.DictWriter(handle, fieldnames=header, extrasaction="ignore")
            if not existing_header:
                writer.writeheader()
            for item in items:
                writer.writerow({"received": item["received"], "file": item["path"], **{k: item["fields"].get(k, "") for k in keys}})
        files.append({"type": doc_type, "path": str(path), "records": len(items)})
        knowledge.db.executemany("UPDATE intake_record SET status='exported', updated=? WHERE id=? AND status='new'",
                                 [(now(), item["id"]) for item in items])
    knowledge.db.commit()
    return {"ok": True, "files": files, "records": sum(f["records"] for f in files)}


def workflow_variables(record: dict) -> dict:
    """Fields as workflow variables: $var.total, $var.vendor, $var.due_date ..."""
    out = {}
    for key, value in record["fields"].items():
        name = re.sub(r"[^A-Za-z0-9_]", "_", key)
        if name and not name[0].isdigit():
            out[name] = value if isinstance(value, str) else (f"{value:.2f}" if isinstance(value, float) else str(value))
    out["document_path"] = record["path"]
    out["document_title"] = record["title"]
    return out
