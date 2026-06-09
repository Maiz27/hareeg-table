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
      seed: _nextRoundSeed(progress),
    );
    return ClassicHareegMatchSnapshot(
      setup: setup,
      hands: round.hands,
      seed: round.seed,
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

  /// Derives a deterministic seed for the next round's deal.
  ///
  /// Previously the next round was dealt with an unseeded `Random()`, which made
  /// any match longer than one round non-reproducible: replaying the same
  /// `(seed, setup)` diverged from round 2 onward because each reshuffle drew
  /// fresh entropy. The seed here is a pure function of the completed round's
  /// deterministic outcome (round number, the rotated next starter, and the
  /// post-round scores + active seats in a stable order). Two runs that reach
  /// the identical match state therefore reshuffle identically, so a full match
  /// replays byte-for-byte — the property committed golden transcripts rely on.
  int _nextRoundSeed(MatchProgressState progress) {
    // Build the seed from stable integers only (enum indices and int scores) so
    // it is reproducible both within and across processes — String/default
    // hashCodes are per-process-randomised in Dart and must not feed the seed.
    var hash = 0x811c9dc5; // FNV-1a 32-bit offset basis.
    void mix(int value) {
      hash = (hash ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF; // FNV prime.
    }

    mix(roundNumber + 1);
    mix(progress.nextStarter.index);
    for (final seat in PlayerSeat.values) {
      mix(seat.index);
      mix(progress.scores[seat] ?? 0);
      mix(progress.activeSeats.contains(seat) ? 1 : 0);
    }
    return hash;
  }
}
