from __future__ import annotations

import json
import queue
import re
import threading
import time
import uuid
from pathlib import Path
from typing import Any

from .core import flatten_profile


FIELD_DISCOVERY_JS = r"""
() => {
  function textOf(el) {
    if (!el) return "";
    return (el.innerText || el.textContent || "").replace(/\s+/g, " ").trim();
  }

  function labelFor(el) {
    const parts = [];
    if (el.labels) {
      for (const label of el.labels) parts.push(textOf(label));
    }
    const aria = el.getAttribute("aria-label");
    if (aria) parts.push(aria);
    const labelledBy = el.getAttribute("aria-labelledby");
    if (labelledBy) {
      for (const id of labelledBy.split(/\s+/)) {
        const node = document.getElementById(id);
        if (node) parts.push(textOf(node));
      }
    }
    let parent = el.parentElement;
    for (let i = 0; parent && i < 3; i++, parent = parent.parentElement) {
      if (parent.tagName === "LABEL") parts.push(textOf(parent));
    }
    const previous = el.previousElementSibling;
    if (previous && ["LABEL", "SPAN", "DIV", "P"].includes(previous.tagName)) {
      const t = textOf(previous);
      if (t.length <= 160) parts.push(t);
    }
    return [...new Set(parts.filter(Boolean))].join(" | ");
  }

  function visible(el) {
    const style = window.getComputedStyle(el);
    const rect = el.getBoundingClientRect();
    return style.display !== "none" &&
           style.visibility !== "hidden" &&
           Number(style.opacity || 1) > 0 &&
           rect.width > 0 &&
           rect.height > 0;
  }

  const controls = [...document.querySelectorAll("input, textarea, select")];
  return controls.filter(visible).map((el, index) => {
    if (!el.dataset.ojasId) {
      el.dataset.ojasId = "ojas-" + Date.now().toString(36) + "-" +
                          index.toString(36) + "-" +
                          Math.random().toString(36).slice(2, 9);
    }
    const tag = el.tagName.toLowerCase();
    const type = (el.getAttribute("type") || tag).toLowerCase();
    const options = tag === "select"
      ? [...el.options].map(o => ({text: textOf(o), value: o.value}))
      : [];
    return {
      token: el.dataset.ojasId,
      tag,
      type,
      name: el.getAttribute("name") || "",
      id: el.id || "",
      placeholder: el.getAttribute("placeholder") || "",
      aria_label: el.getAttribute("aria-label") || "",
      autocomplete: el.getAttribute("autocomplete") || "",
      label: labelFor(el),
      required: !!el.required,
      disabled: !!el.disabled,
      read_only: !!el.readOnly,
      value: type === "password" ? "<password hidden>" : (el.value || ""),
      checked: !!el.checked,
      options
    };
  });
}
"""


def normalized_field_text(field: dict[str, Any]) -> str:
    parts = [
        field.get("label", ""),
        field.get("name", ""),
        field.get("id", ""),
        field.get("placeholder", ""),
        field.get("aria_label", ""),
        field.get("autocomplete", ""),
    ]
    return re.sub(r"\s+", " ", " ".join(str(p) for p in parts)).strip().lower()


