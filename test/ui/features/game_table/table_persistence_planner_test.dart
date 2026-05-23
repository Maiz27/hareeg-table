import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_score_ledger.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';
import 'package:hareeg_table/ui/features/game_table/table_persistence_planner.dart';

void main() {
  group('ClassicHareegTablePersistencePlanner', () {
    test('active rounds save the active snapshot without presentation', () {
      final active = _snapshot(seed: 1);
      final plan = ClassicHareegTablePersistencePlanner.plan(
        isRoundOver: false,
        activeSnapshot: active,
        nextRoundSnapshot: null,
        roundResult: null,
        scoreView: _scoreView(),
      );

      expect(plan.scenario, ClassicHareegTablePersistenceScenario.activeRound);
      expect(plan.action, ClassicHareegTablePersistenceAction.saveActiveMatch);
      expect(plan.snapshotToSave, same(active));
      expect(plan.shouldShowRoundResult, isFalse);
      expect(plan.logPath, 'active');
    });

    test('completed rounds save next round and present score movement', () {
      final next = _snapshot(seed: 2, roundNumber: 2);
      final result = _normalResult();
      final progress = _progress(matchWinner: null);
      final scoreView = _scoreView(
        previousScores: const {PlayerSeat.south: 10, PlayerSeat.east: 12},
        progress: progress,
      );

      final plan = ClassicHareegTablePersistencePlanner.plan(
        isRoundOver: true,
        activeSnapshot: null,
        nextRoundSnapshot: next,
        roundResult: result,
        scoreView: scoreView,
      );

      expect(
        plan.scenario,
        ClassicHareegTablePersistenceScenario.roundCompleteWithNextRound,
      );
      expect(plan.action, ClassicHareegTablePersistenceAction.saveNextRound);
      expect(plan.snapshotToSave, same(next));
      expect(plan.roundResultPresentation?.result, same(result));
      expect(plan.roundResultPresentation?.progress, same(progress));
      expect(
        plan.roundResultPresentation?.previousScores[PlayerSeat.south],
        10,
      );
      expect(plan.roundResultPresentation?.nextSnapshot, same(next));
      expect(plan.logPath, 'next-round');
    });

    test('completed matches abandon persistence and still present result', () {
      final result = _normalResult();
      final progress = _progress(matchWinner: PlayerSeat.south);

      final plan = ClassicHareegTablePersistencePlanner.plan(
        isRoundOver: true,
        activeSnapshot: null,
        nextRoundSnapshot: null,
        roundResult: result,
        scoreView: _scoreView(progress: progress),
      );

      expect(
        plan.scenario,
        ClassicHareegTablePersistenceScenario.matchComplete,
      );
      expect(
        plan.action,
        ClassicHareegTablePersistenceAction.abandonActiveMatch,
      );
      expect(plan.snapshotToSave, isNull);
      expect(plan.roundResultPresentation?.nextSnapshot, isNull);
      expect(plan.shouldShowRoundResult, isTrue);
      expect(plan.logPath, 'abandon');
    });

    test('completed rounds with incomplete score facts do not present', () {
      final next = _snapshot(seed: 3, roundNumber: 2);

      final plan = ClassicHareegTablePersistencePlanner.plan(
        isRoundOver: true,
        activeSnapshot: null,
        nextRoundSnapshot: next,
        roundResult: _normalResult(),
        scoreView: _scoreView(progress: null),
      );

      expect(
        plan.scenario,
        ClassicHareegTablePersistenceScenario.roundCompleteMissingPresentation,
      );
      expect(plan.action, ClassicHareegTablePersistenceAction.saveNextRound);
      expect(plan.snapshotToSave, same(next));
      expect(plan.shouldShowRoundResult, isFalse);
    });

    test('active-round persistence requires its snapshot', () {
      expect(
        () => ClassicHareegTablePersistencePlanner.plan(
          isRoundOver: false,
          activeSnapshot: null,
          nextRoundSnapshot: null,
          roundResult: null,
          scoreView: _scoreView(),
        ),
        throwsArgumentError,
      );
    });
  });
}

ClassicHareegMatchSnapshot _snapshot({required int seed, int roundNumber = 1}) {
  final round = ClassicHareegRound.deal(
    setup: ClassicHareegSetup.defaults(),
    seed: seed,
  );

  return ClassicHareegMatchSnapshot(
    setup: round.setup,
    hands: round.hands,
    stock: round.stock,
    discardPile: round.discardPile,
    starter: round.starter,
    currentSeat: round.currentSeat,
    turnPhase: round.turnPhase,
    roundNumber: roundNumber,
    savedAt: DateTime.utc(2026, 5, 23),
  );
}

RoundProgressResult _normalResult() {
  return const RoundProgressResult(
    type: RoundOutcomeType.normalFinish,
    winner: PlayerSeat.south,
    remainingCardCounts: {
      PlayerSeat.south: 0,
      PlayerSeat.east: 4,
      PlayerSeat.north: 5,
      PlayerSeat.west: 6,
    },
  );
}

MatchProgressState _progress({PlayerSeat? matchWinner}) {
  return MatchProgressState(
    scores: const {
      PlayerSeat.south: 9,
      PlayerSeat.east: 16,
      PlayerSeat.north: 17,
      PlayerSeat.west: 18,
    },
    activeSeats: matchWinner == null
        ? const [
            PlayerSeat.south,
            PlayerSeat.east,
            PlayerSeat.north,
            PlayerSeat.west,
          ]
        : const [PlayerSeat.south],
    nextStarter: PlayerSeat.south,
    matchWinner: matchWinner,
  );
}

ClassicHareegScoreView _scoreView({
  Map<PlayerSeat, int> previousScores = const {},
  MatchProgressState? progress,
}) {
  return ClassicHareegScoreView(
    previousScores: ClassicHareegScoreLedger.normalize(previousScores),
    currentScores:
        progress?.scores ?? ClassicHareegScoreLedger.normalize(previousScores),
    progress: progress,
  );
}
