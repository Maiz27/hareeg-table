import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/fifty_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

void main() {
  group('ClassicHareegFiftyRules', () {
    test('only immediate next player can claim valid Fifty', () {
      final discarded = card(CardRank.nine, CardSuit.clubs);
      final window = ClassicHareegFiftyRules.openWindow(
        discarder: PlayerSeat.south,
        discardedCard: discarded,
        durationSeconds: 4,
      );

      final valid = ClassicHareegFiftyRules.validateClaim(
        window: window,
        claimant: PlayerSeat.east,
        elapsedSeconds: 3,
        finishingMelds: [
          meld([
            card(CardRank.seven, CardSuit.clubs),
            card(CardRank.eight, CardSuit.clubs),
            discarded,
          ]),
        ],
        finalDiscard: card(CardRank.two, CardSuit.hearts),
      );
      final wrongPlayer = ClassicHareegFiftyRules.validateClaim(
        window: window,
        claimant: PlayerSeat.north,
        elapsedSeconds: 3,
        finishingMelds: [
          meld([
            card(CardRank.seven, CardSuit.clubs),
            card(CardRank.eight, CardSuit.clubs),
            discarded,
          ]),
        ],
        finalDiscard: card(CardRank.two, CardSuit.hearts),
      );

      expect(window.claimant, PlayerSeat.east);
      expect(valid.isValid, isTrue);
      expect(wrongPlayer.isValid, isFalse);
    });

    test('blocking-tier action appears only when valid Fifty exists', () {
      final discarded = card(CardRank.nine, CardSuit.clubs);
      final window = ClassicHareegFiftyRules.openWindow(
        discarder: PlayerSeat.south,
        discardedCard: discarded,
        durationSeconds: 4,
      );

      expect(
        ClassicHareegFiftyRules.shouldShowBlockingTierAction(
          window: window,
          viewer: PlayerSeat.east,
          elapsedSeconds: 1,
          finishingMelds: [
            meld([
              card(CardRank.seven, CardSuit.clubs),
              card(CardRank.eight, CardSuit.clubs),
              discarded,
            ]),
          ],
          finalDiscard: card(CardRank.two, CardSuit.hearts),
        ),
        isTrue,
      );
      expect(
        ClassicHareegFiftyRules.shouldShowBlockingTierAction(
          window: window,
          viewer: PlayerSeat.east,
          elapsedSeconds: 1,
          finishingMelds: [
            meld([
              card(CardRank.seven, CardSuit.hearts),
              card(CardRank.eight, CardSuit.hearts),
              card(CardRank.nine, CardSuit.hearts),
            ]),
          ],
          finalDiscard: card(CardRank.two, CardSuit.hearts),
        ),
        isFalse,
      );
    });

    test('timer expiry blocks Fifty but allows normal pickup', () {
      final discarded = card(CardRank.nine, CardSuit.clubs);
      final window = ClassicHareegFiftyRules.openWindow(
        discarder: PlayerSeat.south,
        discardedCard: discarded,
        durationSeconds: 4,
      );
      final expired = ClassicHareegFiftyRules.validateClaim(
        window: window,
        claimant: PlayerSeat.east,
        elapsedSeconds: 4,
        finishingMelds: [
          meld([
            card(CardRank.seven, CardSuit.clubs),
            card(CardRank.eight, CardSuit.clubs),
            discarded,
          ]),
        ],
        finalDiscard: card(CardRank.two, CardSuit.hearts),
      );

      expect(expired.isValid, isFalse);
      expect(
        ClassicHareegFiftyRules.canTakeNormallyAfterMiss(
          window: window,
          player: PlayerSeat.east,
          elapsedSeconds: 4,
        ),
        isTrue,
      );
    });

    test('discarded card can be used after chained cover setup', () {
      final discarded = card(CardRank.ten, CardSuit.clubs);
      final window = ClassicHareegFiftyRules.openWindow(
        discarder: PlayerSeat.south,
        discardedCard: discarded,
        durationSeconds: 4,
      );
      final result = ClassicHareegFiftyRules.validateClaim(
        window: window,
        claimant: PlayerSeat.east,
        elapsedSeconds: 2,
        finishingMelds: [
          meld([
            card(CardRank.six, CardSuit.clubs),
            card(CardRank.seven, CardSuit.clubs),
            card(CardRank.eight, CardSuit.clubs),
            card(CardRank.nine, CardSuit.clubs),
            discarded,
          ]),
        ],
        finalDiscard: card(CardRank.two, CardSuit.hearts),
      );

      expect(result.isValid, isTrue);
    });

    test('first dealt round exception is represented in claim result', () {
      final discarded = card(CardRank.nine, CardSuit.clubs);
      final window = ClassicHareegFiftyRules.openWindow(
        discarder: PlayerSeat.south,
        discardedCard: discarded,
        durationSeconds: 4,
        isFirstDealtRound: true,
      );
      final result = ClassicHareegFiftyRules.validateClaim(
        window: window,
        claimant: PlayerSeat.east,
        elapsedSeconds: 2,
        finishingMelds: [
          meld([
            card(CardRank.seven, CardSuit.clubs),
            card(CardRank.eight, CardSuit.clubs),
            discarded,
          ]),
        ],
        finalDiscard: card(CardRank.two, CardSuit.hearts),
      );

      expect(result.isValid, isTrue);
      expect(result.firstRoundException, isTrue);
    });
  });
}

PlacedMeld meld(List<HareegCard> cards) {
  return PlacedMeld.fromCards(cards);
}

HareegCard card(CardRank rank, CardSuit suit) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: 0);
}
