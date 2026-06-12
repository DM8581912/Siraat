# Siraat Design Sprint — Log

Compounding record across sessions. Each phase appends; never rewrite history.

## VQS rubric (0–100 per screen)
Hierarchy 15 · Type system 15 · Color discipline 15 · Spacing rhythm 15 · Motion restraint 10
· RTL + Arabic 15 · Anti-slop 15. A change ships only if it holds or raises the score.

---

## Phase 1 — Baseline (2026-06-12)
BEFORE screenshots: `docs/design-sprint/before/{dashboard,reader,recitation,khutba}.png`
(real iPhone 16 simulator captures via CI, location-seeded so the dashboard populates).

### Scores (BEFORE)
| Screen | Hier | Type | Color | Space | Motion | RTL/Ar | Slop | **Total** |
|---|---|---|---|---|---|---|---|---|
| Dashboard | 11 | 9 | 9 | 11 | 8 | 9 | 8 | **65** |
| Khutba | 9 | 9 | 7 | 7 | 7 | 9 | 9 | **57** |
| Reader | 7 | 9 | 6 | 8 | 7 | 10 | 6 | **53** |
| Recitation | 8 | 7 | 6 | 6 | 7 | 9 | 7 | **50** |

Target after sprint: **≥ 80** every screen.

### Cross-cutting findings (hit every screen)
1. **CRITICAL — default iOS blue tint everywhere.** Controls (play/bookmark/share, pickers,
   trash, library, the selected tab) render in system blue, not `SiraatColor.accent`. The brand
   teal exists but is never set as the tint. One-line root fix (`.tint` at app/Nav root), huge
   visual lift. Biggest single "generic/unbranded" tell.
2. **Label clipping in tight control rows.** Recitation "Ayah 1" → vertical "A y a h 1";
   Khutba "English" → "Engl / ish". Real, visible.
3. **System serif Arabic, not Uthmani** (font asset not yet bundled — graceful fallback in play).

### Top 3 per screen
- **Dashboard (65):** (a) tint→teal incl. tab bar; (b) break card-stack monotony — give the hero
  more presence and the prayer strip a lighter treatment; (c) Uthmani verse-of-day + stronger
  section rhythm.
- **Reader (53):** (a) collapse toolbar soup into an "Aa" display sheet — show the ayah, not the
  chrome; (b) tint the icon row teal + quieter per-verse action affordances; (c) Uthmani scripture
  + remove the odd default gold highlight on verse 1.
- **Recitation (50):** (a) fix the clipped control row (stack Surah / Ayah+Script on two lines);
  (b) make follow-along chips feel alive, not disabled-grey; (c) tint + tighten the two-card stack.
- **Khutba (57):** (a) fix clipped language picker; (b) center/anchor the empty state, kill the
  dead vertical space; (c) tint trash/library; warm the record affordance.

### Status
Screenshot pipeline (Option A) proven: CI builds → tests → captures 4 PNGs → IPA, all green.
Phase 1 GATE reached.

---

## Phases 2–4 — Refine + Enhance (2026-06-12)
AFTER screenshots: `docs/design-sprint/after/{dashboard,reader,recitation,khutba}.png`
CI run 27418793722 (green): tests pass, screenshots captured, IPA built.

### Changes made (5 commits)
1. **Root tint fix** — `.tint(SiraatColor.accent)` at WindowGroup root. Killed default iOS blue
   across every screen: tab bar, pickers, steppers, buttons, toggles, toolbar icons.
2. **Clipped control rows** — Recitation: split HStack to VStack (Surah on own row, Ayah+Script
   on second). Khutba: `.fixedSize()` on language picker + globe icon label.
3. **Reader toolbar collapse** — Moved script/mode/font-size into an "Aa" display-settings sheet
   (`.presentationDetents([.medium])`). Reclaimed ~80pt vertical space. Quieter per-verse action
   icons (secondary tint, smaller font). Replaced gold playing-highlight with subtle accent tint.
4. **Dashboard rhythm** — Removed Card wrapper from prayer strip. Added section headers (VERSE OF
   THE DAY, QUICK ACTIONS) with tracked micro-caps. Applied SiraatType/SiraatSpacing tokens.
5. **Chips + empty state** — Recitation: pending chips use secondaryBackground + hairline border
   instead of `.primary.opacity(0.18)`. Khutba: vertically centered empty state with Spacer().

### Scores (AFTER)
| Screen | Hier | Type | Color | Space | Motion | RTL/Ar | Slop | **Total** | **Delta** |
|---|---|---|---|---|---|---|---|---|---|
| Dashboard | 13 | 12 | 14 | 12 | 8 | 9 | 11 | **79** | **+14** |
| Reader | 12 | 12 | 13 | 12 | 7 | 10 | 11 | **77** | **+24** |
| Khutba | 12 | 9 | 13 | 11 | 7 | 9 | 12 | **73** | **+16** |
| Recitation | 11 | 9 | 13 | 10 | 7 | 9 | 11 | **70** | **+20** |

### Before / After summary
| Screen | BEFORE | AFTER | Delta |
|---|---|---|---|
| Dashboard | 65 | 79 | +14 |
| Reader | 53 | 77 | +24 |
| Khutba | 57 | 73 | +16 |
| Recitation | 50 | 70 | +20 |

### What improved most
- **Color discipline** jumped +5–7 per screen from the root tint fix alone.
- **Reader hierarchy** gained +5 from toolbar collapse (3 visible ayahs vs 2).
- **Recitation spacing** gained +4 from the control row fix + chip refinement.
- **Khutba anti-slop** gained +3 from centered empty state + no dead space.

### What still blocks ≥80
- **Type system** (Reader/Recitation/Khutba 9): SectionBand, playback bar, and some views still
  use raw `.headline`/`.body` instead of `SiraatType` tokens. One more pass to converge.
- **Spacing rhythm** (Recitation 10): the two SectionBand cards still have uniform padding;
  varying inner-to-outer spacing would add rhythm.
- **Uthmani font** not yet bundled — Arabic renders in system serif. This caps RTL/Arabic at 9–10
  across all screens. Bundling a licensed Uthmani font would lift every screen +2–3.
- **Motion** capped at 7–8: no new motion was added (correctly restrained), but the recitation
  waveform and khutba waveform could use subtle entrance animation.

### Status
Phase 5 GATE reached. All four screens improved. None regressed. Target ≥80 not yet met — the
remaining gap is primarily Uthmani font bundling (RTL/Arabic +2–3 each) and one more token
convergence pass (Type +2–3 each). No reverts needed.
