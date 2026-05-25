import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_observation.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';

void main() {
  group('LiveCpuObservation', () {
    test('delegates visible controller state without mutating it', () {
      final setup = ClassicHareegSetup.defaults().copyWith(
        cpuDifficulty: CpuDifficulty.skilled,
      );
      final controller = _controllerForCpuDrawTurn(setup: setup);
      final legalActionIds = [
        ClassicHareegActionIds.drawStock,
        ClassicHareegActionIds.takeDiscard,
      ];

      final observation = LiveCpuObservation(
        controller: controller,
        seat: PlayerSeat.east,
        legalActionIds: legalActionIds,
        difficulty: setup.cpuDifficulty,
      );
      legalActionIds.add('late-action');

      expect(observation.seat, PlayerSeat.east);
      expect(observation.difficulty, CpuDifficulty.skilled);
      expect(observation.legalActionIds, [
        ClassicHareegActionIds.drawStock,
        ClassicHareegActionIds.takeDiscard,
      ]);
      expect(
        () => observation.legalActionIds.add('mutate'),
        throwsUnsupportedError,
      );
      expect(observation.turnPhase, TurnPhase.draw);
      expect(observation.pendingDiscard, isNull);
      expect(observation.ownHand, controller.handFor(PlayerSeat.east));
      expect(
        observation.handCountFor(PlayerSeat.south),
        controller.cardCountFor(PlayerSeat.south),
      );
      expect(observation.tableMeldsFor(PlayerSeat.east), isEmpty);
      expect(observation.tableMelds, controller.tableMelds);
      expect(observation.tableMeldCount, 0);
      expect(observation.stockCount, controller.stockCount);
      expect(observation.topDiscard, controller.topDiscard);
      expect(observation.discardCount, controller.discardPile.length);
      expect(observation.openingState, same(controller.openingState));
      expect(observation.hasOpened(PlayerSeat.east), isFalse);
      expect(observation.ownHasOpened(), isFalse);
      expect(observation.benchmarkOwner, isNull);
      expect(observation.currentOpeningRequirement, setup.openingRequirement);
      expect(
        observation.scoreView.currentScores,
        controller.scoreView.currentScores,
      );
      expect(observation.scoreFor(PlayerSeat.east), 0);
      expect(observation.ownScore, 0);
      expect(
        observation.eliminationThreshold,
        controller.rules.eliminationScore,
      );
      expect(observation.activeSeats, controller.activeSeats);
      expect(observation.currentSeat, PlayerSeat.east);
      expect(observation.opponents, [
        PlayerSeat.north,
        PlayerSeat.west,
        PlayerSeat.south,
      ]);
      expect(observation.fiftyClaimant, controller.fiftyClaimant);
      expect(
        observation.fiftySecondsRemaining,
        controller.fiftySecondsRemaining,
      );
      expect(
        observation.ownIsFiftyClaimant,
        controller.fiftyClaimant == PlayerSeat.east,
      );
      expect(observation.difficultyProfile.difficulty, CpuDifficulty.skilled);
    });

    test('uses live discard history and partition views by default', () {
      final controller = _controllerForCpuDrawTurn();
      final observation = LiveCpuObservation(
        controller: controller,
        seat: PlayerSeat.east,
        legalActionIds: const [ClassicHareegActionIds.drawStock],
        difficulty: CpuDifficulty.casual,
      );

      expect(
        observation.discardHistory.lastDiscardsBy(PlayerSeat.south, 2),
        isEmpty,
      );
      expect(
        observation.discardHistory.lastPickupsBy(PlayerSeat.south, 2),
        isEmpty,
      );
      expect(
        observation.discardHistory.cardSeenAt(CardRank.ace, CardSuit.clubs),
        isFalse,
      );
      expect(observation.discardHistory.discardsCount(CardRank.ace), 0);
      expect(observation.discardHistory.jokersDiscarded, 0);
      expect(observation.partitions, isA<LiveMeldPartitionView>());
    });

    test('enumerates live partitions for convenience helpers', () {
      final hand = [
        _card(CardRank.seven, CardSuit.clubs, deckIndex: 1),
        _card(CardRank.seven, CardSuit.diamonds, deckIndex: 1),
        _card(CardRank.seven, CardSuit.hearts, deckIndex: 1),
        _card(CardRank.two, CardSuit.clubs, deckIndex: 1),
      ];
      final controller = _controllerWithCpuHand(hand);
      final observation = LiveCpuObservation(
        controller: controller,
        seat: PlayerSeat.east,
        legalActionIds: const [ClassicHareegActionIds.discardPrefix],
        difficulty: CpuDifficulty.casual,
      );

      final partitions = observation.partitions.enumerate().toList();

      expect(partitions, hasLength(1));
      expect(partitions.single.meldCount, 1);
      expect(partitions.single.cardsRemaining, [hand.last]);
      expect(
        observation.shortestSingleMeld()?.cardsRemaining,
        partitions.single.cardsRemaining,
      );
      expect(
        observation.finishingPartition()?.cardsRemaining,
        partitions.single.cardsRemaining,
      );
    });
  });

  test('FakeCpuObservation can be constructed for strategy unit tests', () {
    final observation = _FakeCpuObservation(
      seat: PlayerSeat.north,
      legalActionIds: const ['draw-stock'],
      difficulty: CpuDifficulty.expert,
      ownScore: 7,
    );

    expect(observation.seat, PlayerSeat.north);
    expect(observation.legalActionIds, const ['draw-stock']);
    expect(observation.difficultyProfile.difficulty, CpuDifficulty.expert);
    expect(observation.scoreFor(PlayerSeat.north), 7);
    expect(observation.ownScore, 7);
  });
}

