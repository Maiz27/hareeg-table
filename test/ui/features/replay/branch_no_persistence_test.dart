import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/data/persistence/match_history_repository.dart';
import 'package:hareeg_table/data/persistence/match_repository.dart';
import 'package:hareeg_table/data/persistence/learning_progress_repository.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/data/persistence/replay_file_store.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';
import 'package:hareeg_table/ui/features/replay/views/branch_sandbox_host.dart';
import 'package:hareeg_table/ui/features/replay/views/match_replay_screen.dart';
import 'package:hareeg_table/ui/features/replay/widgets/replay_hud_clusters.dart';

import '../../../support/branch_sandbox_harness.dart';
import '../../../support/completed_match_fixture.dart';
import '../../../support/test_fixtures.dart';

/// V11a: a branch sandbox reaches no durable store, proven by recording every
/// attempt rather than by hoping a sentinel throws.
///
/// **The attempt log is the gate, not the exception.** `_persistAndMaybeFinish`
/// wraps its write sites in a catch-all that swallows the error and shows a
/// "couldn't save" snackbar, so a sentinel that only threw would be caught
/// inside the widget and the test would see nothing at all. Every guarded
/// method therefore appends to the log *before* raising.
///
/// **Reads are allowed inside the window.** Loading and re-checking a replay
/// requires them, and a blanket throwing sentinel on the history repository
/// would stop the replay from ever opening — so the replay guard beneath it
/// would never be reached, and the pass would be vacuous.
///
/// **Three armed windows, not one, and the split is forced.** B58 asks the
/// window to span play, the coach, restart, completion, exit, teardown,
/// replay restoration and every final comparison. A single test cannot do
/// that: the teardown case destroys the widget tree, so nothing after it could
/// assert restoration, and completion is only reachable from a late branch
/// point that the lifecycle case must not start from. The lifecycle, the
/// completion and the kill therefore each get their own window, and **each one
/// ends by proving it was still armed** while its own comparisons ran. No
/// window disarms before the assertions it exists to protect.
class _MutationGuard {
  bool armed = false;

  /// Every mutation attempted while armed, in order. Must stay empty.
  final List<String> attempts = <String>[];

  /// Every read that reached a store while armed. Kept so "no attempts" can be
  /// distinguished from "nothing ran at all".
  final List<String> reads = <String>[];

  void read(String what) {
    if (armed) reads.add(what);
  }

  Never Function()? _refuse(String what) {
    if (!armed) return null;
    attempts.add(what);
    return () => throw StateError('Forbidden durable mutation: $what');
  }

  /// Records [what] and refuses it while armed; a no-op before arming, so
  /// fixtures can be seeded through the same objects.
  void guard(String what) {
    final refusal = _refuse(what);
    if (refusal != null) refusal();
  }
}

class _GuardedMatchRepository implements MatchRepository {
  _GuardedMatchRepository(this._guard, this._inner);

  final _MutationGuard _guard;
  final MatchRepository _inner;

  @override
  Future<ActiveMatchLoadOutcome> loadActiveMatch() {
    _guard.read('match.loadActiveMatch');
    return _inner.loadActiveMatch();
  }

  @override
  Future<void> saveActiveMatch(MatchCheckpoint checkpoint) {
    _guard.guard('match.saveActiveMatch');
    return _inner.saveActiveMatch(checkpoint);
  }

  @override
  Future<void> abandonActiveMatch() {
    _guard.guard('match.abandonActiveMatch');
    return _inner.abandonActiveMatch();
  }
}

class _GuardedHistoryRepository implements MatchHistoryRepository {
  _GuardedHistoryRepository(this._guard, this._inner);

  final _MutationGuard _guard;
  final MatchHistoryRepository _inner;

  @override
  Future<MatchHistoryListOutcome> listSummaries() {
    _guard.read('history.listSummaries');
    return _inner.listSummaries();
  }

