import '../models/table_strictness.dart';
import 'strictness_rule_profile.dart';

/// Mistake types recognized by Classic Hareeg presets.
enum MistakeType {
  /// Attempt to discard a cover during normal play.
  illegalCoverDiscard,

  /// Wrong Fifty claim.
  wrongFiftyClaim,

  /// Opening below the current requirement.
  insufficientOpening,

  /// Wrong joker replacement attempt.
  wrongJokerReplacement,

  /// Normal joker discard, always blocked.
  normalJokerDiscard,
}

/// Result of applying a mistake preset.
class MistakeResolution {
  /// Creates a mistake resolution.
  const MistakeResolution({
    required this.isAllowed,
    required this.penaltyPoints,
    required this.removeFromRound,
    required this.keepExistingMelds,
    required this.message,
    this.revertsAction = false,
  });

  /// Whether the mistaken action is allowed to happen.
  ///
  /// When false the engine blocks the action outright (coaching / standard).
  /// When true the engine surfaces the action as legal so it can be picked,
  /// then applies the penalty defined here.
  final bool isAllowed;

  /// Score penalty to apply immediately.
  final int penaltyPoints;

  /// Whether the player is removed from the current round.
  final bool removeFromRound;

  /// Whether existing table melds remain available for covers.
  final bool keepExistingMelds;

  /// Player-facing explanation.
  final String message;

  /// Strict-tier behavior: the penalty applies but the action itself is
  /// undone. The offending card stays in the seat's hand and the turn does
  /// not advance — the human is being coached with a real-money sting but
  /// still has to make a legal move. False for Table tier (the bad card
  /// lands on the discard pile and the offender is removed).
  final bool revertsAction;
}

/// Mistake-handling behavior derived from [TableStrictness].
abstract final class ClassicHareegMistakePresetRules {
  /// Resolves a mistake under a strictness tier.
  static MistakeResolution resolve({
    required TableStrictness strictness,
    required MistakeType mistake,
  }) {
    if (mistake == MistakeType.normalJokerDiscard) {
      return const MistakeResolution(
        isAllowed: false,
        penaltyPoints: 0,
        removeFromRound: false,
        keepExistingMelds: true,
        message: 'Jokers cannot be discarded during normal play.',
      );
    }

    return switch (strictness) {
      TableStrictness.coaching || TableStrictness.standard =>
        const MistakeResolution(
          isAllowed: false,
          penaltyPoints: 0,
          removeFromRound: false,
          keepExistingMelds: true,
          message: 'This illegal action is blocked at this strictness.',
        ),
      TableStrictness.strict => const MistakeResolution(
        isAllowed: true,
        penaltyPoints: 3,
        removeFromRound: false,
        keepExistingMelds: true,
        revertsAction: true,
        message: 'Table penalty: +3.',
      ),
      TableStrictness.table => const MistakeResolution(
        isAllowed: true,
        penaltyPoints: 17,
        removeFromRound: true,
        keepExistingMelds: true,
        message: 'Hard table mistake: +17 and out of this round.',
      ),
    };
  }

  /// Whether CPU mistakes may be generated under this strictness.
  ///
  /// CPU difficulty no longer gates mistake permission; mistakes are a rules
  /// concern (governed by [TableStrictness]) rather than a tier concern.
  static bool cpuMistakesAllowed(TableStrictness strictness) {
    return strictness.cpuMistakesAllowed;
  }
}
