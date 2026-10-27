"""Adapter that exposes a Playwright MCP server as SideLearner browser tools."""
from __future__ import annotations

import base64
import logging
import time
from pathlib import Path
from typing import Any, Optional

from .client import MCPClient, MCPError

log = logging.getLogger("sidelearner.mcp.playwright")

# Map stable SideLearner tool names -> candidate MCP tool names, in preference order.
# Different MCP servers use slightly different conventions; we try the common ones.
_KNOWN_TOOLS: dict[str, list[str]] = {
    "browser.open": ["playwright_navigate", "browser_navigate", "mcp_playwright_navigate"],
    "browser.screenshot": ["playwright_screenshot", "browser_screenshot", "mcp_playwright_screenshot"],
    "browser.content": ["playwright_get_text", "browser_get_text", "mcp_playwright_get_text", "playwright_inner_text"],
    "browser.click": ["playwright_click", "browser_click", "mcp_playwright_click"],
    "browser.type": ["playwright_fill", "browser_fill", "mcp_playwright_fill", "playwright_type"],
    "browser.evaluate": ["playwright_evaluate", "browser_evaluate", "mcp_playwright_evaluate"],
    "browser.hover": ["playwright_hover", "browser_hover", "mcp_playwright_hover"],
    "browser.select": ["playwright_select", "browser_select", "mcp_playwright_select"],
}


class PlaywrightMCPAdapter:
    """Wraps a connected Playwright MCP client and produces SideLearner ToolSpecs."""

    def __init__(self, client: MCPClient, capture_dir: Optional[Path] = None) -> None:
        self.client = client
        self.capture_dir = capture_dir
        self._mapping: dict[str, str] = {}  # sidelearner name -> actual mcp tool name

    def discover(self) -> dict[str, str]:
        """Build the mapping between our stable names and the server's tool names."""
        available = {t.get("name", ""): t for t in self.client.tools}
        mapping: dict[str, str] = {}
        for stable, candidates in _KNOWN_TOOLS.items():
            for cand in candidates:
                if cand in available:
                    mapping[stable] = cand
                    break
        # Also expose any remaining playwright/browser tools under mcp_* names.
        for name in available:
            if name not in mapping.values():
                mapping[f"browser.mcp.{name}"] = name
        self._mapping = mapping
        log.info("playwright mcp mapping: %s", mapping)
        return mapping

    def has(self, stable_name: str) -> bool:
        return stable_name in self._mapping

    def call(self, stable_name: str, arguments: dict) -> dict:
        actual = self._mapping.get(stable_name)
        if actual is None:
            return {"ok": False, "text": f"tool {stable_name} not available from MCP server"}
        try:
            result = self.client.call_tool(actual, arguments)
        except MCPError as exc:
            return {"ok": False, "text": f"{stable_name} failed: {exc}"}
        return _normalize_result(stable_name, result, capture_dir=self.capture_dir)

    def specs(self) -> list:
        """Return ToolSpec objects for the discovered tools."""
        from ..tools.registry import ToolSpec

        if not self._mapping:
            self.discover()
        specs = []
        for stable_name, actual_name in self._mapping.items():
            tool_info = self.client.tool_named(actual_name) or {}
            schema = tool_info.get("inputSchema", {}) or {}
            params = _schema_to_params(schema)
            risk = _risk_for(stable_name)
            read_only = stable_name in {"browser.open", "browser.content", "browser.screenshot", "browser.evaluate"}
            specs.append(
                ToolSpec(
                    name=stable_name,
                    description=_description_for(stable_name, actual_name),
                    parameters=params,
                    function=lambda name=stable_name: None,  # placeholder; executor uses adapter directly
                    risk=risk,
                    family="browser",
                    read_only=read_only,
                    tags=["mcp", "playwright"],
                )
            )
        return specs


def _normalize_result(stable_name: str, result: dict, capture_dir: Optional[Path] = None) -> dict:
    """Convert an MCP tools/call result into SideLearner's tool result shape."""
    content = result.get("content", [])
    text_parts: list[str] = []
    images: list[str] = []
    data: dict = {"isError": result.get("isError", False)}

    for item in content:
        typ = item.get("type")
        if typ == "text":
            text_parts.append(str(item.get("text", "")))
        elif typ == "image" and item.get("data"):
            # Save base64 image to the capture directory for later inspection.
            try:
                img_bytes = base64.b64decode(item["data"])
                ext = "png" if item.get("mimeType", "").endswith("png") else "jpg"
                target_dir = capture_dir or Path.cwd()
                target_dir.mkdir(parents=True, exist_ok=True)
                path = target_dir / f"browser_capture_mcp_{int(time.time()*1000)}.{ext}"
                path.write_bytes(img_bytes)
                images.append(str(path))
            except Exception as exc:  # noqa: BLE001
                text_parts.append(f"[image decode error: {exc}]")
        elif typ == "resource":
            text_parts.append(str(item.get("resource", "")))

    text = "\n".join(text_parts)
    if images:
        data["images"] = images
    ok = not data["isError"]
    return {"ok": ok, "text": text or ("ok" if ok else "failed"), **data}


def _schema_to_params(schema: dict) -> dict:
    """Convert a JSON schema into our compact parameter description."""
    params: dict = {}
    props = schema.get("properties", {}) or {}
    required = set(schema.get("required", []))
    for name, prop in props.items():
        typ = prop.get("type", "string")
        if typ == "array":
            item_type = (prop.get("items") or {}).get("type", "string")
            desc = f"list[{item_type}]"
        elif typ == "boolean":
            desc = "bool"
        elif typ == "integer":
            desc = "int"
        elif typ == "number":
            desc = "float"
        else:
            desc = "str"
        if name not in required:
            desc += "?"
        params[name] = desc
    return params


def _risk_for(stable_name: str) -> str:
    if stable_name in {"browser.open", "browser.content", "browser.screenshot", "browser.evaluate"}:
        return "low"
    if stable_name in {"browser.click", "browser.type", "browser.hover", "browser.select"}:
        return "medium"
    return "medium"


def _description_for(stable_name: str, actual_name: str) -> str:
    return {
        "browser.open": f"Open a URL in the browser via MCP ({actual_name}).",
        "browser.content": f"Get visible text from the current page via MCP ({actual_name}).",
        "browser.screenshot": f"Capture a browser screenshot via MCP ({actual_name}).",
        "browser.click": f"Click a browser element via MCP ({actual_name}).",
        "browser.type": f"Type text into a browser element via MCP ({actual_name}).",
        "browser.evaluate": f"Evaluate JavaScript in the browser page via MCP ({actual_name}).",
        "browser.hover": f"Hover over a browser element via MCP ({actual_name}).",
        "browser.select": f"Select an option in a browser dropdown via MCP ({actual_name}).",
    }.get(stable_name, f"MCP browser tool {actual_name}.")


def _is_image_tool(name: str) -> bool:
    return "screenshot" in name.lower()
