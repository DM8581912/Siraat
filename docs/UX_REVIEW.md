# Siraat — UX Review

A prioritized, screen-by-screen review of the current iOS app's user experience,
with concrete fixes. It feeds two things: the near-term iOS polish work, and the
**native Android (Jetpack Compose)** port, which must mirror the same design and
behavior (see `DESIGN_UX_SPEC.md`).

**Method & caveat.** This review is from the SwiftUI source and the design docs
(`DESIGN.md`, `PRODUCT.md`, `App/DesignSystem.swift`). The CI per-screen
screenshots could not be retrieved in the review environment (the artifact host
is outside the network egress allowlist), so findings about *visual* rendering
(exact spacing rhythm, truncation, contrast in situ) are marked **[needs visual
pass]** and should be confirmed against the `Siraat-screenshots` CI artifact.

## Severity

| Level | Meaning |
|---|---|
| **P1** | Breaks a stated product principle, or affects every screen. Do first. |
| **P2** | Clear UX friction or inconsistency on a specific screen. |
| **P3** | Polish; nice-to-have. |

---

## Cross-cutting findings (apply app-wide)

### P1 — Design-token drift
`DESIGN.md` and `CLAUDE.md` make `App/DesignSystem.swift` the single source of
truth and **ban raw color/radius/spacing/font literals in screens**. Several
screens still hardcode values, which is exactly what produces an "inconsistent,
unpolished" feel and what will make the Android port drift:

- **Tasbih** (`TasbihView.swift`): `spacing: 24/6/12`, `.padding(20)`,
  `.padding(.vertical, 10)`, `.font(.system(size: 72))`, `ArabicText(size: 34)`
  hardcoded, raw `.headline`/`.subheadline`.
- **Dashboard hero** (`DashboardView.swift`): `.font(.system(size: 40, design:
  .serif))`, `spacing: 18/6`, `CountdownRing` `lineWidth: 6` / `92×92`, cards use
  raw `.headline`/`.title3`/`.caption` and `12/14/20` spacing; `QiblaCard`
  `96×96`, `offset(y: -38)`.
- **Live Translation** (`LiveTranslationView.swift`): `LiveSegmentView`
  `.font(.system(.title3, design: .serif))`, `InfoBanner` `.padding(10)`,
  `EmptyTranslationState` `.font(.system(size: 44))`, control bar default
  `.padding()`.
- **More** (`MoreView.swift`): `MoreRow` raw `.title3`/`.headline`/`.caption`,
  `spacing: 14`, `frame(width: 34)`, `.padding(.vertical, 4)`.
- **Quran Reader** (`QuranReaderView.swift`): `LazyVStack(spacing: 14)`, default
  `.padding()`, footer `.caption2`, playback `.font(.title3)`.
- **Practice Recitation** — **fixed** (literals routed through
  `SiraatSpacing`/`SiraatType`).

**Fix:** sweep each screen and replace literals with `SiraatSpacing`,
`SiraatRadius`, `SiraatType`, `SiraatColor`. Where a value has no token (the 40pt
serif hero title, the 72pt counter, the 260pt tasbih ring), add a named token
(e.g. `SiraatType.heroNumeral`, `SiraatType.Arabic.dhikr` already exists) rather
than leaving a literal. This is the highest-leverage polish item and the
prerequisite for a faithful Android theme.

### P2 — Repeated control bar is not a component
Practice Recitation and Live Translation both build the same bottom bar:
`WaveformView` + a row of bordered icon buttons + a prominent record/listen
button + `.background(.regularMaterial)`. It is duplicated, and the paddings
differ. **Fix:** extract a `RecordingControlBar` component (waveform + leading
secondary actions + trailing primary mic toggle) so the two listening surfaces
are identical and the Android port has one spec to match.

### P2 — Status semantics are re-derived per screen
The recitation word-chip computes foreground/background/symbol from
`status` + tajweed severity inline. The color+symbol status convention (AA,
color-blind-safe) is a design-system concern. **Fix:** centralize a
`StatusStyle(for:)` (color + SF Symbol) in the design system so every status
surface (chips, per-letter tajweed, playback) reads identically.

### P3 — Naming consistency
"Practice Recitation" (entry CTA) vs "Recitation Correction" (old title) —
**fixed**. Audit remaining titles for the same calm, plain register
(`PRODUCT.md` tone): prefer "Practice Recitation", "Live Translation",
"Quran" over clinical phrasing.

---

## Screen-by-screen

### Dashboard (`Features/Dashboard`)
Strong structure: brand header, next-prayer hero with countdown ring, prayer
strip, qibla, verse of the day, quick actions, continue-reading. Adheres to "one
focus" with a clear focal path.
- **P1** token drift in the hero/cards (above).
- **P2** the hero countdown redraws every second via `TimelineView(by: 1)` — fine,
  but confirm it isn't forcing the whole `ScrollView` to recompute. **[needs
  visual pass / profiling]**
