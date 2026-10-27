"""Tests for MCP client and Playwright MCP adapter."""
from __future__ import annotations

import json
import sys
import threading
import time
from pathlib import Path

import pytest

from sidelearner.mcp.client import MCPClient, MCPError
from sidelearner.mcp.playwright_tools import PlaywrightMCPAdapter, _normalize_result
from sidelearner.tools import build_registry
from sidelearner.config import Config


class FakeMCPClient:
    """In-memory MCP client for testing the adapter."""

    def __init__(self, tools: list[dict]) -> None:
        self.tools = tools
        self.calls: list[tuple[str, dict]] = []
        self._responses: list[dict] = []

    def queue(self, result: dict) -> None:
        self._responses.append(result)

    def call_tool(self, name: str, arguments: dict) -> dict:
        self.calls.append((name, arguments))
        if self._responses:
            return self._responses.pop(0)
        return {"content": [{"type": "text", "text": "ok"}]}

    def tool_named(self, name: str) -> dict | None:
        for t in self.tools:
            if t.get("name") == name:
                return t
        return None


def test_adapter_maps_playwright_tools():
    fake = FakeMCPClient(
        [
            {"name": "playwright_navigate", "inputSchema": {"properties": {"url": {"type": "string"}}, "required": ["url"]}},
            {"name": "playwright_click", "inputSchema": {"properties": {"selector": {"type": "string"}}, "required": ["selector"]}},
            {"name": "playwright_screenshot", "inputSchema": {"properties": {}}},
        ]
    )
    adapter = PlaywrightMCPAdapter(fake)
    mapping = adapter.discover()
    assert mapping.get("browser.open") == "playwright_navigate"
    assert mapping.get("browser.click") == "playwright_click"
    assert mapping.get("browser.screenshot") == "playwright_screenshot"

    specs = adapter.specs()
    names = {s.name for s in specs}
    assert "browser.open" in names
    open_spec = next(s for s in specs if s.name == "browser.open")
    assert open_spec.parameters == {"url": "str"}
    assert open_spec.risk == "low"


def test_adapter_call_forwards_and_normalizes():
    fake = FakeMCPClient(
        [{"name": "playwright_navigate", "inputSchema": {"properties": {"url": {"type": "string"}}}}]
    )
    fake.queue({"content": [{"type": "text", "text": "navigated"}]})
    adapter = PlaywrightMCPAdapter(fake)
    adapter.discover()
    result = adapter.call("browser.open", {"url": "http://example.com"})
    assert result["ok"] is True
    assert "navigated" in result["text"]
    assert fake.calls == [("playwright_navigate", {"url": "http://example.com"})]


def test_adapter_image_saved_to_capture_dir(tmp_path: Path):
    fake = FakeMCPClient(
        [{"name": "playwright_screenshot", "inputSchema": {"properties": {}}}]
    )
    fake.queue(
        {
            "content": [
                {"type": "image", "mimeType": "image/png", "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="}
            ]
        }
    )
    adapter = PlaywrightMCPAdapter(fake, capture_dir=tmp_path)
    adapter.discover()
    result = adapter.call("browser.screenshot", {})
    assert result["ok"] is True
    assert result["images"]
    assert Path(result["images"][0]).exists()


def test_normalize_result_error_flag():
    result = _normalize_result("browser.click", {"isError": True, "content": [{"type": "text", "text": "bad"}]})
    assert result["ok"] is False
    assert "bad" in result["text"]


def test_stdio_mock_server(tmp_path: Path):
    """Launch a tiny Python MCP server over stdio and verify initialize/tools/list work."""
    server_path = tmp_path / "mock_mcp_server.py"
    server_path.write_text(
        "import json, sys\n"
        "for line in sys.stdin:\n"
        "    req = json.loads(line.strip())\n"
        "    if req.get('method') == 'initialize':\n"
        "        resp = {'jsonrpc': '2.0', 'id': req['id'], 'result': {'protocolVersion': '2024-11-05', 'serverInfo': {'name': 'mock'}}}\n"
        "    elif req.get('method') == 'notifications/initialized':\n"
        "        continue\n"
        "    elif req.get('method') == 'tools/list':\n"
        "        resp = {'jsonrpc': '2.0', 'id': req['id'], 'result': {'tools': [{'name': 'playwright_navigate', 'inputSchema': {'properties': {'url': {'type': 'string'}}, 'required': ['url']}}]}}\n"
        "    elif req.get('method') == 'tools/call':\n"
        "        resp = {'jsonrpc': '2.0', 'id': req['id'], 'result': {'content': [{'type': 'text', 'text': 'done'}]}}\n"
        "    else:\n"
        "        resp = {'jsonrpc': '2.0', 'id': req['id'], 'result': {}}\n"
        "    print(json.dumps(resp), flush=True)\n",
        encoding="utf-8",
    )
    client = MCPClient(name="mock", command=[sys.executable, str(server_path)], timeout=5.0)
    assert client.connect() is True
    assert client.server_info.get("name") == "mock"
    assert any(t.get("name") == "playwright_navigate" for t in client.tools)
    result = client.call_tool("playwright_navigate", {"url": "http://example.com"})
    assert any(c.get("text") == "done" for c in result.get("content", []))
    client.disconnect()


def test_register_mcp_tools_with_playwright():
    """If no MCP server is configured/running, registry should still build normally."""
    config = Config(data={})
    registry, _, _ = build_registry(config)
    # Default config has no mcp_servers enabled; mcp_clients is empty.
    assert registry.mcp_clients == []


def test_register_mcp_tools_skips_disabled_server():
    config = Config(
        data={
            "mcp_servers": {
                "playwright": {"enabled": False, "command": ["npx", "-y", "@anthropic-ai/playwright-mcp-server"]}
            }
        }
    )
    registry, _, _ = build_registry(config)
    assert registry.mcp_clients == []
