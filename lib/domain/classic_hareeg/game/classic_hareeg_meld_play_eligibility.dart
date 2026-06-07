import '../models/player_seat.dart';
import '../rules/opening_rules.dart';

/// Named outcome for a proposed meld play from the current hand.
enum ClassicHareegMeldPlayScenario {
  /// Player has already opened and may place another valid meld.
  regularMeld,

  /// Player has not opened yet and this play completes the opening value.
  openingComplete,

  /// Player has not opened yet and this play can be staged with more melds.
  openingPartial,

  /// Player has not opened yet, is below opening value, but keeps one discard.
  openingFinishCandidate,

  /// This play would leave no card for the required final discard.
  noFinalDiscard,
}

/// Complete legality and advertisement decision for a meld play.
class ClassicHareegMeldPlayEligibility {
  /// Creates a meld-play eligibility result.
  const ClassicHareegMeldPlayEligibility({
    required this.scenario,
    required this.isAllowed,
    required this.shouldAdvertise,
    required this.message,
    required this.opensPlayer,
    required this.leavesFinalDiscard,
    this.opening,
  });

  /// Identified game-flow scenario.
  final ClassicHareegMeldPlayScenario scenario;

  /// Whether applying the selected valid meld cards may proceed.
  final bool isAllowed;

  /// Whether this meld play should appear in legal action ids.
  final bool shouldAdvertise;

  /// Player-facing explanation for the decision.
  final String message;

  /// Whether applying this play should mark the player as opened.
  final bool opensPlayer;

  /// Whether the play leaves exactly one card available as final discard.
  final bool leavesFinalDiscard;

  /// Opening validation result when the player has not opened yet.
  final OpeningValidationResult? opening;
}

/// Resolves meld play legality as one rich scenario.
abstract final class ClassicHareegMeldPlayEligibilityPlanner {
  /// Evaluates a proposed table meld play after card-shape validation.
  ///
  /// A picked-up discard no longer constrains which melds may be played: the
  /// relaxed taken-discard rule lets the pending card land in any play of the
  /// turn, so melds that do not include it are legal. The controller blocks
  /// the turn from ending while the pending card sits unused.
  static ClassicHareegMeldPlayEligibility evaluate({
    required OpeningState openingState,
    required PlayerSeat seat,
    required Iterable<PlacedMeld> stagedOpeningMelds,
    required Iterable<PlacedMeld> playedMelds,
    required int handCount,
    required Set<String> playedCardIds,
  }) {
    final remainingCards = handCount - playedCardIds.length;
    if (remainingCards <= 0) {
      return const ClassicHareegMeldPlayEligibility(
        scenario: ClassicHareegMeldPlayScenario.noFinalDiscard,
        isAllowed: false,
        shouldAdvertise: false,
        message: 'A finish needs one final discard.',
        opensPlayer: false,
        leavesFinalDiscard: false,
      );
    }

    final leavesFinalDiscard = remainingCards == 1;
    if (openingState.hasOpened(seat)) {
      return ClassicHareegMeldPlayEligibility(
        scenario: ClassicHareegMeldPlayScenario.regularMeld,
        isAllowed: true,
        shouldAdvertise: true,
        message: 'Meld played.',
        opensPlayer: false,
        leavesFinalDiscard: leavesFinalDiscard,
      );
    }

    final openingMelds = <PlacedMeld>[...stagedOpeningMelds, ...playedMelds];
    final opening = ClassicHareegOpeningRules.validateOpening(
      state: openingState,
      seat: seat,
      melds: openingMelds,
    );
    if (opening.isValid) {
      return ClassicHareegMeldPlayEligibility(
        scenario: ClassicHareegMeldPlayScenario.openingComplete,
        isAllowed: true,
        shouldAdvertise: true,
        message: 'Opened at ${opening.value}. Select one card to discard.',
        opensPlayer: true,
        leavesFinalDiscard: leavesFinalDiscard,
        opening: opening,
      );
    }

    if (leavesFinalDiscard) {
      return ClassicHareegMeldPlayEligibility(
        scenario: ClassicHareegMeldPlayScenario.openingFinishCandidate,
        isAllowed: true,
        shouldAdvertise: true,
        message:
            'Opening ${opening.value}/${openingState.currentRequirement}. '
            'Discard to finish.',
        opensPlayer: false,
        leavesFinalDiscard: true,
        opening: opening,
      );
    }

    return ClassicHareegMeldPlayEligibility(
      scenario: ClassicHareegMeldPlayScenario.openingPartial,
      isAllowed: true,
      shouldAdvertise: false,
      message:
          'Opening ${opening.value}/${openingState.currentRequirement}. '
          'Add more melds.',
      opensPlayer: false,
      leavesFinalDiscard: false,
      opening: opening,
    );
  }
}
