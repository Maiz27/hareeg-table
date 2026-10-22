# Design Contract

## Status

Accepted and shipped (see section 13). The contract describes what the app
ships (mostly in `lib/ui/core/theme/lounge_tokens.dart` and
`lib/ui/core/theme/app_theme.dart`) and is binding for new UI work. Lines
marked **Rule** are constraints on future work rather than descriptions.

`direction.md` stays the short brand brief (mood, palette, icon). This file is
the working contract: what tokens exist, how each layer of the UI is built, and
what a screen must satisfy before it ships. The card art contract stays in
[ADR 0002](../adr/0002-card-theme-contract.md).

## 1. Principles

1. **The table is the hero.** Every other screen exists to get the player to
   the table, back from it, or to understand what happened on it.
2. **The table should feel like a real place.** Cards sit on a surface with a
   rim, light and depth. Seats belong to people. Flat cards on a flat colour
   field is not acceptable as a finished table.
3. **Colour means state.** Each state colour has exactly one meaning (section
   3.3). Decoration never borrows a state colour.
4. **Calm by default, heat on purpose.** The resting table is quiet and warm.
   Flame, glow and motion get louder only for turn changes, Fifty, danger and
   match outcomes.
5. **Readability beats spectacle.** Cards stay legible on a small Android phone
   in landscape. Depth effects never tilt, blur or shrink the player's hand.
6. **One product, not a Material template.** No screen ships with stock
   Material defaults (default font, default app bar, bare outlined-button
   stacks) where a contract component exists.
7. **Offline-first assets.** Fonts, textures and sounds are bundled. Nothing in
   the UI is fetched at runtime.

## 2. Token rules

- **Colours are roles, not hues.** A widget asks for `accent`, `surface` or
  `stateSelected`, never for "ember" or "sand". Role names say what a colour
  is for; the hue behind a role can change without touching a call site.
- **Two files, two jobs.** `lib/ui/core/theme/brand_palette.dart`
  (`BrandPalette`) holds the raw hues, named by what they are (`ember`,
  `charcoal`, `sand`, `felt` …). It is the only file that holds a brand hex
  value. `lib/ui/core/theme/lounge_tokens.dart` (`LoungeTokens`) maps each role
  onto a palette hue, plus the few translucent role values (glows, scrim,
  `lineSoft`) that have no palette entry of their own.
- **`BrandPalette` is private to the theme layer.** Nothing outside
  `lib/ui/core/theme/` references it: feature code, shared widgets and
  `lib/app/` paint with `LoungeTokens` roles only. A widget that reached for a
  hue by name would keep the wrong colour after a palette change.
- Feature code uses tokens from `LoungeTokens` (or a successor
  `lib/ui/core/theme` file). Raw `Color(0x...)`, raw font sizes and raw
  `Duration(milliseconds: …)` in `lib/ui/features/**` are contract violations
  unless commented with the reason.
- **Adding a role:** add it to `LoungeTokens` pointing at an existing palette
  hue, with a doc comment saying what it is for, and add it to section 3 of
  this file in the same change. Add a hue to `BrandPalette` only when no
  existing hue fits, and say which role needs it. Never add a role named after
  a hue.
- **Changing a hue:** edit its value in `BrandPalette`; every role that points
  at it follows. To move one role to a different hue, re-point that role in
  `LoungeTokens` (one line). Either change updates the hex column in section
  3.1 in the same change.
- The hue-named tokens from the Sandline Lounge era (`feltGreen`,
  `coffeeCharcoal`, `cardIvory`, `sandLine`, `goldAccent`, `fiftyFlame`,
  `deepRed`, `indigoAccent`, `offWhiteText`, `mutedText`, `feltRaised`,
  `feltSpotlight`, `overlayScrim`, `selectedGlow`, `pendingDiscard`,
  `invalidAction`, `surfaceL2`, `edgeL2`) are retired. They survive only as
  `@Deprecated` aliases while call sites move to roles, and are removed once
  nothing references them. New code never uses them. An alias points at the
  closest role, which is not always the right one: a menu background is
  `surface`, not `tableFelt`; a selected card is `stateSelected`, not
  `accent`. Each call site picks its role during migration.
- Table surface themes (`TableSurfaceTheme`) and card themes may restyle
  surfaces, but they must not redefine state colours (section 3.3).

