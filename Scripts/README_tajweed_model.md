# Tajweed acoustic model (on-device)

The recitation engine forced-aligns microphone audio to each ayah's canonical phoneme
sequence **entirely on-device**. Two things ship separately from the app code:

1. **The acoustic model** — `Wav2Vec2QuranPhonetics.mlmodelc`, produced offline by
   `convert_wav2vec2_phonetics.py`. Large and license-bound, so it is **not committed**.
2. **The phonetic blueprints** — `Siraat/Resources/TajweedBlueprints.json`, the verified
   per-ayah "answer key" (see `TajweedBlueprints.README.md`).

Until the model file is present in the bundle, `CoreMLForcedAligner` falls back to a
deterministic placeholder alignment derived from the blueprint, so the app builds, runs,
and is tested in CI with no model. Nothing about a recitation is ever sent off-device.

## Producing the model

```sh
pip install torch transformers coremltools
python Scripts/convert_wav2vec2_phonetics.py \
    --model TBOGamer22/wav2vec2-quran-phonetics \
    --out build/Wav2Vec2QuranPhonetics.mlpackage \
    --vocab build/phoneme_vocab.json
xcrun coremlcompiler compile build/Wav2Vec2QuranPhonetics.mlpackage Siraat/Resources/
```

Then add `Siraat/Resources/Wav2Vec2QuranPhonetics.mlmodelc` to the Xcode project's
Resources build phase (the project is hand-authored — see `Siraat.xcodeproj/project.pbxproj`).

## How it fits together

- The model outputs a per-frame emissions matrix `[frames, vocab]` of CTC logits.
- `CTCForcedAligner` (pure Swift, unit-tested) force-aligns those frames against the
  blueprint's phoneme token ids, yielding a frame span per phoneme.
- Frame spans convert to seconds via the model's hop size, producing `AlignedPhoneme`s.
- `CharacterTajweedEvaluator` compares durations against the blueprint's expected Madd
  timing and emits per-character `{ char, color, error_type, duration }`.
- `TajweedAyahText` renders the ayah with per-letter coloring via CoreText.

## Required before enabling for all ayahs

- A verified, attributed phonetic/Madd blueprint corpus for all 6236 ayahs
  (`source.verified == true`). The shipped placeholder covers Al-Fatiha only.
- Validation of the model's frame→time hop size against known Al-Fatiha timings.
