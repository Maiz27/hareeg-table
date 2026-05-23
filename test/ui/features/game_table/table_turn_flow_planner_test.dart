import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/ui/features/game_table/table_turn_flow_planner.dart';

void main() {
  group('ClassicHareegTableTurnFlowPlanner', () {
    test('after frame plays an opening deal before CPU or persistence', () {
      final plan = ClassicHareegTableTurnFlowPlanner.afterFrame(
        isMounted: true,
        hasOpeningDealToPlay: true,
        isCpuRunning: false,
        isOpeningDealRunning: false,
        isRoundOver: false,
        isHumanTurn: false,
      );

      expect(plan.action, ClassicHareegTableTurnFlowAction.playOpeningDeal);
      expect(plan.scenario, ClassicHareegTableTurnFlowScenario.openingDeal);
    });

    test('after frame stops when the widget is unmounted', () {
      final plan = ClassicHareegTableTurnFlowPlanner.afterFrame(
        isMounted: false,
        hasOpeningDealToPlay: true,
        isCpuRunning: false,
        isOpeningDealRunning: false,
        isRoundOver: false,
        isHumanTurn: false,
      );

      expect(plan.action, ClassicHareegTableTurnFlowAction.stop);
      expect(plan.scenario, ClassicHareegTableTurnFlowScenario.unmounted);
      expect(plan.shouldStop, isTrue);
    });

    test('after opening deal runs CPU only when CPU flow is available', () {
      final plan = ClassicHareegTableTurnFlowPlanner.afterOpeningDeal(
        isMounted: true,
        isCpuRunning: false,
        isOpeningDealRunning: false,
        isRoundOver: false,
        isHumanTurn: false,
      );

      expect(plan.action, ClassicHareegTableTurnFlowAction.runCpuTurns);
      expect(plan.scenario, ClassicHareegTableTurnFlowScenario.cpuTurn);
    });

    test('human turns persist without asking the CPU runner to skip', () {
      final plan = ClassicHareegTableTurnFlowPlanner.afterOpeningDeal(
        isMounted: true,
        isCpuRunning: false,
        isOpeningDealRunning: false,
        isRoundOver: false,
        isHumanTurn: true,
      );

      expect(plan.action, ClassicHareegTableTurnFlowAction.persistTable);
      expect(
        plan.scenario,
        ClassicHareegTableTurnFlowScenario.humanTurnPersistence,
      );
    });

    test('round-over turns persist result state without CPU flow', () {
      final plan = ClassicHareegTableTurnFlowPlanner.afterOpeningDeal(
        isMounted: true,
        isCpuRunning: false,
        isOpeningDealRunning: false,
        isRoundOver: true,
        isHumanTurn: true,
      );

      expect(plan.action, ClassicHareegTableTurnFlowAction.persistTable);
      expect(
        plan.scenario,
        ClassicHareegTableTurnFlowScenario.roundOverPersistence,
      );
    });

    test('blocked CPU flow persists instead of starting another runner', () {
      final plan = ClassicHareegTableTurnFlowPlanner.afterOpeningDeal(
        isMounted: true,
        isCpuRunning: true,
        isOpeningDealRunning: false,
        isRoundOver: false,
        isHumanTurn: false,
      );

      expect(plan.action, ClassicHareegTableTurnFlowAction.persistTable);
      expect(
        plan.scenario,
        ClassicHareegTableTurnFlowScenario.blockedCpuPersistence,
      );
    });

    test('after CPU turns stops when CPU already persisted', () {
      final plan = ClassicHareegTableTurnFlowPlanner.afterCpuTurns(
        isMounted: true,
        didCpuPersistOrNavigate: true,
      );

      expect(plan.action, ClassicHareegTableTurnFlowAction.stop);
      expect(
        plan.scenario,
        ClassicHareegTableTurnFlowScenario.cpuAlreadyHandled,
      );
    });

    test('after CPU turns persists when CPU did not handle state', () {
      final plan = ClassicHareegTableTurnFlowPlanner.afterCpuTurns(
        isMounted: true,
        didCpuPersistOrNavigate: false,
      );

      expect(plan.action, ClassicHareegTableTurnFlowAction.persistTable);
      expect(
        plan.scenario,
        ClassicHareegTableTurnFlowScenario.cpuNeedsPersistence,
      );
    });
  });
}