ClassicHareegGameController _controllerForCpuDrawTurn({
  ClassicHareegSetup? setup,
}) {
  final round = ClassicHareegRound.deal(
    setup: setup ?? ClassicHareegSetup.defaults(),
    seed: 5,
  );
  final hands = _mutableHands(round);
  final southHand = hands[PlayerSeat.south]!;
  final discarded = southHand.firstWhere((card) => !card.isJoker);
  southHand.removeWhere((card) => card.id == discarded.id);

  return ClassicHareegGameController.fromSnapshot(
    ClassicHareegMatchSnapshot(
      setup: round.setup,
      hands: hands,
      stock: round.stock,
      discardPile: [discarded],
      starter: round.starter,
      currentSeat: PlayerSeat.east,
      turnPhase: TurnPhase.draw,
      savedAt: DateTime.utc(2026, 5, 23),
    ),
  );
}

ClassicHareegGameController _controllerWithCpuHand(List<HareegCard> hand) {
  final setup = ClassicHareegSetup.defaults();
  return ClassicHareegGameController.fromSnapshot(
    ClassicHareegMatchSnapshot(
      setup: setup,
      hands: {
        PlayerSeat.south: const [],
        PlayerSeat.east: hand,
        PlayerSeat.north: const [],
        PlayerSeat.west: const [],
      },
      stock: [_card(CardRank.three, CardSuit.spades, deckIndex: 1)],
      discardPile: const [],
      starter: PlayerSeat.east,
      currentSeat: PlayerSeat.east,
      turnPhase: TurnPhase.action,
      savedAt: DateTime.utc(2026, 5, 23),
    ),
  );
}

Map<PlayerSeat, List<HareegCard>> _mutableHands(ClassicHareegRound round) {
  return {
    for (final seat in PlayerSeat.values)
      seat: List<HareegCard>.of(round.hands[seat] ?? const []),
  };
}

typedef _FakeCpuObservation = CpuObservationFacts;

HareegCard _card(CardRank rank, CardSuit suit, {required int deckIndex}) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
