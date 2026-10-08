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

  final Map<int, Map<PlayerSeat, int>> _completed = {};
  int _framesRead = 0;
  int? _firstRound;
  int _lastRound = 0;
  bool _sawRestart = false;

  /// Whether reconstruction has finished (or refused).
  bool get isDone => _replay.isDone;

  /// Applies up to [budget] recorded actions. Returns true while more remain.
  bool step([int budget = 60]) {
    for (var i = 0; i < budget; i++) {
      if (!_replay.advance()) break;
    }
    _readNewFrames();
    return !_replay.isDone;
  }

  /// Abandons reconstruction.
  void cancel() => _replay.cancel();

  /// First round the transcript covers.
  int get firstRound => _firstRound ?? 1;

  // Frames are read once each, as they are produced, so a long match costs
  // one pass rather than a copy of the whole timeline per step.
  void _readNewFrames() {
    if (_replay.restartedAsLegacyWeb && !_sawRestart) {
      // The replay started over and dropped its earlier frames: read the
      // rebuilt timeline from its first frame.
      _sawRestart = true;
      _framesRead = 0;
      _completed.clear();
      _firstRound = null;
      _lastRound = 0;
    }
    final count = _replay.frameCount;
    for (; _framesRead < count; _framesRead++) {
      final frame = _replay.frameAt(_framesRead);
      _firstRound ??= frame.roundNumber;
      if (frame.roundNumber > _lastRound) _lastRound = frame.roundNumber;
      if (frame.kind == ReplayFrameKind.roundStart) {
        _completed[frame.roundNumber - 1] = ClassicHareegScoreLedger.normalize(
          frame.snapshot.scores,
        );
      }
    }
  }

  /// Totals each completed round ended on, keyed by round number.
  ///
  /// The transcript only reaches a round's opening deal once that round has
  /// a recorded action, so the round that just ended is missing while the
  /// round in play ([currentRound]) has none yet. Then nothing has changed
  /// since the round ended, and [currentScores] are exactly its totals.
  Map<int, Map<PlayerSeat, int>> completedTotals({
    int? currentRound,
    Map<PlayerSeat, int>? currentScores,
  }) {
    final totals = Map<int, Map<PlayerSeat, int>>.of(_completed);
    final finished = currentRound == null ? null : currentRound - 1;
    if (finished != null &&
        currentScores != null &&
        _replay.isDone &&
        _replay.failure == null &&
        _lastRound < currentRound! &&
        _lastRound == finished &&
        !totals.containsKey(finished)) {
      totals[finished] = ClassicHareegScoreLedger.normalize(currentScores);
    }
    return totals;
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
