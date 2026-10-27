"""OpenAI-compatible provider: Ollama, OpenAI, DeepSeek, LM Studio, vLLM, etc."""
from __future__ import annotations

import base64
import tempfile
import time
from typing import Any, Callable, Optional

import requests

from ..utils import bounded_retry
from .base import Completion, Provider, ProviderError

_JPEG = b"\xff\xd8\xff"
_PNG = b"\x89PNG\r\n\x1a\n"


def _guess_mime(data: bytes) -> str:
    if data.startswith(_PNG):
        return "image/png"
    if data.startswith(_JPEG):
        return "image/jpeg"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    return "image/png"


class OpenAICompatProvider(Provider):
    """Talks to any OpenAI-compatible /v1 endpoint.

    Works with: Ollama (http://localhost:11434/v1), OpenAI, DeepSeek,
    LM Studio, vLLM, llama.cpp server, and most self-hosted stacks.
    """

    kind = "openai_compat"

    def __init__(
        self,
        name: str,
        model: str,
        base_url: str,
        api_key: str = "not-needed",
        tier: str = "local",
        tags: Optional[list[str]] = None,
        capabilities: Optional[list[str]] = None,
        embed_model: Optional[str] = None,
        stt_model: Optional[str] = None,
        timeout: float = 120.0,
        extra: Optional[dict] = None,
        **kwargs: Any,
    ) -> None:
        super().__init__(**kwargs)
        self.name = name
        self.model = model
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.tier = tier
        self.tags = tags or []
        self.embed_model = embed_model
        self.stt_model = stt_model
        self.timeout = timeout
        self.extra = extra or {}
        caps = {"text"}
        if capabilities:
            caps |= set(capabilities)
        elif "api.openai.com" in base_url:
            caps |= {"audio"}  # OpenAI endpoints expose /v1/audio
        self.capabilities = caps
        self._client = None

    # -- client -----------------------------------------------------------
    @property
    def client(self):
        if self._client is None:
            try:
                from openai import OpenAI
            except ImportError as exc:  # pragma: no cover
                raise ProviderError("openai package not installed") from exc
            self._client = OpenAI(base_url=self.base_url, api_key=self.api_key, timeout=self.timeout, **self.extra)
        return self._client

    # -- chat -------------------------------------------------------------
    def chat(
        self,
        messages: list[dict],
        stream: bool = False,
        on_token: Optional[Callable[[str], None]] = None,
        temperature: Optional[float] = None,
        max_tokens: Optional[int] = None,
        **kwargs: Any,
    ) -> Completion:
        params: dict = {"model": self.model, "messages": messages, **kwargs}
        if temperature is not None:
            params["temperature"] = temperature
        if max_tokens:
            params["max_tokens"] = max_tokens

        def call() -> Completion:
            if stream:
                parts: list[str] = []
                for chunk in self.client.chat.completions.create(**params, stream=True):
                    delta = chunk.choices[0].delta.content if chunk.choices else None
                    if delta:
                        parts.append(delta)
                        if on_token:
                            on_token(delta)
                return Completion(text="".join(parts), model=self.model, finish_reason="stop")
            resp = self.client.chat.completions.create(**params)
            msg = resp.choices[0].message
            return Completion(
                text=msg.content or "",
                model=resp.model or self.model,
                finish_reason=resp.choices[0].finish_reason,
                usage={
                    "prompt_tokens": getattr(resp.usage, "prompt_tokens", None),
                    "completion_tokens": getattr(resp.usage, "completion_tokens", None),
                },
                raw=resp,
            )

        try:
            return bounded_retry(call, retries=2, delay=1.0, log=None)
        except Exception as exc:  # noqa: BLE001
            raise ProviderError(f"{self.name}: chat failed: {exc}") from exc

    # -- embed ------------------------------------------------------------
    def embed(self, texts: list[str]) -> Optional[list[list[float]]]:
        if not self.embed_model and self.model in (None, ""):
            return None
        model = self.embed_model or self.model
        try:
            resp = self.client.embeddings.create(model=model, input=texts)
            vecs = [d.embedding for d in resp.data]
            return vecs
        except Exception:  # noqa: BLE001
            if self.embed_model:
                return None  # explicit embed model configured but failing
            # Model may be a chat model without embeddings; don't crash.
            return None

    # -- vision -----------------------------------------------------------
    def vision(self, image_bytes: bytes, prompt: str = "Describe this image.") -> Optional[str]:
        if "vision" not in self.capabilities:
            return None
        data_uri = f"data:{_guess_mime(image_bytes)};base64," + base64.b64encode(image_bytes).decode()
        messages = [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {"type": "image_url", "image_url": {"url": data_uri}},
                ],
            }
        ]
        try:
            return self.chat(messages).text
        except ProviderError:
            return None

    # -- transcribe -------------------------------------------------------
    def transcribe(self, audio_bytes: bytes, filename: str = "audio.wav") -> Optional[str]:
        if "audio" not in self.capabilities or not self.stt_model:
            return None
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as fh:
            fh.write(audio_bytes)
            tmp = fh.name
        try:
            with open(tmp, "rb") as fh:
                resp = self.client.audio.transcriptions.create(model=self.stt_model, file=fh)
            return resp.text if hasattr(resp, "text") else str(resp)
        except Exception:  # noqa: BLE001
            return None
        finally:
            import os

            try:
                os.unlink(tmp)
            except OSError:
                pass

    # -- health -----------------------------------------------------------
    def _probe(self) -> bool:
        try:
            resp = requests.get(
                f"{self.base_url}/models",
                headers={"Authorization": f"Bearer {self.api_key}"},
                timeout=3.0,
            )
            return resp.status_code == 200
        except Exception:  # noqa: BLE001
            return False

    def __repr__(self) -> str:  # pragma: no cover
        return f"<openai_compat {self.name} {self.base_url} model={self.model} tier={self.tier}>"
