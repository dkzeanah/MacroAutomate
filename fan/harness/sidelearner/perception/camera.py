"""Camera watcher: always-on (when enabled) low-rate frame capture, local-only."""
from __future__ import annotations

import logging
from pathlib import Path
from typing import Any, Optional

import numpy as np

from ..events import EventBus
from ..utils import now_ms
from .base import WatcherBase
from .screen import image_bytes
from .vision import describe_image

log = logging.getLogger("sidelearner.perception.camera")


class CameraWatcher(WatcherBase):
    kind = "camera"

    def __init__(self, bus: EventBus, config: Any, vault: Path, provider: Optional[Any] = None) -> None:
        cfg = config.get("perception.camera", {})
        super().__init__(bus, config, interval=float(cfg.get("interval_s", 2.0)))
        self.cfg = cfg
        self.vault = Path(vault) / "camera"
        self.vault.mkdir(parents=True, exist_ok=True)
        self.index = int(cfg.get("index", 0))
        self.max_images = int(cfg.get("max_images", 100))
        self.face_detect = bool(cfg.get("face_detect", False))
        self.vision_enabled = bool((cfg.get("vision") or {}).get("enabled", False))
        self.vision_prompt = str((cfg.get("vision") or {}).get("prompt", "Describe this camera frame briefly."))
        self.provider = provider
        self._cap = None
        self._cascade = None

    def _setup(self) -> bool:
        try:
            import cv2  # type: ignore

            self._cv2 = cv2
            cap = cv2.VideoCapture(self.index, cv2.CAP_DSHOW)
            if not cap.isOpened():
                cap = cv2.VideoCapture(self.index)  # fallback backend
            if not cap.isOpened():
                self.error = f"camera {self.index} not available"
                return False
            # Warm up: first frames are often black/underexposed.
            for _ in range(3):
                cap.read()
            self._cap = cap
            if self.face_detect:
                cascade_path = str(Path(cv2.data.haarcascades) / "haarcascade_frontalface_default.xml")
                self._cascade = cv2.CascadeClassifier(cascade_path)
                if self._cascade.empty():
                    self._cascade = None
            return True
        except ImportError as exc:
            self.error = f"opencv not installed ({exc})"
            return False
        except Exception as exc:  # noqa: BLE001
            self.error = f"camera setup failed: {exc}"
            return False

    def _teardown(self) -> None:
        if self._cap is not None:
            self._cap.release()

    def _tick(self) -> None:
        ok, frame = self._cap.read()
        if not ok or frame is None:
            return
        # Downscale for storage economy.
        h, w = frame.shape[:2]
        if w > 640:
            frame = self._cv2.resize(frame, (640, int(h * 640 / w)))
        ok, jpg = self._cv2.imencode(".jpg", frame, [int(self._cv2.IMWRITE_JPEG_QUALITY), 80])
        if not ok:
            return
        path = self.vault / f"{now_ms()}.jpg"
        path.write_bytes(jpg.tobytes())
        self._roll(self.vault, self.max_images)
        data = {"image_path": str(path), "width": frame.shape[1], "height": frame.shape[0]}
        if self._cascade is not None:
            gray = self._cv2.cvtColor(frame, self._cv2.COLOR_BGR2GRAY)
            faces = self._cascade.detectMultiScale(gray, 1.2, 4)
            data["faces"] = int(len(faces))
        self.bus.emit("perception.camera.frame", data, source="camera")
        if self.vision_enabled and "vision" in getattr(self.provider, "capabilities", set()):
            try:
                desc = describe_image(self.provider, jpg.tobytes(), self.vision_prompt)
                if desc:
                    self.bus.emit("perception.camera.vision", {"description": desc, "image_path": str(path)}, source="camera")
            except Exception as exc:  # noqa: BLE001
                log.warning("camera vision failed: %s", exc)

    @staticmethod
    def _roll(directory: Path, keep: int) -> None:
        files = sorted(directory.glob("*.jpg"), key=lambda p: p.stat().st_mtime, reverse=True)
        for stale in files[keep:]:
            try:
                stale.unlink()
            except OSError:
                pass

    def capture_now(self) -> Optional[Path]:
        """One-shot frame grab (used by CLI/demos)."""
        if self._cap is None and not self._setup():
            return None
        ok, frame = self._cap.read()
        if not ok:
            return None
        ok, jpg = self._cv2.imencode(".jpg", frame, [int(self._cv2.IMWRITE_JPEG_QUALITY), 85])
        path = self.vault / f"now_{now_ms()}.jpg"
        path.write_bytes(jpg.tobytes())
        return path
