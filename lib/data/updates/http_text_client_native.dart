import 'dart:convert';
import 'dart:io';

import 'http_text_client.dart';

/// Native GET through `dart:io` [HttpClient], bounded by [timeout] overall.
Future<HttpTextResponse> httpGetTextImpl(
  Uri uri, {
  required Map<String, String> headers,
  required Duration timeout,
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    return await () async {
      final request = await client.getUrl(uri);
      headers.forEach(request.headers.set);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return HttpTextResponse(statusCode: response.statusCode);
      }
      final body = await response.transform(utf8.decoder).join();
      return HttpTextResponse(statusCode: response.statusCode, body: body);
    }().timeout(timeout);
  } finally {
    client.close(force: true);
  }
}
