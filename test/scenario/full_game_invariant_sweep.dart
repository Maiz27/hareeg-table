import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';

import 'classic_hareeg_match_driver.dart';
import 'invariants/match_invariants.dart';

/// Family A: full-match invariant sweep.
///
/// Plays Classic Hareeg matches (every seat driven by the real CPU strategy)
/// across the config matrix and asserts the universal invariants in
/// [MatchInvariantChecker] after every action and every round: card
/// conservation, turn / removed-seat integrity, scores moving only at round
/// boundaries with the documented normal/Fifty/draw deltas, and the elimination
/// threshold.
///
/// It does not assert that a match ends: weak CPUs draw rounds indefinitely,
/// which is a balance property, not a correctness failure. Each match is capped
/// at a finite action budget that still spans several rounds, so every
/// invariant is exercised without waiting on convergence.
///
/// The discovered test files intentionally split the matrix across suites so
/// `flutter test` can parallelize this expensive sweep at file granularity.

// Per-match action budget. Spans several rounds (a casual round is about 100
// actions) so round-boundary invariants run repeatedly, while keeping the whole
// sweep bounded even though casual matches rarely converge.
const fullGameInvariantActionBudget = 600;

const casualSweepSeeds = [1, 2, 3, 5, 7];
const casualSweepJokerCounts = [0, 2, 4];
const strategicSweepSeeds = [1, 2, 3];

const casualSweepTimeout = Timeout(Duration(minutes: 3));
const strategicSweepTimeout = Timeout(Duration(minutes: 5));

ClassicHareegSetup fullGameInvariantSetupFor(
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

void driveFullGameInvariantSweep(ClassicHareegSetup setup, int seed) {
  final checker = MatchInvariantChecker(setup: setup, seed: seed);
  ClassicHareegMatchDriver(actionLimit: fullGameInvariantActionBudget).run(
    setup: setup,
    seed: seed,
    onStep: checker.checkStep,
    onRoundEnd: checker.checkRound,
  );
}

void driveCasualFullGameInvariantSweep(TableStrictness strictness) {
  for (final jokerCount in casualSweepJokerCounts) {
    for (final seed in casualSweepSeeds) {
      driveFullGameInvariantSweep(
        fullGameInvariantSetupFor(strictness, CpuDifficulty.casual, jokerCount),
        seed,
      );
    }
  }
}

void driveStrategicFullGameInvariantSweep(
  CpuDifficulty difficulty,
  TableStrictness strictness,
) {
  for (final seed in strategicSweepSeeds) {
    driveFullGameInvariantSweep(
      fullGameInvariantSetupFor(strictness, difficulty, 2),
      seed,
    );
  }
}
