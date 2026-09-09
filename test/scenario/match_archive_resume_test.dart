import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_replay_verification.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_terminal_facts.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_recorder.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_report_replay.dart';

import '../support/completed_match_fixture.dart';
import 'classic_hareeg_match_driver.dart';

void main() {
  group('a match closed and resumed keeps one whole transcript', () {
    test('the resumed transcript replays to the true final state', () {
      final recorder = MatchRecorder();
      final driver = ClassicHareegMatchDriver(roundLimit: 12);

      // Capture what would have been persisted partway through the match —
      // exactly the bytes a checkpoint save writes.
      String? midMatchState;
      var stepCount = 0;
      final report = driver.run(
        setup: ClassicHareegSetup.defaults(),
        seed: 7,
        recorder: recorder,
        onStep: (_) {
          stepCount++;
          if (stepCount == 25) {
            midMatchState = jsonEncode(recorder.toState().toJson());
          }
        },
      );

      expect(midMatchState, isNotNull, reason: 'match was too short to split');

      final full = recorder.transcript!;
      expect(full.entries.length, greaterThan(30));

      // Replay the whole thing once to learn the true final state.
      final baseline = replayTranscript(full);
      final finalState = baseline.reconstructed!;

      // Now rebuild the recorder the way a resume does, and feed it the
      // actions that happened after the close.
      final resumed = MatchRecorder.restore(
        MatchRecorderState.fromJson(
          jsonDecode(midMatchState!) as Map<String, Object?>,
        ),
      );
      final resumedAt = resumed.transcript!.entries.length;
      // A resumed controller offers its own round as a base snapshot, as it
      // does for any fresh recorder. A restored recorder must ignore it.
      resumed.captureInitialState(finalState);
      for (final entry in full.entries.skip(resumedAt)) {
        resumed.recordAction(
          seat: entry.seat,
          roundNumber: entry.roundNumber,
          phase: entry.phase,
          actionId: entry.actionId,
        );
      }

      final resumedTranscript = resumed.transcript!;

      // The transcript spans the whole match, not just the part after resume.
      expect(resumedTranscript.entries.length, full.entries.length);
      expect(
        [for (final entry in resumedTranscript.entries) entry.order],
        [for (final entry in full.entries) entry.order],
      );
      expect(
        [for (final entry in resumedTranscript.entries) entry.actionId],
        [for (final entry in full.entries) entry.actionId],
      );

      // And it reconstructs the same final state, compared on concrete facts
      // rather than on "replay did not throw".
      final resumedReplay = replayTranscript(
        resumedTranscript,
        expected: finalState,
      );
      expect(
        resumedReplay.matches,
        isTrue,
        reason: resumedReplay.mismatches.join('\n'),
      );

      final reconstructed = resumedReplay.reconstructed!;
      expect(reconstructed.roundNumber, finalState.roundNumber);
      for (final seat in PlayerSeat.values) {
        expect(
          reconstructed.scores[seat] ?? 0,
          finalState.scores[seat] ?? 0,
          reason: 'score mismatch for ${seat.name}',
        );
      }
      expect(
        [for (final seat in reconstructed.removedSeats) seat.name]..sort(),
        [for (final seat in finalState.removedSeats) seat.name]..sort(),
      );
      expect(report.rounds, isNotEmpty);
    });

    test('a fresh recorder on resume loses the match, which is the old bug',
        () {
      // The regression guard. If a resume ever rebuilds the recorder instead of
      // restoring it, the transcript starts at the resumed round and this is
      // what the player gets: a replay that reconstructs the wrong game.
      final recorder = MatchRecorder();
      final driver = ClassicHareegMatchDriver(roundLimit: 12);

      driver.run(
        setup: ClassicHareegSetup.defaults(),
        seed: 7,
        recorder: recorder,
      );

      final full = recorder.transcript!;

      // The state a resumed session would start from: replay the prefix that
      // happened before the close.
      final midMatchState = replayTranscript(
        MatchActionTranscript(
          initialSnapshot: full.initialSnapshot,
          entries: full.entries.take(25),
        ),
      ).reconstructed!;

      final freshAfterResume = MatchRecorder()
        ..captureInitialState(midMatchState);

      for (final entry in full.entries.skip(25)) {
        freshAfterResume.recordAction(
          seat: entry.seat,
          roundNumber: entry.roundNumber,
          phase: entry.phase,
          actionId: entry.actionId,
        );
      }

      expect(
        freshAfterResume.transcript!.entries.length,
        lessThan(full.entries.length),
      );
    });
  });

  group('replay verification refuses an incomplete transcript', () {
    late MatchActionTranscript full;
    late MatchTerminalFacts terminalFacts;
    late ClassicHareegMatchSnapshot finalState;

    setUp(() {
      // A match driven to an actual winner. Terminal facts no longer construct
      // for a capped trace, and rightly so — the facts must describe a match
      // that finished.
      final completed = buildCompletedMatch();
      full = MatchActionTranscript(
        initialSnapshot: completed.recorderState.initialSnapshot!,
        entries: completed.recorderState.entries,
      );
      finalState = completed.finalState;
      terminalFacts = completed.facts;
    });

    test('accepts the complete transcript', () {
      expect(
        verifyReplayReconstructsTerminalFacts(
          transcript: full,
          facts: terminalFacts,
          finalSnapshot: finalState,
        ),
        isNull,
      );
    });

    test('rejects a schema-valid transcript missing one action', () {
      // The dangerous case: dropping an action leaves a transcript that is
      // perfectly well-formed and replays without error. It simply arrives
      // somewhere else, so only running it catches this.
      final withGap = MatchActionTranscript(
        initialSnapshot: full.initialSnapshot,
        entries: [
          ...full.entries.take(full.entries.length - 2),
          full.entries.last,
        ],
      );

      expect(
        verifyReplayReconstructsTerminalFacts(
          transcript: withGap,
          facts: terminalFacts,
          finalSnapshot: finalState,
        ),
        isNotNull,
      );
    });

    test('rejects a truncated transcript', () {
      final truncated = MatchActionTranscript(
        initialSnapshot: full.initialSnapshot,
        entries: full.entries.take(full.entries.length ~/ 2),
      );

      expect(
        verifyReplayReconstructsTerminalFacts(
          transcript: truncated,
          facts: terminalFacts,
          finalSnapshot: finalState,
        ),
        isNotNull,
      );
    });

    test('rejects a false winner even when the facts are self-consistent', () {
      // The dangerous forgery. The transcript is real and complete, the scores
      // and snapshot reconcile, and the facts are internally valid: a loser is
      // named winner and every other seat is marked eliminated. Nothing about
      // the shape gives it away — only replaying the match and asking who
      // actually won does.
      final trueWinner = terminalFacts.winner;
      final impostor = PlayerSeat.values.firstWhere(
        (seat) => seat != trueWinner,
      );

      final falseFacts = MatchTerminalFacts(
        completedAt: terminalFacts.completedAt,
        winner: impostor,
        finalScores: terminalFacts.finalScores,
        roundCount: terminalFacts.roundCount,
        eliminationRounds: {
          for (final seat in PlayerSeat.values)
            if (seat != impostor) seat: terminalFacts.roundCount,
        },
        seats: PlayerSeat.values,
      );

      final reason = verifyReplayReconstructsTerminalFacts(
        transcript: full,
        facts: falseFacts,
        finalSnapshot: finalState,
      );

      expect(reason, isNotNull);
      expect(reason, contains(trueWinner.name));
      expect(reason, contains(impostor.name));
    });

    test('rejects an empty transcript', () {
      expect(
        verifyReplayReconstructsTerminalFacts(
          transcript: MatchActionTranscript(
            initialSnapshot: full.initialSnapshot,
            entries: const [],
          ),
          facts: terminalFacts,
          finalSnapshot: finalState,
        ),
        isNotNull,
      );
    });
  });
}
