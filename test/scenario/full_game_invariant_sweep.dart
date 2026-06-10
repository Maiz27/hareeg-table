import 'dart:io';

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

/// Tiered seed coverage. The full seed matrix is expensive, so PRs run a
/// reduced seed set for fast feedback while every other axis (strictness tier,
/// joker count, CPU difficulty) is preserved. Push-to-`main` and the nightly
/// schedule set `HAREEG_FULL_SWEEP=1` so the complete seed matrix still lands on
/// `main` within a day — see `.github/workflows/flutter-ci.yml`. Set the env var
/// locally to reproduce the full run.
final bool fullSweepSeeds = Platform.environment['HAREEG_FULL_SWEEP'] == '1';

const _casualSeedsFull = [1, 2, 3, 5, 7];
const _casualSeedsPr = [1, 3];
const _strategicSeedsFull = [1, 2, 3];
const _strategicSeedsPr = [1];

List<int> get casualSweepSeeds =>
    fullSweepSeeds ? _casualSeedsFull : _casualSeedsPr;
List<int> get strategicSweepSeeds =>
    fullSweepSeeds ? _strategicSeedsFull : _strategicSeedsPr;

const casualSweepJokerCounts = [0, 2, 4];

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

void driveFullGameInvariantSweep(
  ClassicHareegSetup setup,
  int seed, {
  int actionLimit = fullGameInvariantActionBudget,
  bool requireNoBackstopDraw = false,
  bool recoverStuckFiftyWindows = true,
}) {
  final checker = MatchInvariantChecker(
    setup: setup,
    seed: seed,
    requireNoBackstopDraw: requireNoBackstopDraw,
  );
  ClassicHareegMatchDriver(
    actionLimit: actionLimit,
    recoverStuckFiftyWindows: recoverStuckFiftyWindows,
  ).run(
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
    // Mistake-free CPUs always realize a reachable finish, so the
    // stock-exhaustion backstop must never fire — assert it does not.
    driveFullGameInvariantSweep(
      fullGameInvariantSetupFor(strictness, difficulty, 2),
      seed,
      requireNoBackstopDraw: true,
    );
  }
}

/// Seeds driven long enough to reach removed-seat (3-active) endgames, where a
/// stock-exhausted round historically livelocked once the human was gone. These
/// run in no-recovery mode (mirroring production's CPU loop) with the
/// no-backstop assertion, so a masked detector/executor disagreement fails the
/// sweep instead of silently drawing or running to the action cap.
///
/// Tiered like the rest of the sweep: PRs run a reduced set for fast feedback
/// while push-to-`main`/nightly (`HAREEG_FULL_SWEEP=1`) drive the full matrix.
const _removedSeatEndgameSeedsFull = [1, 2, 3, 4, 5, 6, 7, 8, 11, 13, 17, 23];
const _removedSeatEndgameSeedsPr = [1, 2, 3];

List<int> get removedSeatEndgameSeeds =>
    fullSweepSeeds ? _removedSeatEndgameSeedsFull : _removedSeatEndgameSeedsPr;

/// Higher budget so eliminations land and a 3-seat endgame is actually reached.
const removedSeatEndgameActionBudget = 8000;

const removedSeatEndgameTimeout = Timeout(Duration(minutes: 6));

void driveRemovedSeatEndgameInvariantSweep(
  CpuDifficulty difficulty,
  TableStrictness strictness,
) {
  for (final seed in removedSeatEndgameSeeds) {
    driveFullGameInvariantSweep(
      fullGameInvariantSetupFor(strictness, difficulty, 2),
      seed,
      actionLimit: removedSeatEndgameActionBudget,
      requireNoBackstopDraw: true,
      recoverStuckFiftyWindows: false,
    );
  }
}
