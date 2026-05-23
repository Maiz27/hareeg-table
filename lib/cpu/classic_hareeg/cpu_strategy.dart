import '../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../domain/classic_hareeg/models/player_seat.dart';
import 'cpu_move_planner.dart';

/// Boundary for CPU decision-making.
///
/// Implementations choose from legal actions exposed by the rules engine. They
/// must not mutate game state or bypass rule validation.
abstract interface class CpuStrategy {
  /// Chooses one legal move intent for the current CPU turn snapshot.
  CpuMoveIntent chooseMove(CpuTurnSnapshot snapshot);
}

/// Minimal state visible to a CPU player when choosing a move.
class CpuTurnSnapshot {
  /// Creates a CPU decision snapshot.
  CpuTurnSnapshot({
    required this.seat,
    required Iterable<String> legalActionIds,
    this.difficulty = CpuDifficulty.casual,
  }) : legalActionIds = List.unmodifiable(legalActionIds);

  /// Seat controlled by this CPU decision.
  final PlayerSeat seat;

  /// Read-only identifiers for actions that the rules engine has deemed legal.
  final List<String> legalActionIds;

  /// Difficulty profile to use for this decision.
  final CpuDifficulty difficulty;
}

/// CPU request to apply a legal action.
///
/// The rules engine remains responsible for validating the referenced action
/// when the intent is applied to real game state.
class CpuMoveIntent {
  /// Creates a CPU move intent for a legal action identifier.
  const CpuMoveIntent({required this.actionId});

  /// Identifier for the action selected by the CPU strategy.
  final String actionId;
}

/// First-pass CPU strategy for Classic Hareeg.
///
/// The strategy only chooses from legal action ids already supplied by the
/// rules engine. It never mutates game state or invents moves.
class ClassicHareegCpuStrategy implements CpuStrategy {
  /// Creates a CPU strategy.
  const ClassicHareegCpuStrategy();

  @override
  CpuMoveIntent chooseMove(CpuTurnSnapshot snapshot) {
    final plan = ClassicHareegCpuMovePlanner.evaluate(snapshot.legalActionIds);
    final actionId = plan.actionId;
    if (actionId == null) {
      throw StateError('CPU needs at least one legal action.');
    }
    return CpuMoveIntent(actionId: actionId);
  }
}

/// CPU timing and miss-chance profile.
class CpuDifficultyProfile {
  /// Creates a CPU difficulty profile.
  const CpuDifficultyProfile({
    required this.difficulty,
    required this.fiftyReactionMillis,
    required this.fiftyMissChance,
  });

  /// Difficulty represented by this profile.
  final CpuDifficulty difficulty;

  /// Approximate Fifty reaction delay for later UI timing.
  final int fiftyReactionMillis;

  /// Chance that a CPU misses a valid Fifty opportunity.
  final double fiftyMissChance;

  /// Returns the profile for a difficulty.
  static CpuDifficultyProfile forDifficulty(CpuDifficulty difficulty) {
    return switch (difficulty) {
      CpuDifficulty.beginner => const CpuDifficultyProfile(
        difficulty: CpuDifficulty.beginner,
        fiftyReactionMillis: 2500,
        fiftyMissChance: 0.45,
      ),
      CpuDifficulty.casual => const CpuDifficultyProfile(
        difficulty: CpuDifficulty.casual,
        fiftyReactionMillis: 1800,
        fiftyMissChance: 0.25,
      ),
      CpuDifficulty.skilled => const CpuDifficultyProfile(
        difficulty: CpuDifficulty.skilled,
        fiftyReactionMillis: 1100,
        fiftyMissChance: 0.10,
      ),
      CpuDifficulty.expert => const CpuDifficultyProfile(
        difficulty: CpuDifficulty.expert,
        fiftyReactionMillis: 650,
        fiftyMissChance: 0.03,
      ),
    };
  }
}
