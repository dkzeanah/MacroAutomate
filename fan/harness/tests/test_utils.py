from sidelearner.utils import chunk_text, cosine, jaccard, json_loads_lenient, tokenize


def test_cosine_known_values():
    assert abs(cosine([1, 0, 0], [1, 0, 0]) - 1.0) < 1e-9
    assert abs(cosine([1, 0, 0], [0, 1, 0])) < 1e-9
    assert abs(cosine([1, 1], [1, 1]) - 1.0) < 1e-9
    assert cosine([], [1]) == 0.0


def test_chunk_text():
    text = "line one\n" * 100
    chunks = chunk_text(text, size=100, overlap=10)
    assert chunks
    assert all(len(c) <= 140 for c in chunks)


def test_tokenize_splits_camel_case():
    tokens = tokenize("SideLearner knowledgeGraph")
    assert "sidelearner" in tokens or "side" in tokens
    assert "learner" in tokens


def test_jaccard():
    assert jaccard(["a", "b"], ["b", "a"]) == 1.0
    assert jaccard(["a", "b"], ["c", "d"]) == 0.0
    assert 0.0 < jaccard(["a", "b", "c"], ["a", "b"]) < 1.0


def test_json_loads_lenient_fences_and_stray():
    assert json_loads_lenient('```json\n{"a": 1}\n```') == {"a": 1}
    assert json_loads_lenient('here is text {"b": [1, 2]} trailing') == {"b": [1, 2]}
    try:
        json_loads_lenient("no json at all")
        assert False, "should raise"
    except ValueError:
        pass
