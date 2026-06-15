"""Unit tests for the Tajweed engine.

These run with NumPy + pytest only -- no ML runtime, no FastAPI -- exercising
the deterministic DSP, the CTC forced aligner against the mock acoustic model,
the GOP scorer and the three acoustic Tajweed rules end to end.

Test audio is synthetic (tones, bursts, silence). No Quranic recitation or text
is embedded; the few Arabic strings used are ordinary vocabulary words chosen
only to exercise the grapheme->phoneme mapping.
"""

from __future__ import annotations

import math

import numpy as np
import pytest

from app import audio_processing as ap
from app import tajweed_rules as tj
from app.alignment_engine import (
    ForcedAligner,
    MockAcousticModel,
    forced_align,
    text_to_phonemes,
)
from app.audio_processing import AudioConfig
from app.gop_scorer import GOPScorer
from app.server import AyahTarget, TajweedPipeline, TajweedSession, WordTarget
import json

from app.blueprint import BlueprintError, CanonicalPhoneme, load_blueprint_file
from app.madd_engine import TajweedMaddEngine
from app.tajweed_rules import (
    MaddType,
    RuleStatus,
    TajweedConfig,
    calibrate_harakah,
)

CFG = AudioConfig()
SR = CFG.sample_rate


def tone(freq: float, seconds: float, amp: float = 0.3,
         sr: int = SR) -> np.ndarray:
    t = np.arange(int(seconds * sr)) / sr
    return (amp * np.sin(2 * math.pi * freq * t)).astype(np.float32)


def silence(seconds: float, sr: int = SR) -> np.ndarray:
    return np.zeros(int(seconds * sr), dtype=np.float32)


# ---------------------------------------------------------------------------
# audio_processing
# ---------------------------------------------------------------------------
def test_pcm16_roundtrip():
    sig = tone(220, 0.05)
    restored = ap.pcm16_to_float(ap.float_to_pcm16(sig))
    assert restored.shape == sig.shape
    assert np.max(np.abs(restored - sig)) < 1e-3


def test_pcm16_handles_odd_byte():
    # A dangling byte (split sample at a chunk boundary) must not crash.
    assert ap.pcm16_to_float(b"\x00\x01\x02").shape[0] == 1


def test_resample_changes_length():
    sig = tone(440, 0.1, sr=8000)
    out = ap.resample(sig, 8000, 16000)
    assert abs(out.size - sig.size * 2) <= 2


def test_normalize_rms_hits_target():
    sig = tone(300, 0.2, amp=0.01)
    out = ap.normalize_rms(sig, target_dbfs=-20.0)
    rms_db = 20 * math.log10(float(np.sqrt(np.mean(out ** 2))) + 1e-12)
    assert abs(rms_db - (-20.0)) < 1.0


def test_mel_and_mfcc_shapes():
    sig = tone(300, 0.5)
    mel = ap.mel_spectrogram(sig, CFG)
    mfcc = ap.mfcc(sig, CFG)
    assert mel.shape[1] == CFG.n_mels
    assert mfcc.shape[1] == CFG.n_mfcc
    assert mel.shape[0] == mfcc.shape[0]


def test_vad_separates_speech_and_silence():
    vad = ap.SileroVAD(CFG)
    sig = np.concatenate([silence(0.3), tone(200, 0.5), silence(0.3)])
    segs = vad.segments(sig, threshold=0.5)
    assert len(segs) == 1
    assert segs[0].duration_seconds > 0.3
    # The voiced region should start after the leading silence.
    assert segs[0].start_seconds >= 0.2


def test_formants_shape_and_range():
    sig = tone(500, 0.2)
    formants = ap.track_formants(sig, 3, CFG)
    assert formants.shape[1] == 3
    finite = formants[np.isfinite(formants)]
    assert np.all((finite > 0) & (finite < SR / 2))


# ---------------------------------------------------------------------------
# alignment_engine
# ---------------------------------------------------------------------------
def test_text_to_phonemes_maps_known_graphemes():
    phs = text_to_phonemes("باب")
    assert [p.symbol for p in phs] == ["b", "aa", "b"]


