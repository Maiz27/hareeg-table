import 'dart:convert';

import '../../domain/classic_hareeg/persistence/persistence_codec.dart';
import 'key_value_store.dart';

/// Progress state for a single guided practice lesson.
enum PracticeLessonStatus {
  /// The player has not attempted or dismissed the lesson yet.
  notStarted,

  /// The player explicitly skipped the lesson from the checklist.
  skipped,

  /// The player completed the lesson at least once.
  completed;

  /// Parses a saved enum name, falling back to [notStarted] for unknown
  /// values so newer saves never crash older builds.
  static PracticeLessonStatus fromName(String? name) {
    for (final value in PracticeLessonStatus.values) {
      if (value.name == name) {
        return value;
      }
    }
    return PracticeLessonStatus.notStarted;
  }
}

/// Locally persisted first-run teaching state: onboarding completion plus
/// per-lesson guided practice progress.
///
/// Lives outside [GamePreferences] because learning progress is achievement
/// state rather than a player-tunable setting, and it grows as practice packs
/// ship without forcing preference schema churn.
class LearningProgress {
  /// Creates learning progress state.
  ///
  /// The lesson map is copied into an unmodifiable view so later mutation of
  /// the caller's map can never leak into this instance.
  LearningProgress({
    required this.onboardingCompleted,
    required Map<String, PracticeLessonStatus> lessonStatuses,
  }) : _lessonStatuses = Map.unmodifiable(lessonStatuses);

  /// First-run defaults: onboarding pending, every lesson not started.
  factory LearningProgress.defaults() {
    return LearningProgress(
      onboardingCompleted: false,
      lessonStatuses: const {},
    );
  }

  /// Restores progress from persisted JSON-compatible data.
  factory LearningProgress.fromJson(Map<String, Object?> json) {
    final lessons = <String, PracticeLessonStatus>{};
    final rawLessons = asJsonMap(json['lessons']);
    if (rawLessons != null) {
      for (final entry in rawLessons.entries) {
        final status = PracticeLessonStatus.fromName(
          asJsonString(entry.value),
        );
        if (status != PracticeLessonStatus.notStarted) {
          lessons[entry.key] = status;
        }
      }
    }
    return LearningProgress(
      onboardingCompleted: asJsonBool(json['onboardingCompleted']) ?? false,
      lessonStatuses: lessons,
    );
  }

  /// Whether the first-launch onboarding flow was finished or skipped.
  ///
  /// Skipping counts as completion: onboarding must never interrupt normal
  /// play again after the first-run decision. Skipping does not touch any
  /// lesson status.
  final bool onboardingCompleted;

  final Map<String, PracticeLessonStatus> _lessonStatuses;

  /// Progress for one practice lesson; absent entries are [PracticeLessonStatus.notStarted].
  PracticeLessonStatus statusFor(String lessonId) {
    return _lessonStatuses[lessonId] ?? PracticeLessonStatus.notStarted;
  }

  /// Number of lessons in [lessonIds] currently marked completed.
  int completedCount(Iterable<String> lessonIds) {
    return lessonIds
        .where((id) => statusFor(id) == PracticeLessonStatus.completed)
        .length;
  }

  /// Creates modified progress while preserving unspecified values.
  LearningProgress copyWith({bool? onboardingCompleted}) {
    return LearningProgress(
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      lessonStatuses: _lessonStatuses,
    );
  }

  /// Returns progress with one lesson's status replaced.
  ///
  /// Setting [PracticeLessonStatus.notStarted] removes the stored entry so
  /// unskipping a lesson leaves no residue in the persisted map.
  LearningProgress withLessonStatus(
    String lessonId,
    PracticeLessonStatus status,
  ) {
    final next = Map<String, PracticeLessonStatus>.from(_lessonStatuses);
    if (status == PracticeLessonStatus.notStarted) {
      next.remove(lessonId);
    } else {
      next[lessonId] = status;
    }
    return LearningProgress(
      onboardingCompleted: onboardingCompleted,
      lessonStatuses: next,
    );
  }

  /// Converts progress to JSON-compatible data.
  Map<String, Object?> toJson() {
    return {
      'onboardingCompleted': onboardingCompleted,
      'lessons': {
        for (final entry in _lessonStatuses.entries)
          entry.key: entry.value.name,
      },
    };
  }
}

/// Storage boundary for onboarding and guided practice progress.
abstract interface class LearningProgressRepository {
  /// Loads saved progress, falling back to first-run defaults if none exist.
  Future<LearningProgress> loadProgress();

  /// Persists the player's learning progress.
  Future<void> saveProgress(LearningProgress progress);

  /// Atomically loads, [mutate]s, and saves progress under a per-repository
  /// serialization lock, returning the saved value.
  ///
  /// All updates against the same repository instance run one at a time, so
  /// concurrent load-modify-save commands from different screens that share
  /// the instance can never interleave and lose a write.
  Future<LearningProgress> update(
    LearningProgress Function(LearningProgress current) mutate,
  );
}

/// Serializes [LearningProgressRepository.update] over [loadProgress] and
/// [saveProgress] using a per-instance future chain.
///
/// Mixing this in gives any repository correct write ordering: the
/// serialization boundary is the repository instance shared across screens,
/// not a per-screen caller. Implementations supply the storage primitives;
/// this mixin only adds ordering.
mixin SerializedLearningProgressUpdate implements LearningProgressRepository {
  Future<LearningProgress> _pendingUpdate = Future<LearningProgress>.value(
    LearningProgress.defaults(),
  );

  @override
  Future<LearningProgress> update(
    LearningProgress Function(LearningProgress current) mutate,
  ) {
    final next = _pendingUpdate
        .catchError((Object _) => LearningProgress.defaults())
        .then((_) async {
          final current = await loadProgress();
          final mutated = mutate(current);
          await saveProgress(mutated);
          return mutated;
        });
    _pendingUpdate = next;
    return next;
  }
}

/// JSON-backed learning progress repository.
class LocalLearningProgressRepository
    with SerializedLearningProgressUpdate
    implements LearningProgressRepository {
  /// Creates a repository from a key/value store.
  LocalLearningProgressRepository({required KeyValueStore store})
    : _store = store;

  static const _key = 'learning_progress.v1';

  final KeyValueStore _store;

  @override
  Future<LearningProgress> loadProgress() async {
    final raw = await _store.loadString(_key);
    if (raw == null || raw.isEmpty) {
      return LearningProgress.defaults();
    }

    try {
      final decoded = jsonDecode(raw);
      final json = asJsonMap(decoded);
      if (json != null) {
        return LearningProgress.fromJson(json);
      }
      await _store.remove(_key);
    } on FormatException {
      await _store.remove(_key);
    }

    return LearningProgress.defaults();
  }

  @override
  Future<void> saveProgress(LearningProgress progress) {
    return _store.saveString(_key, jsonEncode(progress.toJson()));
  }
}
