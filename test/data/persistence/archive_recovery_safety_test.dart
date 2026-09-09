import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/data/persistence/match_history_repository.dart';
import 'package:hareeg_table/data/persistence/match_repository.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/data/persistence/replay_file_store.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_terminal_facts.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';
import 'package:hareeg_table/ui/features/game_setup/views/new_game_setup_screen.dart';
import '../../support/test_fixtures.dart';

class FailingStore extends MemoryKeyValueStore {
  bool failIndexWrite = false;
  bool failPendingRemove = false;
  @override
  Future<void> saveString(String key, String value) async {
    if (failIndexWrite && key == LocalMatchHistoryRepository.indexKey) {
      throw StateError('index write failure');
    }
    await super.saveString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    if (failPendingRemove && key == LocalMatchHistoryRepository.pendingKey) {
      throw StateError('pending clear failure');
    }
    await super.remove(key);
  }
}

MatchCheckpoint terminal() =>
    MatchCheckpoint(
      matchId: testMatchId,
      snapshot: snapshotWithSouthHand([]),
      replayIneligible: true,
    ).terminalize(
      MatchTerminalFacts(
        completedAt: DateTime.utc(2026, 9, 9),
        winner: PlayerSeat.south,
        finalScores: {
          for (final seat in PlayerSeat.values)
            seat: seat == PlayerSeat.south ? 0 : 100,
        },
        roundCount: 3,
        eliminationRounds: {
          for (final seat in PlayerSeat.values)
            if (seat != PlayerSeat.south) seat: 3,
        },
        seats: PlayerSeat.values,
      ),
    );