- **P3** `QiblaCard` is a static arrow on the dashboard; consider making it clearly
  tappable into a full qibla screen (affordance: chevron, like Continue Reading).

### Quran Reader (`Features/QuranReader`)
The best-built screen: `LazyVStack` + `EquatableView` row diffing, real empty
states (`ContentUnavailableView`), per-verse play/bookmark/copy/share, display
settings sheet with detents, offline-translation notice. Accessibility labels are
thorough.
- **P2** the search field, surah/juz buttons, and display button form a dense
  toolbar; **[needs visual pass]** to confirm it doesn't crowd on small devices.
- **P3** minor token drift (`spacing: 14`, default padding, `.caption2`).

### Practice Recitation (`Features/RecitationCorrection`) — partially fixed
Was the most overloaded screen (verse picker + ayah stepper + script picker +
redundant Load button + memorize toggle + analysis line + progress + word chips +
per-letter section with its own toggle/warning/legend + live transcript + control
bar) — counter to "one focus, single primary action."
- **Done:** removed the redundant "Load Verse" button (selection auto-loads),
  renamed title, routed literals to tokens.
- **P2 still open:** consolidate selection (surah + ayah + script) into one
  compact header row or a sheet, so the body is dominated by the ayah + chips +
  the single primary action (Listen). Move "Show colored ayah" + experimental
  notice into a disclosure so they don't compete by default.
- **P2:** the per-letter legend and the chip status should share one
  `StatusStyle` (above).

### Live Translation (`Features/LiveTranslation`)
Good empty state, auto-scroll, on-device translation with a clear "downloading
model" notice, save/clear/record actions. Solid.
- **P1** token drift (segment title font, info banner, empty state).
- **P2** shares the control-bar duplication (above).
- **P3** "Translating…" inline spinner is good; ensure it reads to VoiceOver as a
  live region. **[needs visual pass]**

### Tasbih (`Features/Tasbih`)
Clean, focused single-purpose screen: big tap counter with progress ring, dhikr
picker, target presets, haptics, round tracking.
- **P1** the *most* token drift in the app (sizes 72/34, spacings 24/6/12,
  paddings 20/10). Functionally fine, but it bypasses the system wholesale — high
  priority for the token sweep and the Android parity baseline.
- **P3** target presets `33/99/100` and Reset are styled as ad-hoc segmented
  buttons; consider a real segmented control (`Picker(.segmented)`) for the
  presets, Reset separated, to match the reader's display sheet idiom.

### More / 99 Names / Quranic Duas / Khutba Library (`Features/More`)
`MoreView` is a standard grouped `List` of navigation rows. Reasonable.
- **P2** `MoreRow` doesn't use tokens (spacing/fonts/frame literals); align it
  with the row idiom used elsewhere (e.g. Continue Reading card).
- **[needs visual pass]** 99 Names, Duas, Khutba Library list/detail screens were
  not read in depth here; review against the same token + one-focus checklist.

---

## Accessibility (already a strength — keep it)
Dynamic Type via semantic fonts + `ArabicText` (`@ScaledMetric`), Arabic tagged
with `typesettingLanguage(ar)` for shaping + VoiceOver, color+symbol status,
combined accessibility elements, in-language labels. **Hold this bar on Android:**
Material `sp` typography, `LayoutDirection.Rtl`, TalkBack labels in the content
language, and never color-only status.

## Performance / "jank"
No obvious correctness-level perf problems in code: the long list (Quran) uses
`LazyVStack` + `EquatableView`; dashboard/tasbih are short. Likely jank sources to
**profile against the device** (cannot be confirmed from source):
- `TimelineView(by: 1)` hero recompute scope.
- `ArabicText`/scripture font shaping cost on fast scroll if the Uthmani face is
  bundled.
- Waveform animation during recording (18 capsules animating per level change).
Recommend an Instruments/Compose-layout-inspector pass once a screenshot/profile
channel is available.

## Prioritized backlog
1. **P1** App-wide design-token sweep (Tasbih, Dashboard hero, Live Translation,
   More, Reader). Add missing named tokens instead of literals.
2. **P1** Lock the cross-platform spec (`DESIGN_UX_SPEC.md`) so Android starts
   from parity, not a re-interpretation.
3. **P2** Extract `RecordingControlBar` + centralize `StatusStyle`.
4. **P2** Recitation selection consolidation + disclosure for advanced toggles.
5. **P3** Qibla affordance, Tasbih segmented presets, MoreRow tokenization.
6. **Verify** everything marked **[needs visual pass]** against the CI
   `Siraat-screenshots` artifact once the egress host is allowlisted.
