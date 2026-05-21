import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../ui/core/aids/table_aids.dart';
import '../../ui/core/cards/card_theme_registry.dart';
import '../../ui/core/motion/motion_speed.dart';
import '../../ui/core/theme/table_surface_theme.dart';

/// Player-facing language option.
enum AppLanguage {
  /// English launch language.
  english('English', 'en'),

  /// Arabic language.
  arabic('العربية', 'ar');

  const AppLanguage(this.label, this.code);

  /// Settings label.
  final String label;

  /// Stable locale code.
  final String code;

  /// Parses a saved enum name.
  static AppLanguage fromName(String? name) {
    return _enumByName(AppLanguage.values, name) ?? AppLanguage.english;
  }
}

/// Saved app preferences that can seed new games and table behavior.
class GamePreferences {
  /// Creates app preferences.
  const GamePreferences({
    required this.setup,
    required this.autoSort,
    required this.memoryJokerDisplay,
    required this.language,
    required this.motionSpeed,
    required this.fastCpuTurns,
    required this.hapticsEnabled,
    required this.soundEnabled,
    required this.tableAids,
    required this.cardThemeId,
    required this.highContrastCards,
    required this.tableSurfaceTheme,
  });

  /// Default first-run preferences.
  factory GamePreferences.defaults() {
    return GamePreferences(
      setup: ClassicHareegSetup.defaults(),
      autoSort: true,
      memoryJokerDisplay: false,
      language: AppLanguage.english,
      motionSpeed: MotionSpeed.normal,
      fastCpuTurns: true,
      hapticsEnabled: true,
      soundEnabled: false,
      tableAids: TableAids.guided,
      cardThemeId: CardThemeRegistry.defaultThemeId,
      highContrastCards: false,
      tableSurfaceTheme: TableSurfaceTheme.sandline,
    );
  }

  /// Restores preferences from persisted JSON-compatible data.
  factory GamePreferences.fromJson(Map<String, Object?> json) {
    final defaults = GamePreferences.defaults();
    final setupJson = _asMap(json['setup']);
    final legacyReducedMotion = _asBool(json['reducedMotion']) ?? false;
    final motionSpeed = json.containsKey('motionSpeed')
        ? MotionSpeed.fromName(_asString(json['motionSpeed']))
        : (legacyReducedMotion ? MotionSpeed.reduced : MotionSpeed.normal);
    return GamePreferences(
      setup: setupJson != null
          ? ClassicHareegSetup.fromJson(setupJson)
          : ClassicHareegSetup.defaults(),
      autoSort: _asBool(json['autoSort']) ?? defaults.autoSort,
      memoryJokerDisplay:
          _asBool(json['memoryJokerDisplay']) ?? defaults.memoryJokerDisplay,
      language: AppLanguage.fromName(_asString(json['language'])),
      motionSpeed: motionSpeed,
      fastCpuTurns: _asBool(json['fastCpuTurns']) ?? defaults.fastCpuTurns,
      hapticsEnabled:
          _asBool(json['hapticsEnabled']) ?? defaults.hapticsEnabled,
      soundEnabled: _asBool(json['soundEnabled']) ?? defaults.soundEnabled,
      tableAids: TableAids.fromName(_asString(json['tableAids'])),
      cardThemeId: _asString(json['cardThemeId']) ?? defaults.cardThemeId,
      highContrastCards:
          _asBool(json['highContrastCards']) ?? defaults.highContrastCards,
      tableSurfaceTheme: TableSurfaceTheme.fromName(
        _asString(json['tableSurfaceTheme']),
      ),
    );
  }

  /// Setup values used for a new Classic Hareeg table.
  final ClassicHareegSetup setup;

  /// Whether human hands should be auto-sorted.
  final bool autoSort;

  /// Whether represented jokers should use a memory-oriented display.
  final bool memoryJokerDisplay;

  /// Language setting.
  final AppLanguage language;

  /// Motion speed choice (normal / fast / reduced).
  final MotionSpeed motionSpeed;

  /// Whether CPU turns use shorter pauses and quicker card flights.
  final bool fastCpuTurns;

  /// Whether table haptics are enabled.
  final bool hapticsEnabled;

  /// Whether table sounds are enabled. The audio engine ships as a stub in
  /// this release; the toggle persists for the planned audio follow-up.
  final bool soundEnabled;

  /// Player-facing aid level.
  final TableAids tableAids;

  /// Selected card theme id (see [CardThemeRegistry]).
  final String cardThemeId;

  /// Whether card faces should use the high-contrast accessibility renderer.
  final bool highContrastCards;

  /// Selected table surface theme.
  final TableSurfaceTheme tableSurfaceTheme;

  /// Derived reduced-motion bool, kept as a getter so callers reading the
  /// older API keep working without storing a redundant field.
  bool get reducedMotion => motionSpeed == MotionSpeed.reduced;

