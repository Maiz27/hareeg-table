import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/cover_rules.dart';

void main() {
  group('ClassicHareegCoverRules', () {
    test('detects direct adjacent sequence covers only', () {
      final meld = [
        card(CardRank.six, CardSuit.clubs),
        card(CardRank.seven, CardSuit.clubs),
        card(CardRank.eight, CardSuit.clubs),
      ];

      expect(
        ClassicHareegCoverRules.isCover(
          tableMeld: meld,
          candidate: card(CardRank.five, CardSuit.clubs),
        ),
        isTrue,
      );
      expect(
        ClassicHareegCoverRules.isCover(
          tableMeld: meld,
          candidate: card(CardRank.nine, CardSuit.clubs),
        ),
        isTrue,
      );
      expect(
        ClassicHareegCoverRules.isCover(
          tableMeld: meld,
          candidate: card(CardRank.four, CardSuit.clubs),
        ),
        isFalse,
      );
      expect(
        ClassicHareegCoverRules.isCover(
          tableMeld: meld,
          candidate: card(CardRank.nine, CardSuit.hearts),
        ),
        isFalse,
      );
    });

    test('detects ace as the high-end cover for face-card sequences', () {
      final queenKingJack = [
        card(CardRank.jack, CardSuit.spades),
        card(CardRank.queen, CardSuit.spades),
        card(CardRank.king, CardSuit.spades),
      ];
      final tenToKing = [
        card(CardRank.ten, CardSuit.hearts),
        card(CardRank.jack, CardSuit.hearts),
        card(CardRank.queen, CardSuit.hearts),
        card(CardRank.king, CardSuit.hearts),
      ];

      expect(
        ClassicHareegCoverRules.isCover(
          tableMeld: queenKingJack,
          candidate: card(CardRank.ace, CardSuit.spades),
        ),
        isTrue,
      );
      expect(
        ClassicHareegCoverRules.isCover(
          tableMeld: tenToKing,
          candidate: card(CardRank.ace, CardSuit.hearts),
        ),
        isTrue,
      );
      expect(
        ClassicHareegCoverRules.isCover(
          tableMeld: tenToKing,
          candidate: card(CardRank.ace, CardSuit.clubs),
        ),
        isFalse,
      );
    });

    test('detects missing-suit set covers', () {
      final meld = [
        card(CardRank.nine, CardSuit.clubs),
        card(CardRank.nine, CardSuit.diamonds),
        card(CardRank.nine, CardSuit.hearts),
      ];

      expect(
        ClassicHareegCoverRules.isCover(
          tableMeld: meld,
          candidate: card(CardRank.nine, CardSuit.spades),
        ),
        isTrue,
      );
      expect(
        ClassicHareegCoverRules.isCover(
          tableMeld: meld,
          candidate: card(CardRank.nine, CardSuit.clubs, deckIndex: 1),
        ),
        isFalse,
      );
    });

    test('represented jokers do not make duplicate set suits covers', () {
      const represented = CardIdentity(
        rank: CardRank.jack,
        suit: CardSuit.clubs,
      );
      final meld = [
        const HareegCard.joker(
          deckIndex: 0,
          jokerIndex: 0,
          representedIdentity: represented,
        ),
        card(CardRank.jack, CardSuit.hearts),
        card(CardRank.jack, CardSuit.spades),
      ];

      expect(
        ClassicHareegCoverRules.isCover(
          tableMeld: meld,
          candidate: card(CardRank.jack, CardSuit.diamonds),
        ),
        isTrue,
      );
      expect(
        ClassicHareegCoverRules.isCover(
          tableMeld: meld,
          candidate: card(CardRank.jack, CardSuit.hearts, deckIndex: 1),
        ),
        isFalse,
      );
    });

    test('allows chained covers when each placement unlocks the next', () {
      final meld = [
        card(CardRank.six, CardSuit.clubs),
        card(CardRank.seven, CardSuit.clubs),
        card(CardRank.eight, CardSuit.clubs),
      ];
      final withNine = ClassicHareegCoverRules.placeCover(
        playerOpened: true,
        tableMeld: meld,
        candidate: card(CardRank.nine, CardSuit.clubs),
      );
      final withTen = ClassicHareegCoverRules.placeCover(
        playerOpened: true,
        tableMeld: withNine,
        candidate: card(CardRank.ten, CardSuit.clubs),
      );

      expect(withNine.map((card) => card.label), contains('9C'));
      expect(withTen.map((card) => card.label), contains('10C'));
    });

    test('unopened players cannot play covers', () {
      final meld = [
        card(CardRank.six, CardSuit.clubs),
        card(CardRank.seven, CardSuit.clubs),
        card(CardRank.eight, CardSuit.clubs),
      ];

      expect(
        () => ClassicHareegCoverRules.placeCover(
          playerOpened: false,
          tableMeld: meld,
          candidate: card(CardRank.nine, CardSuit.clubs),
        ),
        throwsStateError,
      );
    });

    test('blocks normal cover discard with clear feedback', () {
      final meld = [
        card(CardRank.six, CardSuit.clubs),
        card(CardRank.seven, CardSuit.clubs),
        card(CardRank.eight, CardSuit.clubs),
      ];
      final result = ClassicHareegCoverRules.canDiscard(
        tableMelds: [meld],
        candidate: card(CardRank.nine, CardSuit.clubs),
        isFinalDiscard: false,
      );
      final finalDiscard = ClassicHareegCoverRules.canDiscard(
        tableMelds: [meld],
        candidate: card(CardRank.nine, CardSuit.clubs),
        isFinalDiscard: true,
      );

      expect(result.canDiscard, isFalse);
      expect(result.message, contains('cover'));
      expect(finalDiscard.canDiscard, isTrue);
    });
  });
}

HareegCard card(CardRank rank, CardSuit suit, {int deckIndex = 0}) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
