import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../app/app_metadata.dart';
import '../../../domain/classic_hareeg/reporting/classic_hareeg_match_report.dart';
import 'match_report_exporter.dart';
import 'match_report_sentry_transport.dart';

/// Where a diagnostics event came from. Sent as the `source` tag so triage can
/// tell player reports from automatic captures.
enum DiagnosticsSource {
  /// The player pressed "Report table issue" / "Export".
  userReport('user_report'),

  /// A freeze/liveness backstop tripped during play.
  backstop('auto_backstop'),

  /// An error escaped to a global handler or the CPU loop.
  uncaughtError('uncaught_error');

  const DiagnosticsSource(this.tag);

  /// Wire value of the `source` tag.
  final String tag;
}

/// Severity of a diagnostics event.
enum DiagnosticsLevel {
  /// Player-initiated report.
  info,

  /// Recovered stall.
  warning,

  /// Thrown error.
  error,
}

/// A text file attached to a diagnostics event.
@immutable
class DiagnosticsAttachment {
  /// Creates an attachment.
  const DiagnosticsAttachment({
    required this.fileName,
    required this.text,
    this.contentType = matchReportMimeType,
  });

  /// Attachment file name.
  final String fileName;

  /// Attachment contents.
  final String text;

  /// MIME type.
  final String contentType;
}

/// One event handed to a [DiagnosticsTransport].
@immutable
class DiagnosticsEvent {
  /// Creates a diagnostics event.
  const DiagnosticsEvent({
    required this.source,
    required this.message,
    required this.level,
    this.error,
    this.stackTrace,
    this.tags = const {},
    this.fingerprint,
    this.attachment,
  });

  /// Origin, sent as the `source` tag.
  final DiagnosticsSource source;

  /// Human-readable summary (used when there is no [error]).
  final String message;

  /// Severity.
  final DiagnosticsLevel level;

  /// Thrown error, when this event reports one.
  final Object? error;

  /// Stack trace for [error].
  final StackTrace? stackTrace;

  /// Extra tags, merged under the `source` tag.
  final Map<String, String> tags;

  /// Grouping fingerprint, or null for the backend's default grouping.
  final List<String>? fingerprint;

  /// Replayable match report, when one could be built.
  final DiagnosticsAttachment? attachment;

  /// All tags sent with this event, `source` included.
  Map<String, String> get allTags => {...tags, 'source': source.tag};
}

/// What a transport needs from the gateway while it runs: the live consent
/// gate and the in-flight match report for errors it captures by itself.
abstract interface class DiagnosticsGate {
  /// Whether transmission is currently allowed. Checked again for every event
  /// right before it leaves, so an opt-out wins over anything already queued.
  bool get isTransmissionAllowed;

  /// The in-flight match report as an attachment, or null when no live match
  /// is registered or the report cannot be built.
  DiagnosticsAttachment? liveReportAttachment();
}

/// Backend that actually delivers diagnostics events (Sentry in production).
abstract interface class DiagnosticsTransport {
  /// Starts the backend. Only called once consent allows transmission.
  Future<void> start(DiagnosticsGate gate);

  /// Stops the backend so nothing more can be transmitted.
  Future<void> stop();

  /// Sends [event]; true when it was accepted for delivery (it may still be
  /// queued offline and flushed later).
  Future<bool> send(DiagnosticsEvent event);
}

/// Registry for the match currently on the table.
///
/// Global error handlers and the transport have no widget context, so the game
/// screen registers a builder for its in-flight report here. Only the most
/// recent owner is kept; a stale owner detaching never clears a newer one.
class LiveMatchReportSource {
  /// Creates an empty registry (tests); production uses [instance].
  LiveMatchReportSource();

  /// Process-wide registry.
  static final LiveMatchReportSource instance = LiveMatchReportSource();

  Object? _owner;
  ClassicHareegMatchReport Function()? _build;

  /// Registers [build] as the live report for [owner].
  void attach(Object owner, ClassicHareegMatchReport Function() build) {
    _owner = owner;
    _build = build;
  }

  /// Clears the registration if [owner] still holds it.
  void detach(Object owner) {
    if (identical(_owner, owner)) {
      _owner = null;
      _build = null;
    }
  }

  /// Whether a live match is registered.
  bool get hasLiveMatch => _build != null;

  /// Builds the live report, or null when none is registered or building
  /// fails. Never throws: it runs inside error handlers.
  ClassicHareegMatchReport? current() {
    final build = _build;
    if (build == null) {
      return null;
    }
    try {
      return build();
    } on Object catch (error) {
      debugPrint('[hareeg:diagnostics] Could not build live report: $error');
      return null;
    }
  }
}

