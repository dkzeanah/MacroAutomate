from sidelearner.memory.graph import KnowledgeGraph
from sidelearner.memory.store import Store


def test_facts_add_query_merge(workspace, embedder):
    store = Store(workspace / "g.db")
    graph = KnowledgeGraph(store, embedder, merge_similarity=0.6)

    fid1, created = graph.add_fact("The client Acme Supply uses NET-30 payment terms", confidence=0.8, source_ids=[1])
    assert created and fid1 > 0

    # A near-duplicate fact merges into the first.
    fid2, created2 = graph.add_fact("Acme Supply uses NET-30 payment terms for invoices", confidence=0.7, source_ids=[2])
    assert not created2
    assert fid2 == fid1

    hits = graph.query("what are the payment terms of Acme Supply", k=5)
    assert hits, "expected retrieval hits"
    assert hits[0].kind == "fact"
    assert "net-30" in hits[0].text.lower()


def test_entities_reinforce(workspace, embedder):
    store = Store(workspace / "g.db")
    graph = KnowledgeGraph(store, embedder)
    eid = graph.add_entity("QuickBooks", kind="tool")
    graph.add_entity("QuickBooks", kind="tool")
    rows = store.entities_all()
    assert len(rows) == 1
    assert rows[0]["weight"] >= 2.0


def test_relations_and_export(workspace, embedder):
    store = Store(workspace / "g.db")
    graph = KnowledgeGraph(store, embedder)
    a = graph.add_entity("Acme Supply", "vendor")
    b = graph.add_entity("QuickBooks", "tool")
    graph.relate(a, "invoiced_in", b)
    path = graph.export(workspace / "twin.jsonl")
    lines = path.read_text(encoding="utf-8").strip().splitlines()
    kinds = [line.split('"t": "')[1].split('"')[0] for line in lines]
    assert "entity" in kinds and "relation" in kinds


def test_query_floor(workspace, embedder):
    store = Store(workspace / "g.db")
    graph = KnowledgeGraph(store, embedder, query_similarity=0.9)
    graph.add_fact("The sky is blue on clear days", source_ids=[1])
    hits = graph.query("invoice payment terms", k=5)
    assert hits == []
