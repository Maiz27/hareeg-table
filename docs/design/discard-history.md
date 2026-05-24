# Design: DiscardHistory Module

## Purpose

Skilled CPU tiers need richer queries against the discard stream than the
controller's flat `_discardPile` + last-discarder pair affords. `DiscardHistory`
is a **passive, derived, per-round, per-seat-attributed event log** colocated
with the controller. It is read-only from the outside, mutated only by the
controller along the same code paths that mutate the discard pile, and reset on
the same round boundary as the rest of the controller's per-round state.

Hot path: Skilled tier issues ~20-50 queries per CPU decision. The interface
favors zero-allocation reads where possible (`Iterable` views over `List`
copies) and rank-indexed lookups over linear scans.

## 1. Interface Sketch

```dart
// lib/domain/classic_hareeg/game/classic_hareeg_discard_history.dart
import '../models/player_seat.dart';
import '../models/playing_card.dart';

enum DiscardEventKind { discard, pickup }

class DiscardEvent {
  const DiscardEvent({
    required this.seat,
    required this.card,
    required this.kind,
    required this.sequence,
  });
  final PlayerSeat seat;
  final HareegCard card;
  final DiscardEventKind kind;
  final int sequence; // monotonic within the round, useful for ordering
}

class DiscardHistory {
  DiscardHistory();

  // --- Append API (controller-only; package-private by convention) ---
  void recordDiscard(PlayerSeat seat, HareegCard card);
  void recordPickup(PlayerSeat seat, HareegCard card);
  /// Undo the most recently recorded event (used by retraction paths).
  /// Asserts the head matches the supplied seat+card+kind for safety.
  void retract({
    required PlayerSeat seat,
    required HareegCard card,
    required DiscardEventKind kind,
  });
  void resetForNewRound();

  // --- Read API (consumed by CpuObservation) ---
  /// Last [n] discards by [seat] this round, newest-first. Returns an
  /// `Iterable` backed by an internal per-seat ring buffer so the caller
  /// pays no allocation when iterating with a small `n`.
  Iterable<HareegCard> lastDiscardsBy(PlayerSeat seat, int n);

  /// Last [n] pickups by [seat] this round, newest-first.
  Iterable<HareegCard> lastPickupsBy(PlayerSeat seat, int n);

  /// Whether a card of (rank, suit) has appeared anywhere in the pile this
  /// round, regardless of seat or event kind. O(1).
  bool cardSeenAt(CardRank rank, CardSuit suit);

  /// Count of pile entries with this rank across the round. O(1).
  int discardsCount(CardRank rank);

  /// Full chronological event stream (oldest-first), for tests and debugging.
  Iterable<DiscardEvent> get events;
}
```

Internal storage:

- `final List<DiscardEvent> _events` — append-only chronological log.
- `final Map<PlayerSeat, List<int>> _discardIndicesBySeat` and
  `_pickupIndicesBySeat` — indices into `_events`, so `lastDiscardsBy` walks
  the tail of one small list rather than filtering the whole stream.
- `final List<int> _countsByRank` — `[CardRank.values.length]`, incremented on
  discard, decremented on `retract(discard)`. Powers both `discardsCount` and
  `cardSeenAt` (`countsByRank[rank.index] > 0` AND a `Set<String>` keyed by
  `CardIdentity.key` for suit-specific membership).

Jokers: `cardSeenAt(rank, suit)` only matches real cards whose
`identity.rank == rank && identity.suit == suit`. A joker contributes to
`discardsCount` only if a represented identity is meaningful — recommend
**not** counting jokers in rank totals; surface `jokersSeen` as a separate
counter if needed. (Open question 1.)

## 2. Where the Log Lives

A separate module, **composed by the controller**, in
`lib/domain/classic_hareeg/game/classic_hareeg_discard_history.dart` (sibling
to `classic_hareeg_turn_ledger.dart`). Reasoning:

- Lifecycle is identical to the controller's per-round state, so it lives in
  the `game/` folder, not `rules/` (it's not a rule, it's bookkeeping).
