"""Register tools from configured MCP servers."""
from __future__ import annotations

import logging
from pathlib import Path
from typing import Any, Optional

from ..events import EventBus
from ..mcp.client import MCPClient
from ..mcp.playwright_tools import PlaywrightMCPAdapter
from .registry import ToolRegistry, ToolSpec

log = logging.getLogger("sidelearner.tools.mcp")


def register_mcp_tools(registry: ToolRegistry, config: Any, bus: Optional[EventBus] = None) -> list[MCPClient]:
    """Connect configured MCP servers and register their tools.

    Returns the list of connected clients so the harness can keep them alive.
    """
    clients: list[MCPClient] = []
    mcp_cfg = config.get("mcp_servers") or {}
    if not isinstance(mcp_cfg, dict):
        log.warning("mcp_servers config is not a dict; skipping")
        return clients

    for name, server in mcp_cfg.items():
        if not isinstance(server, dict):
            continue
        if server.get("enabled") is False:
            continue
        command = server.get("command")
        url = server.get("url")
        env = server.get("env")
        timeout = float(server.get("timeout", 30.0))

        client = MCPClient(name=name, command=command, url=url, env=env, timeout=timeout)
        if not client.connect():
            log.warning("mcp server %s did not connect; skipping", name)
            client.disconnect()
            continue

        # Playwright is special: map to stable browser.* names.
        browser_enabled = config.get("tools.browser.enabled", True)
        if _looks_like_playwright(client) and browser_enabled:
            capture_dir = Path(str(config.get("vault_dir", "."))) / "mcp"
            adapter = PlaywrightMCPAdapter(client, capture_dir=capture_dir)
            adapter.discover()
            for spec in adapter.specs():
                # Replace placeholder function with one bound to this adapter.
                bound = _make_browser_function(adapter, spec.name)
                registry.register(
                    ToolSpec(
                        name=spec.name,
                        description=spec.description,
                        parameters=spec.parameters,
                        function=bound,
                        risk=spec.risk,
                        family=spec.family,
                        read_only=spec.read_only,
                        tags=spec.tags,
                    )
                )
            log.info("registered %d browser tools from playwright mcp server", len(adapter.specs()))
        else:
            # Generic MCP tools: expose as mcp.<server>.<tool>.
            _register_generic_mcp_tools(registry, client, bus)

        clients.append(client)

    return clients


def _looks_like_playwright(client: MCPClient) -> bool:
    """Heuristic: does this server expose playwright-style tools?"""
    names = {t.get("name", "").lower() for t in client.tools}
    return bool(
        names
        & {
            "playwright_navigate",
            "playwright_click",
            "playwright_screenshot",
            "browser_navigate",
            "browser_click",
        }
    )


def _make_browser_function(adapter: PlaywrightMCPAdapter, name: str):
    def _fn(**kwargs: Any) -> dict:
        return adapter.call(name, kwargs)

    return _fn


def _register_generic_mcp_tools(registry: ToolRegistry, client: MCPClient, bus: Optional[EventBus]) -> None:
    from ..mcp.playwright_tools import _schema_to_params

    for tool in client.tools:
        tool_name = tool.get("name", "")
        if not tool_name:
            continue
        stable = f"mcp.{client.name}.{tool_name}"
        schema = tool.get("inputSchema", {}) or {}
        params = _schema_to_params(schema)

        def _fn(name=tool_name, cli=client):
            def __fn(**kwargs: Any) -> dict:
                try:
                    result = cli.call_tool(name, kwargs)
                except Exception as exc:  # noqa: BLE001
                    return {"ok": False, "text": f"mcp call failed: {exc}"}
                # Best-effort normalization.
                content = result.get("content", [])
                text = "\n".join(str(c.get("text", "")) for c in content)
                return {"ok": not result.get("isError", False), "text": text or "ok"}

            return __fn

        registry.register(
            ToolSpec(
                name=stable,
                description=tool.get("description") or f"MCP tool {tool_name} from {client.name}",
                parameters=params,
                function=_fn(),
                risk="medium",
                family="mcp",
                read_only=False,
                tags=["mcp", client.name],
            )
        )
