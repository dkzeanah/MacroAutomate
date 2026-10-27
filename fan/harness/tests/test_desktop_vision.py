"""Tests for vision-guided desktop element detection."""
from __future__ import annotations

import pytest
from PIL import Image

from sidelearner.tools.desktop_vision import _extract_json, find_element


def _fake_screen():
    return Image.new("RGB", (100, 100), color=(30, 30, 30))


class FakeVisionProvider:
    kind = "fake"
    capabilities = {"text", "vision"}

    def __init__(self, response: str = ""):
        self.response = response
        self.calls: list[tuple[bytes, str]] = []

    def vision(self, image_bytes: bytes, prompt: str) -> str:
        self.calls.append((image_bytes, prompt))
        return self.response


def test_extract_json_strips_fences():
    text = "```json\n{\"x\": 0.5, \"y\": 0.5}\n```"
    assert _extract_json(text) == {"x": 0.5, "y": 0.5}


def test_extract_json_raw():
    text = '{"x":0.1,"y":0.2,"w":0.3,"h":0.4}'
    assert _extract_json(text) == {"x": 0.1, "y": 0.2, "w": 0.3, "h": 0.4}


def test_extract_json_no_json_returns_none():
    assert _extract_json("just text") is None


def test_find_element_no_provider():
    result = find_element("the OK button", lambda: None)
    assert result["ok"] is False
    assert "no vision provider" in result["text"]


def test_find_element_provider_without_vision():
    class NoVision:
        capabilities = {"text"}

    result = find_element("the OK button", lambda: NoVision())
    assert result["ok"] is False
    assert "does not support vision" in result["text"]


def test_find_element_returns_coordinates(monkeypatch):
    provider = FakeVisionProvider('{"x": 0.25, "y": 0.75, "w": 0.1, "h": 0.05, "reason": "button"}')
    monkeypatch.setattr("sidelearner.tools.desktop_vision.grab_screen", _fake_screen)
    monkeypatch.setattr("sidelearner.tools.desktop_vision._screen_size", lambda: (1920, 1080))

    result = find_element("the OK button", lambda: provider)
    assert result["ok"] is True
    assert result["x"] == int(0.25 * 1920)
    assert result["y"] == int(0.75 * 1080)
    assert "OK button" in result["text"]


def test_find_element_not_found(monkeypatch):
    provider = FakeVisionProvider('{"found": false}')
    monkeypatch.setattr("sidelearner.tools.desktop_vision.grab_screen", _fake_screen)
    monkeypatch.setattr("sidelearner.tools.desktop_vision._screen_size", lambda: (1920, 1080))

    result = find_element("missing thing", lambda: provider)
    assert result["ok"] is False
    assert "not found" in result["text"]


def test_find_element_bad_json(monkeypatch):
    provider = FakeVisionProvider("I think it's near the top left")
    monkeypatch.setattr("sidelearner.tools.desktop_vision.grab_screen", _fake_screen)

    result = find_element("something", lambda: provider)
    assert result["ok"] is False
    assert "did not return JSON" in result["text"]
