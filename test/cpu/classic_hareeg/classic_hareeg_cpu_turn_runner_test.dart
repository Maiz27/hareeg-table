import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/classic_hareeg_cpu_turn_runner.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_strategy.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';

void main() {
  group('ClassicHareegCpuTurnRunner', () {
    test('stops immediately when the human has the turn', () async {
      final controller = ClassicHareegGameController.fromRound(
        ClassicHareegRound.deal(setup: ClassicHareegSetup.defaults(), seed: 5),
      );
      var hookCalled = false;

      final result = await ClassicHareegCpuTurnRunner(
        controller: controller,
        strategy: _FirstLegalStrategy(),
        hooks: ClassicHareegCpuTurnHooks(
          beforeDecision: (_) async {
            hookCalled = true;
            return true;
          },
        ),
      ).run();

      expect(result.stopReason, ClassicHareegCpuTurnStopReason.humanTurn);
      expect(result.appliedActionCount, 0);
      expect(result.didApplyAction, isFalse);
      expect(hookCalled, isFalse);
    });

    test('applies one CPU action then lets a hook stop the run', () async {
      final controller = _controllerForCpuDrawTurn();
      final legalReads = <List<String>>[];
      final choices = <String>[];

      final result = await ClassicHareegCpuTurnRunner(
        controller: controller,
        strategy: _PreferredActionStrategy([ClassicHareegActionIds.drawStock]),
        hooks: ClassicHareegCpuTurnHooks(
          onLegalActions: (_, legal) => legalReads.add(legal),
          onActionChosen: (decision) => choices.add(decision.actionId),
          afterApply: (_, _) async => false,
        ),
      ).run();

      expect(result.stopReason, ClassicHareegCpuTurnStopReason.hookStopped);
      expect(result.appliedActionCount, 1);
      expect(result.didApplyAction, isTrue);
      expect(result.appliedDecisions.single.seat, PlayerSeat.east);
      expect(result.appliedDecisions.single.actionId, choices.single);
      expect(legalReads.single, contains(ClassicHareegActionIds.drawStock));
      expect(choices.single, ClassicHareegActionIds.drawStock);
      expect(controller.currentSeat, PlayerSeat.east);
      expect(controller.turnPhase, TurnPhase.action);
    });

    test(
      'stops at the action safety limit before preparing another action',
      () async {
        final controller = _controllerForCpuDrawTurn();
        var beforeNextActionCalls = 0;

        final result = await ClassicHareegCpuTurnRunner(
          controller: controller,
          strategy: _PreferredActionStrategy([
            ClassicHareegActionIds.drawStock,
          ]),
          actionLimit: 1,
          hooks: ClassicHareegCpuTurnHooks(
            beforeNextAction: (_) async {
              beforeNextActionCalls += 1;
              return true;
            },
          ),
        ).run();

        expect(result.stopReason, ClassicHareegCpuTurnStopReason.safetyLimit);
        expect(result.reachedSafetyLimit, isTrue);
        expect(result.appliedActionCount, 1);
        expect(beforeNextActionCalls, 0);
        expect(controller.currentSeat, PlayerSeat.east);
        expect(controller.turnPhase, TurnPhase.action);
      },
    );

    test('runs until control returns to the human seat', () async {
      final controller = _controllerForCpuActionTurn(PlayerSeat.west);
      var afterApplyCalls = 0;
      var beforeNextActionCalls = 0;

      final result = await ClassicHareegCpuTurnRunner(
        controller: controller,
        strategy: _DiscardStrategy(),
        hooks: ClassicHareegCpuTurnHooks(
          afterApply: (_, _) async {
            afterApplyCalls += 1;
            return true;
          },
          beforeNextAction: (_) async {
            beforeNextActionCalls += 1;
            return true;
          },
        ),
      ).run();

      expect(result.stopReason, ClassicHareegCpuTurnStopReason.humanTurn);
      expect(result.appliedActionCount, 1);
      expect(afterApplyCalls, 1);
      expect(beforeNextActionCalls, 0);
      expect(controller.currentSeat, PlayerSeat.south);
      expect(controller.turnPhase, TurnPhase.draw);
      expect(controller.topDiscard, isNotNull);
    });

    test('throws when a CPU strategy returns an illegal action', () async {
      final controller = _controllerForCpuDrawTurn();

      expect(
        () => ClassicHareegCpuTurnRunner(
          controller: controller,
          strategy: const _IllegalStrategy(),
        ).run(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('CPU strategy returned illegal action'),
          ),
        ),
      );
    });

    test(
      'reports no legal actions when the active CPU seat is inactive',
      () async {
        final controller = _controllerForInactiveCpuSeat();

        final result = await ClassicHareegCpuTurnRunner(
          controller: controller,
          strategy: _FirstLegalStrategy(),
        ).run();

        expect(
          result.stopReason,
          ClassicHareegCpuTurnStopReason.noLegalActions,
        );
        expect(result.appliedActionCount, 0);
        expect(result.didApplyAction, isFalse);
      },
    );
  });
}

