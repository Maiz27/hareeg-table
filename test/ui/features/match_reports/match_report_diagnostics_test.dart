import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/classic_hareeg_match_report.dart';
import 'package:hareeg_table/ui/features/match_reports/match_report_diagnostics.dart';
import 'package:hareeg_table/ui/features/match_reports/match_report_exporter.dart';

import '../../../support/fake_diagnostics.dart';

void main() {
  group('MatchReportDiagnostics without a DSN', () {
    test('never starts the transport and sends nothing', () async {
      final transport = FakeDiagnosticsTransport();
      final diagnostics = fakeDiagnostics(transport, dsn: '');

      await diagnostics.applyConsent(allowed: true);

      expect(diagnostics.isAvailable, isFalse);
      expect(diagnostics.canSend, isFalse);
      expect(transport.starts, 0);
      expect(await diagnostics.sendUserReport(sampleMatchReport()), isFalse);
      expect(await diagnostics.captureBackstop(trigger: 'x'), isFalse);
      expect(await diagnostics.captureError(StateError('boom'), null), isFalse);
      expect(transport.sent, isEmpty);
    });
  });

  group('MatchReportDiagnostics consent gating', () {
    test('sends nothing before consent is applied', () async {
      final transport = FakeDiagnosticsTransport();
      final diagnostics = fakeDiagnostics(transport);

      expect(diagnostics.isAvailable, isTrue);
      expect(diagnostics.canSend, isFalse);
      expect(await diagnostics.sendUserReport(sampleMatchReport()), isFalse);
      expect(transport.starts, 0);
      expect(transport.sent, isEmpty);
    });

    test('opt-out never starts the transport', () async {
      final transport = FakeDiagnosticsTransport();
      final diagnostics = fakeDiagnostics(transport);

      await diagnostics.applyConsent(allowed: false);

      expect(transport.starts, 0);
      expect(diagnostics.isTransmissionAllowed, isFalse);
      expect(await diagnostics.captureBackstop(trigger: 'x'), isFalse);
      expect(transport.sent, isEmpty);
    });

    test('opting out after opting in stops the transport and blocks every '
        'later send', () async {
      final transport = FakeDiagnosticsTransport();
      final diagnostics = fakeDiagnostics(transport);

      await diagnostics.applyConsent(allowed: true);
      expect(transport.isRunning, isTrue);
      expect(diagnostics.canSend, isTrue);

      await diagnostics.applyConsent(allowed: false);

      expect(transport.stops, 1);
      expect(transport.isRunning, isFalse);
      expect(diagnostics.isTransmissionAllowed, isFalse);
      expect(await diagnostics.sendUserReport(sampleMatchReport()), isFalse);
      expect(await diagnostics.captureError(StateError('boom'), null), isFalse);
      expect(transport.sent, isEmpty);
    });

    test('a quick toggle settles on the last answer', () async {
      final transport = FakeDiagnosticsTransport();
      final diagnostics = fakeDiagnostics(transport);

      final first = diagnostics.applyConsent(allowed: true);
      final second = diagnostics.applyConsent(allowed: false);
      await Future.wait([first, second]);

      expect(transport.isRunning, isFalse);
      expect(diagnostics.canSend, isFalse);
    });

    test('the gate handed to the transport follows consent live', () async {
      final transport = FakeDiagnosticsTransport();
      final diagnostics = fakeDiagnostics(transport);

      await diagnostics.applyConsent(allowed: true);
      final gate = transport.gate!;
      expect(gate.isTransmissionAllowed, isTrue);

      await diagnostics.applyConsent(allowed: false);
      expect(gate.isTransmissionAllowed, isFalse);
    });
  });

  group('MatchReportDiagnostics events', () {
    late FakeDiagnosticsTransport transport;
    late LiveMatchReportSource live;
    late MatchReportDiagnostics diagnostics;

    setUp(() async {
      transport = FakeDiagnosticsTransport();
      live = LiveMatchReportSource();
      diagnostics = fakeDiagnostics(transport, liveMatch: live);
      await diagnostics.applyConsent(allowed: true);
    });

    test('a player report is tagged user_report and carries the exported '
        'report file', () async {
      final report = sampleMatchReport();
      const exporter = MatchReportExporter();

      expect(await diagnostics.sendUserReport(report), isTrue);

      final event = transport.sent.single;
      expect(event.source, DiagnosticsSource.userReport);
      expect(event.allTags['source'], 'user_report');
      expect(event.allTags['report_stage'], 'active');
      expect(event.level, DiagnosticsLevel.info);
      expect(event.attachment!.fileName, exporter.fileNameFor(report));
      expect(event.attachment!.text, exporter.encode(report));
      expect(event.attachment!.contentType, matchReportMimeType);
    });

    test('a backstop capture attaches the live match report', () async {
      final report = sampleMatchReport(seed: 23);
      live.attach(Object(), () => report);

      expect(
        await diagnostics.captureBackstop(
          trigger: 'livelock_forced_draw',
          tags: {'round': '3'},
        ),
        isTrue,
      );

      final event = transport.sent.single;
      expect(event.source, DiagnosticsSource.backstop);
      expect(event.allTags, {
        'round': '3',
        'trigger': 'livelock_forced_draw',
        'source': 'auto_backstop',
      });
      expect(event.fingerprint, ['liveness-backstop', 'livelock_forced_draw']);
      final attached = ClassicHareegMatchReport.fromJson(
        _jsonMap(jsonDecode(event.attachment!.text)),
      );
      expect(attached.seed, 23);
    });

    test(
      'an error capture carries the error, stack, and live report',
      () async {
        live.attach(Object(), () => sampleMatchReport(seed: 29));
        final error = StateError('boom');
        final stack = StackTrace.current;

        expect(
          await diagnostics.captureError(
            error,
            stack,
            trigger: 'cpu_turn_error',
          ),
          isTrue,
        );

        final event = transport.sent.single;
        expect(event.source, DiagnosticsSource.uncaughtError);
        expect(event.error, same(error));
        expect(event.stackTrace, same(stack));
        expect(event.allTags['trigger'], 'cpu_turn_error');
        expect(event.attachment, isNotNull);
      },
    );

    test('an error with no live match still sends, without a report', () async {
      expect(await diagnostics.captureError(StateError('boom'), null), isTrue);
      expect(transport.sent.single.attachment, isNull);
    });

    test('a failing transport reports false instead of throwing', () async {
      transport.throwOnSend = true;
      expect(await diagnostics.sendUserReport(sampleMatchReport()), isFalse);
    });

    test('a rejected event reports false', () async {
      transport.accept = false;
      expect(await diagnostics.sendUserReport(sampleMatchReport()), isFalse);
    });
  });

  group('LiveMatchReportSource', () {
    test('a stale owner detaching does not clear a newer registration', () {
      final live = LiveMatchReportSource();
      final older = Object();
      final newer = Object();
      live.attach(older, sampleMatchReport);
      live.attach(newer, sampleMatchReport);

      live.detach(older);
      expect(live.hasLiveMatch, isTrue);

      live.detach(newer);
      expect(live.hasLiveMatch, isFalse);
      expect(live.current(), isNull);
    });

    test('a builder that throws yields no report rather than an error', () {
      final live = LiveMatchReportSource()
        ..attach(Object(), () => throw StateError('mid-deal'));
      expect(live.current(), isNull);
    });
  });
}

Map<String, Object?> _jsonMap(Object? value) {
  final map = value as Map<String, dynamic>;
  return {for (final entry in map.entries) entry.key: entry.value};
}
