# Fine-tuning the on-device Quran phoneme model

The shipped acoustic model (`TBOGamer22/wav2vec2-quran-phonetics`) is general MSA phonetics. It
gives real Madd/Ghunnah grading today, but its consonant romanization is unconfirmed and it is
not tuned to Qur'anic recitation across reciters and speeds. Fine-tuning it on real recitation
is the path from "good" to top-tier acoustic follow-along + honest tajweed measurement.

This is a **multi-day, offline, dev-machine effort** — it never runs in CI and the device never
sees any of it. Recitation audio stays on the device in production; this pipeline only touches
public corpora on a workstation.

## Pipeline

1. **Get the data** (see licensing below). Extract IqraEval/QuranMB and (optionally) EveryAyah.
2. **Build the manifest:**
   ```sh
   python Scripts/prepare_finetune_data.py \
       --iqraeval /data/IqraEval --everyayah /data/everyayah \
       --out build/finetune_manifest.jsonl --val-fraction 0.05
   python Scripts/prepare_finetune_data.py --validate build/finetune_manifest.jsonl
   ```
   Output is one normalized JSONL row per utterance: audio path, sample rate, verse key,
   reciter, Uthmani text, phoneme labels (or null), source, and a deterministic train/val split
   (hash-based, so re-runs never leak val into train).
3. **Fine-tune** wav2vec2 + CTC over the phoneme vocabulary on the labeled rows (IqraEval). The
   unlabeled EveryAyah rows are for cross-voice robustness via alignment / self-training, not
   direct CTC supervision (we never invent phoneme labels for them).
4. **Export + quantize** with the existing `Scripts/convert_wav2vec2_phonetics.py` (int8, ~90 MB)
   so the fine-tuned weights drop straight into the same on-device path.
5. **Measure** with `Scripts/eval_harness.py` against the held-out QuranMB test set and report the
   before/after PER + the follow-along / tajweed deltas in the PR. No metric, no merge.

## Datasets

| Corpus | What | Use | Licensing note |
|---|---|---|---|
| **IqraEval / QuranMB** | MSA Qur'anic recitation, 68-phoneme QPS inventory, per-utterance phoneme labels, labeled mispronunciation test set | primary CTC supervision + eval | Public (ArabicNLP 2025 shared task), `huggingface.co/IqraEval` / GitHub `Iqra-Eval`. Confirm the per-dataset license before redistribution; we store only derived labels + paths. |
| **EveryAyah** | 26 professional reciters, full Qur'an, some word-level timing | cross-voice robustness | `everyayah.com`. Reciter recordings carry their own terms; for research/eval use, keep audio on the workstation, never redistribute. |

The phoneme inventory is the corpus's QPS (68 symbols). We never define or invent phonetic
symbols in code — `prepare_finetune_data.py` only ingests labels the corpus provides and
sanity-checks their count.

## Honesty + privacy guardrails

- **No invented labels.** EveryAyah rows ship with `phonemes: null`; the trainer must not
  fabricate supervision for them.
- **No audio leaves the workstation.** The manifest is paths + derived labels; the device never
  participates in training.
- **Held-out eval is sacred.** The QuranMB test split is never trained on; the hash split keeps
  it stable across runs.
- A fine-tuned model only ships after its before/after numbers clear the eval harness, and
  tajweed grading still stays gated on the qualified-Qari sign-off regardless of model quality.
