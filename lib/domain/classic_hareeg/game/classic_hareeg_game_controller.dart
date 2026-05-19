import '../models/classic_hareeg_setup.dart';
import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../rules/classic_hareeg_rules.dart';
import '../rules/cover_rules.dart';
import '../rules/finish_rules.dart';
import '../rules/joker_rules.dart';
import '../rules/match_progression_rules.dart';
import 'classic_hareeg_match_snapshot.dart';
import 'classic_hareeg_round.dart';

/// Outcome of applying an action through the controller.
class ApplyActionResult {
  /// Creates an apply-action result.
  const ApplyActionResult({required this.isSuccess, required this.message});

  /// Successful result.
  const ApplyActionResult.success([this.message = ''])
    : isSuccess = true;

  /// Failed result with a player-facing explanation.
  const ApplyActionResult.failure(this.message) : isSuccess = false;

  /// Whether the action was accepted and applied.
  final bool isSuccess;

  /// Player-facing explanation for blocked or rejected actions.
  final String message;
}

/// Action ids used by [ClassicHareegGameController].
///
/// Discard action ids embed the physical card id after a colon. The prefix
/// segment carries the CPU-relevant tags `discard-blocked-cover:` or
/// `discard-joker:` when the discard is only legal under non-assisted presets,
/// matching the convention consumed by `ClassicHareegCpuStrategy`.
abstract final class ClassicHareegActionIds {
  /// Draw one card from stock.
  static const drawStock = 'draw-stock';

  /// Take the previous player's discard into pending state.
  static const takeDiscard = 'take-discard';

  /// Commit a pending discard as used (advances to discard phase).
  static const usePendingDiscard = 'use-pending-discard';

  /// Return a pending discard and draw from stock instead.
  static const returnPendingDiscard = 'return-pending-discard';

  /// Discard action id prefix for plain legal discards.
  static const discardPrefix = 'discard:';

  /// Discard action id prefix for cards that are covers (only legal as final
  /// discard, or under presets that allow cover discards with a penalty).
  static const discardBlockedCoverPrefix = 'discard-blocked-cover:';

  /// Discard action id prefix for jokers (only legal as final discard, or under
  /// presets that allow joker discards with a penalty).
  static const discardJokerPrefix = 'discard-joker:';

  /// Returns the card id encoded in a discard action id, if present.
  static String? discardCardId(String actionId) {
    for (final prefix in const [
      discardPrefix,
      discardBlockedCoverPrefix,
      discardJokerPrefix,
    ]) {
      if (actionId.startsWith(prefix)) {
        return actionId.substring(prefix.length);
      }
    }
    return null;
  }
}

/// Live Classic Hareeg game state controller.
///
/// Owns the dealt round + turn-flow state and exposes the rules-engine seam
/// described in [ADR 0001](../../../docs/adr/0001-rules-engine-boundary.md).
/// The Flutter UI and CPU strategy both interact with the game exclusively
/// through [legalActionIdsFor] and [applyAction]; this is the single point at
/// which moves are validated against the rules engine.
class ClassicHareegGameController {
  /// Creates a controller from a dealt round.
  ClassicHareegGameController.fromRound(ClassicHareegRound round)
    : setup = round.setup,
      rules = round.rules,
      _hands = {
        for (final entry in round.hands.entries)
          entry.key: List<HareegCard>.of(entry.value),
      },
      _stock = List<HareegCard>.of(round.stock),
      _discardPile = List<HareegCard>.of(round.discardPile),
      _starter = round.starter,
      _currentSeat = round.currentSeat,
      _phase = round.turnPhase,
      _pendingDiscard = null,
      _previousDiscardSeat = null,
      _roundOutcome = null {
    _evaluateRoundEnd();
  }

  /// Creates a controller restored from a persisted snapshot.
  ClassicHareegGameController.fromSnapshot(
    ClassicHareegMatchSnapshot snapshot, {
    ClassicHareegRules? rules,
  }) : setup = snapshot.setup,
       rules = rules ?? ClassicHareegRules.defaults(),
       _hands = {
         for (final entry in snapshot.hands.entries)
           entry.key: List<HareegCard>.of(entry.value),
       },
       _stock = List<HareegCard>.of(snapshot.stock),
       _discardPile = List<HareegCard>.of(snapshot.discardPile),
       _starter = snapshot.starter,
       _currentSeat = snapshot.currentSeat,
       _phase = snapshot.turnPhase,
       _pendingDiscard = snapshot.pendingDiscard,
       _previousDiscardSeat = snapshot.discardPile.isEmpty
           ? null
           : snapshot.currentSeat.previousAntiClockwise,
       _roundOutcome = null {
    _evaluateRoundEnd();
  }

  /// Setup values used to deal the active round.
  final ClassicHareegSetup setup;

  /// Rules active for this round.
  final ClassicHareegRules rules;

