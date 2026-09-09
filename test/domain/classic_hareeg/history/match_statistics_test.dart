import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_summary.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_statistics.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';

import '../../../support/test_fixtures.dart';

ClassicHareegSetup setupOf({
  CpuDifficulty difficulty = CpuDifficulty.casual,
  TableStrictness strictness = TableStrictness.standard,
}) {
  return ClassicHareegSetup.defaults().copyWith(
    cpuDifficulty: difficulty,
    tableStrictness: strictness,
  );
}

void main() {
  group('MatchStatisticsMetrics formulas', () {
    test(
      'unknown legacy placement is excluded rather than counted as zero',
      () {
        final unknown = historySummary(
          matchId: 'm-unknown-aaaaaaaa',
          southPlacement: 0,
        );
        expect(
          MatchStatisticsMetrics.fromSummaries([unknown]).averagePlacement,
          isNull,
        );
        final mixed = MatchStatisticsMetrics.fromSummaries([
          unknown,
          historySummary(matchId: 'm-known-aaaaaaaa', southPlacement: 3),
        ]);
        expect(mixed.gamesPlayed, 2);
        expect(mixed.averagePlacement, 3);
      },
    );
    test('win rate counts only south wins', () {
      final metrics = MatchStatisticsMetrics.fromSummaries([
        historySummary(matchId: 'm-a-aaaaaaaa'),
        historySummary(
          matchId: 'm-b-aaaaaaaa',
          winner: PlayerSeat.east,
          southPlacement: 3,
        ),
        historySummary(
          matchId: 'm-c-aaaaaaaa',
          winner: PlayerSeat.north,
          southPlacement: 4,
        ),
      ]);

      expect(metrics.gamesPlayed, 3);
      expect(metrics.wins, 1);
      expect(metrics.winRate, closeTo(1 / 3, 1e-12));
    });

    test('average placement is the mean of stored placements', () {
      final metrics = MatchStatisticsMetrics.fromSummaries([
        historySummary(matchId: 'm-a-aaaaaaaa', southPlacement: 1),
        historySummary(matchId: 'm-b-aaaaaaaa', southPlacement: 4),
      ]);

      expect(metrics.averagePlacement, 2.5);
    });

    test('every rate is null rather than zero when nothing was measured', () {
      final metrics = MatchStatisticsMetrics.fromSummaries(const []);

      // A rendered 0% would claim a measurement that was never taken.
      expect(metrics.gamesPlayed, 0);
      expect(metrics.winRate, isNull);
      expect(metrics.averagePlacement, isNull);
      expect(metrics.fiftyAttemptRate, isNull);
      expect(metrics.fiftySuccessRate, isNull);
      expect(metrics.averageScoringMargin, isNull);
    });

    test('Fifty success rate is unavailable when there were no attempts', () {
      final metrics = MatchStatisticsMetrics.fromSummaries([
        historySummary(matchId: 'm-a-aaaaaaaa'),
        historySummary(matchId: 'm-b-aaaaaaaa'),
      ]);

      expect(metrics.fiftyMeasuredMatches, 2);
      expect(metrics.fiftyAttempts, 0);
      // Attempt rate is a real measurement: two measured matches, no attempts.
      expect(metrics.fiftyAttemptRate, 0.0);
      // Success rate has no denominator at all, which is not the same as zero.
      expect(metrics.fiftySuccessRate, isNull);
    });

    test('unknown counters are excluded from every Fifty figure', () {
      final measured = [
        historySummary(
          matchId: 'm-a-aaaaaaaa',
          southFiftyAttempts: 2,
          southFiftySuccesses: 1,
        ),
        historySummary(matchId: 'm-b-aaaaaaaa'),
      ];

      final withoutLegacy = MatchStatisticsMetrics.fromSummaries(measured);
      final withLegacy = MatchStatisticsMetrics.fromSummaries([
        ...measured,
        // Zero counters that mean "never measured", not "measured as zero".
        historySummary(
          matchId: 'm-legacy-aaaaaaaa',
          fiftyCountersComplete: false,
        ),
      ]);

      expect(withLegacy.gamesPlayed, withoutLegacy.gamesPlayed + 1);
      expect(
        withLegacy.fiftyMeasuredMatches,
        withoutLegacy.fiftyMeasuredMatches,
      );
      expect(withLegacy.fiftyAttemptRate, withoutLegacy.fiftyAttemptRate);
      expect(withLegacy.fiftySuccessRate, withoutLegacy.fiftySuccessRate);
      expect(withLegacy.hasUnmeasuredFiftyMatches, isTrue);
      expect(withoutLegacy.hasUnmeasuredFiftyMatches, isFalse);
    });

    test('Fifty rates use the measured denominators', () {
      final metrics = MatchStatisticsMetrics.fromSummaries([
        historySummary(
          matchId: 'm-a-aaaaaaaa',
          southFiftyAttempts: 3,
          southFiftySuccesses: 1,
        ),
        historySummary(
          matchId: 'm-b-aaaaaaaa',
          southFiftyAttempts: 1,
          southFiftySuccesses: 1,
        ),
        historySummary(matchId: 'm-c-aaaaaaaa'),
        historySummary(matchId: 'm-d-aaaaaaaa', fiftyCountersComplete: false),
      ]);

      expect(metrics.gamesPlayed, 4);
      expect(metrics.fiftyMeasuredMatches, 3);
      expect(metrics.matchesWithFiftyAttempt, 2);
      expect(metrics.fiftyAttemptRate, closeTo(2 / 3, 1e-12));
      expect(metrics.fiftyAttempts, 4);
      expect(metrics.fiftySuccesses, 2);
      expect(metrics.fiftySuccessRate, 0.5);
    });

    test('scoring margin is positive when south finished ahead', () {
      final won = historySummary(
        matchId: 'm-a-aaaaaaaa',
        finalScores: const {
          PlayerSeat.south: 10,
          PlayerSeat.east: 34,
          PlayerSeat.north: 51,
        },
      );
      final lost = historySummary(
        matchId: 'm-b-aaaaaaaa',
        winner: PlayerSeat.east,
        southPlacement: 3,
        finalScores: const {
          PlayerSeat.south: 60,
          PlayerSeat.east: 12,
          PlayerSeat.north: 40,
        },
      );

      // Best opponent is the lowest opponent score: 34 - 10, then 12 - 60.
      expect(MatchStatisticsMetrics.scoringMarginOf(won), 24);
      expect(MatchStatisticsMetrics.scoringMarginOf(lost), -48);

      final metrics = MatchStatisticsMetrics.fromSummaries([won, lost]);
      expect(metrics.marginMatches, 2);
      expect(metrics.averageScoringMargin, (24 - 48) / 2);
    });

    test('a match with no opponent score is excluded from the margin only', () {
      final soloScores = historySummary(
        matchId: 'm-solo-aaaaaaaa',
        finalScores: const {PlayerSeat.south: 10},
      );

      expect(MatchStatisticsMetrics.scoringMarginOf(soloScores), isNull);

      final metrics = MatchStatisticsMetrics.fromSummaries([
        soloScores,
        historySummary(
          matchId: 'm-b-aaaaaaaa',
          finalScores: const {PlayerSeat.south: 5, PlayerSeat.east: 25},
        ),
      ]);

      expect(metrics.gamesPlayed, 2);
      expect(metrics.marginMatches, 1);
      expect(metrics.averageScoringMargin, 20);
    });

    test('input order does not change any figure', () {
      final summaries = [
        historySummary(matchId: 'm-a-aaaaaaaa', southFiftyAttempts: 2),
        historySummary(
          matchId: 'm-b-aaaaaaaa',
          winner: PlayerSeat.west,
          southPlacement: 2,
        ),
        historySummary(matchId: 'm-c-aaaaaaaa', fiftyCountersComplete: false),
      ];

      final forward = MatchStatisticsMetrics.fromSummaries(summaries);
      final backward = MatchStatisticsMetrics.fromSummaries(summaries.reversed);

      expect(backward.gamesPlayed, forward.gamesPlayed);
      expect(backward.winRate, forward.winRate);
      expect(backward.averagePlacement, forward.averagePlacement);
      expect(backward.fiftyMeasuredMatches, forward.fiftyMeasuredMatches);
      expect(backward.fiftyAttemptRate, forward.fiftyAttemptRate);
      expect(backward.fiftySuccessRate, forward.fiftySuccessRate);
      expect(backward.averageScoringMargin, forward.averageScoringMargin);
    });
  });

  group('MatchStatisticsReport grouping', () {
    test('groups iterate in declared order, coaching false before true', () {
      final report = MatchStatisticsReport.fromSummaries([
        historySummary(
          matchId: 'm-a-aaaaaaaa',
          setup: setupOf(difficulty: CpuDifficulty.expert),
          coachWasEnabled: true,
        ),
        historySummary(
          matchId: 'm-b-aaaaaaaa',
          setup: setupOf(difficulty: CpuDifficulty.beginner),
        ),
        historySummary(
          matchId: 'm-c-aaaaaaaa',
          setup: setupOf(
            difficulty: CpuDifficulty.skilled,
            strictness: TableStrictness.table,
          ),
        ),
        historySummary(
          matchId: 'm-d-aaaaaaaa',
          setup: setupOf(strictness: TableStrictness.coaching),
        ),
      ]);

      expect(report.byCpuDifficulty.keys, [
        CpuDifficulty.beginner,
        // m-d is a default-difficulty match, so casual is present and must
        // still sort into its declared position rather than to the end.
        CpuDifficulty.casual,
        CpuDifficulty.skilled,
        CpuDifficulty.expert,
      ]);
      expect(report.byTableStrictness.keys, [
        TableStrictness.coaching,
        TableStrictness.standard,
        TableStrictness.table,
      ]);
      expect(report.byCoachWasEnabled.keys, [false, true]);
    });

    test('a group with no matches is absent, not zero-filled', () {
      final report = MatchStatisticsReport.fromSummaries([
        historySummary(
          matchId: 'm-a-aaaaaaaa',
          setup: setupOf(difficulty: CpuDifficulty.casual),
        ),
      ]);

      // A zero-filled Expert group would be indistinguishable from having
      // played Expert and lost every time.
      expect(report.byCpuDifficulty.containsKey(CpuDifficulty.expert), isFalse);
      expect(report.byCoachWasEnabled.containsKey(true), isFalse);
      expect(report.byCoachWasEnabled.keys, [false]);
    });

    test('every grouping partitions the input', () {
      final summaries = _partitionFixture();
      final report = MatchStatisticsReport.fromSummaries(summaries);

      int sum(Iterable<MatchStatisticsMetrics> metrics) =>
          metrics.fold(0, (total, m) => total + m.gamesPlayed);

      expect(report.overall.gamesPlayed, summaries.length);
      expect(sum(report.byCpuDifficulty.values), summaries.length);
      expect(sum(report.byTableStrictness.values), summaries.length);
      expect(sum(report.byCoachWasEnabled.values), summaries.length);
    });

    test('each group equals the same computation over its filtered subset', () {
      final summaries = _partitionFixture();
      final report = MatchStatisticsReport.fromSummaries(summaries);

      void sameAsSubset(
        MatchStatisticsMetrics group,
        bool Function(MatchHistorySummary) predicate,
      ) {
        final expected = MatchStatisticsMetrics.fromSummaries(
          summaries.where(predicate),
        );
        expect(group.gamesPlayed, expected.gamesPlayed);
        expect(group.wins, expected.wins);
        expect(group.winRate, expected.winRate);
        expect(group.averagePlacement, expected.averagePlacement);
        expect(group.fiftyMeasuredMatches, expected.fiftyMeasuredMatches);
        expect(group.fiftyAttemptRate, expected.fiftyAttemptRate);
        expect(group.fiftySuccessRate, expected.fiftySuccessRate);
        expect(group.averageScoringMargin, expected.averageScoringMargin);
      }

      // Swapping two group keys survives a count sum but not this comparison.
      for (final entry in report.byCpuDifficulty.entries) {
        sameAsSubset(
          entry.value,
          (summary) => summary.setup.cpuDifficulty == entry.key,
        );
      }
      for (final entry in report.byTableStrictness.entries) {
        sameAsSubset(
          entry.value,
          (summary) => summary.setup.tableStrictness == entry.key,
        );
      }
      for (final entry in report.byCoachWasEnabled.entries) {
        sameAsSubset(
          entry.value,
          (summary) => summary.coachWasEnabled == entry.key,
        );
      }
    });

    group('one summary routes to exactly one key', () {
      for (final difficulty in CpuDifficulty.values) {
        test('difficulty ${difficulty.name}', () {
          final report = MatchStatisticsReport.fromSummaries([
            historySummary(
              matchId: 'm-one-aaaaaaaa',
              setup: setupOf(difficulty: difficulty),
            ),
          ]);

          expect(report.byCpuDifficulty.keys, [difficulty]);
          expect(report.byCpuDifficulty[difficulty]!.gamesPlayed, 1);
        });
      }

      for (final tier in TableStrictness.values) {
        test('strictness ${tier.name}', () {
          final report = MatchStatisticsReport.fromSummaries([
            historySummary(
              matchId: 'm-one-aaaaaaaa',
              setup: setupOf(strictness: tier),
            ),
          ]);

          expect(report.byTableStrictness.keys, [tier]);
          expect(report.byTableStrictness[tier]!.gamesPlayed, 1);
        });
      }

      for (final coached in [false, true]) {
        test('coaching $coached', () {
          final report = MatchStatisticsReport.fromSummaries([
            historySummary(matchId: 'm-one-aaaaaaaa', coachWasEnabled: coached),
          ]);

          expect(report.byCoachWasEnabled.keys, [coached]);
          expect(report.byCoachWasEnabled[coached]!.gamesPlayed, 1);
        });
      }
    });
  });

  group('fixed fixture with hand-computed values', () {
    // Six matches, chosen so the unmeasured Fifty match sits inside a group
    // rather than only in the overall set. That is what proves the measured
    // denominator is computed per slice and not inherited from the whole.
    late List<MatchHistorySummary> summaries;
    late MatchStatisticsReport report;

    setUp(() {
      summaries = _fixedFixture();
      report = MatchStatisticsReport.fromSummaries(summaries);
    });

    // Every expected value below is read off the fixture table by hand and
    // written as a literal. None is produced by the production computation, so
    // a formula that changed would have to disagree with these rather than
    // move in step with them.
    //
    // Rows contributing to each slice, from the table on `_fixedFixture`:
    //
    //   overall      f1 f2 f3 f4 f5 f6
    //   casual       f1 f2 f3        strictness standard  f1 f2 f3 f6
    //   skilled      f6             strictness strict     f4 f5
    //   expert       f4 f5          coach off             f3 f4 f5 f6
    //                               coach on              f1 f2
    for (final slice in _expectedSlices) {
      test('exact figures for ${slice.name}', () {
        final metrics = slice.pick(report);
        final expected = slice.expected;

        expect(
          metrics.gamesPlayed,
          expected.gamesPlayed,
          reason: 'gamesPlayed',
        );
        expect(metrics.wins, expected.wins, reason: 'wins');
        expect(
          metrics.winRate,
          closeTo(expected.winRate, 1e-12),
          reason: 'winRate',
        );
        expect(
          metrics.averagePlacement,
          closeTo(expected.averagePlacement, 1e-12),
          reason: 'averagePlacement',
        );
        expect(
          metrics.fiftyMeasuredMatches,
          expected.fiftyMeasuredMatches,
          reason: 'fiftyMeasuredMatches',
        );
        expect(
          metrics.hasUnmeasuredFiftyMatches,
          expected.fiftyMeasuredMatches != expected.gamesPlayed,
          reason: 'hasUnmeasuredFiftyMatches',
        );
        expect(
          metrics.matchesWithFiftyAttempt,
          expected.matchesWithFiftyAttempt,
          reason: 'matchesWithFiftyAttempt',
        );
        expect(
          metrics.fiftyAttempts,
          expected.fiftyAttempts,
          reason: 'fiftyAttempts',
        );
        expect(
          metrics.fiftySuccesses,
          expected.fiftySuccesses,
          reason: 'fiftySuccesses',
        );
        expect(
          metrics.fiftyAttemptRate,
          closeTo(expected.fiftyAttemptRate, 1e-12),
          reason: 'fiftyAttemptRate',
        );
        expect(
          metrics.fiftySuccessRate,
          closeTo(expected.fiftySuccessRate, 1e-12),
          reason: 'fiftySuccessRate',
        );
        expect(
          metrics.marginMatches,
          expected.marginMatches,
          reason: 'marginMatches',
        );
        expect(
          metrics.averageScoringMargin,
          closeTo(expected.averageScoringMargin, 1e-12),
          reason: 'averageScoringMargin',
        );
      });
    }

    test('the oracle covers every group the report produced', () {
      // Without this, adding a group to the report would silently escape the
      // hand-computed values above.
      final covered = _expectedSlices.map((slice) => slice.name).toSet();
      final produced = <String>{
        'overall',
        for (final key in report.byCpuDifficulty.keys) 'difficulty ${key.name}',
        for (final key in report.byTableStrictness.keys)
          'strictness ${key.name}',
        for (final key in report.byCoachWasEnabled.keys) 'coach $key',
      };

      expect(covered, produced);
    });

    test('the unmeasured match sits inside a group, not only overall', () {
      // This is what makes the slice-local disclosure provable: the casual and
      // coach-off groups each hold the legacy match, while expert and coach-on
      // are fully measured.
      expect(
        report.byCpuDifficulty[CpuDifficulty.casual]!.hasUnmeasuredFiftyMatches,
        isTrue,
      );
      expect(
        report.byCpuDifficulty[CpuDifficulty.expert]!.hasUnmeasuredFiftyMatches,
        isFalse,
      );
      expect(
        report.byCoachWasEnabled[false]!.hasUnmeasuredFiftyMatches,
        isTrue,
      );
      expect(
        report.byCoachWasEnabled[true]!.hasUnmeasuredFiftyMatches,
        isFalse,
      );
    });

    test('coaching and strictness are independent groupings', () {
      // The coached pair spans one tier and the uncoached four span two, so
      // neither grouping can be read off the other.
      expect(report.byTableStrictness.length, greaterThan(1));
      expect(report.byCoachWasEnabled.keys, [false, true]);
      expect(
        report.byCoachWasEnabled[false]!.gamesPlayed +
            report.byCoachWasEnabled[true]!.gamesPlayed,
        summaries.length,
      );
    });
  });
}

