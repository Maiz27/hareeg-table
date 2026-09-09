import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_summary.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/core/theme/lounge_tokens.dart';
import 'package:hareeg_table/ui/features/history/views/match_history_screen.dart';
import 'package:hareeg_table/ui/features/history/widgets/match_history_entry_card.dart';

import '../../../support/test_fixtures.dart';

/// Counts listings without widening the shared fake for one test.
class _CountingHistoryRepository extends MemoryMatchHistoryRepository {
  int listCalls = 0;

  @override
  Future<MatchHistoryListOutcome> listSummaries() {
    listCalls += 1;
    return super.listSummaries();
  }
}

class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }

  /// Routes pushed on top of the screen under test.
  Iterable<Route<dynamic>> get afterFirst => pushed.skip(1);
}

Widget _historyApp(
  _CountingHistoryRepository repository,
  _RecordingObserver observer,
) {
  return MaterialApp(
    navigatorObservers: [observer],
    routes: {
      // A stand-in for the viewer, with real chrome so Back behaves the way
      // it does in the app.
      AppRoutes.replay: (context) => Scaffold(
        appBar: AppBar(title: const Text('replay')),
        body: const SizedBox.shrink(),
      ),
      AppRoutes.statistics: (context) => const Scaffold(body: Text('stats')),
    },
    home: MatchHistoryScreen(historyRepository: repository),
  );
}

void main() {
  late _CountingHistoryRepository repository;
  late _RecordingObserver observer;

  setUp(() {
    repository = _CountingHistoryRepository();
    observer = _RecordingObserver();
  });

  void seed(MatchHistorySummary summary) =>
      repository.summaries[summary.matchId] = summary;

  testWidgets('a replayable match offers a way in', (tester) async {
    seed(historySummary(matchId: 'm-good-aaaaaaaa'));

    await tester.pumpWidget(_historyApp(repository, observer));
    await tester.pumpAndSettle();

    expect(find.byType(MatchHistoryEntryCard), findsOneWidget);
    expect(find.text(AppStrings.english.replayTitle), findsOneWidget);

    await tester.tap(find.text(AppStrings.english.replayTitle));
    await tester.pumpAndSettle();

    expect(observer.afterFirst, hasLength(1));
    expect(
      observer.afterFirst.single.settings.name,
      AppRoutes.replay,
      reason: 'the entry must open the replay viewer',
    );
    // The summary travels with the route; the viewer is not asked to look it
    // up again.
    expect(
      observer.afterFirst.single.settings.arguments,
      isA<MatchHistorySummary>(),
    );
  });

  testWidgets('a match with no replay offers nothing to tap', (tester) async {
    seed(historySummary(matchId: 'm-lost-aaaaaaaa', replayable: false));

    await tester.pumpWidget(_historyApp(repository, observer));
    await tester.pumpAndSettle();

    // The state is still stated plainly — silence would be indistinguishable
    // from a bug.
    expect(find.text(AppStrings.english.historyReplayUnavailable), findsOneWidget);
    expect(find.text(AppStrings.english.replayTitle), findsNothing);

    // And tapping the card itself goes nowhere, rather than to a dead end.
    await tester.tap(find.byType(MatchHistoryEntryCard));
    await tester.pumpAndSettle();
    expect(observer.afterFirst, isEmpty);
  });

  testWidgets('only the replayable entries are actionable in a mixed list', (
    tester,
  ) async {
    seed(historySummary(matchId: 'm-one-aaaaaaaa'));
    seed(historySummary(matchId: 'm-two-aaaaaaaa', replayable: false));
    seed(historySummary(matchId: 'm-three-aaaaaaaa'));

    await tester.pumpWidget(_historyApp(repository, observer));
    await tester.pumpAndSettle();

    expect(find.byType(MatchHistoryEntryCard), findsNWidgets(3));
    expect(find.text(AppStrings.english.replayTitle), findsNWidgets(2));
    expect(
      find.text(AppStrings.english.historyReplayUnavailable),
      findsOneWidget,
    );
  });

  testWidgets('the way in is named for a screen reader and big enough to hit', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    seed(historySummary(matchId: 'm-good-aaaaaaaa'));

    await tester.pumpWidget(_historyApp(repository, observer));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(AppStrings.english.replayTitle),
      findsWidgets,
    );
    expect(
      tester.getSize(find.text(AppStrings.english.replayTitle)).height,
      lessThanOrEqualTo(LoungeTokens.tapTargetCardShort),
    );

    final button = find.ancestor(
      of: find.text(AppStrings.english.replayTitle),
      matching: find.byType(TextButton),
    );
    expect(
      tester.getSize(button).height,
      greaterThanOrEqualTo(LoungeTokens.tapTargetCardShort),
    );

    handle.dispose();
  });

  testWidgets('returning from a replay re-reads history', (tester) async {
    seed(historySummary(matchId: 'm-good-aaaaaaaa'));

    await tester.pumpWidget(_historyApp(repository, observer));
    await tester.pumpAndSettle();
    final listingsBefore = repository.listCalls;

    await tester.tap(find.text(AppStrings.english.replayTitle));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Opening a replay can repair the entry, so a stale list would keep
    // offering a replay that has just been withdrawn.
    expect(repository.listCalls, greaterThan(listingsBefore));
  });
}
