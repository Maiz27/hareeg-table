import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/data/persistence/match_history_repository.dart';
import 'package:hareeg_table/data/persistence/match_repository.dart';
import 'package:hareeg_table/data/persistence/replay_file_store.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/analysis_coach_settings.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_summary.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_statistics.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';
import 'package:hareeg_table/ui/features/history/views/match_history_screen.dart';
import 'package:hareeg_table/ui/features/history/widgets/match_history_entry_card.dart';
import 'package:hareeg_table/ui/features/replay/views/branch_sandbox_host.dart';
import 'package:hareeg_table/ui/features/replay/views/match_replay_screen.dart';
import 'package:hareeg_table/ui/features/replay/widgets/analysis_coach_panel.dart';
import 'package:hareeg_table/ui/features/replay/widgets/replay_hud_clusters.dart';

import '../support/branch_sandbox_harness.dart';
import '../support/test_fixtures.dart';

/// The whole PRD, walked once: a match ends, becomes history, becomes
/// statistics, becomes a replay, becomes a sandbox — and the sandbox changes
/// none of it.
///
/// **The walk starts from a seeded near-terminal active match, not a fresh
/// deal.** Completing a real match through the UI is roughly seventeen hundred
/// applied actions; what matters here is the seam between a *real* completion
/// and everything downstream of it, and that seam is reached the same way
/// either side of the shortcut. The finish itself — meld, discard, go out — is
/// played through the real table.
const _matchId = 'm-e2e-aaaaaaaa';

/// Every opponent sits one round-penalty below the elimination score, so
/// south's finish eliminates all three at once and south wins the match.
Map<PlayerSeat, int> get _terminalScores => const {
  PlayerSeat.south: 0,
  PlayerSeat.east: 30,
  PlayerSeat.north: 30,
  PlayerSeat.west: 30,
};

ClassicHareegMatchSnapshot _nearTerminalSnapshot() {
  final setup = ClassicHareegSetup.defaults();
  final dealt = ClassicHareegRound.deal(setup: setup, seed: 3);
  return ClassicHareegMatchSnapshot(
    setup: setup,
    hands: {...dealt.hands, PlayerSeat.south: branchFinishingHand},
    stock: dealt.stock,
    discardPile: const [],
    starter: dealt.starter,
    currentSeat: PlayerSeat.south,
    turnPhase: TurnPhase.action,
    openingState: branchOpened(PlayerSeat.south),
    scores: _terminalScores,
    roundNumber: 3,
    savedAt: DateTime.utc(2026, 6, 1),
  );
}

typedef _Stores = ({
  MemoryKeyValueStore historyStore,
  MemoryKeyValueStore matchStore,
  MemoryReplayFileStore replayFiles,
  LocalMatchRepository matches,
  LocalMatchHistoryRepository history,
});

_Stores _buildStores() {
  final historyStore = MemoryKeyValueStore();
  final matchStore = MemoryKeyValueStore();
  final replayFiles = MemoryReplayFileStore();
  final matches = LocalMatchRepository(
    store: matchStore,
    mintMatchId: () async => _matchId,
  );
  return (
    historyStore: historyStore,
    matchStore: matchStore,
    replayFiles: replayFiles,
    matches: matches,
    history: LocalMatchHistoryRepository(
      store: historyStore,
      replayFiles: replayFiles,
      matches: matches,
    ),
  );
}

Widget _app(_Stores stores, {required String route}) {
  return HareegTableApp(
    // A fresh key per mount. `initialRouteOverride` is read once, in
    // `initState`; without this, pumping the app again at a different route
    // would reuse the previous `State` and quietly stay where it was.
    key: UniqueKey(),
    matchRepository: stores.matches,
    historyRepository: stores.history,
    preferencesRepository: MemoryPreferencesRepository(),
    learningProgressRepository: MemoryLearningProgressRepository(),
    initialRouteOverride: route,
  );
}

