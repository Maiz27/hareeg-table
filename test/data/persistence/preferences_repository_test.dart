import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
      expect(preferences.autoSort, isTrue);
      expect(preferences.motionSpeed, MotionSpeed.normal);
      expect(preferences.reducedMotion, isFalse);
      expect(preferences.language, AppLanguage.english);
      expect(preferences.highContrastCards, isFalse);
      expect(preferences.tableSurfaceTheme, TableSurfaceTheme.felt);
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
        autoSort: false,
        motionSpeed: MotionSpeed.reduced,
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
      expect(restored.autoSort, isFalse);
      expect(restored.motionSpeed, MotionSpeed.reduced);
      expect(restored.reducedMotion, isTrue);
      expect(restored.memoryJokerDisplay, isTrue);
      expect(restored.language, AppLanguage.arabic);
      expect(restored.highContrastCards, isTrue);
      expect(restored.tableSurfaceTheme, TableSurfaceTheme.wood);
    });

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
