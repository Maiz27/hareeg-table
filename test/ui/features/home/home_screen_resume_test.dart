import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/data/persistence/match_repository.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_terminal_facts.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_recorder.dart';

import '../../../support/test_fixtures.dart';

void main() {
  ShowcaseCardFan.disableLoopingMotionForTesting = true;

  ClassicHareegMatchSnapshot buildSnapshot() {
    final round = ClassicHareegRound.deal(
      setup: ClassicHareegSetup.defaults(),
      seed: 7,
    );
    return ClassicHareegMatchSnapshot(
      setup: round.setup,
      hands: round.hands,
      stock: round.stock,
      discardPile: round.discardPile,
      starter: round.starter,
      currentSeat: round.currentSeat,
      turnPhase: round.turnPhase,
      savedAt: DateTime.utc(2026, 8, 22),
    );
  }

  MatchCheckpoint liveCheckpoint() {
    final base = buildSnapshot();
    final recorder = MatchRecorder()..captureInitialState(base);
    recorder
      ..recordAction(
        seat: PlayerSeat.south,
        roundNumber: 1,
        phase: TurnPhase.action,
        actionId: 'claim-fifty',
      )
      ..recordFiftySuccess(PlayerSeat.south);

    return MatchCheckpoint(
      matchId: testMatchId,
      snapshot: base,
      recorderState: recorder.toState(),
      eliminationRounds: const {PlayerSeat.west: 2},
      coachWasEnabled: true,
    );
  }

  MatchCheckpoint terminalCheckpoint() {
    return MatchCheckpoint(
      matchId: 'm-done-bbbbbbbb',
      snapshot: buildSnapshot(),
    ).terminalize(
      MatchTerminalFacts(
        completedAt: DateTime.utc(2026, 8, 22, 10),
        winner: PlayerSeat.south,
        finalScores: const {
          PlayerSeat.south: 4,
          PlayerSeat.east: 31,
          PlayerSeat.north: 32,
          PlayerSeat.west: 33,
        },
        roundCount: 3,
        eliminationRounds: const {
          PlayerSeat.east: 2,
          PlayerSeat.north: 3,
          PlayerSeat.west: 1,
        },
        seats: PlayerSeat.values,
      ),
    );
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    required MemoryMatchRepository matches,
    required MemoryMatchHistoryRepository history,
  }) async {
    await tester.pumpWidget(
      HareegTableApp(
        matchRepository: matches,
        historyRepository: history,
        preferencesRepository: MemoryPreferencesRepository(),
        initialRouteOverride: AppRoutes.home,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Home screen resume', () {
    testWidgets('offers Continue for a live checkpoint', (tester) async {
      await pumpHome(
        tester,
        matches: MemoryMatchRepository(checkpoint: liveCheckpoint()),
        history: MemoryMatchHistoryRepository(),
      );

      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('does not offer Continue for a terminal checkpoint', (
      tester,
    ) async {
      // A completed match waiting to be archived is not a game to resume.
      // Offering it would put the player back into a match that is already over.
      final matches = MemoryMatchRepository(checkpoint: terminalCheckpoint());
      await pumpHome(
        tester,
        matches: matches,
        history: MemoryMatchHistoryRepository(),
      );

      // Continue still renders — it is disabled rather than removed — so the
      // assertion that matters is that it cannot take the player anywhere.
      await tester.tap(find.text('Continue'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('New Game'), findsOneWidget);
      // Still the untouched terminal checkpoint: no table opened and re-saved
      // it as a live match.
      expect(matches.savedCheckpoint!.isTerminal, isTrue);
      expect(matches.savedCheckpoint!.matchId, 'm-done-bbbbbbbb');
    });

    testWidgets('recovers a pending archive before deciding what is resumable', (
      tester,
    ) async {
      final history = _RecordingHistoryRepository();

      await pumpHome(
        tester,
        matches: MemoryMatchRepository(checkpoint: liveCheckpoint()),
        history: history,
      );

      expect(history.recoveryCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('a failing recovery still shows the resumable match', (
      tester,
    ) async {
      // A storage hiccup during recovery must not hide the player's game. The
      // pending record survives for the next launch; a missing Continue button
      // would look to them like the match had been lost.
      final history = _RecordingHistoryRepository(failRecovery: true);

      await pumpHome(
        tester,
        matches: MemoryMatchRepository(checkpoint: liveCheckpoint()),
        history: history,
      );

      expect(history.recoveryCalls, greaterThanOrEqualTo(1));
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('Continue carries the whole checkpoint to the table', (
      tester,
    ) async {
      final checkpoint = liveCheckpoint();
      final matches = MemoryMatchRepository(checkpoint: checkpoint);

      await pumpHome(
        tester,
        matches: matches,
        history: MemoryMatchHistoryRepository(),
      );

      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // The table saved on entry, and what it saved must still be this match —
      // same id, same transcript, same counters, same eliminations, same coach
      // history. A bare snapshot would have lost every one of them.
      final saved = matches.savedCheckpoint!;
      expect(saved.matchId, testMatchId);
      expect(saved.recorderState, isNotNull);
      expect(saved.recorderState!.entries, isNotEmpty);
      expect(saved.fiftyCounters.attemptsFor(PlayerSeat.south), 1);
      expect(saved.fiftyCounters.successesFor(PlayerSeat.south), 1);
      expect(saved.eliminationRounds[PlayerSeat.west], 2);
      expect(saved.coachWasEnabled, isTrue);
    });
  });

  _coachAndRematchSeam();
}

/// Screen/checkpoint seam coverage for facts that only the table produces.
void _coachAndRematchSeam() {
  group('Coach flag and rematch at the table seam', () {
    testWidgets('coaching enabled marks the match even with no insight', (
      tester,
    ) async {
      // The recorded fact is that coaching was available and enabled, not that
      // a hint happened to be produced. A quiet turn is still a coached match.
      final matches = MemoryMatchRepository();
      await tester.pumpWidget(
        HareegTableApp(
          matchRepository: matches,
          historyRepository: MemoryMatchHistoryRepository(matches: matches),
          preferencesRepository: MemoryPreferencesRepository()
            ..preferences = GamePreferences.defaults().copyWith(
              coachingTipsEnabled: true,
            ),
          initialRouteOverride: AppRoutes.table,
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(matches.savedCheckpoint, isNotNull);
      expect(matches.savedCheckpoint!.coachWasEnabled, isTrue);
    });

    testWidgets('the coach flag stays set after coaching is switched off', (
      tester,
    ) async {
      final matches = MemoryMatchRepository();
      final preferences = MemoryPreferencesRepository()
        ..preferences = GamePreferences.defaults().copyWith(
          coachingTipsEnabled: true,
        );

      await tester.pumpWidget(
        HareegTableApp(
          matchRepository: matches,
          historyRepository: MemoryMatchHistoryRepository(matches: matches),
          preferencesRepository: preferences,
          initialRouteOverride: AppRoutes.table,
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(matches.savedCheckpoint!.coachWasEnabled, isTrue);

      // Turning the coach off mid-match must not erase having used it.
      final restored = matches.savedCheckpoint!;
      expect(restored.withCoachEnabled(false).coachWasEnabled, isTrue);
      // And it survives the round trip a resume performs.
      expect(
        MatchCheckpoint.fromJson(restored.toJson()).coachWasEnabled,
        isTrue,
      );
    });

    // The real complete -> rematch -> new-match lifecycle lives in
    // game_table_widget_test.dart, where the harness that can actually finish a
    // match already exists.
  });
}

class _RecordingHistoryRepository extends MemoryMatchHistoryRepository {
  _RecordingHistoryRepository({this.failRecovery = false});

  final bool failRecovery;
  int recoveryCalls = 0;

  @override
  Future<MatchArchivePublishOutcome> recoverPendingArchive() async {
    recoveryCalls++;
    if (failRecovery) {
      throw StateError('Simulated recovery failure.');
    }
    return super.recoverPendingArchive();
  }
}
