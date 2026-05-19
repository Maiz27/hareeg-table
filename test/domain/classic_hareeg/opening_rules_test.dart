import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

void main() {
  group('ClassicHareegOpeningRules', () {
    test('validates opening value against the current requirement', () {
      final state = OpeningState.initial(51);
      final low = [
        meld([nines(0), nines(1), nines(2)]),
      ];
      final high = [
        meld([
          card(CardRank.ten, CardSuit.clubs),
          card(CardRank.jack, CardSuit.clubs),
          card(CardRank.queen, CardSuit.clubs),
          card(CardRank.king, CardSuit.clubs),
          card(CardRank.ace, CardSuit.clubs),
        ]),
        meld([
          card(CardRank.nine, CardSuit.clubs),
          card(CardRank.nine, CardSuit.diamonds),
          card(CardRank.nine, CardSuit.hearts),
        ]),
      ];

      expect(
        ClassicHareegOpeningRules.validateOpening(
          state: state,
          seat: PlayerSeat.south,
          melds: low,
        ).isValid,
        isFalse,
      );
      expect(
        ClassicHareegOpeningRules.validateOpening(
          state: state,
          seat: PlayerSeat.south,
          melds: high,
        ).isValid,
        isTrue,
      );
    });

    test('supports custom opening requirements such as 75', () {
      final state = OpeningState.initial(75);
      final low = [
        meld([
          card(CardRank.ten, CardSuit.clubs),
          card(CardRank.jack, CardSuit.clubs),
          card(CardRank.queen, CardSuit.clubs),
          card(CardRank.king, CardSuit.clubs),
          card(CardRank.ace, CardSuit.clubs),
        ]),
      ];
      final high = [
        meld([
          card(CardRank.ten, CardSuit.clubs),
          card(CardRank.jack, CardSuit.clubs),
          card(CardRank.queen, CardSuit.clubs),
          card(CardRank.king, CardSuit.clubs),
          card(CardRank.ace, CardSuit.clubs),
        ]),
        meld([
          card(CardRank.ten, CardSuit.diamonds),
          card(CardRank.jack, CardSuit.diamonds),
          card(CardRank.queen, CardSuit.diamonds),
        ]),
      ];

      final result = ClassicHareegOpeningRules.validateOpening(
        state: state,
        seat: PlayerSeat.south,
        melds: low,
      );
      final highResult = ClassicHareegOpeningRules.validateOpening(
        state: state,
        seat: PlayerSeat.south,
        melds: high,
      );

      expect(result.isValid, isFalse);
      expect(result.value, 50);
      expect(highResult.isValid, isTrue);
      expect(highResult.value, 80);
    });

    test('rejects covers as opening contribution', () {
      final state = OpeningState.initial(51);
      final result = ClassicHareegOpeningRules.validateOpening(
        state: state,
        seat: PlayerSeat.south,
        melds: [PlacedMeld(cards: const [], valueSnapshot: 51)],
        containsCovers: true,
      );

      expect(result.isValid, isFalse);
      expect(result.message, contains('Covers cannot'));
    });

    test('first opener owns benchmark and can raise it until lock', () {
      final firstOpening = [PlacedMeld(cards: const [], valueSnapshot: 60)];
      var state = ClassicHareegOpeningRules.applyOpening(
        state: OpeningState.initial(51),
        seat: PlayerSeat.south,
        melds: firstOpening,
      );

      expect(state.benchmarkOwner, PlayerSeat.south);
      expect(state.currentRequirement, 60);
      expect(state.isLocked, isFalse);

      state = ClassicHareegOpeningRules.recordBenchmarkContribution(
        state: state,
        seat: PlayerSeat.south,
        value: 10,
      );

      expect(state.currentRequirement, 70);

      state = ClassicHareegOpeningRules.applyOpening(
        state: state,
        seat: PlayerSeat.east,
        melds: [PlacedMeld(cards: const [], valueSnapshot: 70)],
      );

      expect(state.isLocked, isTrue);

      final afterLock = ClassicHareegOpeningRules.recordBenchmarkContribution(
        state: state,
        seat: PlayerSeat.south,
        value: 10,
      );

      expect(afterLock.currentRequirement, 70);
    });

    test('non-owner and later players cannot raise benchmark', () {
      final state = ClassicHareegOpeningRules.applyOpening(
        state: OpeningState.initial(51),
        seat: PlayerSeat.south,
        melds: [PlacedMeld(cards: const [], valueSnapshot: 60)],
      );

      final unchanged = ClassicHareegOpeningRules.recordBenchmarkContribution(
        state: state,
        seat: PlayerSeat.east,
        value: 10,
      );

      expect(unchanged.currentRequirement, 60);
    });

    test('ace value snapshot does not retroactively change after cover', () {
      final original = meld([
        card(CardRank.ace, CardSuit.spades),
        card(CardRank.two, CardSuit.spades),
        card(CardRank.three, CardSuit.spades),
        card(CardRank.four, CardSuit.spades),
      ]);
      final covered = original.addCoverValue(5);
      final replayedWithFive = meld([
        card(CardRank.ace, CardSuit.spades),
        card(CardRank.two, CardSuit.spades),
        card(CardRank.three, CardSuit.spades),
        card(CardRank.four, CardSuit.spades),
        card(CardRank.five, CardSuit.spades),
      ]);

      expect(original.valueSnapshot, 19);
      expect(covered.valueSnapshot, 19);
      expect(covered.totalValue, 24);
      expect(replayedWithFive.valueSnapshot, 15);
    });
  });
}

PlacedMeld meld(List<HareegCard> cards) {
  return PlacedMeld.fromCards(cards);
}

HareegCard nines(int suitIndex) {
  return card(CardRank.nine, CardSuit.values[suitIndex]);
}

HareegCard card(CardRank rank, CardSuit suit, {int deckIndex = 0}) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
