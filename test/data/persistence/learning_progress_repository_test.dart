import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/learning_progress_repository.dart';
import 'package:hareeg_table/ui/features/learning/progress/learning_progress_workflow.dart';

import '../../support/test_fixtures.dart';

void main() {
  group('LocalLearningProgressRepository', () {
    test('returns first-run defaults when nothing is saved', () async {
      final repository = LocalLearningProgressRepository(
        store: MemoryKeyValueStore(),
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
      final store = MemoryKeyValueStore();
      final repository = LocalLearningProgressRepository(store: store);
      final saved = LearningProgress.defaults()
          .copyWith(onboardingCompleted: true)
          .withLessonStatus('turn-rhythm', PracticeLessonStatus.completed)
          .withLessonStatus('opening-51', PracticeLessonStatus.skipped);

      await repository.saveProgress(saved);

      final restored = await repository.loadProgress();
      expect(restored.onboardingCompleted, isTrue);
      expect(restored.statusFor('turn-rhythm'), PracticeLessonStatus.completed);
      expect(restored.statusFor('opening-51'), PracticeLessonStatus.skipped);
      expect(
        restored.statusFor('pending-discard'),
        PracticeLessonStatus.notStarted,
      );
      expect(restored.completedCount(['turn-rhythm', 'opening-51']), 1);
    });

    test('completing onboarding does not mark any lesson complete', () async {
      final store = MemoryKeyValueStore();
      final repository = LocalLearningProgressRepository(store: store);

      final progress = await repository.loadProgress();
      await repository.saveProgress(
        progress.copyWith(onboardingCompleted: true),
      );

      final restored = await repository.loadProgress();
      expect(restored.onboardingCompleted, isTrue);
      expect(restored.completedCount(['turn-rhythm', 'pending-discard']), 0);
    });

    test('unskipping a lesson removes its persisted entry', () async {
      final store = MemoryKeyValueStore();
      final repository = LocalLearningProgressRepository(store: store);
      final skipped = LearningProgress.defaults().withLessonStatus(
        'set-cover',
        PracticeLessonStatus.skipped,
      );
      await repository.saveProgress(skipped);

      await repository.saveProgress(
        skipped.withLessonStatus('set-cover', PracticeLessonStatus.notStarted),
      );

      expect(
        store.values['learning_progress.v1'],
        isNot(contains('set-cover')),
      );
      final restored = await repository.loadProgress();
      expect(restored.statusFor('set-cover'), PracticeLessonStatus.notStarted);
    });

    test('unknown lesson status names fall back to not started', () async {
      final store = MemoryKeyValueStore()
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
      final store = MemoryKeyValueStore()..values['learning_progress.v1'] = '{';
      final repository = LocalLearningProgressRepository(store: store);

      final restored = await repository.loadProgress();

      expect(restored.onboardingCompleted, isFalse);
      expect(store.values.containsKey('learning_progress.v1'), isFalse);
    });

    test('non-map saved progress falls back to defaults', () async {
      final store = MemoryKeyValueStore()
        ..values['learning_progress.v1'] = '[1,2]';
      final repository = LocalLearningProgressRepository(store: store);

      final restored = await repository.loadProgress();

      expect(restored.onboardingCompleted, isFalse);
      expect(store.values.containsKey('learning_progress.v1'), isFalse);
    });

    test('update serializes interleaved load-modify-save commands', () async {
      final repository = _SlowLearningProgressRepository();

      // Two commands fired back-to-back against the same instance before
      // either save lands. Without serialization the second read would see
      // stale state and clobber the first write.
      final first = repository.update(
        (progress) =>
            progress.withLessonStatus('a', PracticeLessonStatus.skipped),
      );
      final second = repository.update(
        (progress) =>
            progress.withLessonStatus('b', PracticeLessonStatus.completed),
      );
      await Future.wait([first, second]);

      expect(repository.progress.statusFor('a'), PracticeLessonStatus.skipped);
      expect(
        repository.progress.statusFor('b'),
        PracticeLessonStatus.completed,
      );
    });

    test('update returns the mutated progress it saved', () async {
      final repository = LocalLearningProgressRepository(
        store: MemoryKeyValueStore(),
      );

      final result = await repository.update(
        (progress) => progress.copyWith(onboardingCompleted: true),
      );

      expect(result.onboardingCompleted, isTrue);
      expect(
        (await repository.loadProgress()).onboardingCompleted,
        isTrue,
      );
    });
  });

  group('LearningProgressWorkflow', () {
    test('completes onboarding without changing lesson progress', () async {
      final repository = MemoryLearningProgressRepository(
        progress: LearningProgress.defaults().withLessonStatus(
          'turn-rhythm',
          PracticeLessonStatus.skipped,
        ),
      );
      final workflow = LearningProgressWorkflow(repository);

      await workflow.completeOnboarding();

      expect(repository.progress.onboardingCompleted, isTrue);
      expect(
        repository.progress.statusFor('turn-rhythm'),
        PracticeLessonStatus.skipped,
      );
    });

    test('sets lesson statuses through load modify save', () async {
      final repository = MemoryLearningProgressRepository();
      final workflow = LearningProgressWorkflow(repository);

      await workflow.completeLesson('turn-rhythm');
      await workflow.skipLesson('first-meld');
      await workflow.unskipLesson('first-meld');

      expect(
        repository.progress.statusFor('turn-rhythm'),
        PracticeLessonStatus.completed,
      );
      expect(
        repository.progress.statusFor('first-meld'),
        PracticeLessonStatus.notStarted,
      );
    });

    test(
      'transient workflows over a shared repository do not lose writes',
      () async {
        // Two separate workflow instances stand in for two screens sharing the
        // single app-shell repository. The repository, not the workflow, owns
        // serialization, so interleaved commands through it cannot race.
        final repository = _SlowLearningProgressRepository();
        final screenA = LearningProgressWorkflow(repository);
        final screenB = LearningProgressWorkflow(repository);

        final first = screenA.skipLesson('turn-rhythm');
        final second = screenB.completeLesson('first-meld');
        await Future.wait([first, second]);

        expect(
          repository.progress.statusFor('turn-rhythm'),
          PracticeLessonStatus.skipped,
        );
        expect(
          repository.progress.statusFor('first-meld'),
          PracticeLessonStatus.completed,
        );
      },
    );
  });
}

class _SlowLearningProgressRepository
    with SerializedLearningProgressUpdate
    implements LearningProgressRepository {
  LearningProgress progress = LearningProgress.defaults();

  @override
  Future<LearningProgress> loadProgress() async => progress;

  @override
  Future<void> saveProgress(LearningProgress progress) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    this.progress = progress;
  }
}