## 3. Colour

### 3.1 Colour roles — Current

The identity is the **Lit card** (`direction.md`): charcoal ground, ember
accent, sand hairlines, ivory paper. Felt green is the playing surface and
nothing else. Hex values come from `BrandPalette`; the table lists them so a
reader does not have to open the code, and section 2 says how to change one.

| Group | Role (`LoungeTokens`) | Palette hue | Hex | Use |
| --- | --- | --- | --- | --- |
| Surfaces | `surface` | `charcoal` | `#15110E` | The ground: scaffold, menus, screen headers, the splash |
| | `surfaceRaised` | `charcoalRaised` | `#221B16` | One step up: raised chips, banners, inset panels on `surface` |
| | `surfaceSpotlight` | `charcoalSpotlight` | `#2C231C` | Two steps up: the pool behind cards and lit medallions on `surface` |
| | `surfaceInset` | `charcoalDeep` | `#0E0B09` | Sunk one step: recessed fills, progress tracks, inset trays |
| | `panel` | `charcoalRaised` | `#221B16` | L3 fill: sheets, pause, score, the coach card |
| | `panelTranslucent` | (role value) | `#15110E` @ 88% | L2 fill, slightly translucent over the table |
| | `scrim` | (role value) | `#0B0A08` @ 80% | Behind sheets and overlays above the table |
| | `paper` | `ivory` | `#F8F0DD` | Paper panels, the light brand pairing |
| Table | `tableFelt` | `felt` | `#12382F` | The playing surface |
| | `tableFeltRaised` | `feltRaised` | `#184235` | Meld lanes, inset panels on the table |
| | `tableFeltSpotlight` | `feltSpotlight` | `#1B4A3C` | The lighter pool behind on-table cards |
| | `cardFace` | `ivory` | `#F8F0DD` | Default card face base |
| Accent | `accent` | `ember` | `#E4522B` | Primary action: filled buttons, active controls, progress, medallion rings, the lamp |
| | `accentPressed` | `emberDeep` | `#C8401F` | `accent` pressed or deepened; the dark end of a lit gradient |
| | `accentBright` | `emberBright` | `#F07A52` | `accent` caught by the light; the bright end of a lit gradient |
| | `onAccent` | `charcoal` | `#15110E` | Text and icons on `accent` |
| | `accentGlow` | (role value) | `#E4522B` @ 40% | Outer glow for accent rings and lit medallions |
| Lines and text | `line` | `sand` | `#D7BD83` | Hairlines, motif strokes, secondary borders, overlines |
| | `lineSoft` | (role value) | `#D7BD83` @ 25% | Hairline edge for L2 surfaces |
| | `textPrimary` | `offWhite` | `#F5EFE3` | Primary text on dark surfaces |
| | `textMuted` | `stone` | `#B8AA91` | Secondary text on dark surfaces |
| | `textOnPaper` | `charcoal` | `#15110E` | Text on `paper` and `cardFace` |
| Signals | `danger` | `crimson` | `#A92E24` | Warnings, elimination, illegal-action copy |
| | `suitRed` | `crimson` | `#A92E24` | Hearts and diamonds on the default card faces |
| | `seatCool` | `indigo` | `#23395B` | Opponent badges, inactive seats, the west seat |
| | `seatEast` | `slate` | `#2F5F6D` | The east seat's identity, a second cool told apart from `seatCool` |
| | `fiftyHeatCore` | `flameCore` | `#FFE3A0` | The white-hot core of the Fifty flame: stamp edge, first shockwave ring, fresh embers |
| | `celebrationCool` | `lagoon` | `#5FA8D3` | A decorative cool spark in celebrations only; never a state |
| High contrast | `highContrastSelected` (+`Glow`), `highContrastPending` (+`Glow`, `Tint`), `highContrastCover` (+`Glow`, `Tint`), `highContrastCoach` (+`Glow`), `highContrastInvalid` | `signalYellow`, `signalOrange`, `signalCyan`, `signalMint`, `signalRed` | `#FFD400`, `#FF6F00`, `#00D9FF`, `#36F0DC`, `#FF2F2F` | Overlay-only replacements for the states (and the panel edge) when the high-contrast cues setting is on; saturated by design |
| States | see section 3.3 | | | Reserved meanings |

