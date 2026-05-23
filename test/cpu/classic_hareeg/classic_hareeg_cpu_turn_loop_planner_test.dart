import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/classic_hareeg_cpu_turn_loop_planner.dart';

void main() {
  group('ClassicHareegCpuTurnLoopPlanner', () {
    test('turn gate prioritizes round over before other stop scenarios', () {
      final plan = ClassicHareegCpuTurnLoopPlanner.turnGate(
        isRoundOver: true,
        isHumanTurn: true,
        appliedActionCount: 64,
        actionLimit: 64,
      );

      expect(plan.scenario, ClassicHareegCpuTurnLoopScenario.roundOver);
      expect(plan.shouldStop, isTrue);
    });

    test('turn gate prioritizes human turn before safety limit', () {
      final plan = ClassicHareegCpuTurnLoopPlanner.turnGate(
        isRoundOver: false,
        isHumanTurn: true,
        appliedActionCount: 64,
        actionLimit: 64,
      );

      expect(plan.scenario, ClassicHareegCpuTurnLoopScenario.humanTurn);
      expect(plan.shouldStop, isTrue);
    });

    test('turn gate stops at the safety limit before another action', () {
      final plan = ClassicHareegCpuTurnLoopPlanner.turnGate(
        isRoundOver: false,
        isHumanTurn: false,
        appliedActionCount: 3,
        actionLimit: 3,
      );

      expect(plan.scenario, ClassicHareegCpuTurnLoopScenario.safetyLimit);
      expect(plan.shouldStop, isTrue);
    });

    test('turn gate continues while the CPU still owns flow', () {
      final plan = ClassicHareegCpuTurnLoopPlanner.turnGate(
        isRoundOver: false,
        isHumanTurn: false,
        appliedActionCount: 2,
        actionLimit: 3,
      );

      expect(plan.scenario, ClassicHareegCpuTurnLoopScenario.continueTurn);
      expect(plan.canContinue, isTrue);
    });

    test('legal action gate stops empty CPU action surfaces', () {
      final plan = ClassicHareegCpuTurnLoopPlanner.legalActionGate(
        hasLegalActions: false,
      );

      expect(plan.scenario, ClassicHareegCpuTurnLoopScenario.noLegalActions);
      expect(plan.shouldStop, isTrue);
    });

    test('hook gate stops when a caller hook declines continuation', () {
      final plan = ClassicHareegCpuTurnLoopPlanner.hookGate(
        shouldContinue: false,
      );

      expect(plan.scenario, ClassicHareegCpuTurnLoopScenario.hookStopped);
      expect(plan.shouldStop, isTrue);
    });

    test('after apply hook reports round over before hook stop', () {
      final roundOverPlan = ClassicHareegCpuTurnLoopPlanner.afterApplyHookGate(
        shouldContinue: false,
        isRoundOver: true,
      );
      final hookStopPlan = ClassicHareegCpuTurnLoopPlanner.afterApplyHookGate(
        shouldContinue: false,
        isRoundOver: false,
      );

      expect(
        roundOverPlan.scenario,
        ClassicHareegCpuTurnLoopScenario.roundOver,
      );
      expect(
        hookStopPlan.scenario,
        ClassicHareegCpuTurnLoopScenario.hookStopped,
      );
    });
  });
}
