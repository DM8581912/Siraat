# Siraat — Design System

Single source of truth: `Siraat/App/DesignSystem.swift`. Screen views consume these tokens;
they do not define colors, radii, spacing, or fonts locally. (Generated from the codebase;
keep in sync as the system evolves.)

## Color — `SiraatColor`
Strategy: **Restrained** — tinted neutrals carry the surface, a single teal-green accent does
the work, gold is a sparing secondary. Every token is OKLCH-spirit hand-tuned hex with adaptive
light/dark resolution (`Color(lightHex:darkHex:)`); no pure `#000`/`#fff`.

| Token | Light | Dark | Role |
|---|---|---|---|
| `background` | `#F7F5F0` warm off-white | `#0E1413` deep charcoal | app canvas |
| `secondaryBackground` | `#FFFFFF` | `#18211F` | cards / surfaces |
| `surfaceElevated` | `#FFFFFF` | `#1F2A27` | raised surface |
| `hairline` | `#E6E1D6` | `#2A3633` | 1px borders |
| `accent` | `#0C6B57` teal-green | `#4FC2A6` | primary action, highlight |
| `accentDeep` | `#094B3D` | `#2E8C76` | gradients, pressed |
| `gold` | `#8A6410` (AA-safe) | `#E0B65C` | sparing secondary / verse-of-day |
| `warning` / `destructive` | `#C2741E` / `#C53330` | `#E2944A` / `#E57470` | status |
| `textPrimary` / `textSecondary` | `#14201D` / `#5C6864` | `#F2F5F3` / `#9BA8A3` | text |

**Theme:** adaptive (system light/dark), user-overridable in Settings. Light is the default —
the scene is a reader holding a mushaf in daylight; dark is a quiet night reading. Both first-class.

## Typography — `SiraatType` + `ArabicText`
Latin text rides SwiftUI semantic styles (free Dynamic Type). Ramp: `display` (serif largeTitle
bold) → `title` → `heading` → `body` → `callout` → `caption` → `micro`. Weight + scale contrast
≥1.25 between rungs; never flat.

**Arabic** goes through `ArabicText` (a `@ScaledMetric` view): scales with Dynamic Type, tags the
run with `typesettingLanguage(ar)` for correct shaping + VoiceOver, and in `scripture: true` mode
uses the Uthmani face (`SiraatFont.quran`, registered at launch; graceful system fallback until
the font file is bundled — see `Resources/Fonts/README.md`). Arabic base sizes centralized in
`SiraatType.Arabic`.

## Radius — `SiraatRadius`
Two tiers only: `card = 16` (outer containers, heroes), `inner = 10` (rows, chips, banners).
Replaces prior 8/12/14/18/22 drift.

## Spacing — `SiraatSpacing`
`xxs 4 · xs 8 · sm 12 · md 16 · lg 20 · xl 24 · xxl 32`. Vary deliberately for rhythm; avoid
uniform padding. (Call-site convergence is in-progress — phase 2+ work.)

## Elevation
Flat + hairline, no heavy shadows. `Card` and `SectionBand` = `secondaryBackground` fill +
`hairline` stroke + `card` radius. One container language; nested cards are banned.

## Motion
Restrained, purposeful, ease-out (no bounce/elastic). Existing signatures: dashboard countdown
ring (`TimelineView` 1s tick), tasbih `numericText` count-up, qibla compass spring, gold-tint
highlight on the reciting ayah. Never animate layout properties decoratively.

## Components
`Card`, `SectionBand`, `ArabicText`, `WaveformView`, `FlowLayout` (RTL chip wrapping),
`ContentUnavailableView` for empty states. Status uses color **and** an SF Symbol (color-blind safe).

## Governance (sprint rule)
`DesignSystem.swift` is the only place tokens are defined. Screen agents request token changes
from the coordinator; they never add color/radius/spacing/font literals to a view.