"(role value)" marks a translucent value defined in `LoungeTokens` itself; its
base hue is the palette hue named in the hex column.

### 3.2 Surface tones and elevation

Menus, headers, panels and the splash sit on charcoal. Felt appears only on
the playing table (and the table's own surface theme, `TableSurfaceTheme`);
a menu that needs depth lifts to `surfaceRaised` or `surfaceSpotlight`, never
to felt.

| Level | Use | Fill | Edge | Shadow |
| --- | --- | --- | --- | --- |
| L0 Surface | Menu and screen background; table surface | `surface` (menus) / `tableFelt` or surface theme (table) | — | — |
| L1 On-table | Cards, meld lanes, stock, discard | `cardFace` / `tableFeltSpotlight`, `tableFeltRaised` | theme border | `0 2 4 / 35%` + `0 6 14 / 20%` |
| L1 On-menu | Raised chips, banners, inset panels, card pools on menus | `surfaceRaised` / `surfaceSpotlight` | `lineSoft` | none, or L2 |
| L2 HUD | Seat plates, HUD chips, toasts | `panelTranslucent` | `lineSoft` | `0 4 12 / 35%` |
| L3 Panel | Sheets, pause, score, coach card | `panel` | `line` @ 40–45% | `0 12 32 / 45%` |
| L4 Modal | Blocking dialogs | L3 + `scrim` behind | as L3 | as L3 |

Shadow notation is `x y blur / alpha` in black. A widget picks a level, not an
ad-hoc shadow. L2 and L3 are `LoungeTokens.elevationL2` / `elevationL3`; L1
card shadows live with the card view, and L4 reuses L3 over the scrim. On
charcoal a shadow alone separates little, so L2 and L3 always carry their edge
hairline.

### 3.3 State colours — Current (reserved meanings)

| State | Token | Hue | Meaning | Where it appears |
| --- | --- | --- | --- | --- |
| Selection | `stateSelected`, `stateSelectedGlow` | sand | Player picked this | Hand cards, chosen controls |
| Cover target | `stateSelected` hover ring | sand | Legal drop zone | Meld lanes |
| Pending discard | `statePending` | amber | Will leave the hand on confirm | Hand card |
| Invalid | `stateInvalid` | rose | Rejected action | Ring/border flash |
| Fifty | `fiftyHeat` | ember | Fifty / Khamsin, high stakes | Fifty moments, danger scores |
| Active turn | Turn hue over the active seat's cards | — | Whose turn it is | Seat rails, hand |
| Eliminated | Dimmed seat plate (no dedicated token) | — | Seat out of the round | Seat overlay |
| Coach (keep) | `coachHighlight`, `coachHighlightB`, `coachHighlightC` (`coachRingPalette`) | teal, blue, violet | Coach-tier proactive hint, one hue per meld group | Coaching strictness only |
| Coach (let go) | `coachDiscard` | orchid rose | Coach-recommended discard | Coaching strictness only |

Selection is **quiet sand** so the flame stays reserved for fire: ember on the
table means Fifty and nothing else. `fiftyHeat` and the chrome `accent` share
the ember hue on purpose (it is the brand flame), but they are separate roles.
Chrome uses `accent`; nothing on the playing surface uses `accent` to mark a
card, a lane or a seat state.

The coach family is **deliberately cool** so a coached card can never be
mistaken for selection (sand), pending (amber), invalid (rose) or Fifty
(ember). This is an intentional exception to the warm palette, and it holds
only inside coaching UI. The one warm coach hue, orchid "let go", sits apart
from rose by hue and only ever appears alongside the cool "keep" rings of the
same hint. No other feature may use these hues.

### 3.4 Contrast

- Body text ≥ 4.5:1 against its surface; large text and icons ≥ 3:1.
- `textMuted` on `surfaceSpotlight` (the lightest charcoal step, about 6.7:1)
  is the floor for secondary copy on menus and panels; never put secondary
  copy on a lighter fill.
- On the table the floor is `textMuted` on `tableFelt` (about 5.6:1). The
  felt spotlight pool is lighter: `textMuted` on `tableFeltSpotlight` is about
  4.4:1, below the body floor, so secondary copy there uses `textPrimary` or
  sits on an L2 plate.
- `onAccent` (charcoal, about 5:1) is the only label colour on an `accent`
  fill; off-white on ember (about 3.3:1) falls below the body-text floor.
- Text on `paper` and `cardFace` uses `textOnPaper`.
- The existing **High-contrast cues** setting strengthens state rings and pop-up
  surfaces; every new state ring must define its high-contrast variant.

## 4. Typography

Two bundled families, both with Latin **and** Arabic coverage:

| Role | Family | Why |
| --- | --- | --- |
| Display (wordmark, screen titles, big scores, Fifty) | **Reem Kufi** (OFL) | Geometric Kufic. Matches the geometric motif; bilingual. |
| UI / body | **IBM Plex Sans Arabic** (OFL) | Neutral, very legible at small sizes, Latin + Arabic. |

Fonts are bundled under `assets/fonts/` with their OFL notices beside them
(`OFL-ReemKufi.txt`, `OFL-IBMPlexSansArabic.txt`) and attributed on the
licences screen. No `google_fonts` runtime fetching.

Type scale (logical px, line-height in brackets):

| Token | Size / weight | Family | Use |
| --- | --- | --- | --- |
| `displayLarge` | 40 / 700 [1.1] | Display | Home wordmark, match result |
| `display` | 28 / 700 [1.15] | Display | Screen titles |
| `heading` | 18 / 700 [1.25] | UI | Section headings, panel titles |
| `title` | 15 / 600 [1.3] | UI | List rows, seat names, button labels |
| `titleSmall` | 13 / 700 [1.3], +0.6 tracking | UI | Chips, overlines (uppercase allowed only here) |
| `body` | 14 / 400 [1.45] | UI | Copy |
| `bodyMuted` | 13 / 400 [1.45] | UI | Secondary copy |
| `numericChip`, `numericDisplay` | 14–32 / 700, tabular figures | UI | Scores, counts, open-need |

Scores and counts always use tabular figures so numbers don't jitter as they
change.

## 5. Spacing, radius, touch targets

- Spacing: 4 dp base, `space1`–`space8` (4, 8, 12, 16, 20, 24, 32).
- Radius: `radiusCard` 10, `radiusButton` 12, `radiusPanel` 18, `radiusPill`
  999 for HUD chips and seat plates.
- Touch targets: primary 48, hand card short edge 44, compact cover 36,
  overlay 40. These are floors, not suggestions.

## 6. Motion

`MotionSpeed` multiplies durations (normal 1.0, fast 0.6, reduced 0.35 with
linear curves, OS reduce-motion honoured). Durations equal to a token use it;
the remaining literals are capped by the token ratchet (section 12).

### Duration tokens

| Token | Normal | Use |
| --- | --- | --- |
| `motionInstant` | 120 ms | Press feedback, ring flash in |
| `motionQuick` | 180 ms | Card lift, chip/state changes |
| `motionStandard` | 220 ms | Panels, toasts, seat plate state |
| `motionEmphasis` | 280 ms | Turn change, coach card in/out |
| Card flights | `TableMotion` in `motion_speed.dart` | Card flight (draw, discard, meld placement) and the opening deal keep their own tuned durations |
| Celebrations | Each effect's own `duration` in `celebration.dart` | Win fireworks 3400 ms, Fifty strike 1500 ms, table shake 560 ms (section 6.1) |

Curves: `easeOutCubic` for things arriving, `easeInCubic` for leaving,
`easeInOutCubic` for things moving across the table. Reduced motion uses linear
curves, keeps flights but shortens them, and drops idle pulses and celebration
particles entirely.

### 6.1 Celebration and impact — Current

Two moments are allowed to be loud (principle 4), both one-shot and
pointer-transparent (`lib/ui/core/motion/celebration.dart`):

- **Match won:** fireworks and confetti over the match-over standings —
  nine bursts and drifting confetti in the brand palette (ember, ivory,
  crimson), about three
  seconds, then silence. Only when the player wins.
- **Fifty strike:** on any seat's Fifty claim and on a round won on a Fifty —
  a flame flash, two shockwaves from the table's centre, a *50* slammed down
  in the display face, embers, and a short shake of the whole table.

Under reduced motion the fireworks and shake are skipped and the strike is a
brief glow.

## 7. The table

### 7.1 Layout contract (landscape)

```
┌──────────────────────────────────────────────────────────┐
│ [HUD tl]           [ North seat plate + rail ]   [HUD tr]│
│                                                          │
│ [West]        N meld lane                       [East]   │
│ [plate]   W lane   [ stock | discard ]   E lane  [plate] │
│ [rail ]       S meld lane                       [rail ]  │
│                                                          │
│ [stock]           [  player hand (fan)  ]   [open need]  │
└──────────────────────────────────────────────────────────┘
```

- Four seats: North, West, East (CPU) and South (player), anti-clockwise turns.
- **Reserved zones:** seat plates and their rails are never covered by
  banners, coach cards or toasts. Transient UI uses the free band between the
  north rail and the centre, or anchors beside the hand.
- HUD corners hold at most one control each (stats, pause) plus the open-need
  chip by the hand.
- The replay screen is this same table with replay chrome (section 7.6); it
  keeps the same reserved zones.

### 7.2 Seat plate

Every CPU seat gets an L2 plate attached to its rail:

- Name / persona, CPU level badge (`seatCool`).
- Card count (tabular numeric), opened yes/no, running score.
- **Active turn:** keeps the existing turn hue over the seat's cards and adds an
  `accent` plate edge with a `motionEmphasis` glow-in.
- **Thinking:** a quiet three-dot or `line` (sand) sweep, no spinner.
- **Eliminated:** plate and rail dimmed, score struck through.
- **Fifty pressure:** plate edge shifts toward `fiftyHeat` when that seat is
  in Fifty danger.

The player (South) gets the same data in a compact strip by the hand.

### 7.3 Depth: the 2.5D table — Current

The table reads as an object seen from the player's chair, built only with
standard Flutter so web and low-end Android keep working:

- **Everything sits on the table.** The live table lays out the playfield,
  HUD, coach and card flights inside the rail (`TableBackground.insetChild`),
  in one coordinate space, so flights still land on their slots. Nothing runs
  under the rail.
- **Foreshortened rail:** thin on the far (top) side, deep on the near
  (bottom) side (`TableBackground.railInsets`), lit from above, with the far
  rail's inner wall visible and a brass inlay at the seam.
- **Surface in perspective:** only the surface layer (texture, medallion,
  lamp light) is tilted back with a `Matrix4` perspective, so the medallion
  foreshortens into an ellipse. Interactive widgets are never transformed:
  their geometry is shared with `table_flight_geometry.dart`.
- **Lamp:** a warm pool of light over the centre, falling off to the edges.
- **Card depth:** every card casts a two-layer contact shadow, so fanned
  hands, piles and melds read as stacked physical cards. Selected cards lift.
- **The pot:** the stock sits at the centre beside the discard
  (`resolveStockPileRect`, shared by playfield and flights). The replay
  surface uses the same centred stock (section 7.6).
- **Hand:** a flat row. An arc was considered and left out: drag reorder and
  the 44 dp card tap target rely on the row's straight slots.

### 7.4 Coach UI

The coach (Coaching strictness, opted into from setup) renders as an L3 **coach
card** docked in the top-start corner (the HUD capsule owns the other), clear of
the west seat plate, sized to stop short of the north seat (rail centred,
plate on its far side). Up to four body lines. Tables too narrow to dock it
(the sandbox panel, small phones) fall back to the full-width strip. The
coach hue family is used for its accent only.

### 7.5 Score book — Current

The score sheet is kept the way the table keeps score on paper: players as
columns, rounds as rows. Each cell is the seat's running total with the
round's change beneath it (true minus sign for a drop); a total at or past
the elimination score is struck through in red. The round in play is the last,
lit row, labelled *Now*; the page scrolls from the bottom so the latest rounds
are always in view. Column heads are seat medallions whose ring warms toward
flame with the seat's total, `accent` on the seat to play. Earlier rounds are
recovered from the match transcript (`ScoreBookReader`), reconstructed in
small steps while the sheet opens, so it works after a resume too.

The pause panel keeps only the at-a-glance standings; the round-result panel
shows just the round that ended. The book is the one place the whole match
history lives.

### 7.6 Replay review — Current

The replay is the live table plus replay chrome; the live table is the base.

- **Table:** the live playfield exactly — inset inside the rail
  (`TableBackground.insetChild`), the stock at the centre, seat plates with the
  scores in force at the reviewed position. Passive: nothing on it is playable.
- **HUD capsule (top-end):** the live table's capsule
  (`table_hud_capsule.dart`, shared, not copied) with the replay's segments in
  reading order: **Analysis** (a switch, lit `accent` when on) | **Branch** (play
  on from here; refused frames say why in its label) | **Exit**. Segments are
  floored at 44 dp, as in the sandbox.
- **Replay card (top-start):** an L3 lounge card docked where the coach card
  docks (`CoachOverlay.dockedStartFor` / `dockedTopFor`, never inside the west
  column, stopping short of the north seat). It holds, top to bottom: the
  position overline (*Round 1 · 31 of 568*), the event line, the timeline
  scrubber and **one row** of the six transport controls — start, previous
  round, step back, step forward, next round, end. The step pair is the
  emphasised `accent` pair; round and end jumps are quiet outlines. Every control
  is a 44 dp target. The timeline (row, glyphs and scrubber) runs left to
  right in both languages.
- **Analysis** opens as a section inside the same card, under the transport,
  so opening it never moves a control. It is sticky: stepping updates it in
  place; only the capsule switch closes it.
- **Room:** the card never covers a seat plate, a rail, the hand or the
  capsule. At rest it also keeps off the pot wherever the table leaves room;
  an opened analysis section may reach over the pot and the meld lanes, down
  to the hand. Out of room, the card trims in order — the event line's second
  line (only to keep an opened section), then the analysis section, then the
  event line — and never gives up the position, scrubber or transport.
- **Band fallback:** where six 44 dp targets do not fit between the west
  column and the north seat (640x360, 915x412 and other compact or crowded
  landscapes), the same card sits in the free band between the north rail and
  the pot, still start-docked, with the position and scrubber between the two
  halves of the transport row and the event line under it.
- **Portrait:** the same table on top, the same card docked full width below
  it, and the capsule in a slim header over the table's top-end corner (on a
  table that narrow the north plate fills the corner).
