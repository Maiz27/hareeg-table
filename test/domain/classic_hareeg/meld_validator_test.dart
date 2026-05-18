import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/meld_validator.dart';

void main() {
  group('ClassicHareegMeldValidator', () {
    test('accepts same-rank sets with different suits', () {
      final result = ClassicHareegMeldValidator.validate([
        card(CardRank.nine, CardSuit.clubs),
        card(CardRank.nine, CardSuit.diamonds),
        card(CardRank.nine, CardSuit.hearts),
      ]);

      expect(result.isValid, isTrue);
      expect(result.type, MeldType.set);
      expect(result.value, 27);
    });

    test('rejects duplicate visual cards inside a set', () {
      final result = ClassicHareegMeldValidator.validate([
        card(CardRank.nine, CardSuit.clubs),
        card(CardRank.nine, CardSuit.clubs, deckIndex: 1),
        card(CardRank.nine, CardSuit.hearts),
      ]);

      expect(result.isValid, isFalse);
      expect(result.message, contains('duplicate visual cards'));
    });

    test('accepts same-suit sequences', () {
      final result = ClassicHareegMeldValidator.validate([
        card(CardRank.six, CardSuit.clubs),
        card(CardRank.seven, CardSuit.clubs),
        card(CardRank.eight, CardSuit.clubs),
      ]);

      expect(result.isValid, isTrue);
      expect(result.type, MeldType.sequence);
      expect(result.value, 21);
    });

    test('rejects duplicate visual cards inside a sequence', () {
      final result = ClassicHareegMeldValidator.validate([
        card(CardRank.six, CardSuit.clubs),
        card(CardRank.seven, CardSuit.clubs),
        card(CardRank.seven, CardSuit.clubs, deckIndex: 1),
        card(CardRank.eight, CardSuit.clubs),
      ]);

      expect(result.isValid, isFalse);
      expect(result.message, contains('duplicate visual cards'));
    });

    test('allows duplicate visual cards in separate meld validations', () {
      final first = ClassicHareegMeldValidator.validate([
        card(CardRank.nine, CardSuit.clubs),
        card(CardRank.nine, CardSuit.diamonds),
        card(CardRank.nine, CardSuit.hearts),
      ]);
      final second = ClassicHareegMeldValidator.validate([
        card(CardRank.nine, CardSuit.clubs, deckIndex: 1),
        card(CardRank.ten, CardSuit.clubs),
        card(CardRank.jack, CardSuit.clubs),
      ]);

      expect(first.isValid, isTrue);
      expect(second.isValid, isTrue);
    });

    test('accepts low ace sequences with documented values', () {
      final aceTwoThree = ClassicHareegMeldValidator.validate([
        card(CardRank.ace, CardSuit.spades),
        card(CardRank.two, CardSuit.spades),
        card(CardRank.three, CardSuit.spades),
      ]);
      final aceToFour = ClassicHareegMeldValidator.validate([
        card(CardRank.ace, CardSuit.spades),
        card(CardRank.two, CardSuit.spades),
        card(CardRank.three, CardSuit.spades),
        card(CardRank.four, CardSuit.spades),
      ]);
      final aceToFive = ClassicHareegMeldValidator.validate([
        card(CardRank.ace, CardSuit.spades),
        card(CardRank.two, CardSuit.spades),
        card(CardRank.three, CardSuit.spades),
        card(CardRank.four, CardSuit.spades),
        card(CardRank.five, CardSuit.spades),
      ]);

      expect(aceTwoThree.value, 15);
      expect(aceToFour.value, 19);
      expect(aceToFive.value, 15);
    });

    test('accepts high ace sequences and rejects wraparound', () {
      final highAce = ClassicHareegMeldValidator.validate([
        card(CardRank.queen, CardSuit.hearts),
        card(CardRank.king, CardSuit.hearts),
        card(CardRank.ace, CardSuit.hearts),
      ]);
      final wrap = ClassicHareegMeldValidator.validate([
        card(CardRank.king, CardSuit.hearts),
        card(CardRank.ace, CardSuit.hearts),
        card(CardRank.two, CardSuit.hearts),
      ]);

      expect(highAce.isValid, isTrue);
      expect(highAce.value, 30);
      expect(wrap.isValid, isFalse);
    });
  });
}

HareegCard card(CardRank rank, CardSuit suit, {int deckIndex = 0}) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
