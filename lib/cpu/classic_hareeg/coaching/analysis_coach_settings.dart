import '../../../domain/classic_hareeg/persistence/persistence_codec.dart';

/// How much the replay analysis coach says.
enum AnalysisVerbosity {
  /// Every observation, including routine ones.
  narrateAll,

  /// Notable moments and clear mistakes.
  keyMoments,

  /// Only moves the evidence marks as clearly wrong.
  clearMistakes;

  /// Parses a persisted name, falling back to the default.
  ///
  /// A verbosity that no longer exists is a settings-shaped problem, not a
  /// reason to refuse to load a player's whole preferences file.
  static AnalysisVerbosity fromName(String? name) {
    for (final value in AnalysisVerbosity.values) {
      if (value.name == name) {
        return value;
      }
    }
    return AnalysisVerbosity.keyMoments;
  }
}

/// Player-controlled shape of the replay analysis coach.
///
/// A plain value with no I/O: the persisted default lives inside the existing
/// preferences record, and a replay may override it locally without the
/// override ever being written back.
class AnalysisCoachSettings {
  /// Creates settings.
  const AnalysisCoachSettings({
    required this.verbosity,
    required this.cardDeathWarnings,
  });

  /// First-run defaults: key moments, with dead-card warnings on.
  factory AnalysisCoachSettings.defaults() => const AnalysisCoachSettings(
    verbosity: AnalysisVerbosity.keyMoments,
    cardDeathWarnings: true,
  );

  /// Restores settings from JSON-compatible data.
  factory AnalysisCoachSettings.fromJson(Map<String, Object?>? json) {
    final defaults = AnalysisCoachSettings.defaults();
    if (json == null) {
      return defaults;
    }
    return AnalysisCoachSettings(
      verbosity: AnalysisVerbosity.fromName(asJsonString(json['verbosity'])),
      cardDeathWarnings:
          asJsonBool(json['cardDeathWarnings']) ?? defaults.cardDeathWarnings,
    );
  }

  /// How much the coach says.
  final AnalysisVerbosity verbosity;

  /// Whether dead-card warnings are shown at all.
  ///
  /// Independent of [verbosity]: a player who finds card-death talk noisy can
  /// silence it while still narrating everything else.
  final bool cardDeathWarnings;

  /// Creates modified settings.
  AnalysisCoachSettings copyWith({
    AnalysisVerbosity? verbosity,
    bool? cardDeathWarnings,
  }) {
    return AnalysisCoachSettings(
      verbosity: verbosity ?? this.verbosity,
      cardDeathWarnings: cardDeathWarnings ?? this.cardDeathWarnings,
    );
  }

  /// Converts to JSON-compatible data.
  Map<String, Object?> toJson() => {
    'verbosity': verbosity.name,
    'cardDeathWarnings': cardDeathWarnings,
  };

  @override
  bool operator ==(Object other) =>
      other is AnalysisCoachSettings &&
      other.verbosity == verbosity &&
      other.cardDeathWarnings == cardDeathWarnings;

  @override
  int get hashCode => Object.hash(verbosity, cardDeathWarnings);
}
