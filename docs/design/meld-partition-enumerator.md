# Meld Partition Enumerator

Status: Draft (design only — no code yet)
Scope: Classic Hareeg rules layer (`lib/domain/classic_hareeg/rules/`)
Related: ADR 0001 (rules-engine boundary), `meld_candidate_search.dart`, `meld_validator.dart`, `joker_rules.dart`, `opening_rules.dart`, `classic_hareeg_table_play_planner.dart`

## 1. `MeldPartition` value type

`MeldPartition` is the immutable description of *one* legal way to commit a subset of a hand into one or more melds.

```dart
final class MeldPartition {
  const MeldPartition({
    required this.melds,            // List<PlacedMeld>, each already validated + ordered
    required this.cardsUsed,        // List<HareegCard>, union of all meld cards (with represented identities baked in)
    required this.cardsRemaining,   // List<HareegCard>, hand minus cardsUsed, original physical cards (no representations)
    required this.jokerAssignments, // List<JokerMeldAssignment>, one per unresolved-joker-in-partition
  });

  final List<PlacedMeld> melds;
  final List<HareegCard> cardsUsed;
  final List<HareegCard> cardsRemaining;
  final List<JokerMeldAssignment> jokerAssignments;

  // Derived (cheap getters, computed from melds — no extra storage needed):
  int get totalValue;             // sum of PlacedMeld.valueSnapshot
  int get meldCount;              // melds.length, also "cover-surface count"
  double get meanMeldLength;      // cardsUsed.length / meldCount
  int get jokerCount;             // jokers in cardsUsed
  bool usesCardId(String cardId); // O(meldCount * avgMeldSize)
  Set<String> get usedCardIds;    // memoized lazily by callers if hot
}
```

Compatibility note: `PlacedMeld` already carries `valueSnapshot` and ordered cards, so `totalValue` and "did this partition open above the benchmark?" reduce to existing primitives. `JokerMeldAssignment` is reused from `classic_hareeg_table_play_planner.dart` rather than reinventing the representation record.

`cardsRemaining` is the *unmodified* physical leftover from the hand — important because the CPU strategy needs to reason about what would be discarded if this partition were played. `cardsUsed` carries the represented-identity-baked-in version (so set membership against the hand uses `HareegCard.id`, which is invariant under representation).

## 2. `MeldPartitionEnumerator` interface

```dart
abstract final class MeldPartitionEnumerator {
  /// Lazy stream of partitions of [hand] into one or more legal melds.
  /// Iteration stops the moment the caller stops pulling.
  static Iterable<MeldPartition> partitionsOf(
    List<HareegCard> hand, {
    int minMelds = 1,              // 1 lets a single big meld qualify; opening normally needs >= 1
    int maxMelds = 5,              // hard ceiling; 14 cards / 3-per-meld = 4 melds max in practice
    String? mustUseCardId,         // e.g. pending-discard or a specific joker
    int? minTotalValue,            // e.g. openingState.currentRequirement
    int safetyCap = 2048,          // internal runaway guard, see §5
  });

  /// Convenience: same enumeration, sorted by [comparator], up to [take].
  /// Materializes at most [take] partitions; uses a bounded priority queue.
  static List<MeldPartition> topPartitions(
    List<HareegCard> hand, {
    required Comparator<MeldPartition> comparator,
    required int take,
    /* same filter params as partitionsOf */
  });
}
```

Filtering is intentionally pushed *into* the enumerator (rather than left to `.where(...)` on the iterable) so the search can prune subtrees that cannot satisfy `mustUseCardId` or `minTotalValue` — e.g. once the partial total + remaining-hand-upper-bound is below `minTotalValue`, abandon the branch.

Rankers (mean-length, cover-surface, opening-value) are plain `Comparator<MeldPartition>` constants exported from the module:

```dart
abstract final class MeldPartitionRankers {
  static const Comparator<MeldPartition> byMeanMeldLengthAsc = /* short melds first */;
  static const Comparator<MeldPartition> byCoverSurfaceDesc = /* more melds first */;
  static const Comparator<MeldPartition> byTotalValueDesc;
}
```

