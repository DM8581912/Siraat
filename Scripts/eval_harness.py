#!/usr/bin/env python3
"""Offline recitation / tajweed evaluation harness.

This is the large-corpus counterpart to the in-CI Swift harness
(`SiraatTests/RecitationEvalHarness.swift`). The Swift tier is the merge gate: it runs in
milliseconds on synthetic fixtures with no model and guards the honesty invariants. This
tier scores the on-device engine against real recitation audio from the public corpora and
reports the same metrics at scale, so a human can paste a real before/after delta into a PR.

It is deliberately decoupled from how predictions are produced: you run the device/engine
over a corpus, dump a predictions manifest (schema below), and this script scores it. That
keeps the large audio off CI and off the repo, and keeps audio on-device — the manifest
holds only derived labels, never recitation audio.

Datasets (per the data decision): IqraEval / QuranMB (labeled mispronunciations, CC) and
EveryAyah (26 reciters, cross-voice robustness). See eval/README.md for provenance.

Manifest schema (JSON):
{
  "dataset": "iqraeval-quranmb-v2",
  "clips": [
    {
      "id": "clip-0001",
      "verse_key": "1:1",
      "words": [                          # one entry per expected word
        {"ideal_correct": true,           # truth: was this word recited correctly?
         "truth_mistake": null,           # null | "skip" | "substitution"
         "pred_status": "correct"},       # engine output: pending|correct|uncertain|missed
        ...
      ],
      "letters": [                         # one entry per graded cluster (optional)
        {"truth_error": null,             # null | madd_short | ghunnah_missed | tashkeel_wrong | ...
         "pred_error": null},
        ...
      ]
    }
  ]
}

Usage:
    python Scripts/eval_harness.py path/to/manifest.json
    python Scripts/eval_harness.py --demo          # runs a tiny embedded example
    python Scripts/eval_harness.py manifest.json --baseline eval/baseline.json
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field


@dataclass
class Detector:
    """Precision/recall accumulator. No false alarms => precision 1.0 (the honest default)."""
    tp: int = 0
    fp: int = 0
    fn: int = 0

    def record(self, predicted: bool, actual: bool) -> None:
        if predicted and actual:
            self.tp += 1
        elif predicted and not actual:
            self.fp += 1
        elif actual and not predicted:
            self.fn += 1

    @property
    def precision(self) -> float:
        d = self.tp + self.fp
        return 1.0 if d == 0 else self.tp / d

    @property
    def recall(self) -> float:
        d = self.tp + self.fn
        return 1.0 if d == 0 else self.tp / d


def score(manifest: dict) -> dict:
    complete_num = complete_den = 0
    hard_fp_num = hard_fp_den = 0
    mistake = Detector()
    letter_fp_num = letter_fp_den = 0
    per_rule: dict[str, Detector] = {}

    for clip in manifest.get("clips", []):
        for word in clip.get("words", []):
            status = word.get("pred_status", "pending")
            ideal = bool(word.get("ideal_correct", False))
            truth_mistake = word.get("truth_mistake")
            pred_hard = status == "missed"
            if ideal:
                complete_den += 1
                if status == "correct":
                    complete_num += 1
                hard_fp_den += 1
                if pred_hard:
                    hard_fp_num += 1
            mistake.record(predicted=pred_hard, actual=truth_mistake is not None)

        for letter in clip.get("letters", []):
            truth = letter.get("truth_error")
            pred = letter.get("pred_error")
            letter_fp_den += 1
            if pred is not None and truth is None:
                letter_fp_num += 1
            rules = {r for r in (truth, pred) if r is not None}
            for rule in rules:
                per_rule.setdefault(rule, Detector()).record(predicted=pred == rule, actual=truth == rule)

    return {
        "dataset": manifest.get("dataset", "unknown"),
        "follow_along": {
            "follow_completeness": (complete_num / complete_den) if complete_den else 1.0,
            "hard_false_positive_rate": (hard_fp_num / hard_fp_den) if hard_fp_den else 0.0,
            "mistake_precision": mistake.precision,
            "mistake_recall": mistake.recall,
        },
        "tajweed": {
            "false_positive_rate": (letter_fp_num / letter_fp_den) if letter_fp_den else 0.0,
            "per_rule": {
                rule: {"precision": d.precision, "recall": d.recall, "tp": d.tp, "fp": d.fp, "fn": d.fn}
                for rule, d in sorted(per_rule.items())
            },
        },
    }


def render(result: dict) -> str:
    fa = result["follow_along"]
    tj = result["tajweed"]
    lines = [
        "================ RECITATION EVAL SCOREBOARD (offline) ================",
        f"dataset: {result['dataset']}",
        "FOLLOW-ALONG (word level)",
        f"  follow-completeness:                {fa['follow_completeness'] * 100:.0f}%",
        f"  HARD false-positive rate:           {fa['hard_false_positive_rate'] * 100:.0f}%  [honesty: must be 0%]",
        f"  mistake precision / recall:         {fa['mistake_precision']:.2f} / {fa['mistake_recall']:.2f}",
        "TAJWEED (character level)",
        f"  false-positive rate on green truth: {tj['false_positive_rate'] * 100:.0f}%  [honesty: must be 0%]",
    ]
    for rule, d in tj["per_rule"].items():
        lines.append(f"    - {rule}: precision {d['precision']:.2f} recall {d['recall']:.2f}")
    lines.append("=====================================================================")
    return "\n".join(lines)


DEMO_MANIFEST = {
    "dataset": "demo",
    "clips": [
        {
            "id": "demo-perfect",
            "verse_key": "1:1",
            "words": [{"ideal_correct": True, "truth_mistake": None, "pred_status": "correct"} for _ in range(4)],
            "letters": [{"truth_error": None, "pred_error": None} for _ in range(3)],
        },
        {
            "id": "demo-skip",
            "verse_key": "1:1",
            "words": [
                {"ideal_correct": True, "truth_mistake": None, "pred_status": "correct"},
                {"ideal_correct": False, "truth_mistake": "skip", "pred_status": "pending"},
            ],
            "letters": [{"truth_error": "madd_short", "pred_error": "madd_short"}],
        },
    ],
}


def main() -> int:
    parser = argparse.ArgumentParser(description="Offline recitation/tajweed eval harness.")
    parser.add_argument("manifest", nargs="?", help="Path to a predictions manifest JSON.")
    parser.add_argument("--demo", action="store_true", help="Run the embedded demo manifest.")
    parser.add_argument("--baseline", help="Optional baseline JSON to diff honesty metrics against.")
    args = parser.parse_args()

    if args.demo or not args.manifest:
        manifest = DEMO_MANIFEST
    else:
        with open(args.manifest, "r", encoding="utf-8") as handle:
            manifest = json.load(handle)

    result = score(manifest)
    print(render(result))

    # Honesty gate: never let a correct reciter be hard-flagged.
    hard_fp = result["follow_along"]["hard_false_positive_rate"]
    taj_fp = result["tajweed"]["false_positive_rate"]
    if hard_fp > 0 or taj_fp > 0:
        print(f"\nHONESTY REGRESSION: hard_fp={hard_fp:.3f} tajweed_fp={taj_fp:.3f} (both must be 0)", file=sys.stderr)
        return 1

    if args.baseline:
        with open(args.baseline, "r", encoding="utf-8") as handle:
            baseline = json.load(handle)
        print("\nBaseline follow-completeness:",
              baseline.get("follow_along", {}).get("follow_completeness"),
              "-> current:", round(result["follow_along"]["follow_completeness"], 3))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
