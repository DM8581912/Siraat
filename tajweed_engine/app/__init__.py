"""Siraat Tajweed Engine.

A modular, real-time Quranic Tajweed and phonetic verification engine.

The package is split into five cooperating layers:

* :mod:`app.audio_processing` -- normalization, VAD and acoustic feature extraction.
* :mod:`app.alignment_engine` -- forced alignment of audio frames to phonemes.
* :mod:`app.gop_scorer` -- Goodness of Pronunciation scoring for Makharij.
* :mod:`app.tajweed_rules` -- DSP heuristics for Madd, Ghunnah and Qalqalah.
* :mod:`app.server` -- a FastAPI WebSocket streaming front end.

Religious-content note
----------------------
This engine evaluates *acoustic* properties of a recitation. It never
generates, alters or guesses Quranic text. Canonical text and its phoneme
mapping are supplied by the caller from a verified source; the engine only
scores audio against that supplied target.
"""

from __future__ import annotations

__version__ = "0.1.0"

__all__ = [
    "audio_processing",
    "alignment_engine",
    "gop_scorer",
    "tajweed_rules",
    "server",
]
