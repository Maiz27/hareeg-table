import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/joker_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/meld_validator.dart';

void main() {
  group('ClassicHareegJokerRules', () {
    test('finds represented identity options for sequence placement', () {
      final joker = HareegCard.joker(deckIndex: 0, jokerIndex: 0);
      final options = ClassicHareegJokerRules.representationOptionsForMeld(
        cards: [
          card(CardRank.six, CardSuit.clubs),
          joker,
          card(CardRank.eight, CardSuit.clubs),
        ],
        joker: joker,
      );

      expect(options, [
        const CardIdentity(rank: CardRank.seven, suit: CardSuit.clubs),
      ]);
    });

    test('finds represented identity inside a longer sequence', () {
      final joker = HareegCard.joker(deckIndex: 0, jokerIndex: 0);
      final options = ClassicHareegJokerRules.representationOptionsForMeld(
        cards: [
          card(CardRank.nine, CardSuit.spades),
          card(CardRank.ten, CardSuit.spades),
          joker,
          card(CardRank.queen, CardSuit.spades),
        ],
        joker: joker,
      );

      expect(options, [
        const CardIdentity(rank: CardRank.jack, suit: CardSuit.spades),
      ]);
    });

    test('finds both edge identities for a same-suit face-card sequence', () {
      final joker = HareegCard.joker(deckIndex: 0, jokerIndex: 0);
      final options = ClassicHareegJokerRules.representationOptionsForMeld(
        cards: [
          card(CardRank.jack, CardSuit.hearts),
          card(CardRank.queen, CardSuit.hearts),
          joker,
        ],
        joker: joker,
      );

      expect(options, [
        const CardIdentity(rank: CardRank.ten, suit: CardSuit.hearts),
        const CardIdentity(rank: CardRank.king, suit: CardSuit.hearts),
      ]);
    });

    test('rejects mixed-suit face cards with a joker as a sequence', () {
      final joker = HareegCard.joker(deckIndex: 0, jokerIndex: 0);
      final options = ClassicHareegJokerRules.representationOptionsForMeld(
        cards: [
          card(CardRank.jack, CardSuit.diamonds),
          card(CardRank.queen, CardSuit.hearts),
          joker,
        ],
        joker: joker,
      );

      expect(options, isEmpty);
    });

    test('finds ambiguous represented identity options for set placement', () {
      final joker = HareegCard.joker(deckIndex: 0, jokerIndex: 0);
      final options = ClassicHareegJokerRules.representationOptionsForMeld(
        cards: [
          card(CardRank.seven, CardSuit.clubs),
          joker,
          card(CardRank.seven, CardSuit.diamonds),
        ],
        joker: joker,
      );

      expect(options, [
        const CardIdentity(rank: CardRank.seven, suit: CardSuit.hearts),
        const CardIdentity(rank: CardRank.seven, suit: CardSuit.spades),
      ]);
    });

    test('CPU chooses deterministic represented identity', () {
      final joker = HareegCard.joker(deckIndex: 0, jokerIndex: 0);
      final identity = ClassicHareegJokerRules.deterministicCpuIdentity(
        cards: [
          card(CardRank.seven, CardSuit.clubs),
          joker,
          card(CardRank.seven, CardSuit.diamonds),
        ],
        joker: joker,
      );

      expect(
        identity,
        const CardIdentity(rank: CardRank.seven, suit: CardSuit.hearts),
      );
    });

    test('represented joker validates inside a meld and has visual label', () {
      final representedJoker = HareegCard.joker(
        deckIndex: 0,
        jokerIndex: 0,
        representedIdentity: const CardIdentity(
          rank: CardRank.seven,
          suit: CardSuit.clubs,
        ),
      );
      final result = ClassicHareegMeldValidator.validate([
        card(CardRank.six, CardSuit.clubs),
        representedJoker,
        card(CardRank.eight, CardSuit.clubs),
      ]);

      expect(result.isValid, isTrue);
      expect(representedJoker.label, 'J(7C)');
    });

    test('opened player can replace represented table joker', () {
      final representedJoker = HareegCard.joker(
        deckIndex: 0,
        jokerIndex: 0,
        representedIdentity: const CardIdentity(
          rank: CardRank.seven,
          suit: CardSuit.clubs,
        ),
      );
      final replacement = card(CardRank.seven, CardSuit.clubs, deckIndex: 1);

      final result = ClassicHareegJokerRules.replaceJoker(
        playerOpened: true,
        tableCards: [
          card(CardRank.six, CardSuit.clubs),
          representedJoker,
          card(CardRank.eight, CardSuit.clubs),
        ],
        replacementCard: replacement,
      );

      expect(result.tableCards[1], replacement);
      expect(result.freedJoker.isJoker, isTrue);
      expect(result.freedJoker.representedIdentity, isNull);
    });

    test('unopened player cannot replace joker', () {
      final representedJoker = HareegCard.joker(
        deckIndex: 0,
        jokerIndex: 0,
        representedIdentity: const CardIdentity(
          rank: CardRank.seven,
          suit: CardSuit.clubs,
        ),
      );

      expect(
        ClassicHareegJokerRules.canReplaceJoker(
          playerOpened: false,
          tableCards: [representedJoker],
          replacementCard: card(CardRank.seven, CardSuit.clubs),
        ),
        isFalse,
      );
    });

    test('blocks normal joker discard but allows final joker discard', () {
      final joker = HareegCard.joker(deckIndex: 0, jokerIndex: 0);

      expect(
        ClassicHareegJokerRules.canDiscard(joker, isFinalDiscard: false),
        isFalse,
      );
      expect(
        ClassicHareegJokerRules.canDiscard(joker, isFinalDiscard: true),
        isTrue,
      );
    });
  });
}

HareegCard card(CardRank rank, CardSuit suit, {int deckIndex = 0}) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
