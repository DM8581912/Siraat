# SIRAAT: Production Hardening — Resume Phase 4+

## Repo
`DM8581912/Siraat` (private). Clone if not local:
```bash
gh repo clone DM8581912/Siraat ~/Siraat && cd ~/Siraat
git checkout main
```

## What this is

Native SwiftUI iOS Islamic app. Prayer times (vendored adhan-swift), Qibla compass,
offline Quran reader (6236 ayahs, 4 scripts, 6 translations, 4 reciters), recitation
follow-along with tajweed feedback, 99 Names, Quranic du'as, tasbih counter, live khutba
translation. Dev machine is Windows with no Xcode. CI on GitHub Actions is the compiler,
test runner, and eyes. Push → CI → verify.

## What has been done (Phases 0-3, merged to main)

**Phase 0**: Full production-readiness audit. Grade: B- (68/100). See AUDIT.md.

**Phase 1 (Religious correctness)**: QiblaMathTests with hardcoded Aladhan API reference
bearings (independent truth source) + vendored Adhan cross-check. High-latitude prayer
validation (Reykjavik 64.1°N, Tromso 69.6°N). Per-prayer manual time offset wired through
Adhan PrayerAdjustments → ReaderSettings → PrayerTimesService → Settings UI (5 steppers,
no Sunrise). Backward-compat decode test for old settings JSON.

**Phase 2 (Privacy/security)**: Heading sensor lifecycle (stop on background, restart on
foreground via scenePhaseChanged). Removed stale QURAN_CONTENT_API_BASE_URL from Info.plist.

**Phase 3 (Performance/offline/battery)**: QuranVerseRow conforms to Equatable + wrapped in
EquatableView for scroll optimization. Cached last DailyPrayerSchedule for instant cold
launch. Reminder re-arm on every foreground entry (reset didAutoRescheduleReminders on
background). Audio caching audited (HTTP-level via URLCache, acceptable).

**Current state**: 47 tests, 0 failures. All merged to main. CI macOS runners were in
outage (GitHub-side); retry with `gh workflow run "Build unsigned IPA" -R DM8581912/Siraat --ref main`.

## 8-Dimension Audit (conducted post-Phase 3)

### Dimension 1: Religious Correctness (95/100)
- Vendored Adhan library (reference implementation). Tested against Aladhan API.
- Quran text from FullQuran.json (verifiable source). 114 surahs, 6236 ayahs confirmed.
- Translations licensed and attributed (Saheeh International, Jalandhari, Diyanet, Kemenag RI).
- Qibla math tested from 5 cities + Aladhan cross-reference.
- Gap: CoreML tajweed model is unvalidated against real tajweed rules. Ship without it or validate.
- Gap: No Jummah (Friday prayer) handling — app shows Dhuhr on Friday, not Jummah.