class FieldMapper:
    def __init__(self, profile: dict[str, Any], rules: dict[str, Any]) -> None:
        self.profile = profile
        self.rules = rules
        self.flat = flatten_profile(profile)
        self.manual_keywords = [
            keyword.lower() for keyword in rules.get("manual_only_keywords", [])
        ]
        self.aliases = rules.get("safe_field_aliases", {})

    def map_field(self, field: dict[str, Any]) -> dict[str, Any]:
        text = normalized_field_text(field)
        result = {
            **field,
            "field_text": text,
            "status": "unknown",
            "source": "",
            "proposed": "",
            "confidence": 0.0,
            "reason": "No verified profile mapping found.",
        }

        if field.get("disabled") or field.get("read_only"):
            result.update(
                status="ignored",
                reason="Field is disabled or read-only.",
            )
            return result

        if field.get("type") in {"hidden", "submit", "button", "reset", "password"}:
            result.update(status="ignored", reason=f"Field type {field.get('type')} is not autofilled.")
            return result

        if any(keyword in text for keyword in self.manual_keywords):
            result.update(
                status="manual",
                reason="Sensitive, legal, compensation, authorization, or attestation field.",
            )
            return result

        if field.get("type") in {"checkbox", "radio"}:
            result.update(
                status="manual",
                reason="Checkboxes and radio buttons require explicit user review.",
            )
            return result

        autocomplete_map = {
            "given-name": "first_name",
            "additional-name": "middle_name",
            "family-name": "last_name",
            "nickname": "preferred_name",
            "email": "email",
            "tel": "phone",
            "tel-national": "phone",
            "street-address": "address_line_1",
            "address-line1": "address_line_1",
            "address-line2": "address_line_2",
            "address-level2": "city",
            "address-level1": "state",
            "postal-code": "postal_code",
            "country": "country",
            "country-name": "country",
            "url": "website",
        }
        autocomplete = str(field.get("autocomplete", "")).lower().strip()
        if autocomplete in autocomplete_map:
            key = autocomplete_map[autocomplete]
            value = self.flat.get(key, "")
            if value:
                result.update(
                    status="safe",
                    source=key,
                    proposed=str(value),
                    confidence=0.99,
                    reason=f"Mapped from HTML autocomplete={autocomplete}.",
                )
                return result

        best_key = ""
        best_score = 0.0
        for key, aliases in self.aliases.items():
            for alias in aliases:
                alias = str(alias).lower().strip()
                if not alias:
                    continue
                if text == alias:
                    score = 1.0
                elif re.search(rf"\b{re.escape(alias)}\b", text):
                    score = min(0.96, 0.72 + len(alias) / max(80, len(text)))
                elif alias.replace(" ", "") in text.replace(" ", ""):
                    score = 0.68
                else:
                    continue
                if score > best_score:
                    best_key = key
                    best_score = score

        if best_key:
            value = self.flat.get(best_key, "")
            if value:
                if field.get("type") == "file":
                    path = Path(str(value)).expanduser()
                    if not path.exists():
                        result.update(
                            status="manual",
                            source=best_key,
                            proposed=str(value),
                            confidence=best_score,
                            reason="Mapped file path does not exist.",
                        )
                    else:
                        result.update(
                            status="safe",
                            source=best_key,
                            proposed=str(path),
                            confidence=best_score,
                            reason="Verified local document path.",
                        )
                else:
                    result.update(
                        status="safe",
                        source=best_key,
                        proposed=str(value),
                        confidence=best_score,
                        reason="Mapped to a non-empty verified profile field.",
                    )
            else:
                result.update(
                    status="missing",
                    source=best_key,
                    confidence=best_score,
                    reason=f"Profile field {best_key!r} is empty.",
                )
        return result

    def map_all(self, fields: list[dict[str, Any]]) -> list[dict[str, Any]]:
        return [self.map_field(field) for field in fields]


