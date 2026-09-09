import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/round_seed_algorithm.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_flow.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/classic_hareeg_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_table_reading.dart';

void main() {
  test('32-bit FNV matches published vectors and a BigInt reference', () {
    expect(TableReadingPolicy.fnv1a32('a'), 3826002220);
    expect(TableReadingPolicy.fnv1a32('foobar'), 3214735720);
    expect(
      TableReadingPolicy.fnv1a32('east|r2|action|s63|d4|m1|h12'),
      2501005033,
    );
    for (var value = 0; value <= 0xffffffff; value += 16777213) {
      expect(
        fnvMultiply32(value),
        ((BigInt.from(value) * BigInt.from(0x01000193)) &
                BigInt.from(0xffffffff))
            .toInt(),
      );
    }
  });
  test(
    'new deals agree across runtimes; legacy web arithmetic remains readable',
    () {
      int seed(RoundSeedAlgorithm algorithm) =>
          ClassicHareegMatchFlow(
                setup: ClassicHareegSetup.defaults(),
                rules: ClassicHareegRules.defaults(),
                scores: {for (final seat in PlayerSeat.values) seat: 0},
                activeSeats: PlayerSeat.values,
                currentStarter: PlayerSeat.south,
                roundNumber: 1,
                roundSeedAlgorithm: algorithm,
              )
              .nextRoundSnapshotFor(
                roundResult: const RoundProgressResult(
                  type: RoundOutcomeType.normalFinish,
                  winner: PlayerSeat.south,
                  remainingCardCounts: {
                    PlayerSeat.south: 0,
                    PlayerSeat.east: 8,
                    PlayerSeat.north: 9,
                    PlayerSeat.west: 10,
                  },
                ),
              )!
              .seed!;
      expect(seed(RoundSeedAlgorithm.exact32), 1394977655);
      expect(seed(RoundSeedAlgorithm.legacyWeb), 3274259660);
    },
  );
}
