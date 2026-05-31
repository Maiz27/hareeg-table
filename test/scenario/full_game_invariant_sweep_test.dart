import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';

import 'classic_hareeg_match_driver.dart';
import 'invariants/match_invariants.dart';

/// Family A — full-match invariant sweep.
///
/// Plays Classic Hareeg matches (every seat driven by the real CPU strategy)
/// across the config matrix and asserts the universal invariants in
/// [MatchInvariantChecker] after every action and every round: card
/// conservation, turn / removed-seat integrity, scores moving only at round
/// boundaries with the documented normal/Fifty/draw deltas, and the elimination
/// threshold.
///
/// It does not assert that a match *ends* — weak CPUs draw rounds indefinitely,
/// which is a balance property, not a correctness failure. Each match is capped
/// at a finite action budget that still spans several rounds, so every
/// invariant is exercised without waiting on convergence.
void main() {
  // Per-match action budget. Spans several rounds (a casual round is ~100
  // actions) so round-boundary invariants run repeatedly, while keeping the
  // whole sweep fast even though casual matches rarely converge.
  const actionBudget = 600;

  ClassicHareegSetup setupFor(
    TableStrictness strictness,
    CpuDifficulty difficulty,
    int jokerCount,
  ) {
    return ClassicHareegSetup.defaults().copyWith(
      tableStrictness: strictness,
      cpuDifficulty: difficulty,
      jokerCount: jokerCount,
    );
  }

  void driveAndCheck(ClassicHareegSetup setup, int seed) {
    final checker = MatchInvariantChecker(setup: setup, seed: seed);
    ClassicHareegMatchDriver(actionLimit: actionBudget).run(
      setup: setup,
      seed: seed,
      onStep: checker.checkStep,
      onRoundEnd: checker.checkRound,
    );
  }

  // Broad coverage with the cheap (priority) planner: every strictness tier ×
  // joker count × several seeds. This is where most engine regressions surface.
  group('Correctness sweep — casual planner', () {
    const seeds = [1, 2, 3, 5, 7];
    const jokerCounts = [0, 2, 4];
    for (final strictness in TableStrictness.values) {
      test('${strictness.name}: invariants hold across seeds and joker counts',
          () {
        for (final jokerCount in jokerCounts) {
          for (final seed in seeds) {
            driveAndCheck(setupFor(strictness, CpuDifficulty.casual, jokerCount),
                seed);
          }
        }
      });
    }
  });

  // Thinner slice exercising the strategic planners (partition search, defensive
  // discards, joker timing) so their action sequences are covered too. Fewer
  // cells because these planners are far more expensive per decision.
  group('Correctness sweep — strategic planners', () {
    const seeds = [1, 2, 3];
    for (final difficulty in [CpuDifficulty.skilled, CpuDifficulty.expert]) {
      for (final strictness in [TableStrictness.standard, TableStrictness.table]) {
        test('${difficulty.name} × ${strictness.name}: invariants hold', () {
          for (final seed in seeds) {
            driveAndCheck(setupFor(strictness, difficulty, 2), seed);
          }
        });
      }
    }
  });
}
