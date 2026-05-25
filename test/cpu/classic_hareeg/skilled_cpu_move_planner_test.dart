import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_observation.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_strategy.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_discard_history.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

void main() {
  group('Skilled CPU routing', () {
    test('prefers split short melds while Casual keeps priority order', () {
      final run = [
        card(CardRank.five, CardSuit.clubs),
        card(CardRank.six, CardSuit.clubs),
        card(CardRank.seven, CardSuit.clubs),
        card(CardRank.eight, CardSuit.clubs),
        card(CardRank.nine, CardSuit.clubs),
        card(CardRank.ten, CardSuit.clubs),
        card(CardRank.jack, CardSuit.clubs),
      ];
      final leftovers = [
        card(CardRank.two, CardSuit.spades),
        card(CardRank.three, CardSuit.spades),
      ];
      final fullRunAction = ClassicHareegActionIds.playMeldActionId(
        run.map((card) => card.id),
      );
      final shortRunAction = ClassicHareegActionIds.playMeldActionId(
        run.take(3).map((card) => card.id),
      );
      const strategy = ClassicHareegCpuStrategy();

      final casual = strategy.chooseMove(
        CpuTurnSnapshot(
          seat: PlayerSeat.east,
          difficulty: CpuDifficulty.casual,
          legalActionIds: [fullRunAction],
        ),
      );
      final skilled = strategy.chooseMove(
        CpuTurnSnapshot(
          seat: PlayerSeat.east,
          difficulty: CpuDifficulty.skilled,
          legalActionIds: [fullRunAction],
        ),
        observation: _FakeCpuObservation(
          legalActionIds: [fullRunAction],
          ownHand: [...run, ...leftovers],
          openingState: _opened(),
          partitions: _FakeMeldPartitionView([
            partition([run], remaining: leftovers),
            partition([
              run.take(3).toList(),
              run.skip(3).toList(),
            ], remaining: leftovers),
          ]),
        ),
      );

      expect(casual.actionId, fullRunAction);
      expect(skilled.actionId, shortRunAction);
    });

    test('avoids discarding ranks recently picked up by opponents', () {
      final nineClubs = card(CardRank.nine, CardSuit.clubs);
      final fourDiamonds = card(CardRank.four, CardSuit.diamonds);
      final discardNine = discardAction(nineClubs);
      final discardFour = discardAction(fourDiamonds);
      final history = DiscardHistory()
        ..recordPickup(PlayerSeat.west, card(CardRank.nine, CardSuit.hearts));
      const strategy = ClassicHareegCpuStrategy();

      final casual = strategy.chooseMove(
        CpuTurnSnapshot(
          seat: PlayerSeat.east,
          difficulty: CpuDifficulty.casual,
          legalActionIds: [discardNine, discardFour],
        ),
      );
      final skilled = strategy.chooseMove(
        CpuTurnSnapshot(
          seat: PlayerSeat.east,
          difficulty: CpuDifficulty.skilled,
          legalActionIds: [discardNine, discardFour],
        ),
        observation: _FakeCpuObservation(
          legalActionIds: [discardNine, discardFour],
          ownHand: [nineClubs, fourDiamonds],
          discardHistory: history,
          openingState: _opened(),
        ),
      );

      expect(casual.actionId, discardNine);
      expect(skilled.actionId, discardFour);
    });

    test('returns a pending discard when no partition uses it', () {
      final pending = card(CardRank.five, CardSuit.clubs);
      final unrelatedMeld = [
        card(CardRank.seven, CardSuit.diamonds),
        card(CardRank.eight, CardSuit.diamonds),
        card(CardRank.nine, CardSuit.diamonds),
      ];
      final unrelatedMeldAction = ClassicHareegActionIds.playMeldActionId(
        unrelatedMeld.map((card) => card.id),
      );
      const strategy = ClassicHareegCpuStrategy();

      final skilled = strategy.chooseMove(
        CpuTurnSnapshot(
          seat: PlayerSeat.east,
          difficulty: CpuDifficulty.skilled,
          legalActionIds: [
            unrelatedMeldAction,
            ClassicHareegActionIds.returnPendingDiscard,
          ],
        ),
        observation: _FakeCpuObservation(
          legalActionIds: [
            unrelatedMeldAction,
            ClassicHareegActionIds.returnPendingDiscard,
          ],
          pendingDiscard: pending,
          ownHand: [
            pending,
            ...unrelatedMeld,
            card(CardRank.two, CardSuit.clubs),
          ],
          openingState: _opened(),
        ),
      );

      expect(skilled.actionId, ClassicHareegActionIds.returnPendingDiscard);
    });

    test(
      'draws stock when an unopened seat cannot use the discard for opening',
      () {
        // Regression: a pre-opening CPU used to take a low-value discard,
        // discover the only partition using it failed the opening floor, get
        // forced into return-pending-discard, then loop on the same discard.
        // _shouldTakeDiscard must respect the opening requirement when the
        // seat hasn't opened.
        final twoSpades = card(CardRank.two, CardSuit.spades);
        final twoHearts = card(CardRank.two, CardSuit.hearts);
        final twoDiamonds = card(CardRank.two, CardSuit.diamonds);
        const strategy = ClassicHareegCpuStrategy();

        final skilled = strategy.chooseMove(
          CpuTurnSnapshot(
            seat: PlayerSeat.east,
            difficulty: CpuDifficulty.skilled,
            legalActionIds: const [
              ClassicHareegActionIds.takeDiscard,
              ClassicHareegActionIds.drawStock,
            ],
          ),
          observation: _FakeCpuObservation(
            legalActionIds: const [
              ClassicHareegActionIds.takeDiscard,
              ClassicHareegActionIds.drawStock,
            ],
            turnPhase: TurnPhase.draw,
            topDiscard: twoSpades,
            ownHand: [
              twoHearts,
              twoDiamonds,
              card(CardRank.four, CardSuit.hearts),
              card(CardRank.nine, CardSuit.hearts),
              card(CardRank.seven, CardSuit.hearts),
              card(CardRank.five, CardSuit.spades),
              card(CardRank.ten, CardSuit.spades),
              card(CardRank.king, CardSuit.hearts),
              card(CardRank.six, CardSuit.diamonds),
              card(CardRank.queen, CardSuit.spades),
              card(CardRank.three, CardSuit.clubs),
              card(CardRank.four, CardSuit.clubs),
              card(CardRank.eight, CardSuit.diamonds),
              card(CardRank.jack, CardSuit.spades),
            ],
            openingState: const OpeningState(
              baseRequirement: 51,
              currentRequirement: 51,
              openedSeats: {},
            ),
            stockCount: 40,
          ),
        );

        expect(skilled.actionId, ClassicHareegActionIds.drawStock);
      },
    );

    test('takes the discard when it immediately improves a partition', () {
      final sevenClubs = card(CardRank.seven, CardSuit.clubs);
      final eightClubs = card(CardRank.eight, CardSuit.clubs);
      final nineClubs = card(CardRank.nine, CardSuit.clubs);
      const strategy = ClassicHareegCpuStrategy();

      final casual = strategy.chooseMove(
        CpuTurnSnapshot(
          seat: PlayerSeat.east,
          difficulty: CpuDifficulty.casual,
          legalActionIds: [
            ClassicHareegActionIds.takeDiscard,
            ClassicHareegActionIds.drawStock,
          ],
        ),
      );
      final skilled = strategy.chooseMove(
        CpuTurnSnapshot(
          seat: PlayerSeat.east,
          difficulty: CpuDifficulty.skilled,
          legalActionIds: [
            ClassicHareegActionIds.takeDiscard,
            ClassicHareegActionIds.drawStock,
          ],
        ),
        observation: _FakeCpuObservation(
          legalActionIds: [
            ClassicHareegActionIds.takeDiscard,
            ClassicHareegActionIds.drawStock,
          ],
          turnPhase: TurnPhase.draw,
          topDiscard: nineClubs,
          ownHand: [
            sevenClubs,
            eightClubs,
            card(CardRank.two, CardSuit.diamonds),
          ],
          openingState: _opened(),
        ),
      );

      expect(casual.actionId, ClassicHareegActionIds.drawStock);
      expect(skilled.actionId, ClassicHareegActionIds.takeDiscard);
    });

    test('holds a normal finish for a plausible Fifty setup', () {
      final firstMeld = [
        card(CardRank.seven, CardSuit.clubs),
        card(CardRank.eight, CardSuit.clubs),
        card(CardRank.nine, CardSuit.clubs),
      ];
      final secondMeld = [
        card(CardRank.ten, CardSuit.hearts),
        card(CardRank.jack, CardSuit.hearts),
        card(CardRank.queen, CardSuit.hearts),
      ];
      final finalDiscard = card(CardRank.king, CardSuit.diamonds);
      final finish = partition(
        [firstMeld, secondMeld],
        remaining: [finalDiscard],
      );
      final finishAction = ClassicHareegActionIds.playMeldActionId(
        [...firstMeld, ...secondMeld].map((card) => card.id),
      );
      final discardFinal = discardAction(finalDiscard);
      final history = DiscardHistory()
        ..recordDiscard(PlayerSeat.south, card(CardRank.four, CardSuit.clubs));
      const strategy = ClassicHareegCpuStrategy();

      final skilled = strategy.chooseMove(
        CpuTurnSnapshot(
          seat: PlayerSeat.east,
          difficulty: CpuDifficulty.skilled,
          legalActionIds: [finishAction, discardFinal],
        ),
        observation: _FakeCpuObservation(
          legalActionIds: [finishAction, discardFinal],
          ownHand: [...firstMeld, ...secondMeld, finalDiscard],
          stockCount: 20,
          openingState: _opened(),
          discardHistory: history,
          partitions: _FakeMeldPartitionView([finish]),
          finishingPartition: finish,
        ),
      );

      expect(skilled.actionId, discardFinal);
    });

    test('near elimination finishes instead of holding for Fifty', () {
      final firstMeld = [
        card(CardRank.seven, CardSuit.clubs),
        card(CardRank.eight, CardSuit.clubs),
        card(CardRank.nine, CardSuit.clubs),
      ];
      final secondMeld = [
        card(CardRank.ten, CardSuit.hearts),
        card(CardRank.jack, CardSuit.hearts),
        card(CardRank.queen, CardSuit.hearts),
      ];
      final finalDiscard = card(CardRank.king, CardSuit.diamonds);
      final finish = partition(
        [firstMeld, secondMeld],
        remaining: [finalDiscard],
      );
      final finishAction = ClassicHareegActionIds.playMeldActionId(
        [...firstMeld, ...secondMeld].map((card) => card.id),
      );
      final history = DiscardHistory()
        ..recordDiscard(PlayerSeat.south, card(CardRank.four, CardSuit.clubs));
      const strategy = ClassicHareegCpuStrategy();

      final skilled = strategy.chooseMove(
        CpuTurnSnapshot(
          seat: PlayerSeat.east,
          difficulty: CpuDifficulty.skilled,
          legalActionIds: [finishAction, discardAction(finalDiscard)],
        ),
        observation: _FakeCpuObservation(
          legalActionIds: [finishAction, discardAction(finalDiscard)],
          ownHand: [...firstMeld, ...secondMeld, finalDiscard],
          ownScore: 25,
          stockCount: 20,
          openingState: _opened(),
          discardHistory: history,
          partitions: _FakeMeldPartitionView([finish]),
          finishingPartition: finish,
        ),
      );

      expect(skilled.actionId, finishAction);
    });

    test('min-opens instead of taking the fattest opening partition', () {
      final lowOpen = [
        card(CardRank.jack, CardSuit.hearts),
        card(CardRank.queen, CardSuit.hearts),
        card(CardRank.king, CardSuit.hearts),
      ];
      final fatOpen = [
        card(CardRank.nine, CardSuit.clubs),
        card(CardRank.ten, CardSuit.clubs),
        card(CardRank.jack, CardSuit.clubs),
        card(CardRank.queen, CardSuit.clubs),
      ];
      final leftovers = [card(CardRank.two, CardSuit.spades)];
      final fatAction = ClassicHareegActionIds.playMeldActionId(
        fatOpen.map((card) => card.id),
      );
      final lowAction = ClassicHareegActionIds.playMeldActionId(
        lowOpen.map((card) => card.id),
      );
      const strategy = ClassicHareegCpuStrategy();

      final skilled = strategy.chooseMove(
        CpuTurnSnapshot(
          seat: PlayerSeat.east,
          difficulty: CpuDifficulty.skilled,
          legalActionIds: [fatAction, lowAction],
        ),
        observation: _FakeCpuObservation(
          legalActionIds: [fatAction, lowAction],
          ownHand: [...fatOpen, ...lowOpen, ...leftovers],
          openingState: OpeningState.initial(30),
          partitions: _FakeMeldPartitionView([
            partition([fatOpen], remaining: [...lowOpen, ...leftovers]),
            partition([lowOpen], remaining: [...fatOpen, ...leftovers]),
          ]),
        ),
      );

      expect(skilled.actionId, lowAction);
    });
  });
}

