import '../models/classic_hareeg_setup.dart';
import '../models/player_seat.dart';
import '../rules/classic_hareeg_rules.dart';
import '../rules/match_progression_rules.dart';
import '../rules/opening_rules.dart';
import 'classic_hareeg_match_snapshot.dart';
import 'classic_hareeg_round.dart';

/// Match-level progression for completed Classic Hareeg rounds.
///
/// Keeps scoring, elimination, next starter, and next-round snapshot assembly
/// behind one domain interface so the live controller can stay focused on
/// current-round turn mutation.
class ClassicHareegMatchFlow {
  /// Creates match flow for the active match state before applying a result.
  const ClassicHareegMatchFlow({
    required this.setup,
    required this.rules,
    required this.scores,
    required this.activeSeats,
    required this.currentStarter,
    required this.roundNumber,
  });

  /// Setup used to deal the next round.
  final ClassicHareegSetup setup;

  /// Rules used for scoring and dealing.
  final ClassicHareegRules rules;

  /// Match scores before applying the completed round result.
  final Map<PlayerSeat, int> scores;

  /// Seats active before applying the completed round result.
  final List<PlayerSeat> activeSeats;

  /// Starter of the completed round.
  final PlayerSeat currentStarter;

  /// One-based number of the completed round.
  final int roundNumber;

  /// Applies [roundResult] to produce match progress, or null if no result is
  /// available yet.
  MatchProgressState? progressFor(RoundProgressResult? roundResult) {
    if (roundResult == null) {
      return null;
    }

    return ClassicHareegMatchProgressionRules.applyRoundResult(
      scores: scores,
      activeSeats: activeSeats,
      currentStarter: currentStarter,
      result: roundResult,
      eliminationScore: rules.eliminationScore,
    );
  }

  /// Deals the next round snapshot after applying [roundResult].
  ///
  /// Returns null when no completed round result is available or when the
  /// completed round produced a match winner.
  ClassicHareegMatchSnapshot? nextRoundSnapshotFor({
    required RoundProgressResult? roundResult,
    DateTime? savedAt,
  }) {
    final progress = progressFor(roundResult);
    if (progress == null || progress.matchWinner != null) {
      return null;
    }

    final round = ClassicHareegRound.deal(
      setup: setup,
      rules: rules,
      activeSeats: progress.activeSeats,
      starterOverride: progress.nextStarter,
    );
    return ClassicHareegMatchSnapshot(
      setup: setup,
      hands: round.hands,
      stock: round.stock,
      discardPile: round.discardPile,
      tableMelds: {
        for (final seat in PlayerSeat.values) seat: const <PlacedMeld>[],
      },
      starter: round.starter,
      currentSeat: round.currentSeat,
      turnPhase: round.turnPhase,
      openingState: OpeningState.initial(setup.openingRequirement),
      scores: progress.scores,
      activeSeats: progress.activeSeats,
      roundNumber: roundNumber + 1,
      removedSeats: const [],
      savedAt: savedAt ?? DateTime.now().toUtc(),
    );
  }
}
