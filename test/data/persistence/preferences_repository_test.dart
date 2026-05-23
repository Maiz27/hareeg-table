import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/key_value_store.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/ui/core/motion/motion_speed.dart';
import 'package:hareeg_table/ui/core/theme/table_surface_theme.dart';

void main() {
  group('LocalPreferencesRepository', () {
    test('returns defaults when no preferences are saved', () async {
      final repository = LocalPreferencesRepository(store: _MemoryStore());

      final preferences = await repository.loadPreferences();

      expect(preferences.setup.cpuDifficulty, CpuDifficulty.casual);
      expect(preferences.setup.rulePreset, RulePreset.assisted);
      expect(preferences.handSortMode, HandSortMode.byRank);
      expect(preferences.motionSpeed, MotionSpeed.normal);
      expect(preferences.fastCpuTurns, isTrue);
      expect(preferences.reducedMotion, isFalse);
      expect(preferences.soundEnabled, isTrue);
      expect(preferences.language, AppLanguage.english);
      expect(preferences.highContrastCards, isFalse);
      expect(preferences.tableSurfaceTheme, TableSurfaceTheme.sandline);
    });

    test('saves and restores setup and display preferences', () async {
      final store = _MemoryStore();
      final repository = LocalPreferencesRepository(store: store);
      final saved = GamePreferences.defaults().copyWith(
        setup: ClassicHareegSetup.defaults().copyWith(
          cpuDifficulty: CpuDifficulty.expert,
          openingRequirement: 75,
          deckCount: 3,
          jokerCount: 4,
          fiftyTimerSeconds: 6,
          rulePreset: RulePreset.hardTable17,
        ),
        handSortMode: HandSortMode.bySuit,
        motionSpeed: MotionSpeed.reduced,
        fastCpuTurns: false,
        soundEnabled: false,
        memoryJokerDisplay: true,
        language: AppLanguage.arabic,
        highContrastCards: true,
        tableSurfaceTheme: TableSurfaceTheme.wood,
      );

      await repository.savePreferences(saved);

      final restored = await repository.loadPreferences();
      expect(restored.setup.cpuDifficulty, CpuDifficulty.expert);
      expect(restored.setup.openingRequirement, 75);
      expect(restored.setup.deckCount, 3);
      expect(restored.setup.jokerCount, 4);
      expect(restored.setup.fiftyTimerSeconds, 6);
      expect(restored.setup.rulePreset, RulePreset.hardTable17);
      expect(restored.handSortMode, HandSortMode.bySuit);
      expect(restored.motionSpeed, MotionSpeed.reduced);
      expect(restored.fastCpuTurns, isFalse);
      expect(restored.reducedMotion, isTrue);
      expect(restored.soundEnabled, isFalse);
      expect(restored.memoryJokerDisplay, isTrue);
      expect(restored.language, AppLanguage.arabic);
      expect(restored.highContrastCards, isTrue);
      expect(restored.tableSurfaceTheme, TableSurfaceTheme.wood);
    });

    test('legacy saved silent defaults migrate to sound on once', () async {
      final store = _MemoryStore()
        ..values['preferences.v1'] =
            '{"soundEnabled":false,"autoSort":false,"fastCpuTurns":false}';
      final repository = LocalPreferencesRepository(store: store);

      final restored = await repository.loadPreferences();

      expect(restored.soundEnabled, isTrue);
      expect(restored.handSortMode, HandSortMode.manual);
      expect(restored.fastCpuTurns, isFalse);
    });

    test('legacy autoSort=true migrates to byRank', () async {
      final store = _MemoryStore()
        ..values['preferences.v1'] = '{"autoSort":true}';
      final repository = LocalPreferencesRepository(store: store);

      final restored = await repository.loadPreferences();

      expect(restored.handSortMode, HandSortMode.byRank);
    });

    test('saved handSortMode overrides legacy autoSort', () async {
      final store = _MemoryStore()
        ..values['preferences.v1'] =
            '{"autoSort":true,"handSortMode":"bySuit"}';
      final repository = LocalPreferencesRepository(store: store);

      final restored = await repository.loadPreferences();

      expect(restored.handSortMode, HandSortMode.bySuit);
    });

    test(
      'saved sound off is preserved after the audio-default migration',
      () async {
        final store = _MemoryStore()
          ..values['preferences.v1'] =
              '{"soundEnabled":false,"soundDefaultsVersion":1}';
        final repository = LocalPreferencesRepository(store: store);

        final restored = await repository.loadPreferences();

        expect(restored.soundEnabled, isFalse);
      },
    );

    test('invalid saved preferences fall back to defaults', () async {
      final store = _MemoryStore()..values['preferences.v1'] = '{';
      final repository = LocalPreferencesRepository(store: store);

      final preferences = await repository.loadPreferences();

      expect(preferences.setup.rulePreset, RulePreset.assisted);
      expect(store.values.containsKey('preferences.v1'), isFalse);
    });

    test('method-channel store falls back in memory on desktop', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });
      final store = MethodChannelKeyValueStore(
        channel: const MethodChannel('hareeg_table/test_missing_desktop'),
      );

      await store.saveString('key', 'value');

      expect(await store.loadString('key'), 'value');
    });

    test('method-channel store rethrows missing mobile plugins', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });
      final store = MethodChannelKeyValueStore(
        channel: const MethodChannel('hareeg_table/test_missing_mobile'),
      );

      expect(
        () => store.loadString('key'),
        throwsA(isA<MissingPluginException>()),
      );
    });
  });
}

class _MemoryStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> loadString(String key) async => values[key];

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> saveString(String key, String value) async {
    values[key] = value;
  }
}
