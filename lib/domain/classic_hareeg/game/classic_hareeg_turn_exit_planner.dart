import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../rules/fifty_rules.dart';
import '../rules/finish_rules.dart';
import '../rules/match_progression_rules.dart';
import 'classic_hareeg_round.dart';

/// Planned state change after a successful discard.
class ClassicHareegDiscardExit {
  /// Creates a discard-exit plan.
  const ClassicHareegDiscardExit({
    required this.fiftyWindow,
    this.nextSeat,
    this.nextPhase,
    this.roundResult,
  });

  /// Fifty window opened by the discard.
  final FiftyClaimWindow fiftyWindow;

  /// Next active seat when the round continues.
  final PlayerSeat? nextSeat;

  /// Next phase when the round continues.
  final TurnPhase? nextPhase;

  /// Round result when the discard ends the round.
  final RoundProgressResult? roundResult;
}

/// Planned state change after a hard-table removal.
class ClassicHareegMistakeExit {
  /// Creates a mistake-exit plan.
  const ClassicHareegMistakeExit({
    this.nextSeat,
    this.nextPhase,
    this.roundResult,
  });

  /// Next active seat when the round continues.
  final PlayerSeat? nextSeat;

  /// Next phase when the round continues.
  final TurnPhase? nextPhase;

  /// Round result when the removal ends the round.
  final RoundProgressResult? roundResult;
}

/// Plans turn exits, player removal, and round-ending transitions.
abstract final class ClassicHareegTurnExitPlanner {
  /// Seats still active in the current round.
  static List<PlayerSeat> roundActiveSeats({
    required Iterable<PlayerSeat> activeSeats,
    required Set<PlayerSeat> removedSeats,
  }) {
    return List.unmodifiable([
      for (final seat in activeSeats)
        if (!removedSeats.contains(seat)) seat,
    ]);
  }

  /// Next active seat in Classic Hareeg's anti-clockwise order.
  static PlayerSeat nextActiveSeat({
    required PlayerSeat seat,
    required Iterable<PlayerSeat> activeSeats,
    required Set<PlayerSeat> removedSeats,
  }) {
    final seats = roundActiveSeats(
      activeSeats: activeSeats,
      removedSeats: removedSeats,
    );
    if (seats.isEmpty) {
      return seat.nextAntiClockwise;
    }

    var next = seat.nextAntiClockwise;
    while (next != seat) {
      if (seats.contains(next)) {
        return next;
      }
      next = next.nextAntiClockwise;
    }
    return seat;
  }

  /// Whether the current draw-phase player may take the top discard.
  ///
  /// Authoritative version that walks past removed seats. The narrower check
  /// inside `ClassicTurnFlowState` (`turn_flow_rules.dart`) does not know about
  /// removed seats and is therefore correct only when no one has been removed
  /// mid-round — callers exposed to elimination should consult this planner
  /// before reaching the rules-layer apply path.
  static bool canTakePreviousDiscard({
    required PlayerSeat currentSeat,
    required TurnPhase phase,
    required PlayerSeat? previousDiscardSeat,
    required bool discardPileIsNotEmpty,
    required Iterable<PlayerSeat> activeSeats,
    required Set<PlayerSeat> removedSeats,
  }) {
    final previousSeat = previousDiscardSeat;
    return phase == TurnPhase.draw &&
        previousSeat != null &&
        discardPileIsNotEmpty &&
        nextActiveSeat(
              seat: previousSeat,
              activeSeats: activeSeats,
              removedSeats: removedSeats,
            ) ==
            currentSeat;
  }

  /// Builds the persisted round result.
  static RoundProgressResult roundResult({
    required RoundOutcomeType type,
    required Map<PlayerSeat, int> remainingCardCounts,
    PlayerSeat? winner,
    PlayerSeat? fiftyDiscarder,
    bool firstRoundFiftyException = false,
  }) {
    return RoundProgressResult(
      type: type,
      winner: winner,
      fiftyDiscarder: fiftyDiscarder,
      firstRoundFiftyException: firstRoundFiftyException,
      remainingCardCounts: remainingCardCounts,
    );
  }

  /// Plans the transition after a successful discard.
  static ClassicHareegDiscardExit afterDiscard({
    required PlayerSeat discarder,
    required HareegCard discardedCard,
    required bool isFinalDiscard,
    required Iterable<PlayerSeat> activeSeats,
    required Set<PlayerSeat> removedSeats,
    required int roundNumber,
    required int fiftyTimerSeconds,
    required Map<PlayerSeat, int> remainingCardCounts,
  }) {
    final nextSeat = nextActiveSeat(
      seat: discarder,
      activeSeats: activeSeats,
      removedSeats: removedSeats,
    );
    final window = ClassicHareegFiftyRules.openWindow(
      discarder: discarder,
      claimant: isFinalDiscard ? null : nextSeat,
      discardedCard: discardedCard,
      durationSeconds: fiftyTimerSeconds,
      isFirstDealtRound: roundNumber == 1,
    );

    if (isFinalDiscard) {
      return ClassicHareegDiscardExit(
        fiftyWindow: window,
        roundResult: roundResult(
          type: RoundOutcomeType.normalFinish,
          winner: discarder,
          remainingCardCounts: remainingCardCounts,
        ),
      );
    }

    return ClassicHareegDiscardExit(
      fiftyWindow: window,
      nextSeat: nextSeat,
      nextPhase: TurnPhase.draw,
    );
  }

  /// Plans whether empty stock ends a draw phase.
  static RoundProgressResult? stockExhaustionRoundResult({
    required bool stockIsEmpty,
    required bool previousDiscardCanFinish,
    required bool pickupWouldFinish,
    required Map<PlayerSeat, int> remainingCardCounts,
  }) {
    final exhaustion = ClassicHareegFinishRules.evaluateStockExhaustion(
      stockIsEmpty: stockIsEmpty,
      previousDiscardCanFinish: previousDiscardCanFinish,
      pickupWouldFinish: pickupWouldFinish,
    );
    if (exhaustion.decision != StockExhaustionDecision.roundDraw) {
      return null;
    }
    return roundResult(
      type: RoundOutcomeType.draw,
      remainingCardCounts: remainingCardCounts,
    );
  }

  /// Plans the transition after a mistake removes a player from the round.
  static ClassicHareegMistakeExit afterPlayerRemoval({
    required PlayerSeat removedSeat,
    required Iterable<PlayerSeat> activeSeats,
    required Set<PlayerSeat> removedSeats,
    required Map<PlayerSeat, int> remainingCardCounts,
  }) {
    final remaining = roundActiveSeats(
      activeSeats: activeSeats,
      removedSeats: removedSeats,
    );
    if (remaining.length == 1) {
      return ClassicHareegMistakeExit(
        roundResult: roundResult(
          type: RoundOutcomeType.normalFinish,
          winner: remaining.single,
          remainingCardCounts: remainingCardCounts,
        ),
      );
    }
    if (remaining.isEmpty) {
      return const ClassicHareegMistakeExit();
    }
    return ClassicHareegMistakeExit(
      nextSeat: nextActiveSeat(
        seat: removedSeat,
        activeSeats: activeSeats,
        removedSeats: removedSeats,
      ),
      nextPhase: TurnPhase.draw,
    );
  }
}
