import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_turn_checkpoint.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_turn_journal.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/finish_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

void main() {
  group('ClassicHareegTurnCheckpoint', () {
    test('rolls back active turn melds into the saved hand', () {
      final meldCards = [
        card(CardRank.jack, CardSuit.hearts),
        card(CardRank.queen, CardSuit.hearts),
        card(CardRank.king, CardSuit.hearts),
      ];
      final heldCard = card(CardRank.two, CardSuit.spades);
      final meld = PlacedMeld.fromCards(meldCards);

      final state = ClassicHareegTurnCheckpoint(
        currentSeat: PlayerSeat.east,
        hands: {
          PlayerSeat.east: [heldCard],
        },
        tableMelds: {
          PlayerSeat.east: [meld],
        },
        openingState: OpeningState(
          baseRequirement: 30,
          currentRequirement: meld.totalValue,
          benchmarkOwner: PlayerSeat.east,
          openedSeats: const {PlayerSeat.east},
        ),
        pendingDiscard: null,
        journalSnapshot: ClassicHareegTurnJournalSnapshot(
          finishMelds: const [],
          openingMelds: const [],
          turnMelds: [
            ClassicHareegTurnMeldPlay(owner: PlayerSeat.east, meld: meld),
          ],
          coverPlays: const [],
          consumedPendingDiscard: null,
          source: FinishCardSource.stock,
        ),
      ).toSnapshotState();

      expect(state.tableMelds[PlayerSeat.east], isEmpty);
      expect(state.hands[PlayerSeat.east]!.map((card) => card.id), [
        ...meldCards.map((card) => card.id),
        heldCard.id,
      ]);
      expect(state.openingState.currentRequirement, 30);
    });

    test('restores cover state and consumed pending discard', () {
      final baseMeld = PlacedMeld.fromCards([
        card(CardRank.seven, CardSuit.clubs),
        card(CardRank.eight, CardSuit.clubs),
        card(CardRank.nine, CardSuit.clubs),
      ]);
      final coverCard = card(CardRank.ten, CardSuit.clubs);
      final coveredMeld = baseMeld.addCoverCards([coverCard]);
      final pending = card(CardRank.ten, CardSuit.clubs, deckIndex: 2);
      const previousOpening = OpeningState(
        baseRequirement: 30,
        currentRequirement: 30,
        benchmarkOwner: PlayerSeat.east,
        openedSeats: {PlayerSeat.east},
      );

      final state = ClassicHareegTurnCheckpoint(
        currentSeat: PlayerSeat.east,
        hands: {PlayerSeat.east: const []},
        tableMelds: {
          PlayerSeat.east: [coveredMeld],
        },
        openingState: OpeningState(
          baseRequirement: 30,
          currentRequirement: coveredMeld.totalValue,
          benchmarkOwner: PlayerSeat.east,
          openedSeats: const {PlayerSeat.east},
        ),
        pendingDiscard: null,
        journalSnapshot: ClassicHareegTurnJournalSnapshot(
          finishMelds: const [],
          openingMelds: const [],
          turnMelds: const [],
          coverPlays: [
            ClassicHareegTurnCoverPlay(
              targetSeat: PlayerSeat.east,
              meldIndex: 0,
              previousMeld: baseMeld,
              coverMeld: PlacedMeld(cards: [coverCard], valueSnapshot: 10),
              previousOpeningState: previousOpening,
              consumedPendingDiscard: pending,
            ),
          ],
          consumedPendingDiscard: null,
          source: FinishCardSource.stock,
        ),
      ).toSnapshotState();

      expect(state.tableMelds[PlayerSeat.east], [baseMeld]);
      expect(state.hands[PlayerSeat.east]!.single.id, coverCard.id);
      expect(state.pendingDiscard, pending);
      expect(state.openingState.currentRequirement, 30);
    });
  });
}

HareegCard card(CardRank rank, CardSuit suit, {int deckIndex = 1}) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