  @override
  Future<MatchReplayOpenOutcome> openReplay(String matchId) {
    _guard.read('history.openReplay');
    return _inner.openReplay(matchId);
  }

  @override
  Future<bool> isMatchIdTaken(String candidate) {
    _guard.read('history.isMatchIdTaken');
    return _inner.isMatchIdTaken(candidate);
  }

  @override
  Future<MatchHistoryDeleteOutcome> deleteMatch(String matchId) {
    _guard.guard('history.deleteMatch');
    return _inner.deleteMatch(matchId);
  }

  @override
  Future<MatchReplayRepairOutcome> repairUnusableReplay({
    required String matchId,
    required String reason,
  }) {
    _guard.guard('history.repairUnusableReplay');
    return _inner.repairUnusableReplay(matchId: matchId, reason: reason);
  }

  @override
  Future<MatchArchivePublishOutcome> archiveCompletedMatch(
    MatchCheckpoint terminal,
  ) {
    _guard.guard('history.archiveCompletedMatch');
    return _inner.archiveCompletedMatch(terminal);
  }

  @override
  Future<MatchArchivePublishOutcome> recoverPendingArchive() {
    _guard.guard('history.recoverPendingArchive');
    return _inner.recoverPendingArchive();
  }
}

class _GuardedReplayFileStore implements ReplayFileStore {
  _GuardedReplayFileStore(this._guard, this._inner);

  final _MutationGuard _guard;
  final ReplayFileStore _inner;

  @override
  Future<List<String>> listKeys() {
    _guard.read('replay.listKeys');
    return _inner.listKeys();
  }

  @override
  Future<String?> readFile(String key) {
    _guard.read('replay.readFile');
    return _inner.readFile(key);
  }

  @override
  Future<void> writeFile(String key, String contents) {
    _guard.guard('replay.writeFile');
    return _inner.writeFile(key, contents);
  }

  @override
  Future<bool> deleteFile(String key) {
    _guard.guard('replay.deleteFile');
    return _inner.deleteFile(key);
  }
}

class _GuardedPreferencesRepository implements PreferencesRepository {
  _GuardedPreferencesRepository(this._guard, this._inner);

  final _MutationGuard _guard;
  final PreferencesRepository _inner;

  @override
  Future<GamePreferences> loadPreferences() {
    _guard.read('preferences.loadPreferences');
    return _inner.loadPreferences();
  }

  @override
  Future<void> savePreferences(GamePreferences preferences) {
    _guard.guard('preferences.savePreferences');
    return _inner.savePreferences(preferences);
  }
}

class _GuardedLearningRepository implements LearningProgressRepository {
  _GuardedLearningRepository(this._guard, this._inner);

  final _MutationGuard _guard;
  final LearningProgressRepository _inner;

  @override
  Future<LearningProgress> loadProgress() {
    _guard.read('learning.loadProgress');
    return _inner.loadProgress();
  }

  @override
  Future<void> saveProgress(LearningProgress progress) {
    _guard.guard('learning.saveProgress');
    return _inner.saveProgress(progress);
  }

  @override
  Future<LearningProgress> update(
    LearningProgress Function(LearningProgress current) change,
  ) {
    _guard.guard('learning.update');
    return _inner.update(change);
  }
}

/// The whole app over guarded stores, plus the raw bytes behind them.
typedef _Harness = ({
  Widget app,
  _MutationGuard guard,
  MatchRepository guardedMatches,
  MemoryKeyValueStore historyStore,
  MemoryKeyValueStore matchStore,
  MemoryReplayFileStore replayFiles,
});

const _seededMatchId = 'm-guarded-aaaaaaaa';

