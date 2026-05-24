# CpuObservation Design

Status: Proposed. Scope: deepen the CPU/rules seam for Classic Hareeg so tier-specific
strategies (Beginner / Casual / Skilled / Expert) can reason about the table, not
just the legal action ids. Replaces the shallow `CpuTurnSnapshot` in
`lib/cpu/classic_hareeg/cpu_strategy.dart`.

ADR-0001 still binds: the CPU consumes visible state and emits intents through legal
action ids. Nothing on this interface lets a strategy mutate state or peek at
private controller fields.

## 1. Interface sketch

`CpuObservation` is an abstract interface, pure Dart, no Flutter import. All accessors
must be O(1) or O(hand-size); enumerators are pull-only and lazy.

```dart
abstract interface class CpuObservation {
  // ---- identity & legal options (today's surface) ----
  PlayerSeat get seat;
  CpuDifficulty get difficulty;
  List<String> get legalActionIds;            // unmodifiable
  TurnPhase get turnPhase;
  HareegCard? get pendingDiscard;

  // ---- visible hand & table ----
  List<HareegCard> get ownHand;
  int handCountFor(PlayerSeat seat);          // any seat (count only is visible)
  List<PlacedMeld> tableMeldsFor(PlayerSeat seat);
  Map<PlayerSeat, List<PlacedMeld>> get tableMelds;
  int get tableMeldCount;

  // ---- pile state ----
  int get stockCount;
  HareegCard? get topDiscard;
  int get discardCount;

  // ---- opening / benchmark ----
  OpeningState get openingState;
  bool ownHasOpened();
  PlayerSeat? get benchmarkOwner;             // openingState.benchmarkOwner
  int get currentOpeningRequirement;          // openingState.currentRequirement

  // ---- scoring / elimination posture ----
  ClassicHareegScoreView get scoreView;
  int scoreFor(PlayerSeat seat);
  int get ownScore;
  int get eliminationThreshold;               // setup.eliminationThreshold (visible)
  List<PlayerSeat> get activeSeats;
  PlayerSeat get currentSeat;                 // == seat during own turn
  List<PlayerSeat> get opponents;             // activeSeats - seat, in turn order

  // ---- Fifty / Khamsin window ----
  PlayerSeat? get fiftyClaimant;
  int? get fiftySecondsRemaining;             // null when no window
  bool get ownIsFiftyClaimant;                // convenience

  // ---- sub-interfaces designed by sibling agents ----
  DiscardHistoryView get discardHistory;      // per-round attributed log
  MeldPartitionView get partitions;           // enumeration of own hand partitions

  // ---- difficulty profile passthrough ----
  CpuDifficultyProfile get difficultyProfile;
}
```

Two thin sub-interfaces hide the shape the sibling-designed modules will eventually
land. `CpuObservation` only specifies the *queries* it needs; the concrete API of
`DiscardHistory` / `MeldPartitionEnumerator` is owned by those design docs.

```dart
abstract interface class DiscardHistoryView {
  /// Last [n] discards by [seat], newest first, with rank/suit. Joker discards
  /// included with their face identity (jokers are visible when discarded).
  List<DiscardEvent> lastDiscardsBy(PlayerSeat seat, int n);

  /// Cards picked up from the discard pile by [seat] this round.
  List<PickupEvent> lastPickupsBy(PlayerSeat seat, int n);

  /// Where (and when) a specific card identity was last seen in the pile.
  CardSighting? cardSeenAt(CardRank rank, CardSuit suit);

  /// All discards this round, attributed to discarder seat. Ordered oldest-first
  /// so Expert can build rank/suit "hot lists" per opponent.
  Iterable<DiscardEvent> get all;
}

abstract interface class MeldPartitionView {
  /// Lazy enumerator of ways to partition [ownHand] (plus optional pending
  /// discard) into one or more legal melds. The enumerator yields complete
  /// partitions; Skilled/Expert can rank by partition score, joker count,
  /// or meld length. Pulling is bounded so the CPU never blocks the isolate.
  Iterable<MeldPartition> enumerate({
    bool includePendingDiscard = true,
    int maxPartitions = 32,
  });

  /// Convenience: best single meld for "shorter melds preferred" Skilled rule.
  MeldPartition? shortestSingleMeld();

  /// Convenience: a partition that finishes the hand (empties it to 1 card),
  /// if any. Used by finish-turn joker positioning.
  MeldPartition? finishingPartition();
}
```

`DiscardEvent`, `PickupEvent`, `CardSighting`, and `MeldPartition` are owned by the
sibling design docs. The signatures above are the *only* coupling this design
introduces.

## 2. Adapter shape

