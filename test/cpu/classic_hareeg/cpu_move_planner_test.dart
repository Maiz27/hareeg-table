import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_move_planner.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';

void main() {
  group('ClassicHareegCpuMovePlanner', () {
    test('empty legal action surface produces no-action scenario', () {
      final plan = ClassicHareegCpuMovePlanner.evaluate(const []);

      expect(plan.scenario, ClassicHareegCpuMoveScenario.noLegalActions);
      expect(plan.hasAction, isFalse);
      expect(plan.actionId, isNull);
    });

    test('prioritizes Fifty before every other action', () {
      final plan = ClassicHareegCpuMovePlanner.evaluate([
        ClassicHareegActionIds.drawStock,
        ClassicHareegActionIds.claimFifty,
        ClassicHareegActionIds.playMeldActionId(['1', '2', '3']),
      ]);

      expect(plan.scenario, ClassicHareegCpuMoveScenario.fiftyClaim);
      expect(plan.actionId, ClassicHareegActionIds.claimFifty);
    });

    test(
      'chooses plain meld before represented-joker meld regardless of order',
      () {
        final represented =
            ClassicHareegActionIds.playMeldWithJokerIdentityActionId(
              cardIds: ['joker', '2', '3'],
              jokerId: 'joker',
              identity: const CardIdentity(
                rank: CardRank.four,
                suit: CardSuit.clubs,
              ),
            );
        final plain = ClassicHareegActionIds.playMeldActionId(['4', '5', '6']);

        final plan = ClassicHareegCpuMovePlanner.evaluate([
          represented,
          plain,
          ClassicHareegActionIds.drawStock,
        ]);

        expect(plan.scenario, ClassicHareegCpuMoveScenario.meldPlay);
        expect(plan.actionId, plain);
      },
    );

    test('falls through table play priorities before draw decisions', () {
      final replacement = ClassicHareegActionIds.replaceJokerActionId(
        targetSeat: PlayerSeat.south,
        meldIndex: 0,
        cardId: 'jack-clubs',
      );
      final cover = ClassicHareegActionIds.placeCoverActionId(
        targetSeat: PlayerSeat.south,
        meldIndex: 0,
        cardIds: ['jack-diamonds'],
      );

      final replacePlan = ClassicHareegCpuMovePlanner.evaluate([
        ClassicHareegActionIds.drawStock,
        cover,
        replacement,
      ]);
      final coverPlan = ClassicHareegCpuMovePlanner.evaluate([
        ClassicHareegActionIds.drawStock,
        cover,
      ]);

      expect(
        replacePlan.scenario,
        ClassicHareegCpuMoveScenario.jokerReplacement,
      );
      expect(replacePlan.actionId, replacement);
      expect(coverPlan.scenario, ClassicHareegCpuMoveScenario.cover);
      expect(coverPlan.actionId, cover);
    });

    test('draws stock before taking discard', () {
      final plan = ClassicHareegCpuMovePlanner.evaluate([
        ClassicHareegActionIds.takeDiscard,
        ClassicHareegActionIds.drawStock,
      ]);

      expect(plan.scenario, ClassicHareegCpuMoveScenario.drawStock);
      expect(plan.actionId, ClassicHareegActionIds.drawStock);
    });

    test(
      'chooses safe discard before returning pending discard or mistakes',
      () {
        final safeDiscard = '${ClassicHareegActionIds.discardPrefix}7-hearts';

        final plan = ClassicHareegCpuMovePlanner.evaluate([
          '${ClassicHareegActionIds.discardBlockedCoverPrefix}9-clubs',
          ClassicHareegActionIds.returnPendingDiscard,
          '${ClassicHareegActionIds.discardJokerPrefix}joker',
          safeDiscard,
        ]);

        expect(plan.scenario, ClassicHareegCpuMoveScenario.safeDiscard);
        expect(plan.actionId, safeDiscard);
      },
    );

    test('returns pending discard when no productive action exists', () {
      final plan = ClassicHareegCpuMovePlanner.evaluate([
        ClassicHareegActionIds.returnPendingDiscard,
      ]);

      expect(plan.scenario, ClassicHareegCpuMoveScenario.returnPendingDiscard);
      expect(plan.actionId, ClassicHareegActionIds.returnPendingDiscard);
    });

    test('falls back to the first legal action as a last resort', () {
      final blocked =
          '${ClassicHareegActionIds.discardBlockedCoverPrefix}9-clubs';
      final joker = '${ClassicHareegActionIds.discardJokerPrefix}joker';

      final plan = ClassicHareegCpuMovePlanner.evaluate([blocked, joker]);

      expect(plan.scenario, ClassicHareegCpuMoveScenario.fallback);
      expect(plan.actionId, blocked);
    });
  });
}
