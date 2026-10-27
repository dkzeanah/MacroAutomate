"""Build the full tool registry for a config."""
from __future__ import annotations

import logging
from typing import Any, Optional

from ..events import EventBus
from .browser import register_browser_tools
from .desktop import register_desktop_tools
from .fs import FsSandbox, register_fs_tools
from .mcp import register_mcp_tools
from .registry import ToolRegistry, ToolResult, ToolSpec
from .shell import ShellPolicy, register_shell_tools

log = logging.getLogger("sidelearner.tools")


def build_registry(
    config: Any, bus: Optional[EventBus] = None, vision_provider_factory=None
) -> tuple[ToolRegistry, FsSandbox, ShellPolicy]:
    """Create a registry with all standard tools registered."""
    registry = ToolRegistry(config, bus=bus)
    sandbox = register_fs_tools(registry, config)
    policy = register_shell_tools(registry, config)
    register_desktop_tools(registry, provider_factory=vision_provider_factory)
    register_browser_tools(registry)
    registry.mcp_clients = register_mcp_tools(registry, config, bus=bus)
    from sidelearner.perception.vision import FanBridgeClient
    FanBridgeClient().register_to(registry)
    return registry, sandbox, policy


__all__ = [
    "ToolRegistry",
    "ToolResult",
    "ToolSpec",
    "FsSandbox",
    "ShellPolicy",
    "build_registry",
]