Sort/filter are deliberately *not* methods on `MeldPartition` itself — keeping the value type comparator-free preserves it as a pure data record.

## 3. Joker representation handling

**Decision: yield one partition per distinct legal representation.**

A partition with a single joker representing the missing 7♣ in a 5-6-J(7)-8♣ sequence is a *different partition* from the same physical cards where the joker represents 9♣ (and forms 6-7-8-J(9)). The enumerator yields both.

Trade-off acknowledged in the prompt:
- (+) `MeldPartition` stays immutable, complete, and ranker-friendly — `totalValue` is unambiguous, opening checks need no follow-up resolution step.
- (-) Search space grows; partition count for hands with 2+ jokers can multiply by ~10x.

Mitigations:
- Representations come from `ClassicHareegJokerRules.resolveMeldVariants` (already capped at `limit: 52` per meld via `representationOptionsForMeld`), so per-meld blow-up is bounded.
- The enumerator deduplicates by a partition key built from `(sorted PlacedMeld ordered-card-id list joined per meld, joined across melds)` — visually-equivalent representations collapse.
- `safetyCap` provides a final escape valve.

## 4. Implementation sketch

High-level algorithm: backtracking over the hand, anchored on the lowest-indexed unused card (the trick already used in `_partitionIntoMelds` and `_candidateGroupsContainingFirst` inside `classic_hareeg_table_play_planner.dart`).

```
fn enumerate(remainingHand, accumulatedMelds, accumulatedAssignments):
  if remainingHand.isEmpty OR accumulatedMelds.length >= maxMelds:
    if accumulatedMelds.length >= minMelds AND satisfiesFilters():
      yield MeldPartition(...)
    if remainingHand.isEmpty: return

  // Branch A: skip into cardsRemaining (only legal if we already have >= minMelds)
  if accumulatedMelds.length >= minMelds:
    yield MeldPartition(... cardsRemaining: remainingHand ...)

  // Branch B: pick the lowest-index card and enumerate every legal meld containing it.
  anchor = remainingHand.first
  for group in meldGroupsContaining(remainingHand, anchor):
    for resolution in ClassicHareegJokerRules.resolveMeldVariants(group):
      if !resolution.result.isValid: continue
      recurse(remainingHand - group, accumulatedMelds + PlacedMeld.fromCards(resolution.cards), ...)
```

Reused helpers from the existing rules layer:
- `ClassicHareegMeldValidator.validate` — gates each candidate group.
- `ClassicHareegJokerRules.resolveMeldVariants` — supplies the representation expansion in §3.
- `PlacedMeld.fromCards` — gives ordered cards and `valueSnapshot` for free.
- `meld_candidate_search.dart`'s shape of `_addSetCandidateGroups` / `_addSequenceCandidateGroups` informs the *per-anchor* candidate enumeration, but cannot be used as-is: that module returns a flat capped list across the whole hand, whereas the enumerator needs candidates anchored on a specific card.

Anchoring on the lowest-index unused card is the same dedup trick that prevents `(meldA, meldB)` and `(meldB, meldA)` from both being yielded.

**Complexity.** Worst case is exponential in hand size: the number of partitions of a 14-card hand into melds of size ≥ 3 is bounded by the number of subset-decompositions, which for n=14 is in the low thousands once joker representations are expanded. Empirical expectation for a "normal" 14-card Hareeg hand (1-2 jokers, 3-5 candidate melds) is dozens to low hundreds of partitions — fast enough that Expert-tier evaluation against a comparator over the full set is fine. The `safetyCap` exists for adversarial hands (e.g. 4 jokers and many same-rank duplicates).

## 5. Bounds and limits

