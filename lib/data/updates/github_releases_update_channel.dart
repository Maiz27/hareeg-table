import 'dart:convert';

import '../../domain/updates/app_release.dart';
import '../../domain/updates/app_version.dart';
import 'http_text_client.dart';
import 'update_channel.dart';

/// Update channel backed by the GitHub releases of `Maiz27/hareeg-table`.
///
/// Every release so far is marked pre-release, and GitHub's `releases/latest`
/// skips pre-releases, so this lists the most recent releases and picks the
/// newest non-draft one by version order instead.
class GitHubReleasesUpdateChannel implements UpdateChannel {
  /// Creates the GitHub channel. [httpGet] defaults to the platform client.
  GitHubReleasesUpdateChannel({
    HttpGetText? httpGet,
    this.timeout = const Duration(seconds: 8),
  }) : _httpGet = httpGet ?? platformHttpGetText;

  /// The releases listing the channel reads.
  static final releasesUri = Uri.parse(
    'https://api.github.com/repos/Maiz27/hareeg-table/releases?per_page=10',
  );

  /// Request headers. Unauthenticated; the User-Agent is required by GitHub
  /// and names the app, nothing about the player.
  static const requestHeaders = {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'hareeg-table-update-check',
  };

  final HttpGetText _httpGet;

  /// Overall request timeout.
  final Duration timeout;

  @override
  bool get reportsVersions => true;

  @override
  Uri? get storeListingUrl => null;

  @override
  Future<AppRelease?> fetchLatestRelease() async {
    final HttpTextResponse response;
    try {
      response = await _httpGet(
        releasesUri,
        headers: requestHeaders,
        timeout: timeout,
      );
    } on UpdateCheckException {
      rethrow;
    } catch (error) {
      throw UpdateCheckException(UpdateCheckFailureKind.network, error);
    }
    final status = response.statusCode;
    if (status == 403 || status == 429) {
      throw UpdateCheckException(UpdateCheckFailureKind.rateLimited, status);
    }
    if (status < 200 || status >= 300) {
      throw UpdateCheckException(UpdateCheckFailureKind.http, status);
    }
    try {
      return parseLatestRelease(jsonDecode(response.body));
    } on FormatException catch (error) {
      throw UpdateCheckException(UpdateCheckFailureKind.malformed, error);
    }
  }

  /// Picks the newest non-draft release from a decoded releases listing.
  ///
  /// Returns null when the listing holds no usable release. Throws
  /// [FormatException] when [decoded] is not a listing at all.
  static AppRelease? parseLatestRelease(Object? decoded) {
    if (decoded is! List) {
      throw const FormatException('Expected a list of releases.');
    }
    AppRelease? newest;
    for (final entry in decoded) {
      final release = _parseRelease(entry);
      if (release == null) continue;
      if (newest == null || release.version.isNewerThan(newest.version)) {
        newest = release;
      }
    }
    return newest;
  }

  static AppRelease? _parseRelease(Object? entry) {
    if (entry is! Map) return null;
    if (entry['draft'] == true) return null;
    final tag = entry['tag_name'];
    final htmlUrl = entry['html_url'];
    if (tag is! String || htmlUrl is! String) return null;
    final version = AppVersion.tryParse(tag);
    final notesUrl = Uri.tryParse(htmlUrl);
    if (version == null || notesUrl == null) return null;
    final body = entry['body'];
    final published = entry['published_at'];
    return AppRelease(
      tag: tag,
      version: version,
      releaseNotesUrl: notesUrl,
      downloadUrl: _androidAssetUrl(entry['assets'], version),
      notes: body is String ? body : '',
      publishedAt: published is String ? DateTime.tryParse(published) : null,
    );
  }

  /// The release's Android APK: `hareeg-table-v<version>-android.apk` by
  /// name, else any asset ending in `-android.apk`, else none.
  static Uri? _androidAssetUrl(Object? assets, AppVersion version) {
    if (assets is! List) return null;
    final expectedName = 'hareeg-table-v$version-android.apk';
    Uri? fallback;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is! String || url is! String) continue;
      final uri = Uri.tryParse(url);
      if (uri == null) continue;
      if (name == expectedName) return uri;
      if (name.endsWith('-android.apk')) fallback ??= uri;
    }
    return fallback;
  }
}