- It's NOT folded into the turn ledger: the turn ledger resets every turn
  (`resetForNewTurn()` at lines 669, 680, 701, 1325), whereas discard history
  must survive every turn boundary within a round.
- The controller exposes a read-only getter (`DiscardHistory get discardHistory`)
  for `CpuObservation` to consume; the mutating methods are only called from
  within the controller itself. Pure Dart, no Flutter — satisfies ADR 0001.

## 3. Update Hooks

All hooks are inside `classic_hareeg_game_controller.dart`. The history is
appended to on **exactly two state transitions** and retracted on **one**:

| Method | Line | Hook |
|---|---|---|
| `_applyDiscard` | ~1264 (append `_discardPile.add(card)` is at line 1303) | After `_discardPile.add(card)` and before `_previousDiscardSeat = _currentSeat`, call `_discardHistory.recordDiscard(_currentSeat, card)`. |
| `_applyTakePreviousDiscard` | ~673 | After `_applyTurnFlowState(next)` (which physically removes the top of the discard pile), call `_discardHistory.recordPickup(_currentSeat, takenCard)`. The taken card is `next.pendingDiscard!.card` (or `_pendingDiscard` after apply). |
| `_applyReturnPendingDiscard` | ~690 | The pending discard goes back on top of the pile via `ClassicHareegTurnFlowRules.returnPendingDiscard`. This is the **edge case**: the original `pickup` event must be **retracted**, restoring the prior state as if the take never happened. Call `_discardHistory.retract(seat: _currentSeat, card: pending, kind: DiscardEventKind.pickup)` after `_applyTurnFlowState(next)`. Do **not** record a fresh discard for the returned card — the original discarder of that card is preserved by `returnPendingDiscard` setting `previousDiscardSeat` back to `pending.fromSeat`, and the original `recordDiscard` event for that card is still in the log. |

Note: `_consumePendingDiscard` (line 1368, called from successful meld/cover
plays that consume the pickup) does NOT need a hook — the pickup event stays
valid; the card simply transitions from "briefly in hand" to "played to table".
The CPU's "live in opponent's hand" inference reading `lastPickupsBy` still
works because a *consumed* pickup is still informative ("they touched it"),
and CPUs already learn the consumption from the table-meld stream. (Open
question 2.)

## 4. Reset Semantics

The log resets **once per dealt round**, at the controller construction
boundary:

- `ClassicHareegGameController.fromRound` (line 76) constructs a fresh
  `DiscardHistory()` in its initializer list — empty.
- `ClassicHareegGameController._fromRestoredMatch` (line 122) either
  constructs a fresh empty `DiscardHistory()` (if not persisting; see §5) or
  rehydrates from snapshot fields.
- `nextRoundSnapshot()` (line 379) returns a `ClassicHareegMatchSnapshot` for
  a brand-new dealt round with an empty `discardPile`. When the host re-enters
  the engine via `fromSnapshot`, the new controller constructs a fresh
  `DiscardHistory`. **No explicit per-round reset method is called by the
  controller mid-life** — round boundaries always cross via controller
  construction, so the reset is structural, not procedural.

`resetForNewRound()` is exposed for tests and future direct-reuse scenarios
but is unused by production flow.

## 5. Persistence Stance

**Recommendation: do NOT persist `DiscardHistory` in
`ClassicHareegMatchSnapshot`.** Resume-with-fresh-memory is acceptable because:

- The snapshot already carries `discardPile` as an ordered list; on resume,
  the visible-cards baseline (`cardSeenAt`, `discardsCount`) could be
  re-derived from `discardPile` alone, since every card in the pile was at
  some point discarded.
- Per-seat attribution (`lastDiscardsBy`, `lastPickupsBy`) is **CPU memory**,
  not rule-relevant state. Losing it on resume affects only Skilled-tier
  decision quality for a few subsequent turns until the log re-fills, and
  does not affect legality, scoring, or game outcome.
