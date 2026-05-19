import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/finish_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

void main() {
  group('ClassicHareegFinishRules', () {
    test('rejects finishing without a final discard', () {
      final result = ClassicHareegFinishRules.validateFinish(
        playedMelds: [sequence()],
        finalDiscard: null,
        playerOpened: true,
        source: FinishCardSource.stock,
      );

      expect(result.isValid, isFalse);
      expect(result.message, contains('final discard'));
    });

    test('valid finish resolves to played cards plus one final discard', () {
      final discard = card(CardRank.two, CardSuit.hearts);
      final result = ClassicHareegFinishRules.validateFinish(
        playedMelds: [sequence()],
        finalDiscard: discard,
        playerOpened: true,
        source: FinishCardSource.stock,
      );

      expect(result.isValid, isTrue);
      expect(result.playedCards.length, 3);
      expect(result.finalDiscard, discard);
    });

    test('final discard may be a cover card or joker', () {
      final cover = ClassicHareegFinishRules.validateFinish(
        playedMelds: [sequence()],
        finalDiscard: card(CardRank.nine, CardSuit.clubs),
        playerOpened: true,
        source: FinishCardSource.stock,
      );
      final joker = ClassicHareegFinishRules.validateFinish(
        playedMelds: [sequence()],
        finalDiscard: HareegCard.joker(deckIndex: 0, jokerIndex: 0),
        playerOpened: true,
        source: FinishCardSource.stock,
      );

      expect(cover.isValid, isTrue);
      expect(joker.isValid, isTrue);
    });

    test('perfect hand finish can bypass opening requirement', () {
      final result = ClassicHareegFinishRules.validateFinish(
        playedMelds: [sequence()],
        finalDiscard: card(CardRank.two, CardSuit.hearts),
        playerOpened: false,
        source: FinishCardSource.stock,
        perfectHandAttempt: true,
      );

      expect(result.isValid, isTrue);
      expect(result.perfectHandBypass, isTrue);
      expect(result.source, FinishCardSource.stock);
    });

    test('stock exhaustion does not recycle discard pile', () {
      final draw = ClassicHareegFinishRules.evaluateStockExhaustion(
        stockIsEmpty: true,
        previousDiscardCanFinish: false,
        pickupWouldFinish: false,
      );
      final finishOnly = ClassicHareegFinishRules.evaluateStockExhaustion(
        stockIsEmpty: true,
        previousDiscardCanFinish: true,
        pickupWouldFinish: true,
      );
      final nonFinishingPickup =
          ClassicHareegFinishRules.evaluateStockExhaustion(
            stockIsEmpty: true,
            previousDiscardCanFinish: true,
            pickupWouldFinish: false,
          );

      expect(draw.decision, StockExhaustionDecision.roundDraw);
      expect(finishOnly.decision, StockExhaustionDecision.finishOnly);
      expect(nonFinishingPickup.decision, StockExhaustionDecision.roundDraw);
    });
  });
}

PlacedMeld sequence() {
  return PlacedMeld.fromCards([
    card(CardRank.six, CardSuit.clubs),
    card(CardRank.seven, CardSuit.clubs),
    card(CardRank.eight, CardSuit.clubs),
  ]);
}

HareegCard card(CardRank rank, CardSuit suit) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: 0);
}
