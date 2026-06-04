import '../models/table_strictness.dart';
import 'strictness_rule_profile.dart';

/// Mistake types recognized by Classic Hareeg strictness tiers.
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

/// Result of applying mistake handling for a strictness tier.
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
  ///
  /// The structural facts (allowed / penalty / removal) come straight from
  /// [StrictnessRuleProfile] so the tier ladder lives in exactly one place.
  /// Only the player-facing copy and the [MistakeType.normalJokerDiscard]
  /// hard-block override are decided here.
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

    final allowed = !strictness.blocksIllegalMoves;
    final removeFromRound = strictness.removesPlayerOnMistake;
    // Strict-tier semantics: penalty applies but the action is undone. That
    // is exactly the case where the mistake is allowed (penalised) yet the
    // player stays in the round.
    final revertsAction = allowed && !removeFromRound;
    return MistakeResolution(
      isAllowed: allowed,
      penaltyPoints: strictness.mistakePenaltyPoints,
      removeFromRound: removeFromRound,
      keepExistingMelds: true,
      revertsAction: revertsAction,
      message: _messageFor(strictness),
    );
  }

  static String _messageFor(TableStrictness strictness) {
    return switch (strictness) {
      TableStrictness.coaching ||
      TableStrictness.standard => 'This strictness blocks that illegal action.',
      TableStrictness.strict => 'Strict penalty: +3.',
      TableStrictness.table => 'Table mistake: +17 and out of this round.',
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