Future<_Harness> _buildHarness() async {
  final guard = _MutationGuard();
  final historyStore = MemoryKeyValueStore();
  final matchStore = MemoryKeyValueStore();
  final replayFiles = MemoryReplayFileStore();
  final matches = LocalMatchRepository(
    store: matchStore,
    // Never reached here: the fixture is archived directly and no legacy save
    // is migrated. Present because the constructor requires it.
    mintMatchId: () async => 'm-unused-aaaaaaaa',
  );

  final history = LocalMatchHistoryRepository(
    store: historyStore,
    replayFiles: _GuardedReplayFileStore(guard, replayFiles),
    matches: matches,
  );

  // Seeded through the real publication path, before the guard is armed, so
  // the fixture is a genuinely archived match rather than hand-written bytes.
  final fixture = buildCompletedMatch(seed: 13);
  final terminal =
      MatchCheckpoint(
            matchId: _seededMatchId,
            snapshot: fixture.finalState,
            recorderState: fixture.recorderState,
          )
          // Coach-**eligible**, and that is load-bearing rather than incidental: an
          // ineligible archive builds no toggle at all, so a guarded window over one
          // could never cover a coach that was switched on, ran an advisor and
          // rendered an insight. The flag is set through the production sticky setter
          // and travels into the summary the same way a real coached match's does.
          .withCoachEnabled(true)
          .terminalize(fixture.facts);
  final published = await history.archiveCompletedMatch(terminal);
  expect(published, isA<MatchArchivePublished>());
  await matches.abandonActiveMatch();

  final guardedMatches = _GuardedMatchRepository(guard, matches);
  return (
    app: HareegTableApp(
      matchRepository: guardedMatches,
      historyRepository: _GuardedHistoryRepository(guard, history),
      preferencesRepository: _GuardedPreferencesRepository(
        guard,
        MemoryPreferencesRepository(),
      ),
      learningProgressRepository: _GuardedLearningRepository(
        guard,
        MemoryLearningProgressRepository(),
      ),
      initialRouteOverride: AppRoutes.history,
    ),
    guard: guard,
    guardedMatches: guardedMatches,
    historyStore: historyStore,
    matchStore: matchStore,
    replayFiles: replayFiles,
  );
}

