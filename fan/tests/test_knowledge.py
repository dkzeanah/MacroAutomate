"""Knowledge base: roots, parsers, self-trained vectors, head discovery, inbox records, job CLI."""
import csv
import json
import os
import random
import subprocess
import sys
import tempfile
import unittest
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from fan.knowledge import embed, intake, model, parsers  # noqa: E402
from fan.knowledge.ingest import Knowledge  # noqa: E402
from fan.knowledge.text import RootNormalizer, complexity, idf_table, is_element, split_sentences, stem  # noqa: E402

TOPICS = {
    "domes": ["A geodesic dome is a spherical structure built from a network of triangles.",
              "Dome struts are cut to precise chord lengths before assembly.",
              "A 3V geodesic dome uses three strut lengths and many hubs.", "Hubs join the struts of a dome at each vertex.",
              "Visit www.geodesic-domes.com for GeodesicDome kit plans.", "Domes distribute load evenly across the whole frame.",
              "The dome frequency determines how many triangles the sphere has.", "Cover the dome frame with a waterproof membrane.",
              "Measure every strut twice before cutting the dome frame.", "Small domes make great greenhouses and garden shelters."],
    "code": ["Python is a programming language used for scripting and automation.", "A function groups code that runs when it is called.",
             "Write unit tests so the code keeps working after changes.", "Variables store values that the program uses later.",
             "Use version control with git to track every code change.", "A loop repeats code until a condition is false.",
             "The compiler translates source code into machine instructions.", "Debugging means finding and fixing errors in the program.",
             "Refactor long functions into smaller functions with clear names.", "An API lets one program call functions in another program."],
    "chemistry": ["An acid is a substance that donates hydrogen ions in water.", "Sodium chloride is the chemical compound we call table salt.",
                  "Mixing an acid with a base produces water and a salt.", "The pH scale measures how acidic a solution is.",
                  "Wear gloves when handling concentrated acids.", "A catalyst speeds up a chemical reaction without being consumed.",
                  "Molecules are atoms bonded together in fixed ratios.", "Oxidation reactions transfer electrons between atoms.",
                  "Store reactive chemicals away from heat sources.", "Titration measures the concentration of an acid solution."],
    "knitting": ["Knitting creates fabric by looping yarn with two needles.", "A knit stitch and a purl stitch are the two basic stitches.",
                 "Choose a yarn weight that matches the needle size.", "Cast on stitches before you begin the first row.",
                 "Wool yarn keeps a knitted scarf warm in winter.", "Count your stitches at the end of every row.",
                 "Blocking a finished sweater evens out the stitches.", "Circular needles knit hats without seams.",
                 "A knitting pattern lists the stitches row by row.", "Bind off the stitches to finish the knitted edge."],
}


def write_docx(path, paragraphs):
    body = "".join(f"<w:p><w:r><w:t>{p}</w:t></w:r></w:p>" for p in paragraphs)
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("word/document.xml", '<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/'
                   f'wordprocessingml/2006/main"><w:body>{body}</w:body></w:document>')


