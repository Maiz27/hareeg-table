import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_meld_play_eligibility.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

void main() {
  group('ClassicHareegMeldPlayEligibilityPlanner', () {
    test('already opened players may advertise regular meld plays', () {
      final played = meld([
        card(CardRank.five, CardSuit.clubs),
        card(CardRank.six, CardSuit.clubs),
        card(CardRank.seven, CardSuit.clubs),
      ]);

      final result = ClassicHareegMeldPlayEligibilityPlanner.evaluate(
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          openedSeats: {PlayerSeat.south},
        ),
        seat: PlayerSeat.south,
        stagedOpeningMelds: const [],
        playedMelds: [played],
        handCount: 6,
        playedCardIds: idsOf(played.cards),
      );

      expect(result.scenario, ClassicHareegMeldPlayScenario.regularMeld);
      expect(result.isAllowed, isTrue);
      expect(result.shouldAdvertise, isTrue);
      expect(result.opensPlayer, isFalse);
      expect(result.message, 'Meld played.');
    });

    test('picked up discard must be included in the meld play', () {
      final played = meld([
        card(CardRank.ten, CardSuit.clubs),
        card(CardRank.ten, CardSuit.diamonds),
        card(CardRank.ten, CardSuit.hearts),
      ]);
      final pendingDiscard = card(CardRank.two, CardSuit.spades);

      final result = ClassicHareegMeldPlayEligibilityPlanner.evaluate(
        openingState: OpeningState.initial(51),
        seat: PlayerSeat.south,
        stagedOpeningMelds: const [],
        playedMelds: [played],
        handCount: 7,
        playedCardIds: idsOf(played.cards),
        pendingDiscardId: pendingDiscard.id,
      );

      expect(
        result.scenario,
        ClassicHareegMeldPlayScenario.missingPendingDiscard,
      );
      expect(result.isAllowed, isFalse);
      expect(result.shouldAdvertise, isFalse);
      expect(result.message, contains('picked up discard'));
    });

    test('meld plays cannot consume the final discard card', () {
      final played = meld([
        card(CardRank.ten, CardSuit.clubs),
        card(CardRank.ten, CardSuit.diamonds),
        card(CardRank.ten, CardSuit.hearts),
      ]);

      final result = ClassicHareegMeldPlayEligibilityPlanner.evaluate(
        openingState: OpeningState.initial(51),
        seat: PlayerSeat.south,
        stagedOpeningMelds: const [],
        playedMelds: [played],
        handCount: 3,
        playedCardIds: idsOf(played.cards),
      );

      expect(result.scenario, ClassicHareegMeldPlayScenario.noFinalDiscard);
      expect(result.isAllowed, isFalse);
      expect(result.shouldAdvertise, isFalse);
      expect(result.message, contains('final discard'));
    });

    test('opening-complete plays are allowed and advertised', () {
      final tenSet = meld([
        card(CardRank.ten, CardSuit.clubs),
        card(CardRank.ten, CardSuit.diamonds),
        card(CardRank.ten, CardSuit.hearts),
      ]);
      final nineSet = meld([
        card(CardRank.nine, CardSuit.clubs),
        card(CardRank.nine, CardSuit.diamonds),
        card(CardRank.nine, CardSuit.hearts),
      ]);
      final cards = [...tenSet.cards, ...nineSet.cards];

      final result = ClassicHareegMeldPlayEligibilityPlanner.evaluate(
        openingState: OpeningState.initial(51),
        seat: PlayerSeat.south,
        stagedOpeningMelds: const [],
        playedMelds: [tenSet, nineSet],
        handCount: 7,
        playedCardIds: idsOf(cards),
      );

      expect(result.scenario, ClassicHareegMeldPlayScenario.openingComplete);
      expect(result.isAllowed, isTrue);
      expect(result.shouldAdvertise, isTrue);
      expect(result.opensPlayer, isTrue);
      expect(result.leavesFinalDiscard, isTrue);
      expect(result.opening?.value, 57);
      expect(result.message, contains('Opened at 57'));
    });

    test(
      'partial opening melds can be applied but stay hidden from legal ids',
      () {
        final tenSet = meld([
          card(CardRank.ten, CardSuit.clubs),
          card(CardRank.ten, CardSuit.diamonds),
          card(CardRank.ten, CardSuit.hearts),
        ]);

        final result = ClassicHareegMeldPlayEligibilityPlanner.evaluate(
          openingState: OpeningState.initial(51),
          seat: PlayerSeat.south,
          stagedOpeningMelds: const [],
          playedMelds: [tenSet],
          handCount: 8,
          playedCardIds: idsOf(tenSet.cards),
        );

        expect(result.scenario, ClassicHareegMeldPlayScenario.openingPartial);
        expect(result.isAllowed, isTrue);
        expect(result.shouldAdvertise, isFalse);
        expect(result.opensPlayer, isFalse);
        expect(result.message, contains('Opening 30/51'));
        expect(result.message, contains('Add more melds'));
      },
    );

    test('below-requirement finish candidates are allowed and advertised', () {
      final tenSet = meld([
        card(CardRank.ten, CardSuit.clubs),
        card(CardRank.ten, CardSuit.diamonds),
        card(CardRank.ten, CardSuit.hearts),
      ]);

      final result = ClassicHareegMeldPlayEligibilityPlanner.evaluate(
        openingState: OpeningState.initial(51),
        seat: PlayerSeat.south,
        stagedOpeningMelds: const [],
        playedMelds: [tenSet],
        handCount: 4,
        playedCardIds: idsOf(tenSet.cards),
      );

      expect(
        result.scenario,
        ClassicHareegMeldPlayScenario.openingFinishCandidate,
      );
      expect(result.isAllowed, isTrue);
      expect(result.shouldAdvertise, isTrue);
      expect(result.opensPlayer, isFalse);
      expect(result.leavesFinalDiscard, isTrue);
      expect(result.message, contains('Discard to finish'));
    });
  });
}

PlacedMeld meld(List<HareegCard> cards) {
  return PlacedMeld.fromCards(cards);
}

Set<String> idsOf(Iterable<HareegCard> cards) {
  return cards.map((card) => card.id).toSet();
}

HareegCard card(CardRank rank, CardSuit suit) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: 1);
}
