"""Desktop control tools: screenshots, clipboard, windows, mouse/keyboard.

Mouse/keyboard injection is HIGH risk and disabled by default — it only
activates with tools.desktop.control_enabled=true. Screenshot/clipboard/
window introspection are read-only and safe.
"""
from __future__ import annotations

import logging
from pathlib import Path
from typing import Any, Optional

log = logging.getLogger("sidelearner.tools.desktop")


def screenshot(path: Optional[str] = None) -> dict:
    """Capture the primary screen to a PNG/JPG file."""
    from ..perception.screen import grab_screen

    img = grab_screen()
    if img is None:
        return {"ok": False, "text": "screen capture failed"}
    target = Path(path) if path else Path("screen_capture.png")
    target.parent.mkdir(parents=True, exist_ok=True)
    fmt = "PNG" if target.suffix.lower() == ".png" else "JPEG"
    img.save(target, format=fmt)
    return {"ok": True, "text": f"screenshot saved to {target}", "file": str(target)}


def clipboard_get() -> dict:
    try:
        import win32clipboard  # type: ignore

        win32clipboard.OpenClipboard()
        try:
            if win32clipboard.IsClipboardFormatAvailable(win32clipboard.CF_UNICODETEXT):
                data = win32clipboard.GetClipboardData(win32clipboard.CF_UNICODETEXT)
                return {"ok": True, "text": f"clipboard ({len(data)} chars):\n{data[:2000]}", "content": data}
            return {"ok": True, "text": "clipboard has no text content"}
        finally:
            win32clipboard.CloseClipboard()
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "text": f"clipboard read failed: {exc}"}


def clipboard_set(text: str) -> dict:
    try:
        import win32clipboard  # type: ignore

        win32clipboard.OpenClipboard()
        try:
            win32clipboard.EmptyClipboard()
            win32clipboard.SetClipboardData(win32clipboard.CF_UNICODETEXT, text)
        finally:
            win32clipboard.CloseClipboard()
        return {"ok": True, "text": f"clipboard set ({len(text)} chars)"}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "text": f"clipboard write failed: {exc}"}


def window_list() -> dict:
    try:
        import win32gui  # type: ignore

        rows = []

        def _cb(hwnd, _):
            if win32gui.IsWindowVisible(hwnd):
                title = win32gui.GetWindowText(hwnd)
                if title.strip():
                    rows.append({"hwnd": hwnd, "title": title, "app": win32gui.GetClassName(hwnd)})
            return True

        win32gui.EnumWindows(_cb, None)
        lines = "\n".join(f"[{r['hwnd']}] {r['app']}: {r['title']}" for r in rows[:60])
        return {"ok": True, "text": f"{len(rows)} visible windows:\n{lines}", "windows": rows[:60]}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "text": f"window enumeration failed: {exc}"}


def focus_window(title_substring: str) -> dict:
    try:
        import win32con
        import win32gui  # type: ignore

        target = None

        def _cb(hwnd, _):
            nonlocal target
            if target is None and win32gui.IsWindowVisible(hwnd):
                title = win32gui.GetWindowText(hwnd)
                if title_substring.lower() in title.lower():
                    target = hwnd
            return True

        win32gui.EnumWindows(_cb, None)
        if target is None:
            return {"ok": False, "text": f"no visible window matching {title_substring!r}"}
        win32gui.ShowWindow(target, win32con.SW_RESTORE)
        win32gui.SetForegroundWindow(target)
        return {"ok": True, "text": f"focused window: {win32gui.GetWindowText(target)}"}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "text": f"focus failed: {exc}"}


def _pyautogui():
    import pyautogui  # type: ignore

    pyautogui.FAILSAFE = True
    pyautogui.PAUSE = 0.15
    return pyautogui


def click(x: int, y: int, button: str = "left") -> dict:
    pg = _pyautogui()
    pg.click(x, y, button=button)
    return {"ok": True, "text": f"clicked ({x},{y}) button={button}"}


def move(x: int, y: int) -> dict:
    pg = _pyautogui()
    pg.moveTo(x, y)
    return {"ok": True, "text": f"moved mouse to ({x},{y})"}


def type_text(text: str, interval: float = 0.02) -> dict:
    pg = _pyautogui()
    pg.write(text, interval=interval)
    return {"ok": True, "text": f"typed {len(text)} chars"}


def hotkey(*keys: str) -> dict:
    pg = _pyautogui()
    pg.hotkey(*keys)
    return {"ok": True, "text": f"sent hotkey {'+'.join(keys)}"}


def register_desktop_tools(registry, provider_factory=None) -> None:
    from .registry import ToolSpec

    registry.register_many(
        [
            ToolSpec("desktop.screenshot", "Capture the screen to an image file.", {"path": "str?"}, screenshot, "low", "desktop", True),
            ToolSpec("desktop.clipboard_get", "Read the clipboard text.", {}, clipboard_get, "low", "desktop", True),
            ToolSpec("desktop.clipboard_set", "Set the clipboard text.", {"text": "str"}, clipboard_set, "medium", "desktop", False),
            ToolSpec("desktop.window_list", "List visible windows.", {}, window_list, "low", "desktop", True),
            ToolSpec("desktop.focus_window", "Focus a window by title substring.", {"title_substring": "str"}, focus_window, "medium", "desktop", False),
            ToolSpec("desktop.click", "Click at screen coordinates.", {"x": "int", "y": "int", "button": "str?"}, click, "high", "desktop", False),
            ToolSpec("desktop.move", "Move the mouse.", {"x": "int", "y": "int"}, move, "high", "desktop", False),
            ToolSpec("desktop.type_text", "Type text via keyboard.", {"text": "str", "interval": "float?"}, type_text, "high", "desktop", False),
            ToolSpec("desktop.hotkey", "Send a hotkey combo.", {"keys": "list[str]"}, lambda keys: hotkey(*keys), "high", "desktop", False),
        ]
    )

    if provider_factory is not None:
        from .desktop_vision import find_element

        def _find(description: str) -> dict:
            return find_element(description, provider_factory)

        def _click_element(description: str) -> dict:
            found = find_element(description, provider_factory)
            if not found.get("ok"):
                return found
            return click(found["x"], found["y"])

        def _type_element(description: str, text: str) -> dict:
            found = find_element(description, provider_factory)
            if not found.get("ok"):
                return found
            click_result = click(found["x"], found["y"])
            if not click_result.get("ok"):
                return click_result
            return type_text(text)

        registry.register_many(
            [
                ToolSpec(
                    "desktop.find_element",
                    "Find a UI element by description and return screen coordinates (vision model).",
                    {"description": "str"},
                    _find,
                    "medium",
                    "desktop",
                    True,
                ),
                ToolSpec(
                    "desktop.click_element",
                    "Find and click a UI element by description (vision model).",
                    {"description": "str"},
                    _click_element,
                    "high",
                    "desktop",
                    False,
                ),
                ToolSpec(
                    "desktop.type_element",
                    "Find a UI element, click it, and type text (vision model).",
                    {"description": "str", "text": "str"},
                    _type_element,
                    "high",
                    "desktop",
                    False,
                ),
            ]
        )
