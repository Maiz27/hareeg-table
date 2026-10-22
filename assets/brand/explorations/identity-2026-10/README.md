# Identity exploration — October 2026

Two shortlisted logo directions for Hareeg Table, built with the logo-design
skill's process (brief → clichés → concepts → black-first SVG → tests → kit).
Nothing here is wired into the app yet; the launcher, splash, web manifest and
store art still use the Sandline joker. Untracked until a direction is chosen.

## Start here

- `concepts-round-1.png` — the checkpoint sheet (A, B and the dropped C).
- `board/board.html` (slides also in `board/slides/*.png`) — the presentation:
  brief, each direction with rationale and six mockups, side by side,
  recommendation.
- `preview.html` — the test sheet: size ladder, 16/32 px, one-colour,
  reversed, blur, mirror, contexts, shelf test against reference marks.
- `GUIDELINES.md` — palette, clear space, minimum sizes, type, don'ts.

## Files per direction (`a-lit-card/`, `b-fifty/`)

| File | What |
|---|---|
| `*-symbol.svg` | Master symbol, black, 256 canvas, paths only |
| `*-symbol-color.svg` | Two-colour symbol on the charcoal tile (launcher source) |
| `*-symbol-ember.svg` | One-colour ember |
| `lit-card-symbol-small.svg` | A only: small-size cut without the pip (favicon source) |
| `*-wordmark-latin.svg`, `*-wordmark-arabic.svg` | Outlined wordmarks |
| `*-horizontal.svg`, `*-horizontal-arabic.svg`, `*-stacked.svg` | Lockups |
| `dist/` | Black / white / ember variants with PNGs, square avatar, favicon.svg + .ico, app-icon, PWA icon set, `site.webmanifest`, `head-snippet.html` |

## Rebuilding

`make_kit.py` regenerates every master SVG from the geometry and the bundled
fonts. It needs `fonttools` and `uharfbuzz` (for Arabic shaping and kerning);
run it from a venv with both installed. The variants, test sheet and board
come from the skill's scripts (`export_variants.py`, `preview_sheet.py`,
`presentation_board.py`) with `presentation-spec.json`.

## Open items

- Latin wordmark is stock Reem Kufi 600; a custom pass on "g" and "ee" is
  owed before it is final. Arabic wordmark is shaped Reem Kufi, outlined.
- No trademark clearance has been done; run a search before launch.
- B reads as a drop to non-Arabic readers in one colour; colour fixes it.
- Chosen direction still has to be cut into the Android adaptive launcher
  (foreground/background/monochrome), the splash, the web icons and the Play
  listing art, replacing the Sandline joker set.
