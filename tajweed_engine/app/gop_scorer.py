"""Goodness of Pronunciation (GOP) scoring for Makharij validation.

GOP is the classic posterior-based confidence measure for Computer-Assisted
Pronunciation Training. For a phoneme :math:`p` aligned to frames
:math:`[t_{start}, t_{end}]`:

.. math::

    GOP(p) = \\frac{1}{t_{end}-t_{start}+1}
             \\sum_{t=t_{start}}^{t_{end}}
             \\left[ \\log P(p \\mid o_t) - \\max_q \\log P(q \\mid o_t) \\right]

The score is :math:`\\le 0`; values near 0 mean the model is confident the
intended phoneme was produced (correct *makhraj*), while strongly negative
values indicate the articulation point was missed. A configurable per-phoneme
threshold turns the continuous score into a pass/fail verdict.

This layer consumes the emission matrix and aligned phoneme spans from
:mod:`app.alignment_engine`; it does not look at raw audio.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Optional, Sequence

import numpy as np

from .alignment_engine import AlignedPhoneme, LogProbArray, PHONEME_INVENTORY


class GOPStatus(str, Enum):
    PASSED = "passed"
    WEAK = "weak"
    FAILED = "failed"


@dataclass(frozen=True)
class GOPConfig:
    """Thresholds for turning a raw GOP score into a verdict.

    GOP values are non-positive. ``fail_threshold`` is the floor below which a
    phoneme is a clear Makhraj error; the band between it and ``weak_threshold``
    is flagged as borderline. Per-phoneme overrides accommodate sounds that are
    intrinsically harder for the model to score (e.g. emphatics, the hamza)."""

    weak_threshold: float = -1.5
    fail_threshold: float = -3.0
    per_phoneme_fail: dict[str, float] = field(default_factory=dict)

    def fail_for(self, symbol: str) -> float:
        return self.per_phoneme_fail.get(symbol, self.fail_threshold)


@dataclass
class PhonemeScore:
    """The GOP verdict for a single aligned phoneme."""

    symbol: str
    grapheme_index: int
    gop_score: float
    status: GOPStatus
    start_time: float
    end_time: float
    error: Optional[str] = None

    @property
    def confidence(self) -> float:
        """A 0..1 confidence derived from the GOP score (1 = perfect)."""
        # Map GOP in [-6, 0] -> [0, 1] with a smooth clamp.
        return float(np.clip(1.0 + self.gop_score / 6.0, 0.0, 1.0))


def frame_gop(emission: LogProbArray, token_id: int,
              start_frame: int, end_frame: int) -> float:
    """Compute the GOP score for one token over an inclusive frame span."""
    span = emission[start_frame : end_frame + 1]
    if span.shape[0] == 0:
        return float("-inf")
    log_p = span[:, token_id]
    best = np.max(span, axis=1)
    return float(np.mean(log_p - best))


class GOPScorer:
    """Scores aligned phonemes against the emission matrix."""

    def __init__(self, config: GOPConfig = GOPConfig()) -> None:
        self.config = config

    def _verdict(self, symbol: str, score: float) -> tuple[GOPStatus, Optional[str]]:
        if score < self.config.fail_for(symbol):
            return GOPStatus.FAILED, f"Makhraj error: '{symbol}' articulation unclear"
        if score < self.config.weak_threshold:
            return GOPStatus.WEAK, f"Weak articulation of '{symbol}'"
        return GOPStatus.PASSED, None

    def score_phoneme(self, emission: LogProbArray,
                      phoneme: AlignedPhoneme) -> PhonemeScore:
        gop = frame_gop(emission, phoneme.token_id,
                        phoneme.start_frame, phoneme.end_frame)
        status, error = self._verdict(phoneme.symbol, gop)
        return PhonemeScore(
            symbol=phoneme.symbol,
            grapheme_index=phoneme.grapheme_index,
            gop_score=round(gop, 4),
            status=status,
            start_time=round(phoneme.start_time, 4),
            end_time=round(phoneme.end_time, 4),
            error=error,
        )

    def score(self, emission: LogProbArray,
              phonemes: Sequence[AlignedPhoneme]) -> list[PhonemeScore]:
        """Score every aligned phoneme; preserves recitation order."""
        return [self.score_phoneme(emission, p) for p in phonemes]

    @staticmethod
    def summary(scores: Sequence[PhonemeScore]) -> dict[str, object]:
        """Aggregate per-phoneme scores into a word/utterance verdict."""
        if not scores:
            return {"status": "empty", "mean_gop": 0.0, "failed": []}
        mean = float(np.mean([s.gop_score for s in scores]))
        failed = [s.symbol for s in scores if s.status is GOPStatus.FAILED]
        weak = [s.symbol for s in scores if s.status is GOPStatus.WEAK]
        if failed:
            status = "incorrect"
        elif weak:
            status = "borderline"
        else:
            status = "correct"
        return {
            "status": status,
            "mean_gop": round(mean, 4),
            "failed": failed,
            "weak": weak,
        }


def vocab_label(token_id: int) -> str:
    """Resolve a token id back to its phoneme symbol (for diagnostics)."""
    if 0 <= token_id < len(PHONEME_INVENTORY):
        return PHONEME_INVENTORY[token_id]
    return f"<unk:{token_id}>"
