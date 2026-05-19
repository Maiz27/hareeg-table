import '../models/classic_hareeg_setup.dart';

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
  });

  /// Whether the mistaken action is allowed to happen.
  final bool isAllowed;

  /// Score penalty to apply immediately.
  final int penaltyPoints;

  /// Whether the player is removed from the current round.
  final bool removeFromRound;

  /// Whether existing table melds remain available for covers.
  final bool keepExistingMelds;

  /// Player-facing explanation.
  final String message;
}

/// Rule preset behavior for mistake handling.
abstract final class ClassicHareegMistakePresetRules {
  /// Resolves a mistake under a preset.
  static MistakeResolution resolve({
    required RulePreset preset,
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

    return switch (preset) {
      RulePreset.assisted => const MistakeResolution(
        isAllowed: false,
        penaltyPoints: 0,
        removeFromRound: false,
        keepExistingMelds: true,
        message: 'Assisted mode blocks this illegal action.',
      ),
      RulePreset.tablePenalties => const MistakeResolution(
        isAllowed: true,
        penaltyPoints: 3,
        removeFromRound: false,
        keepExistingMelds: true,
        message: 'Table penalty: +3.',
      ),
      RulePreset.hardTable17 => const MistakeResolution(
        isAllowed: true,
        penaltyPoints: 17,
        removeFromRound: true,
        keepExistingMelds: true,
        message: 'Hard table mistake: +17 and out of this round.',
      ),
    };
  }

  /// Whether CPU mistakes may be generated under this preset/difficulty.
  static bool cpuMistakesAllowed({
    required RulePreset preset,
    required CpuDifficulty difficulty,
  }) {
    if (preset == RulePreset.assisted) {
      return false;
    }

    return switch (difficulty) {
      CpuDifficulty.beginner || CpuDifficulty.casual => true,
      CpuDifficulty.skilled || CpuDifficulty.expert => false,
    };
  }
}
