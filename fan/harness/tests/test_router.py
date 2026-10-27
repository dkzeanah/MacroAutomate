from sidelearner.providers.registry import ProviderRegistry
from sidelearner.router.embeddings import TokenHashEmbedder
from sidelearner.router.router import RouteContext, Router


def test_rule_intents(config, embedder):
    router = Router(registry=None, embedder=embedder, config=config)
    cases = {
        "fix the bug in the login function": "code_edit",
        "run pytest now": "shell",
        "pip install requests": "shell",
        "what is a knowledge graph": "research",
        "what is on my screen right now": "vision",
        "transcribe the meeting audio": "transcribe",
        "summarize this article": "summarize",
        "explain what this file does": "code_read",
    }
    for task, expected in cases.items():
        decision = router.route(task)
        assert decision.intent == expected, f"{task!r} -> {decision.intent}, expected {expected}"


def test_business_vocabulary_elevates_workflow(config, embedder):
    config.data["business"]["vocabulary"] = ["invoice", "reconcile"]
    router = Router(registry=None, embedder=embedder, config=config)
    decision = router.route("can you help reconcile the bank statement")
    assert decision.intent == "workflow"


def test_knn_fallback_intent(config, embedder):
    router = Router(registry=None, embedder=embedder, config=config)
    decision = router.route("create a script that renames files")
    assert decision.intent == "code_edit"


def test_local_only_when_no_providers(config, embedder):
    router = Router(registry=ProviderRegistry({}), embedder=embedder, config=config)
    decision = router.route("fix the login bug")
    assert decision.local_only is True
    assert decision.provider is None
    assert any("deterministic" in r for r in decision.reasons)


def test_route_context_flows(config, embedder):
    router = Router(registry=None, embedder=embedder, config=config)
    ctx = RouteContext(app="chrome", window_title="QuickBooks - Reconcile", business={"vocabulary": ["reconcile"]})
    decision = router.route("reconcile the client ledger", ctx=ctx)
    assert decision.intent == "workflow"


def test_skill_matching(config, embedder):
    class FakeSkill:
        name = "workspace_recon"
        keywords = ["recon", "inventory", "audit", "workspace"]

    router = Router(registry=None, embedder=embedder, config=config)
    assert router.match_skill("recon the workspace", [FakeSkill()]) == "workspace_recon"
    assert router.match_skill("sing a song", [FakeSkill()]) is None
