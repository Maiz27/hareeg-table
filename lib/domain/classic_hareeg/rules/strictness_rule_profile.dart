import '../models/table_strictness.dart';

/// Rules-engine derivations of [TableStrictness].
///
/// Lives in the rules layer so consumers like [ClassicHareegMistakePresetRules],
/// [ClassicHareegDiscardEligibilityPlanner], [ClassicHareegFiftyClaimPlanner],
/// [ClassicHareegTablePlayRetractionPlanner], and the live controller can
/// ask the strictness directly for rules-relevant facts without inspecting
/// the enum's name.
///
/// UI-side derivations (hints, joker display, inspect verbosity) live on
/// [StrictnessUiProfile] in `lib/ui/core/strictness/`.
extension StrictnessRuleProfile on TableStrictness {
  /// Whether the rules engine should refuse illegal moves outright.
  ///
  /// True for [TableStrictness.coaching] and [TableStrictness.standard];
  /// false for the permissive tiers, where mistakes are allowed and assessed
  /// a score penalty instead.
  bool get blocksIllegalMoves {
    return switch (this) {
      TableStrictness.coaching || TableStrictness.standard => true,
      TableStrictness.strict || TableStrictness.table => false,
    };
  }

  /// Score penalty applied when a mistake is committed under this strictness.
  ///
  /// Zero for blocking tiers (mistakes never reach the penalty path).
  int get mistakePenaltyPoints {
    return switch (this) {
      TableStrictness.coaching || TableStrictness.standard => 0,
      TableStrictness.strict => 3,
      TableStrictness.table => 17,
    };
  }

  /// Whether a mistake removes the offending player from the round.
  ///
  /// Only true for [TableStrictness.table]; the +17 penalty is severe enough
  /// to round-out the player.
  bool get removesPlayerOnMistake => this == TableStrictness.table;

  /// Whether players may retract a table play during their turn.
  ///
  /// All tiers except [TableStrictness.table] allow retraction so a player
  /// can undo a misclick or rethink an opening. The hardest tier locks plays
  /// to mirror physical-table commitment.
  bool get allowsTablePlayRetraction => this != TableStrictness.table;

  /// Whether the Fifty/Khamsin claim affordance should only advertise when
  /// the engine can prove the finish is legal.
  ///
  /// True only when [blocksIllegalMoves] is true — in permissive tiers, the
  /// player can attempt a Fifty claim and eat the penalty if it's illegal.
  bool get fiftyClaimNeedsFinishProofForAdvertise => blocksIllegalMoves;

  /// Whether CPUs are permitted to attempt mistakes under this strictness.
  ///
  /// Only Table tier accepts CPU mistakes — Strict's penalty is a coaching
  /// cue for the human (the action is reverted), so letting CPUs trigger
  /// it would burn turns to no useful effect.
  bool get cpuMistakesAllowed => this == TableStrictness.table;
}
