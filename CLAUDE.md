# Siraat — Project Context (Claude Code)

Premium **SwiftUI iOS** Islamic app: prayer times + qibla, offline Quran reader, recitation
follow-along, 99 Names, du'as, tasbih, live khutba translation. Repo: `github.com/DM8581912/Siraat`.
Read `PRODUCT.md` (brand/users/anti-slop) and `DESIGN.md` (design system) before any UI work.

## The build/verify loop (read this first)
The dev machine is **Windows with no Xcode — nothing compiles or runs locally.** Do not claim
"done" from reading code. The CI loop is the compiler, the test runner, and the eyes:

- Push to a `main | feat/** | feature/** | fix/** | chore/**` branch → `.github/workflows/ios-build.yml`
  (macos-15) creates+boots a simulator, runs tests, captures a **PNG per screen**, builds the
  **unsigned IPA**.
- Watch: `gh run watch <id> --exit-status --interval 30`
- Screens: `gh run download <id> -R DM8581912/Siraat -n Siraat-screenshots -D <dir>` (Read the PNGs).
- IPA (sideload via Sideloadly/AltStore): `... -n Siraat-unsigned-ipa`. See `BUILD_ON_IPHONE.md`.
- Screenshots are driven by a `UITEST_SCREEN` env hook in `SiraatApp` (simctl-only, never in prod).

## Non-negotiables
- **Religious correctness is sacred.** Never generate, alter, paraphrase, or guess Quranic text,
  translations, transliterations, attributions, or surah/ayah numbers. Verified data only
  (`FullQuran.json`, `Resources/Translations/*` built by `Scripts/build_translations.py`).
  Design the container; never invent contents. A wrong ayah ships nothing.
- **One token source of truth: `Siraat/App/DesignSystem.swift`** (`SiraatColor`, `SiraatRadius`,
  `SiraatSpacing`, `SiraatType`, `ArabicText`, `SiraatFont`). Views consume tokens; never add
  raw color/radius/spacing/font literals to a screen.
- **Never push to main directly.** Feature branches + PR. Conventional Commits. End commits with
  the Co-Authored-By trailer.
- Accessibility is the floor: Dynamic Type (incl. Arabic via `ArabicText`), VoiceOver in-language,
  AA contrast, color+symbol status. Reverence over decoration; the anti-slop bans in PRODUCT.md hold.

## Current state — Design Sprint (branch `feature/design-sprint`)
Full handoff + resume prompt: `docs/design-sprint/ITERATION_PROMPT.md`. Scores + findings:
`DESIGN_LOG.md`. BEFORE screenshots: `docs/design-sprint/before/`.

- Phase 0 (PRODUCT.md, DESIGN.md, token extraction) and Phase 1 baseline: **done, CI-green.**
- VQS baseline (target ≥80): **Dashboard 65 · Khutba 57 · Reader 53 · Recitation 50.**
- **#1 finding: default iOS blue everywhere instead of teal `SiraatColor.accent`** — root `.tint`
  fix is the biggest single lift. Also: clipped control rows (Recitation "Ayah", Khutba language
  picker), reader toolbar control-soup, system-serif Arabic (Uthmani font not yet bundled).
- Owner approved running **Phases 2→4** (refine + enhance) then proving at Phase 5. **Rule: every
  visual change raises the screen's VQS or is reverted** — re-capture via CI to prove it.

## Map
`App/` shell + DesignSystem · `Core/Services` (QuranDatabaseManager, audio, prayer, location,
translation) · `Core/Models` · `Core/PrayerEngine/Adhan.swift` (validated vs Aladhan) ·
`Features/{Dashboard,QuranReader,RecitationCorrection,LiveTranslation,More,Settings,Tasbih}` ·
`SiraatTests/`. Prayer math + qibla + Quran bundle are test-covered; audio/notifications are not.

## Done earlier (main, via PR #9)
Design tokens, `ArabicText` Dynamic Type, recitation honesty (no false "wrong" verdicts),
prayer-reminder drift fix, App Store blockers (privacy manifest, keys out of Info.plist),
offline translation editions + misattribution fix. Staged next (not built): full background
audio + lock screen, real acoustic tajweed model, khutba encrypted store, Swift 6 strict concurrency.
