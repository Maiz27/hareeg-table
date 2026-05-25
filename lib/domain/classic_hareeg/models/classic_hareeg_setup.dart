import '../persistence/persistence_codec.dart';
import 'table_strictness.dart';

export 'table_strictness.dart';

/// CPU skill profile selected before a Classic Hareeg game starts.
enum CpuDifficulty {
  /// Relaxed play with forgiving CPU choices.
  beginner('Beginner'),

  /// Default casual table behavior.
  casual('Casual'),

  /// Stronger table-aware behavior for later strategy work.
  skilled('Skilled'),

  /// Highest planned CPU profile.
  expert('Expert');

  const CpuDifficulty(this.label);

  /// Player-facing label.
  final String label;

  /// Parses a saved enum name, falling back to the default difficulty.
  static CpuDifficulty fromName(String? name) {
    return _enumByName(CpuDifficulty.values, name) ?? CpuDifficulty.casual;
  }
}

/// How the first starter is selected.
enum StarterMode {
  /// The human player starts the first round.
  human('Human starts'),

  /// The app chooses the first starter.
  random('Random starter');

  const StarterMode(this.label);

  /// Player-facing label.
  final String label;

  /// Parses a saved enum name, falling back to the default starter mode.
  static StarterMode fromName(String? name) {
    return _enumByName(StarterMode.values, name) ?? StarterMode.human;
  }
}

/// Local setup values used to start a Classic Hareeg table.
class ClassicHareegSetup {
  /// Creates setup values for a Classic Hareeg table.
  const ClassicHareegSetup({
    required this.cpuDifficulty,
    required this.starterMode,
    required this.openingRequirement,
    required this.deckCount,
    required this.jokerCount,
    required this.fiftyTimerSeconds,
    required this.tableStrictness,
  });

  /// Default first-run setup values.
  ///
  /// `tableStrictness` defaults to [TableStrictness.coaching] — the loudest
  /// tier, best fit for first-run players who need both rule blocking and
  /// hint surfaces. Existing assisted+guided users land here through the
  /// persistence migration in `preferences_repository.dart`.
  factory ClassicHareegSetup.defaults() {
    return const ClassicHareegSetup(
      cpuDifficulty: CpuDifficulty.casual,
      starterMode: StarterMode.human,
      openingRequirement: 51,
      deckCount: 2,
      jokerCount: 2,
      fiftyTimerSeconds: 4,
      tableStrictness: TableStrictness.coaching,
    );
  }

  /// Restores setup values from persisted JSON-compatible data.
  ///
  /// Reads the v2 schema (`tableStrictness` key). Legacy migration from the
  /// old `rulePreset` × `tableAids` × `memoryJokerDisplay` shape lives in
  /// `GamePreferences.fromJson` and runs before this factory.
  factory ClassicHareegSetup.fromJson(Map<String, Object?> json) {
    final defaults = ClassicHareegSetup.defaults();
    return ClassicHareegSetup(
      cpuDifficulty: CpuDifficulty.fromName(asJsonString(json['cpuDifficulty'])),
      starterMode: StarterMode.fromName(asJsonString(json['starterMode'])),
      openingRequirement: _positiveIntOrDefault(
        json['openingRequirement'],
        defaults.openingRequirement,
      ),
      deckCount: _positiveIntOrDefault(json['deckCount'], defaults.deckCount),
      jokerCount: _nonNegativeIntOrDefault(
        json['jokerCount'],
        defaults.jokerCount,
      ),
      fiftyTimerSeconds: _positiveIntOrDefault(
        json['fiftyTimerSeconds'],
        defaults.fiftyTimerSeconds,
      ),
      tableStrictness: TableStrictness.fromName(
        asJsonString(json['tableStrictness']),
      ),
    );
  }

  /// CPU behavior profile.
  final CpuDifficulty cpuDifficulty;

  /// First starter selection mode.
  final StarterMode starterMode;

  /// Opening requirement before benchmark pressure.
  final int openingRequirement;

  /// Number of standard 52-card decks.
  final int deckCount;

  /// Number of jokers included in the deck.
  final int jokerCount;

  /// Fifty claim timer in seconds.
  final int fiftyTimerSeconds;

  /// Strictness tier controlling mistake handling, hint surfaces, and joker
  /// identity persistence. See [TableStrictness].
  final TableStrictness tableStrictness;

  /// Creates a modified setup while preserving unspecified values.
  ClassicHareegSetup copyWith({
    CpuDifficulty? cpuDifficulty,
    StarterMode? starterMode,
    int? openingRequirement,
    int? deckCount,
    int? jokerCount,
    int? fiftyTimerSeconds,
    TableStrictness? tableStrictness,
  }) {
    return ClassicHareegSetup(
      cpuDifficulty: cpuDifficulty ?? this.cpuDifficulty,
      starterMode: starterMode ?? this.starterMode,
      openingRequirement: openingRequirement ?? this.openingRequirement,
      deckCount: deckCount ?? this.deckCount,
      jokerCount: jokerCount ?? this.jokerCount,
      fiftyTimerSeconds: fiftyTimerSeconds ?? this.fiftyTimerSeconds,
      tableStrictness: tableStrictness ?? this.tableStrictness,
    );
  }

  /// Converts setup values to JSON-compatible data.
  Map<String, Object?> toJson() {
    return {
      'cpuDifficulty': cpuDifficulty.name,
      'starterMode': starterMode.name,
      'openingRequirement': openingRequirement,
      'deckCount': deckCount,
      'jokerCount': jokerCount,
      'fiftyTimerSeconds': fiftyTimerSeconds,
      'tableStrictness': tableStrictness.name,
    };
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

int _positiveIntOrDefault(Object? value, int fallback) {
  final parsed = asJsonInt(value);
  return parsed == null || parsed <= 0 ? fallback : parsed;
}

int _nonNegativeIntOrDefault(Object? value, int fallback) {
  final parsed = asJsonInt(value);
  return parsed == null || parsed < 0 ? fallback : parsed;
}
