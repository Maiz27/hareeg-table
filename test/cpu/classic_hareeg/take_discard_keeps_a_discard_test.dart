import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_move_plan_pipeline.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_observation.dart';
import 'package:hareeg_table/cpu/classic_hareeg/expert_cpu_move_planner.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

HareegCard _card(CardRank rank, CardSuit suit) =>
    HareegCard.standard(rank: rank, suit: suit, deckIndex: 1);

/// A taken discard must be played this turn, and a turn ends on a discard. A
/// CPU may therefore only take the discard when it can keep it: meld it and
/// still hold a card to throw, or lay it on a table meld as a cover.
///
/// Playtest: an opened seat took the human's discard because hand + discard
/// made melds with nothing left over, could not end the turn, returned the
/// card and drew from stock instead — every time that card came round.
void main() {
  group('the shared pickup rule (Casual, Skilled, Expert)', () {
    test('two cards that meld away whole with the pickup: not taken', () {
      final observation = CpuObservationFacts(
        ownHand: [
          _card(CardRank.seven, CardSuit.clubs),
          _card(CardRank.eight, CardSuit.clubs),
        ],
        topDiscard: _card(CardRank.nine, CardSuit.clubs),
        stockCount: 20,
      );
      expect(shouldTakeDiscardForObservationCore(observation), isFalse);
    });

    test('a set closed by the pickup with nothing left over: not taken', () {
      final observation = CpuObservationFacts(
        ownHand: [
          _card(CardRank.queen, CardSuit.hearts),
          _card(CardRank.queen, CardSuit.spades),
        ],
        topDiscard: _card(CardRank.queen, CardSuit.diamonds),
        stockCount: 20,
      );
      expect(shouldTakeDiscardForObservationCore(observation), isFalse);
    });

    test('a hand that could also meld away whole is judged on the split that '
        'keeps a card', () {
      // 7-8-9♣ + K K K uses everything, but 7-8-9♣ alone keeps the kings to
      // throw: the rule weighs every way to meld the pickup, not hand size.
      final observation = CpuObservationFacts(
        ownHand: [
          _card(CardRank.seven, CardSuit.clubs),
          _card(CardRank.eight, CardSuit.clubs),
          _card(CardRank.king, CardSuit.hearts),
          _card(CardRank.king, CardSuit.spades),
          _card(CardRank.king, CardSuit.diamonds),
        ],
        topDiscard: _card(CardRank.nine, CardSuit.clubs),
        stockCount: 20,
      );
      expect(shouldTakeDiscardForObservationCore(observation), isTrue);
    });

    test('an unopened seat whose opening would use every card: not taken', () {
      final observation = CpuObservationFacts(
        ownHand: [
          _card(CardRank.king, CardSuit.hearts),
          _card(CardRank.king, CardSuit.spades),
          _card(CardRank.queen, CardSuit.clubs),
          _card(CardRank.jack, CardSuit.clubs),
        ],
        topDiscard: _card(CardRank.king, CardSuit.diamonds),
        stockCount: 20,
        openingState: const OpeningState(
          baseRequirement: 30,
          currentRequirement: 30,
          openedSeats: {},
        ),
      );
      // K K K (30) opens alone and leaves Q J to keep and throw: taken.
      expect(shouldTakeDiscardForObservationCore(observation), isTrue);

      final tight = CpuObservationFacts(
        ownHand: [
          _card(CardRank.king, CardSuit.hearts),
          _card(CardRank.king, CardSuit.spades),
        ],
        topDiscard: _card(CardRank.king, CardSuit.diamonds),
        stockCount: 20,
        openingState: const OpeningState(
          baseRequirement: 30,
          currentRequirement: 30,
          openedSeats: {},
        ),
      );
      expect(shouldTakeDiscardForObservationCore(tight), isFalse);
    });

    test('the same pickup is taken when a card is left to discard', () {
      final observation = CpuObservationFacts(
        ownHand: [
          _card(CardRank.seven, CardSuit.clubs),
          _card(CardRank.eight, CardSuit.clubs),
          _card(CardRank.king, CardSuit.diamonds),
        ],
        topDiscard: _card(CardRank.nine, CardSuit.clubs),
        stockCount: 20,
      );
      expect(shouldTakeDiscardForObservationCore(observation), isTrue);
    });
  });

  group("Expert's thin-stock pickup", () {
    CpuObservationFacts thinStock({
      Map<PlayerSeat, List<PlacedMeld>> tableMelds = const {},
    }) => CpuObservationFacts(
      difficulty: CpuDifficulty.expert,
      turnPhase: TurnPhase.draw,
      legalActionIds: const [
        ClassicHareegActionIds.drawStock,
        ClassicHareegActionIds.takeDiscard,
      ],
      ownHand: [
        _card(CardRank.two, CardSuit.hearts),
        _card(CardRank.nine, CardSuit.spades),
      ],
      topDiscard: _card(CardRank.five, CardSuit.diamonds),
      tableMelds: tableMelds,
      stockCount: 4,
    );

    test('does not grab a card it cannot play', () {
      expect(
        const ExpertCpuMovePlanner().plan(thinStock()).actionId,
        ClassicHareegActionIds.drawStock,
      );
    });

    test('denies a card it can cover with together with a hand card', () {
      // Table run 3-4-5♥, discard 7♥, 6♥ in hand: 6-7 is a legal two-card
      // cover even though 7♥ alone is not.
      final run = PlacedMeld.fromCards([
        _card(CardRank.three, CardSuit.hearts),
        _card(CardRank.four, CardSuit.hearts),
        _card(CardRank.five, CardSuit.hearts),
      ]);
      final observation = CpuObservationFacts(
        ownHand: [
          _card(CardRank.six, CardSuit.hearts),
          _card(CardRank.queen, CardSuit.spades),
        ],
        topDiscard: _card(CardRank.seven, CardSuit.hearts),
        tableMelds: {
          PlayerSeat.west: [run],
        },
        stockCount: 4,
      );
      expect(canCoverWithTakenDiscard(observation), isTrue);
    });

    test('never counts a cover that would empty the hand', () {
      final run = PlacedMeld.fromCards([
        _card(CardRank.three, CardSuit.hearts),
        _card(CardRank.four, CardSuit.hearts),
        _card(CardRank.five, CardSuit.hearts),
      ]);
      final observation = CpuObservationFacts(
        ownHand: [_card(CardRank.six, CardSuit.hearts)],
        topDiscard: _card(CardRank.seven, CardSuit.hearts),
        tableMelds: {
          PlayerSeat.west: [run],
        },
        stockCount: 4,
      );
      // 6-7♥ covers, but leaves nothing to discard; 7♥ alone does not cover.
      expect(canCoverWithTakenDiscard(observation), isFalse);
    });

    test('still denies a card it can lay as a cover', () {
      final run = PlacedMeld.fromCards([
        _card(CardRank.six, CardSuit.diamonds),
        _card(CardRank.seven, CardSuit.diamonds),
        _card(CardRank.eight, CardSuit.diamonds),
      ]);
      expect(
        canCoverWithTakenDiscard(
          thinStock(
            tableMelds: {
              PlayerSeat.north: [run],
            },
          ),
        ),
        isTrue,
      );
    });
  });
}
