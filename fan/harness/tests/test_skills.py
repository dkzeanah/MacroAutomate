import yaml

from sidelearner.skills.engine import Skill, SkillEngine
from sidelearner.tools import build_registry


def _make_skill(workspace) -> Skill:
    yaml_text = """
name: test_flow
description: exercises every step kind
keywords: [flow, testflow]
triggers: []
requires: [fs]
steps:
  - name: set_value
    kind: set
    vars: { total: 0 }
  - name: mkdir_step
    kind: tool
    tool: fs.mkdir
    args: { path: "out" }
  - name: write_files
    kind: repeat
    over: "[1, 2, 3]"
    as: i
    steps:
      - name: write_one
        kind: tool
        tool: fs.write_text
        args: { path: "out/file{{ i }}.txt", content: "file {{ i }}" }
      - name: bump
        kind: set
        vars: { total: "vars['total'] + 1" }
  - name: verify_total
    kind: check
    expr: "vars['total'] == 3"
  - name: branch
    kind: condition
    if: "vars['total'] == 3"
    then:
      - name: touch_ok
        kind: tool
        tool: fs.write_text
        args: { path: "out/branch_ok.txt", content: "yes" }
    else: []
  - name: stop_here
    kind: stop
    ok: true
    message: "done: {{ vars['total'] }} files"
"""
    path = workspace / "test_flow.yaml"
    path.write_text(yaml_text, encoding="utf-8")
    return Skill.from_yaml(path)


def test_skill_engine_full_flow(workspace, config):
    registry, _, _ = build_registry(config)
    engine = SkillEngine(config, registry)
    skill = _make_skill(workspace)
    result = engine.run(skill, vars={"cwd": str(workspace)})
    assert result.ok, result.output
    assert "done: 3 files" in result.output
    for i in (1, 2, 3):
        assert (workspace / "out" / f"file{i}.txt").exists()
    assert (workspace / "out" / "branch_ok.txt").exists()
    # Written paths propagate for the agent loop's verification pass.
    assert any(str(workspace / "out" / "file1.txt") in w for w in result.written)
    # Steps: set, mkdir, 3x(write+set), check, condition(write), stop
    assert len(result.steps) == 10


def test_skill_check_failure_stops(workspace, config):
    registry, _, _ = build_registry(config)
    engine = SkillEngine(config, registry)
    path = workspace / "bad.yaml"
    path.write_text(
        yaml.safe_dump(
            {
                "name": "bad_flow",
                "steps": [
                    {"name": "nope", "kind": "check", "expr": "1 == 2"},
                    {"name": "never", "kind": "tool", "tool": "fs.mkdir", "args": {"path": "never_dir"}},
                ],
            }
        ),
        encoding="utf-8",
    )
    skill = Skill.from_yaml(path)
    result = engine.run(skill, vars={"cwd": str(workspace)})
    assert not result.ok
    assert not (workspace / "never_dir").exists()


def test_prompt_step_skips_without_provider(workspace, config):
    registry, _, _ = build_registry(config)
    engine = SkillEngine(config, registry)
    path = workspace / "prompt.yaml"
    path.write_text(
        yaml.safe_dump(
            {
                "name": "prompt_flow",
                "steps": [
                    {"name": "ask", "kind": "prompt", "prompt": "hi", "collect": "answer"},
                    {"name": "use", "kind": "set", "vars": {"got": "vars['answer'] == ''"}},
                    {"name": "check_empty", "kind": "check", "expr": "vars['got']"},
                ],
            }
        ),
        encoding="utf-8",
    )
    skill = Skill.from_yaml(path)
    result = engine.run(skill, vars={"cwd": str(workspace)})
    assert result.ok


def test_template_errors_are_contained():
    from sidelearner.skills.engine import _render

    assert _render("hello {{ vars['name'] }}", {"name": "world"}) == "hello world"
    rendered = _render("bad {{ vars['missing_key'] }}", {})
    assert rendered.startswith("bad [expr-error:")
