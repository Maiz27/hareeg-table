import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';

import 'classic_hareeg_match_driver.dart';

/// Family B — golden match transcripts.
///
/// For a few curated (config, seed) tuples this records a canonical, fully
/// deterministic fingerprint of game flow — every action, every round result,
/// and the running scores — and asserts it never changes. Unlike the invariant
/// sweep (which proves *consistency*), a golden proves *stability*: if a feature
/// silently alters how a game plays out, the transcript diffs and you must
/// consciously accept the new golden.
///
/// Requires engine reproducibility (same seed ⇒ same game). The determinism
/// guard in match_determinism_test.dart protects that precondition.
///
/// Regenerate after an intentional behaviour change:
///
/// ```
/// UPDATE_GOLDENS=1 flutter test test/scenario/golden_match_test.dart
/// ```
///
/// Brittle by design, so the curated set is intentionally small.
void main() {
  const actionBudget = 150;

  final goldenDir = Directory('test/scenario/golden');
  final shouldUpdate = Platform.environment['UPDATE_GOLDENS'] == '1';

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
  ];

  String seatTag(PlayerSeat s) => s.name[0].toUpperCase();

  String scoresTag(Map<PlayerSeat, int> scores) {
    return PlayerSeat.values
        .map((s) => '${seatTag(s)}=${scores[s] ?? 0}')
        .join(',');
  }

  String transcriptFor(ClassicHareegSetup setup, int seed) {
    final lines = <String>[];
    final report = ClassicHareegMatchDriver(actionLimit: actionBudget).run(
      setup: setup,
      seed: seed,
      onStep: (step) {
        lines.add(
          'r${step.roundNumber}#${step.actionIndex} ${seatTag(step.seat)} '
          '${step.phase.name} ${step.actionId}',
        );
      },
      onRoundEnd: (r) {
        lines.add(
          '=ROUND ${r.roundNumber} ${r.result?.type.name ?? "?"} '
          'winner=${r.result?.winner == null ? "-" : seatTag(r.result!.winner!)} '
          'scores=${scoresTag(r.scoresAfter)}',
        );
      },
    );
    lines.add(
      '=MATCH stop=${report.stopReason.name} '
      'winner=${report.winner == null ? "-" : seatTag(report.winner!)} '
      'actions=${report.totalActions} rounds=${report.rounds.length}',
    );
    return '${lines.join('\n')}\n';
  }

  String normalizeTranscriptLineEndings(String transcript) {
    return transcript.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  group('Golden match transcripts', () {
    for (final c in cases) {
      test(c.name, () {
        final actual = transcriptFor(c.setup, c.seed);
        final file = File('${goldenDir.path}/${c.name}.txt');

        if (shouldUpdate) {
          goldenDir.createSync(recursive: true);
          file.writeAsStringSync(actual);
          // ignore: avoid_print
          print('Updated golden: ${file.path}');
          return;
        }

        expect(
          file.existsSync(),
          isTrue,
          reason:
              'missing golden ${file.path}; regenerate with '
              'UPDATE_GOLDENS=1 flutter test test/scenario/golden_match_test.dart',
        );
        expect(
          actual,
          normalizeTranscriptLineEndings(file.readAsStringSync()),
          reason:
              'game flow changed for ${c.name}. If this change is '
              'intentional, regenerate with UPDATE_GOLDENS=1.',
        );
      });
    }
  });
}
