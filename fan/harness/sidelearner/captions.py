"""Native always-on-top live captions for Windows.

The overlay is intentionally implemented with the Python standard library
(Tkinter), so it does not add a second GUI framework. It subscribes directly to
SideLearner's event bus and displays partial/final audio transcripts.
"""
from __future__ import annotations

import queue
import threading
from typing import Optional

from .events import Event, EventBus


class CaptionOverlay:
    """Thread-owned transparent caption window controlled at runtime."""

    def __init__(self, bus: EventBus, config) -> None:
        cfg = config.get("captions", {}) or {}
        self.bus = bus
        self.enabled = bool(cfg.get("enabled", False))
        self.font_size = int(cfg.get("font_size", 24))
        self.max_chars = int(cfg.get("max_chars", 280))
        self.opacity = float(cfg.get("opacity", 0.88))
        self.position = str(cfg.get("position", "bottom"))
        self._queue: queue.Queue[tuple[str, object]] = queue.Queue(maxsize=100)
        self._thread: Optional[threading.Thread] = None
        self._root = None
        self._label = None
        self._started = threading.Event()
        self._sub_partial = bus.subscribe("perception.audio.transcript.partial", self._on_transcript)
        self._sub_final = bus.subscribe("perception.audio.transcript", self._on_transcript)

    def start(self) -> None:
        if self._thread is not None and self._thread.is_alive():
            return
        self._thread = threading.Thread(target=self._run, name="caption-overlay", daemon=True)
        self._thread.start()
        self._started.wait(timeout=2.0)

    def set_enabled(self, enabled: bool) -> bool:
        self.enabled = bool(enabled)
        self.start()
        self._put(("enabled", self.enabled))
        self.bus.emit("captions.state", {"enabled": self.enabled}, source="captions")
        return self.enabled

    def toggle(self) -> bool:
        return self.set_enabled(not self.enabled)

    def status(self) -> dict:
        return {
            "enabled": self.enabled,
            "running": bool(self._thread and self._thread.is_alive()),
            "surface": "windows-overlay",
        }

    def stop(self) -> None:
        self.enabled = False
        self._put(("stop", None))
        if self._thread is not None and self._thread.is_alive():
            self._thread.join(timeout=2.0)
        self.bus.unsubscribe(self._sub_partial)
        self.bus.unsubscribe(self._sub_final)

    def _on_transcript(self, event: Event) -> None:
        text = str((event.data or {}).get("text", "")).strip()
        if text:
            self._put(("text", text[-self.max_chars :]))

    def _put(self, item: tuple[str, object]) -> None:
        try:
            self._queue.put_nowait(item)
        except queue.Full:
            try:
                self._queue.get_nowait()
                self._queue.put_nowait(item)
            except queue.Empty:
                pass

    def _run(self) -> None:
        try:
            import tkinter as tk

            root = tk.Tk()
            self._root = root
            root.title("SideLearner Live Captions")
            root.configure(bg="#111111")
            root.attributes("-topmost", True)
            root.attributes("-alpha", max(0.2, min(1.0, self.opacity)))
            root.overrideredirect(True)
            frame = tk.Frame(root, bg="#111111")
            frame.pack(fill="both", expand=True)
            close_button = tk.Button(
                frame,
                text="×",
                command=lambda: self.set_enabled(False),
                bg="#111111",
                fg="#bbbbbb",
                activebackground="#cc3333",
                activeforeground="#ffffff",
                relief="flat",
                borderwidth=0,
                font=("Segoe UI", 16, "bold"),
                cursor="hand2",
                padx=8,
                pady=0,
            )
            close_button.place(relx=1.0, x=-4, y=2, anchor="ne")
            label = tk.Label(
                frame,
                text="Listening for desktop audio…",
                bg="#111111",
                fg="#ffffff",
                font=("Segoe UI", self.font_size, "bold"),
                wraplength=1050,
                justify="center",
                padx=42,
                pady=14,
            )
            label.pack(fill="both", expand=True)
            close_button.lift()
            self._label = label
            root.update_idletasks()
            width = min(1200, max(700, root.winfo_reqwidth()))
            height = max(90, root.winfo_reqheight())
            x = max(0, (root.winfo_screenwidth() - width) // 2)
            y = 40 if self.position == "top" else max(0, root.winfo_screenheight() - height - 70)
            root.geometry(f"{width}x{height}+{x}+{y}")
            if not self.enabled:
                root.withdraw()
            self._started.set()

            def pump() -> None:
                while True:
                    try:
                        kind, value = self._queue.get_nowait()
                    except queue.Empty:
                        break
                    if kind == "stop":
                        root.destroy()
                        return
                    if kind == "enabled":
                        if value:
                            root.deiconify()
                            root.attributes("-topmost", True)
                        else:
                            root.withdraw()
                    elif kind == "text" and self.enabled:
                        label.configure(text=str(value))
                        root.deiconify()
                root.after(50, pump)

            root.after(50, pump)
            root.mainloop()
        except Exception as exc:  # noqa: BLE001
            self._started.set()
            self.bus.emit("captions.unavailable", {"reason": str(exc)}, source="captions")
        finally:
            self._root = None
            self._label = None
