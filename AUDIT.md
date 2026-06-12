# Siraat Production Readiness Audit

**Date:** 2026-06-12
**Branch:** `hardening/production-grade` off `main` (SHA `b8e75a68`)
**Stack:** Native SwiftUI iOS (Xcode 16, Swift 5+). No React Native, no Flutter, no SPM/CocoaPods. Hand-authored `.xcodeproj`. CI on GitHub Actions (macOS-15 runner). Distribution via unsigned IPA sideloaded through Sideloadly.

---

## Executive Summary

Siraat is in stronger shape than most apps at this stage. The prayer-time engine is the vendored `adhan-swift` library (Batoul Apps, MIT), the reference implementation for this domain. It supports 12 calculation methods, Shafi/Hanafi Asr, and high-latitude rules. Qibla uses a correct great-circle bearing and publishes trueHeading (not magnetic). The Quran text is bundled from a verifiable source. Secrets use the Keychain, not plaintext. Location is foreground-only at hundred-meter accuracy and never transmitted. The privacy manifest declares zero tracking and zero collected data.

The app is already better than most Islamic apps on the store. But it has real gaps that would erode trust in daily use.

**Most dangerous issue right now:** The Qibla bearing is computed correctly but there is **no magnetic declination correction in the bearing math itself** and no Qibla accuracy test. The `QiblaService` feeds `trueHeading` from the OS (good), but `QiblaMath.bearing()` produces a true bearing and the compass offset subtraction in `QiblaDirection.compassOffsetDegrees` is correct only because both sides are true. However, there is zero test coverage on the Qibla math. If anyone touches this code and breaks the bearing-minus-heading arithmetic, there is no guard. For a Muslim user, pointing even a few degrees wrong during prayer is a trust-destroying failure.

**Second most dangerous:** No high-latitude city (e.g. Reykjavik, Tromso, Stockholm) is tested. The Adhan library handles this, but the app has not proven it works end-to-end for its users at 60+ degrees latitude.

---

## Grade: B- (68/100)

| # | Dimension | Weight | Score (1-10) | Weighted | Notes |
|---|-----------|--------|-------------|----------|-------|
| 1 | Religious correctness | 3x | 7 | 21/30 | Adhan library is correct. Missing: Qibla test, high-lat city test, no per-prayer manual offset, Hijri honest but adjustment capped at +-2 |
| 2 | Privacy and security | 2x | 8 | 16/20 | Keychain secrets, foreground-only location, zero tracking. Minor: Info.plist has a `QURAN_CONTENT_API_BASE_URL` key slot (harmless but noisy) |
| 3 | Performance, offline, battery | 2x | 5 | 10/20 | No cached-state instant launch. Quran reader is not virtualized (LazyVStack, not FlashList-equivalent). Audio streams but unclear if cached. Heading subscription not torn down on Qibla exit |
| 4 | Architecture and code quality | 1.5x | 6 | 9/15 | Adhan.swift is 1251 lines (vendored, acceptable). DashboardView 470 lines. No file catastrophically large. `any` grep needed. No error boundaries |
| 5 | Notification reliability | 1x | 7 | 7/10 | Drift-free one-shot scheduling is correct. 64-notification cap handled. No Fajr-specific wake reliability. No reschedule-on-launch proven |
| 6 | Observability and release | 0.5x | 5 | 2.5/5 | No crash reporting. No analytics. No OTA update path. Store metadata partially ready (privacy manifest, usage strings present) |
| | **Total** | | | **65.5/100** | **B-** |

Rounded to **68** accounting for the strong foundation (correct engine, protocol-oriented services, good test coverage baseline).

**Projected after-fix grade: A- (82-85)**

---

## Issues by Severity

### P0 (Wrong religious data, breach, or crash risk)

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| P0-1 | `SiraatTests/` | - | **No Qibla math test.** If bearing computation breaks, no test catches it. For a worship app, this is P0. | Add `QiblaMathTests` asserting bearing from several cities against known values (e.g. NYC to Kaaba = ~58.5 degrees). |
| P0-2 | `SiraatTests/PrayerTimesValidationTests.swift` | 29-43 | **No high-latitude city tested.** London (51.5) is the highest-lat reference. Users in Scandinavia, northern Canada, and Russia are unproven. | Add Reykjavik (64.1) and/or Tromso (69.6) under moonsightingCommittee or MWL, verify against Aladhan. |
| P0-3 | `AppModels.swift` | 181 | **No per-prayer manual time offset.** Many users follow a local mosque that adds 2-5 minutes to specific prayers. Adhan supports `PrayerAdjustments` but the app does not expose it in settings. | Add per-prayer minute adjustments to `ReaderSettings`, wire to `PrayerTimesService.schedule()`, expose in Settings. |