ClassicHareegGameController _controllerForCpuDrawTurn() {
  final round = ClassicHareegRound.deal(
    setup: ClassicHareegSetup.defaults(),
    seed: 5,
  );
  final hands = _mutableHands(round);
  final southHand = hands[PlayerSeat.south]!;
  final discarded = southHand.firstWhere((card) => !card.isJoker);
  southHand.removeWhere((card) => card.id == discarded.id);

  return ClassicHareegGameController.fromSnapshot(
    ClassicHareegMatchSnapshot(
      setup: round.setup,
      hands: hands,
      stock: round.stock,
      discardPile: [discarded],
      starter: round.starter,
      currentSeat: PlayerSeat.east,
      turnPhase: TurnPhase.draw,
      savedAt: DateTime.utc(2026, 5, 21),
    ),
  );
}

ClassicHareegGameController _controllerForCpuActionTurn(PlayerSeat seat) {
  final round = ClassicHareegRound.deal(
    setup: ClassicHareegSetup.defaults(),
    seed: 7,
  );

  return ClassicHareegGameController.fromSnapshot(
    ClassicHareegMatchSnapshot(
      setup: round.setup,
      hands: _mutableHands(round),
      stock: round.stock,
      discardPile: const [],
      starter: round.starter,
      currentSeat: seat,
      turnPhase: TurnPhase.action,
      savedAt: DateTime.utc(2026, 5, 21),
    ),
  );
}

ClassicHareegGameController _controllerForInactiveCpuSeat() {
  final round = ClassicHareegRound.deal(
    setup: ClassicHareegSetup.defaults(),
    seed: 9,
  );

  return ClassicHareegGameController.fromSnapshot(
    ClassicHareegMatchSnapshot(
      setup: round.setup,
      hands: _mutableHands(round),
      stock: round.stock,
      discardPile: const [],
      starter: round.starter,
      currentSeat: PlayerSeat.east,
      turnPhase: TurnPhase.action,
      activeSeats: const [PlayerSeat.south],
      savedAt: DateTime.utc(2026, 5, 21),
    ),
  );
}

Map<PlayerSeat, List<HareegCard>> _mutableHands(ClassicHareegRound round) {
  return {
    for (final seat in PlayerSeat.values)
      seat: List<HareegCard>.of(round.hands[seat] ?? const []),
  };
}

class _FirstLegalStrategy implements CpuStrategy {
  @override
  CpuMoveIntent chooseMove(CpuTurnSnapshot snapshot) {
    return CpuMoveIntent(actionId: snapshot.legalActionIds.first);
  }
}

class _PreferredActionStrategy implements CpuStrategy {
  _PreferredActionStrategy(this.actionIds);

  final List<String> actionIds;

  @override
  CpuMoveIntent chooseMove(CpuTurnSnapshot snapshot) {
    for (final actionId in actionIds) {
      if (snapshot.legalActionIds.contains(actionId)) {
        return CpuMoveIntent(actionId: actionId);
      }
    }
    return CpuMoveIntent(actionId: snapshot.legalActionIds.first);
  }
}

class _DiscardStrategy implements CpuStrategy {
  @override
  CpuMoveIntent chooseMove(CpuTurnSnapshot snapshot) {
    final discard = snapshot.legalActionIds.firstWhere(
      (actionId) => ClassicHareegActionIds.discardCardId(actionId) != null,
    );
    return CpuMoveIntent(actionId: discard);
  }
}

class _IllegalStrategy implements CpuStrategy {
  const _IllegalStrategy();

  @override
  CpuMoveIntent chooseMove(CpuTurnSnapshot snapshot) {
    return const CpuMoveIntent(actionId: 'not-legal');
  }
}
