import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/match_history_repository.dart';
import 'package:hareeg_table/data/persistence/replay_file_store.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_summary.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/history/views/match_history_screen.dart';

import '../../../support/test_fixtures.dart';

/// Viewport sizes the screen must survive, including a deliberately cramped
/// portrait and a short landscape.
const _viewports = <String, Size>{
  'narrow portrait': Size(320, 568),
  'short landscape': Size(740, 360),
};

Future<void> pumpHistory(
  WidgetTester tester,
  MatchHistoryRepository repository, {
  AppStrings strings = AppStrings.english,
  Size size = const Size(400, 800),
  NavigatorObserver? observer,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(strings.languageCode),
      navigatorObservers: [?observer],
      home: AppStringsScope(
        strings: strings,
        child: Directionality(
          textDirection: strings.textDirection,
          child: MatchHistoryScreen(historyRepository: repository),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('listing', () {
    testWidgets('renders newest-first through the real repository', (
      tester,
    ) async {
      // Seeded out of order on purpose. Ordering belongs to the repository, so
      // the assertion has to travel through it — MemoryMatchHistoryRepository
      // returns an unsorted list and would prove nothing here.
      final harness = historyHarness(
        summaries: [
          historySummary(
            matchId: 'm-mid-aaaaaaaa',
            completedAt: DateTime.utc(2026, 6, 2),
            roundCount: 5,
          ),
          historySummary(
            matchId: 'm-old-aaaaaaaa',
            completedAt: DateTime.utc(2026, 1, 1),
            roundCount: 4,
          ),
          historySummary(
            matchId: 'm-new-aaaaaaaa',
            completedAt: DateTime.utc(2026, 12, 9),
            roundCount: 6,
          ),
        ],
      );

      await pumpHistory(tester, harness.repository, size: const Size(400, 1400));

      final rendered = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .toList();
      final order = [
        rendered.indexWhere((t) => t.contains('6 rounds')),
        rendered.indexWhere((t) => t.contains('5 rounds')),
        rendered.indexWhere((t) => t.contains('4 rounds')),
      ];

      expect(order, everyElement(isNot(-1)));
      expect(order, orderedEquals([...order]..sort()));
    });

    testWidgets('reads no replay payloads while listing', (tester) async {
      final harness = historyHarness(
        summaries: [
          historySummary(matchId: 'm-a-aaaaaaaa'),
          historySummary(matchId: 'm-b-aaaaaaaa'),
          historySummary(matchId: 'm-c-aaaaaaaa'),
        ],
      );

      await pumpHistory(tester, harness.repository, size: const Size(400, 1400));

      // Summary-only is a fact about calls, not about what happens to be on
      // screen. A missing replay is found by set difference, never by reading.
      expect(harness.replayFiles.readFileCalls, 0);
      expect(harness.replayFiles.listKeysCalls, 1);
    });

    testWidgets('shows the whole setup and outcome for an entry', (
      tester,
    ) async {
      final harness = historyHarness(
        summaries: [
          historySummary(
            matchId: 'm-a-aaaaaaaa',
            setup: ClassicHareegSetup.defaults().copyWith(
              cpuDifficulty: CpuDifficulty.expert,
              tableStrictness: TableStrictness.strict,
              deckCount: 3,
              jokerCount: 4,
              openingRequirement: 71,
              fiftyTimerSeconds: 9,
              starterMode: StarterMode.random,
            ),
            winner: PlayerSeat.east,
            southPlacement: 3,
            roundCount: 7,
            finalScores: const {
              PlayerSeat.south: 41,
              PlayerSeat.east: 12,
              PlayerSeat.north: 33,
              PlayerSeat.west: 55,
            },
          ),
        ],
      );

      await pumpHistory(tester, harness.repository, size: const Size(400, 1400));
      final strings = AppStrings.english;

      // Setup: all seven fields, none silently dropped.
      expect(find.text(strings.cpuDifficultyLabel(CpuDifficulty.expert)), findsOneWidget);
      expect(
        find.text(strings.tableStrictnessLabel(TableStrictness.strict)),
        findsOneWidget,
      );
      expect(find.text('3 decks'), findsOneWidget);
      expect(find.text('4 jokers'), findsOneWidget);
      expect(find.text('71 opening'), findsOneWidget);
      expect(find.text('9s'), findsOneWidget);
      expect(find.text(strings.starterModeLabel(StarterMode.random)), findsOneWidget);

      // Outcome: winner, placement, rounds, and a score for every seat.
      expect(find.textContaining(strings.historyWinnerLabel), findsOneWidget);
      expect(find.textContaining('3 of 4'), findsOneWidget);
      expect(find.text('7 rounds'), findsOneWidget);
      for (final seat in PlayerSeat.values) {
        expect(
          find.text(strings.historySeatScore(seat, {
            PlayerSeat.south: 41,
            PlayerSeat.east: 12,
            PlayerSeat.north: 33,
            PlayerSeat.west: 55,
          }[seat]!)),
          findsOneWidget,
          reason: 'Missing a final score for ${seat.name}.',
        );
      }
    });

    testWidgets('states replay availability in both directions', (
      tester,
    ) async {
      final harness = historyHarness(
        summaries: [
          historySummary(matchId: 'm-ok-aaaaaaaa'),
          historySummary(matchId: 'm-no-aaaaaaaa', replayable: false),
        ],
      );

      await pumpHistory(tester, harness.repository, size: const Size(400, 1600));
      final strings = AppStrings.english;

      // The non-replayable entry is listed, not hidden.
      expect(find.text(strings.historyReplayUnavailable), findsOneWidget);
      expect(find.text(strings.historyReplayAvailable), findsOneWidget);
    });

    testWidgets('states the coach flag in both directions', (tester) async {
      final harness = historyHarness(
        summaries: [
          historySummary(matchId: 'm-on-aaaaaaaa', coachWasEnabled: true),
          historySummary(matchId: 'm-off-aaaaaaaa'),
        ],
      );

      await pumpHistory(tester, harness.repository, size: const Size(400, 1600));
      final strings = AppStrings.english;

      expect(find.text(strings.historyCoachOn), findsOneWidget);
      expect(find.text(strings.historyCoachOff), findsOneWidget);
    });

    testWidgets('a summary repaired during listing is still shown', (
      tester,
    ) async {
      // Replayable in the index, but its file is gone. The repository repairs
      // it to non-replayable; the screen must still list it.
      final harness = historyHarness(
        summaries: [historySummary(matchId: 'm-lost-aaaaaaaa')],
        withoutReplayFiles: {'m-lost-aaaaaaaa'},
      );

      await pumpHistory(tester, harness.repository, size: const Size(400, 1400));

      expect(
        find.text(AppStrings.english.historyReplayUnavailable),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('no entry navigates anywhere; replay arrives later', (
      tester,
    ) async {
      final harness = historyHarness(
        summaries: [historySummary(matchId: 'm-a-aaaaaaaa')],
      );
      final observer = _RouteCountingObserver();

      await pumpHistory(
        tester,
        harness.repository,
        size: const Size(400, 1400),
        observer: observer,
      );
      final pushesAfterLoad = observer.pushes;

      // Tapping the card body must go nowhere. Advertising a destination that
      // does not exist yet is worse than saying nothing, and asserting on
      // behaviour rather than on widget types keeps the AppBar's own buttons
      // out of it.
      await tester.tap(
        find.textContaining(AppStrings.english.historyWinnerLabel),
      );
      await tester.pumpAndSettle();

      expect(observer.pushes, pushesAfterLoad);
    });
  });

  group('empty and failure states', () {
    testWidgets('an empty history shows the first-run panel', (tester) async {
      await pumpHistory(tester, historyHarness().repository);
      final strings = AppStrings.english;

      expect(find.text(strings.historyEmptyTitle), findsOneWidget);
      expect(find.text(strings.historyEmptyBody), findsOneWidget);
      expect(find.text(strings.historyRetry), findsNothing);
    });

    testWidgets('a retryable failure invites a retry that re-lists', (
      tester,
    ) async {
      final repository = _FailingListRepository(
        kind: MatchHistoryFailureKind.retryable,
      );

      await pumpHistory(tester, repository);
      final strings = AppStrings.english;

      expect(find.text(strings.historyLoadFailedRetryableTitle), findsOneWidget);
      expect(find.text(strings.historyEmptyTitle), findsNothing);
      expect(repository.listCalls, 1);

      await tester.tap(find.text(strings.historyRetry));
      await tester.pumpAndSettle();

      expect(repository.listCalls, 2);
    });

    testWidgets('a corrupt failure says so and promises no retry', (
      tester,
    ) async {
      // Driven through the repository's genuine corrupt path: bytes that raise
      // a FormatException out of its index read.
      final harness = historyHarness();
      corruptHistoryIndex(harness.store);

      await pumpHistory(tester, harness.repository);
      final strings = AppStrings.english;

      expect(find.text(strings.historyLoadFailedCorruptTitle), findsOneWidget);
      expect(find.text(strings.historyLoadFailedCorruptBody), findsOneWidget);
      // Retrying reads the same bad bytes, so offering one would be a lie.
      expect(find.text(strings.historyRetry), findsNothing);
      expect(find.text(strings.historyEmptyTitle), findsNothing);
    });
  });

  group('delete', () {
    testWidgets('cancelling asks the repository for nothing', (tester) async {
      final repository = _CountingDeleteRepository(
        summaries: [historySummary(matchId: 'm-a-aaaaaaaa')],
      );

      await pumpHistory(tester, repository, size: const Size(400, 1400));
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.english.historyCancel));
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, isEmpty);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('confirming calls deleteMatch once with that entry\'s id', (
      tester,
    ) async {
      final repository = _CountingDeleteRepository(
        summaries: [
          historySummary(matchId: 'm-first-aaaaaaaa'),
          historySummary(matchId: 'm-second-aaaaaaaa'),
        ],
      );

      await pumpHistory(tester, repository, size: const Size(400, 1600));
      // The fake lists in insertion order, so the first delete icon belongs to
      // the first seeded match.
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.english.historyDelete));
      await tester.pumpAndSettle();

      // Exactly one call, for the selected match and not its neighbour.
      expect(repository.deleteCalls, ['m-first-aaaaaaaa']);
    });

    testWidgets('confirming removes both records and leaves the rest', (
      tester,
    ) async {
      final harness = historyHarness(
        summaries: [
          historySummary(
            matchId: 'm-keep-aaaaaaaa',
            completedAt: DateTime.utc(2026, 5),
            roundCount: 9,
          ),
          historySummary(
            matchId: 'm-drop-aaaaaaaa',
            completedAt: DateTime.utc(2026, 4),
            roundCount: 8,
          ),
        ],
      );

      await pumpHistory(tester, harness.repository, size: const Size(400, 1600));
      expect(await harness.replayFiles.inner.listKeys(), hasLength(2));

      // The second card is the older match.
      await tester.tap(find.byIcon(Icons.delete_outline).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.english.historyDelete));
      await tester.pumpAndSettle();

      expect(find.text('8 rounds'), findsNothing);
      expect(find.text('9 rounds'), findsOneWidget);
      // Both records, not just the visible row.
      expect(await harness.replayFiles.inner.listKeys(), ['m-keep-aaaaaaaa']);
      final remaining = await harness.repository.listSummaries();
      expect(
        (remaining as MatchHistoryListed).summaries.map((s) => s.matchId),
        ['m-keep-aaaaaaaa'],
      );
    });

    testWidgets('a retryable delete failure keeps the entry and offers retry', (
      tester,
    ) async {
      final harness = historyHarness(
        summaries: [historySummary(matchId: 'm-a-aaaaaaaa')],
      );
      // A throwing replay delete is the repository's real retryable path.
      final replayFiles = _ThrowingDeleteStore(harness.replayFiles);
      final repository = LocalMatchHistoryRepository(
        store: harness.store,
        replayFiles: replayFiles,
        matches: MemoryMatchRepository(),
      );

      await pumpHistory(tester, repository, size: const Size(400, 1400));
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.english.historyDelete));
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.english.historyDeleteFailedRetryable),
        findsOneWidget,
      );
      expect(replayFiles.deleteAttempts, 1);

      // The retry has to actually retry. An affordance that only looks like
      // one is worse than none, because the player believes they tried again.
      await tester.tap(find.text(AppStrings.english.historyRetry));
      await tester.pumpAndSettle();

      expect(replayFiles.deleteAttempts, 2);
      // Still listed: a failed delete must not look like a successful one.
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('a corrupt delete failure keeps the entry and offers no retry', (
      tester,
    ) async {
      // Driven through the repository's genuine corrupt path rather than a
      // hand-made outcome: the index lists fine, then its bytes are damaged
      // before the delete, so `_readIndex` raises a FormatException *after*
      // the replay file has already gone.
      final harness = historyHarness(
        summaries: [historySummary(matchId: 'm-a-aaaaaaaa')],
      );

      await pumpHistory(tester, harness.repository, size: const Size(400, 1400));
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);

      corruptHistoryIndex(harness.store);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.english.historyDelete));
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.english.historyDeleteFailedCorrupt),
        findsOneWidget,
      );
      // Retrying reads the same bad bytes, so there is nothing honest to offer.
      expect(find.text(AppStrings.english.historyRetry), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });
  });

  group('layout and RTL', () {
    for (final entry in _viewports.entries) {
      for (final strings in [AppStrings.english, AppStrings.arabic]) {
        testWidgets('${entry.key}, ${strings.languageCode}, with entries', (
          tester,
        ) async {
          final harness = historyHarness(
            summaries: [
              historySummary(matchId: 'm-a-aaaaaaaa', coachWasEnabled: true),
              historySummary(matchId: 'm-b-aaaaaaaa', replayable: false),
            ],
          );

          await pumpHistory(
            tester,
            harness.repository,
            strings: strings,
            size: entry.value,
          );

          expect(tester.takeException(), isNull);
          expect(find.text(strings.historyTitle), findsOneWidget);
        });

        testWidgets('${entry.key}, ${strings.languageCode}, empty', (
          tester,
        ) async {
          await pumpHistory(
            tester,
            historyHarness().repository,
            strings: strings,
            size: entry.value,
          );

          expect(tester.takeException(), isNull);
          expect(find.text(strings.historyEmptyTitle), findsOneWidget);
        });
      }
    }
  });
}