### Dimension 2: UX & Onboarding (55/100) — WORST DIMENSION
- NO onboarding flow. User opens app → blank dashboard → confusion.
- No manual location fallback. If location is denied, user is stuck.
- Recitation "Listen" button is mislabeled — it records, not plays.
- No reference playback in recitation (can't hear correct pronunciation).
- Settings changes have no visual confirmation (no toast).
- Empty states exist but are generic (no next-step guidance).
- No loading feedback when switching reciters or translations.

### Dimension 3: Feature Completeness (65/100)
- Missing: Manual city/coordinates entry when location unavailable.
- Missing: Jummah prayer handling (Friday replaces Dhuhr).
- Missing: Expanded du'a collection (only 13 hardcoded, no categories).
- Missing: Bookmark notes UI (model has `note` field but UI never shows/edits it).
- Missing: Quran audio progress bar (no currentTime/duration tracking).
- Missing: Khutba metadata (mosque name, imam, topic).
- Missing: Khutba/dua export (PDF, share).
- Nice-to-have: Prayer tracking, hifz tracker, zakat calculator, tafsir.

### Dimension 4: Performance (70/100)
- QuranVerseRow now uses EquatableView (Phase 3 fix).
- Page mode reader uses TabView which renders ALL pages upfront — janky on long surahs.
- Search is O(n) unoptimized — full filter on every keystroke, no debounce.
- PrayerTimesService.schedule() is synchronous, CPU-bound — could jank main thread.
- No audio preloading — gap between verses during continuous playback.

### Dimension 5: Accessibility (78/100)
- VoiceOver: Excellent. Custom labels on dashboard, prayer strip, qibla compass, tasbih, verse rows.
- Dynamic Type: Works. ArabicText uses @ScaledMetric. SiraatType uses semantic fonts.
- Contrast: WCAG AA compliant (verified in DesignSystem.swift comments). Gold accent was darkened to pass.
- Gap: Hairline borders (0xE6E1D6 on white) fail AA for lines.
- Gap: No symbol indicator for "next prayer" — only color change.
- Gap: Tab bar items have no custom accessibility labels.

### Dimension 6: Data Integrity (72/100)
- Verse of the day hash can produce nil (no bounds check on global ayah number).
- Prayer schedule cache doesn't track which settings computed it — stale if method changes.
- No validation that translation files are complete (partial corruption = silent blank translations).
- Timezone change doesn't invalidate cached prayer times.
- Bookmark referencing a deleted verse = blank card.

### Dimension 7: Error Handling (60/100)
- No error boundary on any screen. Thrown error in .task{} = blank/crash.
- Reminder scheduling failure is silent — user never knows.
- Audio 404 is silent — playback fails with no message.
- Network fetch failure in reader = blank, no retry button.
- DeepL rate limit (429) surfaces as vague "invalid response".
- Location timeout doesn't exist — waits forever.

### Dimension 8: Polish (60/100)
- Minimal animations (only tasbih ring + qibla compass).
- No page transitions between tabs.
- No toast notification system (only blocking alerts).
- No bookmark toggle animation or haptic.
- No loading state when switching surah/reciter/translation.
- No dark mode transition animation.

### Overall: 68/100 (B-)
Path to A-: Fix onboarding, location fallback, error boundaries, search debounce, reader page
mode, reminder feedback. Estimated: 40-60 hours.

## What to do next (Phase 4+)

Pick from these priorities based on impact. Each is independent and can be done in any order.

### P0 — Must fix

1. **Onboarding flow**: First-launch welcome screen explaining features. Guided location
   permission request with "We use your location for prayer times, never upload it."
   Manual city entry fallback if denied. Set `UserDefaults.hasCompletedOnboarding`.

2. **Manual location fallback**: When location is denied or unavailable, offer a city
   search or manual lat/lon entry. Store as a "manual override" in settings.

3. **Error boundaries**: Wrap each screen's `.task{}` in do/catch. Show
   `ContentUnavailableView` with retry button on failure. Never blank screen.

4. **Reminder scheduling feedback**: When PrayerNotificationService fails (permission
   denied), show a toast/banner on Dashboard. When it succeeds, show "Reminders set."

5. **Recitation UX fix**: Rename "Listen" → "Record". Add a "Play verse" button that
   plays the reference recitation from the selected reciter.

### P1 — Should fix

6. **Search debounce**: Add 300ms debounce to QuranReaderViewModel.searchText before
   filtering displayedVerses. Currently O(n) on every keystroke.

7. **Verse of the day bounds check**: Validate that the global ayah number from the hash
   resolves to a real verse. If nil, fall back to 1:1 (Fatihah).

8. **Prayer cache invalidation**: Add a settings hash to the cached DailyPrayerSchedule.
   When settings change, discard the stale cache.

9. **Reader page mode optimization**: Replace TabView paging with a LazyHStack + paging
   scroll behavior, or limit prefetch to ±5 pages.

10. **Audio error handling**: Listen for AVPlayerItem.status == .failed in QuranAudioPlayer.
    Surface error message when a verse's audio URL returns 404.

### P2 — Polish

11. **Toast notification system**: A floating banner view that slides in from top, shows
    success/error/info messages, auto-dismisses after 3s. Replace all .alert() for
    non-blocking messages.

12. **Bookmark haptics + animation**: UIImpactFeedbackGenerator(.light) on toggle.
    Scale animation on the bookmark icon.

13. **Expanded du'as**: Increase from 13 to 30+ Quranic du'as. Add categories
    (forgiveness, guidance, hardship, knowledge, healing). Add audio playback per dua.

14. **Khutba metadata**: Add optional mosque name, imam, topic fields to KhutbaSession.
    Show in library list.

15. **Jummah handling**: Detect Friday, show "Jummah" instead of "Dhuhr" in the prayer
    strip and reminders.

## Build/verify loop

- Git author: `git -c user.name="Malek" -c user.email="malekadjeb@gmail.com" commit`
- Push to main → CI runs
- Watch: `gh run watch <id> --exit-status --interval 30`
- CI trigger includes: `main | feat/** | feature/** | fix/** | chore/** | hardening/**`
- Screenshots: `gh run download <id> -R DM8581912/Siraat -n Siraat-screenshots -D <dir>`

## Rules

- Religious correctness is sacred. Never generate/alter Quranic text.
- One token source of truth: `Siraat/App/DesignSystem.swift`.
- Conventional Commits. No Co-Authored-By trailer.
- Prove every change via CI. "It should work" is not acceptable.
- Read CLAUDE.md, PRODUCT.md, AUDIT.md before starting any work.

## Architecture quick reference

```
App/         → SiraatApp, AppServices (DI), DesignSystem, MainTabView, AppearanceController
Core/
  Models/    → AppModels, IslamicUtilityModels, QuranChapter, QuranBundle
  Services/  → PrayerTimesService, LocationManager, PrayerNotificationService,
               QuranDatabaseManager, QuranAudioPlayer, TranslationService,
               RecitationCorrectionService, AudioStreamManager, QiblaService,
               SecretsProvider, AudioURLBuilder
  Utilities/ → QiblaMath, HijriDate, ArabicTextNormalizer, TranscriptSegmenter
  PrayerEngine/ → Adhan.swift (vendored, 1251 lines, MIT)
Features/
  Dashboard/           → DashboardView (474 lines), DashboardViewModel
  QuranReader/         → QuranReaderView (393 lines), QuranReaderViewModel, SurahIndexView, JuzIndexView
  RecitationCorrection/→ RecitationCorrectionView, RecitationCorrectionViewModel
  LiveTranslation/     → LiveTranslationView, LiveTranslationViewModel, KhutbaLibrary, KhutbaLibraryView
  Settings/            → SettingsView, SettingsViewModel
  More/                → MoreView, NamesOfAllah, NamesOfAllahView, QuranicDuas, DuasView
  Tasbih/              → TasbihView
SiraatTests/ → 16 test files, 47 tests
```

## Test coverage map

| Tested | Not tested |
|--------|-----------|
| Prayer math (5 cities, 3 methods, high-lat) | LocationManager (auth, heading) |
| Qibla math (5 cities, Aladhan ref) | PrayerNotificationService (scheduling) |
| Quran bundle (114 surahs, 6236 ayahs) | QuranAudioPlayer (playback) |
| Recitation correction (word match, tajweed) | All ViewModels (Dashboard, Settings, LiveTranslation) |
| Audio URL builder (3 reciters) | All Views (no UI tests) |
| Translation service (mock + factory) | HijriDate conversion |
| Reader VM (debounce, persistence) | CoreML tajweed model |
| Database manager (persistence, offline) | |
| Backward-compat settings decode | |
