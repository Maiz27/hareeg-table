import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_move_plan_pipeline.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_observation.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_strategy.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

void main() {
  group('Casual CPU routing', () {
    test(
      'takes a discard that immediately completes a meld while Beginner draws',
      () {
        final sevenClubs = card(CardRank.seven, CardSuit.clubs);
        final eightClubs = card(CardRank.eight, CardSuit.clubs);
        final nineClubs = card(CardRank.nine, CardSuit.clubs);
        final observation = CpuObservationFacts(
          legalActionIds: const [
            ClassicHareegActionIds.drawStock,
            ClassicHareegActionIds.takeDiscard,
          ],
          turnPhase: TurnPhase.draw,
          topDiscard: nineClubs,
          ownHand: [
            sevenClubs,
            eightClubs,
            card(CardRank.two, CardSuit.diamonds),
          ],
          openingState: opened(),
        );

        expect(
          _choose(CpuDifficulty.beginner, observation),
          ClassicHareegActionIds.drawStock,
        );
        expect(
          _choose(CpuDifficulty.casual, observation),
          ClassicHareegActionIds.takeDiscard,
        );
      },
    );

    test('sheds high pips while Beginner discards the first safe card', () {
      final fourClubs = card(CardRank.four, CardSuit.clubs);
      final kingDiamonds = card(CardRank.king, CardSuit.diamonds);
      final observation = CpuObservationFacts(
        legalActionIds: [discardAction(fourClubs), discardAction(kingDiamonds)],
        ownHand: [fourClubs, kingDiamonds],
        openingState: opened(),
      );

      expect(
        _choose(CpuDifficulty.beginner, observation),
        discardAction(fourClubs),
      );
      expect(
        _choose(CpuDifficulty.casual, observation),
        discardAction(kingDiamonds),
      );
    });

    test('Fifty miss chance is consumed by the shared claim gate', () {
      final discarded = card(CardRank.nine, CardSuit.clubs);
      final finish = partition(
        [
          [
            card(CardRank.seven, CardSuit.clubs),
            card(CardRank.eight, CardSuit.clubs),
            discarded,
          ],
        ],
        remaining: [card(CardRank.two, CardSuit.hearts)],
      );
      final observation = CpuObservationFacts(
        legalActionIds: const [
          ClassicHareegActionIds.claimFifty,
          ClassicHareegActionIds.drawStock,
        ],
        turnPhase: TurnPhase.draw,
        topDiscard: discarded,
        ownHand: [
          card(CardRank.seven, CardSuit.clubs),
          card(CardRank.eight, CardSuit.clubs),
          card(CardRank.two, CardSuit.hearts),
        ],
        fiftyClaimant: PlayerSeat.east,
        finishingPartition: finish,
      );

      expect(
        shouldAttemptFiftyClaimFor(
          observation,
          profile: const CpuDifficultyProfile(
            difficulty: CpuDifficulty.casual,
            fiftyReactionMillis: 0,
            fiftyMissChance: 0,
          ),
        ),
        isTrue,
      );
      expect(
        shouldAttemptFiftyClaimFor(
          observation,
          profile: const CpuDifficultyProfile(
            difficulty: CpuDifficulty.casual,
            fiftyReactionMillis: 0,
            fiftyMissChance: 1,
          ),
        ),
        isFalse,
      );
    });
  });
}

String _choose(CpuDifficulty difficulty, CpuObservationFacts observation) {
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
  return const OpeningState(
    baseRequirement: 30,
    currentRequirement: 30,
    openedSeats: {PlayerSeat.east},
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