  /// Creates modified preferences while preserving unspecified values.
  GamePreferences copyWith({
    ClassicHareegSetup? setup,
    bool? autoSort,
    bool? memoryJokerDisplay,
    AppLanguage? language,
    MotionSpeed? motionSpeed,
    bool? fastCpuTurns,
    bool? hapticsEnabled,
    bool? soundEnabled,
    TableAids? tableAids,
    String? cardThemeId,
    bool? highContrastCards,
    TableSurfaceTheme? tableSurfaceTheme,
  }) {
    return GamePreferences(
      setup: setup ?? this.setup,
      autoSort: autoSort ?? this.autoSort,
      memoryJokerDisplay: memoryJokerDisplay ?? this.memoryJokerDisplay,
      language: language ?? this.language,
      motionSpeed: motionSpeed ?? this.motionSpeed,
      fastCpuTurns: fastCpuTurns ?? this.fastCpuTurns,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      tableAids: tableAids ?? this.tableAids,
      cardThemeId: cardThemeId ?? this.cardThemeId,
      highContrastCards: highContrastCards ?? this.highContrastCards,
      tableSurfaceTheme: tableSurfaceTheme ?? this.tableSurfaceTheme,
    );
  }

  /// Converts preferences to JSON-compatible data.
  Map<String, Object?> toJson() {
    return {
      'setup': setup.toJson(),
      'autoSort': autoSort,
      'memoryJokerDisplay': memoryJokerDisplay,
      'language': language.name,
      'motionSpeed': motionSpeed.name,
      'fastCpuTurns': fastCpuTurns,
      'hapticsEnabled': hapticsEnabled,
      'soundEnabled': soundEnabled,
      'tableAids': tableAids.name,
      'cardThemeId': cardThemeId,
      'highContrastCards': highContrastCards,
      'tableSurfaceTheme': tableSurfaceTheme.name,
    };
  }
}

/// Storage boundary for local user preferences.
abstract interface class PreferencesRepository {
  /// Loads saved preferences, falling back to defaults if none exist.
  Future<GamePreferences> loadPreferences();

  /// Persists the user's preferences.
  Future<void> savePreferences(GamePreferences preferences);
}

/// Minimal string key/value store used by persistence repositories.
abstract interface class KeyValueStore {
  /// Loads a stored string value.
  Future<String?> loadString(String key);

  /// Saves a string value.
  Future<void> saveString(String key, String value);

  /// Removes a stored value.
  Future<void> remove(String key);
}

/// Platform-channel key/value storage backed by Android SharedPreferences and
/// iOS UserDefaults.
///
/// Falls back to an in-process map when the platform channel is unavailable
/// (desktop/web), so the app continues to function in unsupported targets.
/// The fallback is logged loudly so support gaps are visible in the console
/// rather than silently swallowing persisted state.
class MethodChannelKeyValueStore implements KeyValueStore {
  /// Creates platform-channel storage.
  MethodChannelKeyValueStore({
    MethodChannel channel = const MethodChannel('hareeg_table/local_storage'),
  }) : _channel = channel;

  final MethodChannel _channel;
  final Map<String, String> _fallbackMemory = {};
  bool _loggedFallback = false;

  bool get _canUseInMemoryFallback {
    if (kIsWeb) {
      return true;
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => false,
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.fuchsia => true,
    };
  }

  void _warnAboutFallback() {
    if (_loggedFallback) {
      return;
    }
    _loggedFallback = true;
    debugPrint(
      '[hareeg_table] Platform channel "hareeg_table/local_storage" is not '
      'available on this platform. Falling back to in-memory storage; saved '
      'preferences and matches will not survive app restart. '
      'Android and iOS register this channel at startup.',
    );
  }

  @override
  Future<String?> loadString(String key) async {
    try {
      return await _channel.invokeMethod<String>('getString', {'key': key});
    } on MissingPluginException {
      if (!_canUseInMemoryFallback) {
        rethrow;
      }
      _warnAboutFallback();
      return _fallbackMemory[key];
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      await _channel.invokeMethod<void>('remove', {'key': key});
    } on MissingPluginException {
      if (!_canUseInMemoryFallback) {
        rethrow;
      }
      _warnAboutFallback();
      _fallbackMemory.remove(key);
    }
  }

  @override
  Future<void> saveString(String key, String value) async {
    try {
      await _channel.invokeMethod<void>('setString', {
        'key': key,
        'value': value,
      });
    } on MissingPluginException {
      if (!_canUseInMemoryFallback) {
        rethrow;
      }
      _warnAboutFallback();
      _fallbackMemory[key] = value;
    }
  }
}

/// JSON-backed preferences repository.
class LocalPreferencesRepository implements PreferencesRepository {
  /// Creates a repository from a key/value store.
  const LocalPreferencesRepository({required KeyValueStore store})
    : _store = store;

  static const _key = 'preferences.v1';

  final KeyValueStore _store;

  @override
  Future<GamePreferences> loadPreferences() async {
    final raw = await _store.loadString(_key);
    if (raw == null || raw.isEmpty) {
      return GamePreferences.defaults();
    }

    try {
      final decoded = jsonDecode(raw);
      final json = _asMap(decoded);
      if (json != null) {
        return GamePreferences.fromJson(json);
      }
      await _store.remove(_key);
    } on FormatException {
      await _store.remove(_key);
    }

    return GamePreferences.defaults();
  }

  @override
  Future<void> savePreferences(GamePreferences preferences) {
    return _store.saveString(_key, jsonEncode(preferences.toJson()));
  }
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  return null;
}

bool? _asBool(Object? value) {
  return value is bool ? value : null;
}

String? _asString(Object? value) {
  return value is String ? value : null;
}

T? _enumByName<T extends Enum>(Iterable<T> values, String? name) {
  if (name == null) {
    return null;
  }

  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }

  return null;
}
