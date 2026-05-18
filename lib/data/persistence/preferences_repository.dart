import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/classic_hareeg/models/classic_hareeg_setup.dart';

/// Player-facing language option.
enum AppLanguage {
  /// English launch language.
  english('English', 'en'),

  /// Arabic-ready setting, pending translated strings.
  arabic('Arabic (planned)', 'ar');

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

/// Display style selected by the player.
enum VisualStyle {
  /// Launch visual direction.
  warmSudaneseLounge('Warm Sudanese lounge');

  const VisualStyle(this.label);

  /// Settings label.
  final String label;

  /// Parses a saved enum name.
  static VisualStyle fromName(String? name) {
    return _enumByName(VisualStyle.values, name) ??
        VisualStyle.warmSudaneseLounge;
  }
}

/// Saved app preferences that can seed new games and table behavior.
class GamePreferences {
  /// Creates app preferences.
  const GamePreferences({
    required this.setup,
    required this.autoSort,
    required this.reducedMotion,
    required this.memoryJokerDisplay,
    required this.visualStyle,
    required this.language,
  });

  /// Default first-run preferences.
  factory GamePreferences.defaults() {
    return GamePreferences(
      setup: ClassicHareegSetup.defaults(),
      autoSort: true,
      reducedMotion: false,
      memoryJokerDisplay: false,
      visualStyle: VisualStyle.warmSudaneseLounge,
      language: AppLanguage.english,
    );
  }

  /// Restores preferences from persisted JSON-compatible data.
  factory GamePreferences.fromJson(Map<String, Object?> json) {
    final setupJson = _asMap(json['setup']);
    return GamePreferences(
      setup: setupJson != null
          ? ClassicHareegSetup.fromJson(setupJson)
          : ClassicHareegSetup.defaults(),
      autoSort:
          _asBool(json['autoSort']) ?? GamePreferences.defaults().autoSort,
      reducedMotion:
          _asBool(json['reducedMotion']) ??
          GamePreferences.defaults().reducedMotion,
      memoryJokerDisplay:
          _asBool(json['memoryJokerDisplay']) ??
          GamePreferences.defaults().memoryJokerDisplay,
      visualStyle: VisualStyle.fromName(_asString(json['visualStyle'])),
      language: AppLanguage.fromName(_asString(json['language'])),
    );
  }

  /// Setup values used for a new Classic Hareeg table.
  final ClassicHareegSetup setup;

  /// Whether human hands should be auto-sorted.
  final bool autoSort;

  /// Whether nonessential motion should be reduced.
  final bool reducedMotion;

  /// Whether represented jokers should use a memory-oriented display.
  final bool memoryJokerDisplay;

  /// Visual direction selection.
  final VisualStyle visualStyle;

  /// Language setting.
  final AppLanguage language;

  /// Creates modified preferences while preserving unspecified values.
  GamePreferences copyWith({
    ClassicHareegSetup? setup,
    bool? autoSort,
    bool? reducedMotion,
    bool? memoryJokerDisplay,
    VisualStyle? visualStyle,
    AppLanguage? language,
  }) {
    return GamePreferences(
      setup: setup ?? this.setup,
      autoSort: autoSort ?? this.autoSort,
      reducedMotion: reducedMotion ?? this.reducedMotion,
      memoryJokerDisplay: memoryJokerDisplay ?? this.memoryJokerDisplay,
      visualStyle: visualStyle ?? this.visualStyle,
      language: language ?? this.language,
    );
  }

  /// Converts preferences to JSON-compatible data.
  Map<String, Object?> toJson() {
    return {
      'setup': setup.toJson(),
      'autoSort': autoSort,
      'reducedMotion': reducedMotion,
      'memoryJokerDisplay': memoryJokerDisplay,
      'visualStyle': visualStyle.name,
      'language': language.name,
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
class MethodChannelKeyValueStore implements KeyValueStore {
  /// Creates platform-channel storage.
  MethodChannelKeyValueStore({
    MethodChannel channel = const MethodChannel('hareeg_table/local_storage'),
  }) : _channel = channel;

  final MethodChannel _channel;
  final Map<String, String> _fallbackMemory = {};

  @override
  Future<String?> loadString(String key) async {
    try {
      return await _channel.invokeMethod<String>('getString', {'key': key});
    } on MissingPluginException {
      return _fallbackMemory[key];
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      await _channel.invokeMethod<void>('remove', {'key': key});
    } on MissingPluginException {
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
