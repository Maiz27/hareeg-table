# Hareeg Table — Logo Guidelines (compact, two shortlisted directions)

Two directions are carried in this round, **A — Lit card** and **B — Fifty**.
Everything below applies to both unless a row says otherwise. Pick one as the
primary mark; the recommendation is A as the logo and B as the in-game Fifty
cue (strike overlay, timer ring).

## 1. The logo

- **A — Lit card.** The card itself is the fire: one silhouette, a flame for a
  top edge, a diamond pip cut from it. Files: `a-lit-card/lit-card-*`.
- **B — Fifty.** Arabic-Indic fifty, ٥٠, read right to left: a flame ring for
  the five, a spark for the zero. Files: `b-fifty/fifty-*`.
- **Versions** (each direction): horizontal (Latin) · horizontal (Arabic,
  symbol on the right) · stacked bilingual · symbol-only · wordmark-only
  (Latin and Arabic) · colour symbol on charcoal · ember one-colour · small-size
  cut (A only: the pip is dropped below 24 px).
- **Files**: `*.svg` are the masters (all paths, no live text, no strokes);
  `dist/` holds black, white, ember, square, favicon, app-icon and the web icon
  set; `board/` holds the presentation slides.

## 2. Clear space

Keep a clear zone of **1 × the pip height** (A) or **1 × the spark diameter**
(B) around the logo on all sides. The zone scales with the logo; never use a
fixed distance.

## 3. Minimum size

| Version | Screen | Print |
|---|---|---|
| Horizontal (Latin) | 140 px wide | 35 mm wide |
| Horizontal (Arabic) | 110 px wide | 28 mm wide |
| Stacked | 96 px wide | 24 mm wide |
| Symbol A | 24 px; below that use `lit-card-symbol-small` (no pip) | 8 mm |
| Symbol B | 16 px | 6 mm |

## 4. Colour

| Name | HEX | RGB | CMYK (approx.) | Pantone (approx.) | Use |
|---|---|---|---|---|---|
| Ember | #E4522B | 228 82 43 | 0 64 81 11 | 1665 C | Flame, key accent, one-colour logo |
| Charcoal | #15110E | 21 17 14 | 0 19 33 92 | Black 7 C | Ground, app-icon tile, type |
| Sand | #D7BD83 | 215 189 131 | 0 12 39 16 | 7502 C | Spark (B), lines, secondary accent |
| Ivory | #F8F0DD | 248 240 221 | 0 3 11 3 | 7499 C | Card (A), paper, light backgrounds |

Felt green (#12382F) stays the in-game table surface. It is not a brand colour
and the logo never sits on it without the charcoal tile.

**Approved logo/background pairs**: colour symbol on Charcoal · Ember on Ivory
· Charcoal on Ivory · white on Charcoal · black on white. On photos or busy
art, use the symbol in its charcoal tile.

Pantone and CMYK values are approximations; verify against a physical guide
before any print run.

## 5. Typography

- Wordmarks: Reem Kufi, weight 600, outlined (both scripts). The Latin is set
  with 1 % tracking; the Arabic is set 1/3 taller than the Latin cap height so
  the two carry equal weight.
- App display type: Reem Kufi (variable). UI type: IBM Plex Sans Arabic.
- Licences: both fonts ship in the app under the SIL Open Font License, which
  permits logo use. Outlines in the masters were generated from the bundled
  files, so the logo does not depend on an installed font.
- Open item: the Latin wordmark is still stock Reem Kufi. A custom pass on
  "g" and the "ee" pair is recommended before it is treated as final.

## 6. Don'ts

Don't stretch or squash · don't recolour outside the palette · don't rotate
the flame · don't add shadows, outlines, gradients, glows or bevels · don't
rearrange or resize the parts of a lockup · don't place on felt green or busy
art without the charcoal tile · don't recreate the wordmark by typing it ·
don't fan cards, add chips or coins around the mark.

## 7. Contact

Master files: `assets/brand/explorations/identity-2026-10/`. Generator:
`make_kit.py` (kept with the session notes; rebuilds every SVG from the
geometry and the bundled fonts).
