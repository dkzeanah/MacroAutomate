from pathlib import Path

from sidelearner.config import Config


def test_defaults_and_path_resolution(workspace):
    cfg = Config({}, workspace=workspace)
    assert Path(cfg.get("vault_dir")).is_absolute()
    assert Path(cfg.get("memory.db")).is_absolute()
    assert Path(cfg.get("tools.fs.roots")[0]).is_absolute()
    assert cfg.get("perception.screen.enabled") is True
    assert cfg.get("agent.max_steps") == 12


def test_business_vocabulary_access(config):
    config.data["business"]["vocabulary"] = ["invoice", "payroll"]
    assert "invoice" in config.get("business.vocabulary")
    assert config.get("business.missing.key", "fallback") == "fallback"


def test_env_expansion(config):
    config.data["providers"] = {"p": {"kind": "openai_compat", "base_url": "${SL_TEST_BASE}/v1", "model": "m"}}
    # Expand via expand_env to simulate load-time behavior.
    from sidelearner.utils import expand_env

    expanded = expand_env(config.data)
    assert expanded["providers"]["p"]["base_url"].endswith("/v1")


def test_save_load_roundtrip(workspace):
    path = workspace / "cfg.yaml"
    cfg = Config({"business": {"name": "acme"}}, workspace=workspace)
    cfg.save(path)
    loaded = Config.load(path, workspace=workspace)
    assert loaded.get("business.name") == "acme"


class TestFanIntegration:
    """Local memory remains readable while desktop input obeys control policy."""

    def test_control_policy_blocks_before_transport(self, config, monkeypatch):
        from sidelearner.perception.vision import FanBridgeClient
        from sidelearner.tools.registry import ToolRegistry
        client = FanBridgeClient()
        calls = []
        monkeypatch.setattr(client, "call", lambda name, args: calls.append(name) or {"ok": True})
        registry = ToolRegistry(config)
        client.register_to(registry)
        spec = registry.specs["fan_taskbar_open"]
        assert spec.risk == "high" and spec.family == "desktop" and not spec.read_only
        result = registry.execute("fan_taskbar_open", {"name": "SciTE"})
        assert result.denied and not calls
        assert registry.execute("fan_taskbar_list", {"query": "SciTE"}).ok
        assert calls == ["fan_taskbar_list"]

    def test_loopback_credentials_and_tool_boundary(self, tmp_path, monkeypatch):
        import json
        import urllib.request
        from sidelearner.perception.vision import FanBridgeClient
        folder = tmp_path / "fan" / "DeepSeekBridge"
        folder.mkdir(parents=True)
        (folder / ".env").write_text("BRIDGE_TOKEN=private-test-token\nBRIDGE_PORT=8765\nBRIDGE_HOST=untrusted.invalid\n")
        seen = []
        class Response:
            def __enter__(self):
                return self
            def __exit__(self, *args):
                pass
            def read(self, limit):
                return json.dumps({"ok": True, "targets": []}).encode()
        def send(request, **kwargs):
            seen.append(request)
            return Response()
        monkeypatch.setattr(urllib.request, "urlopen", send)
        client = FanBridgeClient(tmp_path)
        assert client.call("fan_taskbar_list")["ok"]
        assert seen[0].full_url == "http://127.0.0.1:8765/tools/fan_taskbar_list"
        assert seen[0].get_header("X-bridge-token") == "private-test-token"
        import pytest
        with pytest.raises(ValueError, match="scope"):
            client.call("text_type", {"text": "unadvertised input"})
        assert len(seen) == 1

    def test_learning_tab_builds_offline(self):
        import tkinter as tk
        from tkinter import ttk
        from types import SimpleNamespace
        from studio.tabs.gate_tab import AutomationTab
        root = tk.Tk()
        root.withdraw()
        callbacks = {}
        job = SimpleNamespace(on=lambda name, callback: callbacks.update({name: callback}))
        try:
            tab = AutomationTab(ttk.Frame(root), SimpleNamespace(job=job))
            assert len(tab.buttons) == 9
            assert "Observed" in tab.output.get() or "captures icons" in tab.output.get()
            tab.query.set("")
            tab.run("fan_taskbar_open")
            assert "Enter a saved app name" in tab.output.get()
            tab.done({"ok": True, "targets": [{"label": "SciTE", "exe": "SciTE.exe", "binary_length": 760}]})
            assert "SciTE" in tab.output.get()
        finally:
            root.destroy()
