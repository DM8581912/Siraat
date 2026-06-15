# Siraat Tajweed Engine

A modular, real-time Quranic Tajweed and phonetic verification engine. It goes
beyond text matching to evaluate **how** a verse is recited: phonetic accuracy
(*Makharij*) via a Goodness-of-Pronunciation framework, and acoustic Tajweed
rules (*Madd*, *Ghunnah*, *Qalqalah*) via a DSP/heuristic layer.

This is the Python reference/research backend for Siraat's recitation
follow-along. The shipping iOS app force-aligns and scores **entirely
on-device** (see `Scripts/README_tajweed_model.md` and the Swift
`CTCForcedAligner`); this package is the cross-platform implementation of the
same pipeline, usable for evaluation, batch scoring, and self-hosted streaming.

## Religious-correctness and privacy

- **Text is never generated.** The engine scores audio against a *canonical
  phoneme target supplied by the caller* from a verified source. It transliterates
  graphemes into model tokens; it never invents, paraphrases, or guesses Quranic
  text, verse numbers, or attributions.
- **Audio stays private.** Recitation audio is held only in the session buffer
  for the current computation and is never persisted. Run this on-device or as a
  user's own self-hosted endpoint; do not deploy it as a shared service that
  retains recordings, and do not add raw-audio logging.

## Architecture

```
tajweed_engine/
├── app/
│   ├── audio_processing.py   # 16 kHz mono normalization, VAD, mel/MFCC, LPC formants
│   ├── alignment_engine.py   # Wav2Vec2/CTC acoustic model + Viterbi forced alignment
│   ├── gop_scorer.py         # Goodness of Pronunciation (Makharij) scoring
│   ├── tajweed_rules.py      # Madd / Ghunnah / Qalqalah acoustic DSP heuristics + Hafs map
│   ├── blueprint.py          # Strict per-ayah blueprint schema (mirrors the Swift schema)
│   ├── madd_engine.py        # Stateful, pace-relative TajweedMaddEngine
│   └── server.py             # FastAPI WebSocket server (queue + background worker)
├── tests/test_engine.py
├── requirements.txt
└── README.md
```

### Signal flow

```
PCM16 chunks ─▶ audio_processing ─▶ alignment_engine ─▶ gop_scorer ──┐
            (normalize, VAD,     (emissions + Viterbi   (Makharij     │
             mel/MFCC, formants)  forced alignment)      log-LR)      ├─▶ feedback JSON
                       │                                              │
                       └────────────▶ tajweed_rules ─────────────────┘
                                     (Madd / Ghunnah / Qalqalah on
                                      each phoneme's aligned segment)
```

## Module detail

### `audio_processing.py`
Standardizes every stream to 16 kHz mono float32. Provides PCM16 ⇄ float
conversion, RMS normalization, a `SileroVAD` wrapper (neural when `torch` +
the Silero hub model are present, sliding-window RMS-energy gate otherwise),
log-mel spectrograms, MFCCs, and **F1–F3 formant tracking via LPC**
(autocorrelation + Levinson–Durbin + polynomial roots).

### `alignment_engine.py`
Defines a compact Arabic phoneme inventory and a deterministic grapheme→phoneme
map. `Wav2Vec2AcousticModel` wraps a fine-tuned `Wav2Vec2ForCTC` checkpoint
(e.g. a Quranic-Arabic fine-tune of `wav2vec2-large-xlsr-53`); `MockAcousticModel`
synthesizes target-biased emissions so the pipeline is fully exercisable with no
weights. `forced_align` runs **CTC Viterbi forced alignment** to produce per-phoneme
frame spans, which convert to time via the hop size.

### `gop_scorer.py`
Implements the posterior GOP measure over the emission matrix:

```
GOP(p) = 1/(t_end - t_start + 1) · Σ_t [ log P(p | o_t) − max_q log P(q | o_t) ]
```

Scores are ≤ 0; per-phoneme thresholds turn them into `passed` / `weak` /
`failed` verdicts. A `failed` phoneme is flagged as a **Makhraj error**.

### `tajweed_rules.py`
Acoustic heuristics on each phoneme's aligned waveform segment:

