#!/usr/bin/env python3
"""Build bundled offline Qur'an translation editions for Siraat.

Fetches complete translation editions (all 6236 ayat, mushaf order) from the quran.com
v4 API and writes one JSON file per language into Siraat/Resources/Translations/. Those
files let the reader show non-English translations fully offline instead of silently
falling back to English under the wrong translator's credit.

Output schema (decoded by `BundledTranslation` in QuranDatabaseManager.swift):
    { "language": "ur", "resourceId": 234, "credit": "...", "texts": [<6236 strings>] }
`texts[globalAyahNumber - 1]` is the translation for that ayah.

Run:  python Scripts/build_translations.py
Re-run any time to refresh. Requires only the Python standard library + network.

LICENSING (confirm before shipping — see Siraat/Resources/Translations/LICENSING.md):
  - ur 234  Fatah Muhammad Jalandhari — author d. 1954, public domain (life+70).
  - id 33   Kementerian Agama RI (Indonesian Ministry) — government edition.
  - tr 77   Diyanet İşleri (Turkish Presidency of Religious Affairs) — government edition.
"""
from __future__ import annotations

import html
import json
import re
import sys
import urllib.request
from pathlib import Path

API = "https://api.quran.com/api/v4/quran/translations/{rid}"
EXPECTED_AYAH_COUNT = 6236

# language code -> (quran.com resource id, translator credit). Keep credit in sync with
# TranslationLanguage.quranTranslationCredit in AppModels.swift.
EDITIONS = {
    "ur": (234, "Fatah Muhammad Jalandhari"),
    "id": (33, "Kementerian Agama Republik Indonesia"),
    "tr": (77, "Diyanet İşleri"),
}

_TAG = re.compile(r"<[^>]+>")


def clean(text: str) -> str:
    """Strip quran.com footnote/HTML markup and unescape entities."""
    return html.unescape(_TAG.sub("", text)).strip()


def fetch(resource_id: int) -> list[str]:
    url = API.format(rid=resource_id)
    # quran.com rejects the default Python user-agent with 403; send a normal one.
    request = urllib.request.Request(url, headers={"User-Agent": "Siraat-build/1.0"})
    with urllib.request.urlopen(request, timeout=60) as resp:
        payload = json.load(resp)
    texts = [clean(item["text"]) for item in payload["translations"]]
    if len(texts) != EXPECTED_AYAH_COUNT:
        raise SystemExit(
            f"resource {resource_id}: expected {EXPECTED_AYAH_COUNT} ayat, got {len(texts)}"
        )
    return texts


def main() -> int:
    out_dir = Path(__file__).resolve().parent.parent / "Siraat" / "Resources" / "Translations"
    out_dir.mkdir(parents=True, exist_ok=True)

    for lang, (resource_id, credit) in EDITIONS.items():
        print(f"fetching {lang} (resource {resource_id})...", flush=True)
        texts = fetch(resource_id)
        doc = {"language": lang, "resourceId": resource_id, "credit": credit, "texts": texts}
        out = out_dir / f"Translation-{lang}.json"
        # Compact, deterministic output. ensure_ascii=False keeps the Arabic/Urdu/etc.
        # readable and roughly halves file size vs. \uXXXX escaping.
        out.write_text(
            json.dumps(doc, ensure_ascii=False, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )
        print(f"  wrote {out.relative_to(out_dir.parent.parent.parent)} ({out.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