- Snapshot v1 stays untouched; no schema version bump needed.

Tradeoff to flag: a player resuming mid-round against Skilled CPU will see
slightly weaker opponents for the first ~5-10 turns post-resume. This is
acceptable for v1; revisit if user testing reveals a noticeable regression.

Optional follow-up: on `fromSnapshot`, seed `_countsByRank` and the
`cardSeenAt` set from `snapshot.discardPile` so the rank/identity-membership
queries are accurate immediately on resume. Per-seat lists start empty.

## 6. Test Surface

New test file: `test/domain/classic_hareeg/game/classic_hareeg_discard_history_test.dart`.

- `lastDiscardsBy_returnsCardsInReverseChronologicalOrder` — North discards
  7S then 8S; `lastDiscardsBy(north, 2)` returns `[8S, 7S]`.
- `lastDiscardsBy_clampsToAvailableCount` — request 5, only 2 in log, returns 2.
- `lastPickupsBy_recordsTakePreviousDiscard` — East discards 9H, North takes
  it; `lastPickupsBy(north, 1)` returns `[9H]`.
- `retract_undoesPickupOnReturnPendingDiscard` — North takes 9H then returns
  it; `lastPickupsBy(north, 1)` is empty, `topDiscard` is 9H, original East
  discard event remains in `events`.
- `cardSeenAt_trueAfterDiscard_falseBeforeRound` — fresh controller: false;
  after a 5C discard: true; after `nextRoundSnapshot` + resume: false again.
- `discardsCount_aggregatesAcrossSeats` — 7S, 7H, 7D discarded by three
  different seats; `discardsCount(seven)` returns 3.
- `history_resetsOnNewRound` — finish round 1, transition to round 2 via
  `nextRoundSnapshot` + `fromSnapshot`, history is empty.

Plus a controller-level integration test that the consume-pending path
(meld using pickup) leaves the pickup event intact, vs. return-pending
retracts it.

## 7. Open Questions

1. **Joker accounting in `discardsCount` / `cardSeenAt`.** A joker on the
   pile has no real-card identity unless `representedIdentity` is set (which
   happens only when it was placed on a table meld and later... actually
   never, jokers don't end up on the discard pile representing anything).
   Recommend: jokers contribute to a separate `jokersDiscarded` counter and
   are excluded from rank/suit queries. Confirm before implementation.

2. **Pickup event after `_consumePendingDiscard`.** Should the pickup event
   be retracted, or marked "consumed"? Current recommendation: leave it as a
   pickup event (it informs the CPU that the seat touched that card) and let
   `CpuObservation` cross-reference with the table-meld stream to infer
   consumption. Alternative: add a third `DiscardEventKind.pickupConsumed`
   so consumers can filter.

3. **`discardsAdjacentToOpponentRunEnd`.** This query belongs in
   `CpuObservation`, not `DiscardHistory`. Rationale: it needs to join
   discard data with the opponent's *table melds* (run endpoints) and uses
   rank-arithmetic adjacency — both are higher-level concerns. `DiscardHistory`
   exposes the primitives (`lastDiscardsBy`, `cardSeenAt`); `CpuObservation`
   composes them with `tableMeldsFor(opponentSeat)` to compute adjacency.
   Calling this out so the sibling `CpuObservation` design agent owns it.

4. **Ring-buffer capacity.** Per-seat discard list grows up to ~15 entries in
   a long round; per-seat pickup list rarely exceeds 3-4. A bounded ring
   buffer (cap 16) would guarantee O(1) appends and `lastN` scans. Confirm
   that no consumer ever needs the full per-seat history beyond the last 16.
   If yes, use `List<DiscardEvent>` unbounded and accept O(n) for full scans
   (still cheap at round-size).

5. **Exposure surface.** Should the controller expose the full
   `DiscardHistory` getter, or only a narrow CPU-facing interface
   (`DiscardHistoryView`)? The narrow view prevents UI code from accidentally
   depending on CPU memory state. Recommend narrow view.
