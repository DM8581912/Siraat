#!/usr/bin/env python3
"""Offline conversion of a Wav2Vec2 Arabic phonetic CTC model to Core ML.

This script runs ONLY on a developer's macOS machine. It is never executed by the
app or by CI, and the model it produces is NOT committed to the repo (it is large and
license-bound). The Siraat app loads the resulting `Wav2Vec2QuranPhonetics.mlmodelc`
from its bundle at runtime; until that file is present, the app uses a deterministic
placeholder aligner (see `CoreMLForcedAligner`). All recitation audio stays on-device.

Pipeline
--------
1. Download a phonetic CTC model, e.g. `TBOGamer22/wav2vec2-quran-phonetics`.
2. Trace it to TorchScript with a fixed-length raw-waveform input (16 kHz mono).
3. Convert to a Core ML mlprogram with coremltools.
4. Compile to `.mlmodelc` and drop it in `Siraat/Resources/`.
5. Export the phoneme vocabulary so `CanonicalPhoneme.symbol` values in
   `TajweedBlueprints.json` map to the model's output token ids.

Usage
-----
    pip install torch transformers coremltools
    python Scripts/convert_wav2vec2_phonetics.py \
        --model TBOGamer22/wav2vec2-quran-phonetics \
        --out build/Wav2Vec2QuranPhonetics.mlpackage \
        --vocab build/phoneme_vocab.json

Then compile with:
    xcrun coremlcompiler compile build/Wav2Vec2QuranPhonetics.mlpackage Siraat/Resources/

The model is expected to output an emissions matrix [frames, vocab] of CTC logits.
The app feeds those frames to `CTCForcedAligner` (pure Swift) to force-align against
each ayah's canonical phoneme sequence and derive per-phoneme timestamps.
"""

import argparse
import json
import sys

SAMPLE_RATE = 16_000
# A fixed trace length keeps the Core ML input shape static. ~10s covers most ayahs;
# longer recitations are chunked by the app before inference.
TRACE_SECONDS = 10


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True, help="HF model id or local path")
    parser.add_argument("--out", required=True, help="output .mlpackage path")
    parser.add_argument("--vocab", required=True, help="output phoneme vocab json path")
    args = parser.parse_args()

    try:
        import torch
        import coremltools as ct
        from transformers import AutoProcessor, AutoModelForCTC
    except ImportError as exc:  # pragma: no cover - dev-only tooling
        print(
            "Missing ML dependencies. Install with:\n"
            "    pip install torch transformers coremltools\n"
            f"Import error: {exc}",
            file=sys.stderr,
        )
        return 1

    print(f"Loading {args.model} ...")
    processor = AutoProcessor.from_pretrained(args.model)
    model = AutoModelForCTC.from_pretrained(args.model).eval()

    # Persist the vocab so the Swift blueprint symbols line up with output token ids.
    vocab = processor.tokenizer.get_vocab()
    with open(args.vocab, "w", encoding="utf-8") as handle:
        json.dump(vocab, handle, ensure_ascii=False, indent=2)
    print(f"Wrote phoneme vocab ({len(vocab)} tokens) -> {args.vocab}")

    example = torch.zeros(1, SAMPLE_RATE * TRACE_SECONDS, dtype=torch.float32)

    class Emissions(torch.nn.Module):
        def __init__(self, ctc):
            super().__init__()
            self.ctc = ctc

        def forward(self, waveform):
            return self.ctc(waveform).logits

    traced = torch.jit.trace(Emissions(model), example)

    print("Converting to Core ML ...")
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="waveform", shape=example.shape)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS16,
    )
    mlmodel.short_description = (
        "Wav2Vec2 Arabic phonetic CTC. Outputs per-frame logits for forced alignment."
    )
    mlmodel.save(args.out)
    print(f"Saved {args.out}")
    print(
        "Next: xcrun coremlcompiler compile "
        f"{args.out} Siraat/Resources/   # produces Wav2Vec2QuranPhonetics.mlmodelc"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
