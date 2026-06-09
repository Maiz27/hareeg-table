import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/classic_hareeg_match_report.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_report_replay.dart';

/// Exercises the developer replay harness against committed report fixtures —
/// the same path `tools/match_report_replay.dart` runs. See that tool's
/// docstring for command-line usage.
void main() {
  const fixtureDir = 'test/fixtures/reports';

  ClassicHareegMatchReport loadReport(String name) {
    final raw = File('$fixtureDir/$name').readAsStringSync();
    final json = jsonDecode(raw) as Map<String, Object?>;
    return ClassicHareegMatchReport.fromJson(json);
  }

  test('known-good report fixture replays to its reported state', () {
    final report = loadReport('good_active_match.hareeg-report.json');
    expect(report.transcript, isNotNull);
    expect(report.diagnostics, isNotNull);

    final result = replayMatchReport(report);

    expect(
      result.matches,
      isTrue,
      reason: 'fixture replay mismatches: ${result.mismatches.join("; ")}',
    );
  });

  test('unsupported-version fixture fails with a clear version error', () {
    expect(
      () => loadReport('unsupported_version.hareeg-report.json'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Unsupported schema version 2'),
        ),
      ),
    );
  });

  test('malformed fixture fails with a clear invalid-report error', () {
    expect(
      () => loadReport('malformed.hareeg-report.json'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Invalid match report'),
        ),
      ),
    );
  });
}