- Loading, error, branch entry and sandbox exit keep their lounge panels.

## 8. Components

| Component | Status | Contract |
| --- | --- | --- |
| Primary button | Current (`FilledButton` theme) | `accent` (ember) fill, `onAccent` (charcoal) label, 48 dp, one per view region |
| Secondary button | Current (`OutlinedButton`) | `line` (sand) outline. **Rule:** max two stacked; beyond that use a section or list |
| Text button | Current | `accent` label, for tertiary actions |
| Segmented control | Current (setup) | `accent` selected segment, shown inside an option card with a one-line explanation |
| Option card | Current | L2 card: icon, title, value summary, chevron/edit; replaces bare segmented rows |
| Lounge panel | Current (`LoungePanel`) | L3 modal surface with medallion; the only modal shell |
| Lounge toast | Current (`LoungeToast`) | L2 transient message; never over a seat zone |
| HUD capsule | Current | One lacquered pill in the top-end corner holding every table control (scores, fast-forward, sandbox exit, pause; replay: analysis, branch, exit), segments split by hairlines; sandbox and replay floor segments at 44 dp |
| HUD chip | Current | Open-need chip: lacquered, brass edge, overline caption over a tabular number |
| Score medallion | Current | Score ringed by an arc that fills and warms toward elimination; shared by seat plates, the score sheet and the pause standings |
| Seat plate | Current | Section 7.2 |
| Coach card | Current | Section 7.4 |
| Replay card | Current | Section 7.6: position, event line, scrubber, one transport row, collapsible analysis |
| Screen header | Current | Replaces the stock black `AppBar`: transparent over the charcoal `surface`, display-face title, back as an icon button |
| List row | Current | History/report rows: title, meta line, trailing result badge; 56 dp min |
| Stat tile | Current | Big tabular number + label + optional trend; used by Stats and match reports |

