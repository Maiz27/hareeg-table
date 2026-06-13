import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'match_report_exporter.dart';

/// Web share gateway that saves the report as a file download.
///
/// `share_plus` has no real file-share target on most desktop browsers, so the
/// "Share report" action would otherwise dead-end there. On web we instead do
/// what the user actually wants — get the JSON onto their disk — by building an
/// in-memory [web.Blob], handing it an object URL, and clicking a hidden anchor
/// with a `download` attribute. No network, no plugin.
class WebDownloadMatchReportShareGateway implements MatchReportShareGateway {
  /// Creates a browser-download share gateway.
  const WebDownloadMatchReportShareGateway();

  @override
  Future<void> shareText({
    required String fileName,
    required String text,
    required String mimeType,
  }) async {
    final bytes = utf8.encode(text);
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor =
        web.document.createElement('a') as web.HTMLAnchorElement
          ..href = url
          ..download = fileName
          ..style.display = 'none';
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
  }
}
