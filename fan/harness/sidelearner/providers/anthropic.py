"""Anthropic Messages API provider (Claude models) via plain requests."""
from __future__ import annotations

import base64
from typing import Any, Callable, Optional

import requests

from .base import Completion, Provider, ProviderError

_API_URL = "https://api.anthropic.com/v1/messages"
_API_VERSION = "2023-06-01"


class AnthropicProvider(Provider):
    kind = "anthropic"

    def __init__(
        self,
        name: str,
        model: str,
        api_key: str,
        tier: str = "best",
        tags: Optional[list[str]] = None,
        capabilities: Optional[list[str]] = None,
        timeout: float = 120.0,
        **kwargs: Any,
    ) -> None:
        super().__init__(**kwargs)
        self.name = name
        self.model = model
        self.api_key = api_key
        self.tier = tier
        self.tags = tags or []
        self.timeout = timeout
        self.capabilities = {"text"} | (set(capabilities) if capabilities else set())

    def _headers(self) -> dict:
        return {
            "x-api-key": self.api_key,
            "anthropic-version": _API_VERSION,
            "content-type": "application/json",
        }

    def chat(
        self,
        messages: list[dict],
        stream: bool = False,
        on_token: Optional[Callable[[str], None]] = None,
        temperature: Optional[float] = None,
        max_tokens: Optional[int] = None,
        **kwargs: Any,
    ) -> Completion:
        if stream:
            return self._chat_stream(messages, on_token, temperature, max_tokens)
        payload: dict = {"model": self.model, "messages": messages, "max_tokens": max_tokens or 2048, **kwargs}
        if temperature is not None:
            payload["temperature"] = temperature
        try:
            resp = requests.post(_API_URL, headers=self._headers(), json=payload, timeout=self.timeout)
            if resp.status_code >= 400:
                raise ProviderError(f"{self.name}: HTTP {resp.status_code}: {resp.text[:300]}")
            body = resp.json()
            text = "".join(b.get("text", "") for b in body.get("content", []) if b.get("type") == "text")
            return Completion(
                text=text,
                model=body.get("model", self.model),
                finish_reason=body.get("stop_reason"),
                usage=body.get("usage", {}),
                raw=body,
            )
        except ProviderError:
            raise
        except Exception as exc:  # noqa: BLE001
            raise ProviderError(f"{self.name}: chat failed: {exc}") from exc

    def _chat_stream(
        self,
        messages: list[dict],
        on_token: Optional[Callable[[str], None]],
        temperature: Optional[float],
        max_tokens: Optional[int],
    ) -> Completion:
        payload: dict = {
            "model": self.model,
            "messages": messages,
            "max_tokens": max_tokens or 2048,
            "stream": True,
        }
        if temperature is not None:
            payload["temperature"] = temperature
        parts: list[str] = []
        try:
            with requests.post(
                _API_URL, headers=self._headers(), json=payload, timeout=self.timeout, stream=True
            ) as resp:
                if resp.status_code >= 400:
                    raise ProviderError(f"{self.name}: HTTP {resp.status_code}: {resp.text[:300]}")
                for line in resp.iter_lines(decode_unicode=True):
                    if not line or not line.startswith("data:"):
                        continue
                    chunk = line[5:].strip()
                    if chunk == "[DONE]":
                        break
                    import json

                    try:
                        ev = json.loads(chunk)
                    except ValueError:
                        continue
                    if ev.get("type") == "content_block_delta":
                        text = ev.get("delta", {}).get("text", "")
                        if text:
                            parts.append(text)
                            if on_token:
                                on_token(text)
        except ProviderError:
            raise
        except Exception as exc:  # noqa: BLE001
            raise ProviderError(f"{self.name}: stream failed: {exc}") from exc
        return Completion(text="".join(parts), model=self.model, finish_reason="stop")

    def vision(self, image_bytes: bytes, prompt: str = "Describe this image.") -> Optional[str]:
        if "vision" not in self.capabilities:
            return None
        data_uri = "data:image/png;base64," + base64.b64encode(image_bytes).decode()
        messages = [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": data_uri.split(",", 1)[1]}},
                ],
            }
        ]
        try:
            return self.chat(messages).text
        except ProviderError:
            return None

    def _probe(self) -> bool:
        if self.api_key in ("", "${ANTHROPIC_API_KEY}"):
            return False
        try:
            resp = requests.get(
                "https://api.anthropic.com/v1/models", headers=self._headers(), timeout=3.0
            )
            return resp.status_code == 200
        except Exception:  # noqa: BLE001
            return False
