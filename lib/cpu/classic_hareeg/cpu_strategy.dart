import '../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../domain/classic_hareeg/models/player_seat.dart';
import 'cpu_move_planner.dart';
import 'cpu_observation.dart';

export 'cpu_difficulty_profile.dart';
export 'cpu_observation.dart' show CpuObservation;

/// Boundary for CPU decision-making.
///
/// Implementations choose from legal actions exposed by the rules engine. They
/// must not mutate game state or bypass rule validation.
abstract interface class CpuStrategy {
  /// Chooses one legal move intent for the current CPU turn snapshot.
  CpuMoveIntent chooseMove(
    CpuTurnSnapshot snapshot, {
    CpuObservation? observation,
  });
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
  CpuMoveIntent chooseMove(
    CpuTurnSnapshot snapshot, {
    CpuObservation? observation,
  }) {
    final plan = switch (snapshot.difficulty) {
      // Route Casual/Beginner through `.plan(observation)` when available so
      // they inherit the same filters as Skilled/Expert (e.g. don't pick
      // claim-fifty without a finishing partition). Fall back to the legacy
      // legal-id-only evaluate when no observation is supplied (tests).
      CpuDifficulty.beginner || CpuDifficulty.casual =>
        observation != null
            ? const PriorityCpuMovePlanner().plan(observation)
            : PriorityCpuMovePlanner.evaluate(snapshot.legalActionIds),
      CpuDifficulty.skilled => _skilledPlan(observation),
      CpuDifficulty.expert => _expertPlan(observation),
    };
    final actionId = plan.actionId;
    if (actionId == null) {
      throw StateError('CPU needs at least one legal action.');
    }
    return CpuMoveIntent(actionId: actionId);
  }

  ClassicHareegCpuMovePlan _skilledPlan(CpuObservation? observation) {
    if (observation == null) {
      throw StateError('Skilled CPU planning requires a CpuObservation.');
    }
    return const SkilledCpuMovePlanner().plan(observation);
  }

  ClassicHareegCpuMovePlan _expertPlan(CpuObservation? observation) {
    if (observation == null) {
      throw StateError('Expert CPU planning requires a CpuObservation.');
    }
    return const ExpertCpuMovePlanner().plan(observation);
  }
}
