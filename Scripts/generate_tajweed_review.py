#!/usr/bin/env python3
"""Generate a Tajweed rule DRAFT + reviewer sheet for Al-Fatiha (the rule-engine half of the
"rule-engine + qualified-Qari audit" corpus decision).

This reads the VERIFIED Uthmani text from Siraat/Resources/FullQuran.json (never hand-typed,
never altered) and applies only the standard, deterministic Hafs rule classifications — the
fixed letter-set algorithms taught in every tajweed primer (noon sakinah & tanwin, meem
sakinah, qalqalah, ghunnah, madd). Every result is a CANDIDATE marked for confirmation.

It is honest and gated by construction:
  * `verified: false` and `status: "awaiting_review"` on every output.
  * Nothing here is wired into the app; the app still only loads TajweedBlueprints.json, whose
    production display already requires `source.verified == true`.
  * The engine covers standard mechanical rules and may miss or mis-apply edge cases. The named
    reviewer's rulings are AUTHORITATIVE and supersede these candidates. The review sheet shows
    the full verified text per ayah so the reviewer can correct and add anything.

Flipping `verified: true` happens ONLY after a signed review comes back — never from this script.

Usage:
  python Scripts/generate_tajweed_review.py --reviewer "Mishary Rashid Alafasy" \\
      --surah 1 --out-dir Siraat/Resources/Tajweed
"""
from __future__ import annotations

import argparse
import json
import os
import unicodedata

# --- Diacritics (Unicode) ---
SUKUN = "ْ"
SHADDA = "ّ"
DAGGER_ALIF = "ٰ"
MADDAH = "ٓ"
TANWIN = {"ً", "ٌ", "ٍ"}  # fathatan, dammatan, kasratan
HARAKAT = {"َ", "ُ", "ِ"}  # fatha, damma, kasra
MARKS = {SUKUN, SHADDA, DAGGER_ALIF, MADDAH, *TANWIN, *HARAKAT,
         "ٔ", "ٕ", "ۚ", "ۖ", "ۗ", "ۘ", "ۙ", "ۢ"}

# --- Standard Hafs letter sets (fixed; from any tajweed primer) ---
QALQALAH = set("قطبجد")
THROAT_IZHAR = set("ءهعحغخ")           # noon-sakinah izhar (halqi)
IDGHAM_GHUNNAH = set("ينمو")            # noon-sakinah idgham with ghunnah (yanmu)
IDGHAM_NO_GHUNNAH = set("لر")           # noon-sakinah idgham without ghunnah
IQLAB = set("ب")                        # noon-sakinah iqlab
MADD_LETTERS = set("اوىي")

# alef variants normalize to ا for "next letter" classification
NORMALIZE = {"ٱ": "ا", "أ": "ا", "إ": "ا", "آ": "ا"}


def base_of(ch: str) -> str:
    return NORMALIZE.get(ch, ch)


def is_arabic_letter(ch: str) -> bool:
    return "ء" <= ch <= "ي" or ch in ("ٱ", "ٰ")


def segment(text: str):
    """Split into (base_letter, marks_string) clusters in reading order, dropping spaces/BOM."""
    clusters = []
    for ch in text:
        if ch in ("﻿", " ", "‏", "‎"):
            clusters.append(None)  # word boundary marker
            continue
        if ch in MARKS:
            if clusters and clusters[-1] is not None:
                base, marks = clusters[-1]
                clusters[-1] = (base, marks + ch)
            continue
        if is_arabic_letter(ch):
            clusters.append((ch, ""))
    return clusters


