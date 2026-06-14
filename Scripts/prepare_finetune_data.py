#!/usr/bin/env python3
"""Build a fine-tuning manifest for the on-device Quran phoneme model.

The shipped acoustic model (`TBOGamer22/wav2vec2-quran-phonetics`) is general MSA phonetics.
Fine-tuning it on real Qur'anic recitation across reciters, speeds, and registers is the path
to top-tier acoustic follow-along + tajweed measurement. This script assembles the training
manifest from the public corpora into one normalized JSONL the trainer consumes.

It is offline-only: it never runs in CI, never touches the device, and emits derived labels +
audio *paths*, not audio. Recitation stays where it is.

Corpora (see Scripts/README_finetune.md for provenance + licensing):
  - IqraEval / QuranMB (ArabicNLP 2025): MSA Qur'anic recitation with a 68-phoneme QPS
    inventory and per-utterance phoneme labels. Primary supervised signal.
  - EveryAyah: 26 professional reciters, full Qur'an. Cross-voice robustness; phoneme labels
    come from the verified corpus phonemizer (not invented here), so EveryAyah rows are emitted
    with `phonemes: null` until that binding exists, and the trainer treats them as
    audio+text for self-training / alignment only.

Manifest row schema (JSONL):
  {"audio": "rel/or/abs/path.wav", "sample_rate": 16000, "verse_key": "1:1",
   "reciter": "...", "text": "<uthmani>", "phonemes": ["b","i","s",...] | null,
   "source": "iqraeval|everyayah", "split": "train|val"}

Usage:
  python Scripts/prepare_finetune_data.py --iqraeval /data/IqraEval --everyayah /data/everyayah \\
      --out build/finetune_manifest.jsonl --val-fraction 0.05
  python Scripts/prepare_finetune_data.py --validate build/finetune_manifest.jsonl
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from dataclasses import dataclass, asdict
from typing import Iterator, Optional

TARGET_SR = 16_000

# The QPS (Qur'an Phonetic Script) inventory size, for a sanity check on labels we ingest.
# We do NOT define the symbols here (that is corpus data); we only assert the count is sane.
QPS_INVENTORY_SIZE = 68


@dataclass
class Row:
    audio: str
    sample_rate: int
    verse_key: str
    reciter: str
    text: str
    phonemes: Optional[list[str]]
    source: str
    split: str


def _deterministic_split(key: str, val_fraction: float) -> str:
    """Stable per-utterance split so re-runs don't reshuffle train/val (which would leak)."""
    digest = hashlib.sha1(key.encode("utf-8")).hexdigest()
    bucket = int(digest[:8], 16) / 0xFFFFFFFF
    return "val" if bucket < val_fraction else "train"


