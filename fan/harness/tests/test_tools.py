from sidelearner.tools import build_registry
from sidelearner.tools.fs import FsSandbox


def test_sandbox_blocks_escape(workspace):
    sandbox = FsSandbox(roots=[str(workspace)])
    try:
        sandbox._resolve(str(workspace.parent / "secret.txt"), for_write=True)
        assert False, "escape must be blocked"
    except PermissionError:
        pass


def test_fs_write_read_roundtrip(workspace, config):
    registry, sandbox, policy = build_registry(config)
    write = registry.execute("fs.write_text", {"path": "note.txt", "content": "hello sidelearner"})
    assert write.ok
    assert (workspace / "note.txt").read_text() == "hello sidelearner"
    read = registry.execute("fs.read_text", {"path": "note.txt"})
    assert read.ok and "hello sidelearner" in read.text


def test_fs_edit_and_grep(workspace, config):
    registry, _, _ = build_registry(config)
    registry.execute("fs.write_text", {"path": "a.py", "content": "TODO fix this\nprint('ok')\n"})
    edit = registry.execute("fs.edit", {"path": "a.py", "old": "TODO fix this", "new": "DONE"})
    assert edit.ok
    grep = registry.execute("fs.grep", {"path": ".", "pattern": "DONE"})
    assert grep.ok and "a.py" in grep.text


def test_shell_denylist(workspace, config):
    registry, _, _ = build_registry(config)
    result = registry.execute("shell.run", {"command": "echo hello"})
    assert result.ok
    result = registry.execute("shell.run", {"command": "format c:"})
    assert result.denied


def test_high_risk_fs_requires_ask(workspace, config):
    registry, _, _ = build_registry(config)
    (workspace / "victim.txt").write_text("x")
    denied = registry.execute("fs.delete", {"path": "victim.txt"})
    assert denied.denied
    assert (workspace / "victim.txt").exists()

    registry.set_ask_callback(lambda msg: True)
    allowed = registry.execute("fs.delete", {"path": "victim.txt"})
    assert allowed.ok
    assert not (workspace / "victim.txt").exists()


def test_unknown_tool(workspace, config):
    registry, _, _ = build_registry(config)
    result = registry.execute("nope.nothing", {})
    assert not result.ok and result.denied


def test_desktop_control_gated(workspace, config):
    registry, _, _ = build_registry(config)
    result = registry.execute("desktop.click", {"x": 0, "y": 0})
    assert result.denied
    assert "control_enabled" in result.text