class BrowserWorker(threading.Thread):
    """Owns Playwright on one dedicated thread."""

    def __init__(self, event_queue: queue.Queue[dict[str, Any]], user_data_dir: Path) -> None:
        super().__init__(daemon=True)
        self.events = event_queue
        self.commands: queue.Queue[dict[str, Any]] = queue.Queue()
        self.user_data_dir = user_data_dir
        self.stop_flag = threading.Event()
        self.playwright = None
        self.context = None
        self.page = None

    def send(self, command: str, **payload: Any) -> None:
        self.commands.put({"command": command, **payload})

    def emit(self, kind: str, **payload: Any) -> None:
        self.events.put({"source": "browser", "kind": kind, **payload})

    def run(self) -> None:
        while not self.stop_flag.is_set():
            try:
                item = self.commands.get(timeout=0.2)
            except queue.Empty:
                continue
            command = item.get("command")
            try:
                if command == "start":
                    self._start_browser(item.get("browser", "chrome"))
                elif command == "navigate":
                    self._ensure_started()
                    url = str(item.get("url", "")).strip()
                    if not re.match(r"^https?://", url, re.I):
                        url = "https://" + url
                    self.page.goto(url, wait_until="domcontentloaded", timeout=90000)
                    self.emit("navigated", url=self.page.url, title=self.page.title())
                elif command == "inspect":
                    self._ensure_started()
                    self._inspect()
                elif command == "fill":
                    self._ensure_started()
                    self._fill(item["mapping"])
                elif command == "focus":
                    self._ensure_started()
                    self._focus(item["mapping"])
                elif command == "page_text":
                    self._ensure_started()
                    text = self.page.locator("body").inner_text(timeout=15000)
                    self.emit("page_text", text=text[:50000], url=self.page.url)
                elif command == "screenshot":
                    self._ensure_started()
                    path = Path(item["path"])
                    path.parent.mkdir(parents=True, exist_ok=True)
                    self.page.screenshot(path=str(path), full_page=True)
                    self.emit("screenshot_saved", path=str(path))
                elif command == "close":
                    self._close_browser()
                elif command == "shutdown":
                    self._close_browser()
                    self.stop_flag.set()
                else:
                    self.emit("error", message=f"Unknown browser command: {command}")
            except Exception as exc:
                self.emit("error", message=f"{type(exc).__name__}: {exc}", command=command)

        self._close_browser()

    def _start_browser(self, browser_choice: str) -> None:
        if self.context:
            self.emit("started", url=self.page.url if self.page else "")
            return
        try:
            from playwright.sync_api import sync_playwright
        except ImportError as exc:
            raise RuntimeError(
                "Playwright is not installed. Use Setup > Install Python dependencies."
            ) from exc

        self.user_data_dir.mkdir(parents=True, exist_ok=True)
        self.playwright = sync_playwright().start()
        kwargs = {
            "user_data_dir": str(self.user_data_dir),
            "headless": False,
            "no_viewport": True,
            "accept_downloads": False,
            "args": ["--disable-blink-features=AutomationControlled"],
        }
        if browser_choice == "chrome":
            try:
                self.context = self.playwright.chromium.launch_persistent_context(
                    channel="chrome", **kwargs
                )
            except Exception:
                self.context = self.playwright.chromium.launch_persistent_context(**kwargs)
        else:
            self.context = self.playwright.chromium.launch_persistent_context(**kwargs)
        self.page = self.context.pages[0] if self.context.pages else self.context.new_page()
        self.emit("started", url=self.page.url, browser=browser_choice)

    def _ensure_started(self) -> None:
        if not self.context or not self.page:
            self._start_browser("chrome")

    def _inspect(self) -> None:
        all_fields: list[dict[str, Any]] = []
        frames = list(self.page.frames)
        for frame_index, frame in enumerate(frames):
            try:
                fields = frame.evaluate(FIELD_DISCOVERY_JS)
                for field in fields:
                    field["frame_index"] = frame_index
                    field["frame_url"] = frame.url
                all_fields.extend(fields)
            except Exception:
                continue
        self.emit(
            "inspected",
            fields=all_fields,
            url=self.page.url,
            title=self.page.title(),
        )

    def _frame_for(self, mapping: dict[str, Any]):
        frames = list(self.page.frames)
        index = int(mapping.get("frame_index", 0))
        if 0 <= index < len(frames):
            return frames[index]
        return self.page.main_frame

    def _fill(self, mapping: dict[str, Any]) -> None:
        frame = self._frame_for(mapping)
        token = mapping["token"]
        locator = frame.locator(f'[data-ojas-id="{token}"]')
        field_type = mapping.get("type", "")
        value = str(mapping.get("proposed", ""))
        if field_type == "file":
            locator.set_input_files(value)
        elif mapping.get("tag") == "select":
            options = mapping.get("options", [])
            selected = None
            value_lower = value.strip().lower()
            for option in options:
                if str(option.get("value", "")).strip().lower() == value_lower:
                    selected = {"value": str(option.get("value", ""))}
                    break
                if str(option.get("text", "")).strip().lower() == value_lower:
                    selected = {"label": str(option.get("text", ""))}
                    break
            if selected:
                locator.select_option(**selected)
            else:
                locator.select_option(label=value)
        else:
            locator.fill(value)
        self.emit(
            "filled",
            token=token,
            source=mapping.get("source", ""),
            value="<file>" if field_type == "file" else value,
        )

    def _focus(self, mapping: dict[str, Any]) -> None:
        frame = self._frame_for(mapping)
        token = mapping["token"]
        locator = frame.locator(f'[data-ojas-id="{token}"]')
        locator.scroll_into_view_if_needed()
        locator.focus()
        locator.evaluate(
            """el => {
                el.style.outline = '4px solid #ff9800';
                el.style.outlineOffset = '2px';
                setTimeout(() => {
                    el.style.outline = '';
                    el.style.outlineOffset = '';
                }, 3500);
            }"""
        )
        self.emit("focused", token=token)

    def _close_browser(self) -> None:
        try:
            if self.context:
                self.context.close()
        except Exception:
            pass
        self.context = None
        self.page = None
        try:
            if self.playwright:
                self.playwright.stop()
        except Exception:
            pass
        self.playwright = None
        self.emit("stopped")
