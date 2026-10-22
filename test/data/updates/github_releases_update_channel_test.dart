import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/updates/github_releases_update_channel.dart';
import 'package:hareeg_table/data/updates/http_text_client.dart';
import 'package:hareeg_table/data/updates/play_store_update_channel.dart';
import 'package:hareeg_table/data/updates/update_channel.dart';

void main() {
  final fixture = File(
    'test/fixtures/updates/github_releases.json',
  ).readAsStringSync();

  GitHubReleasesUpdateChannel channelAnswering(
    HttpTextResponse Function(Uri uri, Map<String, String> headers) answer,
  ) {
    return GitHubReleasesUpdateChannel(
      httpGet:
          (
            Uri uri, {
            Map<String, String> headers = const {},
            Duration timeout = const Duration(seconds: 8),
          }) async => answer(uri, headers),
    );
  }

  group('GitHubReleasesUpdateChannel', () {
    test('picks the newest non-draft release by version order', () async {
      Uri? requested;
      Map<String, String>? sentHeaders;
      final channel = channelAnswering((uri, headers) {
        requested = uri;
        sentHeaders = headers;
        return HttpTextResponse(statusCode: 200, body: fixture);
      });

      final release = await channel.fetchLatestRelease();

      expect(
        requested.toString(),
        'https://api.github.com/repos/Maiz27/hareeg-table/releases?per_page=10',
      );
      expect(sentHeaders?['Accept'], 'application/vnd.github+json');
      expect(sentHeaders?['User-Agent'], isNotEmpty);
      // alpha.14 is a draft, "nightly" does not parse, and alpha.9 sits
      // above alpha.13 in the listing but is older by version order.
      expect(release, isNotNull);
      expect(release!.tag, 'v1.0.0-alpha.13');
      expect(release.version.toString(), '1.0.0-alpha.13');
      expect(
        release.downloadUrl.toString(),
        'https://github.com/Maiz27/hareeg-table/releases/download/'
        'v1.0.0-alpha.13/hareeg-table-v1.0.0-alpha.13-android.apk',
      );
      expect(
        release.releaseNotesUrl.toString(),
        'https://github.com/Maiz27/hareeg-table/releases/tag/v1.0.0-alpha.13',
      );
      expect(release.publishedAt, DateTime.utc(2026, 10, 20, 9, 12, 30));
      expect(release.notesSummary, startsWith('1.0.0-alpha.13 (2026-10-20)'));
      expect(release.notesSummary, isNot(contains('**')));
      expect(release.notesSummary, isNot(contains('](')));
    });

    test('a release without an APK asset has no download url', () {
      final release = GitHubReleasesUpdateChannel.parseLatestRelease(
        jsonDecode(
          '[{"tag_name":"v2.0.0","html_url":"https://x.test/r","draft":false,'
          '"assets":[{"name":"notes.txt","browser_download_url":"https://x.test/n"}]}]',
        ),
      );
      expect(release!.downloadUrl, isNull);
    });

    test('an empty listing reports no release', () {
      expect(GitHubReleasesUpdateChannel.parseLatestRelease(const []), isNull);
    });

    test('rate limiting, HTTP errors and bad bodies are typed failures', () {
      Future<UpdateCheckFailureKind> kindFor(HttpTextResponse response) async {
        try {
          await channelAnswering((_, _) => response).fetchLatestRelease();
        } on UpdateCheckException catch (error) {
          return error.kind;
        }
        fail('expected a failure');
      }

      expect(
        kindFor(const HttpTextResponse(statusCode: 403)),
        completion(UpdateCheckFailureKind.rateLimited),
      );
      expect(
        kindFor(const HttpTextResponse(statusCode: 429)),
        completion(UpdateCheckFailureKind.rateLimited),
      );
      expect(
        kindFor(const HttpTextResponse(statusCode: 500)),
        completion(UpdateCheckFailureKind.http),
      );
      expect(
        kindFor(const HttpTextResponse(statusCode: 200, body: '{not json')),
        completion(UpdateCheckFailureKind.malformed),
      );
      expect(
        kindFor(const HttpTextResponse(statusCode: 200, body: '{}')),
        completion(UpdateCheckFailureKind.malformed),
      );
    });

    test('a transport error is a network failure', () async {
      final channel = GitHubReleasesUpdateChannel(
        httpGet:
            (
              Uri uri, {
              Map<String, String> headers = const {},
              Duration timeout = const Duration(seconds: 8),
            }) => Future.error(const SocketException('offline')),
      );
      await expectLater(
        channel.fetchLatestRelease(),
        throwsA(
          isA<UpdateCheckException>().having(
            (error) => error.kind,
            'kind',
            UpdateCheckFailureKind.network,
          ),
        ),
      );
    });
  });

  group('channel selection', () {
    test('defaults to GitHub; "play" selects the store stub', () {
      expect(createUpdateChannel(), isA<GitHubReleasesUpdateChannel>());
      expect(
        createUpdateChannel(name: 'github'),
        isA<GitHubReleasesUpdateChannel>(),
      );
      expect(createUpdateChannel(name: 'play'), isA<PlayStoreUpdateChannel>());
      expect(
        createUpdateChannel(name: 'unknown'),
        isA<GitHubReleasesUpdateChannel>(),
      );
    });

    test('the Play stub reports no version and opens the listing', () async {
      const channel = PlayStoreUpdateChannel();
      expect(channel.reportsVersions, isFalse);
      expect(await channel.fetchLatestRelease(), isNull);
      expect(
        channel.storeListingUrl.toString(),
        'https://play.google.com/store/apps/details?id=com.maiz27.hareegtable',
      );
    });
  });
}
