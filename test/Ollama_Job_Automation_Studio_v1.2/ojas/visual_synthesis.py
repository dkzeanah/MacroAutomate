from __future__ import annotations

import json
import random
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path
from typing import Any, Callable


class ComfyUIError(RuntimeError):
    pass


class ComfyUIClient:
    """Small dependency-free client for a local ComfyUI server."""

    def __init__(self, base_url: str = "http://127.0.0.1:8188", timeout: int = 60) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    def _request(
        self,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        timeout: int | None = None,
    ) -> bytes:
        body = None
        headers = {"Accept": "application/json"}
        if payload is not None:
            body = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            self.base_url + path,
            data=body,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout or self.timeout) as response:
                return response.read()
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise ComfyUIError(f"HTTP {exc.code}: {detail or exc.reason}") from exc
        except urllib.error.URLError as exc:
            raise ComfyUIError(
                f"Cannot reach ComfyUI at {self.base_url}. Start ComfyUI and verify the URL. "
                f"{exc.reason}"
            ) from exc

    def get_json(self, path: str, timeout: int | None = None) -> dict[str, Any]:
        raw = self._request("GET", path, timeout=timeout)
        try:
            value = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError as exc:
            raise ComfyUIError(f"ComfyUI returned invalid JSON for {path}: {exc}") from exc
        return value if isinstance(value, dict) else {"value": value}

    def post_json(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        raw = self._request("POST", path, payload=payload)
        try:
            value = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError as exc:
            raise ComfyUIError(f"ComfyUI returned invalid JSON for {path}: {exc}") from exc
        return value if isinstance(value, dict) else {"value": value}

    def test(self) -> dict[str, Any]:
        try:
            return self.get_json("/system_stats", timeout=10)
        except Exception:
            return self.get_json("/object_info", timeout=20)

    def checkpoints(self) -> list[str]:
        data = self.get_json("/object_info/CheckpointLoaderSimple", timeout=20)
        node = data.get("CheckpointLoaderSimple", data)
        required = node.get("input", {}).get("required", {}) if isinstance(node, dict) else {}
        ckpt_spec = required.get("ckpt_name", [])
        if isinstance(ckpt_spec, list) and ckpt_spec:
            first = ckpt_spec[0]
            if isinstance(first, list):
                return [str(item) for item in first]
        return []

    def queue_workflow(self, workflow: dict[str, Any]) -> str:
        response = self.post_json(
            "/prompt",
            {
                "prompt": workflow,
                "client_id": str(uuid.uuid4()),
            },
        )
        prompt_id = response.get("prompt_id")
        if not prompt_id:
            raise ComfyUIError(f"ComfyUI did not return a prompt_id: {response}")
        return str(prompt_id)

    def wait_for_images(
        self,
        prompt_id: str,
        *,
        timeout: int = 900,
        poll_interval: float = 1.0,
        progress: Callable[[str], None] | None = None,
    ) -> list[dict[str, str]]:
        deadline = time.monotonic() + timeout
        last_message = 0.0
        while time.monotonic() < deadline:
            history = self.get_json(f"/history/{urllib.parse.quote(prompt_id)}", timeout=30)
            entry = history.get(prompt_id)
            if isinstance(entry, dict):
                outputs = entry.get("outputs", {})
                images: list[dict[str, str]] = []
                if isinstance(outputs, dict):
                    for output in outputs.values():
                        if not isinstance(output, dict):
                            continue
                        for image in output.get("images", []) or []:
                            if isinstance(image, dict) and image.get("filename"):
                                images.append(
                                    {
                                        "filename": str(image.get("filename", "")),
                                        "subfolder": str(image.get("subfolder", "")),
                                        "type": str(image.get("type", "output")),
                                    }
                                )
                if images:
                    return images
                status = entry.get("status", {})
                if isinstance(status, dict) and status.get("status_str") == "error":
                    raise ComfyUIError(f"ComfyUI workflow failed: {status}")
            if progress and time.monotonic() - last_message > 5:
                progress("Waiting for ComfyUI generation to finish...")
                last_message = time.monotonic()
            time.sleep(poll_interval)
        raise TimeoutError(f"ComfyUI did not finish prompt {prompt_id} within {timeout} seconds.")

    def download_image(self, descriptor: dict[str, str], destination: Path) -> Path:
        query = urllib.parse.urlencode(
            {
                "filename": descriptor.get("filename", ""),
                "subfolder": descriptor.get("subfolder", ""),
                "type": descriptor.get("type", "output"),
            }
        )
        data = self._request("GET", f"/view?{query}", timeout=120)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        return destination


def build_txt2img_workflow(
    *,
    checkpoint: str,
    positive_prompt: str,
    negative_prompt: str,
    width: int = 512,
    height: int = 512,
    steps: int = 20,
    cfg: float = 7.0,
    seed: int | None = None,
    filename_prefix: str = "OJAS_visual_synthesis",
) -> dict[str, Any]:
    if not checkpoint.strip():
        raise ValueError("Choose a ComfyUI checkpoint before generating.")
    seed_value = seed if seed is not None and seed >= 0 else random.randint(0, 2**63 - 1)
    width = max(256, min(2048, int(width)))
    height = max(256, min(2048, int(height)))
    # Most latent diffusion checkpoints work best with dimensions divisible by 8.
    width -= width % 8
    height -= height % 8
    return {
        "3": {
            "class_type": "KSampler",
            "inputs": {
                "cfg": float(cfg),
                "denoise": 1,
                "latent_image": ["5", 0],
                "model": ["4", 0],
                "negative": ["7", 0],
                "positive": ["6", 0],
                "sampler_name": "euler",
                "scheduler": "normal",
                "seed": int(seed_value),
                "steps": max(1, min(100, int(steps))),
            },
        },
        "4": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": checkpoint.strip()},
        },
        "5": {
            "class_type": "EmptyLatentImage",
            "inputs": {"batch_size": 1, "height": height, "width": width},
        },
        "6": {
            "class_type": "CLIPTextEncode",
            "inputs": {"clip": ["4", 1], "text": positive_prompt.strip()},
        },
        "7": {
            "class_type": "CLIPTextEncode",
            "inputs": {"clip": ["4", 1], "text": negative_prompt.strip()},
        },
        "8": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["3", 0], "vae": ["4", 2]},
        },
        "9": {
            "class_type": "SaveImage",
            "inputs": {"filename_prefix": filename_prefix, "images": ["8", 0]},
        },
    }


