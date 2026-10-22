import 'http_text_client_native.dart'
    if (dart.library.js_interop) 'http_text_client_web.dart';

/// A plain-text HTTP response: status code and decoded body.
class HttpTextResponse {
  /// Creates a response.
  const HttpTextResponse({required this.statusCode, this.body = ''});

  /// HTTP status code.
  final int statusCode;

  /// UTF-8 decoded body. Empty when the status was not a success, because
  /// the update flow never reads an error body.
  final String body;
}

/// Performs a GET of [uri] with [headers], failing after [timeout].
///
/// The seam the update channels fetch through, so tests hand in canned
/// responses instead of reaching the network.
typedef HttpGetText =
    Future<HttpTextResponse> Function(
      Uri uri, {
      Map<String, String> headers,
      Duration timeout,
    });

/// The platform's GET: `dart:io` `HttpClient` on native, an always-failing
/// stub on web (the web build never checks for updates).
Future<HttpTextResponse> platformHttpGetText(
  Uri uri, {
  Map<String, String> headers = const {},
  Duration timeout = const Duration(seconds: 8),
}) => httpGetTextImpl(uri, headers: headers, timeout: timeout);
