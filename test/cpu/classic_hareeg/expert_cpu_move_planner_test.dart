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
  group('Expert CPU routing', () {
    test('holds a plausible Fifty setup even near own elimination', () {
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
      final observation = _FakeCpuObservation(
        legalActionIds: [finishAction, discardFinal],
        ownHand: [...firstMeld, ...secondMeld, finalDiscard],
        ownScore: 25,
        stockCount: 20,
        openingState: opened(),
        discardHistory: history,
        partitions: _FakeMeldPartitionView([finish]),
        finishingPartition: finish,
      );

      expect(_choose(CpuDifficulty.skilled, observation), finishAction);
      expect(_choose(CpuDifficulty.expert, observation), discardFinal);
    });

    test('extends Fifty hold window for a high-score opponent target', () {
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
      final observation = _FakeCpuObservation(
        legalActionIds: [finishAction, discardFinal],
        ownHand: [...firstMeld, ...secondMeld, finalDiscard],
        stockCount: 9,
        openingState: opened(),
        opponentScores: const {PlayerSeat.west: 28},
        partitions: _FakeMeldPartitionView([finish]),
        finishingPartition: finish,
      );

      expect(_choose(CpuDifficulty.skilled, observation), finishAction);
      expect(_choose(CpuDifficulty.expert, observation), discardFinal);
    });

    test('refuses discard adjacent to a high-score opponent run end', () {
      final nineHearts = card(CardRank.nine, CardSuit.hearts);
      final fourClubs = card(CardRank.four, CardSuit.clubs);
      final westRun = [
        card(CardRank.six, CardSuit.hearts),
        card(CardRank.seven, CardSuit.hearts),
        card(CardRank.eight, CardSuit.hearts),
      ];
      final observation = _FakeCpuObservation(
        legalActionIds: [discardAction(nineHearts), discardAction(fourClubs)],
        ownHand: [nineHearts, fourClubs],
        openingState: opened(),
        opponentScores: const {PlayerSeat.west: 26},
        tableMelds: {
          PlayerSeat.west: [PlacedMeld.fromCards(westRun)],
        },
      );

      expect(
        _choose(CpuDifficulty.skilled, observation),
        discardAction(nineHearts),
      );
      expect(
        _choose(CpuDifficulty.expert, observation),
        discardAction(fourClubs),
      );
    });

    test('uses deeper discard attribution than Skilled hot-list memory', () {
      final nineHearts = card(CardRank.nine, CardSuit.hearts);
      final fourClubs = card(CardRank.four, CardSuit.clubs);
      final history = DiscardHistory()
        ..recordDiscard(PlayerSeat.west, card(CardRank.nine, CardSuit.diamonds))
        ..recordDiscard(PlayerSeat.west, card(CardRank.two, CardSuit.diamonds))
        ..recordDiscard(
          PlayerSeat.west,
          card(CardRank.three, CardSuit.diamonds),
        )
        ..recordDiscard(PlayerSeat.west, card(CardRank.five, CardSuit.spades))
        ..recordDiscard(PlayerSeat.west, card(CardRank.six, CardSuit.spades))
        ..recordDiscard(PlayerSeat.west, card(CardRank.seven, CardSuit.spades));
      final observation = _FakeCpuObservation(
        legalActionIds: [discardAction(nineHearts), discardAction(fourClubs)],
        ownHand: [nineHearts, fourClubs],
        openingState: opened(),
        discardHistory: history,
      );

      expect(
        _choose(CpuDifficulty.skilled, observation),
        discardAction(nineHearts),
      );
      expect(
        _choose(CpuDifficulty.expert, observation),
        discardAction(fourClubs),
      );
    });

    test('takes a thin-stock discard defensively even without a meld', () {
      final kingSpades = card(CardRank.king, CardSuit.spades);
      final observation = _FakeCpuObservation(
        legalActionIds: [
          ClassicHareegActionIds.takeDiscard,
          ClassicHareegActionIds.drawStock,
        ],
        turnPhase: TurnPhase.draw,
        topDiscard: kingSpades,
        ownHand: [
          card(CardRank.two, CardSuit.clubs),
          card(CardRank.four, CardSuit.diamonds),
          card(CardRank.six, CardSuit.hearts),
        ],
        stockCount: 7,
        openingState: opened(),
      );

      expect(
        _choose(CpuDifficulty.skilled, observation),
        ClassicHareegActionIds.drawStock,
      );
      expect(
        _choose(CpuDifficulty.expert, observation),
        ClassicHareegActionIds.takeDiscard,
      );
    });

    test('delays joker replacement until a finish is visible', () {
      final discard = card(CardRank.four, CardSuit.clubs);
      final replacement = ClassicHareegActionIds.replaceJokerActionId(
        targetSeat: PlayerSeat.south,
        meldIndex: 0,
        cardId: card(CardRank.jack, CardSuit.clubs).id,
      );
      final observation = _FakeCpuObservation(
        legalActionIds: [replacement, discardAction(discard)],
        ownHand: [discard],
        openingState: opened(),
      );

      expect(_choose(CpuDifficulty.skilled, observation), replacement);
      expect(
        _choose(CpuDifficulty.expert, observation),
        discardAction(discard),
      );
    });

    test('pushes first opening benchmark into the 70-80 band', () {
      final lowOpen = [
        card(CardRank.jack, CardSuit.hearts),
        card(CardRank.queen, CardSuit.hearts),
        card(CardRank.king, CardSuit.hearts),
      ];
      final fatOpen = [
        card(CardRank.seven, CardSuit.clubs),
        card(CardRank.eight, CardSuit.clubs),
        card(CardRank.nine, CardSuit.clubs),
        card(CardRank.ten, CardSuit.clubs),
        card(CardRank.jack, CardSuit.clubs),
        card(CardRank.queen, CardSuit.clubs),
        card(CardRank.king, CardSuit.clubs),
      ];
      final leftovers = [card(CardRank.two, CardSuit.spades)];
      final lowAction = ClassicHareegActionIds.playMeldActionId(
        lowOpen.map((card) => card.id),
      );
      final fatAction = ClassicHareegActionIds.playMeldActionId(
        fatOpen.map((card) => card.id),
      );
      final observation = _FakeCpuObservation(
        legalActionIds: [lowAction, fatAction],
        ownHand: [...lowOpen, ...fatOpen, ...leftovers],
        stockCount: 40,
        openingState: OpeningState.initial(30),
        partitions: _FakeMeldPartitionView([
          partition([lowOpen], remaining: [...fatOpen, ...leftovers]),
          partition([fatOpen], remaining: [...lowOpen, ...leftovers]),
        ]),
      );

      expect(_choose(CpuDifficulty.skilled, observation), lowAction);
      expect(_choose(CpuDifficulty.expert, observation), fatAction);
    });

    test('prefers interior joker sequence identities', () {
      const joker = HareegCard.joker(deckIndex: 9, jokerIndex: 0);
      final queenHearts = card(CardRank.queen, CardSuit.hearts);
      final kingHearts = card(CardRank.king, CardSuit.hearts);
      final aceHearts = card(CardRank.ace, CardSuit.hearts);
      final leftover = card(CardRank.two, CardSuit.spades);
      const edgeIdentity = CardIdentity(
        rank: CardRank.jack,
        suit: CardSuit.hearts,
      );
      const interiorIdentity = CardIdentity(
        rank: CardRank.king,
        suit: CardSuit.hearts,
      );
      final edgeAssignment = JokerMeldAssignment(
        jokerId: joker.id,
        identity: edgeIdentity,
      );
      final interiorAssignment = JokerMeldAssignment(
        jokerId: joker.id,
        identity: interiorIdentity,
      );
      final edgeAction =
          ClassicHareegActionIds.playMeldWithJokerIdentitiesActionId(
            cardIds: [joker.id, queenHearts.id, kingHearts.id],
            assignments: [edgeAssignment],
          );
      final interiorAction =
          ClassicHareegActionIds.playMeldWithJokerIdentitiesActionId(
            cardIds: [joker.id, queenHearts.id, aceHearts.id],
            assignments: [interiorAssignment],
          );
      final observation = _FakeCpuObservation(
        legalActionIds: [edgeAction, interiorAction],
        ownHand: [joker, queenHearts, kingHearts, aceHearts, leftover],
        openingState: opened(),
        partitions: _FakeMeldPartitionView([
          partitionFromPlaced(
            [
              [joker.asRepresenting(edgeIdentity), queenHearts, kingHearts],
            ],
            remaining: [aceHearts, leftover],
            assignments: [edgeAssignment],
          ),
          partitionFromPlaced(
            [
              [joker.asRepresenting(interiorIdentity), queenHearts, aceHearts],
            ],
            remaining: [kingHearts, leftover],
            assignments: [interiorAssignment],
          ),
        ]),
        discardHistory: DiscardHistory()
          ..recordDiscard(
            PlayerSeat.south,
            card(CardRank.jack, CardSuit.hearts),
          ),
      );

      expect(_choose(CpuDifficulty.skilled, observation), edgeAction);
      expect(_choose(CpuDifficulty.expert, observation), interiorAction);
    });
  });
}

String _choose(CpuDifficulty difficulty, _FakeCpuObservation observation) {
  const strategy = ClassicHareegCpuStrategy();
  return strategy
      .chooseMove(
        CpuTurnSnapshot(
          seat: PlayerSeat.east,
          difficulty: difficulty,
          legalActionIds: observation.legalActionIds,
        ),
        observation: observation,
      )
      .actionId;
}

HareegCard card(CardRank rank, CardSuit suit) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: 1);
}

String discardAction(HareegCard card) {
  return '${ClassicHareegActionIds.discardPrefix}${card.id}';
}

OpeningState opened() {
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
  return partitionFromPlaced(melds, remaining: remaining);
}

MeldPartition partitionFromPlaced(
  List<List<HareegCard>> melds, {
  List<HareegCard> remaining = const [],
  List<JokerMeldAssignment> assignments = const [],
}) {
  final placed = melds.map(PlacedMeld.fromCards).toList(growable: false);
  return MeldPartition(
    melds: placed,
    cardsUsed: placed.expand((meld) => meld.cards),
    cardsRemaining: remaining,
    jokerAssignments: assignments,
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
