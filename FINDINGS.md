# Siraat Findings Backlog

Out-of-scope items and future work discovered during the production-grade audit.
Items here are real but not blocking the current hardening phases.

---

## Future Features (not in current scope)

- **Background audio and lock-screen controls.** Quran audio stops on lock. Needs `AVAudioSession` category `.playback` and `MPNowPlayingInfoCenter` integration.
- **Real acoustic tajweed model.** Recitation correction currently uses word-level follow-along (honest labeling). A real pronunciation model requires ML work.
- **Khutba encrypted store.** Saved khutba transcripts are in UserDefaults/plaintext. If they contain personal notes, they should be encrypted at rest.
- **Swift 6 strict concurrency.** The codebase uses `@MainActor` correctly in most places but has not been audited under Swift 6 strict concurrency checking.
- **Widget / Live Activity.** A lock-screen widget showing next prayer + countdown would be high-value for daily use.
- **Apple Watch companion.** Prayer times and Qibla on the wrist.
- **Ramadan mode.** Suhoor/Iftar times, fasting tracker, special du'as.
- **Offline translation downloads.** Spanish and French translations are online-only. Bundle them for full offline parity.
- **Verse-by-verse audio sync.** Audio plays per-verse but there is no word-level highlight sync during playback.
- **Tafsir integration.** No tafsir (exegesis) is currently available alongside translations.

## Technical Debt

- **Adhan.swift vendored as a single 1251-line file.** Functional but hard to update. Consider SPM if the project ever gains a Package.swift.
- **QuranDatabaseManager at 405 lines.** Not critical but could be split into read/write concerns.
- **No SwiftLint or formatting enforcement in CI.** Code style is manually maintained.
- **Simulator-only screenshot hook in SiraatApp.** The `UITEST_SCREEN` env var approach works but is fragile. A proper UI test target would be more robust.
