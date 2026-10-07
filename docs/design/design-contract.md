# Design Contract

## Status

Accepted and in rollout (see section 13). Sections marked **Current** codify what the app already
ships (mostly in `lib/ui/core/theme/lounge_tokens.dart` and
`lib/ui/core/theme/app_theme.dart`). Sections marked **Target** are the
redesign: they are binding for new UI work once accepted, and existing screens
migrate to them per the rollout plan at the end.

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

### 3.2 Surface tones and elevation — Current tokens, Target usage

| Level | Use | Fill | Edge | Shadow |
| --- | --- | --- | --- | --- |
| L0 Surface | Table felt, menu background | `feltGreen` / surface theme | — | — |
| L1 On-table | Cards, meld lanes, stock, discard | card face / `feltSpotlight` | theme border | `0 2 4 / 35%` + `0 6 14 / 20%` |
| L2 HUD | Seat plates, HUD chips, toasts | `coffeeCharcoal` @ 88% | `sandLine` @ 25% | `0 4 12 / 35%` |
| L3 Panel | Sheets, pause, score, coach card | `coffeeCharcoal` | `sandLine` @ 40–45% | `0 12 32 / 45%` |
| L4 Modal | Blocking dialogs | L3 + `overlayScrim` behind | as L3 | as L3 |

Shadow notation is `x y blur / alpha` in black. A widget picks a level, not an
ad-hoc shadow. **Target:** add `LoungeElevation.l1…l4` box-shadow tokens.

### 3.3 State colours — Current (reserved meanings)

| State | Token | Meaning | Where it appears |
| --- | --- | --- | --- |
| Selection | `goldAccent`, `selectedGlow` | Player picked this | Hand cards, chosen controls |
| Cover target | `coverTargetTint` | Legal drop zone | Meld lanes |
| Pending discard | `pendingDiscard` | Will leave the hand on confirm | Hand card |
| Invalid | `invalidAction` | Rejected action | Ring/border flash |
| Fifty | `fiftyFlame` | Fifty / Khamsin, high stakes | Fifty moments, danger scores |
| Active turn | Turn hue over the active seat's cards | Whose turn it is | Seat rails, hand |
| Eliminated | `eliminatedDim` | Seat out of the round | Seat overlay |
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

### Current

No `fontFamily` is set anywhere, so the app renders in the platform default
(Roboto on Android/web). Text styles exist as tokens (`display` 28/700,
`heading` 18/700, `titleSmall` 13/700, `body` 14, `bodyMuted` 13,
`numericChip` 14/700).

### Target

Two bundled families, both with Latin **and** Arabic coverage so the planned
Arabic localization needs no type redesign:

| Role | Family (proposed) | Why |
| --- | --- | --- |
| Display (wordmark, screen titles, big scores, Fifty) | **Reem Kufi** (OFL) | Geometric Kufic. Matches the geometric motif; bilingual. |
| UI / body | **IBM Plex Sans Arabic** (OFL) | Neutral, very legible at small sizes, Latin + Arabic. |

Fonts are bundled under `assets/fonts/` with their OFL notices in
`THIRD_PARTY.md`. No `google_fonts` runtime fetching.

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
| `numeric` | 14–32 / 700, tabular figures | Display or UI | Scores, counts, open-need |

Scores and counts always use tabular figures so numbers don't jitter as they
change.

## 5. Spacing, radius, touch targets — Current

- Spacing: 4 dp base, `space1`–`space8` (4, 8, 12, 16, 20, 24, 32).
  **Target:** add `space12` (48) and `space16` (64) for screen-level rhythm.
- Radius: `radiusCard` 10, `radiusButton` 12, `radiusPanel` 18.
  **Target:** add `radiusPill` (999) for HUD chips and seat plates.
- Touch targets: primary 48, hand card short edge 44, compact cover 36,
  overlay 40. These are floors, not suggestions.

## 6. Motion

### Current

`MotionSpeed` multiplies durations (normal 1.0, fast 0.6, reduced 0.35 with
linear curves, OS reduce-motion honoured). Its doc comment points to durations
"listed in the design doc", but none were listed: today about 20 distinct
literal durations are spread over 17 UI files (most common: 220, 180, 200,
140 ms).

### Target duration tokens