## 9. Screens and navigation

### 9.1 Inventory

Splash, Onboarding, Home, New game setup, Game table, Rules help, Guided
practice (checklist, reading panel, strictness explainer), Match history,
Match statistics, Match replay, Branch sandbox, Settings (incl. card theme
preview, licences).

### 9.2 Home — information architecture

1. **Hero:** wordmark, card fan, then **one** primary action that adapts:
   `Continue` when a saved match exists (with a one-line match summary),
   otherwise `New game`. The other appears as a secondary action.
2. **Learn:** Guided practice, Rules. Cards or rows, not full-width buttons.
3. **Your table:** History, Stats, replays (and sandbox entry points from
   history). Shows recent results when there are any.
4. Settings in the header.

The rule: a new feature adds a row to a section, never another full-width
button to the home stack.

### 9.3 Setup

Option cards (section 8) grouped as *Opponents* (difficulty, starter),
*Rules* (strictness, opening, jokers, house rules). The strictness card shows
its explanation inline. `Start table` stays pinned at the bottom.

### 9.4 Orientation

Portrait for menus, setup, help, history, stats and settings; landscape for
table, replay and sandbox. Size classes for the table:

| Class | Landscape height | Treatment |
| --- | --- | --- |
| Compact | < 400 dp | Thinner rail, compact rails and plates, full-width coach fallback |
| Regular | 400–700 dp | Full rim, seat plates, docked coach card |
| Expanded (tablet / web desktop) | > 700 dp | Table max width with rim; HUD stays at table corners, not screen corners |

