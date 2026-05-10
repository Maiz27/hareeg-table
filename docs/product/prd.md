# PRD: Hareeg Table

## Summary

Hareeg Table is a free, open-source, offline-first Flutter card game for Classic Hareeg. The first release focuses on one human player against three CPU players, accurate Classic Hareeg rules, strong single-player pacing, and a polished warm Sudanese lounge presentation.

## Goals

- Build an accurate Classic Hareeg offline game.
- Support one human player against three CPU players.
- Ship with no ads and no locked paid cosmetics.
- Provide difficulty levels and CPU personalities that make offline play replayable.
- Make the app localization-ready from day one, with English as the launch language and Arabic planned.
- Keep the game engine independent from Flutter UI so future modes and online play remain possible.

## Non-Goals For First Release

- Online multiplayer.
- Account system.
- Store payments.
- Hareeg 14 full implementation.
- Separate Fifties mode full implementation.

## Primary Mode

Classic Hareeg:

- 4-player table.
- Human + 3 CPUs.
- Anti-clockwise turns.
- 14-card hands, starter has 15.
- Opening requirement default 51.
- Fifty special claim and scoring.
- Elimination at 31.

Detailed rules live in `docs/rules/classic-hareeg.md`.

## Platform And Stack

- Flutter app.
- Dart rule engine independent from UI.
- Android-first launch.
- Cross-platform structure retained for future iOS support.

Proposed packages/modules:

- `core`: cards, deck, melds, rulesets, validation, scoring, game state.
- `ai`: CPU strategy and difficulty.
- `app`: Flutter UI, table, animations, settings, localization.
- `persistence`: preferences, match history, unlocks if needed.

## User Experience

- Main screen opens into the playable table experience, not a marketing landing page.
- Assisted default rules should block illegal actions and explain why.
- Advanced presets can allow selected mistakes and penalties.
- Fifty should feel distinct, timed, and high stakes.
- Auto-sort should be available from settings and during play.
- Themes should be included or earnable, not locked behind payment.

## Design

Design direction lives in `docs/design/direction.md`.

Launch direction:

- Warm Sudanese lounge.
- Clean readable card table.
- Flame accent reserved for Fifty.
- English-first UI with Arabic support planned.

## CPU

Difficulty should not be simple randomness only.

- Beginner: obvious legal plays, occasional missed opportunities.
- Casual: basic meld building and discard safety.
- Skilled: tracks visible cards, avoids feeding opponents, manages opening pressure.
- Expert: stronger hand evaluation, Fifty awareness, joker value planning.

CPU Fifty reaction should depend on difficulty and personality.

## Rule Presets

Product names are pending.

- Assisted: blocks illegal actions and shows helpful state.
- Penalty table: allows selected mistakes and applies +3.
- Hard 17 table: allows selected mistakes, applies +17, and removes player from current round.

## Future Expansion

See `docs/roadmap/future-ideas.md`.

## Open Decisions

- Final public names for mistake/rules presets.
- CPU mistake behavior by difficulty.
- Exact Hareeg 14 scoring values and threshold.
- Full separate Fifties mode rules.
- Arabic terminology glossary.
- License choice for code and future assets.