| Token | Normal | Use |
| --- | --- | --- |
| `motionInstant` | 120 ms | Press feedback, ring flash in |
| `motionQuick` | 180 ms | Card lift, chip/state changes |
| `motionStandard` | 220 ms | Panels, toasts, seat plate state |
| `motionEmphasis` | 280 ms | Turn change, coach card in/out |
| `motionFlight` | 420 ms | Card flight (draw, discard, meld placement) |
| `motionDeal` | 60 ms stagger + `motionFlight` | Opening deal |
| `motionCelebrate` | 1200–1400 ms | Fifty, match won/lost |

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

### 7.1 Layout contract (landscape) — Current structure, Target treatment

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

### 7.2 Seat plate — Target (new component)

Every CPU seat gets an L2 plate attached to its rail:

- Name / persona, CPU level badge (`indigoAccent`).
- Card count (tabular numeric), opened yes/no, running score.
- **Active turn:** keeps the existing turn hue over the seat's cards and adds a
  `goldAccent` plate edge with a `motionEmphasis` glow-in.
- **Thinking:** a quiet three-dot or sand-line sweep, no spinner.
- **Eliminated:** `eliminatedDim` over plate and rail, score struck through.
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
  surface keeps the corner stock; its geometry is frozen.
- **Hand:** a flat row. An arc was considered and left out: drag reorder and
  the 44 dp card tap target rely on the row's straight slots.

### 7.4 Coach UI — Target

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

## 8. Components

| Component | Status | Contract |
| --- | --- | --- |
| Primary button | Current (`FilledButton` theme) | Gold fill, charcoal label, 48 dp, one per view region |
| Secondary button | Current (`OutlinedButton`) | Sand outline. **Target:** max two stacked; beyond that use a section or list |
| Text button | Current | Gold label, for tertiary actions |
| Segmented control | Current (setup) | Gold selected segment. **Target:** shown inside an option card with a one-line explanation |
| Option card | Current | L2 card: icon, title, value summary, chevron/edit; replaces bare segmented rows |
| Lounge panel | Current (`LoungePanel`) | L3 modal surface with medallion; the only modal shell |
| Lounge toast | Current (`LoungeToast`) | L2 transient message; never over a seat zone |
| HUD capsule | Current | One lacquered pill in the top-end corner holding every table control (scores, fast-forward, sandbox exit, pause), segments split by hairlines; sandbox floors segments at 44 dp |
| HUD chip | Current | Open-need chip: lacquered, brass edge, overline caption over a tabular number |
| Score medallion | Current | Score ringed by an arc that fills and warms toward elimination; shared by seat plates, the score sheet and the pause standings |
| Seat plate | Current | Section 7.2 |
| Coach card | Current | Section 7.4 |
| Screen header | Target | Replaces the stock black `AppBar`: transparent over the screen background, display-face title, back as an icon button |
| List row | Target | History/report rows: title, meta line, trailing result badge; 56 dp min |
| Stat tile | Target | Big tabular number + label + optional trend; used by Stats and match reports |

## 9. Screens and navigation

### 9.1 Inventory

Splash, Onboarding, Home, New game setup, Game table, Rules help, Guided
practice (checklist, reading panel, strictness explainer), Match history,
Match statistics, Match replay, Branch sandbox, Settings (incl. card theme
preview, licences).

### 9.2 Home — Target information architecture

1. **Hero:** wordmark, card fan, then **one** primary action that adapts:
   `Continue` when a saved match exists (with a one-line match summary),
   otherwise `New game`. The other appears as a secondary action.
2. **Learn:** Guided practice, Rules. Cards or rows, not full-width buttons.
3. **Your table:** History, Stats, replays (and sandbox entry points from
   history). Shows recent results when there are any.
4. Settings in the header.

The rule: a new feature adds a row to a section, never another full-width
button to the home stack.

### 9.3 Setup — Target

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
  `lib/ui/features/` as a ceiling. Counts may fall, never rise; lower the
  ceiling in the same change that removes literals.
- **Goldens:** deliberately not pixel goldens. Rasterised text and blur
  differ across Flutter versions and machines, so pixel goldens would fail on
  unrelated toolchain upgrades. Layout is guarded instead by the existing
  geometry tests (frozen replay oracle, hand-span parity, coach docking).
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
   (placement medallions, gold-edged wins) and stats tiles. Rules help keeps
   its existing layout under the new type and header.
5. **Enforcement** — done: token ratchet (section 12).

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
