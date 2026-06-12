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

## Current state

### Design Sprint (merged to main via PR #10)
VQS improved across all screens (Dashboard 65->79, Reader 53->77, Khutba 57->73, Recitation
50->70). Root tint fix, toolbar collapse, control row fixes, dashboard rhythm, chip enlivening.
Full log in `DESIGN_LOG.md`, before/after screenshots in `docs/design-sprint/`.

### Production Hardening (branch `hardening/production-grade`)
Audit scored the app at **B- (68/100)**. See `AUDIT.md` for the full breakdown. Key P0s:
no Qibla math test, no high-latitude city in the prayer validation suite, no per-prayer
manual time offset. Privacy and engine correctness are strong; gaps are in test coverage,
performance (cached launch, scroll profiling), and observability (no crash reporting).

## Map
`App/` shell + DesignSystem · `Core/Services` (QuranDatabaseManager, audio, prayer, location,
translation) · `Core/Models` · `Core/PrayerEngine/Adhan.swift` (validated vs Aladhan) ·
`Features/{Dashboard,QuranReader,RecitationCorrection,LiveTranslation,More,Settings,Tasbih}` ·
`SiraatTests/`. Prayer math + qibla + Quran bundle are test-covered; audio/notifications are not.

## Standing rules (the project contract)

- **Religious content is never generated, altered, or guessed.** Quran text from `FullQuran.json`
  (verifiable source). Translations from attributed, licensed editions. Diacritics, verse boundaries,
  and attributions are never modified. When a matter has scholarly difference (calculation method,
  Asr madhab, moon sighting), the app offers the choice and does not impose one answer.
- **Privacy stance on location:** foreground-only, `kCLLocationAccuracyHundredMeters`, never
  transmitted off-device, never persisted beyond the current computation. Manual city fallback for
  users who decline location.
- **Copy rules:** no em dashes, no en dashes, no hedging, no filler. Banned words: sleek,
  cutting-edge, solutions, elevate, world-class. Plain, confident, respectful language.
- **File-size ceiling:** ~500 lines. If a file approaches this, split by responsibility.
- **Visual language:** restrained and premium. Calm neutrals, one confident accent (teal),
  generous space. No clip-art crescents, no cartoon mosque imagery. Where Islamic motifs appear
  they are tasteful geometry rendered with care, not stickers. See `PRODUCT.md` anti-slop list.
- **Commit conventions:** conventional messages (`fix:`, `feat:`, `refactor:`, `perf:`, `test:`,
  `chore:`, `docs:`), Co-Authored-By trailer, one logical change per commit.

## Done earlier (main)
Design tokens + design sprint (PR #10), `ArabicText` Dynamic Type, recitation honesty (no false
"wrong" verdicts), prayer-reminder drift fix, App Store blockers (privacy manifest, keys out of
Info.plist), offline translation editions + misattribution fix. Staged next (not built): full
background audio + lock screen, real acoustic tajweed model, khutba encrypted store, Swift 6
strict concurrency.
