import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';

import 'classic_hareeg_match_driver.dart';

/// Family B — match determinism guard.
///
/// Matches now replay identically from a `(seed, setup)` both within AND across
/// processes: the whole game is deterministic, including the next-round deal
/// (seeded by `_nextRoundSeed` in `classic_hareeg_match_flow.dart` from the
/// completed round's stable integer state, never per-process hashCodes). That
/// cross-process reproducibility is what makes the committed transcripts in
/// `golden_match_test.dart` viable and lets a player replay a reported game from
/// its seed.
///
/// This guard asserts the in-process half of that property — running the same
/// `(seed, setup)` twice in one process produces a byte-identical transcript —
/// which catches a regression that reintroduces non-determinism from leaked
/// mutable/static state, the most damaging kind because it makes every other
/// test flaky. The golden transcripts guard the cross-process half.
void main() {
  final cases = <({String name, ClassicHareegSetup setup, int seed})>[
    (
      name: 'casual_table_jok2_seed11',
      setup: ClassicHareegSetup.defaults().copyWith(
        cpuDifficulty: CpuDifficulty.casual,
        tableStrictness: TableStrictness.table,
        jokerCount: 2,
      ),
      seed: 11,
    ),
    (
      name: 'skilled_standard_jok2_seed7',
      setup: ClassicHareegSetup.defaults().copyWith(
        cpuDifficulty: CpuDifficulty.skilled,
        tableStrictness: TableStrictness.standard,
        jokerCount: 2,
      ),
      seed: 7,
    ),
    (
      name: 'expert_table_jok4_seed3',
      setup: ClassicHareegSetup.defaults().copyWith(
        cpuDifficulty: CpuDifficulty.expert,
        tableStrictness: TableStrictness.table,
        jokerCount: 4,
      ),
      seed: 3,
    ),
  ];

  String transcriptFor(ClassicHareegSetup setup, int seed) {
    final lines = <String>[];
    final report = ClassicHareegMatchDriver(actionLimit: 200).run(
      setup: setup,
      seed: seed,
      onStep: (s) => lines.add('${s.actionIndex}:${s.seat.name}:${s.actionId}'),
      onRoundEnd: (r) => lines.add(
        'R${r.roundNumber}:${r.result?.type.name}:'
        '${PlayerSeat.values.map((s) => r.scoresAfter[s] ?? 0).join(",")}',
      ),
    );
    lines.add('END:${report.stopReason.name}:${report.totalActions}');
    return lines.join('\n');
  }

  group('Match determinism (within process)', () {
    for (final c in cases) {
      test(
        '${c.name} replays identically',
        () {
          final first = transcriptFor(c.setup, c.seed);
          final second = transcriptFor(c.setup, c.seed);
          expect(
            second,
            first,
            reason: 'the same seed+setup must replay identically within a '
                'process; a diff means non-determinism leaked from shared '
                'mutable/static state',
          );
        },
      );
    }
  });
}
