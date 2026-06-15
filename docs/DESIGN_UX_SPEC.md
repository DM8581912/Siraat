# Siraat — Cross-Platform Design & UX Spec

The shared, platform-neutral specification for Siraat's design and user
experience, written so **iOS (SwiftUI)** and **Android (Jetpack Compose)** render
the same product. iOS is the reference implementation; Android mirrors it.

- iOS source of truth for tokens: `Siraat/App/DesignSystem.swift` (see `DESIGN.md`).
- Product principles: `PRODUCT.md`. Current UX issues: `UX_REVIEW.md`.
- **Rule:** screens consume tokens and components. No raw color/spacing/radius/
  font literals in a screen, on either platform.

## 1. Principles (both platforms)
1. **Religious correctness is non-negotiable.** Never generate/alter/guess
   Quranic text, translations, attributions, or ayah numbers. The UI is a
   container; verified data fills it.
2. **Reverence over decoration.** No mosque/crescent clip-art, no gamification,
   no glassmorphism/gradient-text slop (`PRODUCT.md` anti-slop list).
3. **One focus per screen**, one primary action, generous quiet.
4. **Arabic is first-class** typography, not a font swap (shaping, tashkeel, RTL,
   numerals, Dynamic Type scaling of the Arabic itself).
5. **Offline-first** and **accessible by default** (Dynamic Type, screen reader
   in-language, AA contrast, color+symbol status).

## 2. Color
Adaptive light/dark; no pure black/white. Hex is identical across platforms.

| Token | Light | Dark | Role |
|---|---|---|---|
| `background` | `#F7F5F0` | `#0E1413` | app canvas |
| `secondaryBackground` | `#FFFFFF` | `#18211F` | cards / surfaces |
| `surfaceElevated` | `#FFFFFF` | `#1F2A27` | raised surface |
| `hairline` | `#E6E1D6` | `#2A3633` | 1px borders |
| `accent` | `#0C6B57` | `#4FC2A6` | primary action / highlight |
| `accentDeep` | `#094B3D` | `#2E8C76` | gradients, pressed |
| `gold` | `#8A6410` | `#E0B65C` | sparing secondary (verse/khutba) |
| `warning` | `#C2741E` | `#E2944A` | advisory status |
| `destructive` | `#C53330` | `#E57470` | error status |
| `textPrimary` | `#14201D` | `#F2F5F3` | primary text |
| `textSecondary` | `#5C6864` | `#9BA8A3` | secondary text |

**Android:** define these as a custom `ColorScheme` (light + dark). **Disable
Material You dynamic color** — the brand palette is intentional; wallpaper-derived
theming would break it. `gold` light is intentionally darkened to ~4.6:1 so it is
AA-legible as a label on white; keep that value, do not "brighten" it.

## 3. Typography
Latin rides the platform's semantic styles so Dynamic Type / font-scale is free.
The named ramp:

| Token | iOS | Android (Material 3 / `sp`) | Use |
|---|---|---|---|
| `display` | largeTitle serif bold | `headlineLarge`, serif, bold | screen title / brand |
| `title` | title2 semibold | `titleLarge` semibold | card / section heading |
| `heading` | headline | `titleMedium` | row title |
| `body` | body | `bodyLarge` | translation, prose |
| `callout` | subheadline | `bodyMedium` | supporting line |
| `caption` | caption | `labelMedium` | metadata |
| `micro` | caption2 | `labelSmall` | credits, fine print |

Keep weight+scale contrast ≥1.25 between rungs; never flat. Hero numerals (prayer
countdown, tasbih counter) are oversized rounded/serif display figures — give them
named tokens, not literals, on both platforms.

## 4. Spacing & radius
Spacing scale (pt = dp): `xxs 4 · xs 8 · sm 12 · md 16 · lg 20 · xl 24 · xxl 32`.
Vary deliberately for rhythm; avoid uniform padding.
Radius: `card 16`, `inner 10` — two tiers only. (Compose: `RoundedCornerShape`,
continuous-style not available; 16/10 dp is close enough.)

## 5. Elevation & motion
Flat + 1px `hairline` border, **no heavy shadows**; one container language, no
nested cards. Motion is restrained, ease-out, no bounce/elastic: countdown ring
(1s tick), counter numeric roll-up, qibla compass spring, gold highlight on the
reciting ayah. Never animate layout decoratively. (Compose: `tween`/`animate*AsState`
with `FastOutSlowInEasing`; avoid `spring` overshoot except the compass.)

## 6. Arabic typography (critical, both platforms)
- Bundle a licensed Uthmani face (e.g. KFGQPC HAFS / Amiri Quran) for scripture;
  fall back gracefully to the system face until present.
- Scripture text (`scripture: true`) uses the Uthmani face; non-scripture Arabic
  uses the system face.
- Tag Arabic runs with the Arabic language identity for correct shaping **and** so
  the screen reader uses an Arabic voice (iOS `typesettingLanguage(ar)`; Android:
  `LocaleList`/`localeList` span + content locale).
