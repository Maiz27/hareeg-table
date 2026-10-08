import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/ui/features/match_reports/match_report_diagnostics.dart';
import 'package:hareeg_table/ui/features/match_reports/match_report_sentry_transport.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../support/fake_diagnostics.dart';

/// The Sentry-facing half: options and the last-chance `beforeSend` hook.
/// Nothing here initialises the SDK or touches the network; events are built
/// by hand and run through the hook directly.
void main() {
  group('configureSentryOptions', () {
    test('turns off PII, sessions, client reports, screenshots, print '
        'breadcrumbs and native capture', () {
      final options = SentryFlutterOptions();
      configureSentryOptions(
        options,
        dsn: testSentryDsn,
        release: 'app@1.0.0+1',
        gate: _Gate(allowed: true),
      );

      expect(options.dsn, testSentryDsn);
      expect(options.release, 'app@1.0.0+1');
      expect(options.sendDefaultPii, isFalse);
      expect(options.enableAutoSessionTracking, isFalse);
      expect(options.sendClientReports, isFalse);
      expect(options.tracesSampleRate, isNull);
      expect(options.attachScreenshot, isFalse);
      expect(options.enablePrintBreadcrumbs, isFalse);
      expect(options.enableNativeCrashHandling, isFalse);
      expect(options.anrEnabled, isFalse);
      expect(options.beforeSend, isNotNull);
    });

    test('beforeSend drops every event once the gate closes', () async {
      final gate = _Gate(allowed: true);
      final options = SentryFlutterOptions();
      configureSentryOptions(
        options,
        dsn: testSentryDsn,
        release: 'r',
        gate: gate,
      );

      expect(await options.beforeSend!(SentryEvent(), Hint()), isNotNull);
      gate.allowed = false;
      expect(await options.beforeSend!(SentryEvent(), Hint()), isNull);
    });
  });

  group('gateAndScrubSentryEvent', () {
    test('returns null when transmission is not allowed', () {
      final event = SentryEvent(throwable: StateError('boom'));
      expect(
        gateAndScrubSentryEvent(event, Hint(), _Gate(allowed: false)),
        isNull,
      );
    });

    test('strips user, IP, server name, device name/id and culture', () {
      final event = SentryEvent(
        serverName: 'phone-of-someone',
        user: SentryUser(id: 'u1', ipAddress: '203.0.113.9', name: 'Someone'),
        contexts: Contexts(
          device: SentryDevice(name: 'My Phone', deviceUniqueIdentifier: 'abc'),
          culture: SentryCulture(locale: 'ar-SD', timezone: 'Africa/Khartoum'),
        ),
        tags: {'source': 'user_report'},
      );

      final scrubbed = gateAndScrubSentryEvent(event, Hint(), _Gate())!;

      expect(scrubbed.user, isNull);
      expect(scrubbed.serverName, isNull);
      expect(scrubbed.contexts.culture, isNull);
      expect(scrubbed.contexts.device!.name, isNull);
      expect(scrubbed.contexts.device!.deviceUniqueIdentifier, isNull);
      final wire = jsonEncode(scrubbed.toJson());
      expect(wire, isNot(contains('203.0.113.9')));
      expect(wire, isNot(contains('ar-SD')));
      expect(wire, isNot(contains('My Phone')));
    });

    test('an SDK-captured error is tagged uncaught_error and gets the live '
        'match report attached', () {
      final gate = _Gate(
        live: const DiagnosticsAttachment(fileName: 'r.json', text: '{"a":1}'),
      );
      final event = SentryEvent(throwable: StateError('boom'));
      final hint = Hint();

      final result = gateAndScrubSentryEvent(event, hint, gate)!;

      expect(result.tags!['source'], 'uncaught_error');
      expect(result.tags!['trigger'], 'sdk_handler');
      expect(hint.attachments, hasLength(1));
      expect(hint.attachments.single.filename, 'r.json');
    });

    test('an event the app already tagged keeps its own attachment', () {
      final gate = _Gate(
        live: const DiagnosticsAttachment(fileName: 'live.json', text: '{}'),
      );
      final event = SentryEvent(tags: {'source': 'user_report'});
      final hint = Hint.withAttachment(
        sentryAttachmentFor(
          const DiagnosticsAttachment(fileName: 'mine.json', text: '{}'),
        ),
      );

      final result = gateAndScrubSentryEvent(event, hint, gate)!;

      expect(result.tags, {'source': 'user_report'});
      expect(hint.attachments.map((a) => a.filename), ['mine.json']);
    });
  });
}

class _Gate implements DiagnosticsGate {
  _Gate({this.allowed = true, this.live});

  bool allowed;
  final DiagnosticsAttachment? live;

  @override
  bool get isTransmissionAllowed => allowed;

  @override
  DiagnosticsAttachment? liveReportAttachment() => live;
}
