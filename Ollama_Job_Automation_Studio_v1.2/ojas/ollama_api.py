from __future__ import annotations

import base64
import json
import mimetypes
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


class OllamaError(RuntimeError):
    pass


class OllamaClient:
    def __init__(self, base_url: str = "http://localhost:11434", timeout: int = 600) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    def _request(
        self,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        timeout: int | None = None,
    ) -> dict[str, Any]:
        url = self.base_url + path
        body = None
        headers = {"Accept": "application/json"}
        if payload is not None:
            body = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=timeout or self.timeout) as response:
                raw = response.read().decode("utf-8", errors="replace")
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise OllamaError(f"HTTP {exc.code}: {detail or exc.reason}") from exc
        except urllib.error.URLError as exc:
            raise OllamaError(
                f"Cannot reach Ollama at {self.base_url}. Start Ollama and try again. {exc.reason}"
            ) from exc
        except json.JSONDecodeError as exc:
            raise OllamaError(f"Ollama returned invalid JSON: {exc}") from exc

    def ping(self) -> dict[str, Any]:
        return self._request("GET", "/api/tags", timeout=10)

    def list_models(self) -> list[dict[str, Any]]:
        return self.ping().get("models", [])

    def running_models(self) -> list[dict[str, Any]]:
        return self._request("GET", "/api/ps", timeout=15).get("models", [])

    def chat(
        self,
        *,
        model: str,
        prompt: str,
        system: str = "",
        image_path: str = "",
        temperature: float = 0.2,
        num_ctx: int = 8192,
        keep_alive: str = "5m",
    ) -> dict[str, Any]:
        messages: list[dict[str, Any]] = []
        if system.strip():
            messages.append({"role": "system", "content": system.strip()})
        user_message: dict[str, Any] = {"role": "user", "content": prompt}
        if image_path:
            path = Path(image_path)
            if not path.exists():
                raise FileNotFoundError(path)
            mime, _ = mimetypes.guess_type(path.name)
            if not (mime or "").startswith("image/"):
                raise ValueError("The selected vision attachment is not recognized as an image.")
            user_message["images"] = [base64.b64encode(path.read_bytes()).decode("ascii")]
        messages.append(user_message)
        return self._request(
            "POST",
            "/api/chat",
            {
                "model": model,
                "messages": messages,
                "stream": False,
                "keep_alive": keep_alive,
                "options": {
                    "temperature": temperature,
                    "num_ctx": num_ctx,
                },
            },
        )

    def embed(self, model: str, inputs: str | list[str]) -> dict[str, Any]:
        return self._request(
            "POST",
            "/api/embed",
            {"model": model, "input": inputs, "truncate": True},
        )
