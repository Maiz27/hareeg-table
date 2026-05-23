import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/ui/core/audio/table_audio.dart';
import 'package:hareeg_table/ui/core/haptics/table_haptics.dart';
import 'package:hareeg_table/ui/features/game_table/table_human_action_flow_planner.dart';

void main() {
  group('ClassicHareegHumanActionFlowPlanner', () {
    test('rejected actions plan invalid cues and stop follow-up work', () {
      final plan = ClassicHareegHumanActionFlowPlanner.afterApply(
        actionId: ClassicHareegActionIds.drawStock,
        isSuccess: false,
        message: 'Draw before discarding.',
        soundPlayedWithFlight: false,
      );

      expect(plan.didApplyAction, isFalse);
      expect(plan.feedbackMessage, 'Draw before discarding.');
      expect(plan.feedbackIsError, isTrue);
      expect(plan.haptic, TableHapticEvent.illegalAction);
      expect(plan.sound, TableSoundEvent.invalidAction);
      expect(plan.shouldClearSelection, isFalse);
      expect(plan.shouldEnsureFiftyTicker, isFalse);
      expect(plan.shouldPersist, isFalse);
      expect(plan.shouldRunCpuAfterPersist, isFalse);
    });

    test(
      'successful draw keeps selection and asks for persistence and CPU',
      () {
        final plan = ClassicHareegHumanActionFlowPlanner.afterApply(
          actionId: ClassicHareegActionIds.drawStock,
          isSuccess: true,
          message: null,
          soundPlayedWithFlight: false,
        );

        expect(plan.didApplyAction, isTrue);
        expect(plan.feedbackIsError, isFalse);
        expect(plan.haptic, TableHapticEvent.drawCard);
        expect(plan.sound, TableSoundEvent.drawStock);
        expect(plan.shouldClearSelection, isFalse);
        expect(plan.shouldEnsureFiftyTicker, isTrue);
        expect(plan.shouldPersist, isTrue);
        expect(plan.shouldRunCpuAfterPersist, isTrue);
      },
    );

    test(
      'successful table plays clear selection and suppress flight sound',
      () {
        final actionId = ClassicHareegActionIds.placeCoverActionId(
          targetSeat: PlayerSeat.east,
          meldIndex: 0,
          cardIds: const ['jack-diamonds'],
        );

        final plan = ClassicHareegHumanActionFlowPlanner.afterApply(
          actionId: actionId,
          isSuccess: true,
          message: 'Cover placed.',
          soundPlayedWithFlight: true,
        );

        expect(plan.feedbackMessage, 'Cover placed.');
        expect(plan.haptic, TableHapticEvent.buttonTap);
        expect(plan.sound, isNull);
        expect(plan.shouldClearSelection, isTrue);
        expect(plan.shouldPersist, isTrue);
        expect(plan.shouldRunCpuAfterPersist, isTrue);
      },
    );

    test(
      'successful non-visual actions keep haptics without requiring sound',
      () {
        final plan = ClassicHareegHumanActionFlowPlanner.afterApply(
          actionId: ClassicHareegActionIds.usePendingDiscard,
          isSuccess: true,
          message: 'The picked up discard must be used.',
          soundPlayedWithFlight: false,
        );

        expect(plan.haptic, TableHapticEvent.buttonTap);
        expect(plan.sound, isNull);
        expect(plan.shouldClearSelection, isFalse);
        expect(plan.shouldPersist, isTrue);
      },
    );
  });
}
