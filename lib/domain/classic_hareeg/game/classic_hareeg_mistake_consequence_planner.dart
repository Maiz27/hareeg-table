import '../models/player_seat.dart';
import '../models/table_strictness.dart';
import '../rules/match_progression_rules.dart';
import '../rules/mistake_preset_rules.dart';
import 'classic_hareeg_round.dart';
import 'classic_hareeg_score_ledger.dart';
import 'classic_hareeg_turn_exit_planner.dart';

/// Complete consequence class for a resolved mistake.
enum ClassicHareegMistakeConsequenceScenario {
  /// The active strictness blocks the mistake before state changes.
  blocked,

  /// The player receives a score penalty and stays in the round.
  penaltyOnly,

  /// The player receives a penalty, is removed, and play continues.
  removalContinues,

  /// The player receives a penalty and the removal completes the round.
  removalEndsRound,

  /// The player receives a penalty and no active seat remains.
  removalLeavesNoActiveSeat,
}

/// Pure plan for applying score, removal, and turn consequences of a mistake.
class ClassicHareegMistakeConsequencePlan {
  /// Creates a mistake consequence plan.
  const ClassicHareegMistakeConsequencePlan({
    required this.scenario,
    required this.resolution,
    required this.scoresAfterPenalty,
    required this.removedSeatsAfterMistake,
    required this.shouldMovePendingDiscardToDiscardPile,
    this.exit,
    this.removedSeat,
  });

  /// Identified consequence scenario.
  final ClassicHareegMistakeConsequenceScenario scenario;

  /// Preset-specific mistake resolution.
  final MistakeResolution resolution;

  /// Scores after any immediate penalty.
  final Map<PlayerSeat, int> scoresAfterPenalty;

  /// Round removals after the mistake is applied.
  final Set<PlayerSeat> removedSeatsAfterMistake;

  /// Removed seat when [scenario] removes the player from the round.
  final PlayerSeat? removedSeat;

  /// Turn/round transition after a hard-table removal.
  final ClassicHareegMistakeExit? exit;

  /// Whether a picked-up discard should be moved back to the discard pile.
  final bool shouldMovePendingDiscardToDiscardPile;

  /// Player-facing consequence message.
  String get message => resolution.message;

  /// Whether state may be mutated for this mistake.
  bool get canApply => resolution.isAllowed;

  /// Whether a score penalty should be written to the ledger.
  bool get shouldApplyPenalty => canApply;

  /// Whether this mistake removes the player from the current round.
  bool get removesPlayer => removedSeat != null;

  /// Whether transient Fifty state should be cleared.
  bool get shouldClearFiftyWindow => removesPlayer;

  /// Whether transient turn play state should be cleared.
  bool get shouldResetTurnState => removesPlayer;

  /// Round result when the removal completes the round.
  RoundProgressResult? get roundResult => exit?.roundResult;

  /// Next seat when the round continues after removal.
  PlayerSeat? get nextSeat => exit?.nextSeat;

  /// Next phase when the round continues after removal.
  TurnPhase? get nextPhase => exit?.nextPhase;
}

/// Plans mistake consequences behind a single pure rules-engine interface.
abstract final class ClassicHareegMistakeConsequencePlanner {
  /// Resolves [mistake] under [strictness] and plans its consequences.
  ///
  /// [remainingCardCounts] is the pre-mistake card-count map for all active
  /// seats. The planner subtracts the seat itself when the resolution causes
  /// removal, so callers do not need to pre-filter the map.
  static ClassicHareegMistakeConsequencePlan evaluate({
    required TableStrictness strictness,
    required MistakeType mistake,
    required PlayerSeat seat,
    required Map<PlayerSeat, int> scores,
    required Iterable<PlayerSeat> activeSeats,
    required Set<PlayerSeat> removedSeats,
    required bool hasPendingDiscard,
    required Map<PlayerSeat, int> remainingCardCounts,
  }) {
    return fromResolution(
      resolution: ClassicHareegMistakePresetRules.resolve(
        strictness: strictness,
        mistake: mistake,
      ),
      seat: seat,
      scores: scores,
      activeSeats: activeSeats,
      removedSeats: removedSeats,
      hasPendingDiscard: hasPendingDiscard,
      remainingCardCounts: remainingCardCounts,
    );
  }

  /// Plans consequences from a resolution already identified by another module.
  ///
  /// See [evaluate] for the [remainingCardCounts] contract.
  static ClassicHareegMistakeConsequencePlan fromResolution({
    required MistakeResolution resolution,
    required PlayerSeat seat,
    required Map<PlayerSeat, int> scores,
    required Iterable<PlayerSeat> activeSeats,
    required Set<PlayerSeat> removedSeats,
    required bool hasPendingDiscard,
    required Map<PlayerSeat, int> remainingCardCounts,
  }) {
    final normalizedScores = ClassicHareegScoreLedger.normalize(scores);
    if (!resolution.isAllowed) {
      return ClassicHareegMistakeConsequencePlan(
        scenario: ClassicHareegMistakeConsequenceScenario.blocked,
        resolution: resolution,
        scoresAfterPenalty: normalizedScores,
        removedSeatsAfterMistake: Set.unmodifiable(removedSeats),
        shouldMovePendingDiscardToDiscardPile: false,
      );
    }

    final scoresAfterPenalty = ClassicHareegScoreLedger.applyPenalty(
      scores: scores,
      seat: seat,
      resolution: resolution,
    );
    if (!resolution.removeFromRound) {
      return ClassicHareegMistakeConsequencePlan(
        scenario: ClassicHareegMistakeConsequenceScenario.penaltyOnly,
        resolution: resolution,
        scoresAfterPenalty: scoresAfterPenalty,
        removedSeatsAfterMistake: Set.unmodifiable(removedSeats),
        shouldMovePendingDiscardToDiscardPile: false,
      );
    }

    final removedSeatsAfterMistake = Set<PlayerSeat>.unmodifiable({
      ...removedSeats,
      seat,
    });
    final remainingCardCountsAfterMistake = <PlayerSeat, int>{
      for (final entry in remainingCardCounts.entries)
        if (entry.key != seat) entry.key: entry.value,
    };
    final exit = ClassicHareegTurnExitPlanner.afterPlayerRemoval(
      removedSeat: seat,
      activeSeats: activeSeats,
      removedSeats: removedSeatsAfterMistake,
      remainingCardCounts: remainingCardCountsAfterMistake,
    );
    final scenario = _removalScenario(exit);

    return ClassicHareegMistakeConsequencePlan(
      scenario: scenario,
      resolution: resolution,
      scoresAfterPenalty: scoresAfterPenalty,
      removedSeatsAfterMistake: removedSeatsAfterMistake,
      removedSeat: seat,
      exit: exit,
      shouldMovePendingDiscardToDiscardPile: hasPendingDiscard,
    );
  }
}

ClassicHareegMistakeConsequenceScenario _removalScenario(
  ClassicHareegMistakeExit exit,
) {
  if (exit.roundResult != null) {
    return ClassicHareegMistakeConsequenceScenario.removalEndsRound;
  }
  if (exit.nextSeat != null && exit.nextPhase != null) {
    return ClassicHareegMistakeConsequenceScenario.removalContinues;
  }
  return ClassicHareegMistakeConsequenceScenario.removalLeavesNoActiveSeat;
}
