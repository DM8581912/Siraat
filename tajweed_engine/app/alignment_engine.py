"""Forced alignment of audio frames to a canonical phoneme sequence.

The alignment engine answers one question: *given this audio and the phoneme
sequence the reciter is supposed to produce, where (in frames) does each
phoneme start and end?* Those spans are the substrate for GOP scoring and the
Tajweed DSP rules.

Two pieces cooperate:

* An :class:`AcousticModel` produces a frame-level emission matrix of token
  log-probabilities. In production this is a Wav2Vec2-Large-XLSR-53 model
  fine-tuned on Quranic Arabic phonemes. When ``transformers``/``torch`` are
  unavailable, :class:`MockAcousticModel` synthesizes a deterministic emission
  matrix biased toward the target sequence so the pipeline stays exercisable.
* A CTC forced aligner (:func:`forced_align`) runs Viterbi over the emission
  trellis constrained to the target token order, then collapses the path into
  per-phoneme frame spans.

Religious-content note: this module never invents Quranic text. The caller
passes canonical, verified text; :func:`text_to_phonemes` only transliterates
graphemes into the model's phoneme inventory.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, Protocol, Sequence

import numpy as np
from numpy.typing import NDArray

from .audio_processing import AudioConfig, FloatArray

LogProbArray = NDArray[np.float32]


# ---------------------------------------------------------------------------
# Phoneme inventory
# ---------------------------------------------------------------------------
# A compact phonetic inventory for Modern Standard / Quranic Arabic. Symbols are
# ASCII transliterations used purely as model token labels; they are not text
# shown to a user. ``_`` suffixes mark Tajweed-relevant variants the rule layer
# inspects (e.g. an emphatic or a nasalized consonant).
PHONEME_INVENTORY: tuple[str, ...] = (
    "<blank>",
    # short + long vowels
    "a", "i", "u", "aa", "ii", "uu",
    # plosives (qalqalah set marked with _q where it can bounce)
    "b", "t", "d", "k", "q", "j", "T", "D", "g",
    # nasals (ghunnah-bearing when geminated/assimilated -> _gh)
    "m", "n", "m_gh", "n_gh",
    # fricatives / sibilants
    "f", "s", "z", "S", "sh", "th", "dh", "Z", "x", "gh_", "H", "3", "h",
    # liquids / glides / others
    "l", "r", "w", "y", "hamza",
)

PHONEME_TO_ID: dict[str, int] = {p: i for i, p in enumerate(PHONEME_INVENTORY)}
BLANK_ID: int = PHONEME_TO_ID["<blank>"]

# Qalqalah-bearing plosives and ghunnah-bearing nasals, for the rule layer.
QALQALAH_PHONEMES: frozenset[str] = frozenset({"q", "T", "b", "j", "d"})
GHUNNAH_PHONEMES: frozenset[str] = frozenset({"m_gh", "n_gh"})
LONG_VOWELS: frozenset[str] = frozenset({"aa", "ii", "uu"})

# Minimal grapheme -> phoneme map. Diacritics that drive Tajweed (shaddah,
# sukun, the madd letters) are interpreted by the caller's verified blueprint;
# this map only provides a default consonant/vowel skeleton.
_GRAPHEME_MAP: dict[str, str] = {
    "ا": "aa", "أ": "hamza", "إ": "hamza", "آ": "aa", "ء": "hamza", "ئ": "hamza",
    "ؤ": "hamza", "ب": "b", "ت": "t", "ث": "th", "ج": "j", "ح": "H", "خ": "x",
    "د": "d", "ذ": "dh", "ر": "r", "ز": "z", "س": "s", "ش": "sh", "ص": "S",
    "ض": "D", "ط": "T", "ظ": "Z", "ع": "3", "غ": "gh_", "ف": "f", "ق": "q",
    "ك": "k", "ل": "l", "م": "m", "ن": "n", "ه": "h", "و": "w", "ي": "y",
    "ى": "aa", "ة": "t",
    # short-vowel diacritics
    "َ": "a", "ِ": "i", "ُ": "u",
}


@dataclass(frozen=True)
class Phoneme:
    """A target phoneme with its model token id and source grapheme index."""

    symbol: str
    token_id: int
    grapheme_index: int


def text_to_phonemes(text: str) -> list[Phoneme]:
    """Transliterate verified Arabic text into the model's phoneme tokens.

    This is a deterministic skeleton mapping. For shipping accuracy the caller
    should supply a verified per-ayah phoneme blueprint (with shaddah/sukun and
    Madd annotations); see ``Scripts/README_tajweed_model.md`` in the repo.
    """
    phonemes: list[Phoneme] = []
    for idx, ch in enumerate(text):
        sym = _GRAPHEME_MAP.get(ch)
        if sym is None:
            continue
        phonemes.append(Phoneme(sym, PHONEME_TO_ID[sym], idx))
    return phonemes


# ---------------------------------------------------------------------------
# Acoustic model abstraction
# ---------------------------------------------------------------------------
class AcousticModel(Protocol):
    """Anything that maps a waveform to frame-level token log-probabilities."""

    hop_length: int

    def emissions(self, signal: FloatArray) -> LogProbArray:
        """Return log-probabilities of shape (n_frames, vocab_size)."""
        ...


def _log_softmax(logits: NDArray[np.floating], axis: int = -1) -> LogProbArray:
    shifted = logits - np.max(logits, axis=axis, keepdims=True)
    log_sum = np.log(np.sum(np.exp(shifted), axis=axis, keepdims=True))
    return (shifted - log_sum).astype(np.float32)


class MockAcousticModel:
    """Deterministic stand-in for the fine-tuned Wav2Vec2 CTC model.

    It produces an emission matrix whose frames are softly biased toward the
    target token sequence in order, interleaved with blanks. This is *not* a
    recognizer -- it exists so alignment, GOP and the rule layer can be
    developed and unit-tested with no model weights present. Swap in
    :class:`Wav2Vec2AcousticModel` for real inference.
    """

    def __init__(self, config: AudioConfig = AudioConfig(),
                 frames_per_phoneme: int = 8, peak: float = 6.0,
                 seed: int = 0) -> None:
        self.config = config
        self.hop_length = config.hop_length
        self.vocab_size = len(PHONEME_INVENTORY)
        self.frames_per_phoneme = frames_per_phoneme
        self.peak = peak
        self._rng = np.random.default_rng(seed)
        self._target: Sequence[int] = ()

    def set_target(self, token_ids: Sequence[int]) -> None:
        """Condition the synthetic emissions on the expected token order."""
        self._target = tuple(token_ids)

    def emissions(self, signal: FloatArray) -> LogProbArray:
        n_frames = max(1, 1 + (max(0, signal.size - self.config.win_length))
                       // self.hop_length)
        logits = self._rng.normal(0.0, 1.0, size=(n_frames, self.vocab_size))
        logits[:, BLANK_ID] += 1.0
        if self._target:
            for f in range(n_frames):
                pos = int(f / max(1, n_frames) * len(self._target))
                pos = min(pos, len(self._target) - 1)
                tok = self._target[pos]
                # Bias the middle of each phoneme toward its token, edges toward blank.
                within = (f % self.frames_per_phoneme) / self.frames_per_phoneme
                strength = self.peak * (1.0 - abs(0.5 - within) * 2.0)
                logits[f, tok] += max(0.0, strength)
        return _log_softmax(logits, axis=-1)


class Wav2Vec2AcousticModel:  # pragma: no cover - requires torch/transformers
    """Real acoustic model backed by a fine-tuned Wav2Vec2 CTC head.

    Loads a Hugging Face ``Wav2Vec2ForCTC`` checkpoint (e.g. a Quranic-Arabic
    fine-tune of ``facebook/wav2vec2-large-xlsr-53``) and exposes frame-level
    log-probabilities. The model's own tokenizer vocabulary must be reconciled
    with :data:`PHONEME_INVENTORY` via ``token_map``.
    """

    def __init__(self, model_name: str, token_map: dict[int, int],
                 config: AudioConfig = AudioConfig(), device: str = "cpu") -> None:
        import torch
        from transformers import Wav2Vec2ForCTC

        self.config = config
        self.hop_length = config.hop_length
        self._torch = torch
        self._device = device
        self._token_map = token_map
        self._model = Wav2Vec2ForCTC.from_pretrained(model_name).to(device).eval()

    def emissions(self, signal: FloatArray) -> LogProbArray:
        torch = self._torch
        with torch.no_grad():
            inputs = torch.from_numpy(np.ascontiguousarray(signal)).float().to(self._device)
            logits = self._model(inputs.unsqueeze(0)).logits.squeeze(0).cpu().numpy()
        remapped = np.full((logits.shape[0], len(PHONEME_INVENTORY)), -1e4, dtype=np.float32)
        for src, dst in self._token_map.items():
            remapped[:, dst] = logits[:, src]
        return _log_softmax(remapped, axis=-1)


# ---------------------------------------------------------------------------
# CTC forced alignment
# ---------------------------------------------------------------------------
@dataclass
class AlignedPhoneme:
    """A phoneme localized to a frame span and wall-clock time window."""

    symbol: str
    token_id: int
    grapheme_index: int
    start_frame: int
    end_frame: int
    config: AudioConfig
    score: float = 0.0

    @property
    def start_time(self) -> float:
        return self.start_frame * self.config.frame_seconds

    @property
    def end_time(self) -> float:
        return (self.end_frame + 1) * self.config.frame_seconds

    @property
    def duration(self) -> float:
        return self.end_time - self.start_time

    def frame_slice(self) -> slice:
        return slice(self.start_frame, self.end_frame + 1)

    def frame_slice_samples(self, config: Optional[AudioConfig] = None) -> slice:
        """The waveform sample span covered by this phoneme's frames."""
        cfg = config or self.config
        return slice(self.start_frame * cfg.hop_length,
                     (self.end_frame + 1) * cfg.hop_length)


