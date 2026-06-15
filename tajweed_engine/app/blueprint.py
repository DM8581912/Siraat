"""Strict per-ayah phonetic/Tajweed blueprint schema.

This mirrors the on-device Swift schema (`Siraat/Core/Models/PhoneticBlueprint.swift`)
so the Python reference engine consumes exactly the same verified data files the
app ships. A blueprint is the *answer key*: the canonical phoneme sequence for an
ayah with its Tajweed annotations (madd type/count, ghunnah, qalqalah) and a
provenance record. The engine relies on this; it never guesses a Tajweed ruling.

Religious-content note: blueprints carry verified, attributed data only. The
loader refuses to treat an unverified file as authoritative (`require_verified`).
Nothing here generates or alters Quranic text.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

from .tajweed_rules import MaddSpec, MaddType, madd_spec

SCHEMA_VERSION = 1


class BlueprintError(ValueError):
    """Raised when a blueprint file is malformed or fails validation."""


@dataclass(frozen=True)
class BlueprintProvenance:
    """Where a blueprint's data came from and whether it has been verified."""

    corpus: str
    attribution: str
    verified: bool

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "BlueprintProvenance":
        try:
            return cls(str(d["corpus"]), str(d["attribution"]), bool(d["verified"]))
        except KeyError as e:
            raise BlueprintError(f"provenance missing field {e}") from e


@dataclass(frozen=True)
class CanonicalPhoneme:
    """One target phoneme with its Tajweed expectations.

    ``madd_type`` is the authoritative annotation. When a file predates it but
    still carries ``expected_madd_count``, the count is treated as an exact
    obligation. A bare long vowel with neither defaults to a 2-count natural madd
    (Tabi'i) -- never a guessed higher category.
    """

    symbol: str
    base_letter: str
    is_madd_vowel: bool
    expected_madd_count: int
    expected_duration_seconds: float
    requires_ghunnah: bool = False
    requires_qalqalah: bool = False
    madd_type: Optional[MaddType] = None

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "CanonicalPhoneme":
        # Tolerant decoding mirrors the Swift loader: ghunnah/qalqalah/madd_type
        # were added after the first blueprints were authored.
        try:
            raw_type = d.get("maddType")
            madd_type = MaddType(raw_type) if raw_type else None
        except ValueError as e:
            raise BlueprintError(f"unknown maddType {d.get('maddType')!r}") from e
        try:
            return cls(
                symbol=str(d["symbol"]),
                base_letter=str(d["baseLetter"]),
                is_madd_vowel=bool(d["isMaddVowel"]),
                expected_madd_count=int(d["expectedMaddCount"]),
                expected_duration_seconds=float(d["expectedDurationSeconds"]),
                requires_ghunnah=bool(d.get("requiresGhunnah", False)),
                requires_qalqalah=bool(d.get("requiresQalqalah", False)),
                madd_type=madd_type,
            )
        except KeyError as e:
            raise BlueprintError(f"phoneme missing field {e}") from e

    def madd_specification(self) -> tuple[MaddSpec, str]:
        """Resolve this phoneme to the (spec, label) the Madd engine should apply.

        Precedence: explicit ``madd_type`` -> exact ``expected_madd_count`` ->
        default natural 2-count. The engine never invents a madd category.
        """
        if self.madd_type is not None:
            return madd_spec(self.madd_type), self.madd_type.value
        if self.expected_madd_count and self.expected_madd_count != 2:
            count = self.expected_madd_count
            return MaddSpec((count,), True, f"exact {count}-count madd"), f"madd_{count}"
        return madd_spec(MaddType.TABEE), MaddType.TABEE.value


@dataclass(frozen=True)
class AyahPhonemeMap:
    """The canonical phoneme sequence and annotations for a single ayah."""

    verse_key: str
    script_uthmani: str
    source: BlueprintProvenance
    phonemes: list[CanonicalPhoneme]

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "AyahPhonemeMap":
        try:
            phonemes = [CanonicalPhoneme.from_dict(p) for p in d["phonemes"]]
            return cls(str(d["verseKey"]), str(d["scriptUthmani"]),
                       BlueprintProvenance.from_dict(d["source"]), phonemes)
        except KeyError as e:
            raise BlueprintError(f"ayah missing field {e}") from e

    @property
    def madd_vowels(self) -> list[CanonicalPhoneme]:
        return [p for p in self.phonemes if p.is_madd_vowel]


@dataclass(frozen=True)
class PhoneticBlueprintFile:
    """A loaded, validated blueprint file: schema version + ayah maps."""

    schema_version: int
    ayahs: list[AyahPhonemeMap]
    _by_key: dict[str, AyahPhonemeMap] = field(default_factory=dict, repr=False)

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "PhoneticBlueprintFile":
        try:
            version = int(d["schemaVersion"])
            ayahs = [AyahPhonemeMap.from_dict(a) for a in d["ayahs"]]
        except KeyError as e:
            raise BlueprintError(f"blueprint missing field {e}") from e
        if version > SCHEMA_VERSION:
            raise BlueprintError(
                f"schemaVersion {version} newer than supported {SCHEMA_VERSION}")
        return cls(version, ayahs, {a.verse_key: a for a in ayahs})

    def ayah(self, verse_key: str) -> AyahPhonemeMap:
        try:
            return self._by_key[verse_key]
        except KeyError as e:
            raise BlueprintError(f"no blueprint for verse {verse_key}") from e

    def verse_keys(self) -> list[str]:
        return list(self._by_key.keys())


def load_blueprint_file(path: str | Path,
                        require_verified: bool = True) -> PhoneticBlueprintFile:
    """Load and validate a blueprint JSON file.

    With ``require_verified`` (the default), every ayah's provenance must be
    ``verified == true`` -- the engine will not treat placeholder/unverified data
    as authoritative for a religious ruling.
    """
    p = Path(path)
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except FileNotFoundError as e:
        raise BlueprintError(f"blueprint not found: {p}") from e
    except json.JSONDecodeError as e:
        raise BlueprintError(f"blueprint is not valid JSON: {e}") from e

    blueprint = PhoneticBlueprintFile.from_dict(data)
    if require_verified:
        unverified = [a.verse_key for a in blueprint.ayahs if not a.source.verified]
        if unverified:
            raise BlueprintError(
                "unverified blueprint provenance for verses: "
                + ", ".join(unverified))
    return blueprint