## 10. Accessibility and localization

- Touch targets per section 5; semantics labels on every seat plate, chip and
  card (existing pattern).
- State is never colour-only: every state ring also changes shape, weight or
  position (lift, border width, icon).
- Reduced motion and high-contrast settings apply to every new component.
- RTL: menus mirror under Arabic. The **table does not mirror**: seats are
  game-space positions and stay N/W/E/S.

## 11. Cultural motif

The geometric medallion and sand-line patterns appear at the edges: menu
corners, table rim, panel medallions, card backs. Never behind text, never
inside the play area beyond the faint centre medallion, never animated at
rest.

## 12. Enforcement

- **Token ratchet** (`test/lint/design_token_ratchet_test.dart`): pins the
  count of raw `Color(0x…)` and `Duration(milliseconds: …)` literals under
  `lib/ui/` (every occurrence; the token file is excluded) as a ceiling.
  Counts may fall, never rise; lower the ceiling in the same change that
  removes literals. The theme layer (`lib/ui/core/theme/`) is excluded: hex
  values belong there.
- **Palette privacy** (same test): any reference to `BrandPalette` outside
  `lib/ui/core/theme/` (under `lib/ui/` or `lib/app/`) fails. Feature code
  paints with `LoungeTokens` roles (section 2).
- **Retired names:** the Sandline Lounge hue-named tokens listed in section 2
  are `@Deprecated`, so the analyzer reports every use with the role to move
  to. New code must not add a use; migrations replace them by role, and the
  aliases are deleted once nothing references them.
