"""Desktop-audio watcher with VAD, local-first STT, and live captions.

On Windows this prefers WASAPI loopback so it hears the desktop playback mix
without changing or interrupting playback. Speech is segmented, saved as WAV,
transcribed asynchronously, emitted live, and persisted by the harness.
"""
from __future__ import annotations

import io
import logging
import queue
import threading
import uuid
import wave
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import numpy as np

from ..events import EventBus
from ..utils import now_ms, utcnow
from .base import WatcherBase
from .stt import SpeechTranscriber

log = logging.getLogger("sidelearner.perception.audio")


def _find_input_device(loopback: bool, explicit: Optional[str] = None) -> Optional[int]:
    try:
        import sounddevice as sd

        devices = list(sd.query_devices())
        if explicit is not None:
            try:
                index = int(explicit)
                return index if 0 <= index < len(devices) else None
            except ValueError:
                for i, dev in enumerate(devices):
                    if explicit.lower() in str(dev.get("name", "")).lower():
                        if loopback or dev.get("max_input_channels", 0) > 0:
                            return i
                return None
        default = sd.default.device[0] if isinstance(sd.default.device, (list, tuple)) else sd.default.device
        if not loopback:
            return default
        for i, dev in enumerate(devices):
            name = str(dev.get("name", ""))
            if "loopback" in name.lower() and dev.get("max_input_channels", 0) > 0:
                return i
        # Standard sounddevice exposes WASAPI render endpoints as outputs.
        # WasapiSettings(loopback=True) turns the selected endpoint into input.
        try:
            wasapi = next(i for i, host in enumerate(sd.query_hostapis()) if "WASAPI" in str(host.get("name", "")).upper())
            default_output = int(sd.query_hostapis(wasapi).get("default_output_device", -1))
            return default_output if default_output >= 0 else None
        except Exception:  # noqa: BLE001
            return None
    except Exception as exc:  # noqa: BLE001
        log.warning("audio device query failed: %s", exc)
        return None


