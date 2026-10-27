import sqlite3

from sidelearner.memory.classify import DEFAULT_TAXONOMY, DomainClassifier
from sidelearner.memory.graph import KnowledgeGraph
from sidelearner.memory.store import Store


def test_classifier_known_domains():
    classifier = DomainClassifier()
    domain, confidence = classifier.classify("Invoice INV-42 from Acme Supply, post to ledger")
    assert domain == "bookkeeping"
    assert confidence > 0
    domain, _ = classifier.classify("git push origin main then run the tests")
    assert domain in ("development", "procedures")
    domain, confidence = classifier.classify("the cat sat on the mat")
    assert domain == "general" and confidence == 0.0


def test_classifier_custom_taxonomy():
    taxonomy = [{"name": "farming", "keywords": ["crop", "harvest", "tractor", "field"]}]
    classifier = DomainClassifier(taxonomy)
    assert classifier.classify("harvest the crop before Friday")[0] == "farming"
    assert classifier.classify("deploy the website")[0] == "general"


def test_fact_domain_storage_and_status(workspace, embedder):
    store = Store(workspace / "d.db")
    graph = KnowledgeGraph(store, embedder)
    graph.add_fact("Invoice INV-42 from Acme Supply totals $1,200", domain="bookkeeping", source_ids=[1])
    graph.add_fact("git push origin main runs the deploy", domain="development", source_ids=[2])
    status = graph.status()
    assert status["domains"]["bookkeeping"] == 1
    assert status["domains"]["development"] == 1
    hits = graph.query("invoice", k=5, domain="bookkeeping")
    assert hits and hits[0].kind == "fact"
    hits = graph.query("invoice", k=5, domain="development")
    assert hits == []


def test_entity_domain_upgrades_from_general(workspace, embedder):
    store = Store(workspace / "d.db")
    graph = KnowledgeGraph(store, embedder)
    eid = graph.add_entity("QuickBooks", kind="app")  # general first
    graph.add_entity("QuickBooks", kind="app", domain="bookkeeping")
    row = store.entity_by_name("QuickBooks")
    assert row["domain"] == "bookkeeping"


def test_schema_migration_adds_domain_column(workspace):
    """An existing v0.1 database (no domain columns) migrates in place."""
    db = workspace / "old.db"
    conn = sqlite3.connect(str(db))
    conn.execute(
        "CREATE TABLE facts (id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT NOT NULL, "
        "summary TEXT NOT NULL DEFAULT '', embedding BLOB, confidence REAL NOT NULL DEFAULT 0.5, "
        "weight REAL NOT NULL DEFAULT 1.0, source_ids TEXT NOT NULL DEFAULT '[]', "
        "created TEXT NOT NULL, last_seen TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'active')"
    )
    conn.execute(
        "CREATE TABLE entities (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, "
        "kind TEXT NOT NULL DEFAULT 'concept', embedding BLOB, weight REAL NOT NULL DEFAULT 1.0, "
        "first_seen TEXT NOT NULL, last_seen TEXT NOT NULL, sources TEXT NOT NULL DEFAULT '[]', "
        "UNIQUE(name, kind))"
    )
    conn.commit()
    conn.close()
    store = Store(db)  # must migrate without error
    with store.conn() as conn:
        cols = {row["name"] for row in conn.execute("PRAGMA table_info(facts)")}
    assert "domain" in cols
    store.add_fact("hello world fact", "", None, 0.5, [1], domain="bookkeeping")
    assert store.facts_active()[0]["domain"] == "bookkeeping"


def test_compressor_classifies_domains(workspace, embedder, config):
    from sidelearner.memory.compressor import Compressor
    from sidelearner.memory.ledger import Ledger

    store = Store(workspace / "m.db")
    graph = KnowledgeGraph(store, embedder)
    ledger = Ledger(store, gap_minutes=0.0)
    compressor = Compressor(graph, ledger, classifier=DomainClassifier())
    ledger.record(
        "screen",
        "perception",
        "Invoice INV-99 from Acme Supply totals $500 due Friday. Reconcile the ledger afterward.",
    )
    compressor.run()
    domains = {row["domain"] for row in store.facts_active()}
    assert "bookkeeping" in domains
