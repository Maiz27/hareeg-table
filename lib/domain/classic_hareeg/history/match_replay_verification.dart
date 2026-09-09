import '../game/classic_hareeg_match_snapshot.dart';
import '../reporting/match_action_transcript.dart';
import '../reporting/match_report_replay.dart';
import 'match_terminal_facts.dart';

/// Checks that [transcript] actually reconstructs [facts].
///
/// Returns null when it does, or a human-readable reason when it does not.
///
/// This is the safety net that stops a summary being published as replayable
/// when its transcript cannot deliver. A transcript can be perfectly well-formed
/// — correct schema, monotonic order, valid entries — and still be missing an
/// action, because losing actions is exactly what the old resume path did. Such
/// a transcript replays without error and simply arrives somewhere else, so
/// schema validity proves nothing here. The only trustworthy test is to run it
/// and compare the destination.
String? verifyReplayReconstructsTerminalFacts({
  required MatchActionTranscript transcript,
  required MatchTerminalFacts facts,
  required ClassicHareegMatchSnapshot finalSnapshot,
}) {
  if (transcript.isEmpty) {
    return 'The transcript holds no actions.';
  }

  final MatchReportReplayResult result;
  try {
    // Compared against the whole final snapshot, not just the headline facts.
    // A dropped action late in a match often leaves scores, round count, and
    // eliminations untouched while changing hands, stock, or the discard pile —
    // so aggregate checks alone would wave it through.
    result = replayTranscript(transcript, expected: finalSnapshot);
  } catch (error) {
    return 'Replay threw: $error';
  }

  if (result.status == MatchReportReplayStatus.mismatch) {
    return 'Replay diverged from the completed match: '
        '${result.mismatches.join('; ')}';
  }

  final reconstructed = result.reconstructed;
  if (reconstructed == null) {
    return 'Replay produced no final state: ${result.note ?? 'unknown reason'}';
  }

  if (reconstructed.roundNumber != facts.roundCount) {
    return 'Replay ended on round ${reconstructed.roundNumber}, '
        'but the match completed on round ${facts.roundCount}.';
  }

  for (final seat in facts.seats) {
    final expected = facts.finalScores[seat] ?? 0;
    final actual = reconstructed.scores[seat] ?? 0;
    if (expected != actual) {
      return 'Replay scored ${seat.name} $actual, '
          'but the match ended with $expected.';
    }
  }

  // Deliberately not compared against `facts.eliminationRounds`: a snapshot's
  // `removedSeats` is per-round board state, while match-level elimination is
  // decided by round progression between rounds. The two are different facts,
  // and equating them would reject every genuinely completed match.
  //
  // The winner, though, must match exactly. Checking only that the named winner
  // was not eliminated is far too weak: a real transcript can be paired with
  // terminal facts that name a *loser* as the winner and mark every other seat
  // eliminated. Those facts are internally consistent, the snapshot and scores
  // still reconcile, and `removedSeats` is normally empty — so nothing would
  // catch it, and the match would publish a replayable summary whose winner and
  // standing are simply wrong.
  final replayedWinner = result.matchWinner;
  if (replayedWinner == null) {
    return 'Replay did not reach a completed match, so it cannot support a '
        'recorded winner of ${facts.winner.name}.';
  }
  if (replayedWinner != facts.winner) {
    return 'Replay was won by ${replayedWinner.name}, '
        'but the match records ${facts.winner.name} as the winner.';
  }

  if (reconstructed.removedSeats.contains(facts.winner)) {
    return 'Replay eliminated ${facts.winner.name}, '
        'which the match records as the winner.';
  }

  return null;
}
