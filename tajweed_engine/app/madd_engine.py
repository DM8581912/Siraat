"""Stateful, pace-relative Madd (elongation) engine.

This is the high-level entry point the directive calls ``TajweedMaddEngine``. It
wraps the stateless :func:`evaluate_madd_spec` DSP with the two things that make
Madd judging *religiously* correct rather than a fixed-threshold gate:

1. **Pace relativity.** Madd length is a ratio (2 : 4 : 6) of the reciter's own
   single ``harakah``, which varies from slow Tahqiq to fast Hadr. The engine
   abandons fixed millisecond constants: it calibrates the harakah unit from the
   first stable natural (2-count) madd it hears and judges every subsequent madd
   relative to that. Until it is calibrated, a non-natural madd returns
   ``PENDING_CALIBRATION`` rather than being judged against a guessed constant.

2. **Blueprint-driven types.** The engine never guesses which madd a position is.
   It applies the :class:`MaddSpec` the verified blueprint phoneme resolves to
   (explicit ``maddType`` -> exact ``expectedMaddCount`` -> default 2-count).

The Hafs 'an 'Asim rules map itself lives in :mod:`app.tajweed_rules`
(``MaddType`` / ``_MADD_SPEC``); this class orchestrates it.
"""

from __future__ import annotations

from typing import Optional

from .audio_processing import FloatArray
from .blueprint import CanonicalPhoneme
from .tajweed_rules import (
    MaddResult,
    MaddSpec,
    MaddType,
    RuleStatus,
    TajweedConfig,
    calibrate_harakah,
    evaluate_madd_spec,
    is_pitch_stable,
    madd_spec,
)


class TajweedMaddEngine:
    """Evaluate Madd elongations relative to a reciter's calibrated pace."""

    def __init__(self, config: TajweedConfig = TajweedConfig()) -> None:
        self.config = config
        self._harakah_seconds: Optional[float] = None

    # -- calibration state ---------------------------------------------------
    @property
    def harakah_seconds(self) -> Optional[float]:
        """The reciter's calibrated single-count duration, or None if not yet set."""
        return self._harakah_seconds

    @property
    def is_calibrated(self) -> bool:
        return self._harakah_seconds is not None

    def reset(self) -> None:
        """Forget the calibrated pace (e.g. when a new reciter connects)."""
        self._harakah_seconds = None

    def calibrate_from(self, natural_madd_segment: FloatArray) -> float:
        """Anchor the harakah unit to a known natural (2-count) madd segment."""
        self._harakah_seconds = calibrate_harakah(natural_madd_segment, self.config)
        return self._harakah_seconds

    # -- evaluation ----------------------------------------------------------
    def evaluate(self, audio_segment: FloatArray, *,
                 madd_type: Optional[MaddType] = None,
                 expected_count: Optional[int] = None,
                 phoneme_duration: Optional[float] = None) -> MaddResult:
        """Evaluate one madd segment against its resolved specification.

        Resolution precedence matches the blueprint: explicit ``madd_type`` ->
        exact ``expected_count`` -> default natural 2-count. Self-calibrates from
        the segment when it is a stable natural madd and no pace is known yet.
        """
        spec, label = self._resolve_spec(madd_type, expected_count)
        return self._evaluate(audio_segment, spec, label, phoneme_duration)

    def evaluate_phoneme(self, audio_segment: FloatArray,
                         phoneme: CanonicalPhoneme, *,
                         phoneme_duration: Optional[float] = None) -> MaddResult:
        """Evaluate using a blueprint :class:`CanonicalPhoneme`'s madd annotation."""
        spec, label = phoneme.madd_specification()
        return self._evaluate(audio_segment, spec, label, phoneme_duration)

    # -- internals -----------------------------------------------------------
    @staticmethod
    def _resolve_spec(madd_type: Optional[MaddType],
                      expected_count: Optional[int]) -> tuple[MaddSpec, str]:
        if madd_type is not None:
            return madd_spec(madd_type), madd_type.value
        if expected_count is not None and expected_count != 2:
            return (MaddSpec((expected_count,), True, f"exact {expected_count}-count"),
                    f"madd_{expected_count}")
        return madd_spec(MaddType.TABEE), MaddType.TABEE.value

    def _evaluate(self, audio_segment: FloatArray, spec: MaddSpec, label: str,
                  phoneme_duration: Optional[float]) -> MaddResult:
        # A natural-length madd (one that legitimately allows 2 counts) is our
        # calibration anchor: if we have no pace yet and it is steady, adopt it.
        is_natural = 2 in spec.allowed_counts
        if not self.is_calibrated and is_natural and is_pitch_stable(audio_segment, self.config):
            self.calibrate_from(audio_segment)

        if not self.is_calibrated:
            # No fixed-constant fallback: we cannot judge a longer madd in harakat
            # until a natural madd has set the reciter's pace.
            duration = (phoneme_duration if phoneme_duration is not None
                        else audio_segment.size / self.config.sample_rate)
            return MaddResult(
                status=RuleStatus.PENDING_CALIBRATION,
                madd_type=label,
                measured_seconds=round(duration, 4),
                measured_counts=0.0,
                nearest_count=spec.allowed_counts[0],
                allowed_counts=spec.allowed_counts,
                harakah_seconds=0.0,
                pitch_stable=is_pitch_stable(audio_segment, self.config),
                error="Awaiting a natural madd to calibrate the reciter's pace",
            )

        return evaluate_madd_spec(
            audio_segment, spec, label, self.config,
            harakah_seconds=self._harakah_seconds,
            phoneme_duration=phoneme_duration,
        )
