from __future__ import annotations

import numpy as np

from sidelearner.events import EventBus
from sidelearner.harness import Harness
from sidelearner.perception.audio import AudioWatcher
from sidelearner.perception.stt import SpeechTranscriber, TranscriptResult


class _FakeProvider:
    name = "fake-stt"
    capabilities = {"text", "audio"}

    def transcribe(self, audio_bytes, filename="audio.wav"):
        return "desktop audio words"


def test_provider_stt_fallback(config):
    config.data["perception"]["audio"]["stt"] = {"backend": "provider"}
    result = SpeechTranscriber(config, provider=_FakeProvider()).transcribe(b"wav", "test.wav")
    assert result is not None
    assert result.text == "desktop audio words"
    assert result.backend == "provider:fake-stt"


def test_audio_wav_encoding(config, workspace):
    watcher = AudioWatcher(EventBus(), config, workspace / "vault")
    wav = watcher._to_wav(np.zeros(1600, dtype=np.float32))
    assert wav.startswith(b"RIFF")
    assert b"WAVE" in wav[:16]


def test_final_transcript_persists_and_enters_twin(config):
    harness = Harness(config)
    try:
        harness.bus.emit(
            "perception.audio.transcript",
            {
                "segment_id": "seg-1",
                "text": "The quarterly invoice is ready for review.",
                "started": "2026-01-01T00:00:00+00:00",
                "ended": "2026-01-01T00:00:03+00:00",
                "duration_s": 3.0,
                "speech_s": 2.5,
                "wav_path": "vault/audio/seg-1.wav",
                "device": "Speakers (loopback)",
                "capture_mode": "loopback",
                "backend": "faster_whisper",
                "language": "en",
                "confidence": 0.95,
            },
            source="audio",
        )
        rows = harness.store.audio_segments_recent(5)
        assert len(rows) == 1
        assert rows[0]["transcript"].startswith("The quarterly")
        assert rows[0]["capture_mode"] == "loopback"
        observations = harness.store.counts()["observations"]
        assert observations == 1
        stored = harness.store.get_audio_segment("seg-1")
        assert stored is not None
        insights = harness.store.audio_insights()
        assert insights["segments"] == 1
        assert insights["transcribed"] == 1
        assert insights["audio_observations"] == 1
    finally:
        harness.stop()
