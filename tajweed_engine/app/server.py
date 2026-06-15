"""FastAPI WebSocket streaming server for real-time Tajweed feedback.

The transport is intentionally thin. All of the engine logic lives in framework
-agnostic, unit-testable classes:

* :class:`WordTarget` / :class:`AyahTarget` -- the verified canonical target a
  session is reciting against (text + phonemes + Tajweed expectations).
* :class:`TajweedPipeline` -- runs one audio segment through alignment, GOP and
  the Tajweed rules and emits a feedback packet.
* :class:`TajweedSession` -- stateful per-connection buffer that detects word
  boundaries with VAD, advances a cursor through the ayah, and yields packets.

The FastAPI layer (``/v1/stream-tajweed``) is only wired up when ``fastapi`` is
installed; importing this module without it still exposes the pipeline classes.

Privacy posture (Siraat standing rule)
--------------------------------------
Recitation audio is sensitive. This server is designed to run on-device or as a
user's own self-hosted endpoint: audio is held only in the session buffer for
the current computation and is never persisted. Do not add logging of raw audio
or transcripts, and do not deploy this as a shared multi-tenant service that
retains recordings.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable, Optional, Sequence

import numpy as np

from .alignment_engine import (
    AcousticModel,
    AlignedPhoneme,
    ForcedAligner,
    GHUNNAH_PHONEMES,
    LONG_VOWELS,
    MockAcousticModel,
    Phoneme,
    QALQALAH_PHONEMES,
    text_to_phonemes,
)
from .audio_processing import (
    AudioConfig,
    FloatArray,
    SileroVAD,
    frame_rms_db,
    normalize_rms,
    pcm16_to_float,
)
from .gop_scorer import GOPConfig, GOPScorer, GOPStatus
from .tajweed_rules import (
    RuleStatus,
    TajweedConfig,
    evaluate_ghunnah,
    evaluate_madd,
    evaluate_qalqalah,
)


# ---------------------------------------------------------------------------
# Targets (supplied from verified canonical text -- never generated here)
# ---------------------------------------------------------------------------
@dataclass
class WordTarget:
    """One word of the canonical ayah, with its Tajweed expectations.

    ``madd_targets`` maps a phoneme's grapheme index to its required count
    (2/4/6). ``ghunnah_indices`` and ``qalqalah_indices`` flag grapheme indices
    that must exhibit those acoustic properties. These annotations come from a
    verified per-ayah blueprint; defaults are inferred only as a convenience.
    """

    text: str
    phonemes: list[Phoneme]
    madd_targets: dict[int, int] = field(default_factory=dict)
    ghunnah_indices: set[int] = field(default_factory=set)
    qalqalah_indices: set[int] = field(default_factory=set)

    @classmethod
    def from_text(cls, text: str, madd_targets: Optional[dict[int, int]] = None,
                  ghunnah_indices: Optional[Iterable[int]] = None,
                  qalqalah_indices: Optional[Iterable[int]] = None) -> "WordTarget":
        phonemes = text_to_phonemes(text)
        madd = dict(madd_targets or {})
        gh = set(ghunnah_indices or [])
        qa = set(qalqalah_indices or [])
        # Convenience defaults: long vowels carry a 2-count madd unless overridden.
        for p in phonemes:
            if p.symbol in LONG_VOWELS and p.grapheme_index not in madd:
                madd[p.grapheme_index] = 2
            if p.symbol in GHUNNAH_PHONEMES:
                gh.add(p.grapheme_index)
        return cls(text, phonemes, madd, gh, qa)


@dataclass
class AyahTarget:
    """The ordered words a session recites against."""

    words: list[WordTarget]

    @classmethod
    def from_words(cls, words: Sequence[str]) -> "AyahTarget":
        return cls([WordTarget.from_text(w) for w in words])


# ---------------------------------------------------------------------------
# Processing pipeline
# ---------------------------------------------------------------------------
class TajweedPipeline:
    """Runs one audio segment for one word through the full engine."""

    def __init__(self, model: Optional[AcousticModel] = None,
                 audio_config: AudioConfig = AudioConfig(),
                 gop_config: GOPConfig = GOPConfig(),
                 tajweed_config: TajweedConfig = TajweedConfig()) -> None:
        self.audio_config = audio_config
        self.model = model or MockAcousticModel(audio_config)
        self.aligner = ForcedAligner(self.model, audio_config)
        self.scorer = GOPScorer(gop_config)
        self.tajweed_config = tajweed_config

    def process_word(self, signal: FloatArray, word: WordTarget) -> dict:
        """Align, GOP-score and Tajweed-check one word; return a feedback packet."""
        if not word.phonemes:
            return {"word": word.text, "status": "skipped", "phoneme_telemetry": []}
        signal = normalize_rms(signal)
        aligned, emission = self.aligner.align(signal, word.phonemes)
        gop_scores = self.scorer.score(emission, aligned)

        telemetry: list[dict] = []
        any_fail = False
        for phoneme, gop in zip(aligned, gop_scores):
            entry: dict = {
                "phoneme": phoneme.symbol,
                "gop_score": gop.gop_score,
                "status": gop.status.value,
            }
            if gop.error:
                entry["error"] = gop.error
            if gop.status is GOPStatus.FAILED:
                any_fail = True

            tj = self._tajweed_for(signal, phoneme, word)
            if tj is not None:
                entry["tajweed"] = tj
                if tj["status"] == RuleStatus.FAILED.value:
                    any_fail = True
            telemetry.append(entry)

        status = "correct" if not any_fail else "needs_review"
        return {"word": word.text, "status": status, "phoneme_telemetry": telemetry}

    def _tajweed_for(self, signal: FloatArray, phoneme: AlignedPhoneme,
                     word: WordTarget) -> Optional[dict]:
        """Dispatch the relevant acoustic Tajweed rule for a phoneme, if any."""
        seg = signal[phoneme.frame_slice_samples(self.audio_config)]
        gi = phoneme.grapheme_index

        if gi in word.madd_targets and phoneme.symbol in LONG_VOWELS:
            r = evaluate_madd(seg, word.madd_targets[gi], self.tajweed_config,
                              phoneme_duration=phoneme.duration)
            return {"rule": "madd", "status": r.status.value,
                    "measured_counts": r.measured_counts,
                    "target_counts": r.target_counts, "error": r.error}

        if gi in word.ghunnah_indices or phoneme.symbol in GHUNNAH_PHONEMES:
            r = evaluate_ghunnah(seg, self.tajweed_config)
            return {"rule": "ghunnah", "status": r.status.value,
                    "nasal_counts": r.nasal_counts, "error": r.error}

        if gi in word.qalqalah_indices and phoneme.symbol in QALQALAH_PHONEMES:
            # Closure assumed at the start of the aligned consonant segment.
            r = evaluate_qalqalah(seg, 0.0, self.tajweed_config)
            return {"rule": "qalqalah", "status": r.status.value,
                    "peak_denergy": r.peak_denergy, "error": r.error}
        return None


# ---------------------------------------------------------------------------
# Stateful streaming session
# ---------------------------------------------------------------------------
class TajweedSession:
    """Buffers chunked PCM, segments words by VAD, yields feedback packets."""

    def __init__(self, target: AyahTarget, pipeline: Optional[TajweedPipeline] = None,
                 audio_config: AudioConfig = AudioConfig(),
                 silence_hold_ms: float = 250.0,
                 min_word_ms: float = 120.0) -> None:
        self.target = target
        self.pipeline = pipeline or TajweedPipeline(audio_config=audio_config)
        self.config = audio_config
        self.vad = SileroVAD(audio_config)
        self.silence_hold_frames = int(silence_hold_ms / audio_config.vad_frame_ms)
        self.min_word_samples = int(min_word_ms * audio_config.sample_rate / 1000.0)
        self._buffer = np.zeros(0, dtype=np.float32)
        self._cursor = 0   # index of the next word to evaluate

    @property
    def finished(self) -> bool:
        return self._cursor >= len(self.target.words)

    def feed_pcm(self, data: bytes) -> list[dict]:
        """Ingest a binary PCM16 chunk; return packets for any completed words."""
        return self.feed(pcm16_to_float(data))

    def feed(self, samples: FloatArray) -> list[dict]:
        """Ingest float samples; return packets for any completed words."""
        self._buffer = np.concatenate([self._buffer, samples])
        return self._drain(final=False)

    def flush(self) -> list[dict]:
        """End-of-stream: process whatever voiced audio remains buffered."""
        return self._drain(final=True)

    def _drain(self, final: bool) -> list[dict]:
        packets: list[dict] = []
        while not self.finished:
            segment = self._pop_word_segment(final)
            if segment is None:
                break
            if segment.size < self.min_word_samples and not final:
                # Re-buffer a too-short blip; wait for more audio.
                self._buffer = np.concatenate([segment, self._buffer])
                break
            word = self.target.words[self._cursor]
            packets.append(self.pipeline.process_word(segment, word))
            self._cursor += 1
            if final and self._buffer.size == 0:
                break
        return packets

    def _pop_word_segment(self, final: bool) -> Optional[FloatArray]:
        """Extract the next voiced word from the buffer, or ``None`` if not ready.

        A word is "ready" once a voiced run is followed by ``silence_hold_frames``
        of silence (or the stream is ending). The consumed audio (including the
        trailing silence) is removed from the buffer.
        """
        fs = self.config.vad_frame_samples
        if self._buffer.size < fs:
            return self._buffer_tail() if final else None

        db = frame_rms_db(self._buffer, fs)
        voiced = db >= self.config.vad_energy_db_floor
        first = int(np.argmax(voiced)) if voiced.any() else -1
        if first < 0:
            if final:
                self._buffer = np.zeros(0, dtype=np.float32)
            return None

        # Walk to the end of the voiced run, allowing brief gaps < silence_hold.
        last = first
        gap = 0
        boundary = -1
        for i in range(first, voiced.size):
            if voiced[i]:
                last = i
                gap = 0
            else:
                gap += 1
                if gap >= self.silence_hold_frames:
                    boundary = i + 1
                    break
        if boundary < 0:
            if not final:
                return None
            boundary = voiced.size

        seg = self._buffer[: boundary * fs]
        self._buffer = self._buffer[boundary * fs :]
        voiced_seg = seg[first * fs : (last + 1) * fs]
        return voiced_seg

    def _buffer_tail(self) -> Optional[FloatArray]:
        if self._buffer.size == 0:
            return None
        tail = self._buffer
        self._buffer = np.zeros(0, dtype=np.float32)
        return tail


# ---------------------------------------------------------------------------
# FastAPI app (optional import)
# ---------------------------------------------------------------------------
def create_app():  # pragma: no cover - exercised only when fastapi is installed
    """Build the FastAPI app exposing the streaming WebSocket endpoint."""
    from fastapi import FastAPI, WebSocket, WebSocketDisconnect

    app = FastAPI(title="Siraat Tajweed Engine", version="0.1.0")

    @app.get("/healthz")
    async def healthz() -> dict:
        return {"status": "ok"}

    @app.websocket("/v1/stream-tajweed")
    async def stream_tajweed(ws: WebSocket) -> None:
        await ws.accept()
        session: Optional[TajweedSession] = None
        try:
            # First message configures the session with the target ayah words.
            config_msg = await ws.receive_json()
            words = config_msg.get("words", [])
            target = AyahTarget.from_words(words)
            session = TajweedSession(target)
            await ws.send_json({"event": "ready", "word_count": len(words)})

            while True:
                message = await ws.receive()
                if "bytes" in message and message["bytes"] is not None:
                    for packet in session.feed_pcm(message["bytes"]):
                        await ws.send_json(packet)
                elif "text" in message and message["text"] == "__end__":
                    for packet in session.flush():
                        await ws.send_json(packet)
                    await ws.send_json({"event": "complete"})
                    break
        except WebSocketDisconnect:
            return

    return app
