import '../models/player_seat.dart';
import '../models/playing_card.dart';
import 'finish_rules.dart';
import 'opening_rules.dart';

/// Timed Fifty claim window after a discard.
class FiftyClaimWindow {
  /// Creates a Fifty claim window.
  const FiftyClaimWindow({
    required this.discarder,
    required this.claimant,
    required this.discardedCard,
    required this.durationSeconds,
    this.isFirstDealtRound = false,
  });

  /// Seat that discarded the card.
  final PlayerSeat discarder;

  /// Immediate next player eligible to claim Fifty.
  final PlayerSeat claimant;

  /// Discarded card that must be used in the finishing sequence.
  final HareegCard discardedCard;

  /// Configured timer window in seconds.
  final int durationSeconds;

  /// Whether first dealt round scoring exception applies.
  final bool isFirstDealtRound;

  /// Whether the timer has expired at elapsed seconds.
  bool isExpired(int elapsedSeconds) {
    return elapsedSeconds >= durationSeconds;
  }
}

/// Result of checking or claiming Fifty.
class FiftyClaimResult {
  /// Creates a Fifty claim result.
  const FiftyClaimResult({
    required this.isValid,
    required this.message,
    required this.firstRoundException,
  });

  /// Whether the claim is legal.
  final bool isValid;

  /// Player-facing explanation.
  final String message;

  /// Whether scoring should use the first-round -1 exception.
  final bool firstRoundException;
}

/// Classic Hareeg Fifty / Khamsin claim rules.
abstract final class ClassicHareegFiftyRules {
  /// Creates a claim window for the immediate next player.
  static FiftyClaimWindow openWindow({
    required PlayerSeat discarder,
    PlayerSeat? claimant,
    required HareegCard discardedCard,
    required int durationSeconds,
    bool isFirstDealtRound = false,
  }) {
    return FiftyClaimWindow(
      discarder: discarder,
      claimant: claimant ?? discarder.nextAntiClockwise,
      discardedCard: discardedCard,
      durationSeconds: durationSeconds,
      isFirstDealtRound: isFirstDealtRound,
    );
  }

  /// Whether assisted/default UI should show the Fifty action.
  static bool shouldShowAssistedAction({
    required FiftyClaimWindow window,
    required PlayerSeat viewer,
    required int elapsedSeconds,
    required List<PlacedMeld> finishingMelds,
    required HareegCard finalDiscard,
  }) {
    return validateClaim(
      window: window,
      claimant: viewer,
      elapsedSeconds: elapsedSeconds,
      finishingMelds: finishingMelds,
      finalDiscard: finalDiscard,
    ).isValid;
  }

  /// Validates an explicit Fifty claim.
  static FiftyClaimResult validateClaim({
    required FiftyClaimWindow window,
    required PlayerSeat claimant,
    required int elapsedSeconds,
    required List<PlacedMeld> finishingMelds,
    required HareegCard finalDiscard,
  }) {
    if (claimant != window.claimant) {
      return const FiftyClaimResult(
        isValid: false,
        message: 'Only the immediate next player can claim Fifty.',
        firstRoundException: false,
      );
    }

    if (window.isExpired(elapsedSeconds)) {
      return const FiftyClaimResult(
        isValid: false,
        message: 'Fifty timer expired.',
        firstRoundException: false,
      );
    }

    final usesDiscard = finishingMelds.any((meld) {
      return meld.cards.any((card) => card.id == window.discardedCard.id);
    });
    if (!usesDiscard) {
      return const FiftyClaimResult(
        isValid: false,
        message: 'Fifty must use the discarded card in the finish.',
        firstRoundException: false,
      );
    }

    final finish = ClassicHareegFinishRules.validateFinish(
      playedMelds: finishingMelds,
      finalDiscard: finalDiscard,
      playerOpened: true,
      source: FinishCardSource.previousDiscard,
      perfectHandAttempt: true,
    );
    if (!finish.isValid) {
      return FiftyClaimResult(
        isValid: false,
        message: finish.message,
        firstRoundException: false,
      );
    }

    return FiftyClaimResult(
      isValid: true,
      message: 'Valid Fifty.',
      firstRoundException: window.isFirstDealtRound,
    );
  }

  /// After timer expiry, normal discard pickup remains available if legal.
  static bool canTakeNormallyAfterMiss({
    required FiftyClaimWindow window,
    required PlayerSeat player,
    required int elapsedSeconds,
  }) {
    return window.isExpired(elapsedSeconds) && player == window.claimant;
  }
}
