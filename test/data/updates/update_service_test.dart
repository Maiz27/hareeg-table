import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/data/updates/github_releases_update_channel.dart';
import 'package:hareeg_table/data/updates/http_text_client.dart';
import 'package:hareeg_table/data/updates/play_store_update_channel.dart';
import 'package:hareeg_table/data/updates/update_cache_repository.dart';
import 'package:hareeg_table/data/updates/update_channel.dart';
import 'package:hareeg_table/data/updates/update_service.dart';

import '../../support/test_fixtures.dart';
import 'update_test_doubles.dart';

void main() {
  late MemoryKeyValueStore store;
  late FakeUpdateChannel channel;
  late DateTime now;

  UpdateService service({
    String installed = '1.0.0-alpha.12',
    UpdateChannel? overrideChannel,
    bool supported = true,
  }) {
    return UpdateService(
      channel: overrideChannel ?? channel,
      installedVersion: FakeInstalledVersionSource(installed),
      cache: UpdateCacheRepository(store: store),
      supported: supported,
      clock: () => now,
    );
  }

  setUp(() {
    store = MemoryKeyValueStore();
    channel = FakeUpdateChannel(release: fakeRelease('v1.0.0-alpha.13'));
    now = DateTime.utc(2026, 10, 22, 8);
  });

  group('startupCheck cadence', () {
    test('first launch checks, offers, and caches the listing', () async {
      final offered = await service().startupCheck(autoCheckEnabled: true);

      expect(offered?.newest.tag, 'v1.0.0-alpha.13');
      expect(channel.fetchCount, 1);
      final cache = await UpdateCacheRepository(store: store).load();
      expect(cache.lastCheckedAt, now);
      expect(cache.releases.map((r) => r.tag), ['v1.0.0-alpha.13']);
    });

    test(
      'within 24 hours answers from the cache without the network',
      () async {
        await service().startupCheck(autoCheckEnabled: true);
        now = now.add(const Duration(hours: 23));
        channel.releases = [fakeRelease('v1.0.0-alpha.14')];

        final offered = await service().startupCheck(autoCheckEnabled: true);

        expect(channel.fetchCount, 1);
        expect(offered?.newest.tag, 'v1.0.0-alpha.13');
      },
    );

    test('after 24 hours checks again', () async {
      await service().startupCheck(autoCheckEnabled: true);
      now = now.add(const Duration(hours: 24, minutes: 1));
      channel.releases = [fakeRelease('v1.0.0-alpha.14')];

      final offered = await service().startupCheck(autoCheckEnabled: true);

      expect(channel.fetchCount, 2);
      expect(offered?.newest.tag, 'v1.0.0-alpha.14');
    });

    test('offers every release newer than the installed one', () async {
      channel.releases = [
        fakeRelease('v1.0.0-alpha.14'),
        fakeRelease('v1.0.0-alpha.13'),
        fakeRelease('v1.0.0-alpha.12'),
        fakeRelease('v1.0.0-alpha.11'),
      ];

      final offered = await service(
        installed: '1.0.0-alpha.11',
      ).startupCheck(autoCheckEnabled: true);

      expect(offered?.newest.tag, 'v1.0.0-alpha.14');
      expect(offered?.releases.map((r) => r.tag), [
        'v1.0.0-alpha.14',
        'v1.0.0-alpha.13',
        'v1.0.0-alpha.12',
      ]);
      expect(offered?.hasOlderUnlisted, isFalse);
    });

    group('a listing older than the install', () {
      GitHubReleasesUpdateChannel githubAnswering(int count) {
        final body = jsonEncode([
          for (var n = 13 + count - 1; n >= 13; n--)
            {
              'tag_name': 'v1.0.0-alpha.$n',
              'html_url': 'https://x.test/$n',
              'draft': false,
              'body': '* change $n',
            },
        ]);
        return GitHubReleasesUpdateChannel(
          httpGet:
              (
                Uri uri, {
                Map<String, String> headers = const {},
                Duration timeout = const Duration(seconds: 8),
              }) async => HttpTextResponse(statusCode: 200, body: body),
        );
      }

      test('a full page is marked truncated and flags missing ones', () async {
        final offered = await service(
          installed: '1.0.0-alpha.5',
          overrideChannel: githubAnswering(
            GitHubReleasesUpdateChannel.pageSize,
          ),
        ).startupCheck(autoCheckEnabled: true);

        expect(offered?.releases, hasLength(20));
        expect(offered?.hasOlderUnlisted, isTrue);
        final cache = await UpdateCacheRepository(store: store).load();
        expect(cache.mayBeTruncated, isTrue);
      });

      test('a short listing is complete and never flags', () async {
        final offered = await service(
          installed: '1.0.0-alpha.5',
          overrideChannel: githubAnswering(3),
        ).startupCheck(autoCheckEnabled: true);

        expect(offered?.releases, hasLength(3));
        expect(offered?.hasOlderUnlisted, isFalse);
      });
    });

    test('the cached listing is offered against a later install', () async {
      channel.releases = [
        fakeRelease('v1.0.0-alpha.14'),
        fakeRelease('v1.0.0-alpha.13'),
      ];
      await service().startupCheck(autoCheckEnabled: true);
      now = now.add(const Duration(hours: 1));

      // The player installed alpha.13 meanwhile; no new network check.
      final offered = await service(
        installed: '1.0.0-alpha.13',
      ).startupCheck(autoCheckEnabled: true);

      expect(channel.fetchCount, 1);
      expect(offered?.releases.map((r) => r.tag), ['v1.0.0-alpha.14']);
    });

    test('a failed check is silent, not recorded, and retried', () async {
      channel.failure = const UpdateCheckException(
        UpdateCheckFailureKind.rateLimited,
      );
      expect(await service().startupCheck(autoCheckEnabled: true), isNull);
      expect(store.values.containsKey(UpdateCacheRepository.key), isFalse);

      channel.failure = null;
      now = now.add(const Duration(minutes: 5));
      final offered = await service().startupCheck(autoCheckEnabled: true);
      expect(channel.fetchCount, 2);
      expect(offered?.newest.tag, 'v1.0.0-alpha.13');
    });

    test('a failed check still offers a release cached earlier', () async {
      await service().startupCheck(autoCheckEnabled: true);
      now = now.add(const Duration(days: 2));
      channel.failure = const UpdateCheckException(
        UpdateCheckFailureKind.network,
      );

      final offered = await service().startupCheck(autoCheckEnabled: true);

      expect(offered?.newest.tag, 'v1.0.0-alpha.13');
    });

    test('switched off: no network and no prompt', () async {
      expect(await service().startupCheck(autoCheckEnabled: false), isNull);
      expect(channel.fetchCount, 0);
    });

    test('a skipped version is not offered; a newer one is', () async {
      final skipped = await service().startupCheck(
        autoCheckEnabled: true,
        skippedVersion: '1.0.0-alpha.13',
      );
      expect(skipped, isNull);

      now = now.add(const Duration(days: 1));
      channel.releases = [
        fakeRelease('v1.0.0-alpha.14'),
        fakeRelease('v1.0.0-alpha.13'),
      ];
      final newer = await service().startupCheck(
        autoCheckEnabled: true,
        skippedVersion: '1.0.0-alpha.13',
      );
      expect(newer?.newest.tag, 'v1.0.0-alpha.14');
      // The skipped release still ships with the update, so its notes stay.
      expect(newer?.releases.map((r) => r.tag), [
        'v1.0.0-alpha.14',
        'v1.0.0-alpha.13',
      ]);
    });

    test('already on the newest release: nothing to offer', () async {
      final offered = await service(
        installed: '1.0.0-alpha.13',
      ).startupCheck(autoCheckEnabled: true);
      expect(offered, isNull);
    });

    test('unsupported platform (web) is a no-op', () async {
      final offered = await service(
        supported: false,
      ).startupCheck(autoCheckEnabled: true);
      expect(offered, isNull);
      expect(channel.fetchCount, 0);
      expect(
        await service(supported: false).checkNow(),
        isA<UpdateCheckFailed>(),
      );
    });
  });

  group('checkNow', () {
    test('always hits the network, even right after a check', () async {
      await service().startupCheck(autoCheckEnabled: true);
      final result = await service().checkNow();
      expect(channel.fetchCount, 2);
      expect(result, isA<UpdateCheckAvailable>());
      expect(
        (result as UpdateCheckAvailable).offer.newest.tag,
        'v1.0.0-alpha.13',
      );
    });

    test('reports up to date and could-not-check', () async {
      expect(
        await service(installed: '1.0.0-alpha.13').checkNow(),
        isA<UpdateCheckUpToDate>(),
      );
      channel.releases = [];
      expect(await service().checkNow(), isA<UpdateCheckUpToDate>());
      channel.failure = const UpdateCheckException(
        UpdateCheckFailureKind.network,
      );
      final failed = await service().checkNow();
      expect(failed, isA<UpdateCheckFailed>());
      expect(
        (failed as UpdateCheckFailed).kind,
        UpdateCheckFailureKind.network,
      );
    });

    test('the Play channel is store-managed', () async {
      final result = await service(
        overrideChannel: const PlayStoreUpdateChannel(),
      ).checkNow();
      expect(result, isA<UpdateCheckStoreManaged>());
      expect(
        await service(
          overrideChannel: const PlayStoreUpdateChannel(),
        ).startupCheck(autoCheckEnabled: true),
        isNull,
      );
    });
  });

  group('UpdateCacheRepository', () {
    test('a corrupt cache reads as empty', () async {
      store.values[UpdateCacheRepository.key] = '{nope';
      final cache = await UpdateCacheRepository(store: store).load();
      expect(cache.lastCheckedAt, isNull);
      expect(cache.releases, isEmpty);
    });

    test('v2 round-trips the whole listing, newest first', () async {
      final repository = UpdateCacheRepository(store: store);
      await repository.save(
        UpdateCache(
          lastCheckedAt: now,
          mayBeTruncated: true,
          releases: [
            fakeRelease('v1.0.0-alpha.13', notes: '### Features\n* new'),
            fakeRelease('v1.0.0-alpha.12'),
          ],
        ),
      );

      expect(UpdateCacheRepository.key, 'updates.cache.v2');
      final cache = await repository.load();
      expect(cache.lastCheckedAt, now);
      expect(cache.releases.map((r) => r.tag), [
        'v1.0.0-alpha.13',
        'v1.0.0-alpha.12',
      ]);
      expect(cache.mayBeTruncated, isTrue);
      expect(cache.releases.first.notes, '### Features\n* new');
      expect(
        cache.releases.first.downloadUrl.toString(),
        'https://example.test/download/v1.0.0-alpha.13.apk',
      );
    });

    test('unreadable entries are dropped and the rest sorted', () async {
      store.values[UpdateCacheRepository.key] =
          '{"releases":[{"tag":"v1.0.0-alpha.9","releaseNotesUrl":"https://x.test/9"},'
          '{"tag":"nightly","releaseNotesUrl":"https://x.test/n"},'
          '{"tag":"v1.0.0-alpha.13","releaseNotesUrl":"https://x.test/13"},'
          '"garbage"]}';
      final cache = await UpdateCacheRepository(store: store).load();
      expect(cache.lastCheckedAt, isNull);
      // No flag stored reads as a complete listing.
      expect(cache.mayBeTruncated, isFalse);
      expect(cache.releases.map((r) => r.tag), [
        'v1.0.0-alpha.13',
        'v1.0.0-alpha.9',
      ]);
    });

    test('a v1 entry is ignored: the next launch checks again', () async {
      store.values['updates.cache.v1'] =
          '{"lastCheckedAt":"${now.toIso8601String()}",'
          '"lastSeenRelease":{"tag":"v1.0.0-alpha.13",'
          '"releaseNotesUrl":"https://x.test/13"}}';

      final cache = await UpdateCacheRepository(store: store).load();
      expect(cache.lastCheckedAt, isNull);
      expect(cache.releases, isEmpty);

      final offered = await service().startupCheck(autoCheckEnabled: true);
      expect(channel.fetchCount, 1);
      expect(offered?.newest.tag, 'v1.0.0-alpha.13');
    });
  });

  group('GamePreferences update settings', () {
    test('default on, nothing skipped', () {
      final defaults = GamePreferences.defaults();
      expect(defaults.updateCheckEnabled, isTrue);
      expect(defaults.skippedUpdateVersion, isNull);
    });

    test('round-trip through JSON and the repository', () async {
      final repository = LocalPreferencesRepository(store: store);
      await repository.savePreferences(
        GamePreferences.defaults().copyWith(
          updateCheckEnabled: false,
          skippedUpdateVersion: '1.0.0-alpha.13',
        ),
      );
      final restored = await repository.loadPreferences();
      expect(restored.updateCheckEnabled, isFalse);
      expect(restored.skippedUpdateVersion, '1.0.0-alpha.13');
    });

    test('older saves without the fields get the defaults', () {
      final json = GamePreferences.defaults().toJson()
        ..remove('updateCheckEnabled')
        ..remove('skippedUpdateVersion');
      final restored = GamePreferences.fromJson(json);
      expect(restored.updateCheckEnabled, isTrue);
      expect(restored.skippedUpdateVersion, isNull);
    });
  });
}