The runner constructs a `LiveCpuObservation` once per step. It is a read-only view
over the controller and the round-scoped `DiscardHistory` / partition enumerator.

```dart
class LiveCpuObservation implements CpuObservation {
  LiveCpuObservation({
    required this.controller,
    required this.seat,
    required this.legalActionIds,
    required this.difficulty,
    required this.discardHistory,         // round-scoped, lives on runner/controller
    required this.partitions,             // built lazily from controller.handFor(seat)
  });
  // every getter delegates to controller.handFor / tableMeldsFor / openingState /
  // scoreView / stockCount / topDiscard / discardPile.length / fiftyClaimant /
  // fiftySecondsRemaining / activeSeats / currentSeat / turnPhase / pendingDiscard.
}
```

Required controller surface — **all already public**:
`handFor`, `tableMeldsFor`, `tableMelds`, `tableMeldCount`, `stockCount`, `topDiscard`,
`discardPile`, `openingState`, `scoreView`, `activeSeats`, `currentSeat`, `turnPhase`,
`pendingDiscard`, `fiftyClaimant`, `fiftySecondsRemaining`, `cardCountFor`, `setup`.

New surface on the controller (minimised):

- `DiscardHistory get discardHistory` — a round-lifetime ledger the controller already
  has to populate when applying `_applyDiscard` and `_applyTakePreviousDiscard`. The
  sibling `DiscardHistory` design owns the field's exact shape; the controller exposes
  it read-only. **This is the only new public getter required.**
- The partition enumerator is *not* a controller field. `LiveCpuObservation`
  constructs `MeldPartitionEnumerator(handFor(seat), tableMelds, openingState)` on
  demand and caches it for that turn step. No new controller surface.

`eliminationThreshold` is already reachable through `controller.setup` (or its
`rulePreset`); no new field.

The adapter does not copy hands or melds; it returns unmodifiable wrappers, exactly as
the controller's existing accessors already do. Construction is therefore
*field-aliasing*, not deep copy — meeting the "cheap to construct per CPU turn"
constraint at the runner.

## 3. Strategy-side changes

`CpuTurnSnapshot` is **kept and extended**, not replaced. Two reasons:

1. Beginner and Casual today only need `seat`, `legalActionIds`, `difficulty`. The
   existing constructor stays. Tests in `cpu_strategy_test.dart` keep compiling.
2. Tier strategies need the richer view. We add a *second* parameter to
   `CpuStrategy.chooseMove`, defaulting to a minimal observation derived from the
   snapshot:

```dart
abstract interface class CpuStrategy {
  CpuMoveIntent chooseMove(CpuTurnSnapshot snapshot, {CpuObservation? observation});
}
```

Beginner/Casual ignore `observation`. Skilled/Expert require it and throw
`StateError` when null (programmer error from the runner). The runner always passes
a `LiveCpuObservation`. The default-null parameter lets ad-hoc tests construct a
snapshot without building a full controller.

Long term (once Skilled lands), the snapshot becomes a thin facet of the observation:
`CpuTurnSnapshot.fromObservation(obs)`. We do not need that on day one.

## 4. CpuMovePlanner evolution

`ClassicHareegCpuMovePlanner.evaluate(legalActionIds)` becomes one of several
*scoring planners* sharing an interface:

```dart
abstract interface class CpuMovePlanner {
  ClassicHareegCpuMovePlan plan(CpuObservation obs);
}
```

- `PriorityCpuMovePlanner` — today's behaviour, keyed on `legalActionIds` only.
  Used by Beginner and Casual. Its `plan` method ignores everything on `obs` except
  `legalActionIds`. The existing `evaluate(legalActionIds)` becomes a thin wrapper
  on top so `cpu_move_planner_test.dart` keeps passing.
- `SkilledCpuMovePlanner` — scores meld plays via `obs.partitions` (prefers shorter
  melds, fewer jokers), reads `obs.discardHistory.lastDiscardsBy` for discard safety,
  consults `obs.scoreView` and `obs.openingState.benchmarkOwner` for Fifty
  hold/finish and opening fatness.
- `ExpertCpuMovePlanner` — adds per-opponent rank/suit hot lists from
  `obs.discardHistory.all`, joker-placement interior-slot bias on partitions,
  elimination posture when `obs.ownScore >= eliminationThreshold - small`.

`ClassicHareegCpuStrategy` becomes a *router*:

```dart
final planner = switch (obs.difficulty) {
  CpuDifficulty.beginner || CpuDifficulty.casual => const PriorityCpuMovePlanner(),
  CpuDifficulty.skilled => const SkilledCpuMovePlanner(),
  CpuDifficulty.expert => const ExpertCpuMovePlanner(),
};
final plan = planner.plan(obs);
```