def classify(text: str):
    """Return a list of candidate rule dicts for one ayah's verified Uthmani text."""
    raw = [c for c in segment(text)]
    # Flatten to letters with word index.
    letters = []
    word = 0
    for c in raw:
        if c is None:
            word += 1
            continue
        letters.append((c[0], c[1], word))

    candidates = []

    def add(i, rule, subtype, basis):
        base, marks, w = letters[i]
        candidates.append({
            "letter_index": i,
            "word_index": w,
            "base_letter": base,
            "rule": rule,
            "subtype": subtype,
            "basis": basis,
            "status": "candidate_confirm",
        })

    for i, (base, marks, _w) in enumerate(letters):
        nxt = base_of(letters[i + 1][0]) if i + 1 < len(letters) else None

        # Ghunnah: noon/meem with shadda (held ~2 harakat).
        if base in "نم" and SHADDA in marks:
            add(i, "ghunnah", "mushaddad", "noon/meem with shaddah is held with ghunnah ~2 harakat")

        # Qalqalah: qalqalah letter with explicit sukun (echo). Word/ayah-final qalqalah at
        # pause is left for the reviewer (depends on stop).
        if base in QALQALAH and SUKUN in marks:
            add(i, "qalqalah", "sughra", "qalqalah letter (ق ط ب ج د) with sukun")

        # Noon sakinah & tanwin rules, classified by the next letter.
        is_noon_sakinah = base == "ن" and SUKUN in marks
        is_tanwin = bool(TANWIN & set(marks))
        if (is_noon_sakinah or is_tanwin) and nxt is not None:
            src = "noon sakinah" if is_noon_sakinah else "tanwin"
            if nxt in IQLAB:
                add(i, "iqlab", src, f"{src} followed by ب")
            elif nxt in IDGHAM_GHUNNAH:
                add(i, "idgham", f"{src}/with-ghunnah", f"{src} followed by {nxt} (ينمو)")
            elif nxt in IDGHAM_NO_GHUNNAH:
                add(i, "idgham", f"{src}/no-ghunnah", f"{src} followed by {nxt} (ل ر)")
            elif nxt in THROAT_IZHAR:
                add(i, "izhar", src, f"{src} followed by a throat letter {nxt}")
            else:
                add(i, "ikhfa", src, f"{src} followed by {nxt} (one of the 15 ikhfa letters)")

        # Meem sakinah (shafawi) rules.
        if base == "م" and SUKUN in marks and nxt is not None:
            if nxt == "ب":
                add(i, "ikhfa_shafawi", "meem sakinah", "meem sakinah followed by ب")
            elif nxt == "م":
                add(i, "idgham_shafawi", "meem sakinah", "meem sakinah followed by م")
            else:
                add(i, "izhar_shafawi", "meem sakinah", "meem sakinah followed by a non-labial")

        # Madd: madd letters / dagger alif / maddah (confirm exact type + length with reviewer).
        if base in MADD_LETTERS or DAGGER_ALIF in marks or MADDAH in marks:
            add(i, "madd", "confirm_type_and_length",
                "madd carrier (ا و ي / dagger alif / maddah); type + harakat to be confirmed")

    return candidates


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a Tajweed rule DRAFT + reviewer sheet.")
    parser.add_argument("--reviewer", default="(unassigned)", help="Name + credential of the qualified Qari reviewer.")
    parser.add_argument("--surah", type=int, default=1)
    parser.add_argument("--quran", default="Siraat/Resources/FullQuran.json")
    parser.add_argument("--out-dir", default="Siraat/Resources/Tajweed")
    args = parser.parse_args()

    data = json.load(open(args.quran, encoding="utf-8"))
    surah = next(s for s in data["surahs"] if s["number"] == args.surah)
    name = surah["englishName"]

    ayahs_out = []
    for ayah in surah["ayahs"]:
        text = ayah["textUthmani"].lstrip("﻿")
        ayahs_out.append({
            "verse_key": f'{args.surah}:{ayah["numberInSurah"]}',
            "script_uthmani": text,
            "candidates": classify(text),
        })

    os.makedirs(args.out_dir, exist_ok=True)
    draft = {
        "schemaVersion": 1,
        "surah": args.surah,
        "name": name,
        "source": {
            "text_corpus": "KFGQPC Hafs Uthmani via Siraat/Resources/FullQuran.json (verified text)",
            "rule_engine": "Scripts/generate_tajweed_review.py — standard Hafs rule candidates, mechanically derived",
            "reviewer": args.reviewer,
            "verified": False,
            "status": "awaiting_review",
        },
        "WARNING": "ENGINE DRAFT — candidate rules only, NOT verified. The reviewer's rulings are authoritative and supersede these. Do not display as authoritative grading until verified == true (after signed review).",
        "ayahs": ayahs_out,
    }
    draft_path = os.path.join(args.out_dir, f"{name.replace(' ', '')}_TajweedDraft.json")
    json.dump(draft, open(draft_path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

    # Human review sheet.
    lines = [
        f"# Tajweed review sheet — Surah {args.surah} ({name})",
        "",
        f"**Reviewer:** {args.reviewer}  ",
        "**Status:** awaiting review — this is an ENGINE DRAFT, not verified.",
        "",
        "The text below is the verified Uthmani from the app's bundled mushaf. For each ayah the "
        "engine lists the standard Hafs rule **candidates** it detected mechanically. Please "
        "**confirm, correct, or strike** each, and **add** any rule the engine missed (madd "
        "lengths in particular need your ruling). Your rulings are authoritative.",
        "",
        "Sign-off below flips the production gate; until then nothing displays to users as graded.",
        "",
    ]
    rule_count = 0
    for a in ayahs_out:
        lines.append(f"## {a['verse_key']}")
        lines.append("")
        lines.append(f"> {a['script_uthmani']}")
        lines.append("")
        if not a["candidates"]:
            lines.append("- _(no standard candidates detected — please add any applicable rules)_")
        for c in a["candidates"]:
            rule_count += 1
            label = f"{c['rule']}" + (f" ({c['subtype']})" if c['subtype'] else "")
            lines.append(f"- [ ] **{label}** on `{c['base_letter']}` (word {c['word_index'] + 1}) — {c['basis']}")
        lines.append("")
    lines += [
        "---",
        "",
        "### Reviewer sign-off",
        "",
        "- [ ] I have reviewed every candidate above and the full text of each ayah.",
        "- Corrections/additions noted inline.",
        "",
        f"Name + credential (ijazah): __________________________  Date: ____________",
        "",
        f"_Generated candidates: {rule_count}. Engine coverage is partial; the reviewer is authoritative._",
    ]
    sheet_path = os.path.join(args.out_dir, f"{name.replace(' ', '')}_ReviewSheet.md")
    open(sheet_path, "w", encoding="utf-8").write("\n".join(lines))

    print(f"Wrote {draft_path}")
    print(f"Wrote {sheet_path}")
    print(f"  ayahs: {len(ayahs_out)}  candidate rules: {rule_count}  verified: False")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
