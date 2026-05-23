import '../models/player_seat.dart';
import '../models/playing_card.dart';
import 'opening_rules.dart';

/// Phase within a Classic Hareeg turn.
enum ClassicTurnPhase {
  /// Player must draw from stock or take the previous discard.
  draw,

  /// Player may play cards and then discard.
  action,
}

/// Pending discard picked up by the immediate next player.
class PendingDiscard {
  /// Creates pending discard state.
  const PendingDiscard({required this.card, required this.fromSeat});

  /// Picked up discard card.
  final HareegCard card;

  /// Seat that discarded the card.
  final PlayerSeat fromSeat;
}

/// Small immutable state for draw/take phase behavior.
class ClassicTurnFlowState {
  /// Creates a turn-flow state.
  const ClassicTurnFlowState({
    required this.currentSeat,
    required this.phase,
    required this.hand,
    required this.stock,
    required this.discardPile,
    this.previousDiscardSeat,
    this.pendingDiscard,
    this.activeSeats = PlayerSeat.values,
    this.removedSeats = const {},
  });

  /// Active seat.
  final PlayerSeat currentSeat;

  /// Current turn phase.
  final ClassicTurnPhase phase;

  /// Active player's hand.
  final List<HareegCard> hand;

  /// Stock pile.
  final List<HareegCard> stock;

  /// Discard pile.
  final List<HareegCard> discardPile;

  /// Seat that placed the current top discard.
  final PlayerSeat? previousDiscardSeat;

  /// Pending discard that must be used or returned.
  final PendingDiscard? pendingDiscard;

  /// Seats still active in the round (defaults to all four).
  final Iterable<PlayerSeat> activeSeats;

  /// Seats removed mid-round by hard-table mistakes. Walked past when
  /// resolving anti-clockwise pickup eligibility.
  final Set<PlayerSeat> removedSeats;

  /// Legal action ids for the current draw/take state.
  List<String> get legalActionIds {
    if (pendingDiscard != null) {
      return ['use-pending-discard', 'return-pending-discard'];
    }
    if (phase == ClassicTurnPhase.action) {
      return const ['play-meld', 'discard'];
    }

    final actions = <String>[];
    if (stock.isNotEmpty) {
      actions.add('draw-stock');
    }
    if (_canTakePreviousDiscard) {
      actions.add('take-discard');
    }
    return List.unmodifiable(actions);
  }

  bool get _canTakePreviousDiscard {
    return phase == ClassicTurnPhase.draw &&
        discardPile.isNotEmpty &&
        isPickupSeatEligible(
          currentSeat: currentSeat,
          previousDiscardSeat: previousDiscardSeat,
          activeSeats: activeSeats,
          removedSeats: removedSeats,
        );
  }
}

/// Returns whether anti-clockwise seat order (walking past [removedSeats])
/// makes [currentSeat] the immediate next eligible pickup target after
/// [previousDiscardSeat].
///
/// Single source of truth shared by [ClassicTurnFlowState] and the controller-
/// side turn exit planner. Phase- and pile-emptiness-agnostic; callers pre-
/// gate on those before consulting this primitive.
bool isPickupSeatEligible({
  required PlayerSeat currentSeat,
  required PlayerSeat? previousDiscardSeat,
  required Iterable<PlayerSeat> activeSeats,
  required Set<PlayerSeat> removedSeats,
}) {
  final previousSeat = previousDiscardSeat;
  if (previousSeat == null) {
    return false;
  }
  final remaining = <PlayerSeat>{
    for (final seat in activeSeats)
      if (!removedSeats.contains(seat)) seat,
  };
  if (remaining.isEmpty) {
    return false;
  }
  var next = previousSeat.nextAntiClockwise;
  while (next != previousSeat) {
    if (remaining.contains(next)) {
      return next == currentSeat;
    }
    next = next.nextAntiClockwise;
  }
  return false;
}