HareegCard card(CardRank rank, CardSuit suit) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: 1);
}

String discardAction(HareegCard card) {
  return '${ClassicHareegActionIds.discardPrefix}${card.id}';
}

OpeningState _opened() {
  return OpeningState(
    baseRequirement: 30,
    currentRequirement: 30,
    openedSeats: const {PlayerSeat.east},
  );
}

MeldPartition partition(
  List<List<HareegCard>> melds, {
  List<HareegCard> remaining = const [],
}) {
  final placed = melds.map(PlacedMeld.fromCards).toList(growable: false);
  return MeldPartition(
    melds: placed,
    cardsUsed: placed.expand((meld) => meld.cards),
    cardsRemaining: remaining,
    jokerAssignments: const [],
  );
}

final class _FakeMeldPartitionView implements MeldPartitionView {
  const _FakeMeldPartitionView(this.partitions);

  final List<MeldPartition> partitions;

  @override
  Iterable<MeldPartition> enumerate({
    bool includePendingDiscard = true,
    int maxPartitions = 32,
    int minMelds = 1,
    int maxMelds = 5,
    String? mustUseCardId,
    int? minTotalValue,
  }) {
    return partitions
        .where((partition) => partition.meldCount >= minMelds)
        .where((partition) => partition.meldCount <= maxMelds)
        .where(
          (partition) =>
              mustUseCardId == null || partition.usesCardId(mustUseCardId),
        )
        .where(
          (partition) =>
              minTotalValue == null || partition.totalValue >= minTotalValue,
        )
        .take(maxPartitions);
  }
}

typedef _FakeCpuObservation = CpuObservationFacts;