- **Goldens:** deliberately not pixel goldens. Rasterised text and blur
  differ across Flutter versions and machines, so pixel goldens would fail on
  unrelated toolchain upgrades. Layout is guarded instead by geometry tests
  on the rendered tree (coach docking; `replay_layout_test`: the replay table
  matches the live one rect for rect, and the replay card clears every seat,
  rail, the hand and the capsule at every contracted size).
- PR checklist: a UI change names the contract sections it touches.

## 13. Rollout plan

1. **Foundation** — done: bundled fonts, typography / elevation / motion
   tokens in `AppTheme`, screen headers on the menu ground (felt then,
   charcoal since step 8). Literal durations equal
   to a token now use it; the rest are held by the token ratchet.
2. **Table** — done: inset playing surface, foreshortened rail, perspective
   surface and lamp, card shadows, centred stock, seat plates, docked coach
   card, HUD capsule, open-need chip.
3. **Table panels** — done: score book (7.5), pause (inset settings tray,
   at-a-glance standings), round result (medallion header, display headline,
   delta chips), match-over (trophy medallion, display headline, win
   fireworks), Fifty strike (6.1).
4. **Menus** — done: home, setup, guided practice (progress ring, numbered
   lesson medallions), settings (section cards with icon medallions), history
   (placement medallions, accent-edged wins) and stats tiles. Rules help kept
   its layout under the new type and header (its cards came in step 6).
