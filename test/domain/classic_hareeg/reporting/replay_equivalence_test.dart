import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_report_replay.dart';

import '../../../support/completed_match_fixture.dart';

/// Contract C26: `replayTranscript` was reimplemented on top of
/// `MatchReplayTimeline`. This proves the rewrite did not move behaviour.
///
/// The expectations are literal data frozen from the PRE-refactor
/// implementation, before the first product edit of this sprint. They are not
/// recomputed by anything under test, so an implementation that changed both
/// the code and its own expectations could not satisfy them.
void main() {
  final oracle =
      jsonDecode(
            File(
              'test/domain/classic_hareeg/reporting/replay_result_oracle.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  final cases = (oracle['cases']! as List).cast<Map<String, Object?>>();
  // Seeds 13 and 23 converge on the same final round: the next-round seed is
  // derived from standings, not the original deal seed. Their earlier actions
  // differ, so equal terminal boards do not make either frozen case redundant.

  test('the oracle covers six seeds and was not silently emptied', () {
    // A guard against every assertion below passing because the file is a
    // stub: an oracle with no cases would make this suite vacuously green.
    expect(cases, hasLength(6));
    for (final entry in cases) {
      expect(entry['entryCount'], greaterThan(100));
    }
  });

  for (final expected in cases) {
    final seed = expected['seed']! as int;

    test(
      'seed $seed replays exactly as the pre-refactor implementation did',
      () {
        final fixture = buildCompletedMatch(seed: seed);
        final state = fixture.recorderState;
        final transcript = MatchActionTranscript(
          initialSnapshot: state.initialSnapshot!,
          entries: state.entries,
        );

        expect(transcript.entries.length, expected['entryCount']);

        final unchecked = expected['unchecked']! as Map<String, Object?>;
        final actual = replayTranscript(transcript);

        expect(actual.status.name, unchecked['status']);
        expect(
          actual.mismatches,
          (unchecked['mismatches']! as List).cast<String>(),
        );
        expect(actual.matchWinner?.name, unchecked['matchWinner']);

        // Compared through the production comparator rather than by raw JSON:
        // volatile fields such as `savedAt` are deliberately not part of what
        // "the same reconstructed state" means.
        final frozen = ClassicHareegMatchSnapshot.fromJson(
          (unchecked['reconstructed']! as Map).cast<String, Object?>(),
        );
        expect(
          describeSnapshotMismatch(
            expected: frozen,
            actual: actual.reconstructed!,
          ),
          isEmpty,
        );

        final checked =
            expected['checkedAgainstFinalState']! as Map<String, Object?>;
        final verified = replayTranscript(
          transcript,
          expected: fixture.finalState,
        );
        expect(verified.status.name, checked['status']);
        expect(
          verified.mismatches,
          (checked['mismatches']! as List).cast<String>(),
        );
        expect(verified.matchWinner?.name, checked['matchWinner']);
      },
    );
  }

  test('the verifier no longer walks the transcript itself', () {
    // C25: reconstruction has exactly one owner. If these tokens come back,
    // a second replay loop has appeared alongside the timeline's.
    final source = File(
      'lib/domain/classic_hareeg/reporting/match_report_replay.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('applyAction')));
    expect(source, isNot(contains('nextRoundSnapshot')));
    expect(source, isNot(contains('Duration(seconds:')));
    expect(source, isNot(contains('DateTime.utc')));
  });

  test(
    'the replay package applies actions and crosses rounds in one place each',
    () {
      // C63c. The synchronous verifier and the asynchronous viewer must drain
      // the same machine; two call sites would mean two reconstruction rules.
      final directory = Directory('lib/domain/classic_hareeg/replay');
      var applySites = 0;
      var roundSites = 0;
      final files = directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();
      expect(files, isNotEmpty);

      for (final file in files) {
        final source = file.readAsStringSync();
        applySites += '.applyAction('.allMatches(source).length;
        roundSites += '.nextRoundSnapshot('.allMatches(source).length;
      }

      expect(applySites, 1, reason: 'exactly one action-application seam');
      expect(roundSites, 1, reason: 'exactly one round-crossing seam');
    },
  );
}