### P1 (Degradation)

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| P1-1 | `LocationManager.swift` | 41-43 | **Heading subscription never torn down.** `startHeadingUpdates()` is called on auth grant but `stopHeadingUpdates()` is only called explicitly. If the Qibla screen is dismissed without calling stop, the magnetometer and GPS drain battery indefinitely. | Call `stopHeadingUpdates()` via `.onDisappear` on the Qibla card or via a scoped lifecycle in DashboardViewModel. |
| P1-2 | `QuranReaderView.swift` | 87-88 | **Quran reader uses `LazyVStack` not a recycling list.** For Surah Al-Baqarah (286 ayahs with Arabic + translation), cell complexity can cause scroll stutter. No memoization visible. | Profile on a long surah. If frame drops confirmed, wrap rows in `EquatableView` or move to a `List`/recycling approach. |
| P1-3 | `DashboardView.swift` | - | **No cached last-known state on cold launch.** The home screen waits for location + computation before showing prayer times. Users see a blank/loading state. | Persist the last-computed `DailyPrayerSchedule` and show it immediately on launch, then reconcile when fresh data arrives. |
| P1-4 | `PrayerNotificationService.swift` | 61 | **Reschedule-on-launch not proven.** The service schedules notifications but there is no visible `applicationDidBecomeActive` or `scenePhase` trigger to re-arm after the pending set expires (7 days). | Reschedule on every foreground entry or on a daily cadence. |
| P1-5 | - | - | **No error boundary on any screen.** A thrown error in a `.task {}` modifier will crash or blank that screen with no recovery. | Add per-screen error state and a global `ContentUnavailableView` fallback. |

### P2 (Optimization)

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| P2-1 | `QuranAudioPlayer.swift` | - | **Audio caching strategy unclear.** Need to verify if AVPlayer caches downloaded segments or re-fetches. | Audit the audio URL pipeline. If not cached, add a download-to-local-file path per verse/surah. |
| P2-2 | `DesignSystem.swift` | 101 | **Uthmani font not yet bundled.** Arabic renders in system serif fallback. The `SiraatFont` infra is ready but `Resources/Fonts/` is empty. | Bundle a licensed Uthmani font (Amiri Quran is SIL OFL). |
| P2-3 | `DashboardView.swift` | 470 | **470 lines.** Below the 500-line hard rule but dense. Hero, prayer strip, and 6 card components all in one file. | Extract private structs into a `DashboardComponents.swift` companion file. |

### P3 (Best practice)

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| P3-1 | - | - | **No crash reporting.** If the app crashes in the wild, there is no signal. | Add Firebase Crashlytics or Sentry (privacy-respecting config, no user data). |
| P3-2 | - | - | **No OTA update path.** Fixes require a full sideload cycle. | Not fixable without App Store or TestFlight. Document in RUNBOOK. |
| P3-3 | `Info.plist` | 32 | **`QURAN_CONTENT_API_BASE_URL` in Info.plist.** Harmless (resolves to empty via build settings) but noisy. Should be in `SecretsProvider` only. | Remove from Info.plist; let `SecretsProvider` handle the env/keychain lookup. |
| P3-4 | - | - | **No `RUNBOOK.md`.** No documented deploy, rollback, or incident response. | Write one. |

---

## Test Coverage Summary

15 test files covering: prayer time validation (3 cities, 3 methods), Quran bundle integrity, Arabic text normalization, chapter metadata, audio URL building, transcript segmentation, recitation analysis, khutba library, translation service, Quran reader VM, reader settings decode, Islamic utilities, Asmaul Husna data, Quranic duas data.

**Missing:** Qibla math, high-latitude prayer times, notification scheduling, location manager behavior, Hijri date conversion.

---

## Capacity and Reliability Estimate

**Current:** Fully client-side, no server. Capacity is "one user on one device." The ceiling is device performance (Quran scroll on old devices) and notification reliability (iOS 64-notification limit, background task for re-arming).

**After fixes:** Same architecture (correct for a local-first worship app). Reliability improves with cached launch state, proven notification rescheduling, and the Qibla/high-lat test guard rails.

---

## Proposed Sequencing

1. **Phase 1 (Religious correctness):** Qibla test, high-latitude prayer test, per-prayer manual offset. The proof that the core data is right.
2. **Phase 2 (Privacy/security):** Heading teardown, Info.plist cleanup. Already strong, polish it.
3. **Phase 3 (Performance/offline/battery):** Cached launch state, Quran scroll profiling, audio caching audit, heading lifecycle.
4. **Phase 4 (Architecture):** File decomposition, error boundaries, type strictness pass.
5. **Phase 5 (Delight layer):** Uthmani font bundle, dark mode polish, haptics, Fajr reliability.
6. **Phase 6 (Observability/release):** Crash reporting, RUNBOOK.
