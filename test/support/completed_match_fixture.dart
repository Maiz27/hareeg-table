import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_terminal_facts.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_recorder.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_report_replay.dart';

import '../scenario/classic_hareeg_match_driver.dart';

/// A match driven to an actual winner, with the facts that describe it.
typedef CompletedMatchFixture = ({
  MatchRecorderState recorderState,
  ClassicHareegMatchSnapshot finalState,
  MatchTerminalFacts facts,
});

/// Plays a full match and returns its recorder state, final snapshot, and
/// terminal facts.
///
/// Throws unless the driver reached a real winner. That refusal is the point:
/// a run that merely hit an action or round cap has several seats still
/// playing, and terminalizing it would manufacture a "completed match" that
/// never finished — which is exactly the shape a partial trace takes when it is
/// published as replayable.
CompletedMatchFixture buildCompletedMatch({int seed = 7, int roundLimit = 60}) {
  final recorder = MatchRecorder();
  final report = ClassicHareegMatchDriver(roundLimit: roundLimit).run(
    setup: ClassicHareegSetup.defaults(),
    seed: seed,
    recorder: recorder,
  );

  final winner = report.winner;
  if (!report.endedNaturally || winner == null) {
    throw StateError(
      'Seed $seed did not reach a winner: ${report.stopReason}. '
      'A capped run must not be terminalized.',
    );
  }

  final finalState = replayTranscript(recorder.transcript!).reconstructed!;

  // Elimination is a match-progression fact, decided between rounds, so it
  // comes from the driven round reports. A snapshot's `removedSeats` is
  // per-round board state and is empty even for a completed match — reading it
  // here would report that nobody was ever eliminated.
  final eliminationRounds = <PlayerSeat, int>{};
  for (final round in report.rounds) {
    final progress = round.progress;
    if (progress == null) {
      continue;
    }
    for (final seat in PlayerSeat.values) {
      if (!progress.activeSeats.contains(seat) &&
          !eliminationRounds.containsKey(seat) &&
          seat != winner) {
        eliminationRounds[seat] = round.roundNumber;
      }
    }
  }

  return (
    recorderState: recorder.toState(),
    finalState: finalState,
    facts: MatchTerminalFacts(
      completedAt: DateTime.utc(2026, 8, 22, 10),
      winner: winner,
      finalScores: {
        for (final seat in PlayerSeat.values) seat: finalState.scores[seat] ?? 0,
      },
      roundCount: finalState.roundNumber,
      eliminationRounds: eliminationRounds,
      seats: PlayerSeat.values,
    ),
  );
}