/// Counts route pushes so "goes nowhere" is asserted as behaviour.
class _RouteCountingObserver extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

/// Lists a fixed failure, counting how often it was asked.
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

/// Serves seeded summaries and records every delete request.
///
/// Used only where the assertion is about *which call was made*. Both failure
/// paths are driven through the real `LocalMatchHistoryRepository` instead, so
/// the copy and affordances under test are the ones a genuinely broken store
/// produces rather than a hand-made outcome.
class _CountingDeleteRepository extends MemoryMatchHistoryRepository {
  _CountingDeleteRepository({required List<MatchHistorySummary> summaries}) {
    for (final summary in summaries) {
      this.summaries[summary.matchId] = summary;
    }
  }

  final deleteCalls = <String>[];

  @override
  Future<MatchHistoryDeleteOutcome> deleteMatch(String matchId) async {
    deleteCalls.add(matchId);
    return super.deleteMatch(matchId);
  }
}

/// Throws on delete, which is the repository's genuine retryable path.
class _ThrowingDeleteStore implements ReplayFileStore {
  _ThrowingDeleteStore(this._inner);

  final ReplayFileStore _inner;

  /// How often a delete was attempted, so a retry can be proven to retry.
  int deleteAttempts = 0;

  @override
  Future<bool> deleteFile(String key) async {
    deleteAttempts++;
    throw const ReplayFileStoreException(
      code: ReplayFileStoreErrorCode.ioError,
      message: 'seeded backend failure',
    );
  }

  @override
  Future<List<String>> listKeys() => _inner.listKeys();

  @override
  Future<String?> readFile(String key) => _inner.readFile(key);

  @override
  Future<void> writeFile(String key, String contents) =>
      _inner.writeFile(key, contents);
}
