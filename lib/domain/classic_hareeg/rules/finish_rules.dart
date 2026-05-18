import '../models/playing_card.dart';
import 'opening_rules.dart';

/// Source of the card that enabled a finish.
enum FinishCardSource {
  /// Finish came after a stock draw.
  stock,

  /// Finish came after taking the previous discard.
  previousDiscard,
}

/// Stock exhaustion decision.
enum StockExhaustionDecision {
  /// Stock still has cards, normal play continues.
  continuePlay,

  /// Round ends as a draw.
  roundDraw,

  /// Only an immediate finishing discard pickup may continue.
  finishOnly,
}

/// Result of a finish validation.
class FinishValidationResult {
  /// Creates a finish validation result.
  const FinishValidationResult({
    required this.isValid,
    required this.message,
    required this.playedCards,
    required this.source,
    this.finalDiscard,
    this.perfectHandBypass = false,
  });

  /// Whether the finish shape is legal.
  final bool isValid;

  /// Player-facing explanation.
  final String message;

  /// Cards played before the final discard.
  final List<HareegCard> playedCards;

  /// Exactly one final discard when valid.
  final HareegCard? finalDiscard;

  /// Whether an unopened player bypassed opening by finishing the full hand.
  final bool perfectHandBypass;

  /// Source of the finishing turn card.
  final FinishCardSource source;
}

/// Result of stock exhaustion handling.
class StockExhaustionResult {
  /// Creates a stock exhaustion result.
  const StockExhaustionResult({required this.decision, required this.message});

  /// Decision for an empty-stock state.
  final StockExhaustionDecision decision;

  /// Player-facing explanation.
  final String message;
}

/// Classic Hareeg finish and empty-stock rules.
abstract final class ClassicHareegFinishRules {
  /// Validates a finish as played melds plus exactly one final discard.
  static FinishValidationResult validateFinish({
    required List<PlacedMeld> playedMelds,
    required HareegCard? finalDiscard,
    required bool playerOpened,
    required FinishCardSource source,
    bool perfectHandAttempt = false,
  }) {
    final playedCards = [for (final meld in playedMelds) ...meld.cards];

    if (finalDiscard == null) {
      return FinishValidationResult(
        isValid: false,
        message: 'A finish needs exactly one final discard.',
        playedCards: List.unmodifiable(playedCards),
        source: source,
      );
    }

    if (playedMelds.isEmpty) {
      return FinishValidationResult(
        isValid: false,
        message: 'A finish needs played cards before the final discard.',
        playedCards: const [],
        finalDiscard: finalDiscard,
        source: source,
      );
    }

    if (!playerOpened && !perfectHandAttempt) {
      return FinishValidationResult(
        isValid: false,
        message: 'Unopened players must open or finish a perfect hand.',
        playedCards: List.unmodifiable(playedCards),
        finalDiscard: finalDiscard,
        source: source,
      );
    }

    return FinishValidationResult(
      isValid: true,
      message: perfectHandAttempt
          ? 'Perfect hand finish bypasses opening.'
          : 'Valid finish.',
      playedCards: List.unmodifiable(playedCards),
      finalDiscard: finalDiscard,
      perfectHandBypass: perfectHandAttempt && !playerOpened,
      source: source,
    );
  }

  /// Handles stock exhaustion without recycling the discard pile.
  static StockExhaustionResult evaluateStockExhaustion({
    required bool stockIsEmpty,
    required bool previousDiscardCanFinish,
    required bool pickupWouldFinish,
  }) {
    if (!stockIsEmpty) {
      return const StockExhaustionResult(
        decision: StockExhaustionDecision.continuePlay,
        message: 'Stock still has cards.',
      );
    }

    if (previousDiscardCanFinish && pickupWouldFinish) {
      return const StockExhaustionResult(
        decision: StockExhaustionDecision.finishOnly,
        message: 'Only an immediate finish may continue after empty stock.',
      );
    }

    return const StockExhaustionResult(
      decision: StockExhaustionDecision.roundDraw,
      message: 'Stock is empty; round ends as a draw.',
    );
  }
}
