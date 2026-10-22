import 'http_text_client.dart';

/// Web stub. The web build updates itself as a PWA and never checks for a
/// release, so reaching this is a wiring mistake rather than a network state.
Future<HttpTextResponse> httpGetTextImpl(
  Uri uri, {
  required Map<String, String> headers,
  required Duration timeout,
}) {
  return Future.error(
    UnsupportedError('Update checks are not available on web.'),
  );
}
