import 'dart:convert';
import 'dart:io';

import 'package:hareeg_table/domain/classic_hareeg/reporting/classic_hareeg_match_report.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_report_replay.dart';

/// Developer harness for exported `.hareeg-report.json` match reports.
///
/// Loads a report file, validates its schema version, prints the reported
/// snapshot summary, and — when a transcript is present — replays it against the
/// report's setup and seed, confirming the reconstructed state matches the
/// reported state (or printing a useful mismatch summary).
///
/// Usage:
///
/// ```sh
/// dart run tools/match_report_replay.dart path/to/hareeg-match-report-*.json
/// ```
///
/// Exit codes: 0 = matched / inspected, 1 = mismatch, 2 = unreadable or invalid
/// report.
void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tools/match_report_replay.dart <report.json>',
    );
    exitCode = 2;
    return;
  }

  final file = File(args.single);
  if (!file.existsSync()) {
    stderr.writeln('Report file not found: ${args.single}');
    exitCode = 2;
    return;
  }

  final ClassicHareegMatchReport report;
  try {
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map<String, Object?>) {
      stderr.writeln('Report root is not a JSON object.');
      exitCode = 2;
      return;
    }
    report = ClassicHareegMatchReport.fromJson(json);
  } on FormatException catch (error) {
    // Covers unsupported schema versions and malformed reports — fromJson
    // routes through the versioned decoder, which throws a FormatException.
    stderr.writeln('Invalid match report: ${error.message}');
    exitCode = 2;
    return;
  } on Object catch (error) {
    stderr.writeln('Could not parse match report: $error');
    exitCode = 2;
    return;
  }

  stdout
    ..writeln('Match report')
    ..writeln('  app:       ${report.app.appName} '
        '${report.app.version} (${report.app.buildNumber})')
    ..writeln('  platform:  ${report.platform}')
    ..writeln('  stage:     ${report.stage.name}')
    ..writeln('  round:     ${report.roundNumber}')
    ..writeln('  seat:      ${report.currentSeat.name}')
    ..writeln('  phase:     ${report.turnPhase.name}')
    ..writeln('  seed:      ${report.seed ?? "(none)"}')
    ..writeln('  scores:    ${_scoreLine(report)}')
    ..writeln('  diagnostics: '
        '${report.diagnostics?.events.length ?? 0} events '
        '(${report.diagnostics?.droppedCount ?? 0} dropped)')
    ..writeln('  transcript:  '
        '${report.transcript?.entries.length ?? 0} actions');

  final result = replayMatchReport(report);
  stdout.writeln('');
  switch (result.status) {
    case MatchReportReplayStatus.noTranscript:
      stdout.writeln('No transcript present — snapshot inspected only.');
      exitCode = 0;
    case MatchReportReplayStatus.matched:
      stdout.writeln('Replay OK — reconstructed state matches the report.');
      exitCode = 0;
    case MatchReportReplayStatus.mismatch:
      stdout.writeln('Replay MISMATCH:');
      for (final line in result.mismatches) {
        stdout.writeln('  - $line');
      }
      exitCode = 1;
  }
}

String _scoreLine(ClassicHareegMatchReport report) {
  return report.scores.entries
      .map((entry) => '${entry.key.name}=${entry.value}')
      .join(' ');
}
