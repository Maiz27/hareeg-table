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

- Feature code uses tokens from `LoungeTokens` (or a successor `lib/ui/core/theme`
  file). Raw `Color(0x...)`, raw font sizes and raw `Duration(milliseconds: …)`
  in `lib/ui/features/**` are contract violations unless commented with the
  reason.
- New tokens are added to code **and** to this file in the same change.
- Table surface themes (`TableSurfaceTheme`) and card themes may restyle
  surfaces, but they must not redefine state colours (section 3.3).

## 3. Colour

### 3.1 Brand palette — Current

| Token | Hex | Role |
| --- | --- | --- |
| `feltGreen` | `#12382F` | Primary table surface, menu backgrounds |
| `coffeeCharcoal` | `#15110E` | Chrome, panels, deep edges |
| `cardIvory` | `#F8F0DD` | Card face base |
| `sandLine` | `#D7BD83` | Hairlines, motif strokes, secondary borders |
| `goldAccent` | `#D69B35` | Primary action, selection, active control |
| `fiftyFlame` | `#EF5A24` | Fifty / Khamsin heat only |
| `deepRed` | `#A92E24` | Danger, hearts/diamonds |
| `indigoAccent` | `#23395B` | Opponent badges, inactive seats |
| `offWhiteText` | `#F5EFE3` | Primary text on dark |
| `mutedText` | `#B8AA91` | Secondary text on dark |

### 3.2 Surface tones and elevation

| Level | Use | Fill | Edge | Shadow |
| --- | --- | --- | --- | --- |
| L0 Surface | Table felt, menu background | `feltGreen` / surface theme | — | — |
| L1 On-table | Cards, meld lanes, stock, discard | card face / `feltSpotlight` | theme border | `0 2 4 / 35%` + `0 6 14 / 20%` |
| L2 HUD | Seat plates, HUD chips, toasts | `coffeeCharcoal` @ 88% | `sandLine` @ 25% | `0 4 12 / 35%` |
| L3 Panel | Sheets, pause, score, coach card | `coffeeCharcoal` | `sandLine` @ 40–45% | `0 12 32 / 45%` |
| L4 Modal | Blocking dialogs | L3 + `overlayScrim` behind | as L3 | as L3 |

Shadow notation is `x y blur / alpha` in black. A widget picks a level, not an
ad-hoc shadow. L2 and L3 are `LoungeTokens.elevationL2` / `elevationL3`; L1
card shadows live with the card view, and L4 reuses L3 over the scrim.

### 3.3 State colours — Current (reserved meanings)

| State | Token | Meaning | Where it appears |
| --- | --- | --- | --- |
| Selection | `goldAccent`, `selectedGlow` | Player picked this | Hand cards, chosen controls |
| Cover target | `goldAccent` hover ring (no dedicated token) | Legal drop zone | Meld lanes |
| Pending discard | `pendingDiscard` | Will leave the hand on confirm | Hand card |
| Invalid | `invalidAction` | Rejected action | Ring/border flash |
| Fifty | `fiftyFlame` | Fifty / Khamsin, high stakes | Fifty moments, danger scores |
| Active turn | Turn hue over the active seat's cards | Whose turn it is | Seat rails, hand |
| Eliminated | Dimmed seat plate (no dedicated token) | Seat out of the round | Seat overlay |
| Coach (keep) | `coachHighlight` teal, `coachHighlightB` blue, `coachHighlightC` violet | Coach-tier proactive hint, one hue per meld group | Coaching strictness only |
| Coach (let go) | `coachDiscard` rose | Coach-recommended discard | Coaching strictness only |

The coach family is **deliberately cool** so a coached card can never be
mistaken for selection (gold), pending (amber), invalid (red) or Fifty (flame).
This is an intentional exception to the warm palette, and it holds only inside
coaching UI. No other feature may use these hues.

### 3.4 Contrast

