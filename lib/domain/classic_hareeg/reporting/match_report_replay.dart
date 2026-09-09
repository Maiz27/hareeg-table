import '../game/classic_hareeg_match_snapshot.dart';
import '../models/player_seat.dart';
import '../replay/match_replay_timeline.dart';
import 'classic_hareeg_match_report.dart';
import 'match_action_transcript.dart';

export 'snapshot_mismatch.dart' show describeSnapshotMismatch;

/// Outcome class for a transcript replay.
enum MatchReportReplayStatus {
  /// The reconstructed state matched the reported snapshot.
  matched,

  /// Replay completed but the reconstructed state diverged.
  mismatch,

  /// Replay could not run because the report carries no transcript.
  noTranscript,
}

/// Result of replaying a report's action transcript.
///
/// On a mismatch, [mismatches] holds human-readable lines covering round, seat,
/// turn phase, scores, and relevant table state so a reproduction failure
/// points at the specific divergence instead of a bare assertion.
class MatchReportReplayResult {
  /// Creates a replay result.
  const MatchReportReplayResult({
    required this.status,
    this.mismatches = const [],
    this.reconstructed,
    this.note,
    this.matchWinner,
  });

  /// Replay outcome.
  final MatchReportReplayStatus status;

  /// Human-readable divergence lines, empty when [matches] is true.
  final List<String> mismatches;

  /// Reconstructed final snapshot, when replay ran to completion.
  final ClassicHareegMatchSnapshot? reconstructed;

  /// Optional explanation (e.g. why replay could not run).
  final String? note;

  /// Winner the replayed match actually reached, when it reached one.
  ///
  /// Null when replay did not run, or ran but ended before a seat won. A
  /// snapshot carries no winner, so this is the only way a caller can check a
  /// recorded winner against what the transcript really produces.
  final PlayerSeat? matchWinner;

  /// Whether replay confirmed the reported state.
  bool get matches => status == MatchReportReplayStatus.matched;
}

/// Replays [report]'s transcript and compares the reconstructed state to the
/// report snapshot.
///
/// Returns [MatchReportReplayStatus.noTranscript] when the report has no
/// transcript to replay.
MatchReportReplayResult replayMatchReport(ClassicHareegMatchReport report) {
  final transcript = report.transcript;
  if (transcript == null) {
    return const MatchReportReplayResult(
      status: MatchReportReplayStatus.noTranscript,
      note: 'Report has no action transcript to replay.',
    );
  }
  return replayTranscript(transcript, expected: report.snapshot);
}

/// Replays a [transcript] from its base snapshot, optionally comparing the
/// reconstructed state to [expected].
///
/// Verification and review are the same reconstruction: this drains
/// [MatchReplayTimeline] rather than walking the transcript itself, so there is
/// exactly one round-crossing rule, one application seam, one Fifty retry and
/// one clock in the codebase.
///
/// When [expected] is null the result is always
/// [MatchReportReplayStatus.matched] with the reconstructed snapshot attached,
/// so callers can inspect the replayed state without a reference snapshot.
MatchReportReplayResult replayTranscript(
  MatchActionTranscript transcript, {
  ClassicHareegMatchSnapshot? expected,
}) {
  final outcome = MatchReplayTimeline.build(transcript);

  switch (outcome) {
    case ReplayTimelineFailed(:final failure):
      return MatchReportReplayResult(
        status: MatchReportReplayStatus.mismatch,
        mismatches: [failure.message],
        reconstructed: failure.partialSnapshot,
      );

    case ReplayTimelineBuilt(:final timeline):
      final reconstructed = timeline.finalSnapshot;
      final replayedWinner = timeline.matchWinner;
      if (expected == null) {
        return MatchReportReplayResult(
          status: MatchReportReplayStatus.matched,
          reconstructed: reconstructed,
          matchWinner: replayedWinner,
        );
      }

      final mismatches = timeline.verifyAgainst(expected);
      return MatchReportReplayResult(
        status: mismatches.isEmpty
            ? MatchReportReplayStatus.matched
            : MatchReportReplayStatus.mismatch,
        mismatches: mismatches,
        reconstructed: reconstructed,
        matchWinner: replayedWinner,
      );
  }
}
