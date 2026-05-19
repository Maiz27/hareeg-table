import '../models/player_seat.dart';

/// Type of round result.
enum RoundOutcomeType {
  /// Normal round finish.
  normalFinish,

  /// Fifty / Khamsin finish.
  fiftyFinish,

  /// Drawn round from stock exhaustion.
  draw,
}

/// Match state after scoring and elimination.
class MatchProgressState {
  /// Creates match progress state.
  const MatchProgressState({
    required this.scores,
    required this.activeSeats,
    required this.nextStarter,
    this.matchWinner,
  });

  /// Current scores by seat.
  final Map<PlayerSeat, int> scores;

  /// Seats still active in the match.
  final List<PlayerSeat> activeSeats;

  /// Starter for the next dealt round.
  final PlayerSeat nextStarter;

  /// Last remaining player, if the match is over.
  final PlayerSeat? matchWinner;
}

/// Round result needed for Classic Hareeg scoring.
class RoundProgressResult {
  /// Creates a round result.
  const RoundProgressResult({
    required this.type,
    required this.remainingCardCounts,
    this.winner,
    this.fiftyDiscarder,
    this.firstRoundFiftyException = false,
  });

  /// Outcome type.
  final RoundOutcomeType type;

  /// Remaining card counts for active seats.
  final Map<PlayerSeat, int> remainingCardCounts;

  /// Round winner for normal/Fifty finishes.
  final PlayerSeat? winner;

  /// Player whose discard was hit by Fifty.
  final PlayerSeat? fiftyDiscarder;

  /// Whether first dealt round Fifty uses -1 instead of -3.
  final bool firstRoundFiftyException;
}

/// Classic Hareeg scoring, elimination, and next-round progression.
abstract final class ClassicHareegMatchProgressionRules {
  /// Applies a round result to scores and active seat state.
  static MatchProgressState applyRoundResult({
    required Map<PlayerSeat, int> scores,
    required List<PlayerSeat> activeSeats,
    required PlayerSeat currentStarter,
    required RoundProgressResult result,
    int eliminationScore = 31,
  }) {
    final nextScores = Map<PlayerSeat, int>.of(scores);

    switch (result.type) {
      case RoundOutcomeType.draw:
        _requireActiveSeat(currentStarter, activeSeats, 'Current starter');
        break;
      case RoundOutcomeType.normalFinish:
        final winner = _requireActiveWinner(result, activeSeats);
        for (final seat in activeSeats) {
          if (seat == winner) {
            nextScores[seat] = (nextScores[seat] ?? 0) - 1;
          } else {
            nextScores[seat] =
                (nextScores[seat] ?? 0) +
                (result.remainingCardCounts[seat] ?? 0);
          }
        }
      case RoundOutcomeType.fiftyFinish:
        final winner = _requireActiveWinner(result, activeSeats);
        final discarder = result.fiftyDiscarder;
        if (discarder == null) {
          throw ArgumentError('Fifty scoring needs a discarder.');
        }
        _requireActiveSeat(discarder, activeSeats, 'Fifty discarder');
        if (discarder == winner) {
          throw ArgumentError('Fifty discarder cannot also be the winner.');
        }

        for (final seat in activeSeats) {
          if (seat == winner) {
            nextScores[seat] =
                (nextScores[seat] ?? 0) +
                (result.firstRoundFiftyException ? -1 : -3);
          } else if (seat == discarder) {
            nextScores[seat] =
                (nextScores[seat] ?? 0) +
                (result.remainingCardCounts[seat] ?? 0) +
                3;
          } else {
            nextScores[seat] =
                (nextScores[seat] ?? 0) +
                (result.remainingCardCounts[seat] ?? 0);
          }
        }
    }

    final remainingSeats = [
      for (final seat in activeSeats)
        if ((nextScores[seat] ?? 0) < eliminationScore) seat,
    ];

    return MatchProgressState(
      scores: Map.unmodifiable(nextScores),
      activeSeats: List.unmodifiable(remainingSeats),
      nextStarter: result.type == RoundOutcomeType.draw
          ? currentStarter
          : _requireActiveWinner(result, activeSeats),
      matchWinner: remainingSeats.length == 1 ? remainingSeats.single : null,
    );
  }

  static PlayerSeat _requireActiveWinner(
    RoundProgressResult result,
    List<PlayerSeat> activeSeats,
  ) {
    final winner = _requireWinner(result);
    _requireActiveSeat(winner, activeSeats, 'Round winner');
    return winner;
  }

  static void _requireActiveSeat(
    PlayerSeat seat,
    List<PlayerSeat> activeSeats,
    String role,
  ) {
    if (!activeSeats.contains(seat)) {
      throw ArgumentError('$role must be one of the active seats.');
    }
  }

  static PlayerSeat _requireWinner(RoundProgressResult result) {
    final winner = result.winner;
    if (winner == null) {
      throw ArgumentError('Round result requires a winner.');
    }
    return winner;
  }
}