List<MatchHistorySummary> _partitionFixture() {
  return [
    historySummary(
      matchId: 'm-p1-aaaaaaaa',
      setup: setupOf(difficulty: CpuDifficulty.beginner),
      coachWasEnabled: true,
    ),
    historySummary(
      matchId: 'm-p2-aaaaaaaa',
      setup: setupOf(
        difficulty: CpuDifficulty.casual,
        strictness: TableStrictness.strict,
      ),
      southFiftyAttempts: 2,
      southFiftySuccesses: 1,
    ),
    historySummary(
      matchId: 'm-p3-aaaaaaaa',
      setup: setupOf(
        difficulty: CpuDifficulty.expert,
        strictness: TableStrictness.table,
      ),
      winner: PlayerSeat.east,
      southPlacement: 4,
      fiftyCountersComplete: false,
    ),
    historySummary(
      matchId: 'm-p4-aaaaaaaa',
      setup: setupOf(difficulty: CpuDifficulty.casual),
      coachWasEnabled: true,
      southFiftyAttempts: 1,
    ),
    historySummary(
      matchId: 'm-p5-aaaaaaaa',
      setup: setupOf(difficulty: CpuDifficulty.skilled),
      winner: PlayerSeat.north,
      southPlacement: 2,
    ),
  ];
}