class AudioWatcher(WatcherBase):
    kind = "audio"

    def __init__(self, bus: EventBus, config: Any, vault: Path, provider: Optional[Any] = None) -> None:
        cfg = config.get("perception.audio", {}) or {}
        super().__init__(bus, config, interval=0.02)
        self.cfg = cfg
        self.vault = Path(vault) / "audio"
        self.vault.mkdir(parents=True, exist_ok=True)
        self.sample_rate = int(cfg.get("sample_rate", 16000))
        self.block_ms = int(cfg.get("block_ms", 30))
        self.blocksize = max(64, int(self.sample_rate * self.block_ms / 1000))
        self.vad_energy = float(cfg.get("vad_energy", 0.015))
        self.min_speech_s = float(cfg.get("min_speech_s", 0.4))
        self.max_speech_s = float(cfg.get("max_speech_s", 30.0))
        # Keep one continuous file through ordinary conversational pauses;
        # finalize only after a genuinely long gap.
        self.silence_s = float(cfg.get("long_pause_s", cfg.get("silence_s", 4.0)))
        self.partial_every_s = float(cfg.get("partial_every_s", 1.5))
        self.transcribe_enabled = bool(cfg.get("transcribe", True))
        self.max_wavs = int(cfg.get("max_wavs", 100))
        self.capture_mode = str(cfg.get("capture_mode", "loopback")).lower()
        self.loopback = self.capture_mode == "loopback" or bool(cfg.get("loopback", False))
        self.fallback_to_mic = bool(cfg.get("fallback_to_mic", False))
        self.device = cfg.get("device")
        self.provider = provider
        self.transcriber = SpeechTranscriber(config, provider=provider)
        self._queue: queue.Queue[np.ndarray] = queue.Queue(maxsize=300)
        self._stt_queue: queue.Queue[dict] = queue.Queue(maxsize=4)
        self._stream = None
        self._sd = None
        self._soundcard_recorder = None
        self._capture_backend = ""
        self._device_name = ""
        self._segment: list[np.ndarray] = []
        self._speech = False
        self._speech_s = 0.0
        self._silence_s = 0.0
        self._level = 0.0
        self._segment_id = ""
        self._segment_started = ""
        self._last_partial_s = 0.0
        self._stt_thread: Optional[threading.Thread] = None

    def _setup(self) -> bool:
        if self.loopback and self._setup_soundcard_loopback():
            return True
        try:
            import sounddevice as sd  # type: ignore

            self._sd = sd
        except ImportError as exc:
            self.error = f"sounddevice not installed ({exc})"
            return False
        try:
            device = _find_input_device(self.loopback, self.device)
            if device is None and self.loopback and self.fallback_to_mic:
                device = _find_input_device(False, self.device)
                self.capture_mode = "microphone-fallback"
            if device is None:
                self.error = "WASAPI loopback input not found; install/enable a loopback-capable PortAudio device or set fallback_to_mic"
                return False
            info = self._sd.query_devices(device)
            self._device_name = str(info.get("name", device))
            channels = 1
            extra_settings = None
            if self.loopback and int(info.get("max_input_channels", 0)) == 0:
                channels = max(1, min(2, int(info.get("max_output_channels", 0))))
                try:
                    extra_settings = self._sd.WasapiSettings(loopback=True)
                except TypeError as exc:
                    self.error = "installed sounddevice build lacks WASAPI loopback support; install the soundcard package for desktop capture"
                    log.warning("audio watcher disabled: %s", exc)
                    return False
            self._stream = self._sd.InputStream(
                samplerate=self.sample_rate,
                blocksize=self.blocksize,
                device=device,
                channels=channels,
                dtype="float32",
                extra_settings=extra_settings,
                callback=self._callback,
            )
            self._stream.start()
            self._capture_backend = "sounddevice"
            self._start_stt_and_emit_ready()
            return True
        except Exception as exc:  # noqa: BLE001
            self.error = f"audio input unavailable: {exc}"
            log.warning("audio watcher disabled: %s", exc)
            return False

    def _setup_soundcard_loopback(self) -> bool:
        """Use SoundCard's native WASAPI loopback, which works for output-only endpoints."""
        try:
            import soundcard as sc  # type: ignore

            speaker = None
            if self.device is not None:
                needle = str(self.device).lower()
                speakers = list(sc.all_speakers())
                # Numeric sounddevice indices cannot identify SoundCard devices;
                # prefer the current Windows default output in that case.
                if not needle.isdigit():
                    speaker = next((item for item in speakers if needle in str(item.name).lower()), None)
            speaker = speaker or sc.default_speaker()
            if speaker is None:
                return False
            microphone = sc.get_microphone(id=str(speaker.id), include_loopback=True)
            if microphone is None:
                return False
            self._soundcard_recorder = microphone.recorder(samplerate=self.sample_rate, channels=1, blocksize=self.blocksize)
            self._soundcard_recorder.__enter__()
            self._device_name = str(speaker.name)
            self._capture_backend = "soundcard-wasapi-loopback"
            self._start_stt_and_emit_ready()
            return True
        except Exception as exc:  # noqa: BLE001
            log.warning("SoundCard loopback unavailable, trying sounddevice: %s", exc)
            self._soundcard_recorder = None
            return False

    def _start_stt_and_emit_ready(self) -> None:
        if self.transcribe_enabled:
            self._stt_thread = threading.Thread(target=self._stt_worker, name="audio-stt", daemon=True)
            self._stt_thread.start()
        self.bus.emit(
            "perception.audio.ready",
            {
                "device": self._device_name,
                "capture_mode": self.capture_mode,
                "capture_backend": self._capture_backend,
                "transcribe": self.transcribe_enabled,
            },
            source="audio",
        )

    def _callback(self, indata, frames, time_info, status) -> None:  # noqa: ARG002
        try:
            block = indata.mean(axis=1) if indata.ndim > 1 else indata
            self._queue.put_nowait(np.asarray(block, dtype=np.float32).copy())
        except queue.Full:
            pass

    def _teardown(self) -> None:
        if self._soundcard_recorder is not None:
            try:
                self._soundcard_recorder.__exit__(None, None, None)
            except Exception:  # noqa: BLE001
                pass
        if self._stream is not None:
            try:
                self._stream.stop()
                self._stream.close()
            except Exception:  # noqa: BLE001
                pass
        try:
            self._stt_queue.put_nowait({"stop": True})
        except queue.Full:
            pass
        if self._stt_thread is not None:
            self._stt_thread.join(timeout=2.0)

    def _tick(self) -> None:
        if self._soundcard_recorder is not None:
            captured = self._soundcard_recorder.record(numframes=self.blocksize)
            block = captured.mean(axis=1) if captured.ndim > 1 else captured
            block = np.asarray(block, dtype=np.float32)
        else:
            try:
                block = self._queue.get_nowait()
            except queue.Empty:
                return
        rms = float(np.sqrt(np.mean(block**2))) if block.size else 0.0
        self._level = rms
        block_s = block.size / self.sample_rate
        if rms >= self.vad_energy:
            if not self._speech:
                self._segment.clear()
                self._segment_id = uuid.uuid4().hex
                self._segment_started = utcnow()
                self._last_partial_s = 0.0
            self._speech = True
            self._speech_s += block_s
            self._silence_s = 0.0
            self._segment.append(block)
            if self.transcribe_enabled and self._speech_s - self._last_partial_s >= self.partial_every_s:
                self._last_partial_s = self._speech_s
                self._enqueue_transcription(final=False)
            if self._speech_s >= self.max_speech_s:
                self._finalize()
        elif self._speech:
            self._silence_s += block_s
            self._segment.append(block)
            if self._silence_s >= self.silence_s:
                self._finalize()
        else:
            self._silence_s += block_s

    def _enqueue_transcription(self, final: bool, wav_bytes: Optional[bytes] = None, path: Optional[Path] = None, duration: float = 0.0, speech: float = 0.0) -> None:
        if not self.transcribe_enabled:
            return
        if wav_bytes is None:
            if not self._segment:
                return
            wav_bytes = self._to_wav(np.concatenate(self._segment))
        item = {
            "segment_id": self._segment_id,
            "started": self._segment_started,
            "ended": utcnow(),
            "final": final,
            "wav_bytes": wav_bytes,
            "wav_path": str(path) if path else "",
            "duration_s": duration or len(wav_bytes) / max(1, self.sample_rate * 2),
            "speech_s": speech or self._speech_s,
        }
        try:
            self._stt_queue.put_nowait(item)
        except queue.Full:
            if final:
                try:
                    self._stt_queue.get_nowait()
                    self._stt_queue.put_nowait(item)
                except queue.Empty:
                    pass

    def _finalize(self) -> None:
        duration = sum(block.size for block in self._segment) / self.sample_rate
        speech = self._speech_s
        self._speech = False
        self._speech_s = 0.0
        self._silence_s = 0.0
        if not self._segment or duration < self.min_speech_s:
            self._segment.clear()
            return
        audio = np.concatenate(self._segment)
        self._segment.clear()
        wav_bytes = self._to_wav(audio)
        path = self.vault / f"{now_ms()}_{self._segment_id[:8]}.wav"
        path.write_bytes(wav_bytes)
        self._roll(self.vault, self.max_wavs)
        payload = {
            "segment_id": self._segment_id,
            "started": self._segment_started,
            "ended": utcnow(),
            "wav_path": str(path),
            "duration_s": round(duration, 2),
            "speech_s": round(speech, 2),
            "level": round(self._level, 4),
            "device": self._device_name,
            "capture_mode": self.capture_mode,
        }
        self.bus.emit("perception.audio.speech", payload, source="audio")
        self._enqueue_transcription(final=True, wav_bytes=wav_bytes, path=path, duration=duration, speech=speech)

    def _stt_worker(self) -> None:
        while not self._stop.is_set():
            try:
                item = self._stt_queue.get(timeout=0.2)
            except queue.Empty:
                continue
            if item.get("stop"):
                return
            result = self.transcriber.transcribe(item["wav_bytes"], filename=Path(item.get("wav_path") or "audio.wav").name)
            if result is None:
                if item["final"]:
                    self.bus.emit("perception.audio.transcription_failed", {"segment_id": item["segment_id"]}, source="audio")
                continue
            payload = {
                "segment_id": item["segment_id"],
                "text": result.text,
                "final": bool(item["final"]),
                "started": item["started"],
                "ended": item["ended"],
                "duration_s": round(float(item["duration_s"]), 2),
                "speech_s": round(float(item["speech_s"]), 2),
                "wav_path": item.get("wav_path", ""),
                "device": self._device_name,
                "capture_mode": self.capture_mode,
                "backend": result.backend,
                "language": result.language,
                "confidence": result.confidence,
            }
            event_type = "perception.audio.transcript" if item["final"] else "perception.audio.transcript.partial"
            self.bus.emit(event_type, payload, source="audio")

    def _to_wav(self, audio: np.ndarray) -> bytes:
        pcm = (np.clip(audio, -1.0, 1.0) * 32767).astype(np.int16)
        buf = io.BytesIO()
        with wave.open(buf, "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(self.sample_rate)
            wav.writeframes(pcm.tobytes())
        return buf.getvalue()

    @staticmethod
    def _roll(directory: Path, keep: int) -> None:
        files = sorted(directory.glob("*.wav"), key=lambda p: p.stat().st_mtime, reverse=True)
        for stale in files[keep:]:
            try:
                stale.unlink()
            except OSError:
                pass

    def status(self) -> dict:
        base = super().status()
        base.update(
            {
                "level": round(self._level, 4),
                "speech": self._speech,
                "device": self._device_name,
                "capture_mode": self.capture_mode,
                "capture_backend": self._capture_backend,
                "transcribe": self.transcribe_enabled,
                "stt_backend": self.transcriber.backend,
                "stt_local_error": self.transcriber.local_error,
            }
        )
        return base
