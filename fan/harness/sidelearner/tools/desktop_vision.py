"""Vision-guided desktop element detection.

Given a text description, capture the screen and ask a vision model to return
the bounding box of the described UI element. The model returns normalized
[x, y, w, h] (0-1); we scale to the actual screen size for pyautogui.
"""
from __future__ import annotations

import json
import logging
import re
from typing import Any, Callable, Optional

from ..perception.screen import grab_screen
from .desktop import _pyautogui

log = logging.getLogger("sidelearner.tools.desktop_vision")


VISION_PROMPT = """You are a UI automation assistant. Look at the screenshot and locate the UI element described by the user.
Return ONLY a JSON object in this exact format:
{"x": <normalized center x 0-1>, "y": <normalized center y 0-1>, "w": <normalized width 0-1>, "h": <normalized height 0-1>, "reason": "brief note"}
Do not wrap in markdown. If the element is not visible, return {"found": false}."""


def _screen_size() -> tuple[int, int]:
    pg = _pyautogui()
    return pg.size()


def _extract_json(text: str) -> Optional[dict]:
    """Extract the first JSON object from model output (handles fences)."""
    text = text.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    # Find the first { ... } block.
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if not match:
        return None
    try:
        return json.loads(match.group(0))
    except json.JSONDecodeError:
        return None


def find_element(description: str, provider_factory: Callable[[], Optional[Any]]) -> dict:
    """Find a UI element by description and return screen coordinates.

    Returns:
        {"ok": True, "x": int, "y": int, "box": {...}, "reason": str}
        or {"ok": False, "text": "..."}
    """
    provider = provider_factory()
    if provider is None:
        return {"ok": False, "text": "no vision provider available for desktop element detection"}
    if "vision" not in getattr(provider, "capabilities", set()):
        return {"ok": False, "text": "provider does not support vision"}

    img = grab_screen()
    if img is None:
        return {"ok": False, "text": "screen capture failed"}

    from ..perception.screen import image_bytes

    try:
        prompt = f"{VISION_PROMPT}\n\nElement to locate: {description}"
        response = provider.vision(image_bytes(img), prompt)
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "text": f"vision model failed: {exc}"}

    if not response:
        return {"ok": False, "text": "vision model returned empty response"}

    box = _extract_json(response)
    if box is None:
        return {"ok": False, "text": f"vision model did not return JSON: {response[:200]}"}
    if box.get("found") is False:
        return {"ok": False, "text": f"element not found: {description}"}

    sw, sh = _screen_size()
    x = box.get("x", 0.5)
    y = box.get("y", 0.5)
    if "cx" in box and "cy" in box:
        x, y = box["cx"], box["cy"]
    screen_x = int(x * sw)
    screen_y = int(y * sh)

    return {
        "ok": True,
        "x": screen_x,
        "y": screen_y,
        "box": box,
        "reason": box.get("reason", ""),
        "text": f"found '{description}' at ({screen_x}, {screen_y})",
    }
