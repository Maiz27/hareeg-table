import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_fifty_claim_planner.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_finish_planner.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';

void main() {
  group('ClassicHareegFinishPlanner cover-aware planning', () {
    test('finds a covers-only finish that a melds-only search misses', () {
      final eight = card(CardRank.eight, CardSuit.spades);
      final nine = card(CardRank.nine, CardSuit.spades);
      final finalDiscard = card(CardRank.two, CardSuit.hearts);

      final planner = ClassicHareegFinishPlanner(
        [eight, nine, finalDiscard],
        coverTargets: [spadesRunTarget()],
      );

      expect(planner.partitionWithout(finalDiscard), isNull);

      final parts = planner.planWithout(finalDiscard);
      expect(parts, isNotNull);
      expect(parts!.melds, isEmpty);
      expect(parts.covers, hasLength(1));
      expect(parts.covers.single.targetSeat, PlayerSeat.north);
      expect(parts.covers.single.meldIndex, 0);
      expect(
        parts.covers.single.cards.map((c) => c.label),
        orderedEquals(['8S', '9S']),
      );
    });

    test('cover chains require the bridging card (no gap jumps)', () {
      // 9S can only land after 8S bridges the 5-6-7S run; without 8S in the
      // card set there is no legal route.
      final nine = card(CardRank.nine, CardSuit.spades);
      final finalDiscard = card(CardRank.two, CardSuit.hearts);

      final planner = ClassicHareegFinishPlanner(
        [nine, finalDiscard],
        coverTargets: [spadesRunTarget()],
      );

      expect(planner.planWithout(finalDiscard), isNull);
      expect(planner.hasFinishUseContaining(nine.id), isFalse);
    });

    test('mixes fresh melds with cover placements', () {
      final kings = [
        card(CardRank.king, CardSuit.clubs),
        card(CardRank.king, CardSuit.diamonds),
        card(CardRank.king, CardSuit.hearts),
      ];
      final eight = card(CardRank.eight, CardSuit.spades);
      final finalDiscard = card(CardRank.two, CardSuit.hearts);

      final planner = ClassicHareegFinishPlanner(
        [...kings, eight, finalDiscard],
        coverTargets: [spadesRunTarget()],
      );

      final parts = planner.planWithout(finalDiscard);
      expect(parts, isNotNull);
      expect(parts!.melds, hasLength(1));
      expect(parts.melds.single.cards, hasLength(3));
      expect(parts.covers, hasLength(1));
      expect(parts.covers.single.cards.single.label, '8S');
    });

    test('unopened cover plans need fresh melds above the benchmark', () {
      final lowMeld = [
        card(CardRank.two, CardSuit.clubs),
        card(CardRank.two, CardSuit.diamonds),
        card(CardRank.two, CardSuit.spades),
      ];
      final eight = card(CardRank.eight, CardSuit.spades);
      final finalDiscard = card(CardRank.three, CardSuit.hearts);

      final constrained = ClassicHareegFinishPlanner(
        [...lowMeld, eight, finalDiscard],
        coverTargets: [spadesRunTarget()],
        coverPlanMinimumMeldValue: 51,
      );
      final unconstrained = ClassicHareegFinishPlanner(
        [...lowMeld, eight, finalDiscard],
        coverTargets: [spadesRunTarget()],
      );

      // 2-2-2 is worth 6 < 51, so the cover-routed plan is rejected for the
      // unopened seat but fine for an opened one.
      expect(constrained.planWithout(finalDiscard), isNull);
      expect(unconstrained.planWithout(finalDiscard), isNotNull);
    });

    test('melds-only perfect hands stay exempt from the cover benchmark', () {
      final lowMeld = [
        card(CardRank.two, CardSuit.clubs),
        card(CardRank.two, CardSuit.diamonds),
        card(CardRank.two, CardSuit.spades),
      ];
      final finalDiscard = card(CardRank.three, CardSuit.hearts);

      final planner = ClassicHareegFinishPlanner(
        [...lowMeld, finalDiscard],
        coverTargets: [spadesRunTarget()],
        coverPlanMinimumMeldValue: 51,
      );

      final parts = planner.planWithout(finalDiscard);
      expect(parts, isNotNull);
      expect(parts!.covers, isEmpty);
      expect(parts.melds, hasLength(1));
    });
  });

  group('finishPlanForClaim cover routing', () {
    test('claimed card may land as the second cover of a chain', () {
      // Owner-named scenario: the claimant's own 8S opens the spot, the
      // claimed 9S covers after it. No fresh meld uses the claimed card.
      final discarded = card(CardRank.nine, CardSuit.spades);
      final hand = [
        card(CardRank.eight, CardSuit.spades),
        card(CardRank.two, CardSuit.hearts),
      ];

      final meldsOnly = ClassicHareegFiftyClaimPlanner.finishPlanForClaim(
        hand: hand,
        discarded: discarded,
        playerOpened: true,
      );
      final coverAware = ClassicHareegFiftyClaimPlanner.finishPlanForClaim(
        hand: hand,
        discarded: discarded,
        playerOpened: true,
        coverTargets: [spadesRunTarget()],
      );

      expect(meldsOnly, isNull);
      expect(coverAware, isNotNull);
      expect(coverAware!.finalDiscard.label, '2H');
      expect(coverAware.melds, isEmpty);
      expect(coverAware.covers, hasLength(1));
      expect(
        coverAware.covers.single.cards.map((c) => c.label),
        orderedEquals(['8S', '9S']),
      );
      // Claim validation consumes covers as played groups.
      expect(coverAware.allPlayedMelds, hasLength(1));
      expect(coverAware.allPlayedMelds.single.valueSnapshot, 17);
    });

    test('unopened claimant cannot claim a covers-only Fifty below bench', () {
      final discarded = card(CardRank.nine, CardSuit.spades);
      final hand = [
        card(CardRank.eight, CardSuit.spades),
        card(CardRank.two, CardSuit.hearts),
      ];

      final plan = ClassicHareegFiftyClaimPlanner.finishPlanForClaim(
        hand: hand,
        discarded: discarded,
        playerOpened: false,
        coverTargets: [spadesRunTarget()],
        openingRequirement: 51,
      );

      expect(plan, isNull);
    });
  });
}

ClassicHareegFinishCoverTarget spadesRunTarget() {
  return ClassicHareegFinishCoverTarget(
    owner: PlayerSeat.north,
    meldIndex: 0,
    meldCards: [
      card(CardRank.five, CardSuit.spades, 9),
      card(CardRank.six, CardSuit.spades, 9),
      card(CardRank.seven, CardSuit.spades, 9),
    ],
  );
}

HareegCard card(CardRank rank, CardSuit suit, [int deckIndex = 1]) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
