import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../domain/classic_hareeg/reporting/classic_hareeg_match_report.dart';

/// MIME type used for exported match reports.
const matchReportMimeType = 'application/json';

/// Current Flutter target platform label for report metadata.
String currentMatchReportPlatform() => defaultTargetPlatform.name;

/// Copies report text to a destination.
abstract interface class MatchReportClipboardGateway {
  /// Copies [text].
  Future<void> copyText(String text);
}

/// Clipboard gateway backed by Flutter platform services.
class SystemMatchReportClipboardGateway implements MatchReportClipboardGateway {
  /// Creates a system clipboard gateway.
  const SystemMatchReportClipboardGateway();

  @override
  Future<void> copyText(String text) {
    return Clipboard.setData(ClipboardData(text: text));
  }
}

/// Shares report text as an exportable file/text payload.
abstract interface class MatchReportShareGateway {
  /// Shares [text] using [fileName] and [mimeType].
  Future<void> shareText({
    required String fileName,
    required String text,
    required String mimeType,
  });
}

/// Callback used by the native share adapter.
typedef SharePlusShareCallback =
    Future<ShareResult> Function(ShareParams params);

/// Native share gateway backed by the platform share sheet.
class SharePlusMatchReportShareGateway implements MatchReportShareGateway {
  /// Creates a native share gateway.
  const SharePlusMatchReportShareGateway({
    SharePlusShareCallback? shareCallback,
  }) : _shareCallback = shareCallback;

  final SharePlusShareCallback? _shareCallback;

  @override
  Future<void> shareText({
    required String fileName,
    required String text,
    required String mimeType,
  }) async {
    final share = _shareCallback ?? SharePlus.instance.share;
    await share(
      ShareParams(
        title: fileName,
        subject: fileName,
        files: [XFile.fromData(utf8.encode(text), mimeType: mimeType)],
        fileNameOverrides: [fileName],
      ),
    );
  }
}

/// Share gateway used by tests and unsupported builds to force copy fallback.
class UnavailableMatchReportShareGateway implements MatchReportShareGateway {
  /// Creates an unavailable share gateway.
  const UnavailableMatchReportShareGateway();

  @override
  Future<void> shareText({
    required String fileName,
    required String text,
    required String mimeType,
  }) {
    throw const MatchReportShareUnavailableException();
  }
}

/// Raised when file sharing is not available on the current build.
class MatchReportShareUnavailableException implements Exception {
  /// Creates a share-unavailable exception.
  const MatchReportShareUnavailableException();

  @override
  String toString() => 'Match report file sharing is unavailable.';
}

/// Result of attempting to share a match report.
class MatchReportShareAttempt {
  /// Creates a share attempt result.
  const MatchReportShareAttempt._({required this.shared, this.error});

  /// Successful share attempt.
  const MatchReportShareAttempt.shared() : this._(shared: true);

  /// Failed share attempt with copy fallback available.
  const MatchReportShareAttempt.copyFallback(Object error)
    : this._(shared: false, error: error);

  /// Whether platform sharing completed.
  final bool shared;

  /// Error that made the copy fallback necessary.
  final Object? error;
}

/// Encodes, shares, and copies match reports.
class MatchReportExporter {
  /// Creates a match report exporter.
  const MatchReportExporter({
    this.shareGateway = const SharePlusMatchReportShareGateway(),
    this.clipboardGateway = const SystemMatchReportClipboardGateway(),
  });

  static const _jsonEncoder = JsonEncoder.withIndent('  ');

  /// Platform share adapter.
  final MatchReportShareGateway shareGateway;

  /// Clipboard adapter.
  final MatchReportClipboardGateway clipboardGateway;

  /// Encodes [report] to pretty JSON.
  String encode(ClassicHareegMatchReport report) {
    return _jsonEncoder.convert(report.toJson());
  }

  /// Attempts to share [report], returning a copy-fallback result on failure.
  Future<MatchReportShareAttempt> share(ClassicHareegMatchReport report) async {
    final text = encode(report);
    try {
      await shareGateway.shareText(
        fileName: fileNameFor(report),
        text: text,
        mimeType: matchReportMimeType,
      );
      return const MatchReportShareAttempt.shared();
    } on Object catch (error) {
      return MatchReportShareAttempt.copyFallback(error);
    }
  }

  /// Copies [report] JSON to the clipboard.
  Future<void> copy(ClassicHareegMatchReport report) {
    return clipboardGateway.copyText(encode(report));
  }

  /// Stable export file name for [report].
  String fileNameFor(ClassicHareegMatchReport report) {
    final timestamp = report.generatedAt
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '-');
    return 'hareeg-match-report-${report.stage.name}-$timestamp.json';
  }
}
