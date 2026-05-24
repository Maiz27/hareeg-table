import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_mistake_consequence_planner.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/mistake_preset_rules.dart';

void main() {
  group('ClassicHareegMistakeConsequencePlanner', () {
    test(
      'assisted preset blocks mistakes without score or removal changes',
      () {
        final plan = ClassicHareegMistakeConsequencePlanner.evaluate(
          strictness: TableStrictness.coaching,
          mistake: MistakeType.wrongJokerReplacement,
          seat: PlayerSeat.south,
          scores: const {PlayerSeat.south: 4},
          activeSeats: PlayerSeat.values,
          removedSeats: const {},
          hasPendingDiscard: true,
          remainingCardCounts: const {
            PlayerSeat.south: 8,
            PlayerSeat.east: 9,
          },
        );

        expect(plan.scenario, ClassicHareegMistakeConsequenceScenario.blocked);
        expect(plan.canApply, isFalse);
        expect(plan.scoresAfterPenalty[PlayerSeat.south], 4);
        expect(plan.removedSeatsAfterMistake, isEmpty);
        expect(plan.shouldMovePendingDiscardToDiscardPile, isFalse);
        expect(plan.exit, isNull);
      },
    );

    test('table penalties apply score only and keep turn state alive', () {
      final plan = ClassicHareegMistakeConsequencePlanner.evaluate(
        strictness: TableStrictness.strict,
        mistake: MistakeType.wrongFiftyClaim,
        seat: PlayerSeat.east,
        scores: const {PlayerSeat.east: 6},
        activeSeats: PlayerSeat.values,
        removedSeats: const {},
        hasPendingDiscard: false,
        remainingCardCounts: const {
          PlayerSeat.south: 7,
          PlayerSeat.east: 8,
        },
      );

      expect(
        plan.scenario,
        ClassicHareegMistakeConsequenceScenario.penaltyOnly,
      );
      expect(plan.canApply, isTrue);
      expect(plan.shouldApplyPenalty, isTrue);
      expect(plan.scoresAfterPenalty[PlayerSeat.east], 9);
      expect(plan.removesPlayer, isFalse);
      expect(plan.shouldClearFiftyWindow, isFalse);
      expect(plan.shouldResetTurnState, isFalse);
    });

    test(
      'hard table removal applies score and advances to next active seat',
      () {
        final plan = ClassicHareegMistakeConsequencePlanner.evaluate(
          strictness: TableStrictness.table,
          mistake: MistakeType.illegalCoverDiscard,
          seat: PlayerSeat.south,
          scores: const {PlayerSeat.south: 2},
          activeSeats: PlayerSeat.values,
          removedSeats: const {PlayerSeat.east},
          hasPendingDiscard: true,
          remainingCardCounts: const {
            PlayerSeat.south: 10,
            PlayerSeat.north: 5,
            PlayerSeat.west: 6,
          },
        );

        expect(
          plan.scenario,
          ClassicHareegMistakeConsequenceScenario.removalContinues,
        );
        expect(plan.scoresAfterPenalty[PlayerSeat.south], 19);
        expect(plan.removedSeat, PlayerSeat.south);
        expect(plan.removedSeatsAfterMistake, {
          PlayerSeat.south,
          PlayerSeat.east,
        });
        expect(plan.nextSeat, PlayerSeat.north);
        expect(plan.nextPhase, TurnPhase.draw);
        expect(plan.shouldMovePendingDiscardToDiscardPile, isTrue);
        expect(plan.shouldClearFiftyWindow, isTrue);
        expect(plan.shouldResetTurnState, isTrue);
      },
    );

    test('hard table removal returns round result when one seat remains', () {
      final plan = ClassicHareegMistakeConsequencePlanner.evaluate(
        strictness: TableStrictness.table,
        mistake: MistakeType.wrongFiftyClaim,
        seat: PlayerSeat.north,
        scores: const {PlayerSeat.north: 0, PlayerSeat.south: 0},
        activeSeats: const [PlayerSeat.south, PlayerSeat.north],
        removedSeats: const {},
        hasPendingDiscard: false,
        remainingCardCounts: const {PlayerSeat.south: 4, PlayerSeat.north: 7},
      );

      expect(
        plan.scenario,
        ClassicHareegMistakeConsequenceScenario.removalEndsRound,
      );
      expect(plan.scoresAfterPenalty[PlayerSeat.north], 17);
      expect(plan.roundResult?.type, RoundOutcomeType.normalFinish);
      expect(plan.roundResult?.winner, PlayerSeat.south);
      expect(plan.nextSeat, isNull);
      expect(plan.nextPhase, isNull);
    });
  });
}
