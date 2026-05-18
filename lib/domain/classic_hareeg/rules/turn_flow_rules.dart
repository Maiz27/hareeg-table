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

  /// Legal action ids for the current draw/take state.
  List<String> get legalActionIds {
    if (pendingDiscard != null) {
      return const ['use-pending-discard', 'return-pending-discard'];
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
    final previousSeat = previousDiscardSeat;
    return phase == ClassicTurnPhase.draw &&
        previousSeat != null &&
        discardPile.isNotEmpty &&
        previousSeat.nextAntiClockwise == currentSeat;
  }
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
    );
  }

  /// Returns the pending discard and draws from stock instead.
  static ClassicTurnFlowState returnPendingDiscardAndDraw(
    ClassicTurnFlowState state,
  ) {
    final pending = state.pendingDiscard;
    if (pending == null) {
      throw StateError('No pending discard to return.');
    }
    if (state.stock.isEmpty) {
      throw StateError('Stock is empty.');
    }

    final hand = List<HareegCard>.of(state.hand)
      ..removeWhere((card) => card.id == pending.card.id);
    final stock = List<HareegCard>.of(state.stock);
    final drawn = stock.removeLast();

    return ClassicTurnFlowState(
      currentSeat: state.currentSeat,
      phase: ClassicTurnPhase.action,
      hand: List.unmodifiable([...hand, drawn]),
      stock: List.unmodifiable(stock),
      discardPile: List.unmodifiable([...state.discardPile, pending.card]),
      previousDiscardSeat: pending.fromSeat,
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
