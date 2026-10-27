from sidelearner.memory.compressor import Compressor, _heuristic_facts
from sidelearner.memory.graph import KnowledgeGraph
from sidelearner.memory.ledger import Ledger
from sidelearner.memory.store import Store


def test_heuristic_fact_extraction():
    text = (
        "Remember: the staging environment runs on port 8443. "
        "Client Acme Supply renewed their contract until December. "
        "the cat sat on the mat all afternoon long"
    )
    facts = _heuristic_facts(text)
    assert facts
    texts = " ".join(f["text"] for f in facts).lower()
    assert "staging" in texts or "acme" in texts


def test_heuristic_facts_empty_for_junk():
    assert _heuristic_facts("the quick brown fox jumps over the lazy dog and nothing else happens") == []


def test_ledger_lifecycle_and_compressor(workspace, embedder):
    store = Store(workspace / "m.db")
    graph = KnowledgeGraph(store, embedder)
    ledger = Ledger(store, gap_minutes=0.0)
    compressor = Compressor(graph, ledger)

    informative = ledger.record(
        "screen", "perception", "Invoice INV-42 from Acme Supply Co totals $1,200 due Friday. Configure the printer."
    )
    junk = ledger.record("screen", "perception", "the quick brown fox jumps over the lazy dog and nothing else happens")
    assert informative is not None and junk is not None
    assert len(ledger.unlearned()) == 2

    result = compressor.run()
    assert result["processed"] == 2
    assert result["facts_added"] >= 1
    assert result["gaps"] == 1  # the junk observation became a learning gap
    assert ledger.stats()["learned"] == 1
    open_gaps = store.gaps_open()
    assert len(open_gaps) == 1
    assert "no extractable" in open_gaps[0]["reason"]


def test_ledger_dedupes_identical(workspace, embedder):
    store = Store(workspace / "m.db")
    ledger = Ledger(store, gap_minutes=5)
    first = ledger.record("window", "perception", "chrome: Docs — meeting notes")
    second = ledger.record("window", "perception", "chrome: Docs — meeting notes")
    assert first is not None
    assert second is None  # identical item not re-ledgered
    assert ledger.stats()["total"] == 1


def test_twin_ingest_and_ask(workspace, embedder, config):
    from sidelearner.memory.twin import DigitalTwin

    store = Store(workspace / "m.db")
    config.data["memory"]["gap_minutes"] = 0.0
    twin = DigitalTwin(store, embedder, config)
    twin.ingest("screen", "Deploy procedure: git push origin main then ssh prod systemctl restart app")
    twin.compressor.run()
    result = twin.ask("how do we deploy", k=3)
    assert result["hits"], "expected the deploy fact to be retrievable"
    status = twin.status()
    assert status["graph"]["facts"] >= 1
    twin.shutdown()
