import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
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
    test('first launch checks, offers, and caches the release', () async {
      final offered = await service().startupCheck(autoCheckEnabled: true);

      expect(offered?.tag, 'v1.0.0-alpha.13');
      expect(channel.fetchCount, 1);
      final cache = await UpdateCacheRepository(store: store).load();
      expect(cache.lastCheckedAt, now);
      expect(cache.lastSeenRelease?.tag, 'v1.0.0-alpha.13');
    });

    test(
      'within 24 hours answers from the cache without the network',
      () async {
        await service().startupCheck(autoCheckEnabled: true);
        now = now.add(const Duration(hours: 23));
        channel.release = fakeRelease('v1.0.0-alpha.14');

        final offered = await service().startupCheck(autoCheckEnabled: true);

        expect(channel.fetchCount, 1);
        expect(offered?.tag, 'v1.0.0-alpha.13');
      },
    );

    test('after 24 hours checks again', () async {
      await service().startupCheck(autoCheckEnabled: true);
      now = now.add(const Duration(hours: 24, minutes: 1));
      channel.release = fakeRelease('v1.0.0-alpha.14');

      final offered = await service().startupCheck(autoCheckEnabled: true);

      expect(channel.fetchCount, 2);
      expect(offered?.tag, 'v1.0.0-alpha.14');
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
      expect(offered?.tag, 'v1.0.0-alpha.13');
    });

    test('a failed check still offers a release cached earlier', () async {
      await service().startupCheck(autoCheckEnabled: true);
      now = now.add(const Duration(days: 2));
      channel.failure = const UpdateCheckException(
        UpdateCheckFailureKind.network,
      );

      final offered = await service().startupCheck(autoCheckEnabled: true);

      expect(offered?.tag, 'v1.0.0-alpha.13');
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
      channel.release = fakeRelease('v1.0.0-alpha.14');
      final newer = await service().startupCheck(
        autoCheckEnabled: true,
        skippedVersion: '1.0.0-alpha.13',
      );
      expect(newer?.tag, 'v1.0.0-alpha.14');
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
    });

    test('reports up to date and could-not-check', () async {
      expect(
        await service(installed: '1.0.0-alpha.13').checkNow(),
        isA<UpdateCheckUpToDate>(),
      );
      channel.release = null;
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
      expect(cache.lastSeenRelease, isNull);
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
