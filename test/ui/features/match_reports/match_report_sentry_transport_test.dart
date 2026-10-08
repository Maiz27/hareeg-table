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
    test('turns off PII, sessions, client reports, screenshots, print and '
        'native breadcrumbs and native capture', () {
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
      expect(options.enableAutoNativeBreadcrumbs, isFalse);
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

    test('drops every breadcrumb, including native system events', () {
      final event = SentryEvent(
        breadcrumbs: [
          Breadcrumb(
            type: 'system',
            category: 'device.event',
            data: {
              'action': 'android.intent.action.TIMEZONE_CHANGED',
              'time-zone': 'Africa/Khartoum',
            },
          ),
          Breadcrumb(category: 'ui.click', message: 'view.tapped'),
        ],
        tags: {'source': 'user_report'},
      );

      final scrubbed = gateAndScrubSentryEvent(event, Hint(), _Gate())!;

      expect(scrubbed.breadcrumbs, isNull);
      final wire = jsonEncode(scrubbed.toJson());
      expect(wire, isNot(contains('Africa/Khartoum')));
      expect(wire, isNot(contains('breadcrumbs')));
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

    test('native-merged device, os and app contexts keep only allowlisted '
        'fields', () {
      // The shape Android's native scope merges into every Dart event: keys
      // the Dart model does not know end up in `unknown` and would serialize.
      final event = SentryEvent(
        contexts: Contexts.fromJson({
          'device': {
            'id': 'install-uuid-1234',
            'name': 'My Phone',
            'timezone': 'Africa/Khartoum',
            'language': 'ar',
            'locale': 'ar_SD',
            'connection_type': 'wifi',
            'boot_time': '2026-01-02T03:04:05.000Z',
            'battery_level': 42.0,
            'device_unique_identifier': 'dui-5678',
            'model': 'Pixel 7',
            'manufacturer': 'Google',
            'brand': 'google',
            'family': 'Pixel',
            'memory_size': 8000000000,
            'screen_width_pixels': 1080,
            'screen_height_pixels': 2400,
            'orientation': 'portrait',
          },
          'os': {
            'name': 'Android',
            'version': '14',
            'kernel_version': 'kernel-secret-build',
            'rooted': false,
            'locale': 'ar_SD',
          },
          'app': {
            'app_version': '1.0.0',
            'app_build': '12',
            'device_app_hash': 'hash-9999',
            'app_start_time': '2026-01-02T03:04:05.000Z',
          },
          'culture': {'locale': 'ar-SD', 'timezone': 'Africa/Khartoum'},
          'accessibility': {'bold_text': true},
          'custom_native': {'installation': 'install-uuid-1234'},
        }),
        tags: {'source': 'user_report'},
      );

      final scrubbed = gateAndScrubSentryEvent(event, Hint(), _Gate())!;

      final wire = jsonEncode(scrubbed.toJson());
      for (final leaked in [
        'install-uuid-1234',
        'dui-5678',
        'My Phone',
        'Africa/Khartoum',
        'ar_SD',
        'ar-SD',
        '"language"',
        '"locale"',
        '"timezone"',
        '"id"',
        'boot_time',
        'connection_type',
        'battery_level',
        'kernel-secret-build',
        'rooted',
        'hash-9999',
        'app_start_time',
        'accessibility',
        'custom_native',
      ]) {
        expect(wire, isNot(contains(leaked)), reason: leaked);
      }
      final device = scrubbed.contexts.device!;
      expect(device.model, 'Pixel 7');
      expect(device.manufacturer, 'Google');
      expect(device.brand, 'google');
      expect(device.family, 'Pixel');
      expect(device.memorySize, 8000000000);
      expect(device.screenWidthPixels, 1080);
      expect(device.orientation, SentryOrientation.portrait);
      expect(scrubbed.contexts.operatingSystem!.name, 'Android');
      expect(scrubbed.contexts.operatingSystem!.version, '14');
      expect(scrubbed.contexts.app!.version, '1.0.0');
      expect(scrubbed.contexts.app!.build, '12');
      expect(
        scrubbed.contexts.keys.where((k) => scrubbed.contexts[k] != null),
        {
          'device',
          'os',
          'app',
          // Contexts always holds an (empty) runtimes list.
          'runtimes',
        },
      );
      expect(scrubbed.contexts.runtimes, isEmpty);
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
