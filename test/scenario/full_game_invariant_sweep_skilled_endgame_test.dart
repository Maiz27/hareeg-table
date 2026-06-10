import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';

import 'full_game_invariant_sweep.dart';

/// Removed-seat endgame sweep (issue #94): drives skilled-CPU Table matches long
/// enough to reach 3-active endgames, in no-recovery mode (mirroring the
/// production CPU loop) with the no-backstop assertion. A stock-exhausted round
/// that only terminates via the liveness backstop — the finish-detection vs
/// CPU-pickup disagreement — fails the sweep instead of being tolerated as a
/// silent draw or an action-cap stop.
void main() {
  test('skilled table endgame: no stock-exhaustion livelock', () {
    driveRemovedSeatEndgameInvariantSweep(
      CpuDifficulty.skilled,
      TableStrictness.table,
    );
  }, timeout: removedSeatEndgameTimeout);
}