void main() {
  final strings = AppStrings.english;

  setUp(() {
    final prior = ShowcaseCardFan.disableLoopingMotionForTesting;
    ShowcaseCardFan.disableLoopingMotionForTesting = true;
    addTearDown(() => ShowcaseCardFan.disableLoopingMotionForTesting = prior);
  });

  // The menu, history and statistics screens are portrait surfaces; the
  // table, the replay viewer and the sandbox are landscape ones. A single
  // viewport for both would push a real control off-screen and turn a missed
  // tap into a passing test, so the walk resizes as the app would rotate.
  void sizePortrait(WidgetTester tester) {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  void sizeLandscape(WidgetTester tester) {
    tester.view.physicalSize = const Size(1688, 780);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  /// Resumes the seeded match from Home and plays it out to a win.
  Future<void> resumeFromHome(WidgetTester tester, _Stores stores) async {
    sizePortrait(tester);
    await tester.pumpWidget(_app(stores, route: AppRoutes.home));
    await tester.pumpAndSettle(const Duration(seconds: 60));

    await tester.tap(find.text(strings.continueGame));
    await tester.pumpAndSettle(const Duration(seconds: 60));
    sizeLandscape(tester);
    await tester.pumpAndSettle(const Duration(seconds: 60));
  }

  Future<void> resumeAndFinish(WidgetTester tester, _Stores stores) async {
    await resumeFromHome(tester, stores);
    await branchFinishRound(tester);
    await tester.pumpAndSettle(const Duration(seconds: 60));
  }

  /// Opens the archived match's replay from the history list.
  Future<void> openReplayFromHistory(
    WidgetTester tester,
    _Stores stores,
  ) async {
    sizePortrait(tester);
    await tester.pumpWidget(_app(stores, route: AppRoutes.history));
    await tester.pumpAndSettle(const Duration(seconds: 60));
    expect(find.byType(MatchHistoryEntryCard), findsOneWidget);

    await tester.tap(find.text(strings.replayTitle).last);
    await tester.pumpAndSettle(const Duration(seconds: 90));
    sizeLandscape(tester);
    await tester.pumpAndSettle(const Duration(seconds: 60));
    expect(find.byType(MatchReplayScreen), findsOneWidget);
  }

  /// Opens the analysis surface and steps until it produces a **result**.
  ///
  /// "The Analysis button exists" is what round 1 asserted, and it is true of a
  /// coach that never says anything. What is checked here is the rendered
  /// panel's own insight list, the presented sentence reaching the screen, and
  /// the absence of both stand-ins — "nothing to review" (this frame is not a
  /// move) and "nothing worth flagging" (it is, and the coach was silent).
  Future<void> assertAnalysisProducesAResult(WidgetTester tester) async {
    await tester.tap(find.byTooltip(strings.replayCoachTitle));
    await tester.pumpAndSettle(const Duration(seconds: 30));

    AnalysisCoachPanel panel() => tester.widget<AnalysisCoachPanel>(
      find.byType(AnalysisCoachPanel).first,
    );

    // Ask the coach to narrate everything, through its own control. The
    // default filters to key moments, and a walk that only ever saw the
    // filtered view could not tell "the analysis is silent here" from "the
    // analysis does not work".
    await tester.tap(find.byType(PopupMenuButton<AnalysisVerbosity>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.replayVerbosityNarrateAll).last);
    await tester.pumpAndSettle(const Duration(seconds: 30));
    expect(panel().settings.verbosity, AnalysisVerbosity.narrateAll);

    final next = find.byTooltip(strings.replayNext);
    final nextButton = find.ancestor(
      of: next,
      matching: find.byType(ReplayRailButton),
    );
    var steps = 0;
    while (panel().insights.isEmpty) {
      expect(
        tester.widget<ReplayRailButton>(nextButton.first).onPressed,
        isNotNull,
        reason:
            'the replay ran out of frames before the analysis said anything, '
            'so this walk never exercised a real analysis result',
      );
      expect(steps, lessThan(80), reason: 'the analysis never produced one');
      await tester.tap(next);
      await tester.pumpAndSettle(const Duration(seconds: 30));
      steps += 1;
    }

    final rendered = panel();
    expect(rendered.reviewable, isTrue);
    expect(
      find.text(rendered.presenter.sentenceFor(rendered.insights.first)),
      findsWidgets,
      reason: 'the insight must reach the screen, not just the widget',
    );
    expect(find.text(strings.replayCoachNothingToReview), findsNothing);
    expect(find.text(strings.replayCoachQuiet), findsNothing);
  }

  /// Enters the sandbox from the frame under the cursor and applies a real
  /// south action, proven by the exit asking for confirmation — which it only
  /// does once the session has diverged.
  Future<void> branchPlayAndLeave(
    WidgetTester tester, {
    required String choice,
  }) async {
    // Stepping to find an insight can land on the terminal frame, which
    // refuses to branch — correctly. Step back to the nearest frame that
    // offers one, so the walk branches from a real decision point.
    final control = find.byKey(const ValueKey('replay-branch-control'));
    var back = 0;
    while (tester.widget<ReplayRailButton>(control).onPressed == null) {
      expect(back, lessThan(20), reason: 'no branchable frame to walk from');
      await tester.tap(find.byTooltip(strings.replayPrevious));
      await tester.pumpAndSettle(const Duration(seconds: 30));
      back += 1;
    }

    await tester.tap(control);
    await tester.pumpAndSettle();
    final entry = find.byKey(ValueKey(choice));
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle(const Duration(seconds: 90));
    expect(find.byType(BranchSandboxHost), findsOneWidget);

    await branchSettleToSouthTurn(tester);
    expect(
      await branchPlayOneSouthAction(tester),
      isTrue,
      reason: 'the sandbox must actually be played, not merely entered',
    );

    // Exact post-meld replay frames leave only the final discard in hand.
    // Playing it completes this fixture; use the completion panel's real exit,
    // not the background control that the modal correctly blocks.
    if (find.text(strings.branchCompletionTitle).evaluate().isNotEmpty) {
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.ensureVisible(find.text(strings.branchReturnToReplay));
      await tester.tap(find.text(strings.branchReturnToReplay));
    } else {
      await tester.tap(find.byKey(const ValueKey('branch-exit')));
    }
    await tester.pumpAndSettle();
    expect(
      find.text(strings.branchExitTitle),
      findsOneWidget,
      reason:
          'a diverged sandbox confirms on exit; no confirmation means nothing '
          'was applied and the comparison below would be vacuous',
    );
    await tester.tap(find.text(strings.branchExitConfirm));
    await tester.pumpAndSettle(const Duration(seconds: 90));
    expect(find.byType(BranchSandboxHost), findsNothing);
    expect(find.byType(MatchReplayScreen), findsOneWidget);
  }

  /// Reads history and statistics straight from the stores.
  Future<({List<MatchHistorySummary> summaries, MatchStatisticsReport stats})>
  readDurableState(_Stores stores) async {
    final listed = await stores.history.listSummaries();
    expect(listed, isA<MatchHistoryListed>());
    final summaries = (listed as MatchHistoryListed).summaries;
    return (
      summaries: summaries,
      stats: MatchStatisticsReport.fromSummaries(summaries),
    );
  }

  testWidgets(
    'a completed match becomes history, statistics, a replay and a sandbox '
    'that changes none of them',
    (tester) async {
      final stores = _buildStores();
      await stores.matches.saveActiveMatch(
        checkpointForSnapshot(_nearTerminalSnapshot(), matchId: _matchId),
      );

      // 1. Play the finish on the real table; the match ends and archives.
      await resumeAndFinish(tester, stores);

      final afterArchive = await readDurableState(stores);
      expect(
        afterArchive.summaries.map((s) => s.matchId),
        [_matchId],
        reason: 'the completed match must reach history',
      );
      final archived = afterArchive.summaries.single;
      expect(archived.winner, PlayerSeat.south);
      expect(archived.replayable, isTrue);
      // 2. Statistics reflect it.
      expect(afterArchive.stats.overall.gamesPlayed, 1);
      expect(afterArchive.stats.overall.winRate, 1.0);
      expect(afterArchive.stats.overall.averagePlacement, 1.0);
      // And the replay record is really there, not merely promised.
      expect(await stores.replayFiles.listKeys(), [_matchId]);

      // 3. The entry is browsable, and offers its replay.
      await openReplayFromHistory(tester, stores);

      // 4. The analysis coach runs on the reviewed position and says
      // something.
      await assertAnalysisProducesAResult(tester);

      // 5. Branch in, play a real action, and leave.
      await branchPlayAndLeave(tester, choice: 'branch-entry-blind');

      // 6. Nothing downstream moved.
      final afterBranch = await readDurableState(stores);
      expect(
        afterBranch.summaries.map((s) => s.toJson()),
        afterArchive.summaries.map((s) => s.toJson()),
        reason: 'the sandbox changed a history summary',
      );
      expect(afterBranch.stats.overall.gamesPlayed, 1);
      expect(afterBranch.stats.overall.winRate, 1.0);
      expect(await stores.replayFiles.listKeys(), [_matchId]);
      expect(
        await stores.matches.loadActiveMatch(),
        isA<ActiveMatchAbsent>(),
        reason: 'the sandbox left no resumable match',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'the same walk survives a close-and-resume before the finish',
    (tester) async {
      final stores = _buildStores();
      await stores.matches.saveActiveMatch(
        checkpointForSnapshot(_nearTerminalSnapshot(), matchId: _matchId),
      );

      // The close: mount the app, resume, then throw the whole tree away
      // without finishing, and relaunch over the same stores. The checkpoint
      // — identity, recorder state, counters — is what has to survive.
      await resumeFromHome(tester, stores);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // The relaunch, and the finish.
      await resumeAndFinish(tester, stores);

      final state = await readDurableState(stores);
      expect(state.summaries.map((s) => s.matchId), [_matchId]);
      expect(state.summaries.single.replayable, isTrue);
      expect(state.stats.overall.gamesPlayed, 1);

      // And the resumed match's replay still opens, still analyses, and still
      // branches into a sandbox that can be played and left.
      await openReplayFromHistory(tester, stores);
      await assertAnalysisProducesAResult(tester);
      await branchPlayAndLeave(tester, choice: 'branch-entry-study');

      // Compared from **outside** the sandbox, after the exit. Round 1
      // compared while still inside it, which cannot see a write that lands on
      // the way out — the one place a sandbox is most likely to make one.
      final after = await readDurableState(stores);
      expect(
        after.summaries.map((s) => s.toJson()),
        state.summaries.map((s) => s.toJson()),
        reason: 'the resumed match sandbox changed a history summary',
      );
      expect(after.stats.overall.gamesPlayed, state.stats.overall.gamesPlayed);
      expect(after.stats.overall.winRate, state.stats.overall.winRate);
      expect(await stores.replayFiles.listKeys(), [_matchId]);
      expect(
        await stores.matches.loadActiveMatch(),
        isA<ActiveMatchAbsent>(),
        reason: 'the sandbox left no resumable match behind',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'a non-replayable entry keeps history and statistics and offers no branch',
    (tester) async {
      sizePortrait(tester);
      final harness = historyHarness(
        summaries: [
          historySummary(matchId: 'm-lost-aaaaaaaa', replayable: false),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AppStringsScope(
            strings: strings,
            child: Directionality(
              textDirection: strings.textDirection,
              child: MatchHistoryScreen(historyRepository: harness.repository),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 30));

      // The entry is still there, with its outcome — losing the replay must
      // not lose the match.
      expect(find.byType(MatchHistoryEntryCard), findsOneWidget);
      // No replay affordance, and therefore no route to a branch at all.
      expect(find.text(strings.replayTitle), findsNothing);
      expect(find.byKey(const ValueKey('replay-branch-control')), findsNothing);
      // And an honest, localized reason rather than a silently missing button.
      expect(find.text(strings.historyReplayUnavailable), findsOneWidget);

      // Statistics still count it.
      final listed = await harness.repository.listSummaries();
      final report = MatchStatisticsReport.fromSummaries(
        (listed as MatchHistoryListed).summaries,
      );
      expect(report.overall.gamesPlayed, 1);
    },
  );

  test('the statistics formulas are unchanged', () {
    // Hand-computed over a fixed fixture, so a formula that drifted would have
    // to drift into exactly these numbers to survive.
    final summaries = <MatchHistorySummary>[
      // Two south wins, four losses.
      historySummary(
        matchId: 'm-stat-aaaaaaa1',
        winner: PlayerSeat.south,
        southPlacement: 1,
        finalScores: const {
          PlayerSeat.south: 10,
          PlayerSeat.east: 40,
          PlayerSeat.north: 45,
          PlayerSeat.west: 50,
        },
        southFiftyAttempts: 2,
        southFiftySuccesses: 1,
      ),
      historySummary(
        matchId: 'm-stat-aaaaaaa2',
        winner: PlayerSeat.south,
        southPlacement: 1,
        finalScores: const {
          PlayerSeat.south: 5,
          PlayerSeat.east: 35,
          PlayerSeat.north: 41,
          PlayerSeat.west: 44,
        },
        southFiftyAttempts: 0,
        southFiftySuccesses: 0,
      ),
      for (var i = 3; i <= 6; i++)
        historySummary(
          matchId: 'm-stat-aaaaaaa$i',
          winner: PlayerSeat.east,
          southPlacement: 3,
          finalScores: const {
            PlayerSeat.south: 42,
            PlayerSeat.east: 12,
            PlayerSeat.north: 44,
            PlayerSeat.west: 46,
          },
          southFiftyAttempts: 1,
          southFiftySuccesses: 0,
        ),
    ];

    final metrics = MatchStatisticsReport.fromSummaries(summaries).overall;

    expect(metrics.gamesPlayed, 6);
    // Win rate: 2 of 6.
    expect(metrics.winRate, closeTo(2 / 6, 1e-9));
    // Average placement: (1 + 1 + 3 + 3 + 3 + 3) / 6.
    expect(metrics.averagePlacement, closeTo(14 / 6, 1e-9));
    // Fifty attempt rate: matches with at least one south attempt (5) over
    // games played (6).
    expect(metrics.fiftyAttemptRate, closeTo(5 / 6, 1e-9));
    // Fifty success rate: successes (1) over attempts (2 + 0 + 1*4 = 6).
    expect(metrics.fiftySuccessRate, closeTo(1 / 6, 1e-9));
    // Scoring margin: best opponent's final score minus south's, averaged.
    // Wins: 40 - 10 = 30 and 35 - 5 = 30. Losses: 12 - 42 = -30, four times.
    expect(metrics.averageScoringMargin, closeTo((30 + 30 - 30 * 4) / 6, 1e-9));
  });
}