def _build_trellis(emission: LogProbArray, tokens: Sequence[int],
                   blank_id: int) -> tuple[NDArray[np.float32], list[int]]:
    """Construct the CTC alignment trellis for a fixed token sequence.

    The token sequence is expanded with blanks between every label and at the
    boundaries: ``[blank, t0, blank, t1, ..., blank]``. Returns the trellis and
    the expanded token list.
    """
    expanded: list[int] = [blank_id]
    for t in tokens:
        expanded.append(t)
        expanded.append(blank_id)

    n_frames = emission.shape[0]
    n_states = len(expanded)
    neg_inf = np.float32(-1e9)
    trellis = np.full((n_frames, n_states), neg_inf, dtype=np.float32)
    trellis[0, 0] = emission[0, expanded[0]]
    if n_states > 1:
        trellis[0, 1] = emission[0, expanded[1]]
    return trellis, expanded


def forced_align(emission: LogProbArray, tokens: Sequence[int],
                 config: AudioConfig = AudioConfig(),
                 blank_id: int = BLANK_ID) -> list[tuple[int, int, int, float]]:
    """Viterbi forced alignment of ``emission`` to ``tokens``.

    Returns one ``(token_id, start_frame, end_frame, mean_score)`` tuple per
    non-blank token in order. Raises ``ValueError`` when the audio is too short
    to contain the required tokens.
    """
    if len(tokens) == 0:
        return []
    trellis, expanded = _build_trellis(emission, tokens, blank_id)
    n_frames, n_states = trellis.shape
    if n_frames < len(tokens):
        raise ValueError(
            f"audio too short: {n_frames} frames for {len(tokens)} tokens"
        )

    backptr = np.zeros((n_frames, n_states), dtype=np.int32)
    for f in range(1, n_frames):
        for s in range(n_states):
            best_prev, best_val = s, trellis[f - 1, s]
            if s - 1 >= 0 and trellis[f - 1, s - 1] > best_val:
                best_prev, best_val = s - 1, trellis[f - 1, s - 1]
            # A label state may be entered from two-back, skipping a blank,
            # only when the surrounding labels differ.
            if s - 2 >= 0 and expanded[s] != blank_id and \
                    expanded[s] != expanded[s - 2] and trellis[f - 1, s - 2] > best_val:
                best_prev, best_val = s - 2, trellis[f - 1, s - 2]
            trellis[f, s] = best_val + emission[f, expanded[s]]
            backptr[f, s] = best_prev

    # Backtrack from whichever terminal state (last label or trailing blank) wins.
    end_state = n_states - 1
    if n_states >= 2 and trellis[n_frames - 1, n_states - 2] > trellis[n_frames - 1, end_state]:
        end_state = n_states - 2
    path = np.zeros(n_frames, dtype=np.int32)
    state = end_state
    for f in range(n_frames - 1, -1, -1):
        path[f] = state
        state = backptr[f, state]

    # Collapse the state path into per-label frame spans.
    results: list[tuple[int, int, int, float]] = []
    for label_idx, token in enumerate(tokens):
        state_idx = 2 * label_idx + 1  # label states are at odd positions
        frames = np.where(path == state_idx)[0]
        if frames.size == 0:
            # Degenerate alignment: assign a single nearest frame, score it low.
            approx = min(n_frames - 1, int(round(state_idx / n_states * n_frames)))
            results.append((token, approx, approx, float(emission[approx, token])))
            continue
        start, end = int(frames[0]), int(frames[-1])
        score = float(np.mean(emission[start : end + 1, token]))
        results.append((token, start, end, score))
    return results


