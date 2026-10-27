from sidelearner.autonomy import AutonomyEngine
from sidelearner.events import EventBus
from sidelearner.memory.twin import DigitalTwin
from sidelearner.memory.store import Store
from sidelearner.providers.registry import ProviderRegistry
from sidelearner.router.embeddings import TokenHashEmbedder


class FakeHarness:
    """Minimal harness surface used by AutonomyEngine."""

    def __init__(self, workspace, config):
        self.config = config
        self.bus = EventBus()
        self.registry = ProviderRegistry({})
        self.store = Store(config.get("memory.db"))
        self.twin = DigitalTwin(self.store, TokenHashEmbedder(), config, bus=self.bus)
        self.twin.ledger.gap_minutes = 0.0

        class FakeSupervisor:
            def screenshot_now(self):
                return None

        self.supervisor = FakeSupervisor()
        self.autonomy = AutonomyEngine(self)


def _harness(workspace, config):
    config.data["autonomy"] = {
        "enabled": True,
        "interval_s": 20.0,
        "prompt_mode": "ask",
        "screenshot_on_start": False,
        "vision_on_change": False,
        "pattern_threshold": 2,
        "auto_confidence": 2,
        "max_open_prompts": 3,
    }
    return FakeHarness(workspace, config)


def _focus(harness, app, n=2):
    for _ in range(n):
        # Same window title repeats (as in real life); occurrences still count.
        harness.twin.ingest("window", f"{app}: some window", {"app": app}, source="test")


def test_startup_pass_runs_without_providers(workspace, config):
    harness = _harness(workspace, config)
    report = harness.autonomy.startup_pass()
    assert report["screenshot"] is None
    assert report["compressed"] == "queued (background)"


def test_pattern_prompt_and_answer_flow(workspace, config):
    harness = _harness(workspace, config)
    _focus(harness, "chrome")
    prompted = harness.autonomy.assess_patterns()
    assert prompted == 1
    open_prompts = harness.store.decisions_open(kind="pattern")
    assert len(open_prompts) == 1
    assert open_prompts[0]["subject"] == "chrome"

    result = harness.autonomy.answer(open_prompts[0]["id"], "bookkeeping")
    assert result is not None
    assert result["domain"] == "bookkeeping"
    # A fact about the user's usage pattern was stored in the right domain.
    facts = harness.store.facts_active(domain="bookkeeping")
    assert any("chrome" in f["text"] for f in facts)
    # The pattern is now classified -> no more prompts for this app.
    assert harness.autonomy.assess_patterns() == 0


def test_domain_generalization_auto_answers_over_time(workspace, config):
    """Input requirements shrink: two confirmations, then auto-answers."""
    harness = _harness(workspace, config)
    # Step 1: first development app -> prompted -> user answers.
    _focus(harness, "code")
    harness.autonomy.assess_patterns()
    first = harness.store.decisions_open(kind="pattern")[0]
    harness.autonomy.answer(first["id"], "development")
    # Step 2: second development app -> still prompted (1 confirmation < 2).
    _focus(harness, "sublime")
    assert harness.autonomy.assess_patterns() == 1
    second = harness.store.decisions_open(kind="pattern")[0]
    harness.autonomy.answer(second["id"], "development")
    # Step 3: third app whose best-guess domain is development -> AUTO.
    _focus(harness, "python")
    assert harness.autonomy.assess_patterns() == 0  # no new prompt
    decisions = [r for r in harness.store.decisions_for("pattern", "python") if r["auto"]]
    assert decisions, "expected an auto-answered decision for python"
    assert decisions[0]["answer"] == "development"
    # And the knowledge landed in the right domain without any user input.
    facts = harness.store.facts_active(domain="development")
    assert any("python" in f["text"] for f in facts)


def test_prompt_mode_observe_never_prompts(workspace, config):
    harness = _harness(workspace, config)
    harness.autonomy.prompt_mode = "observe"
    _focus(harness, "chrome")
    assert harness.autonomy.assess_patterns() == 0


def test_max_open_prompts_cap(workspace, config):
    harness = _harness(workspace, config)
    for app in ("app1", "app2", "app3", "app4"):
        _focus(harness, app)
    assert harness.autonomy.assess_patterns() == 3  # capped by max_open_prompts


def test_no_duplicate_prompts_for_same_app(workspace, config):
    harness = _harness(workspace, config)
    _focus(harness, "chrome", n=4)
    assert harness.autonomy.assess_patterns() == 1
    # More occurrences of the same app: still no second prompt for it.
    _focus(harness, "chrome", n=3)
    assert harness.autonomy.assess_patterns() == 0
    open_rows = harness.store.decisions_open(kind="pattern")
    assert len(open_rows) == 1 and open_rows[0]["subject"] == "chrome"


def test_auto_answer_requires_classifiable_guess(workspace, config):
    harness = _harness(workspace, config)
    # Confirm "development" twice via direct decisions (as if answered earlier).
    for app in ("code", "sublime"):
        did = harness.store.add_decision("pattern", app, question="q")
        harness.store.resolve_decision(did, "development", auto=False)
    # An app with NO classifiable guess (generic name) still prompts.
    _focus(harness, "window")
    assert harness.autonomy.assess_patterns() == 1
