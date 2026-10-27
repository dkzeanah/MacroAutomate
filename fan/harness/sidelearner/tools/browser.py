"""Browser automation via Playwright (optional dependency).

Registered only when playwright + a browser are installed:
    pip install playwright && playwright install chromium
"""
from __future__ import annotations

import logging
from pathlib import Path
from typing import Any, Optional

log = logging.getLogger("sidelearner.tools.browser")

_browser = None
_playwright = None


def available() -> bool:
    global _playwright
    if _playwright is None:
        try:
            from playwright.sync_api import sync_playwright  # type: ignore

            _playwright = sync_playwright
        except ImportError:
            _playwright = False  # type: ignore[assignment]
    return bool(_playwright)


def _ensure_page():
    global _browser
    if _browser is None:
        pw = _playwright()
        _browser = pw.chromium.launch(headless=True)
    context = _browser.new_context()
    return context.new_page(), context


def open_url(url: str, wait_ms: int = 1500) -> dict:
    page, _ = _ensure_page()
    page.goto(url, wait_until="domcontentloaded")
    page.wait_for_timeout(wait_ms)
    title = page.title()
    return {"ok": True, "text": f"opened {url} — title: {title}", "title": title}


def content(url: Optional[str] = None, selector: Optional[str] = None, max_chars: int = 8000) -> dict:
    page, _ = _ensure_page()
    if url:
        page.goto(url, wait_until="domcontentloaded")
    if selector:
        text = page.inner_text(selector)
    else:
        text = page.inner_text("body")
    return {"ok": True, "text": text[:max_chars], "content": text}


def click(selector: str) -> dict:
    page, _ = _ensure_page()
    page.click(selector)
    return {"ok": True, "text": f"clicked {selector}"}


def type_text(selector: str, text: str) -> dict:
    page, _ = _ensure_page()
    page.fill(selector, text)
    return {"ok": True, "text": f"filled {selector}"}


def page_screenshot(path: Optional[str] = None, selector: Optional[str] = None) -> dict:
    page, _ = _ensure_page()
    target = Path(path) if path else Path("browser_capture.png")
    if selector:
        el = page.query_selector(selector)
        el.screenshot(path=str(target))
    else:
        page.screenshot(path=str(target))
    return {"ok": True, "text": f"screenshot saved to {target}", "file": str(target)}


def evaluate(script: str) -> dict:
    page, _ = _ensure_page()
    result = page.evaluate(script)
    return {"ok": True, "text": f"evaluated: {str(result)[:2000]}", "result": result}


def register_browser_tools(registry) -> bool:
    from .registry import ToolSpec

    if not available():
        log.info("browser tools skipped: playwright not installed")
        return False
    registry.register_many(
        [
            ToolSpec("browser.open", "Open a URL in a headless browser.", {"url": "str", "wait_ms": "int?"}, open_url, "low", "browser", True),
            ToolSpec("browser.content", "Get page text content.", {"url": "str?", "selector": "str?"}, content, "low", "browser", True),
            ToolSpec("browser.click", "Click a selector.", {"selector": "str"}, click, "medium", "browser", False),
            ToolSpec("browser.type", "Fill a selector with text.", {"selector": "str", "text": "str"}, type_text, "medium", "browser", False),
            ToolSpec("browser.screenshot", "Screenshot the page.", {"path": "str?", "selector": "str?"}, page_screenshot, "low", "browser", True),
            ToolSpec("browser.evaluate", "Run JS in the page.", {"script": "str"}, evaluate, "medium", "browser", True),
        ]
    )
    return True