- Body text ≥ 4.5:1 against its surface; large text and icons ≥ 3:1.
- `mutedText` on `feltGreen` is the floor for secondary copy; never go lower.
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
  nine bursts and drifting confetti in the lounge palette, about three
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

- Name / persona, CPU level badge (`indigoAccent`).
- Card count (tabular numeric), opened yes/no, running score.
- **Active turn:** keeps the existing turn hue over the seat's cards and adds a
  `goldAccent` plate edge with a `motionEmphasis` glow-in.
- **Thinking:** a quiet three-dot or sand-line sweep, no spinner.
- **Eliminated:** plate and rail dimmed, score struck through.
- **Fifty pressure:** plate edge shifts toward `fiftyFlame` when that seat is
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

The coach (Coaching strictness, the setup default) renders as an L3 **coach
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
flame with the seat's total, gold on the seat to play. Earlier rounds are
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
  reading order: **Analysis** (a switch, lit gold when on) | **Branch** (play
  on from here; refused frames say why in its label) | **Exit**. Segments are
  floored at 44 dp, as in the sandbox.
- **Replay card (top-start):** an L3 lounge card docked where the coach card
  docks (`CoachOverlay.dockedStartFor` / `dockedTopFor`, never inside the west
  column, stopping short of the north seat). It holds, top to bottom: the
  position overline (*Round 1 · 31 of 568*), the event line, the timeline
  scrubber and **one row** of the six transport controls — start, previous
  round, step back, step forward, next round, end. The step pair is the
  emphasised gold pair; round and end jumps are quiet outlines. Every control
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
| Primary button | Current (`FilledButton` theme) | Gold fill, charcoal label, 48 dp, one per view region |
| Secondary button | Current (`OutlinedButton`) | Sand outline. **Rule:** max two stacked; beyond that use a section or list |
| Text button | Current | Gold label, for tertiary actions |
| Segmented control | Current (setup) | Gold selected segment, shown inside an option card with a one-line explanation |
| Option card | Current | L2 card: icon, title, value summary, chevron/edit; replaces bare segmented rows |
| Lounge panel | Current (`LoungePanel`) | L3 modal surface with medallion; the only modal shell |
| Lounge toast | Current (`LoungeToast`) | L2 transient message; never over a seat zone |
| HUD capsule | Current | One lacquered pill in the top-end corner holding every table control (scores, fast-forward, sandbox exit, pause; replay: analysis, branch, exit), segments split by hairlines; sandbox and replay floor segments at 44 dp |
| HUD chip | Current | Open-need chip: lacquered, brass edge, overline caption over a tabular number |
| Score medallion | Current | Score ringed by an arc that fills and warms toward elimination; shared by seat plates, the score sheet and the pause standings |
| Seat plate | Current | Section 7.2 |
| Coach card | Current | Section 7.4 |
| Replay card | Current | Section 7.6: position, event line, scrubber, one transport row, collapsible analysis |
| Screen header | Current | Replaces the stock black `AppBar`: transparent over the screen background, display-face title, back as an icon button |
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
  removes literals.
- **Goldens:** deliberately not pixel goldens. Rasterised text and blur
  differ across Flutter versions and machines, so pixel goldens would fail on
  unrelated toolchain upgrades. Layout is guarded instead by geometry tests
  on the rendered tree (coach docking; `replay_layout_test`: the replay table
  matches the live one rect for rect, and the replay card clears every seat,
  rail, the hand and the capsule at every contracted size).
- PR checklist: a UI change names the contract sections it touches.

## 13. Rollout plan

1. **Foundation** — done: bundled fonts, typography / elevation / motion
   tokens in `AppTheme`, screen headers on the felt. Literal durations equal
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
   (placement medallions, gold-edged wins) and stats tiles. Rules help kept
   its layout under the new type and header (its cards came in step 6).
5. **Enforcement** — done: token ratchet (section 12).
6. **Menu gap pass** — done: the screens the menus pass missed now share its
   language. Onboarding moves onto the felt with lit medallion heroes, a lit
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
