# Design Direction

## Product Feel

Hareeg Table should feel like a warm Sudanese card table built for modern mobile play: readable, fast, generous, and grounded. The table is the hero. Cultural details should support the game rather than clutter the play area.

## Visual Direction

Identity: the Lit card. Charcoal ground, ember accent, sand hairlines, ivory paper.

- Menus, headers, panels and the splash sit on charcoal.
- Clean dark felt table for the primary play surface. Felt is used for the table and nowhere else.
- Sand-line pattern accents around menu corners, table edges, card backs, and theme surfaces.
- Ember is the brand flame: the chrome accent and, on the table, Fifty heat only.
- Avoid casino neon, childish cartooning, and constant flame decoration.

## Palette

Hues live in `lib/ui/core/theme/brand_palette.dart`; the app paints with the roles in `lounge_tokens.dart` that map onto them. The full role table is [Design Contract](design-contract.md) section 3.

- Ember #E4522B (`accent`, `fiftyHeat`); deepened #C8401F (`accentPressed`)
- Charcoal #15110E (`surface`, `onAccent`, `textOnPaper`); raised #221B16 (`surfaceRaised`, `panel`); spotlight #2C231C (`surfaceSpotlight`)
- Ivory #F8F0DD (`paper`, `cardFace`)
- Sand #D7BD83 (`line`, `stateSelected`)
- Felt green #12382F (`tableFelt`); raised #184235; spotlight #1B4A3C. Table only.
- Amber #F0962E (`statePending`)
- Rose #E07466 (`stateInvalid`)
- Crimson #A92E24 (`danger`, `suitRed`)
- Indigo #23395B (`seatCool`)
- Off-white #F5EFE3 (`textPrimary`)
- Stone #B8AA91 (`textMuted`)
- Coach family, coaching UI only: teal #2FB4A6, blue #4FA8E0, violet #B07BE6, orchid #DC6FA0 ("let go")

## Icon Direction

![Hareeg Table launcher icon: the Lit card on its ember tile](../../assets/brand/launcher/lit_card_composite.png)

Current identity: the **Lit card**, a single playing card whose top edge is a
flame, with a diamond pip cut from it. One silhouette, two colours on a tile.
Masters, lockups in both scripts and the usage guide live in
`assets/brand/explorations/identity-2026-10/`.

- Launcher: ember tile (`#E4522B`), ivory card, charcoal flame. Colour earns
  its keep on the home screen, where a game should look like one.
- Splash and in-app: charcoal ground, ivory card, ember flame, so the launch
  frame bridges the home screen and the app's dark surfaces.
- Felt green stays the table surface. It is not a brand colour.
- Off-limits: fanned royal cards, chips, coins, casino bevels, glows.
- The Arabic-Indic fifty (٥٠ as a flame ring and spark, `b-fifty/` in the
  explorations folder) is reserved for the in-game Fifty cue, not the logo.
- The earlier painted concept (`assets/brand/app-icon-concept-v2.png`) is
  superseded.

## Interaction Principles

- Cards must be readable on small Android screens.
- The app should support tap-first play, with drag interactions where they add clarity.
- Legal moves should be easy to discover.
- Assisted mode should prevent avoidable frustration.
- More advanced modes may intentionally rely on memory, timing, and player attention.
- Joker identity should be represented creatively, not just with a plain label overlay.
- In memory-oriented modes, joker identity may be shown briefly and then return to a mostly joker appearance.

## Source Of Truth

Product requirements, rule-flow decisions, and acceptance criteria live in the canonical GitHub PRD:

https://github.com/Maiz27/hareeg-table/issues/1

This file records stable visual direction only. Tokens, components, table layout, motion and screen rules live in the [Design Contract](design-contract.md). Do not use it as a branch tracker or a duplicate PRD.
