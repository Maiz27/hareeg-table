import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_turn_exit_planner.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';

void main() {
  group('ClassicHareegTurnExitPlanner', () {
    test('next active seat skips seats removed from the round', () {
      final next = ClassicHareegTurnExitPlanner.nextActiveSeat(
        seat: PlayerSeat.south,
        activeSeats: PlayerSeat.values,
        removedSeats: {PlayerSeat.east},
      );

      expect(next, PlayerSeat.north);
    });

    test('previous discard pickup follows active anti-clockwise order', () {
      final canTake = ClassicHareegTurnExitPlanner.canTakePreviousDiscard(
        currentSeat: PlayerSeat.north,
        phase: TurnPhase.draw,
        previousDiscardSeat: PlayerSeat.south,
        discardPileIsNotEmpty: true,
        activeSeats: PlayerSeat.values,
        removedSeats: {PlayerSeat.east},
      );

      expect(canTake, isTrue);
    });

    test('non-final discard opens Fifty window and advances to draw phase', () {
      final discard = card(CardRank.seven, CardSuit.hearts);
      final exit = ClassicHareegTurnExitPlanner.afterDiscard(
        discarder: PlayerSeat.south,
        discardedCard: discard,
        isFinalDiscard: false,
        activeSeats: PlayerSeat.values,
        removedSeats: const {},
        roundNumber: 1,
        fiftyTimerSeconds: 12,
        remainingCardCounts: const {
          PlayerSeat.south: 3,
          PlayerSeat.east: 4,
        },
      );

      expect(exit.nextSeat, PlayerSeat.east);
      expect(exit.nextPhase, TurnPhase.draw);
      expect(exit.roundResult, isNull);
      expect(exit.fiftyWindow.discarder, PlayerSeat.south);
      expect(exit.fiftyWindow.claimant, PlayerSeat.east);
      expect(exit.fiftyWindow.discardedCard, discard);
    });

    test('final discard produces normal finish result', () {
      final exit = ClassicHareegTurnExitPlanner.afterDiscard(
        discarder: PlayerSeat.south,
        discardedCard: card(CardRank.ace, CardSuit.spades),
        isFinalDiscard: true,
        activeSeats: PlayerSeat.values,
        removedSeats: const {},
        roundNumber: 2,
        fiftyTimerSeconds: 12,
        remainingCardCounts: const {
          PlayerSeat.south: 0,
          PlayerSeat.east: 5,
        },
      );

      expect(exit.roundResult?.type, RoundOutcomeType.normalFinish);
      expect(exit.roundResult?.winner, PlayerSeat.south);
      expect(exit.roundResult?.remainingCardCounts[PlayerSeat.east], 5);
    });

    test('stock exhaustion returns draw result when pickup cannot finish', () {
      final result = ClassicHareegTurnExitPlanner.stockExhaustionRoundResult(
        stockIsEmpty: true,
        previousDiscardCanFinish: true,
        pickupWouldFinish: false,
        remainingCardCounts: const {
          PlayerSeat.south: 3,
          PlayerSeat.east: 4,
        },
      );

      expect(result?.type, RoundOutcomeType.draw);
      expect(result?.remainingCardCounts[PlayerSeat.south], 3);
    });

    test('hard-table removal ends round when one seat remains', () {
      final exit = ClassicHareegTurnExitPlanner.afterPlayerRemoval(
        removedSeat: PlayerSeat.north,
        activeSeats: const [PlayerSeat.south, PlayerSeat.north],
        removedSeats: {PlayerSeat.north},
        remainingCardCounts: const {PlayerSeat.south: 6},
      );

      expect(exit.roundResult?.type, RoundOutcomeType.normalFinish);
      expect(exit.roundResult?.winner, PlayerSeat.south);
      expect(exit.nextSeat, isNull);
    });
  });
}

HareegCard card(CardRank rank, CardSuit suit) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: 500);
}