void main() {
  final strings = AppStrings.english;

  setUp(() {
    final prior = ShowcaseCardFan.disableLoopingMotionForTesting;
    ShowcaseCardFan.disableLoopingMotionForTesting = true;
    addTearDown(() => ShowcaseCardFan.disableLoopingMotionForTesting = prior);
  });

  /// Sizes the view and opens the seeded match's replay through the real list.
  ///
  /// Everything here is setup and happens **before** the guard is armed (B56).
  Future<_Harness> openSeededReplay(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1688, 780);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final harness = await _buildHarness();
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle(const Duration(seconds: 60));
    await tester.tap(find.text(strings.replayTitle).last);
    await tester.pumpAndSettle(const Duration(seconds: 90));
    expect(find.byType(MatchReplayScreen), findsOneWidget);
    return harness;
  }

  /// Enters the sandbox from the frame currently under the cursor.
  Future<void> enterBranch(
    WidgetTester tester, {
    required String choice,
  }) async {
    await tester.tap(find.byKey(const ValueKey('replay-branch-control')));
    await tester.pumpAndSettle();
    final entry = find.byKey(ValueKey(choice));
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle(const Duration(seconds: 90));
    expect(find.byType(BranchSandboxHost), findsOneWidget);
  }

  /// Drains the event loop deterministically, so a fire-and-forget write
  /// scheduled during teardown completes *inside* the armed window rather than
  /// after the assertions have already run.
  Future<void> quiesce(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      await tester.idle();
    }
    await tester.pumpAndSettle(const Duration(seconds: 30));
  }

  /// Asserts nothing was attempted, the stores are byte-identical, and — the
  /// part that makes the other two mean anything — that the window was still
  /// live while all three were checked.
  ///
  /// The guard is disarmed only by this helper, and only on its last line.
  Future<void> assertUntouchedAndStillArmed(
    _Harness harness, {
    required Map<String, String> historyBefore,
    required Map<String, String> matchBefore,
    required List<String> replayBefore,
  }) async {
    final guard = harness.guard;
    expect(
      guard.attempts,
      isEmpty,
      reason:
          'a branch session attempted a durable mutation: ${guard.attempts}',
    );

    // B61: the durable state is byte-identical to what it was before.
    expect(harness.historyStore.values, historyBefore);
    expect(harness.matchStore.values, matchBefore);
    expect(await harness.replayFiles.listKeys(), replayBefore);

    // Proven, not asserted: a mutation attempted *now*, through the same
    // wrappers, is recorded. An empty attempt log against a guard that had
    // quietly disarmed is exactly the vacuous pass this closes.
    expect(
      () => harness.guardedMatches.abandonActiveMatch(),
      throwsA(isA<StateError>()),
    );
    expect(guard.attempts, ['match.abandonActiveMatch']);

    guard.armed = false;
  }

  testWidgets(
    'no durable mutation is attempted anywhere in a branch session',
    (tester) async {
      final harness = await openSeededReplay(tester);

      // ---- arm, only now that the replay is seeded and fully loaded -------
      final guard = harness.guard;
      final historyBefore = Map<String, String>.of(harness.historyStore.values);
      final matchBefore = Map<String, String>.of(harness.matchStore.values);
      final replayBefore = await harness.replayFiles.listKeys();
      guard.armed = true;

      // Step into the round before branching. The opening frame hands the
      // sandbox a board where the only legal move may be the deal itself; a
      // mid-round position always has one, so the window covers real play.
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byTooltip(strings.replayNext));
        await tester.pumpAndSettle(const Duration(seconds: 30));
      }

      await enterBranch(tester, choice: 'branch-entry-study');

      await branchPlayOneSouthAction(tester);

      // Divergence proves an action really applied — and the confirmation is
      // itself part of what the window has to cover.
      await tester.tap(find.byKey(const ValueKey('branch-exit')));
      await tester.pumpAndSettle();
      expect(
        find.text(strings.branchExitTitle),
        findsOneWidget,
        reason: 'the sandbox never applied an action, so the window is idle',
      );
      await tester.tap(find.text(strings.branchExitCancel));
      await tester.pumpAndSettle();

      // ---- the coach, inside the same window ------------------------------
      // The archived match was coached, so the sandbox inherits a live coach
      // and a session-only toggle. Both halves run here: an advisor that
      // actually computes (the expensive path, and the one that could reach a
      // preference), and the toggle that a player would use.
      final toggle = find.byKey(const ValueKey('branch-coach-toggle'));
      await tester.tap(find.byTooltip(strings.pauseTable));
      await tester.pumpAndSettle();
      expect(
        toggle,
        findsOneWidget,
        reason:
            'the archived match was coached, so the sandbox must offer the '
            'toggle — without it this window never covers a live coach',
      );
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      await tester.tap(find.text(strings.branchResume));
      await tester.pumpAndSettle(const Duration(seconds: 30));

      await branchSettleToSouthTurn(tester);
      expect(
        find.byKey(const ValueKey('coach-overlay')),
        findsOneWidget,
        reason:
            'an eligible sandbox with the coach on must render a live '
            'insight; a window over a silent coach proves nothing about the '
            'advisor path',
      );

      // Off, and the insight goes with it — the pair is what shows the
      // assertion above is about the coach and not about some overlay that is
      // always there.
      await tester.tap(find.byTooltip(strings.pauseTable));
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      await tester.tap(find.text(strings.branchResume));
      await tester.pumpAndSettle(const Duration(seconds: 30));
      expect(find.byKey(const ValueKey('coach-overlay')), findsNothing);

      // Restart, which rebuilds the whole table from the seed.
      await tester.tap(find.byTooltip(strings.pauseTable));
      await tester.pumpAndSettle();
      await tester.tap(find.text(strings.branchRestart));
      await tester.pumpAndSettle(const Duration(seconds: 90));
      await branchPlayOneSouthAction(tester);

      // Exit, through the pause route.
      await tester.tap(find.byTooltip(strings.pauseTable));
      await tester.pumpAndSettle();
      await tester.tap(find.text(strings.branchExitSandbox));
      await tester.pumpAndSettle();
      if (find.text(strings.branchExitConfirm).evaluate().isNotEmpty) {
        await tester.tap(find.text(strings.branchExitConfirm));
      }
      await tester.pumpAndSettle(const Duration(seconds: 90));

      // The guard stays armed **through replay restoration**: this is where a
      // late write would land, and disarming at the exit would miss it.
      expect(find.byType(MatchReplayScreen), findsOneWidget);
      expect(find.byType(BranchSandboxHost), findsNothing);

      // ... and through an explicit, deterministic quiescence drain.
      await quiesce(tester);

      // ---- assertions, all of them still inside the armed window ---------
      await assertUntouchedAndStillArmed(
        harness,
        historyBefore: historyBefore,
        matchBefore: matchBefore,
        replayBefore: replayBefore,
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'a sandbox played to completion attempts no durable mutation',
    (tester) async {
      // The segment the lifecycle test above cannot reach. Completion is not
      // an extra button: it is where the live table archives the match, and it
      // is the single most likely place for a branch to write. A window that
      // stopped at the exit would never cover it.
      //
      // Reached by branching **late**, from the last round of the archived
      // match, where two seats are already out and the survivors sit one
      // ordinary penalty from the elimination threshold. South then plays
      // without melding, which is what turns the next round end into a
      // decision rather than another deal.
      final harness = await openSeededReplay(tester);

      // Jump to the end and step back until the branch control is live: the
      // terminal frame refuses to branch, and a round-end frame with no
      // recorded successor refuses too.
      await tester.tap(find.byTooltip(strings.replayLast));
      await tester.pumpAndSettle(const Duration(seconds: 30));
      final branchControl = find.byKey(const ValueKey('replay-branch-control'));
      var stepsBack = 0;
      while (tester.widget<ReplayRailButton>(branchControl).onPressed == null) {
        expect(
          stepsBack,
          lessThan(12),
          reason: 'no branchable frame near the end of the archived match',
        );
        await tester.tap(find.byTooltip(strings.replayPrevious));
        await tester.pumpAndSettle(const Duration(seconds: 30));
        stepsBack += 1;
      }
      expect(
        stepsBack,
        greaterThan(0),
        reason:
            'the terminal frame must have refused, or this branched from a '
            'frame that was never near the end',
      );

      // Then back further still. The *first* branchable frame is the one where
      // a CPU is one discard from going out, and branching there reaches
      // completion without south ever moving — completion on arrival, which
      // proves nothing about a sandbox that was played. These twelve frames
      // hand south several real turns first, while staying inside the final
      // round where the survivors are one penalty from elimination.
      for (var i = 0; i < 12; i++) {
        await tester.tap(find.byTooltip(strings.replayPrevious));
        await tester.pumpAndSettle(const Duration(seconds: 30));
        expect(
          tester.widget<ReplayRailButton>(branchControl).onPressed,
          isNotNull,
          reason: 'stepped back onto an unbranchable frame',
        );
      }

      // ---- arm ------------------------------------------------------------
      final guard = harness.guard;
      final historyBefore = Map<String, String>.of(harness.historyStore.values);
      final matchBefore = Map<String, String>.of(harness.matchStore.values);
      final replayBefore = await harness.replayFiles.listKeys();
      guard.armed = true;

      await enterBranch(tester, choice: 'branch-entry-blind');

      final completion = find.text(strings.branchCompletionTitle);
      var applied = 0;
      var idle = 0;
      while (completion.evaluate().isEmpty) {
        if (await branchPlayOneSouthAction(tester)) {
          applied += 1;
          idle = 0;
        } else {
          // A CPU owns the turn; give the run time to hand it back rather
          // than spinning on a board nobody is moving.
          idle += 1;
          expect(
            idle,
            lessThan(12),
            reason: 'the sandbox stopped handing the turn back to south',
          );
          await tester.pumpAndSettle(const Duration(seconds: 30));
        }
        expect(
          applied,
          lessThan(400),
          reason: 'the sandbox never reached completion',
        );
      }

      expect(
        applied,
        greaterThan(0),
        reason: 'completion must be reached by playing, not on arrival',
      );
      // B51's two ways out, and only those two.
      expect(find.text(strings.branchReturnToReplay), findsOneWidget);
      expect(find.text(strings.branchRestart), findsOneWidget);

      // Leave a *completed* sandbox, which is the exact moment a live table
      // would archive.
      await tester.tap(find.text(strings.branchReturnToReplay));
      await tester.pumpAndSettle();
      // A completed sandbox has still diverged, so leaving it takes the same
      // confirmation every other exit route does.
      expect(find.text(strings.branchExitTitle), findsOneWidget);
      await tester.tap(find.text(strings.branchExitConfirm));
      await tester.pumpAndSettle(const Duration(seconds: 90));
      expect(find.byType(MatchReplayScreen), findsOneWidget);
      expect(find.byType(BranchSandboxHost), findsNothing);

      await quiesce(tester);
      await assertUntouchedAndStillArmed(
        harness,
        historyBefore: historyBefore,
        matchBefore: matchBefore,
        replayBefore: replayBefore,
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );

  testWidgets('the guard bites: a deliberate write is recorded and refused', (
    tester,
  ) async {
    // The assertion above is only worth anything if the log would actually
    // catch a write. Previous rejections in this sprint were all proofs that
    // could not fail, so this one proves itself first.
    final guard = _MutationGuard();
    final inner = MemoryMatchRepository(
      checkpoint: checkpointForSnapshot(
        buildCompletedMatch(seed: 13).finalState,
      ),
    );
    final guarded = _GuardedMatchRepository(guard, inner);
    expect(inner.savedCheckpoint, isNotNull);

    guard.armed = true;
    expect(() => guarded.abandonActiveMatch(), throwsA(isA<StateError>()));
    expect(guard.attempts, ['match.abandonActiveMatch']);
    expect(
      inner.savedCheckpoint,
      isNotNull,
      reason: 'the refusal must also stop the write reaching the store',
    );

    // And the record precedes the throw, which is the whole point: the
    // table's catch-all would swallow the exception and leave only this.
    expect(
      guard.attempts,
      isNotEmpty,
      reason: 'the attempt must be logged before the refusal is raised',
    );
  });

  testWidgets(
    'the guard is wired into the running app, not just callable from a test',
    (tester) async {
      // The second half of anti-vacuity, and the one that matters more. The
      // case above shows a wrapper refuses when *the test* calls it; this
      // shows the wrapper instances actually installed in the app under test
      // sit on the path the app itself writes through. Without it, an empty
      // attempt log in the branch cases could mean "the sandbox wrote
      // nothing" or "these objects were never on a write path at all", and
      // the two would be indistinguishable.
      //
      // Deleting an archived match is the cheapest durable mutation the
      // seeded app reaches through its own UI — and the screen **swallows**
      // the refusal into a snackbar, which is exactly why B58a makes the log
      // the gate rather than the exception.
      final harness = await _buildHarness();
      tester.view.physicalSize = const Size(1688, 780);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle(const Duration(seconds: 60));

      final before = Map<String, String>.of(harness.historyStore.values);
      harness.guard.armed = true;

      await tester.tap(find.byTooltip(strings.historyDeleteTooltip).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(strings.historyDelete));
      await tester.pumpAndSettle(const Duration(seconds: 30));

      expect(
        harness.guard.attempts,
        ['history.deleteMatch'],
        reason:
            'the app deleted a match and the guard did not see it, so an '
            'empty log elsewhere in this file would prove nothing',
      );
      expect(
        harness.historyStore.values,
        before,
        reason: 'the refusal must also stop the write reaching the store',
      );
      harness.guard.armed = false;
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  testWidgets(
    'a process kill mid-branch leaves nothing resumable',
    (tester) async {
      final harness = await openSeededReplay(tester);

      // ---- arm, before the sandbox is entered and before the kill ---------
      // Round 1 rejected this test for running its whole kill unarmed: an
      // unguarded teardown can only be checked by what it left behind, which
      // says nothing about what it *tried*. `GameTableScreen.dispose()` is
      // exactly where a live table settles its last write.
      final guard = harness.guard;
      final historyBefore = Map<String, String>.of(harness.historyStore.values);
      final matchBefore = Map<String, String>.of(harness.matchStore.values);
      final replayBefore = await harness.replayFiles.listKeys();
      guard.armed = true;

      await enterBranch(tester, choice: 'branch-entry-blind');

      // Diverge first. A killed sandbox that never moved has nothing worth
      // saving, so the kill has to happen over a board that does.
      await branchPlayOneSouthAction(tester);

      // The kill: the widget tree goes away mid-sandbox, with no exit and no
      // teardown, and the same stores are relaunched into.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await quiesce(tester);

      // Nothing was *attempted* during the teardown — checked before the
      // outcome assertions below, which could only ever see what survived.
      expect(
        guard.attempts,
        isEmpty,
        reason:
            'a killed sandbox attempted a durable mutation: '
            '${guard.attempts}',
      );
      // ...and the bytes are unchanged, compared *before* the relaunch below
      // reads through unguarded repositories.
      expect(harness.historyStore.values, historyBefore);
      expect(harness.matchStore.values, matchBefore);
      expect(await harness.replayFiles.listKeys(), replayBefore);

      final matches = LocalMatchRepository(
        store: harness.matchStore,
        mintMatchId: () async => 'm-unused-aaaaaaaa',
      );
      final resumed = await matches.loadActiveMatch();
      expect(
        resumed,
        isA<ActiveMatchAbsent>(),
        reason: 'a killed sandbox must leave no resumable match behind',
      );

      final history = LocalMatchHistoryRepository(
        store: harness.historyStore,
        replayFiles: harness.replayFiles,
        matches: matches,
      );
      final listed = await history.listSummaries();
      expect(listed, isA<MatchHistoryListed>());
      expect(
        (listed as MatchHistoryListed).summaries.map((s) => s.matchId),
        [_seededMatchId],
        reason: 'the sandbox must not have added a history entry',
      );

      // Still live, for every assertion above.
      expect(
        () => harness.guardedMatches.abandonActiveMatch(),
        throwsA(isA<StateError>()),
      );
      expect(guard.attempts, ['match.abandonActiveMatch']);
      guard.armed = false;
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test('a branch session is constructed with no durable dependency', () {
    // Structural, and proven independently of the guard: the guard shows that
    // nothing *was* written, this shows that nothing *could* be. The sandbox
    // host takes a frame, a visibility, an eligibility flag, presentation
    // preferences and a clock — and no store of any kind.
    final source = File(
      'lib/ui/features/replay/views/branch_sandbox_host.dart',
    ).readAsStringSync();

    for (final forbidden in const [
      'MatchRepository',
      'MatchHistoryRepository',
      'ReplayFileStore',
      'PreferencesRepository',
      'LearningProgressRepository',
      'AppRepositories',
    ]) {
      expect(
        source.contains(forbidden),
        isFalse,
        reason: 'the sandbox host names $forbidden',
      );
    }

    // `GamePreferences` is a plain value and is read-only here; the repository
    // that could store it is deliberately absent.
    expect(source, contains('GamePreferences'));
    expect(source, contains('onPreferencesChanged: (_) {}'));
  });
}
