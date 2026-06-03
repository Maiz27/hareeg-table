import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';

import 'full_game_invariant_sweep.dart';

void main() {
  test('skilled table: invariants hold across seeds', () {
    driveStrategicFullGameInvariantSweep(
      CpuDifficulty.skilled,
      TableStrictness.table,
    );
  }, timeout: strategicSweepTimeout);
}
