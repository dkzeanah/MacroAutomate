"""Minimal OpenAI-compatible chat client (DeepSeek by default), standard library only.

The API key is resolved here, never passed through request files: the
``DEEPSEEK_API_KEY`` environment variable first, then the same Windows
Credential Manager entry the AutoHotkey app uses (``MacroAutomator/DeepSeek``).
"""
from __future__ import annotations

import json
import os
import random
import socket
import time
import urllib.error
import urllib.request
from dataclasses import dataclass

CREDENTIAL_TARGETS = ("MacroAutomator/DeepSeek", "Cutline/DeepSeek")
DEFAULT_ENDPOINT = "https://api.deepseek.com"
DEFAULT_MODEL = "deepseek-v4-pro"
DEFAULT_PRICES = {"deepseek-v4-pro": (1.32, 3.96), "deepseek-flash": (0.30, 1.20)}


class LLMError(RuntimeError):
    pass


def windows_credential(target: str) -> str:
    if os.name != "nt":
        return ""
    import ctypes
    from ctypes import wintypes

    class Credential(ctypes.Structure):
        _fields_ = [("Flags", wintypes.DWORD), ("Type", wintypes.DWORD), ("TargetName", wintypes.LPWSTR),
                    ("Comment", wintypes.LPWSTR), ("LastWritten", wintypes.FILETIME),
                    ("CredentialBlobSize", wintypes.DWORD), ("CredentialBlob", ctypes.POINTER(ctypes.c_ubyte)),
                    ("Persist", wintypes.DWORD), ("AttributeCount", wintypes.DWORD), ("Attributes", ctypes.c_void_p),
                    ("TargetAlias", wintypes.LPWSTR), ("UserName", wintypes.LPWSTR)]

    advapi = ctypes.WinDLL("advapi32", use_last_error=True)
    advapi.CredReadW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                                 ctypes.POINTER(ctypes.POINTER(Credential))]
    advapi.CredFree.argtypes = [ctypes.c_void_p]
    pointer = ctypes.POINTER(Credential)()
    if not advapi.CredReadW(target, 1, 0, ctypes.byref(pointer)):
        return ""
    try:
        raw = ctypes.string_at(pointer.contents.CredentialBlob, pointer.contents.CredentialBlobSize)
        try:
            return raw.decode("utf-16-le" if raw[1:2] == b"\x00" else "utf-8").rstrip("\x00").strip()
        except UnicodeError:
            return ""
    finally:
        advapi.CredFree(pointer)


def resolve_key() -> tuple[str, str]:
    value = os.environ.get("DEEPSEEK_API_KEY", "").strip()
    if value:
        return value, "environment"
    for target in CREDENTIAL_TARGETS:
        value = windows_credential(target)
        if value:
            return value, f"Windows Credential Manager ({target})"
    return "", "not configured"


@dataclass
class Completion:
    text: str
    model: str
    prompt_tokens: int
    completion_tokens: int
    cost_usd: float


class ChatClient:
    def __init__(self, endpoint: str = DEFAULT_ENDPOINT, model: str = DEFAULT_MODEL, key: str | None = None,
                 timeout: float = 90.0, prices: dict | None = None, budget_usd: float | None = None,
                 transport=None):
        self.endpoint = (endpoint or DEFAULT_ENDPOINT).rstrip("/")
        self.model = model or DEFAULT_MODEL
        self.key = key if key is not None else resolve_key()[0]
        self.timeout = timeout
        self.prices = {**DEFAULT_PRICES, **(prices or {})}
        self.budget_usd = budget_usd
        self.spent_usd = 0.0
        self.transport = transport or self._post
        if not self.endpoint.startswith("https://") and not self.endpoint.startswith(("http://127.0.0.1", "http://localhost")):
            raise LLMError("The model endpoint must use https (or a local loopback address)")

    @property
    def available(self) -> bool:
        return bool(self.key)

    def estimate(self, prompt_chars: int, max_tokens: int) -> float:
        price_in, price_out = self.prices.get(self.model, (2.0, 6.0))
        return (prompt_chars / 3.5) / 1e6 * price_in + max_tokens / 1e6 * price_out

    def complete(self, messages: list[dict], *, max_tokens: int = 2500, json_mode: bool = True,
                 temperature: float = 0.1) -> Completion:
        if not self.key:
            raise LLMError("No DeepSeek API key is configured (Study Assistant > provider key)")
        reserve = self.estimate(sum(len(m.get("content", "")) for m in messages), max_tokens)
        if self.budget_usd is not None and self.spent_usd + reserve > self.budget_usd:
            raise LLMError(f"This request could exceed the remaining model budget (${self.budget_usd:.2f})")
        body = {"model": self.model, "messages": messages, "max_tokens": max_tokens, "temperature": temperature,
                "stream": False}
        if json_mode:
            body["response_format"] = {"type": "json_object"}
        payload = self._with_retries(body)
        try:
            text = payload["choices"][0]["message"]["content"] or ""
        except (KeyError, IndexError, TypeError):
            raise LLMError("The model response had no message content") from None
        usage = payload.get("usage") or {}
        prompt_tokens = int(usage.get("prompt_tokens", 0) or 0)
        completion_tokens = int(usage.get("completion_tokens", 0) or 0)
        price_in, price_out = self.prices.get(self.model, (2.0, 6.0))
        cost = prompt_tokens / 1e6 * price_in + completion_tokens / 1e6 * price_out
        self.spent_usd += cost
        return Completion(text, str(payload.get("model", self.model)), prompt_tokens, completion_tokens, round(cost, 6))

    def _with_retries(self, body: dict, attempts: int = 3) -> dict:
        delay = 1.0
        for attempt in range(1, attempts + 1):
            try:
                return self.transport(f"{self.endpoint}/chat/completions", body)
            except LLMError as error:
                retryable = getattr(error, "retryable", False)
                if not retryable or attempt == attempts:
                    raise
            time.sleep(delay + random.random() * 0.3)
            delay *= 2
        raise LLMError("unreachable")

    def _post(self, url: str, body: dict) -> dict:
        request = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"), method="POST",
                                         headers={"Content-Type": "application/json", "Authorization": f"Bearer {self.key}"})
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            detail = ""
            try:
                detail = json.loads(error.read().decode("utf-8", "replace")).get("error", {}).get("message", "")
            except (ValueError, AttributeError):
                pass
            failure = LLMError(f"Model API returned HTTP {error.code}{': ' + detail[:200] if detail else ''}")
            failure.retryable = error.code in (408, 409, 429, 500, 502, 503, 504)
            raise failure from None
        except (urllib.error.URLError, socket.timeout, TimeoutError, ConnectionError) as error:
            failure = LLMError(f"Could not reach the model API: {getattr(error, 'reason', error)}")
            failure.retryable = True
            raise failure from None
        except ValueError:
            raise LLMError("The model API returned invalid JSON") from None