/// Consent-gated diagnostics gateway for crash and match reports.
///
/// Sits in the UI/infra layer beside the share/copy gateways and reuses
/// [MatchReportExporter.encode] / [MatchReportExporter.fileNameFor] for the
/// attachment, so the report domain layer stays Flutter- and SDK-free
/// (ADR-0001).
///
/// Nothing is transmitted unless a DSN was compiled in **and** the player's
/// consent allows it. Every public method is safe to call from error handlers:
/// failures are logged and reported as `false`, never thrown.
class MatchReportDiagnostics implements DiagnosticsGate {
  /// Creates a gateway.
  MatchReportDiagnostics({
    required String dsn,
    required DiagnosticsTransport transport,
    LiveMatchReportSource? liveMatch,
    MatchReportExporter exporter = const MatchReportExporter(),
  }) : _dsn = dsn,
       _transport = transport,
       _liveMatch = liveMatch ?? LiveMatchReportSource.instance,
       _exporter = exporter;

  /// Process-wide gateway wired to Sentry and the build-time DSN.
  static final MatchReportDiagnostics instance = MatchReportDiagnostics(
    dsn: HareegAppMetadata.sentryDsn,
    transport: const SentryDiagnosticsTransport(
      dsn: HareegAppMetadata.sentryDsn,
      release: HareegAppMetadata.diagnosticsRelease,
    ),
  );

  final String _dsn;
  final DiagnosticsTransport _transport;
  final LiveMatchReportSource _liveMatch;
  final MatchReportExporter _exporter;

  bool _consented = false;
  bool _started = false;
  Future<void> _consentChange = Future.value();

  /// Whether this build can send diagnostics at all (a DSN was compiled in).
  bool get isAvailable => _dsn.isNotEmpty;

  /// Whether the player's consent currently allows transmission.
  bool get isConsented => _consented;

  /// Whether a report sent now would actually be transmitted.
  bool get canSend => isAvailable && _consented && _started;

  @override
  bool get isTransmissionAllowed => isAvailable && _consented;

  /// Applies the player's consent: starts the transport when allowed, stops it
  /// when not. Calls are serialized so a quick toggle cannot interleave a
  /// start with a stop.
  Future<void> applyConsent({required bool allowed}) {
    _consented = allowed;
    final next = _consentChange.then((_) => _syncTransport());
    _consentChange = next;
    return next;
  }

  Future<void> _syncTransport() async {
    if (!isAvailable) {
      return;
    }
    final wanted = _consented;
    try {
      if (wanted && !_started) {
        await _transport.start(this);
        _started = true;
      } else if (!wanted && _started) {
        _started = false;
        await _transport.stop();
      }
    } on Object catch (error, stackTrace) {
      debugPrint('[hareeg:diagnostics] Consent sync failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// Sends a player-initiated report, tagged `source: user_report`.
  Future<bool> sendUserReport(ClassicHareegMatchReport report) {
    return _send(
      () => DiagnosticsEvent(
        source: DiagnosticsSource.userReport,
        message: 'Player table report',
        level: DiagnosticsLevel.info,
        tags: {'report_stage': report.stage.name},
        attachment: attachmentFor(report),
      ),
    );
  }

  /// Captures a freeze/liveness backstop trip with the in-flight report.
  ///
  /// [trigger] names which backstop fired (it is also the grouping key);
  /// [report] defaults to the registered live match.
  Future<bool> captureBackstop({
    required String trigger,
    ClassicHareegMatchReport? report,
    Map<String, String> tags = const {},
  }) {
    return _send(() {
      final resolved = report ?? _liveMatch.current();
      return DiagnosticsEvent(
        source: DiagnosticsSource.backstop,
        message: 'Liveness backstop tripped: $trigger',
        level: DiagnosticsLevel.warning,
        tags: {...tags, 'trigger': trigger},
        fingerprint: ['liveness-backstop', trigger],
        attachment: resolved == null ? null : attachmentFor(resolved),
      );
    });
  }

  /// Captures a thrown error with the in-flight report attached.
  Future<bool> captureError(
    Object error,
    StackTrace? stackTrace, {
    String trigger = 'uncaught',
  }) {
    return _send(
      () => DiagnosticsEvent(
        source: DiagnosticsSource.uncaughtError,
        message: '$error',
        level: DiagnosticsLevel.error,
        error: error,
        stackTrace: stackTrace,
        tags: {'trigger': trigger},
        attachment: liveReportAttachment(),
      ),
    );
  }

  @override
  DiagnosticsAttachment? liveReportAttachment() {
    final report = _liveMatch.current();
    return report == null ? null : attachmentFor(report);
  }

  /// Encodes [report] as an attachment, exactly as Share/Copy would export it.
  DiagnosticsAttachment attachmentFor(ClassicHareegMatchReport report) {
    return DiagnosticsAttachment(
      fileName: _exporter.fileNameFor(report),
      text: _exporter.encode(report),
    );
  }

  Future<bool> _send(DiagnosticsEvent Function() buildEvent) async {
    if (!canSend) {
      return false;
    }
    try {
      return await _transport.send(buildEvent());
    } on Object catch (error, stackTrace) {
      debugPrint('[hareeg:diagnostics] Send failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }
}
