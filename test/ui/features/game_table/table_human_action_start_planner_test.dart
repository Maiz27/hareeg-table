import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/ui/features/game_table/table_human_action_start_planner.dart';

void main() {
  group('ClassicHareegHumanActionStartPlanner', () {
    test('blocks requests while CPU flow is running', () {
      final plan = ClassicHareegHumanActionStartPlanner.start(
        actionId: ClassicHareegActionIds.drawStock,
        playFlight: true,
        isCpuRunning: true,
        isOpeningDealRunning: false,
        isHumanActionPending: false,
      );

      expect(plan.scenario, ClassicHareegHumanActionStartScenario.blockedByCpu);
      expect(plan.shouldStart, isFalse);
      expect(plan.presentation, isNull);
    });

    test(
      'blocks requests during opening deal before pending-action checks',
      () {
        final plan = ClassicHareegHumanActionStartPlanner.start(
          actionId: ClassicHareegActionIds.drawStock,
          playFlight: true,
          isCpuRunning: false,
          isOpeningDealRunning: true,
          isHumanActionPending: true,
        );

        expect(
          plan.scenario,
          ClassicHareegHumanActionStartScenario.blockedByOpeningDeal,
        );
        expect(plan.shouldLockInput, isFalse);
      },
    );

    test('blocks overlapping human action requests', () {
      final plan = ClassicHareegHumanActionStartPlanner.start(
        actionId: ClassicHareegActionIds.drawStock,
        playFlight: true,
        isCpuRunning: false,
        isOpeningDealRunning: false,
        isHumanActionPending: true,
      );

      expect(
        plan.scenario,
        ClassicHareegHumanActionStartScenario.blockedByPendingHumanAction,
      );
      expect(plan.shouldStart, isFalse);
    });

    test('plans a pre-apply flight for visual actions when requested', () {
      final plan = ClassicHareegHumanActionStartPlanner.start(
        actionId: ClassicHareegActionIds.drawStock,
        playFlight: true,
        isCpuRunning: false,
        isOpeningDealRunning: false,
        isHumanActionPending: false,
      );

      expect(
        plan.scenario,
        ClassicHareegHumanActionStartScenario.playFlightBeforeApply,
      );
      expect(plan.shouldStart, isTrue);
      expect(plan.shouldLockInput, isTrue);
      expect(plan.shouldPlayFlight, isTrue);
      expect(plan.presentation?.flight, isNotNull);
    });

    test('skips pre-apply flights when the caller disables them', () {
      final actionId = ClassicHareegActionIds.placeCoverActionId(
        targetSeat: PlayerSeat.east,
        meldIndex: 0,
        cardIds: const ['jack-diamonds'],
      );

      final plan = ClassicHareegHumanActionStartPlanner.start(
        actionId: actionId,
        playFlight: false,
        isCpuRunning: false,
        isOpeningDealRunning: false,
        isHumanActionPending: false,
      );

      expect(
        plan.scenario,
        ClassicHareegHumanActionStartScenario.applyWithoutFlight,
      );
      expect(plan.presentation?.flight, isNotNull);
      expect(plan.shouldPlayFlight, isFalse);
    });

    test('non-visual actions apply without a pre-apply flight', () {
      final plan = ClassicHareegHumanActionStartPlanner.start(
        actionId: ClassicHareegActionIds.usePendingDiscard,
        playFlight: true,
        isCpuRunning: false,
        isOpeningDealRunning: false,
        isHumanActionPending: false,
      );

      expect(
        plan.scenario,
        ClassicHareegHumanActionStartScenario.applyWithoutFlight,
      );
      expect(plan.presentation?.flight, isNull);
      expect(plan.shouldPlayFlight, isFalse);
    });

    test('after pre-apply records sound only for rendered planned flights', () {
      final rendered = ClassicHareegHumanActionStartPlanner.afterPreApply(
        isMounted: true,
        plannedFlight: true,
        flightPlayed: true,
      );
      final missingSource = ClassicHareegHumanActionStartPlanner.afterPreApply(
        isMounted: true,
        plannedFlight: true,
        flightPlayed: false,
      );

      expect(rendered.shouldApply, isTrue);
      expect(rendered.soundPlayedWithFlight, isTrue);
      expect(missingSource.shouldApply, isTrue);
      expect(missingSource.soundPlayedWithFlight, isFalse);
    });

    test('after pre-apply stops when the widget unmounted', () {
      final gate = ClassicHareegHumanActionStartPlanner.afterPreApply(
        isMounted: false,
        plannedFlight: true,
        flightPlayed: true,
      );

      expect(
        gate.scenario,
        ClassicHareegHumanActionApplyGateScenario.unmounted,
      );
      expect(gate.shouldApply, isFalse);
      expect(gate.soundPlayedWithFlight, isFalse);
    });
  });
}
