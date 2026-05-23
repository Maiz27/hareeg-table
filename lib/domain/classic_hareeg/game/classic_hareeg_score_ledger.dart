import '../models/player_seat.dart';
import '../rules/match_progression_rules.dart';
import '../rules/mistake_preset_rules.dart';

/// Score view exposed by the live match controller.
class ClassicHareegScoreView {
  /// Creates a score view.
  const ClassicHareegScoreView({
    required this.previousScores,
    required this.currentScores,
    this.progress,
  });

  /// Scores before applying a completed round result.
  final Map<PlayerSeat, int> previousScores;

  /// Scores the table should display now.
  final Map<PlayerSeat, int> currentScores;

  /// Completed-round progress, when the active round has ended.
  final MatchProgressState? progress;
}

/// Central score ledger for immediate penalties and completed-round views.
abstract final class ClassicHareegScoreLedger {
  /// Normalizes sparse score maps so every seat has a score entry.
  static Map<PlayerSeat, int> normalize(Map<PlayerSeat, int> scores) {
    return Map.unmodifiable({
      for (final seat in PlayerSeat.values) seat: scores[seat] ?? 0,
    });
  }

  /// Applies an immediate mistake penalty to [seat].
  static Map<PlayerSeat, int> applyPenalty({
    required Map<PlayerSeat, int> scores,
    required PlayerSeat seat,
    required MistakeResolution resolution,
  }) {
    final next = <PlayerSeat, int>{
      for (final s in PlayerSeat.values) s: scores[s] ?? 0,
    };
    next[seat] = next[seat]! + resolution.penaltyPoints;
    return Map.unmodifiable(next);
  }

  /// Builds the public score view from stored scores and round progress.
  static ClassicHareegScoreView view({
    required Map<PlayerSeat, int> scores,
    required MatchProgressState? progress,
  }) {
    final previous = normalize(scores);
    return ClassicHareegScoreView(
      previousScores: previous,
      currentScores: progress == null ? previous : normalize(progress.scores),
      progress: progress,
    );
  }
}
