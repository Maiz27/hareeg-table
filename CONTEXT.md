# Hareeg Table Context

This file is a quick orientation map for agents and contributors working on
Classic Hareeg. It captures project vocabulary and points to the deeper design
docs when a term needs implementation detail.

## Architectural Boundary

Classic Hareeg rule logic lives in pure Dart domain code. It must not import
Flutter widgets or UI types. The Flutter app presents state, animations, and
input affordances, but rule decisions remain in the domain layer. CPU strategy
reads visible game state and legal action ids, then emits move intents that the
rules engine validates.

Primary reference: [ADR 0001](docs/adr/0001-rules-engine-boundary.md).

## Current Design Spine

The deepening plan shipped in phases, each recorded in its own design doc.
Phase A collapsed table assistance settings into `TableStrictness`
([table-strictness.md](docs/design/table-strictness.md)). Phase B deepened CPU
observation and planning ([cpu-observation.md](docs/design/cpu-observation.md),
[meld-partition-enumerator.md](docs/design/meld-partition-enumerator.md),
[opponents-ladder.md](docs/design/opponents-ladder.md)). Phase C added the
strictness-specific joker memory mechanic. Phase D added the end-of-match screen
([end-of-match-screen.md](docs/design/end-of-match-screen.md)).

## Domain Vocabulary

### `TableStrictness`

Single table-behavior ladder replacing the legacy `RulePreset`, `TableAids`,
and `memoryJokerDisplay` axes. The four tiers are `coaching`, `standard`,
`strict`, and `table`.

Rules-relevant derivations live in
`lib/domain/classic_hareeg/rules/strictness_rule_profile.dart`. UI-only
derivations live in `lib/ui/core/strictness/strictness_ui_profile.dart` so the
rules layer stays Flutter-free.

References:
- [table-strictness.md](docs/design/table-strictness.md)

### `CpuObservation`

Read-only CPU-facing view of visible game state: the acting seat, legal action
ids, own hand, public table melds, stock/discard state, opening state, scores,
Fifty window state, discard memory, and meld partitions. It is the planned seam
for Skilled and Expert CPU behavior.

The CPU may use this data to choose an action id, but it does not mutate game
state or bypass rule validation.

Reference: [cpu-observation.md](docs/design/cpu-observation.md).

### `DiscardHistory`

Passive, per-round, per-seat discard and pickup log. The controller owns and
mutates it along the same paths that mutate the discard pile. External callers
receive a narrow read interface for CPU memory queries such as recent discards,
recent pickups, card sightings, rank counts, and joker discard counts.

It is persisted in match snapshots via the `discardHistoryEvents` field on
`ClassicHareegMatchSnapshot`; on resume the events replay through the live
record paths, so resumed matches retain full CPU discard memory.

Reference: [discard-history.md](docs/design/discard-history.md).

### `MeldPartition`

Immutable description of one legal way to commit a subset of a hand into one or
more melds. A partition tracks placed melds, cards used, cards remaining, and
joker assignments, with derived values such as total value, meld count, mean meld
length, and joker count.

`MeldPartitionEnumerator` is the planned lazy enumerator used by Skilled and
Expert CPU tiers to compare meld choices beyond the first legal action.

Reference: [meld-partition-enumerator.md](docs/design/meld-partition-enumerator.md).

### `MatchOverScreen`

Dedicated portrait screen shown after the match ends. It replaces the dead
`RoundSummaryScreen` route and presents the winner, final standings, rounds
played, and actions for returning to menu or starting a new match with the same
setup.

The live table still shows the final round overlay briefly before navigating to
this screen, so the player can read the final round scoring first.

Reference: [end-of-match-screen.md](docs/design/end-of-match-screen.md).

### `PlacedMeld`

Domain snapshot of a meld after it is placed on the table. It stores ordered
cards, the value at placement time, later cover value, and the total table
contribution. `PlacedMeld.fromCards` validates the meld and captures its value.

Primary code: `lib/domain/classic_hareeg/rules/opening_rules.dart`.

### `OpeningState`

Round-level opening benchmark state. It records the base opening requirement,
current benchmark requirement, first benchmark owner, lock state, and seats that
have opened. The benchmark can rise before it locks, then later seats must meet
the locked requirement.

Primary code: `lib/domain/classic_hareeg/rules/opening_rules.dart`.

### `FiftyClaimWindow`

Timed Khamsin/Fifty opportunity opened after a discard. It records the discarder,
the immediate claimant, the discarded card that must be used, the timer length,
and whether the first-round scoring exception applies.

Primary code: `lib/domain/classic_hareeg/rules/fifty_rules.dart`.

### `MatchProgressState`

Post-round match state after scoring and elimination. It contains scores by
seat, active seats, the next starter, and the match winner when only one active
seat remains.

Primary code: `lib/domain/classic_hareeg/rules/match_progression_rules.dart`.

## Contributor Notes

- Keep production domain imports relative and test imports package-based, matching
  the existing style.
- Keep CPU tier behavior behind planner classes instead of embedding difficulty
  branches deep inside the controller.
- Prefer rich plan/result objects over booleans for new rule or planner APIs.
- `ClassicHareegGameController` is the live integration point for many upcoming
  phases, but broad controller refactors are out of scope for the current plan.
