"""Acoustic Tajweed rule layer (Madd, Ghunnah, Qalqalah).

GOP tells us *whether the right sound was produced*; this layer tells us
*whether the Tajweed property of that sound was honored*. It is a DSP +
heuristic layer operating directly on the standardized waveform segment for a
phoneme, using the frame timeline from :mod:`app.audio_processing`.

Three rules are implemented:

* **Madd** -- prolongation. Measures the voiced, pitch-stable duration of a
  long vowel and checks it against the required 2 / 4 / 6 ``harakah`` counts.
* **Ghunnah** -- nasalization of a geminated/assimilated *noon* or *meem*.
  Measures sustained nasal-band energy and checks it spans at least 2 counts.
* **Qalqalah** -- the echo "bounce" on a sukun *qaf/taa/baa/jeem/daal*. Looks
  for a high-amplitude release transient (a spike in dE/dt) just after the
  consonant closure.

These are heuristics tuned against reference recitation; thresholds live in
:class:`TajweedConfig` and should be calibrated per acoustic model. The layer
never decides what the *correct text* is -- only how an acoustic event sounds.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional

import numpy as np

from .audio_processing import AudioConfig, FloatArray, frame_signal


class RuleStatus(str, Enum):
    PASSED = "passed"
    FAILED = "failed"
    NOT_APPLICABLE = "n/a"


@dataclass(frozen=True)
class TajweedConfig:
    """Tunable constants for the acoustic Tajweed heuristics."""

    sample_rate: int = 16_000
    # One harakah (count). Tarteel/Tadweer/Tahqeeq vary; ~0.25-0.30 s is typical.
    harakah_seconds: float = 0.275
    madd_count_tolerance: float = 0.30   # +/- fraction of one count allowed
    # Pitch tracking (AMDF).
    pitch_frame_ms: float = 40.0
    pitch_hop_ms: float = 10.0
    pitch_min_hz: float = 75.0
    pitch_max_hz: float = 400.0
    pitch_voiced_threshold: float = 0.30   # min voiced-frame ratio for "stable"
    pitch_cv_max: float = 0.20             # max coefficient of variation of f0
    # Ghunnah band energy.
    nasal_band_hz: tuple[float, float] = (90.0, 1_000.0)
    oral_band_hz: tuple[float, float] = (1_000.0, 3_000.0)
    nasal_ratio_threshold: float = 1.0     # nasal/oral energy ratio to count as nasal
    ghunnah_min_counts: float = 2.0
    # Qalqalah transient.
    qalqalah_search_ms: float = 80.0       # window after closure to scan
    qalqalah_denergy_threshold: float = 4.0  # min normalized dE/dt of the burst

    def counts_to_seconds(self, counts: float) -> float:
        return counts * self.harakah_seconds


# ---------------------------------------------------------------------------
# Pitch tracking (AMDF) -- supports the Madd stability check
# ---------------------------------------------------------------------------
def amdf_pitch(signal: FloatArray, sample_rate: int, min_hz: float,
               max_hz: float) -> tuple[float, float]:
    """Estimate (f0_hz, voicing) for one frame via Average Magnitude Difference.

    ``voicing`` in [0, 1] is ``1 - min_amdf/mean_amdf``; higher means a clearer
    periodicity. Returns ``(0.0, 0.0)`` when no plausible lag is found.
    """
    n = signal.size
    if n < 2:
        return 0.0, 0.0
    min_lag = max(1, int(sample_rate / max_hz))
    max_lag = min(n - 1, int(sample_rate / min_hz))
    if max_lag <= min_lag:
        return 0.0, 0.0
    lags = np.arange(min_lag, max_lag + 1)
    amdf = np.empty(lags.size, dtype=np.float32)
    for i, lag in enumerate(lags):
        amdf[i] = np.mean(np.abs(signal[lag:] - signal[:-lag]))
    mean_amdf = float(np.mean(amdf)) + 1e-9
    best = int(np.argmin(amdf))
    best_lag = int(lags[best])
    voicing = 1.0 - float(amdf[best]) / mean_amdf
    f0 = sample_rate / best_lag
    return float(f0), float(np.clip(voicing, 0.0, 1.0))


def pitch_track(signal: FloatArray, config: TajweedConfig) -> tuple[np.ndarray, np.ndarray]:
    """Frame-wise pitch track -> (f0_hz[n_frames], voicing[n_frames])."""
    frame_len = int(config.sample_rate * config.pitch_frame_ms / 1000.0)
    hop = int(config.sample_rate * config.pitch_hop_ms / 1000.0)
    if signal.size < frame_len:
        f0, v = amdf_pitch(signal, config.sample_rate,
                           config.pitch_min_hz, config.pitch_max_hz)
        return np.array([f0], dtype=np.float32), np.array([v], dtype=np.float32)
    frames = frame_signal(signal, frame_len, hop)
    f0s = np.empty(frames.shape[0], dtype=np.float32)
    voi = np.empty(frames.shape[0], dtype=np.float32)
    for i, fr in enumerate(frames):
        f0s[i], voi[i] = amdf_pitch(fr, config.sample_rate,
                                    config.pitch_min_hz, config.pitch_max_hz)
    return f0s, voi


# ---------------------------------------------------------------------------
# Band energy -- supports the Ghunnah check
# ---------------------------------------------------------------------------
def band_energy(signal: FloatArray, sample_rate: int,
                low_hz: float, high_hz: float) -> float:
    """Total spectral energy of a segment within [low_hz, high_hz]."""
    if signal.size == 0:
        return 0.0
    spectrum = np.abs(np.fft.rfft(signal * np.hanning(signal.size))) ** 2
    freqs = np.fft.rfftfreq(signal.size, d=1.0 / sample_rate)
    mask = (freqs >= low_hz) & (freqs < high_hz)
    return float(np.sum(spectrum[mask]))


# ---------------------------------------------------------------------------
# Rule results
# ---------------------------------------------------------------------------
@dataclass
class MaddResult:
    status: RuleStatus
    measured_seconds: float
    measured_counts: float
    target_counts: int
    pitch_stable: bool
    error: Optional[str] = None


@dataclass
class GhunnahResult:
    status: RuleStatus
    nasal_seconds: float
    nasal_counts: float
    mean_nasal_ratio: float
    error: Optional[str] = None


@dataclass
class QalqalahResult:
    status: RuleStatus
    peak_denergy: float
    burst_time: Optional[float]
    error: Optional[str] = None


# ---------------------------------------------------------------------------
# Madd
# ---------------------------------------------------------------------------
def evaluate_madd(audio_segment: FloatArray, target_counts: int,
                  config: TajweedConfig = TajweedConfig(),
                  phoneme_duration: Optional[float] = None) -> MaddResult:
    """Check whether a prolonged vowel meets its required ``target_counts``.

    The vowel must be both long *enough* and *stable* (continuous voicing with
    low pitch variance) -- a wavering or clipped vowel fails even if its raw
    duration is sufficient.
    """
    duration = (phoneme_duration if phoneme_duration is not None
                else audio_segment.size / config.sample_rate)
    f0s, voi = pitch_track(audio_segment, config)
    voiced_mask = voi >= 0.30
    voiced_ratio = float(np.mean(voiced_mask)) if voi.size else 0.0
    voiced_f0 = f0s[voiced_mask]
    if voiced_f0.size >= 2 and np.mean(voiced_f0) > 0:
        cv = float(np.std(voiced_f0) / (np.mean(voiced_f0) + 1e-9))
    else:
        cv = 1.0
    pitch_stable = (voiced_ratio >= config.pitch_voiced_threshold
                    and cv <= config.pitch_cv_max)

    measured_counts = duration / config.harakah_seconds
    target_seconds = config.counts_to_seconds(target_counts)
    tol = config.counts_to_seconds(config.madd_count_tolerance)

    if not pitch_stable:
        return MaddResult(RuleStatus.FAILED, round(duration, 4),
                          round(measured_counts, 2), target_counts, False,
                          "Madd vowel is not continuous/stable")
    if duration < target_seconds - tol:
        return MaddResult(RuleStatus.FAILED, round(duration, 4),
                          round(measured_counts, 2), target_counts, True,
                          f"Madd too short: {measured_counts:.1f} of "
                          f"{target_counts} counts")
    if duration > target_seconds + tol * 2:
        return MaddResult(RuleStatus.FAILED, round(duration, 4),
                          round(measured_counts, 2), target_counts, True,
                          f"Madd over-prolonged: {measured_counts:.1f} counts")
    return MaddResult(RuleStatus.PASSED, round(duration, 4),
                      round(measured_counts, 2), target_counts, True)


# ---------------------------------------------------------------------------
# Ghunnah
# ---------------------------------------------------------------------------
def evaluate_ghunnah(audio_segment: FloatArray,
                     config: TajweedConfig = TajweedConfig()) -> GhunnahResult:
    """Check the nasalization (and its duration) of a noon/meem mushaddadah.

    Slides a short window across the segment, measuring nasal-band / oral-band
    energy per window. The contiguous span where that ratio stays above
    threshold is the nasal hold; it must last at least ``ghunnah_min_counts``.
    """
    frame_len = int(config.sample_rate * 0.025)
    hop = int(config.sample_rate * 0.010)
    if audio_segment.size < frame_len:
        ratio = (band_energy(audio_segment, config.sample_rate, *config.nasal_band_hz)
                 / (band_energy(audio_segment, config.sample_rate, *config.oral_band_hz) + 1e-9))
        nasal = audio_segment.size / config.sample_rate if ratio >= config.nasal_ratio_threshold else 0.0
        ratios = np.array([ratio], dtype=np.float32)
    else:
        frames = frame_signal(audio_segment, frame_len, hop)
        ratios = np.empty(frames.shape[0], dtype=np.float32)
        for i, fr in enumerate(frames):
            n = band_energy(fr, config.sample_rate, *config.nasal_band_hz)
            o = band_energy(fr, config.sample_rate, *config.oral_band_hz)
            ratios[i] = n / (o + 1e-9)
        # Longest contiguous run above threshold.
        above = ratios >= config.nasal_ratio_threshold
        nasal = _longest_run_seconds(above, hop, config.sample_rate)

    nasal_counts = nasal / config.harakah_seconds
    mean_ratio = float(np.mean(ratios)) if ratios.size else 0.0
    if nasal_counts + 1e-6 < config.ghunnah_min_counts:
        return GhunnahResult(RuleStatus.FAILED, round(nasal, 4),
                             round(nasal_counts, 2), round(mean_ratio, 3),
                             "Ghunnah duration insufficient")
    return GhunnahResult(RuleStatus.PASSED, round(nasal, 4),
                         round(nasal_counts, 2), round(mean_ratio, 3))


def _longest_run_seconds(mask: np.ndarray, hop: int, sample_rate: int) -> float:
    best = run = 0
    for v in mask:
        run = run + 1 if v else 0
        best = max(best, run)
    return best * hop / sample_rate


# ---------------------------------------------------------------------------
# Qalqalah
# ---------------------------------------------------------------------------
def evaluate_qalqalah(audio_segment: FloatArray, closure_time: float,
                      config: TajweedConfig = TajweedConfig()) -> QalqalahResult:
    """Detect the release burst that gives a sukun qalqalah letter its bounce.

    ``closure_time`` is the time (seconds, relative to ``audio_segment``) of the
    consonant closure. The function scans the following ``qalqalah_search_ms``
    for a sharp rise in the short-time energy envelope (the plosive release);
    a peak dE/dt below threshold means the bounce was not produced.
    """
    sr = config.sample_rate
    win = int(sr * 0.005)            # 5 ms energy window
    hop = max(1, int(sr * 0.0025))   # 2.5 ms hop
    start = max(0, int(closure_time * sr))
    end = min(audio_segment.size, start + int(sr * config.qalqalah_search_ms / 1000.0))
    region = audio_segment[start:end]
    if region.size < win + hop:
        return QalqalahResult(RuleStatus.NOT_APPLICABLE, 0.0, None,
                              "Insufficient audio after closure")

    frames = frame_signal(region, win, hop)
    energy = np.sqrt(np.mean(frames ** 2, axis=1) + 1e-12)
    # Normalize so the threshold is recording-level independent.
    energy = energy / (np.max(energy) + 1e-9)
    denergy = np.diff(energy) / (hop / sr)   # per-second derivative
    if denergy.size == 0:
        return QalqalahResult(RuleStatus.NOT_APPLICABLE, 0.0, None,
                              "Insufficient audio after closure")
    peak_idx = int(np.argmax(denergy))
    peak = float(denergy[peak_idx])
    burst_time = closure_time + (peak_idx * hop) / sr
    if peak < config.qalqalah_denergy_threshold:
        return QalqalahResult(RuleStatus.FAILED, round(peak, 3), round(burst_time, 4),
                              "Missing qalqalah: no release burst detected")
    return QalqalahResult(RuleStatus.PASSED, round(peak, 3), round(burst_time, 4))
