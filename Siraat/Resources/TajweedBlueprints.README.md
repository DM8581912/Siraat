# TajweedBlueprints.json — schema and provenance

This file is the per-ayah **phonetic "answer key"** the recitation engine evaluates a
reciter against. It is *data*, never generated at runtime, and it is the only source of
Tajweed expectations the engine trusts.

> **PLACEHOLDER WARNING.** The shipped file covers **Al-Fatiha (1:1–1:7) only**, and every
> entry is marked `source.verified: false`. The base letters were derived mechanically
> from the verified Uthmani text in `FullQuran.json`, but the **Madd flags and durations
> are placeholder reference values, not a verified Tajweed corpus.** Unverified ayahs are
> shown with coloring only in DEBUG builds, clearly labeled "experimental"; production
> requires `source.verified == true`. Replace these values with an attributed, scholarly
> corpus (e.g. KFGQPC Hafs tajweed rules) before enabling colored feedback for users, and
> never guess or hand-invent Quranic phonetic data.

## Schema

```jsonc
{
  "schemaVersion": 1,
  "ayahs": [
    {
      "verseKey": "1:1",
      "scriptUthmani": "…",          // exact text this map was authored against
      "source": {
        "corpus": "…",
        "attribution": "…",
        "verified": false             // gates production display
      },
      "phonemes": [                   // reading order, one per base letter
        {
          "symbol": "b",              // aligner vocab token
          "baseLetter": "ب",          // the base Arabic letter
          "isMaddVowel": false,
          "expectedMaddCount": 0,     // 0, 2, 4, or 6 harakāt
          "expectedDurationSeconds": 0.18
        }
      ]
    }
  ]
}
```

## Notes

- Phonemes are aligned to the rendered text by **reading order**, not by character
  offset. `UthmaniCharacterMapper` segments the runtime Uthmani string into base-letter
  clusters (a base letter plus its combining marks) and zips them with `phonemes` in
  order, so the file is robust to a leading BOM or minor text-source variation.
- `expectedDurationSeconds` is a reference duration at a moderate tempo. The evaluator
  applies a tolerance ratio (a Madd held shorter than half the expected duration is
  flagged), it does not compare exactly.
- Reference Madd guide for a qualified reviewer to fill: natural Madd ≈ 2 harakāt; Madd
  Muttasil/Munfasil and others ≈ 4–6 harakāt. Convert to seconds at your chosen reference
  tempo and cite the corpus in `source`.
