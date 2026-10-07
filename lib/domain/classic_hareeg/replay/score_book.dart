import '../game/classic_hareeg_score_ledger.dart';
import '../models/player_seat.dart';
import '../reporting/match_action_transcript.dart';
import 'replay_reconstruction.dart';

/// One round's line in the match score book: every seat's running total after
/// the round, and what the round added.
class ScoreBookLine {
  /// Creates a score book line.
  const ScoreBookLine({
    required this.roundNumber,
    required this.totals,
    required this.deltas,
    required this.live,
  });

  /// One-based round number.
  final int roundNumber;

  /// Running match total per seat after this round (or right now, when
  /// [live]).
  final Map<PlayerSeat, int> totals;

  /// Points this round added per seat.
  final Map<PlayerSeat, int> deltas;

  /// Whether this is the round in play, whose totals can still change.
  final bool live;
}

/// Reads per-round match totals out of a match transcript.
///
/// The live match only keeps current scores, so the round-by-round history is
/// recovered the same way a replay is: by reconstructing the match from its
/// recorded actions. Each later round's opening deal carries the totals the
/// previous round ended on. Reconstruction runs in bounded [step]s so a long
/// match never stalls a frame.
class ScoreBookReader {
  /// Creates a reader over [transcript].
  ScoreBookReader(MatchActionTranscript transcript)
    : _replay = ReplayReconstruction(transcript),
      startScores = ClassicHareegScoreLedger.normalize(
        transcript.initialSnapshot.scores,
      );

  final ReplayReconstruction _replay;

  /// Totals at the start of the transcript (zero for a whole match; carried
  /// totals for a sandbox seeded mid-match).
  final Map<PlayerSeat, int> startScores;

  /// Whether reconstruction has finished (or refused).
  bool get isDone => _replay.isDone;

  /// Applies up to [budget] recorded actions. Returns true while more remain.
  bool step([int budget = 60]) {
    for (var i = 0; i < budget; i++) {
      if (!_replay.advance()) return false;
    }
    return !_replay.isDone;
  }

  /// Abandons reconstruction.
  void cancel() => _replay.cancel();

  /// First round the transcript covers.
  int get firstRound {
    final frames = _replay.frames;
    return frames.isEmpty ? 1 : frames.first.roundNumber;
  }

  /// Totals each completed round ended on, keyed by round number, for every
  /// round reconstructed so far.
  Map<int, Map<PlayerSeat, int>> completedTotals() {
    return {
      for (final frame in _replay.frames)
        if (frame.kind == ReplayFrameKind.roundStart)
          frame.roundNumber - 1: ClassicHareegScoreLedger.normalize(
            frame.snapshot.scores,
          ),
    };
  }
}

/// Builds the score book's lines: one per completed round from [firstRound],
/// then the live round on [currentScores].
///
/// A round missing from [completed] (still being reconstructed, or a
/// transcript replay refused) ends the completed lines there, so the book
/// never shows a gap; the live line then carries no deltas, since they would
/// be measured against the wrong round.
List<ScoreBookLine> buildScoreBookLines({
  required Map<int, Map<PlayerSeat, int>> completed,
  required int firstRound,
  required int currentRound,
  required Map<PlayerSeat, int> currentScores,
  Map<PlayerSeat, int> startScores = const {},
}) {
  final lines = <ScoreBookLine>[];
  var previous = ClassicHareegScoreLedger.normalize(startScores);
  Map<PlayerSeat, int> delta(Map<PlayerSeat, int> totals) => {
    for (final seat in PlayerSeat.values)
      seat: (totals[seat] ?? 0) - (previous[seat] ?? 0),
  };
  var gap = false;
  for (var round = firstRound; round < currentRound; round++) {
    final totals = completed[round];
    if (totals == null) {
      gap = true;
      break;
    }
    lines.add(
      ScoreBookLine(
        roundNumber: round,
        totals: totals,
        deltas: delta(totals),
        live: false,
      ),
    );
    previous = totals;
  }
  final now = ClassicHareegScoreLedger.normalize(currentScores);
  lines.add(
    ScoreBookLine(
      roundNumber: currentRound,
      totals: now,
      deltas: gap ? const {} : delta(now),
      live: true,
    ),
  );
  return lines;
}
