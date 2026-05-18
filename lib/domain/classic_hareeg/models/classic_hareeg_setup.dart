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

/// Mistake-handling preset for Classic Hareeg.
enum RulePreset {
  /// Default assisted table that blocks illegal moves.
  assisted('Assisted', 'Blocks illegal moves while learning.'),

  /// Allows selected table mistakes with a smaller score penalty.
  tablePenalties('Table penalties', 'Allows selected mistakes with +3.'),

  /// Harder table preset with harsh round-out mistakes.
  hardTable17('Hard table 17', 'Allows selected mistakes with +17.');

  const RulePreset(this.label, this.description);

  /// Player-facing label.
  final String label;

  /// Short setup description.
  final String description;

  /// Parses a saved enum name, falling back to the default preset.
  static RulePreset fromName(String? name) {
    return _enumByName(RulePreset.values, name) ?? RulePreset.assisted;
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
    required this.rulePreset,
  });

  /// Default first-run setup values.
  factory ClassicHareegSetup.defaults() {
    return const ClassicHareegSetup(
      cpuDifficulty: CpuDifficulty.casual,
      starterMode: StarterMode.human,
      openingRequirement: 51,
      deckCount: 2,
      jokerCount: 2,
      fiftyTimerSeconds: 4,
      rulePreset: RulePreset.assisted,
    );
  }

  /// Restores setup values from persisted JSON-compatible data.
  factory ClassicHareegSetup.fromJson(Map<String, Object?> json) {
    return ClassicHareegSetup(
      cpuDifficulty: CpuDifficulty.fromName(_asString(json['cpuDifficulty'])),
      starterMode: StarterMode.fromName(_asString(json['starterMode'])),
      openingRequirement:
          _asInt(json['openingRequirement']) ??
          ClassicHareegSetup.defaults().openingRequirement,
      deckCount:
          _asInt(json['deckCount']) ?? ClassicHareegSetup.defaults().deckCount,
      jokerCount:
          _asInt(json['jokerCount']) ??
          ClassicHareegSetup.defaults().jokerCount,
      fiftyTimerSeconds:
          _asInt(json['fiftyTimerSeconds']) ??
          ClassicHareegSetup.defaults().fiftyTimerSeconds,
      rulePreset: RulePreset.fromName(_asString(json['rulePreset'])),
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

  /// Rule preset controlling mistake handling.
  final RulePreset rulePreset;

  /// Creates a modified setup while preserving unspecified values.
  ClassicHareegSetup copyWith({
    CpuDifficulty? cpuDifficulty,
    StarterMode? starterMode,
    int? openingRequirement,
    int? deckCount,
    int? jokerCount,
    int? fiftyTimerSeconds,
    RulePreset? rulePreset,
  }) {
    return ClassicHareegSetup(
      cpuDifficulty: cpuDifficulty ?? this.cpuDifficulty,
      starterMode: starterMode ?? this.starterMode,
      openingRequirement: openingRequirement ?? this.openingRequirement,
      deckCount: deckCount ?? this.deckCount,
      jokerCount: jokerCount ?? this.jokerCount,
      fiftyTimerSeconds: fiftyTimerSeconds ?? this.fiftyTimerSeconds,
      rulePreset: rulePreset ?? this.rulePreset,
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
      'rulePreset': rulePreset.name,
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

int? _asInt(Object? value) {
  return switch (value) {
    int() => value,
    num() => value.toInt(),
    String() => int.tryParse(value),
    _ => null,
  };
}

String? _asString(Object? value) {
  return value is String ? value : null;
}
