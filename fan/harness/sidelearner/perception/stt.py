"""Speech-to-text backends for desktop audio captions.

Local faster-whisper is preferred when configured and installed. A configured
provider with the ``audio`` capability is used as a fallback. Backends accept
ordinary WAV bytes and return a normalized transcript result.
"""
from __future__ import annotations

import io
import logging
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

log = logging.getLogger("sidelearner.perception.stt")


@dataclass
class TranscriptResult:
    text: str
    backend: str
    language: str = ""
    confidence: Optional[float] = None


class SpeechTranscriber:
    """Lazy, local-first speech transcriber with provider fallback."""

    def __init__(self, config: Any, provider: Optional[Any] = None) -> None:
        cfg = config.get("perception.audio.stt", {}) or {}
        self.backend = str(cfg.get("backend", "auto")).lower()
        self.model_name = str(cfg.get("model", "small.en"))
        self.device = str(cfg.get("device", "auto"))
        self.compute_type = str(cfg.get("compute_type", "int8"))
        self.language = cfg.get("language") or None
        self.provider = provider
        self._model = None
        self._local_error: Optional[str] = None

    @property
    def local_error(self) -> Optional[str]:
        return self._local_error

    def available(self) -> bool:
        if self.backend == "provider":
            return self._provider_available()
        if self.backend == "faster_whisper":
            return self._local_available()
        return self._local_available() or self._provider_available()

    def transcribe(self, wav_bytes: bytes, filename: str = "audio.wav") -> Optional[TranscriptResult]:
        if self.backend in ("auto", "faster_whisper"):
            result = self._transcribe_local(wav_bytes)
            if result is not None:
                return result
            if self.backend == "faster_whisper":
                return None
        if self.backend in ("auto", "provider"):
            return self._transcribe_provider(wav_bytes, filename)
        return None

    def _local_available(self) -> bool:
        if self._model is not None:
            return True
        if self._local_error is not None:
            return False
        try:
            from faster_whisper import WhisperModel  # type: ignore

            self._model = WhisperModel(self.model_name, device=self.device, compute_type=self.compute_type)
            return True
        except Exception as exc:  # noqa: BLE001
            self._local_error = str(exc)
            log.info("local faster-whisper unavailable: %s", exc)
            return False

    def _provider_available(self) -> bool:
        return self.provider is not None and "audio" in getattr(self.provider, "capabilities", set())

    def _transcribe_local(self, wav_bytes: bytes) -> Optional[TranscriptResult]:
        if not self._local_available():
            return None
        tmp_path = ""
        try:
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as fh:
                fh.write(wav_bytes)
                tmp_path = fh.name
            segments, info = self._model.transcribe(
                tmp_path,
                language=self.language,
                vad_filter=False,
                beam_size=1,
                condition_on_previous_text=False,
            )
            parts = [segment.text.strip() for segment in segments if segment.text.strip()]
            text = " ".join(parts).strip()
            if not text:
                return None
            probability = getattr(info, "language_probability", None)
            return TranscriptResult(
                text=text,
                backend="faster_whisper",
                language=str(getattr(info, "language", "") or ""),
                confidence=float(probability) if probability is not None else None,
            )
        except Exception as exc:  # noqa: BLE001
            log.warning("local transcription failed: %s", exc)
            return None
        finally:
            if tmp_path:
                try:
                    Path(tmp_path).unlink(missing_ok=True)
                except OSError:
                    pass

    def _transcribe_provider(self, wav_bytes: bytes, filename: str) -> Optional[TranscriptResult]:
        if not self._provider_available():
            return None
        try:
            text = self.provider.transcribe(wav_bytes, filename=filename)
            if not text or not text.strip():
                return None
            return TranscriptResult(text=text.strip(), backend=f"provider:{getattr(self.provider, 'name', 'audio')}")
        except Exception as exc:  # noqa: BLE001
            log.warning("provider transcription failed: %s", exc)
            return None