5. **Enforcement** — done: token ratchet (section 12).
6. **Menu gap pass** — done: the screens the menus pass missed now share its
   language. Onboarding moves onto the menu ground (charcoal since step 8)
   with lit medallion heroes, a lit
   card per page and numbered page medallions; the strictness explainer gets
   a lit intro under its checklist number and a medallion card per tier;
   rules help keeps its order but sets each part as a lounge card with a
   medallion heading (as licences); history and stats loading, empty and
   error states are lit cards with a state medallion; the splash wordmark is
   set in the display face over a lamp pool, timing unchanged.
7. **Replay** — done: the replay screen is the live table plus replay chrome
   (7.6). The full-bleed table with the corner stock, the 44 dp edge rails,
   the scrub target, the analysis popover and the frozen layout oracle that
   pinned them are retired.
8. **Identity** — done: the Sandline Lounge look (felt-green menus, gold
   accent) gives way to the Lit card identity. The theme layer is split into
   `BrandPalette` (raw hues, the only hex values) and `LoungeTokens` (roles);
   the role table is section 3.1. Menus, headers, panels and the splash move
   to charcoal; felt stays on the playing table only. The chrome accent
   (buttons, active controls, medallions, the lamp) is ember; selection moves
   from gold to quiet sand, pending stays amber, invalid is rose, and Fifty is
   the ember flame (3.3). The launcher, splash and web icons use the Lit card
   in its colour pairings (`assets/brand/README.md`). Spacing, radii,
   typography and motion are unchanged. The hue-named tokens remain as
   `@Deprecated` aliases until the remaining call sites move to roles
   (section 12).

## 14. Decisions taken

The owner handed the redesign over to be led without their input, so these
were decided rather than left open. Each is easy to revisit.

1. **Fonts:** Reem Kufi (display) + IBM Plex Sans Arabic (UI). Numerals use
   Plex with tabular figures: Reem Kufi's round zero reads as the letter O.
2. **Seat identity:** the existing `CPU North / West / East` labels stay (as
   tooltip and semantics). The plate itself shows the match score in a
   medallion with an elimination-danger arc, plus a hand-size pill. No
   invented personas.
3. **Perspective tilt:** dropped (section 7.3).
4. **Hand:** stays a flat row; selected cards already lift.
5. **Stock** moves to the centre beside the discard; **open-need** stays in
   the bottom-end corner, inside the rail.
6. **Player (South) plate:** not added. Both bottom corners share their edge
   columns with the side rails, and the hand hue already marks the player's
   turn; the player's score is one tap away in the score sheet.
7. **Replay transport:** one row of six 44 dp targets is 268 dp wide, wider
   than the coach card's dock on most phones. Where it fits beside the north
   seat (844x390, tablets) the card docks exactly as the coach card does;
   elsewhere it falls back to the band under the north rail (7.6) rather than
   shrinking a target, splitting the row or covering a seat.
8. **Replay capsule floor:** the replay capsule uses the sandbox's 44 dp
   floor rather than the live table's 30/38 dp phone sizes, since the touch
   target floor (section 5) is not traded away.
9. **Accent is ember.** The chrome accent (filled buttons, active controls,
   progress, medallion rings, the lamp) is the brand flame, `#E4522B`,
   replacing gold. One warm accent ties the app to its launcher icon.
10. **Selection is sand.** A picked card or chosen control rings in quiet
    sand, not the accent. With ember as the accent, an ember selection ring
    would read as Fifty; sand keeps the flame on the table reserved for Fifty
    and danger scores.
11. **Menus on charcoal.** Every screen that is not the table (home, setup,
    history, stats, settings, help, onboarding, the splash) sits on the
    charcoal `surface`, with depth from `surfaceRaised` and
    `surfaceSpotlight`.
12. **Felt is table-only.** Felt green is the playing surface, not a brand
    colour. Taking it off the menus makes the table the one green place in
    the app, so arriving at it reads as sitting down to play.
13. **Colour pairings, not one tile.** The mark appears in three pairings
    (`assets/brand/README.md`): the launcher, web icons and store art use an
    ember ground with an ivory card and charcoal flame; the splash and in-app
    surfaces use a charcoal ground with an ivory card and ember flame; light
    surfaces use ivory with a charcoal card and ember flame. The logo never
    sits directly on felt.