- **`safetyCap` (default ~2048):** internal early-termination if the enumerator emits this many partitions without the caller stopping. Protects against pathological hands.
- **No caller-supplied `limit` on the iterable itself** — `Iterable.take(n)` is the idiomatic Dart way; we don't reinvent it.
- **`topPartitions`** is the bounded-output convenience; it owns its own materialization budget.
- **Relationship to `maxPhysicalVariants` in `meld_candidate_search.dart`:** the existing constant is a *UI-preview* concern (cap suggestions surfaced to the user). The enumerator does **not** apply it: CPU evaluation must see the true partition space, not the UI-truncated slice. The enumerator and the candidate search are independent producers; neither calls the other.

## 6. Relationship to `meld_candidate_search.dart`

Keep `meld_candidate_search.dart` as-is for UI preview. It answers a different question ("show me up to 8 nice candidate groups for the picker") and its cap behavior is wrong for CPU use. Deprecating it would force UI to depend on the heavier enumerator with extra `.take()` plumbing for no gain.

If duplication becomes a maintenance problem later, the per-anchor candidate generator inside the enumerator can be extracted as a shared helper that the candidate search calls with `maxPhysicalVariants` and the enumerator calls without a cap. Not needed at v1.

## 7. Test surface

All tests are pure-Dart, no game state.

1. **Empty/short hand** — hand of 0/1/2 cards yields no partitions.
2. **Single trivial meld** — three 7s yields exactly one partition with one set meld and `cardsRemaining = []`.
3. **7-card sequence split** — `5♣6♣7♣8♣9♣10♣J♣` yields *at least* `{[5-6-7],[8-9-10-J]}`, `{[5-6-7-8],[9-10-J]}`, and `{[5-...-J]}` (the full 7-card meld). Assert all three are present and `cardsRemaining` is empty for each.
4. **`mustUseCardId` filter** — partitions that don't include the pending-discard id are not yielded.
5. **`minTotalValue` filter** — partitions whose `totalValue < benchmark` are not yielded; partitions on the boundary (`==`) are.
6. **Joker expansion** — hand `6♣ 7♣ Joker 9♣ 10♣` (one joker between two pairs) yields two partitions: joker as 8♣ giving a 5-card sequence, and (if applicable) any alternative representations the resolver produces. Assert distinct `PlacedMeld.cards` per partition.
7. **Lazy stopping** — `partitionsOf(hand).take(1)` does not iterate further; verify by wrapping a counting iterable or asserting no `safetyCap`-blowup on adversarial input.
8. **Determinism** — same hand yields partitions in the same order on repeat calls (anchoring + iteration order over `CardSuit.values`/`CardRank.values` guarantees this; lock it in a test).
9. **Ranker sanity** — `MeldPartitionRankers.byTotalValueDesc` orders the 7-card split tests correctly.

## 8. Open questions

1. **Should `cardsRemaining` carry represented identities for melded jokers, or strip them?** Current sketch strips (use original physical cards). The CPU's discard logic wants raw cards. Confirm.
2. **Do we expose the partition key (the dedup hash) as a public field on `MeldPartition`?** Useful for memoization in CPU strategy; downside is leaking an implementation detail. Default sketch: no, callers build their own if needed.
3. **High-ace sequences in joker-expanded partitions** — the current `_sequenceRankWindows` in `joker_rules.dart` already emits the high-ace window. Confirm that `MeldPartition.totalValue` derives correctly from `valueSnapshot` so we don't double-count the ace.
4. **Should `MeldPartition` include opening-eligibility as a boolean field**, or leave that as a derived check `partition.totalValue >= openingState.currentRequirement`? Sketch leaves it derived (the partition has no knowledge of opening state).
5. **`CpuObservation` accessor shape** — exposed as `Iterable<MeldPartition> partitions({...filters})` returning the enumerator directly, or wrapped behind a memoized snapshot? Defer to the sibling `CpuObservation` design agent.
6. **`minMelds` default of 1** — does Expert opener strategy ever need `minMelds = 2` (force a multi-meld split)? If so, surface it cleanly; otherwise drop the param and let the comparator/filter do the work.
