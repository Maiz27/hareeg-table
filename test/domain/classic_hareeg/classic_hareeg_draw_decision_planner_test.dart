import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_draw_decision_planner.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_fifty_claim_planner.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';

void main() {
  group('ClassicHareegDrawDecisionPlanner', () {
    test('inactive seats have no draw decision actions', () {
      final plan = evaluate(isSeatTurn: false);

      expect(plan.scenario, ClassicHareegDrawDecisionScenario.inactive);
      expect(plan.actionIds, isEmpty);
      expect(plan.shouldEndRoundAsDraw, isFalse);
    });

    test('stock draw is the only action when no discard pickup is legal', () {
      final plan = evaluate(canTakePreviousDiscard: false);

      expect(plan.scenario, ClassicHareegDrawDecisionScenario.stockDrawOnly);
      expect(plan.actionIds, [ClassicHareegActionIds.drawStock]);
      expect(plan.canDrawStock, isTrue);
      expect(plan.canTakeDiscard, isFalse);
    });

    test(
      'stock and previous discard are both available in normal draw phase',
      () {
        final plan = evaluate(canTakePreviousDiscard: true);

        expect(
          plan.scenario,
          ClassicHareegDrawDecisionScenario.stockDrawOrDiscardPickup,
        );
        expect(plan.actionIds, [
          ClassicHareegActionIds.drawStock,
          ClassicHareegActionIds.takeDiscard,
        ]);
      },
    );

    test('Fifty claim is ordered before normal draw and pickup actions', () {
      final plan = evaluate(
        canTakePreviousDiscard: true,
        fiftyClaimPlan: fiftyClaim(
          scenario: ClassicHareegFiftyClaimScenario.claimWindowOpen,
          shouldAdvertise: true,
        ),
      );

      expect(
        plan.scenario,
        ClassicHareegDrawDecisionScenario.fiftyStockDrawAndDiscardPickup,
      );
      expect(
        plan.fiftyClaimPlan.scenario,
        ClassicHareegFiftyClaimScenario.claimWindowOpen,
      );
      expect(plan.actionIds, [
        ClassicHareegActionIds.claimFifty,
        ClassicHareegActionIds.drawStock,
        ClassicHareegActionIds.takeDiscard,
      ]);
    });

    test(
      'stock exhaustion with a finishing pickup exposes only take discard',
      () {
        final plan = evaluate(
          stockIsEmpty: true,
          canTakePreviousDiscard: true,
          pickupWouldFinish: true,
        );

        expect(
          plan.scenario,
          ClassicHareegDrawDecisionScenario.stockExhaustedPickupFinishOnly,
        );
        expect(plan.actionIds, [ClassicHareegActionIds.takeDiscard]);
        expect(plan.shouldEndRoundAsDraw, isFalse);
      },
    );

    test('stock exhaustion without a finishing pickup ends as a draw', () {
      final plan = evaluate(
        stockIsEmpty: true,
        canTakePreviousDiscard: true,
        pickupWouldFinish: false,
      );

      expect(
        plan.scenario,
        ClassicHareegDrawDecisionScenario.stockExhaustedRoundDraw,
      );
      expect(plan.actionIds, isEmpty);
      expect(plan.shouldEndRoundAsDraw, isTrue);
    });

    test('pending discard state is not treated as a draw decision', () {
      final plan = evaluate(hasPendingDiscard: true);

      expect(plan.scenario, ClassicHareegDrawDecisionScenario.pendingDiscard);
      expect(plan.actionIds, isEmpty);
    });
  });
}

ClassicHareegDrawDecisionPlan evaluate({
  bool isRoundOver = false,
  bool isSeatTurn = true,
  bool isSeatActive = true,
  TurnPhase phase = TurnPhase.draw,
  bool hasPendingDiscard = false,
  bool stockIsEmpty = false,
  bool canTakePreviousDiscard = false,
  bool pickupWouldFinish = false,
  ClassicHareegFiftyClaimPlan? fiftyClaimPlan,
}) {
  return ClassicHareegDrawDecisionPlanner.evaluate(
    isRoundOver: isRoundOver,
    isSeatTurn: isSeatTurn,
    isSeatActive: isSeatActive,
    phase: phase,
    hasPendingDiscard: hasPendingDiscard,
    stockIsEmpty: stockIsEmpty,
    canTakePreviousDiscard: canTakePreviousDiscard,
    pickupWouldFinish: pickupWouldFinish,
    fiftyClaimPlan: fiftyClaimPlan ?? fiftyClaim(),
  );
}

ClassicHareegFiftyClaimPlan fiftyClaim({
  ClassicHareegFiftyClaimScenario scenario =
      ClassicHareegFiftyClaimScenario.noWindow,
  bool shouldAdvertise = false,
}) {
  return ClassicHareegFiftyClaimPlan(
    scenario: scenario,
    shouldAdvertise: shouldAdvertise,
    canApply: shouldAdvertise,
    message: shouldAdvertise
        ? 'Fifty claim is available.'
        : 'Only the immediate next player can claim Fifty.',
  );
}
