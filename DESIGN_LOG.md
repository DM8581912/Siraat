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