  final Map<PlayerSeat, List<HareegCard>> _hands;
  final List<HareegCard> _stock;
  final List<HareegCard> _discardPile;
  final PlayerSeat _starter;
  PlayerSeat _currentSeat;
  TurnPhase _phase;
  HareegCard? _pendingDiscard;
  PlayerSeat? _previousDiscardSeat;
  RoundOutcomeType? _roundOutcome;

  /// Seat that received 15 cards and starts in action phase.
  PlayerSeat get starter => _starter;

  /// Seat whose turn is active.
  PlayerSeat get currentSeat => _currentSeat;

  /// Current turn phase.
  TurnPhase get turnPhase => _phase;

  /// Pending discard awaiting use-or-return decision.
  HareegCard? get pendingDiscard => _pendingDiscard;

  /// Round outcome type, when the round has ended.
  RoundOutcomeType? get roundOutcome => _roundOutcome;

  /// Whether the active round has ended.
  bool get isRoundOver => _roundOutcome != null;

  /// Live card count for a seat.
  int cardCountFor(PlayerSeat seat) => _hands[seat]?.length ?? 0;

  /// Live read-only hand for a seat.
  List<HareegCard> handFor(PlayerSeat seat) {
    return List.unmodifiable(_hands[seat] ?? const []);
  }

  /// Live stock count.
  int get stockCount => _stock.length;

  /// Live top of discard pile, or null when empty.
  HareegCard? get topDiscard => _discardPile.isEmpty ? null : _discardPile.last;

  /// Snapshots the live game state for persistence.
  ClassicHareegMatchSnapshot toSnapshot({DateTime? savedAt}) {
    return ClassicHareegMatchSnapshot(
      setup: setup,
      hands: {
        for (final entry in _hands.entries)
          entry.key: List<HareegCard>.of(entry.value),
      },
      stock: List<HareegCard>.of(_stock),
      discardPile: List<HareegCard>.of(_discardPile),
      starter: _starter,
      currentSeat: _currentSeat,
      turnPhase: _phase,
      pendingDiscard: _pendingDiscard,
      savedAt: savedAt ?? DateTime.now().toUtc(),
    );
  }

  /// Returns the legal action ids for [seat] under the current state.
  ///
  /// Empty when the round has ended, when it is not the seat's turn, or when
  /// the seat has no legal action remaining (e.g. stock exhaustion that the
  /// controller has not yet converted to a [RoundOutcomeType.draw] outcome).
  List<String> legalActionIdsFor(PlayerSeat seat) {
    if (_roundOutcome != null || seat != _currentSeat) {
      return const [];
    }

    if (_pendingDiscard != null) {
      return List.unmodifiable([
        ClassicHareegActionIds.usePendingDiscard,
        if (_stock.isNotEmpty) ClassicHareegActionIds.returnPendingDiscard,
      ]);
    }

    if (_phase == TurnPhase.action) {
      return _discardActionIds(seat);
    }

    final ids = <String>[];
    if (_stock.isNotEmpty) {
      ids.add(ClassicHareegActionIds.drawStock);
    }
    if (_canTakePreviousDiscard) {
      ids.add(ClassicHareegActionIds.takeDiscard);
    }
    return List.unmodifiable(ids);
  }

  /// Applies an action through the rules engine.
  ///
  /// Returns [ApplyActionResult.success] when the action was legal and applied.
  /// Returns [ApplyActionResult.failure] when the action id is unknown or the
  /// action is illegal under the current rule state.
  ApplyActionResult applyAction(String actionId) {
    if (_roundOutcome != null) {
      return const ApplyActionResult.failure('Round has ended.');
    }

    if (!legalActionIdsFor(_currentSeat).contains(actionId)) {
      return ApplyActionResult.failure(
        'Action "$actionId" is not legal right now.',
      );
    }

    switch (actionId) {
      case ClassicHareegActionIds.drawStock:
        return _applyDrawStock();
      case ClassicHareegActionIds.takeDiscard:
        return _applyTakePreviousDiscard();
      case ClassicHareegActionIds.usePendingDiscard:
        return _applyUsePendingDiscard();
      case ClassicHareegActionIds.returnPendingDiscard:
        return _applyReturnPendingDiscard();
    }

    final discardCardId = ClassicHareegActionIds.discardCardId(actionId);
    if (discardCardId != null) {
      return _applyDiscard(discardCardId);
    }

    return ApplyActionResult.failure('Unknown action "$actionId".');
  }

  /// Sorts the seat's hand by suit and rank. Pure UI ergonomics; does not
  /// affect any rule decision.
  void sortHandFor(PlayerSeat seat) {
    final hand = _hands[seat];
    if (hand == null) {
      return;
    }
    hand.sort(_compareCards);
  }

