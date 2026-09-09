import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/match_history_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_summary.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_statistics.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/history/match_statistics_format.dart';
import 'package:hareeg_table/ui/features/history/views/match_statistics_screen.dart';

import '../../../support/test_fixtures.dart';

const _viewports = <String, Size>{
  'narrow portrait': Size(320, 568),
  'short landscape': Size(740, 360),
};

ClassicHareegSetup setupOf({
  CpuDifficulty difficulty = CpuDifficulty.casual,
  TableStrictness strictness = TableStrictness.standard,
}) {
  return ClassicHareegSetup.defaults().copyWith(
    cpuDifficulty: difficulty,
    tableStrictness: strictness,
  );
}

Future<void> pumpStatistics(
  WidgetTester tester,
  MatchHistoryRepository repository, {
  AppStrings strings = AppStrings.english,
  // Tall by default so every slice is built and in the tree: the list is lazy,
  // and a content assertion must not fail merely because a section was below
  // the fold. Realistic sizes are exercised by the layout group instead.
  Size size = const Size(420, 5000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(strings.languageCode),
      home: AppStringsScope(
        strings: strings,
        child: Directionality(
          textDirection: strings.textDirection,
          child: MatchStatisticsScreen(historyRepository: repository),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Every rendered string inside [scope].
List<String> textsWithin(WidgetTester tester, Finder scope) {
  return tester
      .widgetList<Text>(find.descendant(of: scope, matching: find.byType(Text)))
      .map((text) => text.data)
      .whereType<String>()
      .toList();
}

/// The subtree of one named slice.
Finder slice(String id) => find.byKey(ValueKey('stats-slice-$id'));

void main() {
  group('figures come from the domain computation', () {
    testWidgets('overall tiles match the report exactly', (tester) async {
      final summaries = [
        historySummary(
          matchId: 'm-a-aaaaaaaa',
          southFiftyAttempts: 3,
          southFiftySuccesses: 1,
          finalScores: const {
            PlayerSeat.south: 10,
            PlayerSeat.east: 30,
            PlayerSeat.north: 44,
          },
        ),
        historySummary(
          matchId: 'm-b-aaaaaaaa',
          winner: PlayerSeat.east,
          southPlacement: 3,
          finalScores: const {
            PlayerSeat.south: 55,
            PlayerSeat.east: 15,
            PlayerSeat.north: 44,
          },
        ),
      ];

      await pumpStatistics(
        tester,
        historyHarness(summaries: summaries).repository,
      );

      // Expected values are taken from the domain function, so a formula that
      // migrated into the widget would disagree with this rather than agree.
      final expected = MatchStatisticsReport.fromSummaries(summaries).overall;
      final rendered = textsWithin(tester, slice('overall'));

      expect(rendered, contains(MatchStatisticsFormat.count(expected.gamesPlayed)));
      expect(rendered, contains(MatchStatisticsFormat.percent(expected.winRate)));
      expect(
        rendered,
        contains(MatchStatisticsFormat.average(expected.averagePlacement)),
      );
      expect(
        rendered,
        contains(MatchStatisticsFormat.percent(expected.fiftyAttemptRate)),
      );
      expect(
        rendered,
        contains(MatchStatisticsFormat.percent(expected.fiftySuccessRate)),
      );
      expect(
        rendered,
        contains(
          MatchStatisticsFormat.signedMargin(expected.averageScoringMargin),
        ),
      );
    });

    testWidgets('reads no replay payloads', (tester) async {
      final harness = historyHarness(
        summaries: [
          historySummary(matchId: 'm-a-aaaaaaaa'),
          historySummary(matchId: 'm-b-aaaaaaaa'),
        ],
      );

      await pumpStatistics(tester, harness.repository);

      expect(harness.replayFiles.readFileCalls, 0);
    });

    testWidgets('all three groupings render, coaching false before true', (
      tester,
    ) async {
      await pumpStatistics(
        tester,
        historyHarness(summaries: _mixedFixture()).repository,
      );
      final strings = AppStrings.english;

      expect(find.text(strings.statsByDifficultyHeading), findsOneWidget);
      expect(find.text(strings.statsByStrictnessHeading), findsOneWidget);
      expect(find.text(strings.statsByCoachHeading), findsOneWidget);

      final rendered = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .toList();
      expect(
        rendered.indexOf(strings.statsCoachOffGroup),
        lessThan(rendered.indexOf(strings.statsCoachOnGroup)),
      );
    });

    testWidgets('a group nobody played is absent, not zero-filled', (
      tester,
    ) async {
      await pumpStatistics(
        tester,
        historyHarness(
          summaries: [
            historySummary(
              matchId: 'm-a-aaaaaaaa',
              setup: setupOf(difficulty: CpuDifficulty.casual),
            ),
          ],
        ).repository,
      );

      expect(
        find.text(AppStrings.english.cpuDifficultyLabel(CpuDifficulty.expert)),
        findsNothing,
      );
      expect(find.text(AppStrings.english.statsCoachOnGroup), findsNothing);
    });
  });

  group('Fifty sample disclosure is slice-local', () {
    testWidgets('present inside the mixed group, absent inside the measured one', (
      tester,
    ) async {
      // One mixed group beside one fully measured group. The overall slice
      // necessarily discloses too — a single unmeasured match anywhere makes
      // the overall counts differ — so the proof that this is slice-local is
      // the *absence* inside the fully measured group's own subtree.
      await pumpStatistics(
        tester,
        historyHarness(summaries: _mixedFixture()).repository,
      );
      final strings = AppStrings.english;

      final mixedNote = strings.statsFiftyMeasuredNote(1, 2);
      expect(
        textsWithin(tester, slice('difficulty-${strings.casual}')),
        contains(mixedNote),
      );

      final measuredGroup = textsWithin(
        tester,
        slice('difficulty-${strings.expert}'),
      );
      expect(
        measuredGroup.where((t) => t.contains('Fifty figures from')),
        isEmpty,
        reason:
            'A fully measured group must not inherit another group\'s caveat.',
      );

      // And the overall slice, which does contain an unmeasured match.
      expect(
        textsWithin(tester, slice('overall')).where(
          (t) => t.contains('Fifty figures from'),
        ),
        isNotEmpty,
      );
    });

    testWidgets('absent everywhere when every match was measured', (
      tester,
    ) async {
      await pumpStatistics(
        tester,
        historyHarness(
          summaries: [
            historySummary(matchId: 'm-a-aaaaaaaa', southFiftyAttempts: 1),
            historySummary(matchId: 'm-b-aaaaaaaa'),
          ],
        ).repository,
      );

      // Otherwise it becomes permanent chrome nobody reads.
      expect(find.textContaining('Fifty figures from'), findsNothing);
    });
  });

  group('number formatting reaches the screen intact', () {
    testWidgets('one win in three renders 33.3%, not the raw double', (
      tester,
    ) async {
      await pumpStatistics(
        tester,
        historyHarness(
          summaries: [
            historySummary(matchId: 'm-a-aaaaaaaa'),
            historySummary(
              matchId: 'm-b-aaaaaaaa',
              winner: PlayerSeat.east,
              southPlacement: 2,
            ),
            historySummary(
              matchId: 'm-c-aaaaaaaa',
              winner: PlayerSeat.north,
              southPlacement: 3,
            ),
          ],
        ).repository,
      );

      expect(find.text('33.3%'), findsWidgets);
      expect(find.textContaining('33.33333'), findsNothing);
    });

    testWidgets('no rendered number is NaN, Infinity, or over-precise', (
      tester,
    ) async {
      await pumpStatistics(
        tester,
        historyHarness(summaries: _mixedFixture()).repository,
      );

      final numeric = RegExp(r'[-+]?\d+(?:\.\d+)?%?');
      final overPrecise = RegExp(r'\d+\.\d{2,}');

      for (final text in tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()) {
        expect(text, isNot(contains('NaN')), reason: 'Rendered: "$text"');
        expect(text, isNot(contains('Infinity')), reason: 'Rendered: "$text"');
        // Catches a widget that printed a raw Dart double rather than going
        // through the formatter.
        expect(
          overPrecise.hasMatch(text),
          isFalse,
          reason: 'More than one decimal place in: "$text"',
        );
        // Sanity: the scan is actually looking at numbers somewhere.
        numeric.hasMatch(text);
      }

      expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .map((widget) => widget.data)
            .whereType<String>()
            .where(numeric.hasMatch),
        isNotEmpty,
        reason: 'The scan found no numbers at all, so it proved nothing.',
      );
    });

    testWidgets('an unavailable rate renders the marker, never 0%', (
      tester,
    ) async {
      await pumpStatistics(
        tester,
        historyHarness(
          summaries: [historySummary(matchId: 'm-a-aaaaaaaa')],
        ).repository,
      );

      // No Fifty attempts at all, so the success rate has no denominator.
      final overall = textsWithin(tester, slice('overall'));
      expect(overall, contains(MatchStatisticsFormat.unavailable));
    });

    testWidgets('the margin carries a sign and states its direction', (
      tester,
    ) async {
      await pumpStatistics(
        tester,
        historyHarness(
          summaries: [
            historySummary(
              matchId: 'm-a-aaaaaaaa',
              finalScores: const {
                PlayerSeat.south: 10,
                PlayerSeat.east: 30,
              },
            ),
          ],
        ).repository,
      );

      // One match, so every slice reports the same margin.
      expect(find.text('+20.0'), findsWidgets);
      expect(
        textsWithin(tester, slice('overall')),
        contains('+20.0'),
      );
      // A signed number nobody can interpret is not information.
      expect(
        find.text(AppStrings.english.statsMarginDirection),
        findsWidgets,
      );
    });
  });

  group('empty, low-data, and failure states', () {
    testWidgets('no matches shows the empty panel, not a grid of dashes', (
      tester,
    ) async {
      await pumpStatistics(tester, historyHarness().repository);
      final strings = AppStrings.english;

      expect(find.text(strings.statisticsEmptyTitle), findsOneWidget);
      expect(find.text(strings.statsGamesPlayed), findsNothing);
      expect(find.text(MatchStatisticsFormat.unavailable), findsNothing);
    });

    for (final count in [1, 2]) {
      testWidgets('$count match(es) shows the low-data note', (tester) async {
        await pumpStatistics(
          tester,
          historyHarness(summaries: _summaries(count)).repository,
        );

        expect(
          find.text(AppStrings.english.statsLowDataNote(count)),
          findsOneWidget,
        );
      });
    }

    testWidgets('three matches drops the low-data note', (tester) async {
      await pumpStatistics(
        tester,
        historyHarness(summaries: _summaries(3)).repository,
      );

      expect(find.textContaining('Based on just'), findsNothing);
    });

    testWidgets('a retryable failure offers a retry, never zeroed metrics', (
      tester,
    ) async {
      final repository = _FailingListRepository(
        kind: MatchHistoryFailureKind.retryable,
      );

      await pumpStatistics(tester, repository);
      final strings = AppStrings.english;

      expect(find.text(strings.historyLoadFailedRetryableTitle), findsOneWidget);
      expect(find.text(strings.statsGamesPlayed), findsNothing);

      await tester.tap(find.text(strings.historyRetry));
      await tester.pumpAndSettle();
      expect(repository.listCalls, 2);
    });

    testWidgets('a corrupt failure promises no retry', (tester) async {
      final harness = historyHarness();
      corruptHistoryIndex(harness.store);

      await pumpStatistics(tester, harness.repository);
      final strings = AppStrings.english;

      expect(find.text(strings.historyLoadFailedCorruptTitle), findsOneWidget);
      expect(find.text(strings.historyRetry), findsNothing);
      expect(find.text(strings.statisticsEmptyTitle), findsNothing);
    });
  });

  group('layout and RTL', () {
    for (final entry in _viewports.entries) {
      for (final strings in [AppStrings.english, AppStrings.arabic]) {
        testWidgets('${entry.key}, ${strings.languageCode}, with data', (
          tester,
        ) async {
          await pumpStatistics(
            tester,
            historyHarness(summaries: _mixedFixture()).repository,
            strings: strings,
            size: entry.value,
          );

          expect(tester.takeException(), isNull);
          expect(find.text(strings.statisticsTitle), findsOneWidget);
        });

        testWidgets('${entry.key}, ${strings.languageCode}, empty', (
          tester,
        ) async {
          await pumpStatistics(
            tester,
            historyHarness().repository,
            strings: strings,
            size: entry.value,
          );

          expect(tester.takeException(), isNull);
          expect(find.text(strings.statisticsEmptyTitle), findsOneWidget);
        });
      }
    }
  });
}

List<MatchHistorySummary> _summaries(int count) {
  return [
    for (var index = 0; index < count; index++)
      historySummary(
        matchId: 'm-s$index-aaaaaaaa',
        completedAt: DateTime.utc(2026, 1, index + 1),
      ),
  ];
}

/// Casual mixes measured and unmeasured Fifty counters; expert is fully
/// measured. That contrast is what makes the disclosure's scope provable.
List<MatchHistorySummary> _mixedFixture() {
  return [
    historySummary(
      matchId: 'm-c1-aaaaaaaa',
      setup: setupOf(difficulty: CpuDifficulty.casual),
      southFiftyAttempts: 2,
      southFiftySuccesses: 1,
      coachWasEnabled: true,
    ),
    historySummary(
      matchId: 'm-c2-aaaaaaaa',
      setup: setupOf(difficulty: CpuDifficulty.casual),
      fiftyCountersComplete: false,
    ),
    historySummary(
      matchId: 'm-e1-aaaaaaaa',
      setup: setupOf(
        difficulty: CpuDifficulty.expert,
        strictness: TableStrictness.strict,
      ),
      winner: PlayerSeat.east,
      southPlacement: 3,
      southFiftyAttempts: 1,
    ),
    historySummary(
      matchId: 'm-e2-aaaaaaaa',
      setup: setupOf(
        difficulty: CpuDifficulty.expert,
        strictness: TableStrictness.strict,
      ),
      winner: PlayerSeat.north,
      southPlacement: 4,
    ),
  ];
}

class _FailingListRepository extends MemoryMatchHistoryRepository {
  _FailingListRepository({required this.kind});

  final MatchHistoryFailureKind kind;
  int listCalls = 0;

  @override
  Future<MatchHistoryListOutcome> listSummaries() async {
    listCalls++;
    return MatchHistoryListFailed(
      MatchHistoryFailure(kind: kind, message: 'seeded failure'),
    );
  }
}