/// Hand-computed values for one slice of the fixed fixture.
typedef _ExpectedMetrics = ({
  int gamesPlayed,
  int wins,
  double winRate,
  double averagePlacement,
  int fiftyMeasuredMatches,
  int matchesWithFiftyAttempt,
  int fiftyAttempts,
  int fiftySuccesses,
  double fiftyAttemptRate,
  double fiftySuccessRate,
  int marginMatches,
  double averageScoringMargin,
});

typedef _ExpectedSlice = ({
  String name,
  MatchStatisticsMetrics Function(MatchStatisticsReport) pick,
  _ExpectedMetrics expected,
});

/// The oracle: every group the fixed fixture produces, with literal values.
///
/// Derived by reading the table on [_fixedFixture], not by running the code
/// under test.
final List<_ExpectedSlice> _expectedSlices = [
  (
    name: 'overall',
    pick: (report) => report.overall,
    // f1..f6. Placements 1,1,1,3,4,2 -> 12/6. Margins 20,10,5,-10,-30,15 -> 10/6.
    expected: (
      gamesPlayed: 6,
      wins: 3,
      winRate: 0.5,
      averagePlacement: 2.0,
      fiftyMeasuredMatches: 5,
      matchesWithFiftyAttempt: 3,
      fiftyAttempts: 6,
      fiftySuccesses: 3,
      fiftyAttemptRate: 3 / 5,
      fiftySuccessRate: 0.5,
      marginMatches: 6,
      averageScoringMargin: 10 / 6,
    ),
  ),
  (
    name: 'difficulty casual',
    pick: (report) => report.byCpuDifficulty[CpuDifficulty.casual]!,
    // f1, f2, f3. All south wins at place 1. f3 is the unmeasured one.
    // Margins 20, 10, 5 -> 35/3.
    expected: (
      gamesPlayed: 3,
      wins: 3,
      winRate: 1.0,
      averagePlacement: 1.0,
      fiftyMeasuredMatches: 2,
      matchesWithFiftyAttempt: 1,
      fiftyAttempts: 2,
      fiftySuccesses: 1,
      fiftyAttemptRate: 0.5,
      fiftySuccessRate: 0.5,
      marginMatches: 3,
      averageScoringMargin: 35 / 3,
    ),
  ),
  (
    name: 'difficulty skilled',
    pick: (report) => report.byCpuDifficulty[CpuDifficulty.skilled]!,
    // f6 alone: lost at place 2, one attempt and one success, margin +15.
    expected: (
      gamesPlayed: 1,
      wins: 0,
      winRate: 0.0,
      averagePlacement: 2.0,
      fiftyMeasuredMatches: 1,
      matchesWithFiftyAttempt: 1,
      fiftyAttempts: 1,
      fiftySuccesses: 1,
      fiftyAttemptRate: 1.0,
      fiftySuccessRate: 1.0,
      marginMatches: 1,
      averageScoringMargin: 15.0,
    ),
  ),
  (
    name: 'difficulty expert',
    pick: (report) => report.byCpuDifficulty[CpuDifficulty.expert]!,
    // f4, f5. Places 3 and 4 -> 3.5. Margins -10 and -30 -> -20.
    expected: (
      gamesPlayed: 2,
      wins: 0,
      winRate: 0.0,
      averagePlacement: 3.5,
      fiftyMeasuredMatches: 2,
      matchesWithFiftyAttempt: 1,
      fiftyAttempts: 3,
      fiftySuccesses: 1,
      fiftyAttemptRate: 0.5,
      fiftySuccessRate: 1 / 3,
      marginMatches: 2,
      averageScoringMargin: -20.0,
    ),
  ),
  (
    name: 'strictness standard',
    pick: (report) => report.byTableStrictness[TableStrictness.standard]!,
    // f1, f2, f3, f6. Wins f1/f2/f3 -> 3/4. Places 1,1,1,2 -> 5/4.
    // Measured f1, f2, f6. Attempts 2+0+1, successes 1+0+1.
    // Margins 20, 10, 5, 15 -> 50/4.
    expected: (
      gamesPlayed: 4,
      wins: 3,
      winRate: 0.75,
      averagePlacement: 1.25,
      fiftyMeasuredMatches: 3,
      matchesWithFiftyAttempt: 2,
      fiftyAttempts: 3,
      fiftySuccesses: 2,
      fiftyAttemptRate: 2 / 3,
      fiftySuccessRate: 2 / 3,
      marginMatches: 4,
      averageScoringMargin: 12.5,
    ),
  ),
  (
    name: 'strictness strict',
    pick: (report) => report.byTableStrictness[TableStrictness.strict]!,
    // f4, f5 — the same pair as the expert group, reached by a different key.
    expected: (
      gamesPlayed: 2,
      wins: 0,
      winRate: 0.0,
      averagePlacement: 3.5,
      fiftyMeasuredMatches: 2,
      matchesWithFiftyAttempt: 1,
      fiftyAttempts: 3,
      fiftySuccesses: 1,
      fiftyAttemptRate: 0.5,
      fiftySuccessRate: 1 / 3,
      marginMatches: 2,
      averageScoringMargin: -20.0,
    ),
  ),
  (
    name: 'coach false',
    pick: (report) => report.byCoachWasEnabled[false]!,
    // f3, f4, f5, f6. Only f3 is a win. Places 1,3,4,2 -> 10/4.
    // Measured f4, f5, f6. Attempts 3+0+1, successes 1+0+1.
    // Margins 5, -10, -30, 15 -> -20/4.
    expected: (
      gamesPlayed: 4,
      wins: 1,
      winRate: 0.25,
      averagePlacement: 2.5,
      fiftyMeasuredMatches: 3,
      matchesWithFiftyAttempt: 2,
      fiftyAttempts: 4,
      fiftySuccesses: 2,
      fiftyAttemptRate: 2 / 3,
      fiftySuccessRate: 0.5,
      marginMatches: 4,
      averageScoringMargin: -5.0,
    ),
  ),
  (
    name: 'coach true',
    pick: (report) => report.byCoachWasEnabled[true]!,
    // f1, f2. Both wins at place 1. Margins 20 and 10 -> 15.
    expected: (
      gamesPlayed: 2,
      wins: 2,
      winRate: 1.0,
      averagePlacement: 1.0,
      fiftyMeasuredMatches: 2,
      matchesWithFiftyAttempt: 1,
      fiftyAttempts: 2,
      fiftySuccesses: 1,
      fiftyAttemptRate: 0.5,
      fiftySuccessRate: 0.5,
      marginMatches: 2,
      averageScoringMargin: 15.0,
    ),
  ),
];

