"""Audio normalization, Voice Activity Detection and acoustic feature extraction.

This module is the engine's front door. Everything downstream (alignment, GOP,
Tajweed DSP) consumes the standardized, framed signal produced here.

Design goals
------------
* Deterministic: pure-NumPy DSP so the unit tests run with no ML runtime.
* Streaming-friendly: small, allocation-light helpers that operate on chunks.
* Honest fallbacks: heavy dependencies (Silero VAD, librosa) are optional and
  wrapped so the module degrades to a documented heuristic rather than crashing.

All audio is standardized to 16 kHz, single channel, float32 in [-1, 1]. PCM16
ingest/egress helpers are provided for the WebSocket transport.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Optional

import numpy as np
from numpy.typing import NDArray

FloatArray = NDArray[np.float32]
ComplexArray = NDArray[np.complex128]


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class AudioConfig:
    """Canonical audio + framing parameters shared across the engine."""

    sample_rate: int = 16_000
    n_fft: int = 512
    hop_length: int = 160          # 10 ms hop at 16 kHz
    win_length: int = 400          # 25 ms analysis window
    n_mels: int = 80
    n_mfcc: int = 13
    fmin: float = 20.0
    fmax: float = 8_000.0
    preemphasis: float = 0.97
    # VAD
    vad_frame_ms: float = 30.0
    vad_energy_db_floor: float = -45.0   # frames quieter than this are silence
    vad_hangover_frames: int = 3         # keep speech state for N trailing frames

    @property
    def frame_seconds(self) -> float:
        return self.hop_length / self.sample_rate

    @property
    def vad_frame_samples(self) -> int:
        return int(self.sample_rate * self.vad_frame_ms / 1000.0)


# ---------------------------------------------------------------------------
# PCM <-> float conversion and normalization
# ---------------------------------------------------------------------------
def pcm16_to_float(pcm: bytes) -> FloatArray:
    """Decode little-endian 16-bit PCM bytes to float32 in [-1, 1]."""
    if len(pcm) % 2 != 0:
        # Drop a dangling byte rather than raising; chunk boundaries can split a sample.
        pcm = pcm[:-1]
    ints = np.frombuffer(pcm, dtype="<i2").astype(np.float32)
    return (ints / 32768.0).astype(np.float32)


def float_to_pcm16(signal: FloatArray) -> bytes:
    """Encode float32 [-1, 1] to little-endian 16-bit PCM bytes."""
    clipped = np.clip(signal, -1.0, 1.0)
    ints = np.round(clipped * 32767.0).astype("<i2")
    return ints.tobytes()


def to_mono(signal: NDArray[np.floating]) -> FloatArray:
    """Collapse an (n,) or (n, channels) array to a mono float32 vector."""
    arr = np.asarray(signal, dtype=np.float32)
    if arr.ndim == 2:
        arr = arr.mean(axis=1)
    return arr.astype(np.float32)


def resample(signal: FloatArray, src_rate: int, dst_rate: int) -> FloatArray:
    """Linear resampler. Adequate for 16 kHz speech ingest; replace with a
    polyphase filter (``scipy.signal.resample_poly``) for archival quality."""
    if src_rate == dst_rate or signal.size == 0:
        return signal.astype(np.float32)
    duration = signal.size / src_rate
    dst_len = int(round(duration * dst_rate))
    if dst_len <= 0:
        return np.zeros(0, dtype=np.float32)
    src_t = np.linspace(0.0, duration, num=signal.size, endpoint=False)
    dst_t = np.linspace(0.0, duration, num=dst_len, endpoint=False)
    return np.interp(dst_t, src_t, signal).astype(np.float32)


def normalize_rms(signal: FloatArray, target_dbfs: float = -20.0,
                  eps: float = 1e-9) -> FloatArray:
    """Scale a signal to a target RMS level in dBFS (no dynamic compression)."""
    rms = float(np.sqrt(np.mean(np.square(signal)) + eps))
    if rms < eps:
        return signal
    target_rms = 10.0 ** (target_dbfs / 20.0)
    gain = target_rms / rms
    return np.clip(signal * gain, -1.0, 1.0).astype(np.float32)


def preemphasize(signal: FloatArray, coeff: float) -> FloatArray:
    """First-order high-pass pre-emphasis used before spectral analysis."""
    if signal.size == 0:
        return signal
    out = np.empty_like(signal)
    out[0] = signal[0]
    out[1:] = signal[1:] - coeff * signal[:-1]
    return out


def standardize(signal: NDArray[np.floating], src_rate: int,
                config: AudioConfig = AudioConfig()) -> FloatArray:
    """Full ingest pipeline: mono -> 16 kHz -> RMS normalized float32."""
    mono = to_mono(signal)
    at_rate = resample(mono, src_rate, config.sample_rate)
    return normalize_rms(at_rate)


# ---------------------------------------------------------------------------
# Voice Activity Detection
# ---------------------------------------------------------------------------
@dataclass
class VADSegment:
    """A contiguous span of detected speech, in samples and seconds."""

    start_sample: int
    end_sample: int
    sample_rate: int

    @property
    def start_seconds(self) -> float:
        return self.start_sample / self.sample_rate

    @property
    def end_seconds(self) -> float:
        return self.end_sample / self.sample_rate

    @property
    def duration_seconds(self) -> float:
        return self.end_seconds - self.start_seconds


def frame_rms_db(signal: FloatArray, frame_samples: int,
                 eps: float = 1e-9) -> FloatArray:
    """Per-frame RMS energy in dBFS over non-overlapping frames."""
    if signal.size == 0:
        return np.zeros(0, dtype=np.float32)
    n_frames = max(1, signal.size // frame_samples)
    trimmed = signal[: n_frames * frame_samples].reshape(n_frames, frame_samples)
    rms = np.sqrt(np.mean(np.square(trimmed), axis=1) + eps)
    return (20.0 * np.log10(rms + eps)).astype(np.float32)


class SileroVAD:
    """Wrapper around the Silero VAD model with a deterministic energy fallback.

    When ``torch`` and the Silero hub model are available, :meth:`speech_probs`
    delegates to the neural model. Otherwise it falls back to a sliding-window
    RMS energy gate so the rest of the engine (and the tests) keep working with
    no ML runtime installed. The fallback is intentionally simple: production
    deployments should install Silero for robust noise rejection.
    """

    def __init__(self, config: AudioConfig = AudioConfig()) -> None:
        self.config = config
        self._model = None
        self._torch = None
        self._tried_load = False

    def _maybe_load(self) -> None:
        if self._tried_load:
            return
        self._tried_load = True
        try:  # pragma: no cover - exercised only when torch is installed
            import torch

            model, _ = torch.hub.load(
                repo_or_dir="snakers4/silero-vad",
                model="silero_vad",
                trust_repo=True,
            )
            self._model = model
            self._torch = torch
        except Exception:
            # No torch / no network / hub failure: stay on the energy fallback.
            self._model = None
            self._torch = None

    @property
    def is_neural(self) -> bool:
        self._maybe_load()
        return self._model is not None

    def speech_probs(self, signal: FloatArray) -> FloatArray:
        """Return a per-VAD-frame probability of speech in [0, 1]."""
        self._maybe_load()
        if self._model is not None and self._torch is not None:  # pragma: no cover
            return self._neural_probs(signal)
        return self._energy_probs(signal)

    def _neural_probs(self, signal: FloatArray) -> FloatArray:  # pragma: no cover
        torch = self._torch
        assert torch is not None and self._model is not None
        win = 512 if self.config.sample_rate == 16_000 else 256
        probs: list[float] = []
        tensor = torch.from_numpy(np.ascontiguousarray(signal))
        for start in range(0, signal.size, win):
            chunk = tensor[start : start + win]
            if chunk.shape[0] < win:
                chunk = torch.nn.functional.pad(chunk, (0, win - chunk.shape[0]))
            with torch.no_grad():
                probs.append(float(self._model(chunk, self.config.sample_rate).item()))
        return np.asarray(probs, dtype=np.float32)

    def _energy_probs(self, signal: FloatArray) -> FloatArray:
        cfg = self.config
        db = frame_rms_db(signal, cfg.vad_frame_samples)
        # Map [-floor .. -10] dB to [0 .. 1] with a soft knee.
        floor = cfg.vad_energy_db_floor
        scaled = (db - floor) / max(1e-6, (-10.0 - floor))
        return np.clip(scaled, 0.0, 1.0).astype(np.float32)

    def segments(self, signal: FloatArray,
                 threshold: float = 0.5) -> list[VADSegment]:
        """Collapse per-frame speech probabilities into voiced segments."""
        cfg = self.config
        probs = self.speech_probs(signal)
        active = probs >= threshold
        out: list[VADSegment] = []
        hangover = 0
        seg_start: Optional[int] = None
        for i, is_speech in enumerate(active):
            if is_speech:
                if seg_start is None:
                    seg_start = i
                hangover = cfg.vad_hangover_frames
            elif seg_start is not None:
                if hangover > 0:
                    hangover -= 1
                else:
                    out.append(self._make_segment(seg_start, i))
                    seg_start = None
        if seg_start is not None:
            out.append(self._make_segment(seg_start, len(active)))
        return out

    def _make_segment(self, start_frame: int, end_frame: int) -> VADSegment:
        fs = self.config.vad_frame_samples
        return VADSegment(start_frame * fs, end_frame * fs, self.config.sample_rate)


# ---------------------------------------------------------------------------
# Spectral features
# ---------------------------------------------------------------------------
def frame_signal(signal: FloatArray, frame_length: int,
                 hop_length: int) -> FloatArray:
    """Slice a signal into overlapping frames -> (n_frames, frame_length)."""
    if signal.size < frame_length:
        padded = np.pad(signal, (0, frame_length - signal.size))
        return padded[np.newaxis, :].astype(np.float32)
    n_frames = 1 + (signal.size - frame_length) // hop_length
    idx = np.arange(frame_length)[np.newaxis, :] + \
        hop_length * np.arange(n_frames)[:, np.newaxis]
    return signal[idx].astype(np.float32)


def _hann(window_length: int) -> FloatArray:
    n = np.arange(window_length)
    return (0.5 - 0.5 * np.cos(2.0 * math.pi * n / max(1, window_length - 1))).astype(
        np.float32
    )


def power_spectrogram(signal: FloatArray,
                      config: AudioConfig = AudioConfig()) -> FloatArray:
    """Magnitude-squared STFT -> (n_frames, n_fft // 2 + 1)."""
    emphasized = preemphasize(signal, config.preemphasis)
    frames = frame_signal(emphasized, config.win_length, config.hop_length)
    window = _hann(config.win_length)
    windowed = frames * window[np.newaxis, :]
    spectrum = np.fft.rfft(windowed, n=config.n_fft, axis=1)
    return (np.abs(spectrum) ** 2).astype(np.float32)


def _hz_to_mel(hz: NDArray[np.floating]) -> NDArray[np.floating]:
    return 2595.0 * np.log10(1.0 + hz / 700.0)


def _mel_to_hz(mel: NDArray[np.floating]) -> NDArray[np.floating]:
    return 700.0 * (10.0 ** (mel / 2595.0) - 1.0)


def mel_filterbank(config: AudioConfig = AudioConfig()) -> FloatArray:
    """Triangular mel filterbank -> (n_mels, n_fft // 2 + 1)."""
    n_bins = config.n_fft // 2 + 1
    fmax = min(config.fmax, config.sample_rate / 2.0)
    mel_pts = np.linspace(_hz_to_mel(np.array(config.fmin)),
                          _hz_to_mel(np.array(fmax)), config.n_mels + 2)
    hz_pts = _mel_to_hz(mel_pts)
    bin_pts = np.floor((config.n_fft + 1) * hz_pts / config.sample_rate).astype(int)
    bin_pts = np.clip(bin_pts, 0, n_bins - 1)
    fb = np.zeros((config.n_mels, n_bins), dtype=np.float32)
    for m in range(1, config.n_mels + 1):
        left, center, right = bin_pts[m - 1], bin_pts[m], bin_pts[m + 1]
        if center > left:
            fb[m - 1, left:center] = np.linspace(0.0, 1.0, center - left, endpoint=False)
        if right > center:
            fb[m - 1, center:right] = np.linspace(1.0, 0.0, right - center, endpoint=False)
    return fb


def mel_spectrogram(signal: FloatArray,
                    config: AudioConfig = AudioConfig()) -> FloatArray:
    """Log-mel spectrogram -> (n_frames, n_mels)."""
    power = power_spectrogram(signal, config)
    fb = mel_filterbank(config)
    mel = power @ fb.T
    return np.log(mel + 1e-9).astype(np.float32)


def _dct_matrix(n_out: int, n_in: int) -> FloatArray:
    """Orthonormal DCT-II basis -> (n_out, n_in)."""
    k = np.arange(n_out)[:, np.newaxis]
    n = np.arange(n_in)[np.newaxis, :]
    basis = np.cos(math.pi * k * (2 * n + 1) / (2 * n_in))
    basis *= math.sqrt(2.0 / n_in)
    basis[0] *= 1.0 / math.sqrt(2.0)
    return basis.astype(np.float32)


def mfcc(signal: FloatArray, config: AudioConfig = AudioConfig()) -> FloatArray:
    """Mel-frequency cepstral coefficients -> (n_frames, n_mfcc)."""
    log_mel = mel_spectrogram(signal, config)
    dct = _dct_matrix(config.n_mfcc, config.n_mels)
    return (log_mel @ dct.T).astype(np.float32)


# ---------------------------------------------------------------------------
# Formant tracking via Linear Predictive Coding
# ---------------------------------------------------------------------------
def _autocorrelation(frame: FloatArray, order: int) -> FloatArray:
    full = np.correlate(frame, frame, mode="full")
    mid = full.size // 2
    return full[mid : mid + order + 1].astype(np.float32)


def _levinson_durbin(r: FloatArray, order: int) -> FloatArray:
    """Solve the Yule-Walker equations -> LPC coefficients [1, a1..ap]."""
    a = np.zeros(order + 1, dtype=np.float64)
    a[0] = 1.0
    err = float(r[0])
    if err <= 0.0:
        return a.astype(np.float32)
    for i in range(1, order + 1):
        acc = r[i] + np.dot(a[1:i], r[i - 1 : 0 : -1])
        k = -acc / err
        a[1 : i + 1] += k * a[i - 1 :: -1][: i]
        err *= (1.0 - k * k)
        if err <= 0.0:
            break
    return a.astype(np.float32)


def estimate_formants(signal: FloatArray, n_formants: int = 3,
                      config: AudioConfig = AudioConfig()) -> FloatArray:
    """Estimate the first ``n_formants`` formants (Hz) for a single frame.

    Uses LPC (autocorrelation + Levinson-Durbin) and reads formant centers off
    the angles of the LPC polynomial roots. Returns an array of length
    ``n_formants`` padded with NaN when fewer formants are recoverable.
    """
    out = np.full(n_formants, np.nan, dtype=np.float32)
    if signal.size < 2:
        return out
    emphasized = preemphasize(signal, config.preemphasis)
    windowed = emphasized * _hann(emphasized.size)
    order = 2 + config.sample_rate // 1000  # rule of thumb: 2 + fs(kHz)
    r = _autocorrelation(windowed, order)
    if r[0] <= 0.0:
        return out
    a = _levinson_durbin(r, order).astype(np.float64)
    roots = np.roots(a)
    roots = roots[np.imag(roots) > 1e-6]   # keep one of each conjugate pair
    if roots.size == 0:
        return out
    angles = np.arctan2(np.imag(roots), np.real(roots))
    freqs = angles * (config.sample_rate / (2.0 * math.pi))
    bandwidths = -0.5 * (config.sample_rate / (2.0 * math.pi)) * np.log(np.abs(roots))
    # Plausible formants: positive frequency, reasonably narrow bandwidth.
    mask = (freqs > 90.0) & (freqs < config.sample_rate / 2.0) & (bandwidths < 400.0)
    formants = np.sort(freqs[mask])
    out[: min(n_formants, formants.size)] = formants[:n_formants]
    return out


def track_formants(signal: FloatArray, n_formants: int = 3,
                   config: AudioConfig = AudioConfig()) -> FloatArray:
    """Per-frame formant track -> (n_frames, n_formants) in Hz."""
    frames = frame_signal(signal, config.win_length, config.hop_length)
    return np.stack(
        [estimate_formants(f, n_formants, config) for f in frames]
    ).astype(np.float32)


@dataclass
class FeatureBundle:
    """All acoustic features for one audio buffer, sharing a frame timeline."""

    config: AudioConfig
    log_mel: FloatArray
    mfcc: FloatArray
    formants: FloatArray
    rms_db: FloatArray = field(default_factory=lambda: np.zeros(0, dtype=np.float32))

    @property
    def n_frames(self) -> int:
        return int(self.log_mel.shape[0])

    def frame_time(self, frame_index: int) -> float:
        return frame_index * self.config.frame_seconds


def extract_features(signal: FloatArray,
                     config: AudioConfig = AudioConfig()) -> FeatureBundle:
    """Compute the full feature bundle consumed by the alignment + DSP layers."""
    return FeatureBundle(
        config=config,
        log_mel=mel_spectrogram(signal, config),
        mfcc=mfcc(signal, config),
        formants=track_formants(signal, 3, config),
        rms_db=frame_rms_db(signal, config.hop_length),
    )
