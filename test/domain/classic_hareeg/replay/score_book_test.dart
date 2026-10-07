import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/score_book.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_recorder.dart';

import '../../../scenario/classic_hareeg_match_driver.dart';

void main() {
  test('the score book recovers every round the match driver recorded', () {
    final recorder = MatchRecorder();
    final report = ClassicHareegMatchDriver(
      roundLimit: 60,
    ).run(setup: ClassicHareegSetup.defaults(), seed: 7, recorder: recorder);
    final completedRounds = [
      for (final round in report.rounds)
        if (round.progress != null) round,
    ];
    expect(completedRounds.length, greaterThan(1));

    final reader = ScoreBookReader(recorder.transcript!);
    while (reader.step(25)) {}
    final totals = reader.completedTotals();

    // Every round that led into another is in the book, on the scores the
    // driver saw that round end with.
    for (final round in completedRounds.take(completedRounds.length - 1)) {
      expect(totals[round.roundNumber], {
        for (final seat in PlayerSeat.values)
          seat: round.progress!.scores[seat] ?? 0,
      }, reason: 'round ${round.roundNumber}');
    }
  });

  test('lines carry running totals and per-round deltas, live last', () {
    final lines = buildScoreBookLines(
      completed: {
        1: {PlayerSeat.south: 0, PlayerSeat.east: 12, PlayerSeat.north: 5},
        2: {PlayerSeat.south: 7, PlayerSeat.east: 12, PlayerSeat.north: 30},
      },
      firstRound: 1,
      currentRound: 3,
      currentScores: {PlayerSeat.south: 9, PlayerSeat.north: 30},
    );

    expect(lines.map((l) => l.roundNumber), [1, 2, 3]);
    expect(lines.map((l) => l.live), [false, false, true]);
    expect(lines[1].deltas[PlayerSeat.north], 25);
    expect(lines[1].totals[PlayerSeat.east], 12);
    expect(lines[2].deltas[PlayerSeat.south], 2);
    // A seat missing from a score map counts as zero, never as absent.
    expect(lines[2].totals[PlayerSeat.west], 0);
    expect(lines[2].deltas[PlayerSeat.east], -12);
  });

  test('a round still being reconstructed stops the book, never gaps it', () {
    final lines = buildScoreBookLines(
      completed: {
        1: {PlayerSeat.south: 3},
        3: {PlayerSeat.south: 9},
      },
      firstRound: 1,
      currentRound: 4,
      currentScores: const {},
    );
    expect(lines.map((l) => l.roundNumber), [1, 4]);
    expect(lines.last.deltas, isEmpty);
  });
}
