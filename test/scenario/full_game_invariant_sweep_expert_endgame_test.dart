import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';

import 'full_game_invariant_sweep.dart';

/// Removed-seat endgame sweep (issue #94): drives expert-CPU Table matches long
/// enough to reach 3-active endgames, in no-recovery mode (mirroring the
/// production CPU loop) with the no-backstop assertion. See the skilled variant
/// for the full rationale.
void main() {
  test('expert table endgame: no stock-exhaustion livelock', () {
    driveRemovedSeatEndgameInvariantSweep(
      CpuDifficulty.expert,
      TableStrictness.table,
    );
  }, timeout: removedSeatEndgameTimeout);
}
