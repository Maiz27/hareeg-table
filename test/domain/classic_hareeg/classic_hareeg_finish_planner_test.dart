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

    test('an ambiguous joker meld still proves a finish (playtest)', () {
      // Q-K-joker reads as J-Q-K or Q-K-A: resolveMeldCards demands a human
      // choice for that ambiguity, which used to make the candidate INVALID
      // here — hiding whole finishes (and their Fifty claims) behind a joker
      // with more than one legal identity. Any legal identity proves the
      // meld placeable; the planner now resolves to the best-value variant.
      final queen = card(CardRank.queen, CardSuit.spades);
      final king = card(CardRank.king, CardSuit.spades);
      const joker = HareegCard.joker(deckIndex: 90, jokerIndex: 0);
      final finalDiscard = card(CardRank.two, CardSuit.hearts);

      final planner = ClassicHareegFinishPlanner([
        queen,
        king,
        joker,
        finalDiscard,
      ]);

      final parts = planner.planWithout(finalDiscard);
      expect(parts, isNotNull);
      expect(parts!.melds, hasLength(1));
      expect(parts.covers, isEmpty);
    });

    test('two ambiguous joker melds plus a cover plan together (playtest)', () {
      // The owner's screenshot hand: 3♠ 5♠ 7♠ Q♠ K♠ + two jokers + a drawn
      // 5♥ that covers a table heart run. Full finish: 5♥ cover, the
      // 5-joker-7♠ and Q-K-joker runs as fresh melds, 3♠ as the final
      // discard. The ambiguous Q-K-joker used to sink the whole plan.
      final threeSpades = card(CardRank.three, CardSuit.spades);
      final fiveHearts = card(CardRank.five, CardSuit.hearts);

      final planner = ClassicHareegFinishPlanner(
        [
          threeSpades,
          card(CardRank.five, CardSuit.spades),
          card(CardRank.seven, CardSuit.spades),
          card(CardRank.queen, CardSuit.spades),
          card(CardRank.king, CardSuit.spades),
          const HareegCard.joker(deckIndex: 90, jokerIndex: 0),
          const HareegCard.joker(deckIndex: 91, jokerIndex: 1),
          fiveHearts,
        ],
        coverTargets: [
          ClassicHareegFinishCoverTarget(
            owner: PlayerSeat.west,
            meldIndex: 0,
            meldCards: [
              card(CardRank.six, CardSuit.hearts),
              card(CardRank.seven, CardSuit.hearts),
              card(CardRank.eight, CardSuit.hearts),
              card(CardRank.nine, CardSuit.hearts),
            ],
          ),
        ],
      );

      final parts = planner.planWithout(threeSpades);
      expect(parts, isNotNull);
      expect(parts!.melds, hasLength(2));
      expect(parts.covers, hasLength(1));
      expect(parts.covers.single.cards.map((c) => c.id), [fiveHearts.id]);
    });

    test('two-joker meld resolves to its true max value for the gate', () {
      // 4S + two jokers reads as a SET (4 4 4 = 12) or a SEQUENCE (4 5 6 = 15).
      // resolveMeldVariants enumerates the equal-value set readings BEFORE the
      // sequence reading; with the old picker-sized limit (5) the higher
      // sequence reading was truncated, so the planner's "best variant" value
      // was 12, not the true 15. An unopened seat with a benchmark of 13 then
      // saw a value-12 meld and rejected a genuinely-clearing cover plan.
      // With the exhaustive limit the value-15 sequence reading survives.
      final fourSpades = card(CardRank.four, CardSuit.spades);
      const jokerA = HareegCard.joker(deckIndex: 90, jokerIndex: 0);
      const jokerB = HareegCard.joker(deckIndex: 91, jokerIndex: 1);
      final coverEight = card(CardRank.eight, CardSuit.hearts);
      final finalDiscard = card(CardRank.two, CardSuit.diamonds);

      final cards = [fourSpades, jokerA, jokerB, coverEight, finalDiscard];

      // 8H covers a 5-6-7H table run; the spades stay isolated so the two
      // jokers can only land in the 4S fresh meld.
      final coverTargets = [
        ClassicHareegFinishCoverTarget(
          owner: PlayerSeat.north,
          meldIndex: 0,
          meldCards: [
            card(CardRank.five, CardSuit.hearts, 9),
            card(CardRank.six, CardSuit.hearts, 9),
            card(CardRank.seven, CardSuit.hearts, 9),
          ],
        ),
      ];

      // Benchmark 13: the value-12 set reading fails the gate, the value-15
      // sequence reading clears it. Pre-fix this finish was invisible.
      final gated = ClassicHareegFinishPlanner(
        cards,
        coverTargets: coverTargets,
        coverPlanMinimumMeldValue: 13,
      );

      final parts = gated.planWithout(finalDiscard);
      expect(parts, isNotNull);
      expect(parts!.melds, hasLength(1));
      expect(parts.covers, hasLength(1));
      expect(parts.covers.single.cards.map((c) => c.label), ['8H']);

      // The chosen meld must be the value-15 sequence reading, not the
      // value-12 set, and both jokers must carry a represented identity so the
      // downstream proof script can replay the placement.
      final meld = parts.melds.single;
      expect(meld.totalValue, 15);
      final jokers = meld.cards.where((c) => c.isJoker).toList();
      expect(jokers, hasLength(2));
      for (final joker in jokers) {
        expect(joker.representedIdentity, isNotNull);
      }

      // Benchmark 16 sits above even the true max, so no finish exists.
      final tooHigh = ClassicHareegFinishPlanner(
        cards,
        coverTargets: coverTargets,
        coverPlanMinimumMeldValue: 16,
      );
      expect(tooHigh.planWithout(finalDiscard), isNull);
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