def test_forced_align_monotonic_spans():
    model = MockAcousticModel(CFG)
    phonemes = text_to_phonemes("كتاب")
    model.set_target([p.token_id for p in phonemes])
    sig = tone(150, 1.0)
    emission = model.emissions(sig)
    spans = forced_align(emission, [p.token_id for p in phonemes], CFG)
    assert len(spans) == len(phonemes)
    last_end = -1
    for _tok, start, end, _score in spans:
        assert 0 <= start <= end < emission.shape[0]
        assert start >= last_end  # non-overlapping, in order
        last_end = end


def test_forced_align_rejects_too_short_audio():
    with pytest.raises(ValueError):
        forced_align(np.zeros((2, 40), dtype=np.float32), list(range(5)), CFG)


# ---------------------------------------------------------------------------
# gop_scorer
# ---------------------------------------------------------------------------
def test_gop_scores_target_biased_emissions_well():
    model = MockAcousticModel(CFG, peak=8.0)
    aligner = ForcedAligner(model, CFG)
    phonemes = text_to_phonemes("كتاب")
    sig = tone(150, 1.0)
    aligned, emission = aligner.align(sig, phonemes)
    scores = GOPScorer().score(emission, aligned)
    assert len(scores) == len(phonemes)
    summary = GOPScorer.summary(scores)
    # The mock biases the target tokens, so the utterance should score near 0.
    assert summary["mean_gop"] > -3.0


# ---------------------------------------------------------------------------
# tajweed_rules: Madd
# ---------------------------------------------------------------------------
def test_madd_natural_passes_at_two_counts():
    cfg = TajweedConfig()
    vowel = tone(150, cfg.counts_to_seconds(2), amp=0.4)
    res = tj.evaluate_madd(vowel, MaddType.TABEE, cfg)
    assert res.status is RuleStatus.PASSED
    assert res.pitch_stable
    assert abs(res.measured_counts - 2) < 0.6


def test_madd_fails_when_too_short():
    cfg = TajweedConfig()
    vowel = tone(150, cfg.counts_to_seconds(2) * 0.3, amp=0.4)
    res = tj.evaluate_madd(vowel, MaddType.TABEE, cfg)
    assert res.status is RuleStatus.FAILED
    assert "short" in (res.error or "")


def test_madd_lazim_requires_exactly_six():
    cfg = TajweedConfig()
    six = tone(150, cfg.counts_to_seconds(6), amp=0.4)
    assert tj.evaluate_madd(six, MaddType.LAZIM, cfg).status is RuleStatus.PASSED
    # A 4-count hold is correct for Muttasil but wrong for an obligatory Lazim.
    four = tone(150, cfg.counts_to_seconds(4), amp=0.4)
    res = tj.evaluate_madd(four, MaddType.LAZIM, cfg)
    assert res.status is RuleStatus.FAILED
    assert res.nearest_count == 6


def test_madd_munfasil_accepts_two_or_four():
    cfg = TajweedConfig()
    for counts in (2, 4):
        vowel = tone(150, cfg.counts_to_seconds(counts), amp=0.4)
        res = tj.evaluate_madd(vowel, MaddType.MUNFASIL, cfg)
        assert res.status is RuleStatus.PASSED, counts
        assert res.nearest_count == counts


def test_madd_uses_relative_pace_not_absolute():
    # A slow (Tahqiq) reciter: their single count is 0.45 s, so a natural madd
    # lasts ~0.9 s. Judged against the default 0.275 s unit it looks ~3.3 counts
    # and wrongly fails; calibrated to the reciter's pace it is correctly 2.
    cfg = TajweedConfig()
    slow_harakah = 0.45
    natural = tone(150, slow_harakah * 2, amp=0.4)

    uncalibrated = tj.evaluate_madd(natural, MaddType.TABEE, cfg)
    assert uncalibrated.status is RuleStatus.FAILED

    harakah = calibrate_harakah(natural, cfg)
    assert abs(harakah - slow_harakah) < 0.05
    calibrated = tj.evaluate_madd(natural, MaddType.TABEE, cfg,
                                  harakah_seconds=harakah)
    assert calibrated.status is RuleStatus.PASSED


