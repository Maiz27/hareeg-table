import '../../domain/classic_hareeg/models/player_seat.dart';

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
  const CpuTurnSnapshot({required this.seat, required this.legalActionIds});

  /// Seat controlled by this CPU decision.
  final PlayerSeat seat;

  /// Identifiers for actions that the rules engine has already deemed legal.
  final List<String> legalActionIds;
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
