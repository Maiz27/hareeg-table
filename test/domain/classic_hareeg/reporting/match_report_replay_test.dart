import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/classic_hareeg_match_report.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_recorder.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_report_replay.dart';

import '../../../scenario/classic_hareeg_match_driver.dart';

const _app = MatchReportAppMetadata(
  appId: 'com.maiz27.hareegtable',
  appName: 'Hareeg Table',
  version: '1.0.0-alpha.test',
  buildNumber: '42',
);

void main() {
  group('Match report replay', () {
    test('a recorded match replays to the same final state', () {
      final captured = _recordEndedMatch();
      final report = captured.report;
      expect(report.transcript, isNotNull);

      final result = replayMatchReport(report);

      expect(
        result.status,
        MatchReportReplayStatus.matched,
        reason: 'replay mismatches: ${result.mismatches.join("; ")}',
      );
      expect(result.matches, isTrue);
      expect(result.reconstructed, isNotNull);
    });

    test('replay survives a JSON round-trip of the report', () {
      final captured = _recordEndedMatch();
      final decoded = ClassicHareegMatchReport.fromJson(
        captured.report.toJson(),
      );

      final result = replayMatchReport(decoded);

      expect(result.matches, isTrue,
          reason: result.mismatches.join('; '));
    });

    test('a divergent reported snapshot yields a useful mismatch summary', () {
      final captured = _recordEndedMatch();
      // Tamper with the reported snapshot so the reconstructed state cannot
      // match: bump the round number and corrupt a score.
      final tampered = _withTamperedSnapshot(captured.report);

      final result = replayMatchReport(tampered);

      expect(result.status, MatchReportReplayStatus.mismatch);
      expect(result.mismatches, isNotEmpty);
      expect(
        result.mismatches.any((line) => line.startsWith('round:')),
        isTrue,
        reason: 'mismatch summary should call out the diverging round',
      );
    });

    test('reports without a transcript are inspect-only', () {
      final report = ClassicHareegMatchReport.active(
        app: _app,
        platform: 'windows',
        generatedAt: DateTime.utc(2026, 6, 9),
        snapshot: _recordEndedMatch().report.snapshot,
      );

      final result = replayMatchReport(report);

      expect(result.status, MatchReportReplayStatus.noTranscript);
      expect(result.matches, isFalse);
      expect(result.note, isNotNull);
    });
  });
}

class _Captured {
  _Captured(this.report);
  final ClassicHareegMatchReport report;
}

/// Drives a match to a natural finish while recording, and builds a completed
/// report whose snapshot is the final round-over state.
_Captured _recordEndedMatch() {
  final setup = ClassicHareegSetup.defaults().copyWith(
    cpuDifficulty: CpuDifficulty.expert,
    tableStrictness: TableStrictness.standard,
  );
  for (var seed = 1; seed <= 60; seed++) {
    final recorder = MatchRecorder();
    final run = ClassicHareegMatchDriver().run(
      setup: setup,
      seed: seed,
      recorder: recorder,
    );
    if (!run.endedNaturally) {
      continue;
    }
    final lastRound = run.rounds.last;
    final report = ClassicHareegMatchReport.completed(
      app: _app,
      platform: 'windows',
      generatedAt: DateTime.utc(2026, 6, 9, 10),
      snapshot: lastRound.snapshotAtRoundOver,
      roundResult: lastRound.result!,
      matchProgress: lastRound.progress!,
      diagnostics: recorder.diagnostics,
      transcript: recorder.transcript,
    );
    return _Captured(report);
  }
  fail('No converging seed ended a match within 60 tries.');
}

ClassicHareegMatchReport _withTamperedSnapshot(ClassicHareegMatchReport base) {
  final json = base.toJson();
  final snapshot = json['snapshot']! as Map<String, Object?>;
  snapshot['roundNumber'] = base.snapshot.roundNumber + 5;
  return ClassicHareegMatchReport.fromJson(json);
}
