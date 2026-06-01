import 'dart:convert';

import '../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../domain/classic_hareeg/persistence/persistence_codec.dart';
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
    required this.language,
    required this.motionSpeed,
    required this.fastCpuTurns,
    required this.hapticsEnabled,
    required this.soundEnabled,
    required this.cardThemeId,
    required this.highContrastCards,
    required this.tableSurfaceTheme,
    required this.coachingTipsEnabled,
  });

  /// Default first-run preferences.
  factory GamePreferences.defaults() {
    return GamePreferences(
      setup: ClassicHareegSetup.defaults(),
      handSortMode: HandSortMode.byRank,
      language: AppLanguage.english,
      motionSpeed: MotionSpeed.normal,
      fastCpuTurns: true,
      hapticsEnabled: true,
      soundEnabled: true,
      cardThemeId: CardThemeRegistry.defaultThemeId,
      highContrastCards: false,
      tableSurfaceTheme: TableSurfaceTheme.sandline,
      coachingTipsEnabled: true,
    );
  }

  /// Restores preferences from persisted JSON-compatible data.
  ///
  /// Handles the legacy schema (`rulePreset` + `tableAids` + `memoryJokerDisplay`)
  /// by migrating to [TableStrictness]. The migration runs before
  /// [ClassicHareegSetup.fromJson] sees the setup map, so the model factory
  /// never needs to know about the old shape.
  factory GamePreferences.fromJson(Map<String, Object?> json) {
    final defaults = GamePreferences.defaults();
    final setupJson = asJsonMap(json['setup']);
    final legacyReducedMotion = asJsonBool(json['reducedMotion']) ?? false;
    final motionSpeed = json.containsKey('motionSpeed')
        ? MotionSpeed.fromName(asJsonString(json['motionSpeed']))
        : (legacyReducedMotion ? MotionSpeed.reduced : MotionSpeed.normal);
    final savedSoundDefaultsVersion = asJsonInt(json['soundDefaultsVersion']);
    final soundEnabled = savedSoundDefaultsVersion == _soundDefaultsVersion
        ? asJsonBool(json['soundEnabled']) ?? defaults.soundEnabled
        : defaults.soundEnabled;
    final setup = _restoreSetup(
      setupJson: setupJson,
      legacyTableAids: asJsonString(json['tableAids']),
      legacyMemoryJokerDisplay: asJsonBool(json['memoryJokerDisplay']),
    );
    return GamePreferences(
      setup: setup,
      handSortMode: _readHandSortMode(json, defaults.handSortMode),
      language: AppLanguage.fromName(asJsonString(json['language'])),
      motionSpeed: motionSpeed,
      fastCpuTurns: asJsonBool(json['fastCpuTurns']) ?? defaults.fastCpuTurns,
      hapticsEnabled:
          asJsonBool(json['hapticsEnabled']) ?? defaults.hapticsEnabled,
      soundEnabled: soundEnabled,
      cardThemeId: asJsonString(json['cardThemeId']) ?? defaults.cardThemeId,
      highContrastCards:
          asJsonBool(json['highContrastCards']) ?? defaults.highContrastCards,
      tableSurfaceTheme: TableSurfaceTheme.fromName(
        asJsonString(json['tableSurfaceTheme']),
      ),
      coachingTipsEnabled:
          asJsonBool(json['coachingTipsEnabled']) ??
          defaults.coachingTipsEnabled,
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

  /// Selected card theme id (see [CardThemeRegistry]).
  final String cardThemeId;

  /// Whether card faces should use the high-contrast accessibility renderer.
  final bool highContrastCards;

  /// Selected table surface theme.
  final TableSurfaceTheme tableSurfaceTheme;

  /// Whether the coaching tier surfaces proactive hint callouts and the coach
  /// highlight ring. Only consulted on [TableStrictness.coaching]; other tiers
  /// never show hints regardless. Defaults to on so players who pick the
  /// coaching tier get help without an extra step.
  final bool coachingTipsEnabled;

  /// Derived reduced-motion bool, kept as a getter so callers reading the
  /// older API keep working without storing a redundant field.
  bool get reducedMotion => motionSpeed == MotionSpeed.reduced;

  /// Creates modified preferences while preserving unspecified values.
  GamePreferences copyWith({
    ClassicHareegSetup? setup,
    HandSortMode? handSortMode,
    AppLanguage? language,
    MotionSpeed? motionSpeed,
    bool? fastCpuTurns,
    bool? hapticsEnabled,
    bool? soundEnabled,
    String? cardThemeId,
    bool? highContrastCards,
    TableSurfaceTheme? tableSurfaceTheme,
    bool? coachingTipsEnabled,
  }) {
    return GamePreferences(
      setup: setup ?? this.setup,
      handSortMode: handSortMode ?? this.handSortMode,
      language: language ?? this.language,
      motionSpeed: motionSpeed ?? this.motionSpeed,
      fastCpuTurns: fastCpuTurns ?? this.fastCpuTurns,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      cardThemeId: cardThemeId ?? this.cardThemeId,
      highContrastCards: highContrastCards ?? this.highContrastCards,
      tableSurfaceTheme: tableSurfaceTheme ?? this.tableSurfaceTheme,
      coachingTipsEnabled: coachingTipsEnabled ?? this.coachingTipsEnabled,
    );
  }

  /// Converts preferences to JSON-compatible data.
  Map<String, Object?> toJson() {
    return {
      'setup': setup.toJson(),
      'handSortMode': handSortMode.name,
      'language': language.name,
      'motionSpeed': motionSpeed.name,
      'fastCpuTurns': fastCpuTurns,
      'hapticsEnabled': hapticsEnabled,
      'soundEnabled': soundEnabled,
      'soundDefaultsVersion': _soundDefaultsVersion,
      'cardThemeId': cardThemeId,
      'highContrastCards': highContrastCards,
      'tableSurfaceTheme': tableSurfaceTheme.name,
      'coachingTipsEnabled': coachingTipsEnabled,
    };
  }
}

/// Migrates legacy `(rulePreset, tableAids, memoryJokerDisplay)` to
/// [TableStrictness] before [ClassicHareegSetup.fromJson] sees the setup map.
///
/// The transformation runs through the shared [PersistenceCodec] dispatcher
/// as a named [JsonMigrationStep] (see [legacyTableStrictnessMigrationStep])
/// so future schema migrations follow the same pipeline.
///
/// Rules (from `docs/design/table-strictness.md §5` plus the ratified
/// `memoryJokerDisplay` special case):
///
/// - `tableStrictness` already present in setup → use it directly (v2 schema).
/// - `rulePreset=tablePenalties` (any aids) → strict.
/// - `rulePreset=hardTable17` (any aids) → table.
/// - `rulePreset=assisted` + `memoryJokerDisplay=true` → strict (preserves
///   the memory mechanic the user explicitly opted into).
/// - `rulePreset=assisted` + `tableAids=guided` → coaching.
/// - `rulePreset=assisted` + `tableAids=standard` → standard.
/// - `rulePreset=assisted` + `tableAids=tableMode` → standard (normalize the
///   incoherent assisted+tableMode combo).
/// - Anything else / unknown → defaults to coaching.
ClassicHareegSetup _restoreSetup({
  required Map<String, Object?>? setupJson,
  required String? legacyTableAids,
  required bool? legacyMemoryJokerDisplay,
}) {
  if (setupJson == null) {
    return ClassicHareegSetup.defaults();
  }

  final migrated = migrateLegacyMap(
    setupJson,
    steps: [
      legacyTableStrictnessMigrationStep(
        tableAids: legacyTableAids,
        memoryJokerDisplay: legacyMemoryJokerDisplay,
      ),
    ],
  );
  return ClassicHareegSetup.fromJson(migrated);
}

/// Builds the legacy-`tableStrictness` migration step.
///
/// Reads sibling preference fields (`tableAids`, `memoryJokerDisplay`) from
/// the parent preferences map because the strictness derivation depends on
/// them, then upgrades the setup map in place. Lives in the dispatcher
/// pipeline rather than the model factory so model code never has to know
/// about the legacy shape.
JsonMigrationStep legacyTableStrictnessMigrationStep({
  required String? tableAids,
  required bool? memoryJokerDisplay,
}) {
  return JsonMigrationStep(
    name: 'preferences.setup.tableStrictness.v1->v2',
    apply: (source) {
      if (source.containsKey('tableStrictness')) {
        return source;
      }
      final legacyRulePreset = asJsonString(source['rulePreset']);
      final migrated = _migrateStrictness(
        rulePreset: legacyRulePreset,
        tableAids: tableAids,
        memoryJokerDisplay: memoryJokerDisplay,
      );
      return <String, Object?>{
        ...source,
        'tableStrictness': migrated.name,
      }..remove('rulePreset');
    },
  );
}

TableStrictness _migrateStrictness({
  required String? rulePreset,
  required String? tableAids,
  required bool? memoryJokerDisplay,
}) {
  switch (rulePreset) {
    case 'tablePenalties':
      return TableStrictness.strict;
    case 'hardTable17':
      return TableStrictness.table;
    case 'assisted':
      if (memoryJokerDisplay ?? false) {
        return TableStrictness.strict;
      }
      switch (tableAids) {
        case 'guided':
          return TableStrictness.coaching;
        case 'standard':
        case 'tableMode':
          return TableStrictness.standard;
      }
      return TableStrictness.coaching;
    default:
      return TableStrictness.coaching;
  }
}

/// Reads the saved [HandSortMode], migrating the legacy `autoSort` bool when
/// no explicit mode is stored. `autoSort: true` → byRank (the previous
/// auto-sort behaviour), `autoSort: false` → manual.
HandSortMode _readHandSortMode(Map<String, Object?> json, HandSortMode fallback) {
  final stored = _enumByName(HandSortMode.values, asJsonString(json['handSortMode']));
  if (stored != null) {
    return stored;
  }
  final legacyAutoSort = asJsonBool(json['autoSort']);
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
      final json = asJsonMap(decoded);
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
