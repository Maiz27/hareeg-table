import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/key_value_store.dart';
import 'package:hareeg_table/data/persistence/learning_progress_repository.dart';

void main() {
  group('LocalLearningProgressRepository', () {
    test('returns first-run defaults when nothing is saved', () async {
      final repository = LocalLearningProgressRepository(
        store: _MemoryStore(),
      );

      final progress = await repository.loadProgress();

      expect(progress.onboardingCompleted, isFalse);
      expect(
        progress.statusFor('turn-rhythm'),
        PracticeLessonStatus.notStarted,
      );
      expect(progress.completedCount(['turn-rhythm', 'opening-51']), 0);
    });

    test('round-trips onboarding completion and lesson statuses', () async {
      final store = _MemoryStore();
      final repository = LocalLearningProgressRepository(store: store);
      final saved = LearningProgress.defaults()
          .copyWith(onboardingCompleted: true)
          .withLessonStatus('turn-rhythm', PracticeLessonStatus.completed)
          .withLessonStatus('opening-51', PracticeLessonStatus.skipped);

      await repository.saveProgress(saved);

      final restored = await repository.loadProgress();
      expect(restored.onboardingCompleted, isTrue);
      expect(
        restored.statusFor('turn-rhythm'),
        PracticeLessonStatus.completed,
      );
      expect(restored.statusFor('opening-51'), PracticeLessonStatus.skipped);
      expect(
        restored.statusFor('pending-discard'),
        PracticeLessonStatus.notStarted,
      );
      expect(restored.completedCount(['turn-rhythm', 'opening-51']), 1);
    });

    test('completing onboarding does not mark any lesson complete', () async {
      final store = _MemoryStore();
      final repository = LocalLearningProgressRepository(store: store);

      final progress = await repository.loadProgress();
      await repository.saveProgress(
        progress.copyWith(onboardingCompleted: true),
      );

      final restored = await repository.loadProgress();
      expect(restored.onboardingCompleted, isTrue);
      expect(
        restored.completedCount(['turn-rhythm', 'pending-discard']),
        0,
      );
    });

    test('unskipping a lesson removes its persisted entry', () async {
      final store = _MemoryStore();
      final repository = LocalLearningProgressRepository(store: store);
      final skipped = LearningProgress.defaults().withLessonStatus(
        'set-cover',
        PracticeLessonStatus.skipped,
      );
      await repository.saveProgress(skipped);

      await repository.saveProgress(
        skipped.withLessonStatus('set-cover', PracticeLessonStatus.notStarted),
      );

      expect(store.values['learning_progress.v1'], isNot(contains('set-cover')));
      final restored = await repository.loadProgress();
      expect(restored.statusFor('set-cover'), PracticeLessonStatus.notStarted);
    });

    test('unknown lesson status names fall back to not started', () async {
      final store = _MemoryStore()
        ..values['learning_progress.v1'] =
            '{"onboardingCompleted":true,'
                '"lessons":{"turn-rhythm":"mastered","opening-51":"skipped"}}';
      final repository = LocalLearningProgressRepository(store: store);

      final restored = await repository.loadProgress();

      expect(
        restored.statusFor('turn-rhythm'),
        PracticeLessonStatus.notStarted,
      );
      expect(restored.statusFor('opening-51'), PracticeLessonStatus.skipped);
    });

    test('invalid saved progress falls back to defaults', () async {
      final store = _MemoryStore()..values['learning_progress.v1'] = '{';
      final repository = LocalLearningProgressRepository(store: store);

      final restored = await repository.loadProgress();

      expect(restored.onboardingCompleted, isFalse);
      expect(store.values.containsKey('learning_progress.v1'), isFalse);
    });

    test('non-map saved progress falls back to defaults', () async {
      final store = _MemoryStore()..values['learning_progress.v1'] = '[1,2]';
      final repository = LocalLearningProgressRepository(store: store);

      final restored = await repository.loadProgress();

      expect(restored.onboardingCompleted, isFalse);
      expect(store.values.containsKey('learning_progress.v1'), isFalse);
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