void main() {
  late FailingStore store;
  late LocalMatchRepository matches;
  late LocalMatchHistoryRepository history;
  setUp(() {
    store = FailingStore();
    matches = LocalMatchRepository(
      store: store,
      mintMatchId: () async => testMatchId,
    );
    history = LocalMatchHistoryRepository(
      store: store,
      replayFiles: MemoryReplayFileStore(),
      matches: matches,
    );
  });

  test(
    'data-less pending marker reports loss once without permanently blocking recovery',
    () async {
      await store.saveString(
        LocalMatchHistoryRepository.pendingKey,
        jsonEncode({'version': 1, 'matchId': testMatchId}),
      );
      expect(
        await history.recoverPendingArchive(),
        isA<MatchArchivePublishFailed>(),
      );
      expect(
        await store.loadString(LocalMatchHistoryRepository.pendingKey),
        isNull,
      );
      expect(
        await history.recoverPendingArchive(),
        isA<MatchArchiveNothingPending>(),
      );
    },
  );

  test(
    'save identity cache still detects an external terminal checkpoint',
    () async {
      final active = MatchCheckpoint(
        matchId: 'm-next-bbbbbbbb',
        snapshot: snapshotWithSouthHand([]),
      );
      await matches.saveActiveMatch(active);
      final terminalRaw = jsonEncode(terminal().toJson());
      await store.saveString('active_match.v1', terminalRaw);
      await expectLater(matches.saveActiveMatch(active), throwsStateError);
      expect(await store.loadString('active_match.v1'), terminalRaw);
    },
  );

  testWidgets(
    'damaged active save requires confirmation and leaves History untouched',
    (tester) async {
      final store = FailingStore();
      final matches = LocalMatchRepository(
        store: store,
        mintMatchId: () async => testMatchId,
      );
      final history = LocalMatchHistoryRepository(
        store: store,
        replayFiles: MemoryReplayFileStore(),
        matches: matches,
      );
      final damaged = jsonEncode({
        'version': 1,
        'matchId': testMatchId,
        'snapshot': {'version': 1},
      });
      await store.saveString('active_match.v1', damaged);
      ShowcaseCardFan.disableLoopingMotionForTesting = true;
      addTearDown(() => ShowcaseCardFan.disableLoopingMotionForTesting = false);
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        HareegTableApp(
          initialRouteOverride: AppRoutes.home,
          matchRepository: matches,
          historyRepository: history,
          preferencesRepository: MemoryPreferencesRepository(),
          learningProgressRepository: MemoryLearningProgressRepository(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.english.newGame));
      await tester.pumpAndSettle();
      expect(find.byType(NewGameSetupScreen), findsNothing);
      final snackBar = find.byType(SnackBar);
      expect(
        find.descendant(
          of: snackBar,
          matching: find.text(AppStrings.english.discardDamagedSaveWarning),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: snackBar,
          matching: find.text(AppStrings.english.historyRetry),
        ),
        findsNothing,
      );
      await tester.tap(
        find.descendant(
          of: snackBar,
          matching: find.text(AppStrings.english.discardDamagedSave),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.english.historyCancel));
      await tester.pumpAndSettle();
      expect(await store.loadString('active_match.v1'), damaged);
      await tester.tap(find.text(AppStrings.english.discardDamagedSave));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.english.abandonSavedMatch));
      await tester.pumpAndSettle();
      expect(await store.loadString('active_match.v1'), isNull);
      expect(
        (await history.listSummaries() as MatchHistoryListed).summaries,
        isEmpty,
      );
      await tester.tap(find.text(AppStrings.english.newGame));
      await tester.pumpAndSettle();
      expect(find.byType(NewGameSetupScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'legacy completion shows result despite archive failure and retries safely',
    (tester) async {
      final store = FailingStore();
      final matches = LocalMatchRepository(
        store: store,
        mintMatchId: () async => testMatchId,
      );
      final history = LocalMatchHistoryRepository(
        store: store,
        replayFiles: MemoryReplayFileStore(),
        matches: matches,
      );
      final setup = ClassicHareegSetup.defaults();
      final base = ClassicHareegRound.deal(setup: setup, seed: 23);
      await matches.saveActiveMatch(
        MatchCheckpoint(
          matchId: testMatchId,
          replayIneligible: true,
          snapshot: ClassicHareegMatchSnapshot(
            setup: setup,
            hands: base.hands,
            stock: base.stock,
            discardPile: base.discardPile,
            starter: PlayerSeat.south,
            currentSeat: PlayerSeat.east,
            turnPhase: TurnPhase.draw,
            scores: const {
              PlayerSeat.south: 34,
              PlayerSeat.east: 0,
              PlayerSeat.north: 50,
              PlayerSeat.west: 60,
            },
            activeSeats: const [PlayerSeat.south, PlayerSeat.east],
            removedSeats: const [PlayerSeat.south],
            roundNumber: 5,
            savedAt: DateTime.utc(2026, 9, 9),
          ),
        ),
      );
      store.failIndexWrite = true;
      ShowcaseCardFan.disableLoopingMotionForTesting = true;
      addTearDown(() => ShowcaseCardFan.disableLoopingMotionForTesting = false);
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        HareegTableApp(
          initialRouteOverride: AppRoutes.home,
          matchRepository: matches,
          historyRepository: history,
          preferencesRepository: MemoryPreferencesRepository(),
          learningProgressRepository: MemoryLearningProgressRepository(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.english.continueGame));
      await tester.pumpAndSettle(const Duration(seconds: 30));
      expect(find.byKey(const ValueKey('match-over-overlay')), findsOneWidget);
      expect(find.text(AppStrings.english.archiveSaveFailed), findsOneWidget);
      final rematch = find.byKey(const ValueKey('match-over-overlay-rematch'));
      expect(tester.widget<FilledButton>(rematch).onPressed, isNull);
      final terminal =
          (await matches.loadActiveMatch() as ActiveMatchLoaded).checkpoint;
      expect(terminal.isTerminal, isTrue);
      expect(
        terminal.terminalFacts!.unknownEliminationSeats,
        containsAll([PlayerSeat.north, PlayerSeat.west]),
      );
      final completedAt = terminal.terminalFacts!.completedAt;
      expect(
        (await history.listSummaries() as MatchHistoryListed).summaries,
        isEmpty,
      );
      store.failIndexWrite = false;
      await tester.tap(find.text(AppStrings.english.historyRetry));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.english.archiveSaveFailed), findsNothing);
      expect(tester.widget<FilledButton>(rematch).onPressed, isNotNull);
      expect(await matches.loadActiveMatch(), isA<ActiveMatchAbsent>());
      final listed =
          (await history.listSummaries() as MatchHistoryListed).summaries;
      expect(listed, hasLength(1));
      expect(listed.single.completedAt, completedAt);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  test(
    'interrupted deletion resumes before publication and cannot resurrect a deleted match',
    () async {
      store.failPendingRemove = true;
      await matches.saveActiveMatch(terminal());
      expect(
        await history.archiveCompletedMatch(terminal()),
        isA<MatchArchivePublishFailed>(),
      );
      expect(
        (await history.listSummaries() as MatchHistoryListed).summaries,
        hasLength(1),
      );
      expect(
        await history.deleteMatch(testMatchId),
        isA<MatchHistoryDeleteFailed>(),
      );
      expect(
        await store.loadString(LocalMatchHistoryRepository.pendingDeleteKey),
        testMatchId,
      );
      store.failPendingRemove = false;
      expect(
        await history.recoverPendingArchive(),
        isA<MatchArchiveNothingPending>(),
      );
      expect(
        (await history.listSummaries() as MatchHistoryListed).summaries,
        isEmpty,
      );
      expect(await matches.loadActiveMatch(), isA<ActiveMatchAbsent>());
      expect(
        await history.deleteMatch(testMatchId),
        isA<MatchHistoryDeleted>(),
      );
      expect(
        await history.recoverPendingArchive(),
        isA<MatchArchiveNothingPending>(),
      );
    },
  );

  test(
    'new active save cannot overwrite terminal recovery data; retry publishes it',
    () async {
      store.failIndexWrite = true;
      await matches.saveActiveMatch(terminal());
      expect(
        await history.recoverPendingArchive(),
        isA<MatchArchivePublishFailed>(),
      );
      final newGame = MatchCheckpoint(
        matchId: 'm-test-bbbbbbbb',
        snapshot: snapshotWithSouthHand([]),
      );
      await expectLater(matches.saveActiveMatch(newGame), throwsStateError);
      expect(
        (await matches.loadActiveMatch() as ActiveMatchLoaded)
            .checkpoint
            .isTerminal,
        isTrue,
      );
      store.failIndexWrite = false;
      expect(
        await history.recoverPendingArchive(),
        isA<MatchArchivePublishedNonReplayable>(),
      );
      await matches.saveActiveMatch(newGame);
      expect(
        (await matches.loadActiveMatch() as ActiveMatchLoaded)
            .checkpoint
            .matchId,
        newGame.matchId,
      );
    },
  );

  testWidgets('Home refuses New Game until the previous archive is recovered', (
    tester,
  ) async {
    // Construct the serialized repository in the widget test's fake-async zone.
    store = FailingStore();
    matches = LocalMatchRepository(
      store: store,
      mintMatchId: () async => testMatchId,
    );
    history = LocalMatchHistoryRepository(
      store: store,
      replayFiles: MemoryReplayFileStore(),
      matches: matches,
    );
    ShowcaseCardFan.disableLoopingMotionForTesting = true;
    addTearDown(() => ShowcaseCardFan.disableLoopingMotionForTesting = false);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store.failIndexWrite = true;
    await matches.saveActiveMatch(terminal());
    await tester.pumpWidget(
      HareegTableApp(
        initialRouteOverride: AppRoutes.home,
        matchRepository: matches,
        historyRepository: history,
        learningProgressRepository: MemoryLearningProgressRepository(),
        preferencesRepository: MemoryPreferencesRepository()
          ..preferences = GamePreferences.defaults().copyWith(
            language: AppLanguage.english,
          ),
      ),
    );
    await tester.pumpAndSettle();
    for (
      var i = 0;
      i < 20 &&
          find
              .text(AppStrings.english.checkingSavedMatch)
              .evaluate()
              .isNotEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text(AppStrings.english.checkingSavedMatch), findsNothing);
    await tester.tap(find.text(AppStrings.english.newGame));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(NewGameSetupScreen), findsNothing);
    for (
      var i = 0;
      i < 20 &&
          find
              .text(AppStrings.english.archiveRecoveryRequired)
              .evaluate()
              .isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(
      find.text(AppStrings.english.archiveRecoveryRequired),
      findsOneWidget,
    );
    expect(
      (await matches.loadActiveMatch() as ActiveMatchLoaded)
          .checkpoint
          .isTerminal,
      isTrue,
    );
    store.failIndexWrite = false;
    await tester.tap(find.text(AppStrings.english.newGame));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(NewGameSetupScreen), findsOneWidget);
    expect(
      (await history.listSummaries() as MatchHistoryListed)
          .summaries
          .single
          .matchId,
      testMatchId,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