- Arabic **scales with the user's text-size setting** (iOS `@ScaledMetric`;
  Android `sp` + `fontScale`). Default Arabic sizes are centralized
  (`SiraatType.Arabic`: verseOfDay 24, surahName 22, name99 26, dua 28, dhikr 34).
- Always render Arabic RTL with trailing alignment.

## 7. Components (shared contract)
| Component | Contract | iOS | Android |
|---|---|---|---|
| `Card` | secondaryBackground fill, hairline stroke, `card` radius, default `md` padding | `Card` view | `Surface`/`Box` + `border` |
| `SectionBand` | titled card (heading + content) | `SectionBand` | titled `Surface` composable |
| `ArabicText` | RTL, language-tagged, Dynamic-Type-scaled, optional scripture face | `ArabicText` | `Text` w/ locale span + `sp` |
| `WaveformView` | N capsules driven by a 0–1 level, accent gradient | `WaveformView` | `Canvas`/`Row` of bars |
| `FlowLayout` | RTL-aware wrapping chips | `FlowLayout` | `FlowRow` (layoutDirection Rtl) |
| `RecordingControlBar` *(to build)* | waveform + secondary actions + primary mic toggle on `regularMaterial` | extract from Recitation/LiveTranslation | bottom bar on blurred surface |
| `StatusStyle` *(to build)* | maps status → (color, symbol); color-blind-safe | new in DesignSystem | sealed class → (Color, Icon) |
| Empty state | icon + title + one line | `ContentUnavailableView` | custom column composable |

## 8. Screen specs
Each screen: **one focus, one primary action.**
- **Dashboard:** brand header → next-prayer hero (countdown ring) → prayer strip →
  reminder card → verse of the day → qibla (tappable) → quick actions → continue
  reading. Scroll. Primary: next prayer.
- **Quran Reader:** search + surah/juz + display toolbar; `Lazy` verse list
  (continuous) or paged; per-verse play/bookmark/copy/share; bottom playback bar;
  attribution footer. Primary: read/scroll.
- **Practice Recitation:** compact selection header (surah · ayah · script) →
  ayah word chips (karaoke head, redaction in memorize mode) → optional per-letter
  tajweed (in a disclosure) → live transcript → `RecordingControlBar`. Primary:
  Listen.
- **Live Translation:** transcript list (source Arabic + translated) with auto
  scroll and model-download notice → `RecordingControlBar` with language picker +
  save/clear. Primary: Record.
- **Tasbih:** dhikr picker → dhikr (Arabic + translit + meaning) → big tap counter
  ring → round/target → presets + reset. Primary: tap to count. Haptics on tick
  and round completion.
- **More:** grouped list of Worship (Tasbih, 99 Names, Duas) + Library (Khutba).

## 9. Accessibility (floor, both platforms)
Dynamic Type / font-scale incl. Arabic; screen reader labels in the content
language; AA contrast; status by **color + icon**; combine related elements into
one spoken unit; live regions for "Translating…"/listening state.

## 10. Android (Jetpack Compose) parity guide
- **Theme:** custom `lightColorScheme`/`darkColorScheme` from §2; `Typography`
  from §3; shapes 16/10 dp. **No dynamic color.** Provide a `Siraat` theme
  wrapper analogous to the iOS token enums; expose tokens via a `CompositionLocal`
  so screens never hardcode.
- **RTL/Arabic:** `CompositionLocalProvider(LocalLayoutDirection provides Rtl)`
  around Arabic; bundle the Uthmani font in `res/font`; apply a locale span for
  shaping + TalkBack voice; size in `sp`.
- **Lists:** `LazyColumn` with stable `key`s (parity with iOS `LazyVStack` +
  `EquatableView`); hoist row state.
- **Haptics/audio:** `HapticFeedback` for tasbih; `AudioRecord` (16 kHz mono PCM)
  to feed the on-device recitation engine — matches the iOS `AVAudioEngine` tap.
- **On-device ML:** iOS uses Core ML (`Wav2Vec2QuranPhonetics.mlmodelc`). Android
  has no Core ML; options, in order of preference: (a) reuse the model via
  TFLite/ONNX Runtime Mobile on-device; (b) call the shared Python
  `tajweed_engine` over a local/remote WebSocket. Keep the *blueprint schema*
  (`app/blueprint.py` ⇄ `PhoneticBlueprint.swift`) identical so both clients grade
  Madd/Ghunnah/Qalqalah against the same verified answer key.
- **Navigation:** bottom navigation (Dashboard, Quran, Recitation/Translation,
  More) mirroring the iOS tabs; per-screen top app bar titles per §8.

## 11. Definition of done (per screen, per platform)
Tokens only (no literals) · one clear primary action · Arabic shaped + scaled +
RTL + language-tagged · empty/loading/error states · AA + color-symbol status ·
screen-reader labels in-language · matches the opposite platform's layout intent.