  ApplyActionResult _applyDrawStock() {
    final drawn = _stock.removeLast();
    _handFor(_currentSeat).add(drawn);
    _phase = TurnPhase.action;
    return const ApplyActionResult.success();
  }

  ApplyActionResult _applyTakePreviousDiscard() {
    final card = _discardPile.removeLast();
    _handFor(_currentSeat).add(card);
    _pendingDiscard = card;
    _phase = TurnPhase.action;
    return const ApplyActionResult.success();
  }

  ApplyActionResult _applyUsePendingDiscard() {
    _pendingDiscard = null;
    _phase = TurnPhase.action;
    return const ApplyActionResult.success();
  }

  ApplyActionResult _applyReturnPendingDiscard() {
    final pending = _pendingDiscard!;
    final hand = _handFor(_currentSeat);
    hand.removeWhere((card) => card.id == pending.id);
    hand.add(_stock.removeLast());
    _discardPile.add(pending);
    _pendingDiscard = null;
    _phase = TurnPhase.action;
    return const ApplyActionResult.success();
  }

  ApplyActionResult _applyDiscard(String cardId) {
    final hand = _handFor(_currentSeat);
    final index = hand.indexWhere((card) => card.id == cardId);
    if (index == -1) {
      return ApplyActionResult.failure('Card "$cardId" is not in the hand.');
    }

    final card = hand[index];
    if (!ClassicHareegJokerRules.canDiscard(card, isFinalDiscard: false)) {
      return const ApplyActionResult.failure(
        'Jokers cannot be discarded during normal play.',
      );
    }

    final coverResult = ClassicHareegCoverRules.canDiscard(
      tableMelds: const [],
      candidate: card,
      isFinalDiscard: false,
    );
    if (!coverResult.canDiscard) {
      return ApplyActionResult.failure(coverResult.message);
    }

    hand.removeAt(index);
    _discardPile.add(card);
    _previousDiscardSeat = _currentSeat;
    _pendingDiscard = null;
    _currentSeat = _currentSeat.nextAntiClockwise;
    _phase = TurnPhase.draw;
    _evaluateRoundEnd();
    return const ApplyActionResult.success();
  }

  List<HareegCard> _handFor(PlayerSeat seat) {
    return _hands.putIfAbsent(seat, () => <HareegCard>[]);
  }

  void _evaluateRoundEnd() {
    if (_roundOutcome != null || _phase != TurnPhase.draw) {
      return;
    }

    final exhaustion = ClassicHareegFinishRules.evaluateStockExhaustion(
      stockIsEmpty: _stock.isEmpty,
      previousDiscardCanFinish: false,
      pickupWouldFinish: false,
    );
    if (exhaustion.decision == StockExhaustionDecision.roundDraw) {
      _roundOutcome = RoundOutcomeType.draw;
    }
  }

  bool get _canTakePreviousDiscard {
    final previousSeat = _previousDiscardSeat;
    return _phase == TurnPhase.draw &&
        previousSeat != null &&
        _discardPile.isNotEmpty &&
        previousSeat.nextAntiClockwise == _currentSeat;
  }

  List<String> _discardActionIds(PlayerSeat seat) {
    final hand = _hands[seat] ?? const <HareegCard>[];
    final ids = <String>[];
    for (final card in hand) {
      if (!ClassicHareegJokerRules.canDiscard(card, isFinalDiscard: false)) {
        continue;
      }
      final coverResult = ClassicHareegCoverRules.canDiscard(
        tableMelds: const [],
        candidate: card,
        isFinalDiscard: false,
      );
      if (!coverResult.canDiscard) {
        continue;
      }
      ids.add('${ClassicHareegActionIds.discardPrefix}${card.id}');
    }
    return List.unmodifiable(ids);
  }
}

/// Inverse of [PlayerSeat.nextAntiClockwise] used when restoring discard state
/// from a snapshot that doesn't record the discarding seat.
extension on PlayerSeat {
  PlayerSeat get previousAntiClockwise {
    return switch (this) {
      PlayerSeat.south => PlayerSeat.west,
      PlayerSeat.east => PlayerSeat.south,
      PlayerSeat.north => PlayerSeat.east,
      PlayerSeat.west => PlayerSeat.north,
    };
  }
}

/// Sorts a hand by suit + rank with jokers last via null-identity sort.
int _compareCards(HareegCard left, HareegCard right) {
  final leftIdentity = left.effectiveIdentity;
  final rightIdentity = right.effectiveIdentity;
  if (leftIdentity == null && rightIdentity == null) {
    return left.id.compareTo(right.id);
  }
  if (leftIdentity == null) {
    return 1;
  }
  if (rightIdentity == null) {
    return -1;
  }

  final suitCompare = leftIdentity.suit.index.compareTo(
    rightIdentity.suit.index,
  );
  if (suitCompare != 0) {
    return suitCompare;
  }
  return leftIdentity.rank.order.compareTo(rightIdentity.rank.order);
}
