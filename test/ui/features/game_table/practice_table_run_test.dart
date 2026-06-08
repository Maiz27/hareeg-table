import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_strategy.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/game_table/practice_table_run.dart';
import 'package:hareeg_table/ui/features/learning/practice/core_turn_practice_pack.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_session.dart';

void main() {
  group('PracticeTableRun', () {
    test('filters table controls and projects the active banner', () {
      final run = PracticeTableRun(
        PracticeSession(script: CoreTurnPracticePack.turnRhythm()),
      );

      expect(
        run.controlActionIdsFor(
          actionIds: [
            ClassicHareegActionIds.drawStock,
            ClassicHareegActionIds.takeDiscard,
          ],
          isHumanTurn: true,
        ),
        [ClassicHareegActionIds.drawStock],
      );
      expect(
        run.controlActionIdsFor(
          actionIds: [ClassicHareegActionIds.drawStock],
          isHumanTurn: false,
        ),
        isEmpty,
      );

      final banner = run.bannerState(
        blockedByOverlay: false,
        scriptedIntroRunning: false,
      );
      expect(banner, isNotNull);
      expect(
        banner!.prompt(AppStrings.english),
        contains('draw one from the stock'),
      );
    });

    test('submitTableAction maps practice results to table results', () {
      final run = PracticeTableRun(
        PracticeSession(script: CoreTurnPracticePack.turnRhythm()),
      );

      final submission = run.submitTableAction(
        ClassicHareegActionIds.drawStock,
      );
      expect(submission.tableResult.isSuccess, isTrue);

      final effect = run.applyProgress(
        submission.result,
        submission.completedStep,
      );
      expect(effect.shouldRebuild, isTrue);
      expect(run.reaction?.call(AppStrings.english), contains('drawn'));

      final banner = run.bannerState(
        blockedByOverlay: false,
        scriptedIntroRunning: false,
      );
      expect(banner?.prompt(AppStrings.english), contains('discard it'));
    });

    test('turn-rhythm progress drives banner and completion state', () {
      final run = PracticeTableRun(
        PracticeSession(script: CoreTurnPracticePack.turnRhythm()),
      );

      expect(
        run.highlighting(isHumanTurn: true, topDiscard: null).highlightStock,
        isTrue,
      );

      var completedStep = run.currentStep;
      var result = run.submit(ClassicHareegActionIds.drawStock);
      var effect = run.applyProgress(result, completedStep);

      expect(effect.shouldRebuild, isTrue);
      expect(effect.shouldPersistCompletion, isFalse);
      expect(run.reaction, isNotNull);
      expect(run.isComplete, isFalse);

      completedStep = run.currentStep;
      result = run.submit(run.session.allowedActions.first.id);
      effect = run.applyProgress(result, completedStep);

      expect(effect.shouldRebuild, isTrue);
      expect(effect.shouldPersistCompletion, isTrue);
      expect(effect.lessonId, 'turn-rhythm');
      expect(run.isComplete, isTrue);
    });

    test('restart swaps to a fresh session and clears presentation state', () {
      final run = PracticeTableRun(
        PracticeSession(script: CoreTurnPracticePack.turnRhythm()),
      );
      var completedStep = run.currentStep;
      run.applyProgress(
        run.submit(ClassicHareegActionIds.drawStock),
        completedStep,
      );
      completedStep = run.currentStep;
      run.applyProgress(
        run.submit(run.session.allowedActions.first.id),
        completedStep,
      );
      expect(run.isComplete, isTrue);

      run.restart(CoreTurnPracticePack.firstMeld());

      expect(run.session.script.lessonId, 'first-meld');
      expect(run.isComplete, isFalse);
      expect(run.reaction, isNull);
      expect(run.isScoreReveal, isFalse);
    });

    test('intro strategy replays scripted action ids in order', () {
      final strategy = PracticeIntroStrategy(['draw-stock', 'discard:c1']);

      expect(
        strategy
            .chooseMove(
              CpuTurnSnapshot(
                seat: PlayerSeat.west,
                legalActionIds: const ['draw-stock'],
              ),
            )
            .actionId,
        'draw-stock',
      );
      expect(
        strategy
            .chooseMove(
              CpuTurnSnapshot(
                seat: PlayerSeat.west,
                legalActionIds: const ['discard:c1'],
              ),
            )
            .actionId,
        'discard:c1',
      );
      expect(
        () => strategy.chooseMove(
          CpuTurnSnapshot(seat: PlayerSeat.west, legalActionIds: const []),
        ),
        throwsStateError,
      );
    });
  });
}
