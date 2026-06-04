import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_fifty_claim_planner.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/fifty_rules.dart';

void main() {
  group('ClassicHareegFiftyClaimPlanner', () {
    test('blocking tiers advertise only a proven valid Fifty', () {
      final discarded = card(CardRank.nine, CardSuit.clubs);
      final hand = [
        card(CardRank.seven, CardSuit.clubs),
        card(CardRank.eight, CardSuit.clubs),
        card(CardRank.two, CardSuit.hearts),
      ];
      final window = windowFor(discarded);

      final result = ClassicHareegFiftyClaimPlanner.evaluate(
        purpose: ClassicHareegFiftyClaimPurpose.advertise,
        strictness: TableStrictness.coaching,
        window: window,
        claimant: PlayerSeat.east,
        phase: TurnPhase.draw,
        elapsedSeconds: 1,
        topDiscard: discarded,
        finishPlanResolver: () =>
            ClassicHareegFiftyClaimPlanner.finishPlanForClaim(
              hand: hand,
              discarded: discarded,
              playerOpened: false,
            ),
      );

      expect(result.scenario, ClassicHareegFiftyClaimScenario.validClaim);
      expect(result.shouldAdvertise, isTrue);
      expect(result.canApply, isTrue);
      expect(result.appliesMistake, isFalse);
      expect(result.finishPlan?.finalDiscard.label, '2H');
    });

    test('penalty-tier advertisement does not need finish proof', () {
      var resolverCalled = false;
      final discarded = card(CardRank.nine, CardSuit.clubs, 2);

      final result = ClassicHareegFiftyClaimPlanner.evaluate(
        purpose: ClassicHareegFiftyClaimPurpose.advertise,
        strictness: TableStrictness.strict,
        window: windowFor(discarded),
        claimant: PlayerSeat.east,
        phase: TurnPhase.draw,
        elapsedSeconds: 1,
        topDiscard: discarded,
        finishPlanResolver: () {
          resolverCalled = true;
          return null;
        },
      );

      expect(result.scenario, ClassicHareegFiftyClaimScenario.claimWindowOpen);
      expect(result.shouldAdvertise, isTrue);
      expect(result.canApply, isFalse);
      expect(resolverCalled, isFalse);
    });

    test('strict tier converts wrong Fifty claims into +3 mistakes', () {
      final discarded = card(CardRank.nine, CardSuit.clubs, 3);

      final result = ClassicHareegFiftyClaimPlanner.evaluate(
        purpose: ClassicHareegFiftyClaimPurpose.apply,
        strictness: TableStrictness.strict,
        window: windowFor(discarded),
        claimant: PlayerSeat.east,
        phase: TurnPhase.draw,
        elapsedSeconds: 1,
        topDiscard: discarded,
        finishPlanResolver: () => null,
      );

      expect(
        result.scenario,
        ClassicHareegFiftyClaimScenario.penalizedWrongClaim,
      );
      expect(result.canApply, isTrue);
      expect(result.appliesMistake, isTrue);
      expect(result.mistakeResolution?.penaltyPoints, 3);
      expect(result.mistakeResolution?.removeFromRound, isFalse);
    });

    test('table tier converts wrong Fifty claims into removal mistakes', () {
      final discarded = card(CardRank.nine, CardSuit.clubs, 4);

      final result = ClassicHareegFiftyClaimPlanner.evaluate(
        purpose: ClassicHareegFiftyClaimPurpose.apply,
        strictness: TableStrictness.table,
        window: windowFor(discarded),
        claimant: PlayerSeat.east,
        phase: TurnPhase.draw,
        elapsedSeconds: 1,
        topDiscard: discarded,
        finishPlanResolver: () => null,
      );

      expect(
        result.scenario,
        ClassicHareegFiftyClaimScenario.penalizedWrongClaim,
      );
      expect(result.canApply, isTrue);
      expect(result.mistakeResolution?.penaltyPoints, 17);
      expect(result.mistakeResolution?.removeFromRound, isTrue);
    });

    test('blocking tiers block wrong Fifty claims without a penalty', () {
      final discarded = card(CardRank.nine, CardSuit.clubs, 5);

      final result = ClassicHareegFiftyClaimPlanner.evaluate(
        purpose: ClassicHareegFiftyClaimPurpose.apply,
        strictness: TableStrictness.coaching,
        window: windowFor(discarded),
        claimant: PlayerSeat.east,
        phase: TurnPhase.draw,
        elapsedSeconds: 1,
        topDiscard: discarded,
        finishPlanResolver: () => null,
      );

      expect(
        result.scenario,
        ClassicHareegFiftyClaimScenario.blockedWrongClaim,
      );
      expect(result.shouldAdvertise, isFalse);
      expect(result.canApply, isFalse);
      expect(result.mistakeResolution, isNull);
      expect(result.message, contains('valid Fifty'));
    });

    test('expired windows and missing discards are blocked before proof', () {
      final discarded = card(CardRank.nine, CardSuit.clubs, 6);
      var resolverCalls = 0;

      final expired = ClassicHareegFiftyClaimPlanner.evaluate(
        purpose: ClassicHareegFiftyClaimPurpose.apply,
        strictness: TableStrictness.strict,
        window: windowFor(discarded),
        claimant: PlayerSeat.east,
        phase: TurnPhase.draw,
        elapsedSeconds: 4,
        topDiscard: discarded,
        finishPlanResolver: () {
          resolverCalls += 1;
          return null;
        },
      );
      final missing = ClassicHareegFiftyClaimPlanner.evaluate(
        purpose: ClassicHareegFiftyClaimPurpose.apply,
        strictness: TableStrictness.strict,
        window: windowFor(discarded),
        claimant: PlayerSeat.east,
        phase: TurnPhase.draw,
        elapsedSeconds: 1,
        topDiscard: null,
        finishPlanResolver: () {
          resolverCalls += 1;
          return null;
        },
      );

      expect(expired.scenario, ClassicHareegFiftyClaimScenario.expired);
      expect(missing.scenario, ClassicHareegFiftyClaimScenario.missingDiscard);
      expect(expired.canApply, isFalse);
      expect(missing.canApply, isFalse);
      expect(resolverCalls, 0);
    });
  });
}

FiftyClaimWindow windowFor(HareegCard discarded) {
  return ClassicHareegFiftyRules.openWindow(
    discarder: PlayerSeat.south,
    discardedCard: discarded,
    durationSeconds: 4,
  );
}

HareegCard card(CardRank rank, CardSuit suit, [int deckIndex = 1]) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
