import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/ui/core/motion/motion_speed.dart';

void main() {
  group('TableMotion', () {
    test('fast CPU turns keep a readable cadence between visible actions', () {
      const actionCount = 6;
      const gapCount = actionCount - 1;
      final fastCycle = _cpuCycleDuration(
        actionCount: actionCount,
        gapCount: gapCount,
        readPause: TableMotion.fastCpuReadPause,
        flight: TableMotion.fastCpuFlight,
        gap: TableMotion.fastCpuActionGap,
      );
      final normalCycle = _cpuCycleDuration(
        actionCount: actionCount,
        gapCount: gapCount,
        readPause: TableMotion.cpuReadPause,
        flight: TableMotion.cpuFlight,
        gap: TableMotion.cpuMove,
      );

      expect(TableMotion.fastCpuReadPause.inMilliseconds, greaterThan(0));
      expect(TableMotion.fastCpuActionGap.inMilliseconds, greaterThan(0));
      expect(
        TableMotion.fastCpuFlight.inMilliseconds,
        greaterThanOrEqualTo(140),
      );
      expect(fastCycle.inMilliseconds, greaterThanOrEqualTo(2200));
      expect(fastCycle, lessThan(normalCycle));
    });
  });
}

Duration _cpuCycleDuration({
  required int actionCount,
  required int gapCount,
  required Duration readPause,
  required Duration flight,
  required Duration gap,
}) {
  return Duration(
    milliseconds:
        actionCount * (readPause + flight).inMilliseconds +
        gapCount * gap.inMilliseconds,
  );
}