class ForcedAligner:
    """High-level wrapper: text + audio -> aligned phonemes."""

    def __init__(self, model: AcousticModel, config: AudioConfig = AudioConfig()) -> None:
        self.model = model
        self.config = config

    def align(self, signal: FloatArray,
              phonemes: Sequence[Phoneme]) -> tuple[list[AlignedPhoneme], LogProbArray]:
        """Align ``signal`` to ``phonemes``; returns spans plus the emission matrix."""
        if isinstance(self.model, MockAcousticModel):
            self.model.set_target([p.token_id for p in phonemes])
        emission = self.model.emissions(signal)
        token_ids = [p.token_id for p in phonemes]
        spans = forced_align(emission, token_ids, self.config)
        aligned: list[AlignedPhoneme] = []
        for phoneme, (tok, start, end, score) in zip(phonemes, spans):
            aligned.append(
                AlignedPhoneme(
                    symbol=phoneme.symbol,
                    token_id=tok,
                    grapheme_index=phoneme.grapheme_index,
                    start_frame=start,
                    end_frame=end,
                    config=self.config,
                    score=score,
                )
            )
        return aligned, emission

    def align_text(self, signal: FloatArray,
                   text: str) -> tuple[list[AlignedPhoneme], LogProbArray]:
        return self.align(signal, text_to_phonemes(text))
