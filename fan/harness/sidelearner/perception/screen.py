"""Screen watcher: change-aware frame capture, window tracking, optional OCR."""
from __future__ import annotations

import io
import logging
from pathlib import Path
from typing import Any, Optional

import numpy as np
from PIL import Image

from ..events import EventBus
from ..utils import now_ms, sha1_hex
from .base import WatcherBase
from .ocr import ocr_text

log = logging.getLogger("sidelearner.perception.screen")


def grab_screen(monitor: int = 1) -> Optional[Image.Image]:
    """Capture the primary monitor as a PIL image (None on failure)."""
    try:
        import mss

        with mss.mss() as sct:
            mon = sct.monitors[monitor]
            shot = sct.grab(mon)
            return Image.frombytes("RGB", shot.size, shot.rgb)
    except Exception as exc:  # noqa: BLE001
        log.warning("screen grab failed: %s", exc)
        return None


def downscale(img: Image.Image, width: int = 960) -> Image.Image:
    if img.width > width:
        return img.resize((width, int(img.height * width / img.width)), Image.LANCZOS)
    return img


def change_signature(img: Image.Image) -> np.ndarray:
    """Small grayscale frame used to detect visual change cheaply."""
    small = img.convert("L").resize((64, 40), Image.BILINEAR)
    return np.asarray(small, dtype=np.float32) / 255.0


def frame_changed(prev: Optional[np.ndarray], cur: np.ndarray, threshold: float = 0.10) -> float:
    """Mean absolute difference between signature frames."""
    if prev is None or prev.shape != cur.shape:
        return 1.0
    return float(np.mean(np.abs(prev - cur)))


def image_bytes(img: Image.Image, quality: int = 78) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=quality)
    return buf.getvalue()


class ScreenWatcher(WatcherBase):
    """Watches the primary screen: records changed frames, tracks the focused
    window, and (optionally) OCRs periodically. Never injects input."""

    kind = "screen"

    def __init__(self, bus: EventBus, config: Any, vault: Path) -> None:
        cfg = config.get("perception.screen", {})
        super().__init__(bus, config, interval=float(cfg.get("interval_s", 1.5)))
        self.cfg = cfg
        self.vault = Path(vault) / "screen"
        self.vault.mkdir(parents=True, exist_ok=True)
        self.max_images = int(cfg.get("max_images", 200))
        self.change_threshold = float(cfg.get("change_threshold", 0.10))
        self.ocr_enabled = bool((cfg.get("ocr") or {}).get("enabled"))
        self.ocr_interval = float((cfg.get("ocr") or {}).get("interval_s", 30.0))
        self.ocr_lang = str((cfg.get("ocr") or {}).get("lang", "eng"))
        self._last_signature: Optional[np.ndarray] = None
        self._last_ocr = 0.0
        self._window_cfg = config.get("perception.window", {})
        self._window_enabled = bool(self._window_cfg.get("enabled", True))
        self._window_interval = float(self._window_cfg.get("interval_s", 1.0))
        self._last_window: Optional[str] = None
        self._last_window_check = 0.0
        self._win32gui = None
        if self._window_enabled:
            try:
                import win32gui  # type: ignore

                self._win32gui = win32gui
            except ImportError:
                self._win32gui = None

    # -- watcher -----------------------------------------------------------
    def _setup(self) -> bool:
        _ = grab_screen()  # probe once so failures surface early
        return True

    def _tick(self) -> None:
        img = grab_screen()
        if img is None:
            return
        now = now_ms()
        small = downscale(img)
        sig = change_signature(small)
        change = frame_changed(self._last_signature, sig, self.change_threshold)
        if change >= self.change_threshold or self.tick_count == 0:
            self._last_signature = sig
            path = self._save_frame(small)
            self.bus.emit(
                "perception.screen.changed",
                {"image_path": str(path), "change": round(change, 4), "width": small.width, "height": small.height},
                source="screen",
            )
        if self.ocr_enabled and (now - self._last_ocr) / 1000.0 >= self.ocr_interval:
            self._last_ocr = now
            self._run_ocr(small)
        self._track_window(now)

    def _save_frame(self, img: Image.Image) -> Path:
        path = self.vault / f"{now_ms()}.jpg"
        img.save(path, format="JPEG", quality=80)
        self._roll(self.vault, self.max_images)
        return path

    def _run_ocr(self, img: Image.Image) -> None:
        text = ocr_text(img, lang=self.ocr_lang)
        if text.strip():
            self.bus.emit(
                "perception.screen.text",
                {"text": text[:4000], "digest": sha1_hex(text)[:12]},
                source="screen",
            )

    def _track_window(self, now: int) -> None:
        if not self._win32gui or (now - self._last_window_check) / 1000.0 < self._window_interval:
            return
        self._last_window_check = now
        try:
            hwnd = self._win32gui.GetForegroundWindow()
            title = self._win32gui.GetWindowText(hwnd)
            app = self._win32gui.GetClassName(hwnd)
        except Exception:  # noqa: BLE001
            return
        key = f"{app}|{title}"
        if key != self._last_window:
            self._last_window = key
            self.bus.emit(
                "perception.window",
                {"app": app, "title": title, "text": f"{app}: {title}".strip(": "), "hwnd": hwnd},
                source="window",
            )

    @staticmethod
    def _roll(directory: Path, keep: int) -> None:
        files = sorted(directory.glob("*.jpg"), key=lambda p: p.stat().st_mtime, reverse=True)
        for stale in files[keep:]:
            try:
                stale.unlink()
            except OSError:
                pass


def focused_window() -> tuple[str, str]:
    """(app, title) of the foreground window, best-effort."""
    try:
        import win32gui  # type: ignore

        hwnd = win32gui.GetForegroundWindow()
        return win32gui.GetClassName(hwnd), win32gui.GetWindowText(hwnd)
    except Exception:  # noqa: BLE001
        return "", ""