/// Classic Hareeg draw, previous discard pickup, and pending discard rules.
abstract final class ClassicHareegTurnFlowRules {
  /// Draws one stock card and moves into action phase.
  static ClassicTurnFlowState drawStock(ClassicTurnFlowState state) {
    if (state.phase != ClassicTurnPhase.draw || state.pendingDiscard != null) {
      throw StateError('Stock can only be drawn at the start of a turn.');
    }
    if (state.stock.isEmpty) {
      throw StateError('Stock is empty.');
    }

    final stock = List<HareegCard>.of(state.stock);
    final drawn = stock.removeLast();
    return ClassicTurnFlowState(
      currentSeat: state.currentSeat,
      phase: ClassicTurnPhase.action,
      hand: List.unmodifiable([...state.hand, drawn]),
      stock: List.unmodifiable(stock),
      discardPile: state.discardPile,
      previousDiscardSeat: state.previousDiscardSeat,
      activeSeats: state.activeSeats,
      removedSeats: state.removedSeats,
    );
  }

  /// Takes the previous player's top discard into pending state.
  static ClassicTurnFlowState takePreviousDiscard(ClassicTurnFlowState state) {
    if (!state._canTakePreviousDiscard) {
      throw StateError('Only the immediate next player can take that discard.');
    }

    final discardPile = List<HareegCard>.of(state.discardPile);
    final discard = discardPile.removeLast();
    return ClassicTurnFlowState(
      currentSeat: state.currentSeat,
      phase: ClassicTurnPhase.action,
      hand: List.unmodifiable([...state.hand, discard]),
      stock: state.stock,
      discardPile: List.unmodifiable(discardPile),
      previousDiscardSeat: state.previousDiscardSeat,
      pendingDiscard: PendingDiscard(
        card: discard,
        fromSeat: state.previousDiscardSeat!,
      ),
      activeSeats: state.activeSeats,
      removedSeats: state.removedSeats,
    );
  }

  /// Returns the pending discard and moves back to draw/take decision state.
  static ClassicTurnFlowState returnPendingDiscard(ClassicTurnFlowState state) {
    final pending = state.pendingDiscard;
    if (pending == null) {
      throw StateError('No pending discard to return.');
    }

    final hand = List<HareegCard>.of(state.hand);
    final pendingIndex = hand.indexWhere((card) => card.id == pending.card.id);
    if (pendingIndex == -1) {
      throw StateError('Pending discard is not in the player hand.');
    }
    hand.removeAt(pendingIndex);

    return ClassicTurnFlowState(
      currentSeat: state.currentSeat,
      phase: ClassicTurnPhase.draw,
      hand: List.unmodifiable(hand),
      stock: state.stock,
      discardPile: List.unmodifiable([...state.discardPile, pending.card]),
      previousDiscardSeat: pending.fromSeat,
      activeSeats: state.activeSeats,
      removedSeats: state.removedSeats,
    );
  }

  /// Marks the pending discard as legally used.
  static ClassicTurnFlowState usePendingDiscard(ClassicTurnFlowState state) {
    if (state.pendingDiscard == null) {
      throw StateError('No pending discard to use.');
    }

    return ClassicTurnFlowState(
      currentSeat: state.currentSeat,
      phase: ClassicTurnPhase.action,
      hand: state.hand,
      stock: state.stock,
      discardPile: state.discardPile,
      previousDiscardSeat: state.previousDiscardSeat,
      activeSeats: state.activeSeats,
      removedSeats: state.removedSeats,
    );
  }

  /// Checks whether pending discard use can satisfy an opening attempt.
  static bool canUsePendingDiscardToOpen({
    required ClassicTurnFlowState turnState,
    required OpeningState openingState,
    required List<PlacedMeld> openingMelds,
  }) {
    final pending = turnState.pendingDiscard;
    if (pending == null) {
      return false;
    }

    final usesPending = openingMelds.any((meld) {
      return meld.cards.any((card) => card.id == pending.card.id);
    });
    if (!usesPending) {
      return false;
    }

    return ClassicHareegOpeningRules.validateOpening(
      state: openingState,
      seat: turnState.currentSeat,
      melds: openingMelds,
    ).isValid;
  }
}