One planner per tier, all stateless, all picked by enum. This keeps each tier file
small and independently testable, avoids a megafunction with `if (difficulty == ...)`
branches inside the scorer, and lets us land tiers incrementally (Skilled can
ship while Expert is still a passthrough alias to Skilled).

## 5. Migration path

1. **Land `CpuObservation` + `LiveCpuObservation` with no behaviour change.** Runner
   constructs the observation alongside the snapshot and passes both. Strategy
   ignores `observation`. Existing snapshot constructor stays; all existing tests
   pass untouched.
2. **Move `ClassicHareegCpuMovePlanner.evaluate` into `PriorityCpuMovePlanner`,**
   keeping the static `evaluate(legalActionIds)` as a deprecated facade that
   delegates. `cpu_move_planner_test.dart` keeps using the facade.
3. **Add `DiscardHistory` to the controller** (sibling design). Runner threads it
   into `LiveCpuObservation`. Still no strategy change.
4. **Add `MeldPartitionEnumerator` and wire it through `MeldPartitionView`** in
   `LiveCpuObservation` (sibling design). Verify it is cheap on a 15-card hand.
5. **Introduce `SkilledCpuMovePlanner` and the strategy router.** Skilled tier
   becomes selectable from setup; Beginner/Casual paths unchanged. Add Expert in a
   follow-up using the same shape.

At each step the diff is small, the runner-strategy seam stays type-stable, and the
old tests keep passing.

## 6. Test surface

After step 1, `CpuObservation` is mockable. We can build a `FakeCpuObservation` in
tests and assert tier behaviour without instantiating a `ClassicHareegGameController`
or dealing a round:

- "Skilled prefers the 3-card meld when both a 3-card and a 5-card legal partition
  exist" — fake `MeldPartitionView` returning two partitions, assert chosen
  `actionId`.
- "Skilled avoids discarding the rank an opponent just picked up" — fake
  `DiscardHistoryView.lastPickupsBy(west, 3)` returning one event with a 9, hand
  contains 9 and 4 of the same suit, assert the planner chooses to discard the 4.
- **"Expert refuses to discard adjacent to an opponent's run end"** — fake
  `tableMeldsFor(west)` returning a 6-7-8 hearts run, hand contains 5h, 9h, and an
  unrelated card, assert neither 5h nor 9h is chosen for the discard.
- "Near elimination (ownScore == 26, threshold 30), Expert chooses to claim Fifty
  even when a meld play is available" — fake `scoreView` and `legalActionIds`.
- "Skilled returns pending discard when no partition uses it" — fake `partitions`
  returning empty when `includePendingDiscard: true`.

None of these need the rules engine. They become fast, deterministic unit tests
against the strategy module alone.

The existing `cpu_strategy_test.dart` and `cpu_move_planner_test.dart` still cover
the Beginner/Casual contract via the snapshot path, so nothing regresses.

## 7. Open questions

- **Round-scoped lifetime of `DiscardHistory`.** Should the controller own it and
  reset on round end, or should it be a separate object the runner injects?
  Leaning toward controller-owned so it is correctly rebuilt on
  `nextRoundSnapshot`, but the sibling design owns this.
- **Partition enumeration budget.** `maxPartitions: 32` is a guess. We need a
  microbenchmark on a 15-card opening hand once `MeldPartitionEnumerator` exists.
  If enumeration is the bottleneck the observation should expose a *capped*
  iterator rather than a count.
- **Visible joker discards.** When a joker is legally discarded under a permissive
  preset, does `DiscardEvent` carry the joker's face identity or the represented
  identity (if any)? Expert hot-list logic needs the face identity; the design
  doc assumes that. Worth confirming with the rules-engine reviewer.
- **Pending-discard attribution in `DiscardHistoryView`.** When a CPU picks up the
  previous discard and later returns it, does the history record the pickup, the
  return, or both? Expert needs to know "the West seat *considered* this 7 but did
  not keep it" — strong signal that 7 is not useful to West.
- **`legalActionIds` cardinality cap on Expert.** Today `cpuActionIdsFor` already
  prunes the surface. If Expert wants to evaluate covers across all opponents'
  melds, do we need a separate `obs.fullLegalActionIds` accessor? Default answer:
  no — Expert plays through the same bounded surface and trusts the action
  planner. Revisit if Expert behaviour requires it.
- **Backward-compat deadline for the snapshot.** Should `chooseMove(snapshot)`
  remain in the interface forever, or do we collapse it onto `chooseMove(obs)`
  once Skilled ships? Recommend collapsing in a single PR after step 5, with the
  snapshot becoming a constructor argument on a `LiveCpuObservation.fromSnapshot`
  used only by old tests.