def analyze_references(
    ollama_client: Any,
    image_paths: list[Path],
    *,
    vision_model: str,
    goal: str,
    progress: Callable[[str], None] | None = None,
) -> list[dict[str, str]]:
    analyses: list[dict[str, str]] = []
    prompt = (
        "Analyze this reference image for a new-image synthesis task. Describe only visible, "
        "non-identifying visual information: subject/category, composition, geometry, camera or "
        "viewpoint, lighting, palette, materials, texture, typography if present, repeated motifs, "
        "and what is distinctive. Separate high-confidence observations from uncertainty. "
        "Do not identify real people. The user's generation goal is:\n" + (goal or "Create a novel related image.")
    )
    for index, path in enumerate(image_paths, start=1):
        if progress:
            progress(f"Analyzing reference {index}/{len(image_paths)}: {path.name}")
        response = ollama_client.chat(
            model=vision_model,
            prompt=prompt,
            system=(
                "You are a visual design analyst. Extract reusable design information while "
                "avoiding claims about identity and avoiding unsupported details."
            ),
            image_path=str(path),
            temperature=0.1,
            num_ctx=8192,
            keep_alive="5m",
        )
        content = str(response.get("message", {}).get("content", "")).strip()
        analyses.append({"image": str(path), "analysis": content})
    return analyses


def synthesize_generation_prompt(
    ollama_client: Any,
    analyses: list[dict[str, str]],
    *,
    text_model: str,
    goal: str,
    negative_prompt: str,
) -> dict[str, str]:
    observations = "\n\n".join(
        f"REFERENCE {index}: {Path(item['image']).name}\n{item['analysis']}"
        for index, item in enumerate(analyses, start=1)
    )
    prompt = (
        "Create one novel image-generation prompt from the reference analyses below. Infer the "
        "shared visual language, preserve useful recurring principles, and design a new composition "
        "rather than copying any one reference. Resolve contradictions by favoring patterns shared "
        "by several references. Do not request a real person's identity or an exact copyrighted "
        "character.\n\n"
        f"USER GOAL:\n{goal or 'Create a new related image.'}\n\n"
        f"REFERENCE ANALYSES:\n{observations}\n\n"
        "Return strict JSON with exactly these string fields: positive_prompt, negative_prompt, "
        "design_summary. The positive prompt should be concrete and suitable for a diffusion model. "
        f"Begin the negative prompt with these user exclusions when present: {negative_prompt!r}."
    )
    response = ollama_client.chat(
        model=text_model,
        prompt=prompt,
        system=(
            "You are a prompt synthesizer for a local image-generation pipeline. Output valid JSON "
            "only and create a genuinely new composition from high-confidence visual patterns."
        ),
        temperature=0.35,
        num_ctx=12288,
        keep_alive="5m",
    )
    content = str(response.get("message", {}).get("content", "")).strip()
    # Tolerate Markdown fences while still requiring a JSON object.
    content = content.removeprefix("```json").removeprefix("```").removesuffix("```").strip()
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        return {
            "positive_prompt": content,
            "negative_prompt": negative_prompt,
            "design_summary": "The model did not return structured JSON; raw output was used as the prompt.",
        }
    return {
        "positive_prompt": str(data.get("positive_prompt", "")).strip(),
        "negative_prompt": str(data.get("negative_prompt", negative_prompt)).strip(),
        "design_summary": str(data.get("design_summary", "")).strip(),
    }