- **Madd** — measures voiced, pitch-stable duration (AMDF pitch tracking) and
  checks it against the lengths permitted for the *madd type* (natural/Badal = 2,
  Muttasil = 4–5, Lāzim = 6, Munfasil = 2/4/5, ʿĀriḍ/Leen = 2/4/6). The
  *harakah* count unit is **relative to the reciter's pace**: `calibrate_harakah`
  anchors it to a measured natural madd so Tahqīq (slow) and Hadr (fast)
  recitation are judged correctly, rather than against a fixed millisecond value.
- **Ghunnah** — measures sustained nasal-band vs oral-band energy and requires
  the nasal hold to span at least 2 counts.
- **Qalqalah** — scans the window after the consonant closure for a release
  burst (a spike in the normalized energy derivative dE/dt).

Thresholds live in `TajweedConfig` and should be calibrated per acoustic model.

### `blueprint.py`
The strict per-ayah blueprint schema — the verified *answer key*. It mirrors the
on-device Swift schema (`PhoneticBlueprint.swift`): `PhoneticBlueprintFile →
AyahPhonemeMap → CanonicalPhoneme` plus a `BlueprintProvenance{corpus,
attribution, verified}` record. `load_blueprint_file` validates the schema and,
by default, refuses to treat unverified provenance as authoritative. The engine
relies on this for every Tajweed ruling; it never guesses one.

### `madd_engine.py`
`TajweedMaddEngine` — the stateful, pace-relative entry point. It abandons fixed
millisecond constants: it calibrates the harakah unit from the first stable
natural (2-count) madd it hears, then judges every later madd relative to that
pace. Until calibrated, a non-natural madd returns `pending_calibration` rather
than being judged against a guessed constant. Madd *types* always come from the
blueprint (explicit `maddType` → exact `expectedMaddCount` → default 2-count);
the engine never invents a category.

### `server.py`
FastAPI WebSocket endpoint `/v1/stream-tajweed`. The first JSON message sets the
target ayah words; subsequent binary frames stream PCM16 (<100 ms chunks). The
receive loop only enqueues chunks onto a per-connection `asyncio.Queue`; a
background worker drains it and runs the CPU-bound DSP off the event loop, so
ingest stays responsive. A stateful `TajweedSession` buffers audio, detects word
boundaries with VAD, and emits a feedback packet per completed word. The server
is **deployment-neutral** — it runs embedded/on-device (localhost), self-hosted,
or in the cloud; it does not hardcode any remote endpoint. Packet shape:

```json
{
  "word": "مِنْ",
  "status": "correct",
  "phoneme_telemetry": [
    {"phoneme": "m", "gop_score": 0.0, "status": "passed"},
    {"phoneme": "n_gh", "gop_score": -3.4, "status": "failed",
     "error": "Makhraj error: 'n_gh' articulation unclear",
     "tajweed": {"rule": "ghunnah", "status": "failed",
                 "nasal_counts": 1.1, "error": "Ghunnah duration insufficient"}}
  ]
}
```

The pipeline classes (`TajweedPipeline`, `TajweedSession`) are framework-agnostic
and unit-tested directly; FastAPI is only imported inside `create_app()`.

## Quick start

```bash
cd tajweed_engine
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt      # or just `pip install numpy pytest` for the core

# Run the tests (NumPy + pytest only -- no ML runtime required)
python -m pytest tests -q

# Run the streaming server
uvicorn app.server:create_app --factory --host 127.0.0.1 --port 8000
```

### Programmatic use

```python
import numpy as np
from app.server import AyahTarget, TajweedSession

target = AyahTarget.from_words(["باب", "قمر"])  # supply verified canonical words
session = TajweedSession(target)

packets = session.feed(my_float32_audio)   # or session.feed_pcm(pcm16_bytes)
packets += session.flush()                 # process trailing audio at end of stream
```

## Status and limitations

- Ships with `MockAcousticModel` and the RMS-energy VAD fallback so it runs with
  no model weights. Real accuracy requires a fine-tuned Wav2Vec2 phonetic CTC
  checkpoint and per-ayah verified phoneme/Madd blueprints.
- Tajweed thresholds are reference values; calibrate against a labeled Qari set
  before relying on pass/fail verdicts.
- The streaming word-boundary segmentation is energy/VAD based; for dense
  recitation, drive boundaries from the alignment of a known ayah instead.
