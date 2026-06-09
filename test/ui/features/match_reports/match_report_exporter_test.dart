import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/classic_hareeg_match_report.dart';
import 'package:hareeg_table/ui/features/match_reports/match_report_exporter.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  group('MatchReportExporter', () {
    test(
      'offers clipboard fallback when file sharing is unavailable',
      () async {
        final clipboard = _RecordingClipboardGateway();
        final exporter = MatchReportExporter(
          shareGateway: const UnavailableMatchReportShareGateway(),
          clipboardGateway: clipboard,
        );
        final report = _report();

        final attempt = await exporter.share(report);
        await exporter.copy(report);

        expect(attempt.shared, isFalse);
        expect(attempt.error, isA<MatchReportShareUnavailableException>());
        expect(clipboard.text, isNotNull);
        final decoded = ClassicHareegMatchReport.fromJson(
          _jsonMap(jsonDecode(clipboard.text!)),
        );
        expect(decoded.stage, MatchReportStage.active);
        expect(decoded.seed, 19);
      },
    );

    test('shares report JSON as a named native file payload', () async {
      ShareParams? capturedParams;
      final gateway = SharePlusMatchReportShareGateway(
        shareCallback: (params) async {
          capturedParams = params;
          return const ShareResult('test-share', ShareResultStatus.success);
        },
      );
      final exporter = MatchReportExporter(shareGateway: gateway);
      final report = _report();

      final attempt = await exporter.share(report);

      expect(attempt.shared, isTrue);
      final params = capturedParams;
      expect(params, isNotNull);
      expect(params!.fileNameOverrides, [exporter.fileNameFor(report)]);
      expect(params.files, hasLength(1));
      expect(params.files!.single.mimeType, matchReportMimeType);
      final sharedJson = await params.files!.single.readAsString();
      final decoded = ClassicHareegMatchReport.fromJson(
        _jsonMap(jsonDecode(sharedJson)),
      );
      expect(decoded.stage, MatchReportStage.active);
      expect(decoded.seed, 19);
    });
  });
}

ClassicHareegMatchReport _report() {
  final setup = ClassicHareegSetup.defaults();
  final round = ClassicHareegRound.deal(setup: setup, seed: 19);
  final snapshot = ClassicHareegMatchSnapshot(
    setup: setup,
    hands: round.hands,
    seed: round.seed,
    stock: round.stock,
    discardPile: round.discardPile,
    starter: round.starter,
    currentSeat: round.currentSeat,
    turnPhase: round.turnPhase,
    savedAt: DateTime.utc(2026, 6, 9),
  );
  return ClassicHareegMatchReport.active(
    app: const MatchReportAppMetadata(
      appId: 'com.maiz27.hareegtable',
      appName: 'Hareeg Table',
      version: '1.0.0-alpha.test',
      buildNumber: '42',
    ),
    platform: 'test',
    generatedAt: DateTime.utc(2026, 6, 9),
    snapshot: snapshot,
  );
}

Map<String, Object?> _jsonMap(Object? value) {
  final map = value as Map<String, dynamic>;
  return {for (final entry in map.entries) entry.key: entry.value};
}

class _RecordingClipboardGateway implements MatchReportClipboardGateway {
  String? text;

  @override
  Future<void> copyText(String text) async {
    this.text = text;
  }
}
