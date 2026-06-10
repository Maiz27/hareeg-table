import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/classic_hareeg_coaching_advisor.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/coaching_insight.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';

import 'classic_hareeg_match_driver.dart';
import 'full_game_invariant_sweep.dart';

/// Coaching-advisor sweep: runs the advisor against every real mid-match
/// decision state of full driven matches on the Coaching tier — the layer the
/// unit tests cannot reach (test-layering lesson: playtest bugs live in the
/// states nobody hand-built).
///
/// Asserts the advisor:
/// - never throws on any reachable state (including states where it is not
///   the coached seat's turn — the UI gates on turn, the advisor must not
///   depend on it);
/// - is never SILENT on the coached seat's own actionable turns (a draw or a
///   plain discard is available — the floors must cover it; blackouts were a
///   real shipped bug class);
/// - produces a healthy spread of teaching, not one fixated category (the
///   "CPU is collecting" playtest fixation).
void main() {
  test(
    'coaching advisor: never throws, never silent, never fixated across '
    'full driven matches',
    () {
      final leadCounts = <CoachingInsightCategory, int>{};
      var southDecisions = 0;

      for (final seed in casualSweepSeeds) {
        final setup = fullGameInvariantSetupFor(
          TableStrictness.coaching,
          CpuDifficulty.casual,
          2,
        );
        ClassicHareegMatchDriver(
          actionLimit: fullGameInvariantActionBudget,
        ).run(
          setup: setup,
          seed: seed,
          onDecision: (controller, seat) {
            // The advisor must hold up for the coached seat on EVERY state,
            // on-turn or not (the UI computes on its own schedule).
            final insights = ClassicHareegCoachingAdvisor.adviseFor(
              controller,
              PlayerSeat.south,
            );

            if (seat != PlayerSeat.south) {
              return;
            }
            southDecisions += 1;

            final legal = controller.legalActionIdsFor(PlayerSeat.south);
            final hasFloorAction =
                legal.contains(ClassicHareegActionIds.drawStock) ||
                legal.any(
                  (id) => ClassicHareegActionIds.describe(id).isSafeDiscard,
                );
            if (hasFloorAction) {
              expect(
                insights,
                isNotEmpty,
                reason:
                    'Advisor went silent on an actionable turn '
                    '(seed=$seed, legal=$legal).',
              );
            }
            if (insights.isNotEmpty) {
              leadCounts.update(
                insights.first.category,
                (count) => count + 1,
                ifAbsent: () => 1,
              );
            }
          },
        );
      }

      expect(southDecisions, greaterThan(0));
      // Healthy spread: a full match must exercise more than a couple of
      // teaching shapes. (Pre-overhaul, the defensive warning monopolized the
      // top slot for whole stretches of every round.)
      expect(
        leadCounts.keys.length,
        greaterThanOrEqualTo(3),
        reason: 'Lead-hint categories seen: $leadCounts',
      );
      // No single category may own (nearly) every turn. The floors are the
      // most frequent by design, but even they must leave room for real plays.
      final total = leadCounts.values.fold<int>(0, (a, b) => a + b);
      for (final entry in leadCounts.entries) {
        expect(
          entry.value,
          lessThan((total * 0.9).ceil()),
          reason:
              'Category ${entry.key.name} leads ${entry.value}/$total '
              'decisions — fixation regression. Spread: $leadCounts',
        );
      }
    },
    timeout: casualSweepTimeout,
  );
}