def build_corpus(folder: Path, seed=3):
    rng = random.Random(seed)
    for name, sentences in TOPICS.items():
        for index, kind in enumerate(["txt", "docx", "html"]):
            sample = rng.sample(sentences, 7)
            path = folder / f"{name}_{index}.{kind}"
            if kind == "txt":
                path.write_text(" ".join(sample), encoding="utf-8")
            elif kind == "docx":
                write_docx(path, sample)
            else:
                path.write_text("<html><body>" + "".join(f"<p>{s}</p>" for s in sample) + "</body></html>", encoding="utf-8")
    with open(folder / "supplies.csv", "w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["Item", "Use", "Price"])
        writer.writerow(["Dome hub connectors", "join dome struts at each vertex", "45.00"])
        writer.writerow(["Merino wool yarn", "knitting warm scarves and hats", "12.50"])


class TextTests(unittest.TestCase):
    def test_spellings_of_one_idea_share_roots(self):
        self.assertEqual({stem(w) for w in ["Dome", "domes", "doming", "domed"]}, {"dome"})
        self.assertEqual(stem("fixing"), "fix")
        self.assertEqual(stem("running"), "run")
        roots, _ = RootNormalizer({"geodesic": 5, "dome": 9}).text_roots(
            "Visit www.geodesic-domes.com or GeodesicDome tips; geodesicdome builders love domes.")
        self.assertEqual(roots.count("dome"), 4)
        self.assertEqual(roots.count("geodesic"), 3)

    def test_sentences_respect_abbreviations_and_bullets(self):
        units = split_sentences("Dr. Smith built a dome. It is 12 ft. wide, e.g. a small one!\n\n- Cut struts\n- Join hubs\n\nPage 3 of 9")
        self.assertEqual(units, ["Dr. Smith built a dome.", "It is 12 ft. wide, e.g. a small one!", "Cut struts", "Join hubs"])
        long = "word " * 200 + "end."
        self.assertTrue(all(len(u) <= 481 for u in split_sentences(long)))
        self.assertFalse(is_element("Click here", ["click"]))

    def test_complexity_levels_and_definitions(self):
        idf, top = idf_table({"dome": 5, "strut": 2, "polyhedron": 1}, 50)
        simple = complexity("A dome is a rounded structure.", ["dome", "round", "structure"], idf, top)
        hard = complexity("The icosahedral polyhedron subdivision frequency (3V) determines strut chord factors of 0.34862.",
                          ["icosahedral", "polyhedron", "subdivision", "frequency", "strut", "chord", "factor"], idf, top)
        self.assertTrue(simple[2])
        self.assertLess(simple[1], hard[1])


class ParserTests(unittest.TestCase):
    def test_office_and_text_formats(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            write_docx(folder / "a.docx", ["First paragraph about domes.", "Second paragraph."])
            with zipfile.ZipFile(folder / "b.xlsx", "w") as z:
                z.writestr("xl/sharedStrings.xml", '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
                           "<si><t>Item</t></si><si><t>Price</t></si><si><t>Dome kit</t></si></sst>")
                z.writestr("xl/workbook.xml", '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
                           'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
                           '<sheet name="Prices" r:id="rId1"/></sheets></workbook>')
                z.writestr("xl/_rels/workbook.xml.rels", '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                           '<Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>')
                z.writestr("xl/worksheets/sheet1.xml", '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
                           '<row><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>'
                           '<row><c r="A2" t="s"><v>2</v></c><c r="B2"><v>120.5</v></c></row></sheetData></worksheet>')
            with zipfile.ZipFile(folder / "c.pptx", "w") as z:
                z.writestr("ppt/slides/slide1.xml", '<p:sld xmlns:p="x" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
                           "<a:p><a:r><a:t>Slide title about yarn</a:t></a:r></a:p></p:sld>")
            (folder / "d.eml").write_text("From: a@b.com\nSubject: Dome order\nContent-Type: text/plain\n\nPlease ship the dome kit.", encoding="utf-8")
            (folder / "e.rtf").write_text(r"{\rtf1\ansi {\b Bold} dome text\par next line}", encoding="utf-8")
            (folder / "f.json").write_text(json.dumps({"notes": ["Domes need waterproof covers outdoors."], "price": 5}), encoding="utf-8")
            self.assertIn("First paragraph about domes.", parsers.extract(folder / "a.docx")["blocks"][0][1])
            self.assertEqual(parsers.extract(folder / "b.xlsx")["blocks"], [("Prices row 2", "Item: Dome kit; Price: 120.5.")])
            self.assertIn("Slide title about yarn", parsers.extract(folder / "c.pptx")["blocks"][0][1])
            email = dict(parsers.extract(folder / "d.eml")["blocks"])
            self.assertIn("Subject: Dome order", email["header"])
            self.assertIn("Please ship the dome kit.", email["body"])
            self.assertIn("dome text", parsers.extract(folder / "e.rtf")["blocks"][0][1])
            self.assertIn("waterproof covers", parsers.extract(folder / "f.json")["blocks"][0][1])
            with self.assertRaises(parsers.ParseError):
                parsers.extract(folder / "missing.pdf")

    def test_builtin_pdf_reader(self):
        stream = zlib.compress(b"BT /F1 12 Tf 72 720 Td (Geodesic domes are strong.) Tj T* [(Struts ) -250 (join hubs.)] TJ ET")
        pdf = (b"%PDF-1.4\n1 0 obj\n<< /Length " + str(len(stream)).encode() + b" /Filter /FlateDecode >>\nstream\n"
               + stream + b"\nendstream\nendobj\n%%EOF")
        pages = parsers.builtin_pdf_text(pdf)
        self.assertIn("Geodesic domes are strong.", pages[0][1])
        self.assertIn("Struts join hubs.", pages[0][1])


class KnowledgeBaseTests(unittest.TestCase):
    def run_corpus(self, prefer_extension):
        folder = Path(tempfile.mkdtemp(prefix="fan-kb-"))
        docs = folder / "docs"
        docs.mkdir()
        build_corpus(docs)
        kb = Knowledge(folder / "kb.sqlite", prefer_extension=prefer_extension)
        report = kb.ingest(folders=[str(docs)])
        return folder, docs, kb, report

    def test_discovers_the_real_subjects_with_both_vector_backends(self):
        outcomes = {}
        for prefer in (True, False):
            folder, docs, kb, report = self.run_corpus(prefer)
            try:
                self.assertEqual(report["failed"], [])
                self.assertTrue(report["rediscovered"])
                heads = model.head_list(kb.store)
                names = {h["name"].lower() for h in heads}
                self.assertEqual(len(heads), 4, names)
                self.assertTrue({"dome", "code"} <= names, names)
                dome = next(h for h in heads if h["name"] == "Dome")
                self.assertIn("domes", dome["aliases"])
                hits = kb.search("how do I join struts", 3)
                self.assertEqual(hits[0]["text"], "Hubs join the struts of a dome at each vertex.")
                outcomes[kb.store.backend] = [(h["id"], round(h["score"], 3)) for h in hits]
            finally:
                kb.close()
        self.assertEqual(set(outcomes), {"sqlite-vec", "python"} if self._has_vec() else {"python"})
        if len(outcomes) == 2:
            self.assertEqual(outcomes["sqlite-vec"], outcomes["python"])

    def _has_vec(self):
        try:
            import sqlite_vec  # noqa: F401
            return True
        except ImportError:
            return False

    def test_accrual_changes_renames_questions_and_pack(self):
        folder, docs, kb, report = self.run_corpus(True)
        try:
            # Repeated sentences across documents accrue instead of duplicating.
            repeated = kb.db.execute("SELECT MAX(count) FROM element").fetchone()[0]
            self.assertGreater(repeated, 1)
            self.assertEqual(kb.db.execute("SELECT COUNT(*) FROM element").fetchone()[0],
                             kb.db.execute("SELECT COUNT(DISTINCT hash) FROM element").fetchone()[0])
            again = kb.ingest(folders=[str(docs)])
            self.assertEqual((again["skipped"], len(again["ingested"])), (13, 0))
            # A changed file replaces its old contribution.
            (docs / "code_0.txt").write_text("Rust is a systems programming language focused on memory safety and speed.", encoding="utf-8")
            changed = kb.ingest(folders=[str(docs)])
            self.assertEqual(len(changed["ingested"]), 1)
            self.assertEqual(kb.search("memory safety rust", 1)[0]["text"],
                             "Rust is a systems programming language focused on memory safety and speed.")
            # A user's name survives rediscovery.
            dome = next(h for h in model.head_list(kb.store) if h["name"] == "Dome")
            kb.rename_head(dome["id"], "Geodesic domes")
            kb.rediscover()
            self.assertIn("Geodesic domes", {h["name"] for h in model.head_list(kb.store)})
            sequenced = model.head_detail(kb.store, dome["id"])
            self.assertEqual([e["seq"] for e in sequenced], list(range(1, len(sequenced) + 1)))
            answer = model.ask(kb, "what is an acid?")
            self.assertEqual(answer["heads"][0]["name"], next(h["name"] for h in model.head_list(kb.store) if "acid" in h["roots"]))
            self.assertTrue(any("acid" in e["text"].lower() for e in answer["answer"]))
            exported = model.export_pack(kb.store, folder / "export")
            self.assertEqual(exported["heads"], 4)
            pack = model.Pack(exported["pack"])
            self.assertEqual(pack.route("knit a wool hat with circular needles")[0]["id"],
                             next(h["id"] for h in model.head_list(kb.store) if "yarn" in h["roots"]))
            self.assertTrue((folder / "export" / "geodesic-domes.md").read_text(encoding="utf-8").startswith("# Geodesic domes"))
            source = kb.db.execute("SELECT id FROM source WHERE title='supplies.csv'").fetchone()[0]
            kb.forget_source(source)
            self.assertFalse(kb.search("merino wool connectors price", 5) and any("Merino" in e["text"] for e in kb.search("merino", 5)))
        finally:
            kb.close()

    def test_rebuilds_the_extension_index_after_fallback_writes(self):
        if not self._has_vec():
            self.skipTest("sqlite-vec is not installed")
        folder = Path(tempfile.mkdtemp(prefix="fan-kb-"))
        kb = Knowledge(folder / "kb.sqlite", prefer_extension=True)
        kb.ingest_text("Geodesic domes join struts at hubs. Hubs hold five or six struts each.", "Domes")
        kb.close()
        fallback = Knowledge(folder / "kb.sqlite", prefer_extension=False)
        fallback.ingest_text("Wool yarn makes warm hats and scarves for winter.", "Yarn")
        self.assertEqual(fallback.store.meta("vec_dirty"), "1")
        fallback.close()
        again = Knowledge(folder / "kb.sqlite", prefer_extension=True)
        try:
            self.assertEqual(again.store.meta("vec_dirty"), "0")
            self.assertEqual(again.db.execute("SELECT COUNT(*) FROM element_vec").fetchone()[0], again.store.element_count())
            self.assertEqual(again.search("warm winter hat", 1)[0]["text"], "Wool yarn makes warm hats and scarves for winter.")
        finally:
            again.close()


INVOICE = """Acme Dome Supply
123 Builder Way
Phone (555) 201-3344  billing@acmedome.com
INVOICE
Invoice Number: INV-1042
Invoice Date: 03/14/2026
Due Date: April 13, 2026
Bill To: Valley Garden Club
Subtotal $1,150.00
Sales Tax $90.00
Amount Due $1,240.00
Terms: Net 30
"""


class IntakeTests(unittest.TestCase):
    def test_invoice_fields(self):
        fields, how = intake.extract_fields(INVOICE, "inv.txt")
        self.assertEqual(fields["doc_type"], "invoice")
        self.assertEqual((fields["number"], fields["date"], fields["due_date"]), ("INV-1042", "2026-03-14", "2026-04-13"))
        self.assertEqual((fields["total"], fields["subtotal"], fields["tax"], fields["currency"]), (1240.0, 1150.0, 90.0, "USD"))
        self.assertEqual((fields["vendor"], fields["customer"], fields["terms"]), ("Acme Dome Supply", "Valley Garden Club", "NET 30"))
        self.assertEqual(fields["email"], "billing@acmedome.com")
        self.assertEqual(how["total"], "label")
        self.assertEqual(intake.classify("RECEIPT\nThank you for your purchase\nCashier 4\nPaid $12.00")[0], "receipt")
        self.assertEqual(intake.parse_date("15.04.2026"), "2026-04-15")
        self.assertEqual(intake.parse_date("Sept 3, 2026"), "2026-09-03")

    def test_scan_export_edit_and_variables(self):
        folder = Path(tempfile.mkdtemp(prefix="fan-inbox-"))
        inbox = folder / "inbox"
        inbox.mkdir()
        (inbox / "acme-invoice.txt").write_text(INVOICE, encoding="utf-8")
        kb = Knowledge(folder / "kb.sqlite")
        try:
            report = intake.scan(kb, [str(inbox)])
            self.assertEqual(len(report["records"]), 1)
            self.assertNotIn("text", report["ingested"][0])
            records = intake.records(kb)
            self.assertEqual(records[0]["fields"]["number"], "INV-1042")
            self.assertEqual(intake.scan(kb, [str(inbox)])["records"], [])
            intake.update_record(kb, records[0]["id"], fields={"po_number": "PO-77", "terms": ""})
            edited = intake.records(kb)[0]
            self.assertEqual(edited["fields"]["po_number"], "PO-77")
            self.assertNotIn("terms", edited["fields"])
            self.assertEqual(edited["field_sources"]["po_number"], "edited by you")
            exported = intake.export_csv(kb, folder / "exports")
            self.assertEqual(exported["records"], 1)
            self.assertEqual(intake.export_csv(kb, folder / "exports")["records"], 0)
            rows = list(csv.DictReader(open(folder / "exports" / "invoice.csv", encoding="utf-8-sig")))
            self.assertEqual((rows[0]["number"], rows[0]["total"]), ("INV-1042", "1240.0"))
            variables = intake.workflow_variables(intake.records(kb)[0])
            self.assertEqual((variables["total"], variables["vendor"], variables["document_title"]), ("1240.00", "Acme Dome Supply", "acme-invoice.txt"))
            self.assertEqual(kb.search("amount due invoice", 2)[0]["head_id"], kb.search("amount due invoice", 2)[0]["head_id"])
        finally:
            kb.close()


class CliTests(unittest.TestCase):
    def test_jobs_always_answer(self):
        folder = Path(tempfile.mkdtemp(prefix="fan-kbcli-"))
        docs = folder / "docs"
        docs.mkdir()
        build_corpus(docs)

        def job(request):
            request.setdefault("db", str(folder / "kb.sqlite"))
            path = folder / "request.json"
            path.write_text(json.dumps(request), encoding="utf-8")
            done = subprocess.run([sys.executable, "-m", "fan.knowledge.cli", str(path)], cwd=ROOT, capture_output=True, text=True, timeout=180)
            return done.returncode, json.loads((folder / "result.json").read_text(encoding="utf-8"))

        code, result = job({"mode": "kb_ingest", "folders": [str(docs)]})
        self.assertEqual(code, 0, result)
        self.assertEqual(len(result["heads"]), 4)
        code, result = job({"mode": "kb_ask", "question": "how are dome struts joined"})
        self.assertEqual((code, result["heads"][0]["name"]), (0, "Dome"))
        code, result = job({"mode": "kb_status"})
        self.assertEqual(result["stats"]["elements"] > 30, True)
        code, result = job({"mode": "nope"})
        self.assertEqual(code, 1)


if __name__ == "__main__":
    unittest.main()
