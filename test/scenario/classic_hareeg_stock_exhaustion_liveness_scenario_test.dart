import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_observation.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_strategy.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';

import 'classic_hareeg_scenario.dart';

/// Stock-exhaustion round liveness.
///
/// A real exported match (Table strictness, seed `1051392520`, skilled CPU, 2
/// decks, 2 jokers) froze on the score/table screen in round 2 after the human
/// (south) was eliminated by Table-tier penalties: stock was empty and the
/// three remaining CPUs cycled the Fifty window endlessly — taking and
/// re-discarding without anyone finishing — so the round never ended.
///
/// Two layers conspired:
///
///  1. Engine: `_evaluateRoundEnd` declines to draw a stock-exhausted round
///     while it still believes a finish is reachable (a valid Fifty finish or a
///     finishing pickup). In the live loop that belief never resolves — the
///     Fifty window's wall-clock expiry never lands because the CPU loop keeps
///     reopening a fresh window faster than the timer ages, and the detected
///     finish is one the CPU never actually completes. The round can never
///     progress yet is never drawn.
///
///  2. UI: the table's CPU loop auto-restarts itself (`scheduleMicrotask`) when
///     the human is removed and the per-run safety cap is hit, assuming the
///     round will end "naturally". In a livelock it never does, so the table
///     spins frames forever.
///
/// The engine now carries a liveness backstop: once stock is empty, the total
/// card count across active hands can only fall by melding or covering a card
/// onto the table, so if a full rotation of active seats passes with no such
/// reduction the round is provably dead and is drawn. The UI bounds its
/// auto-restart so it can never spin forever even if some state slips past.
void main() {
  group('reported frozen snapshot', () {
    test(
      'restoring the seed 1051392520 freeze resolves the dead round as a draw',
      () {
        // The persisted snapshot reverts the in-progress turn to a clean draw
        // phase, so restoring it reaches `_evaluateRoundEnd` fresh and draws —
        // this is exactly the "leave the table and Continue un-sticks it"
        // recovery the owner observed. It guards the engine's termination of a
        // stock-exhausted, no-finish, removed-seat endgame.
        final raw = File(
          'test/fixtures/reports/livelock_snapshot_1051392520.json',
        ).readAsStringSync();
        final snapshot = ClassicHareegMatchSnapshot.fromJson(
          jsonDecode(raw) as Map<String, Object?>,
        );

        final controller = ClassicHareegGameController.fromSnapshot(
          snapshot,
          now: () => DateTime.parse('2026-06-09T10:23:14.000Z'),
        );

        expect(
          controller.isRoundOver,
          isTrue,
          reason: 'a stock-exhausted endgame with no reachable finish must end',
        );
        expect(controller.roundOutcome, RoundOutcomeType.draw);
        // The human was eliminated, so the round is dead for everyone left.
        expect(controller.removedSeats, contains(PlayerSeat.south));
      },
    );
  });

  group('production-path liveness (no driver recovery)', () {
    // The full-match test driver expires stale Fifty windows and re-polls, so it
    // can never observe this livelock. The real in-app CPU loop has no such
    // recovery, so we drive the production runner surface directly here with a
    // FIXED clock (Fifty windows never age out — the in-app fast-loop
    // condition). Every round must still terminate within a tight per-round
    // action budget; the engine backstop guarantees it.
    final setup = ClassicHareegSetup.defaults().copyWith(
      cpuDifficulty: CpuDifficulty.skilled,
      tableStrictness: TableStrictness.table,
      jokerCount: 2,
      deckCount: 2,
    );

    for (final seed in [23, 1051392520]) {
      for (final stockKeep in [4]) {
        test('raw CPU loop terminates every round (seed=$seed keep=$stockKeep)',
            () {
          const strategy = ClassicHareegCpuStrategy();
          final clock = DateTime.utc(2026, 1, 1); // fixed: windows never expire
          final dealt = ClassicHareegRound.deal(setup: setup, seed: seed);
          var controller = ClassicHareegScenario.deal(
            setup: setup,
            seed: seed,
            stock: dealt.stock.take(stockKeep).toList(),
            now: () => clock,
          ).controller;

          // A legitimate stock-exhausted endgame resolves in far fewer than this
          // many actions per round; exceeding it is the livelock signature.
          const perRoundActionCap = 200;

          var rounds = 0;
          while (rounds < 30) {
            rounds += 1;
            var roundActions = 0;
            while (!controller.isRoundOver) {
              final seat = controller.currentSeat;
              final legal = controller.cpuActionIdsFor(seat);
              expect(
                legal,
                isNotEmpty,
                reason: 'seat ${seat.name} was stranded with no legal action',
              );
              final intent = strategy.chooseMove(
                CpuTurnSnapshot(
                  seat: seat,
                  legalActionIds: legal,
                  difficulty: controller.setup.cpuDifficulty,
                ),
                observation: LiveCpuObservation(
                  controller: controller,
                  seat: seat,
                  legalActionIds: legal,
                  difficulty: controller.setup.cpuDifficulty,
                ),
              );
              final result = controller.applyAction(intent.actionId);
              expect(result.isSuccess, isTrue, reason: result.message);
              roundActions += 1;
              expect(
                roundActions,
                lessThanOrEqualTo(perRoundActionCap),
                reason: 'round did not terminate — stock-exhaustion livelock',
              );
            }
            final next = controller.nextRoundSnapshot(savedAt: clock);
            if (next == null) break; // match winner reached
            controller = ClassicHareegGameController.fromSnapshot(
              next,
              now: () => clock,
            );
          }
        });
      }
    }
  });
}