# ---------------------------------------------------------------------------
# tajweed_rules: Ghunnah
# ---------------------------------------------------------------------------
def test_ghunnah_passes_for_sustained_nasal_band_energy():
    cfg = TajweedConfig()
    nasal = tone(300, cfg.counts_to_seconds(2) + 0.1, amp=0.4)  # within nasal band
    res = tj.evaluate_ghunnah(nasal, cfg)
    assert res.status is RuleStatus.PASSED
    assert res.nasal_counts >= cfg.ghunnah_min_counts - 0.2


def test_ghunnah_fails_for_oral_band_energy():
    cfg = TajweedConfig()
    oral = tone(2000, cfg.counts_to_seconds(2) + 0.1, amp=0.4)  # oral band
    res = tj.evaluate_ghunnah(oral, cfg)
    assert res.status is RuleStatus.FAILED


# ---------------------------------------------------------------------------
# tajweed_rules: Qalqalah
# ---------------------------------------------------------------------------
def test_qalqalah_detects_release_burst():
    cfg = TajweedConfig()
    quiet = tone(120, 0.01, amp=0.002)
    burst = (np.random.default_rng(1).normal(0, 0.5, int(SR * 0.03))).astype(np.float32)
    seg = np.concatenate([quiet, burst]).astype(np.float32)
    res = tj.evaluate_qalqalah(seg, closure_time=0.0, config=cfg)
    assert res.status is RuleStatus.PASSED
    assert res.peak_denergy > cfg.qalqalah_denergy_threshold


def test_qalqalah_fails_without_burst():
    cfg = TajweedConfig()
    # A steady high-frequency tone: its period is far shorter than the 5 ms
    # energy window, so the envelope is flat -- no release transient.
    flat = tone(3000, 0.08, amp=0.3)
    res = tj.evaluate_qalqalah(flat, closure_time=0.0, config=cfg)
    assert res.status is RuleStatus.FAILED


# ---------------------------------------------------------------------------
# server pipeline + session
# ---------------------------------------------------------------------------
def test_pipeline_emits_packet_for_word():
    pipeline = TajweedPipeline(audio_config=CFG)
    word = WordTarget.from_text("قمر")
    packet = pipeline.process_word(tone(150, 0.4), word)
    assert packet["word"] == "قمر"
    assert len(packet["phoneme_telemetry"]) == 3
    assert {"phoneme", "gop_score", "status"} <= set(packet["phoneme_telemetry"][0])


def test_session_segments_two_words():
    target = AyahTarget.from_words(["باب", "قمر"])
    session = TajweedSession(target, audio_config=CFG)
    stream = np.concatenate([tone(180, 0.4), silence(0.4), tone(160, 0.4)])
    packets = session.feed(stream)
    packets += session.flush()
    assert len(packets) == 2
    assert [p["word"] for p in packets] == ["باب", "قمر"]
    assert session.finished


def test_session_feed_pcm_path():
    target = AyahTarget.from_words(["باب"])
    session = TajweedSession(target, audio_config=CFG)
    pcm = ap.float_to_pcm16(np.concatenate([tone(180, 0.4), silence(0.4)]))
    packets = session.feed_pcm(pcm) + session.flush()
    assert len(packets) >= 1
    assert packets[0]["word"] == "باب"


# ---------------------------------------------------------------------------
# blueprint schema
# ---------------------------------------------------------------------------
def _blueprint_dict(verified: bool = True, schema: int = 1) -> dict:
    # Synthetic, non-Quranic placeholder data (verseKey 0:0, scriptUthmani "test").
    return {
        "schemaVersion": schema,
        "ayahs": [{
            "verseKey": "0:0",
            "scriptUthmani": "test",
            "source": {"corpus": "synthetic", "attribution": "unit-test",
                       "verified": verified},
            "phonemes": [
                {"symbol": "m", "baseLetter": "م", "isMaddVowel": False,
                 "expectedMaddCount": 0, "expectedDurationSeconds": 0.1},
                {"symbol": "aa", "baseLetter": "ا", "isMaddVowel": True,
                 "expectedMaddCount": 2, "expectedDurationSeconds": 0.55},
                {"symbol": "aa4", "baseLetter": "ا", "isMaddVowel": True,
                 "expectedMaddCount": 4, "expectedDurationSeconds": 1.1},
                {"symbol": "aa6", "baseLetter": "ا", "isMaddVowel": True,
                 "expectedMaddCount": 6, "expectedDurationSeconds": 1.6,
                 "maddType": "lazim"},
            ],
        }],
    }


