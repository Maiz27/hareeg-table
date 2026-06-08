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
([end-of-match-screen.md](docs/design/end-of-match-screen.md)). The guided
practice layer (PRD #64) added a 21-lesson teaching curriculum that runs on the
real table in practice mode
([guided-practice.md](docs/design/guided-practice.md)).

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

### Coaching advisor

`ClassicHareegCoachingAdvisor.adviseFor(controller, seat)` is a pure function
(no mutation, IO, or time) that classifies the human player's situation into
priority-ranked, localization-free `CoachingInsight`s for the `coaching` tier;
the UI stage maps each to EN/AR copy. It reuses the same analysis brain as the
CPU (`CpuObservation`, the meld-partition enumerator, the shared discard
keep-score model).

Load-bearing decision: the advisor **always observes at `CpuDifficulty.expert`**,
independent of the table's CPU difficulty, so it teaches expert-grade moves
(discards, covers, lay-offs) regardless of who the player is sitting against.
Do not "simplify" it to read the table difficulty.

Insight priority is a single descending ladder declared on
`CoachingInsightCategory` (not scattered band constants); the relative order is
load-bearing and pinned by a test. "Keep vs. shed" decisions (the discard
keep-score and the cover-gate's "isolated card") both derive from one disjoint
best-grouping model (`handKeepScores` / `cardsCanMeldTogether` in
`cpu_move_plan_pipeline.dart`), shared with the Expert CPU.

### Guided practice

Guided practice is an optional teaching layer for Classic Hareeg mechanics: a
checklist of 21 lessons across 4 packs that run deterministic boards on the real
`GameTableScreen` in practice mode, so lesson gestures transfer directly to
normal matches. Full design: [guided-practice.md](docs/design/guided-practice.md).

`PracticeSession` is the runtime for one lesson. It owns a private deterministic
`ClassicHareegGameController`, filters legal engine actions through the active
step, applies actions through the real rules engine, handles take-back
corrections and step regression, and never writes to the active-match store. A
Strict-tier penalty step opts into **`completesOnPenalty`** so a reverted +3
mistake counts as the demonstrated move instead of collapsing to a rejection.

`PracticeTableRun` is the table-hosted practice run module. It owns
practice-mode presentation state after a session mutation: banner reactions,
completion, score-reveal hand-off, dead-end detection, and coach-style
highlighting. `GameTableScreen` still owns rendering, gesture plumbing, motion,
audio, haptics, and shell callbacks. Every gesture affordance crosses one
`TableInteractionActionGate` (AllowAll on the live table, a step-backed Predicate
in practice).

`PracticeLessonRegistry` joins the static `PracticeCatalog` lesson ids to their
`PracticeLessonDelivery`: scripted table lessons from the four per-pack script
modules (`CoreTurnPracticePack`, `TableMechanicsPracticePack`,
`FinishFiftyPracticePack`, `TableStrictnessPracticePack`, which share
`PracticeScriptAuthoring` helpers), the strictness reading panel, or unavailable
lessons. Next-lesson chaining lives in this registry, not in the table or
checklist.

`PracticeBoardGrammar` captures executable board-design rules for lesson boards:
visible openings total what they imply, hand + table cards read as one deal
unless a lesson intentionally uses a mini hand. It also audits **hand
composition** — a script names its `taughtMelds`, and the audit reuses the real
meld enumerator to prove the remaining filler cards form no unintended meld. This
replaces the per-lesson "Fillers: no meld" comment discipline with a checked
claim. A grouped highlight step rings one meld per step in its own palette hue
(`highlightGroups` → `CoachHighlighting.groupOf`: group 0 teal = cards you
hold/play, group 1 blue = the target meld on the table).

`LearningProgressWorkflow` is the command surface for onboarding and practice
progress mutations. Screens delegate onboarding completion, lesson completion,
skip, and unskip through it; `LearningProgressRepository` remains only the
storage adapter and owns write serialization.

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
