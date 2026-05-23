import 'dart:convert';

import '../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../ui/core/aids/table_aids.dart';
import '../../ui/core/cards/card_theme_registry.dart';
import '../../ui/core/motion/motion_speed.dart';
import '../../ui/core/theme/table_surface_theme.dart';
import '../../ui/features/game_table/table_hand_interaction_state.dart'
    show HandSortMode;
import 'key_value_store.dart';

export '../../ui/features/game_table/table_hand_interaction_state.dart'
    show HandSortMode;

const _soundDefaultsVersion = 1;

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
    required this.handSortMode,
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
      handSortMode: HandSortMode.byRank,
      memoryJokerDisplay: false,
      language: AppLanguage.english,
      motionSpeed: MotionSpeed.normal,
      fastCpuTurns: true,
      hapticsEnabled: true,
      soundEnabled: true,
      tableAids: TableAids.guided,
      cardThemeId: CardThemeRegistry.defaultThemeId,
      highContrastCards: false,
      tableSurfaceTheme: TableSurfaceTheme.sandline,
    );
  }

  /// Restores preferences from persisted JSON-compatible data.
  factory GamePreferences.fromJson(Map<String, Object?> json) {
    final defaults = GamePreferences.defaults();
    final setupJson = jsonMapOrNull(json['setup']);
    final legacyReducedMotion = _asBool(json['reducedMotion']) ?? false;
    final motionSpeed = json.containsKey('motionSpeed')
        ? MotionSpeed.fromName(_asString(json['motionSpeed']))
        : (legacyReducedMotion ? MotionSpeed.reduced : MotionSpeed.normal);
    final savedSoundDefaultsVersion = _asInt(json['soundDefaultsVersion']);
    final soundEnabled = savedSoundDefaultsVersion == _soundDefaultsVersion
        ? _asBool(json['soundEnabled']) ?? defaults.soundEnabled
        : defaults.soundEnabled;
    return GamePreferences(
      setup: setupJson != null
          ? ClassicHareegSetup.fromJson(setupJson)
          : ClassicHareegSetup.defaults(),
      handSortMode: _readHandSortMode(json, defaults.handSortMode),
      memoryJokerDisplay:
          _asBool(json['memoryJokerDisplay']) ?? defaults.memoryJokerDisplay,
      language: AppLanguage.fromName(_asString(json['language'])),
      motionSpeed: motionSpeed,
      fastCpuTurns: _asBool(json['fastCpuTurns']) ?? defaults.fastCpuTurns,
      hapticsEnabled:
          _asBool(json['hapticsEnabled']) ?? defaults.hapticsEnabled,
      soundEnabled: soundEnabled,
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

  /// Initial sort applied to the human hand at the start of each round.
  ///
  /// The in-table sort picker overrides this for the current round only;
  /// the next round resets to this preference. Migrated from the legacy
  /// `autoSort` bool — true → [HandSortMode.byRank], false →
  /// [HandSortMode.manual].
  final HandSortMode handSortMode;

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

  /// Whether table sounds are enabled.
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
    HandSortMode? handSortMode,
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
      handSortMode: handSortMode ?? this.handSortMode,
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
      'handSortMode': handSortMode.name,
      'memoryJokerDisplay': memoryJokerDisplay,
      'language': language.name,
      'motionSpeed': motionSpeed.name,
      'fastCpuTurns': fastCpuTurns,
      'hapticsEnabled': hapticsEnabled,
      'soundEnabled': soundEnabled,
      'soundDefaultsVersion': _soundDefaultsVersion,
      'tableAids': tableAids.name,
      'cardThemeId': cardThemeId,
      'highContrastCards': highContrastCards,
      'tableSurfaceTheme': tableSurfaceTheme.name,
    };
  }
}

/// Reads the saved [HandSortMode], migrating the legacy `autoSort` bool when
/// no explicit mode is stored. `autoSort: true` → byRank (the previous
/// auto-sort behaviour), `autoSort: false` → manual.
HandSortMode _readHandSortMode(Map<String, Object?> json, HandSortMode fallback) {
  final stored = _enumByName(HandSortMode.values, _asString(json['handSortMode']));
  if (stored != null) {
    return stored;
  }
  final legacyAutoSort = _asBool(json['autoSort']);
  if (legacyAutoSort != null) {
    return legacyAutoSort ? HandSortMode.byRank : HandSortMode.manual;
  }
  return fallback;
}

/// Storage boundary for local user preferences.
abstract interface class PreferencesRepository {
  /// Loads saved preferences, falling back to defaults if none exist.
  Future<GamePreferences> loadPreferences();

  /// Persists the user's preferences.
  Future<void> savePreferences(GamePreferences preferences);
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
      final json = jsonMapOrNull(decoded);
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

bool? _asBool(Object? value) {
  return value is bool ? value : null;
}

int? _asInt(Object? value) {
  return value is int ? value : null;
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