def test_blueprint_loads_and_resolves_madd_specs(tmp_path):
    path = tmp_path / "bp.json"
    path.write_text(json.dumps(_blueprint_dict()), encoding="utf-8")
    bp = load_blueprint_file(path)
    ayah = bp.ayah("0:0")
    assert len(ayah.madd_vowels) == 3
    # Precedence: explicit type -> exact count -> default 2.
    by_symbol = {p.symbol: p for p in ayah.phonemes}
    assert by_symbol["aa"].madd_specification()[1] == "tabee"
    assert by_symbol["aa4"].madd_specification() == (
        by_symbol["aa4"].madd_specification()[0], "madd_4")
    assert by_symbol["aa4"].madd_specification()[0].allowed_counts == (4,)
    assert by_symbol["aa6"].madd_specification()[1] == "lazim"
    assert by_symbol["aa6"].madd_specification()[0].allowed_counts == (6,)


def test_blueprint_rejects_unverified_provenance(tmp_path):
    path = tmp_path / "bp.json"
    path.write_text(json.dumps(_blueprint_dict(verified=False)), encoding="utf-8")
    with pytest.raises(BlueprintError):
        load_blueprint_file(path)
    # ...but loads when verification is explicitly not required.
    assert load_blueprint_file(path, require_verified=False).ayah("0:0")


def test_blueprint_rejects_future_schema(tmp_path):
    path = tmp_path / "bp.json"
    path.write_text(json.dumps(_blueprint_dict(schema=99)), encoding="utf-8")
    with pytest.raises(BlueprintError):
        load_blueprint_file(path)


def test_blueprint_rejects_unknown_madd_type():
    with pytest.raises(BlueprintError):
        CanonicalPhoneme.from_dict({
            "symbol": "aa", "baseLetter": "ا", "isMaddVowel": True,
            "expectedMaddCount": 2, "expectedDurationSeconds": 0.5,
            "maddType": "not_a_real_type"})


# ---------------------------------------------------------------------------
# TajweedMaddEngine (stateful, pace-relative)
# ---------------------------------------------------------------------------
def test_madd_engine_calibrates_then_judges_relative():
    engine = TajweedMaddEngine(TajweedConfig())
    # A slow reciter: harakah ~0.4 s, so a natural madd is ~0.8 s.
    natural = tone(150, 0.8, amp=0.4)
    res = engine.evaluate(natural)  # default: natural 2-count
    assert res.status is RuleStatus.PASSED
    assert engine.is_calibrated
    assert abs(engine.harakah_seconds - 0.4) < 0.06

    # A 4-count Munfasil at the SAME pace (~1.6 s) is now judged relative -> pass.
    munfasil_4 = tone(150, 1.6, amp=0.4)
    ok = engine.evaluate(munfasil_4, madd_type=MaddType.MUNFASIL)
    assert ok.status is RuleStatus.PASSED
    assert ok.nearest_count == 4

    # A 1-count hold for that Munfasil is too short.
    short = tone(150, 0.4, amp=0.4)
    bad = engine.evaluate(short, madd_type=MaddType.MUNFASIL)
    assert bad.status is RuleStatus.FAILED


def test_madd_engine_pending_before_calibration():
    engine = TajweedMaddEngine(TajweedConfig())
    # First sound is a Lazim (no 2-count option) -> cannot calibrate pace yet.
    res = engine.evaluate(tone(150, 1.0, amp=0.4), madd_type=MaddType.LAZIM)
    assert res.status is RuleStatus.PENDING_CALIBRATION
    assert not engine.is_calibrated


def test_madd_engine_resets():
    engine = TajweedMaddEngine(TajweedConfig())
    engine.evaluate(tone(150, 0.6, amp=0.4))
    assert engine.is_calibrated
    engine.reset()
    assert not engine.is_calibrated
