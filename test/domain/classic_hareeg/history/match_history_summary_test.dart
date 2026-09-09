import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_fifty_counters.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_summary.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';

void main() {
  MatchHistorySummary buildSummary({
    DateTime? completedAt,
    bool replayable = true,
    bool countersComplete = true,
  }) {
    return MatchHistorySummary(
      matchId: 'm-abc-aaaaaaaa',
      completedAt: completedAt ?? DateTime.utc(2026, 8, 22, 9, 30),
      setup: ClassicHareegSetup.defaults(),
      finalScores: const {
        PlayerSeat.south: 12,
        PlayerSeat.east: 31,
        PlayerSeat.north: 28,
        PlayerSeat.west: 33,
      },
      winner: PlayerSeat.south,
      southPlacement: 1,
      roundCount: 7,
      coachWasEnabled: true,
      fiftyCounters: MatchFiftyCounters.empty()
          .withAttempt(PlayerSeat.south)
          .withSuccess(PlayerSeat.south)
          .withAttempt(PlayerSeat.east),
      fiftyCountersComplete: countersComplete,
      replayable: replayable,
    );
  }

  group('MatchHistorySummary', () {
    test('round-trips every field through JSON', () {
      final summary = buildSummary();

      final restored = MatchHistorySummary.fromJson(summary.toJson());

      expect(restored.matchId, 'm-abc-aaaaaaaa');
      expect(restored.completedAt, DateTime.utc(2026, 8, 22, 9, 30));
      expect(restored.setup.deckCount, summary.setup.deckCount);
      expect(restored.setup.openingRequirement, summary.setup.openingRequirement);
      expect(restored.finalScores[PlayerSeat.south], 12);
      expect(restored.finalScores[PlayerSeat.east], 31);
      expect(restored.finalScores[PlayerSeat.north], 28);
      expect(restored.finalScores[PlayerSeat.west], 33);
      expect(restored.winner, PlayerSeat.south);
      expect(restored.southPlacement, 1);
      expect(restored.roundCount, 7);
      expect(restored.coachWasEnabled, isTrue);
      expect(restored.fiftyCounters.attemptsFor(PlayerSeat.south), 1);
      expect(restored.fiftyCounters.successesFor(PlayerSeat.south), 1);
      expect(restored.fiftyCounters.attemptsFor(PlayerSeat.east), 1);
      expect(restored.fiftyCountersComplete, isTrue);
      expect(restored.replayable, isTrue);
    });

    test('stores the completion time in UTC', () {
      // A local-time input must not survive as local time, or two devices in
      // different zones would disagree about the order of the same matches.
      final local = DateTime(2026, 8, 22, 9, 30);
      final summary = buildSummary(completedAt: local);

      expect(summary.completedAt.isUtc, isTrue);
      expect(summary.completedAt, local.toUtc());

      final restored = MatchHistorySummary.fromJson(summary.toJson());
      expect(restored.completedAt.isUtc, isTrue);
      expect(restored.completedAt, local.toUtc());
    });

    test('withReplayable leaves counter completeness alone', () {
      // Losing a replay file says nothing about whether the counters were
      // measured, so one flag must never drag the other with it.
      final summary = buildSummary(countersComplete: true);

      final repaired = summary.withReplayable(false);

      expect(repaired.replayable, isFalse);
      expect(repaired.fiftyCountersComplete, isTrue);
      expect(repaired.fiftyCounters.attemptsFor(PlayerSeat.south), 1);
    });

    test('an incomplete-counter summary still carries its other facts', () {
      final summary = buildSummary(countersComplete: false, replayable: false);

      final restored = MatchHistorySummary.fromJson(summary.toJson());

      expect(restored.fiftyCountersComplete, isFalse);
      expect(restored.winner, PlayerSeat.south);
      expect(restored.roundCount, 7);
      expect(restored.finalScores[PlayerSeat.west], 33);
    });

    test('rejects an invalid match id', () {
      expect(
        () => MatchHistorySummary(
          matchId: '../escape',
          completedAt: DateTime.utc(2026),
          setup: ClassicHareegSetup.defaults(),
          finalScores: const {},
          winner: PlayerSeat.south,
          southPlacement: 1,
          roundCount: 1,
          coachWasEnabled: false,
          fiftyCounters: MatchFiftyCounters.empty(),
          fiftyCountersComplete: true,
          replayable: false,
        ),
        throwsArgumentError,
      );
    });

    test('rejects an unsupported schema version', () {
      final json = buildSummary().toJson()..['version'] = 99;

      expect(() => MatchHistorySummary.fromJson(json), throwsFormatException);
    });

    test('rejects a summary missing a required field', () {
      final json = buildSummary().toJson()..remove('winner');

      expect(() => MatchHistorySummary.fromJson(json), throwsFormatException);
    });
  });
}
