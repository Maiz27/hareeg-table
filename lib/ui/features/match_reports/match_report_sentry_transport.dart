import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'match_report_diagnostics.dart';

/// [DiagnosticsTransport] backed by `sentry_flutter`.
///
/// The only place the app touches the Sentry SDK. Started lazily once consent
/// allows it and closed on opt-out, so an opted-out player never has a running
/// SDK (native crash handlers included) that could transmit anything.
class SentryDiagnosticsTransport implements DiagnosticsTransport {
  /// Creates a Sentry transport for [dsn].
  const SentryDiagnosticsTransport({required this.dsn, required this.release});

  /// Sentry project DSN.
  final String dsn;

  /// Release identifier.
  final String release;

  @override
  Future<void> start(DiagnosticsGate gate) {
    return SentryFlutter.init(
      (options) => configureSentryOptions(
        options,
        dsn: dsn,
        release: release,
        gate: gate,
      ),
    );
  }

  @override
  Future<void> stop() => Sentry.close();

  @override
  Future<bool> send(DiagnosticsEvent event) async {
    final attachment = event.attachment;
    final id = await Sentry.captureEvent(
      SentryEvent(
        message: event.error == null ? SentryMessage(event.message) : null,
        throwable: event.error,
        level: _levelFor(event.level),
        tags: event.allTags,
        fingerprint: event.fingerprint,
      ),
      stackTrace: event.stackTrace,
      hint: attachment == null
          ? null
          : Hint.withAttachment(sentryAttachmentFor(attachment)),
    );
    return id != const SentryId.empty();
  }

  static SentryLevel _levelFor(DiagnosticsLevel level) => switch (level) {
    DiagnosticsLevel.info => SentryLevel.info,
    DiagnosticsLevel.warning => SentryLevel.warning,
    DiagnosticsLevel.error => SentryLevel.error,
  };
}

/// Converts a [DiagnosticsAttachment] into a Sentry attachment.
SentryAttachment sentryAttachmentFor(DiagnosticsAttachment attachment) {
  return SentryAttachment.fromIntList(
    utf8.encode(attachment.text),
    attachment.fileName,
    contentType: attachment.contentType,
  );
}

/// Applies the privacy-preserving Sentry configuration.
///
/// - `sendDefaultPii` off, so the SDK attaches no user, IP or device name.
/// - Only error events: no sessions, performance traces, client reports,
///   screenshots or `print` breadcrumbs (view hierarchies are off by default).
/// - Native crash/ANR capture off, so every event passes through
///   [gateAndScrubSentryEvent] (native events would bypass it).
void configureSentryOptions(
  SentryFlutterOptions options, {
  required String dsn,
  required String release,
  required DiagnosticsGate gate,
}) {
  options
    ..dsn = dsn
    ..release = release
    ..environment = kReleaseMode
        ? 'production'
        : (kProfileMode ? 'profile' : 'debug')
    ..sendDefaultPii = false
    ..enableAutoSessionTracking = false
    ..sendClientReports = false
    ..tracesSampleRate = null
    // View hierarchies are already off by default (the toggle is
    // experimental API, so it is left untouched).
    ..attachScreenshot = false
    ..enablePrintBreadcrumbs = false
    ..enableNativeCrashHandling = false
    ..anrEnabled = false
    ..beforeSend = (event, hint) => gateAndScrubSentryEvent(event, hint, gate);
}

/// Last check before any event leaves the device.
///
/// Drops everything when [gate] no longer allows transmission, strips user,
/// IP, device name/identifier, server name and locale/culture data, and gives
/// SDK-captured errors (FlutterError / platform dispatcher handlers, which do
/// not go through [DiagnosticsTransport.send]) the `source: uncaught_error`
/// tag and the in-flight match report.
SentryEvent? gateAndScrubSentryEvent(
  SentryEvent event,
  Hint hint,
  DiagnosticsGate gate,
) {
  if (!gate.isTransmissionAllowed) {
    return null;
  }
  event
    ..user = null
    ..serverName = null;
  event.contexts.remove(SentryCulture.type);
  final device = event.contexts.device;
  if (device != null) {
    device
      ..name = null
      ..deviceUniqueIdentifier = null;
  }
  final tags = event.tags;
  if (tags == null || !tags.containsKey('source')) {
    event.tags = {
      ...?tags,
      'source': DiagnosticsSource.uncaughtError.tag,
      'trigger': 'sdk_handler',
    };
    if (hint.attachments.isEmpty) {
      final report = gate.liveReportAttachment();
      if (report != null) {
        hint.attachments.add(sentryAttachmentFor(report));
      }
    }
  }
  return event;
}