def _iter_iqraeval(root: str, val_fraction: float) -> Iterator[Row]:
    """IqraEval ships a metadata file (jsonl/tsv) of utterances with phoneme labels.

    We read `metadata.jsonl` if present (fields: audio, verse_key, reciter, text, phonemes),
    falling back to a `metadata.tsv`. Paths are resolved relative to `root`.
    """
    meta_jsonl = os.path.join(root, "metadata.jsonl")
    meta_tsv = os.path.join(root, "metadata.tsv")
    if os.path.exists(meta_jsonl):
        with open(meta_jsonl, "r", encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                entry = json.loads(line)
                phonemes = entry.get("phonemes")
                if isinstance(phonemes, str):
                    phonemes = phonemes.split()
                key = entry.get("verse_key", "") + "|" + entry.get("audio", "")
                yield Row(
                    audio=os.path.join(root, entry["audio"]),
                    sample_rate=int(entry.get("sample_rate", TARGET_SR)),
                    verse_key=entry.get("verse_key", ""),
                    reciter=entry.get("reciter", "iqraeval"),
                    text=entry.get("text", ""),
                    phonemes=phonemes,
                    source="iqraeval",
                    split=_deterministic_split(key, val_fraction),
                )
    elif os.path.exists(meta_tsv):
        with open(meta_tsv, "r", encoding="utf-8") as handle:
            header = handle.readline().rstrip("\n").split("\t")
            idx = {name: i for i, name in enumerate(header)}
            for line in handle:
                cols = line.rstrip("\n").split("\t")
                if len(cols) < len(header):
                    continue
                audio = cols[idx["audio"]]
                key = cols[idx.get("verse_key", 0)] + "|" + audio
                phon = cols[idx["phonemes"]].split() if "phonemes" in idx else None
                yield Row(
                    audio=os.path.join(root, audio),
                    sample_rate=TARGET_SR,
                    verse_key=cols[idx.get("verse_key", 0)] if "verse_key" in idx else "",
                    reciter=cols[idx["reciter"]] if "reciter" in idx else "iqraeval",
                    text=cols[idx["text"]] if "text" in idx else "",
                    phonemes=phon,
                    source="iqraeval",
                    split=_deterministic_split(key, val_fraction),
                )
    else:
        print(f"  (no metadata.jsonl/tsv under {root}; skipping IqraEval)", file=sys.stderr)


def _iter_everyayah(root: str, val_fraction: float) -> Iterator[Row]:
    """EveryAyah is organized as <reciter>/<sssaaa>.mp3 (surah*1000+ayah). Audio + verse only;
    phoneme labels are intentionally null (they come from the verified corpus phonemizer, not
    guessed here)."""
    if not os.path.isdir(root):
        print(f"  (no EveryAyah dir at {root}; skipping)", file=sys.stderr)
        return
    for reciter in sorted(os.listdir(root)):
        rdir = os.path.join(root, reciter)
        if not os.path.isdir(rdir):
            continue
        for name in sorted(os.listdir(rdir)):
            stem, ext = os.path.splitext(name)
            if ext.lower() not in (".mp3", ".wav") or not stem.isdigit() or len(stem) != 6:
                continue
            surah, ayah = int(stem[:3]), int(stem[3:])
            verse_key = f"{surah}:{ayah}"
            yield Row(
                audio=os.path.join(rdir, name),
                sample_rate=TARGET_SR,
                verse_key=verse_key,
                reciter=reciter,
                text="",
                phonemes=None,
                source="everyayah",
                split=_deterministic_split(f"{reciter}|{stem}", val_fraction),
            )


def build(args: argparse.Namespace) -> int:
    rows: list[Row] = []
    if args.iqraeval:
        rows.extend(_iter_iqraeval(args.iqraeval, args.val_fraction))
    if args.everyayah:
        rows.extend(_iter_everyayah(args.everyayah, args.val_fraction))

    if not rows:
        print("No rows produced. Point --iqraeval / --everyayah at the extracted corpora.", file=sys.stderr)
        return 1

    os.makedirs(os.path.dirname(os.path.abspath(args.out)) or ".", exist_ok=True)
    labeled = sum(1 for r in rows if r.phonemes)
    train = sum(1 for r in rows if r.split == "train")
    with open(args.out, "w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(asdict(row), ensure_ascii=False) + "\n")

    print(f"Wrote {len(rows)} rows -> {args.out}")
    print(f"  phoneme-labeled: {labeled}  ({100 * labeled / len(rows):.1f}%)")
    print(f"  train/val: {train}/{len(rows) - train}")
    reciters = sorted({r.reciter for r in rows})
    print(f"  reciters: {len(reciters)} (cross-voice robustness)")
    return 0


def validate(path: str) -> int:
    seen_val, seen_train = set(), set()
    n = labeled = 0
    bad = 0
    with open(path, "r", encoding="utf-8") as handle:
        for i, line in enumerate(handle, 1):
            line = line.strip()
            if not line:
                continue
            n += 1
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:
                print(f"line {i}: bad JSON: {exc}", file=sys.stderr)
                bad += 1
                continue
            if row.get("phonemes"):
                labeled += 1
                if len(set(row["phonemes"])) > QPS_INVENTORY_SIZE:
                    print(f"line {i}: phoneme set larger than QPS inventory", file=sys.stderr)
                    bad += 1
            key = f'{row.get("reciter")}|{row.get("verse_key")}|{row.get("audio")}'
            (seen_val if row.get("split") == "val" else seen_train).add(key)
    leak = seen_val & seen_train
    if leak:
        print(f"train/val LEAK: {len(leak)} utterances in both splits", file=sys.stderr)
        bad += len(leak)
    print(f"validated {n} rows; phoneme-labeled {labeled}; problems {bad}")
    return 1 if bad else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Build / validate the Quran phoneme fine-tuning manifest.")
    parser.add_argument("--iqraeval", help="Path to the extracted IqraEval/QuranMB corpus root.")
    parser.add_argument("--everyayah", help="Path to the extracted EveryAyah corpus root.")
    parser.add_argument("--out", default="build/finetune_manifest.jsonl", help="Output manifest path.")
    parser.add_argument("--val-fraction", type=float, default=0.05, help="Held-out validation fraction.")
    parser.add_argument("--validate", metavar="MANIFEST", help="Validate an existing manifest and exit.")
    args = parser.parse_args()

    if args.validate:
        return validate(args.validate)
    return build(args)


if __name__ == "__main__":
    raise SystemExit(main())
