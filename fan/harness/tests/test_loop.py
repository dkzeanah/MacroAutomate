import json
from pathlib import Path

from sidelearner.memory.store import Store
from sidelearner.providers.base import Completion, Provider
from sidelearner.providers.registry import ProviderRegistry
from sidelearner.reason.loop import AgentLoop
from sidelearner.reason.planner import heuristic_plan
from sidelearner.reason.schema import parse_agent_message
from sidelearner.router.embeddings import TokenHashEmbedder
from sidelearner.router.router import Router
from sidelearner.skills.engine import SkillEngine
from sidelearner.tools import build_registry


class FakeProvider(Provider):
    """Scripted provider that replays canned assistant messages."""

    kind = "fake"

    def __init__(self, script: list[str], name="fake", model="fake-1"):
        super().__init__()
        self.script = list(script)
        self.name = name
        self.model = model
        self.tier = "local"
        self.capabilities = {"text"}
        self.calls = 0

    def chat(self, messages, stream=False, on_token=None, temperature=None, max_tokens=None, **kwargs):
        self.calls += 1
        text = self.script.pop(0) if self.script else '{"thought":"done","tool":null,"tool_args":null,"answer":"script exhausted"}'
        if stream and on_token:
            on_token(text)
        return Completion(text=text, model=self.model)

    def _probe(self):
        return True


def test_parse_agent_message_variants():
    parsed = parse_agent_message('{"thought":"t","tool":"fs.stat","tool_args":{"path":"a"},"answer":null}')
    assert parsed["tool"] == "fs.stat"
    parsed = parse_agent_message("```json\n{\"thought\":\"t\",\"tool\":null,\"tool_args\":null,\"answer\":\"hi\"}\n```")
    assert parsed["answer"] == "hi"
    parsed = parse_agent_message("plain text answer without json")
    assert parsed["tool"] is None and parsed["answer"].startswith("plain text")


def test_heuristic_plans():
    plan = heuristic_plan("run the tests")
    assert plan is not None and plan.steps[0].tool == "shell.run"
    plan = heuristic_plan("list files")
    assert plan is not None and plan.steps[0].tool == "fs.list_dir"
    plan = heuristic_plan("write a new file report.md with: # hello world")
    assert plan is not None
    assert plan.steps[0].tool == "fs.write_text"
    assert plan.steps[0].args["path"] == "report.md"
    assert "# hello" in plan.steps[0].args["content"]
    assert heuristic_plan("please write me a poem about the ocean") is None


def _build_loop(workspace, config, script):
    (workspace / "note.txt").write_text("hello from the note", encoding="utf-8")
    registry = ProviderRegistry({})
    fake = FakeProvider(script)
    registry.providers["fake"] = fake
    registry._order.append("fake")
    router = Router(registry=registry, embedder=TokenHashEmbedder(), config=config)
    tools, _, _ = build_registry(config)
    store = Store(config.get("memory.db"))
    sessions_dir = workspace / "vault" / "sessions"
    loop = AgentLoop(config, registry, router, tools, sessions_dir, store=store)
    return loop, fake


def test_loop_executes_tool_calls(workspace, config):
    script = [
        json.dumps({"thought": "read the note", "tool": "fs.read_text", "tool_args": {"path": "note.txt"}, "answer": None}),
        json.dumps({"thought": "got it", "tool": None, "tool_args": None, "answer": "The note says hello from the note"}),
    ]
    loop, fake = _build_loop(workspace, config, script)
    result = loop.run("read the note")
    assert result.ok
    assert fake.calls == 2
    assert len(result.steps) == 1
    assert result.steps[0]["tool"] == "fs.read_text"
    assert "hello from the note" in result.answer
    # Session log exists and is replayable.
    assert result.session_id
    log_path = workspace / "vault" / "sessions" / f"{result.session_id}.jsonl"
    assert log_path.exists()


def test_loop_denies_and_adapts(workspace, config):
    script = [
        json.dumps({"thought": "try delete", "tool": "fs.delete", "tool_args": {"path": "note.txt"}, "answer": None}),
        json.dumps({"thought": "denied; adapt", "tool": None, "tool_args": None, "answer": "Deletion was denied by policy, so the file remains."}),
    ]
    loop, _ = _build_loop(workspace, config, script)
    result = loop.run("delete the note")
    assert result.ok
    assert result.steps[0]["denied"] is True
    assert (workspace / "note.txt").exists()


def test_loop_verification_notes_missing_writes(workspace, config):
    script = [
        json.dumps({"thought": "write file", "tool": "fs.write_text", "tool_args": {"path": "out.txt", "content": "x"}, "answer": None}),
        json.dumps({"thought": "done", "tool": None, "tool_args": None, "answer": "wrote out.txt and also wrote ghost.txt"}),
    ]
    loop, _ = _build_loop(workspace, config, script)
    result = loop.run("write a file")
    assert result.ok
    assert any("out.txt" in v and "exists" in v for v in result.verification)
    # Claim about a file the loop never wrote is flagged as MISSING.
    assert any("ghost.txt" in v and "MISSING" in v for v in result.verification)
    # Mere mentions without a write verb are not flagged.
    assert not any("note.txt" in v and "MISSING" in v for v in result.verification)


def test_deterministic_skill_run(workspace, config):
    examples = Path(__file__).resolve().parents[1] / "sidelearner" / "skills" / "examples"
    config.data["business"]["workflow_dirs"] = [str(examples)]
    registry = ProviderRegistry({})
    router = Router(registry=registry, embedder=TokenHashEmbedder(), config=config)
    tools, _, _ = build_registry(config)
    engine = SkillEngine(config, tools)
    engine.load()
    loop = AgentLoop(
        config, registry, router, tools, workspace / "vault" / "sessions",
        skill_engine=engine, store=Store(config.get("memory.db")),
    )
    result = loop.run("recon the workspace", mode="auto")
    assert result.deterministic
    assert result.ok
    assert (workspace / ".sl_recon_report.md").exists()


def test_deterministic_no_match_explains(workspace, config):
    registry = ProviderRegistry({})
    router = Router(registry=registry, embedder=TokenHashEmbedder(), config=config)
    tools, _, _ = build_registry(config)
    loop = AgentLoop(config, registry, router, tools, workspace / "vault" / "sessions")
    result = loop.run("compose a sonnet about the ocean", mode="auto")
    assert result.deterministic
    assert not result.ok
    assert "deterministic" in result.error or "No model provider" in result.answer