/// Six matches with every figure hand-computed in the assertions above.
///
/// | id | difficulty | strictness | coach | won | place | fifty a/s | measured | margin |
/// | f1 | casual     | standard   | yes   | yes | 1     | 2 / 1     | yes      | +20 |
/// | f2 | casual     | standard   | yes   | yes | 1     | 0 / 0     | yes      | +10 |
/// | f3 | casual     | standard   | no    | yes | 1     | -         | **no**   | +5  |
/// | f4 | expert     | strict     | no    | no  | 3     | 3 / 1     | yes      | -10 |
/// | f5 | expert     | strict     | no    | no  | 4     | 0 / 0     | yes      | -30 |
/// | f6 | skilled    | standard   | no    | no  | 2     | 1 / 1     | yes      | +15 |
List<MatchHistorySummary> _fixedFixture() {
  Map<PlayerSeat, int> scores(int south, int bestOpponent) => {
    PlayerSeat.south: south,
    PlayerSeat.east: bestOpponent,
    PlayerSeat.north: bestOpponent + 12,
    PlayerSeat.west: bestOpponent + 25,
  };

  return [
    historySummary(
      matchId: 'm-f1-aaaaaaaa',
      setup: setupOf(difficulty: CpuDifficulty.casual),
      coachWasEnabled: true,
      southFiftyAttempts: 2,
      southFiftySuccesses: 1,
      finalScores: scores(10, 30),
    ),
    historySummary(
      matchId: 'm-f2-aaaaaaaa',
      setup: setupOf(difficulty: CpuDifficulty.casual),
      coachWasEnabled: true,
      finalScores: scores(20, 30),
    ),
    historySummary(
      matchId: 'm-f3-aaaaaaaa',
      setup: setupOf(difficulty: CpuDifficulty.casual),
      fiftyCountersComplete: false,
      finalScores: scores(25, 30),
    ),
    historySummary(
      matchId: 'm-f4-aaaaaaaa',
      setup: setupOf(
        difficulty: CpuDifficulty.expert,
        strictness: TableStrictness.strict,
      ),
      winner: PlayerSeat.east,
      southPlacement: 3,
      southFiftyAttempts: 3,
      southFiftySuccesses: 1,
      finalScores: scores(40, 30),
    ),
    historySummary(
      matchId: 'm-f5-aaaaaaaa',
      setup: setupOf(
        difficulty: CpuDifficulty.expert,
        strictness: TableStrictness.strict,
      ),
      winner: PlayerSeat.north,
      southPlacement: 4,
      finalScores: scores(60, 30),
    ),
    historySummary(
      matchId: 'm-f6-aaaaaaaa',
      setup: setupOf(difficulty: CpuDifficulty.skilled),
      winner: PlayerSeat.west,
      southPlacement: 2,
      southFiftyAttempts: 1,
      southFiftySuccesses: 1,
      finalScores: scores(15, 30),
    ),
  ];
}
