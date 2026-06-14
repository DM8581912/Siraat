# Recitation + Tajweed evaluation harness

This is the objective scoreboard for making Siraat's recite-along and tajweed feedback
measurably better than Tarteel. "Better" is not a vibe; it is these numbers, tracked on every
PR. Nothing in this directory ships in the app.

## Why two tiers

| Tier | File | Runs | Role |
|---|---|---|---|
| **CI gate (Swift)** | `SiraatTests/RecitationEvalHarness.swift` + `…HarnessTests.swift` | every CI run, milliseconds, no model, no audio | the merge gate: pins the baseline and **fails the build on an honesty regression** |
| **Offline (Python)** | `Scripts/eval_harness.py` | manually, on a dev machine, against real corpora | scores the on-device engine on real recitation audio and reports the same metrics at scale |

The Swift tier is model-free on purpose: we always know the target text, so we can drive the
engines with synthetic transcripts and synthetic forced-alignments and measure their logic
deterministically. The 90 MB acoustic model and the multi-hour corpora never enter CI or the
repo. Recitation audio stays on-device; the offline manifest carries only derived labels.

## The metrics

Follow-along (word level):
- **follow-completeness** — of the words a reciter truly recited correctly, the fraction the
  engine confirmed (green). Low = the engine can't keep up (the index matcher collapses on a
  leading isti'adha or a repeated word).
- **hard false-positive rate** — of truly-correct words, the fraction given a hard error
  verdict. **This is the honesty number and must stay 0.** A correct reciter is never accused.
- **mistake precision / recall** — detecting real skips and substitutions. Precision first
  (>= 0.95 target); recall reported per error type.

Tajweed (character level):
- **false-positive rate on green truth** — must stay 0 (honesty under low confidence and when
  no model is bundled).
- **per-rule precision / recall** — Madd length, Ghunnah duration, confident wrong letter today;
  qalqalah / idgham / ikhfa as detectors are added and clear the precision floor.

## Targets (the bar)

| Metric | Baseline (M0) | Target |
|---|---|---|
| follow-completeness | 0.61 | > 0.95 (M2) |
| hard false-positive rate | 0% | 0% (never regress) |
| mistake recall | 0.00 | >= 0.95 precision, recall reported per type (M3) |
| tajweed false-positive rate | 0% | 0% (never regress) |
| tajweed per-rule (covered) | P 1.0 / R 1.0 | hold; expand coverage, Qari-signed (M4–M5) |

See `baseline.json` for the committed snapshot. The Swift tests assert the honesty invariants
hard and pin the baseline so a changed number forces an intentional re-baseline.

## Datasets (offline tier)

- **IqraEval / QuranMB** (ArabicNLP 2025 shared task) — first public Qur'anic mispronunciation
  benchmark: a 68-phoneme inventory, labeled test set, CC-licensed. Primary source of seeded /
  real mistake labels. `huggingface.co/IqraEval`, GitHub `Iqra-Eval`.
- **EveryAyah** — 26 professional reciters, full Qur'an, some word-level timing. Cross-voice
  robustness (speed, register).

To score real audio: run the engine over a corpus, emit a predictions manifest (schema in
`Scripts/eval_harness.py`), then `python Scripts/eval_harness.py manifest.json --baseline eval/baseline.json`.
