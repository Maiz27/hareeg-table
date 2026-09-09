import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_observation.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_strategy.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';

import '../../scenario/classic_hareeg_scenario.dart';

void main() {
  test('a Fifty proof keeps its next move after the first meld is saved', () {
    final clock = DateTime.utc(2026, 1, 1);
    HareegCard card(CardRank rank, CardSuit suit) =>
        ScenarioCards.card(rank, suit, deckIndex: 1);
    final controller = ClassicHareegScenario.deal(
      southHand: [
        card(CardRank.two, CardSuit.diamonds),
        card(CardRank.seven, CardSuit.diamonds),
        card(CardRank.three, CardSuit.diamonds),
        card(CardRank.seven, CardSuit.spades),
        card(CardRank.four, CardSuit.diamonds),
        card(CardRank.ace, CardSuit.spades),
      ],
      discardPile: [card(CardRank.seven, CardSuit.hearts)],
      currentSeat: PlayerSeat.south,
      turnPhase: TurnPhase.draw,
      fiftyWindowOpenedAt: clock,
      now: () => clock,
    ).controller;
    expect(controller.applyAction('claim-fifty').isSuccess, isTrue);
    final first = controller.cpuActionIdsFor(PlayerSeat.south).single;
    expect(controller.applyAction(first).isSuccess, isTrue);
    final restored = ClassicHareegGameController.fromSnapshot(
      ClassicHareegMatchSnapshot.fromJson(
        controller.toPositionSnapshot(savedAt: clock).toJson(),
      ),
      now: () => clock,
    );
    expect(
      restored.cpuActionIdsFor(PlayerSeat.south),
      controller.cpuActionIdsFor(PlayerSeat.south),
    );
  });
  for (final seed in [7, 13, 21]) {
    test(
      'seed $seed CPU choices and applied states survive every save',
      () {
        var clock = DateTime.utc(2026, 1, 1);
        DateTime now() => clock;
        var controller = ClassicHareegScenario.deal(
          setup: ClassicHareegSetup.defaults(),
          seed: seed,
          now: now,
        ).controller;
        const strategy = ClassicHareegCpuStrategy();
        for (var action = 0; action < 2500; action++) {
          if (controller.isRoundOver) {
            final next = controller.nextRoundSnapshot(savedAt: now());
            if (next == null) {
              expect(action, greaterThan(135));
              expect(controller.roundProgress?.matchWinner, isNotNull);
              return;
            }
            controller = ClassicHareegGameController.fromSnapshot(
              next,
              now: now,
            );
          }
          final seat = controller.currentSeat;
          var ids = controller.cpuActionIdsFor(seat);
          final snapshot = controller.toPositionSnapshot(savedAt: now());
          final restored = ClassicHareegGameController.fromSnapshot(
            ClassicHareegMatchSnapshot.fromJson(
              jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, Object?>,
            ),
            now: now,
          );
          expect(
            restored.toPositionSnapshot(savedAt: now()).toJson(),
            snapshot.toJson(),
          );
          expect(
            restored.legalActionIdsFor(seat),
            controller.legalActionIdsFor(seat),
          );
          expect(
            restored.cpuActionIdsFor(seat),
            ids,
            reason:
                'action $action round ${controller.roundNumber} ${seat.name}',
          );
          CpuMoveIntent? choose(ClassicHareegGameController source) {
            final candidates = source.cpuActionIdsFor(seat);
            try {
              return strategy.chooseMove(
                CpuTurnSnapshot(
                  seat: seat,
                  legalActionIds: candidates,
                  difficulty: source.setup.cpuDifficulty,
                ),
                observation: LiveCpuObservation(
                  controller: source,
                  seat: seat,
                  legalActionIds: candidates,
                  difficulty: source.setup.cpuDifficulty,
                ),
              );
            } on StateError catch (error) {
              if (error.message.contains('at least one legal action')) {
                return null;
              }
              rethrow;
            }
          }

          var intent = choose(controller);
          expect(
            choose(restored)?.actionId,
            intent?.actionId,
            reason: 'chosen move at action $action',
          );
          if (intent == null) {
            clock = clock.add(
              Duration(seconds: controller.setup.fiftyTimerSeconds + 30),
            );
            ids = controller.cpuActionIdsFor(seat);
            expect(restored.cpuActionIdsFor(seat), ids);
            intent = choose(controller);
            expect(choose(restored)?.actionId, intent?.actionId);
          }
          expect(intent, isNotNull);
          final liveResult = controller.applyAction(intent!.actionId);
          final restoredResult = restored.applyAction(intent.actionId);
          expect(liveResult.isSuccess, isTrue);
          expect(restoredResult.isSuccess, isTrue);
          expect(restoredResult.wasReverted, liveResult.wasReverted);
          expect(
            restored.toPositionSnapshot(savedAt: now()).toJson(),
            controller.toPositionSnapshot(savedAt: now()).toJson(),
            reason: 'applied state at action $action',
          );
          expect(
            restored.roundProgress?.matchWinner,
            controller.roundProgress?.matchWinner,
          );
          if (controller.isRoundOver) {
            expect(
              restored.nextRoundSnapshot(savedAt: now())?.toJson(),
              controller.nextRoundSnapshot(savedAt: now())?.toJson(),
            );
          }
          clock = clock.add(const Duration(seconds: 1));
        }
        fail('match did not finish within the action bound');
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
