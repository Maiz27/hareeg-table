import '../../../../data/persistence/learning_progress_repository.dart';

/// Command surface for onboarding and guided-practice progress mutations.
///
/// The repository remains the storage adapter and owns write serialization
/// via [LearningProgressRepository.update]. This module is a thin command
/// vocabulary so screens do not duplicate progress write policy when they
/// mark onboarding, lesson completion, skip, or unskip. Multiple transient
/// workflow instances over the same shared repository serialize correctly
/// because the lock lives on the repository, not on the workflow.
class LearningProgressWorkflow {
  /// Creates a workflow backed by [repository].
  LearningProgressWorkflow(this.repository);

  /// Storage adapter for learning progress.
  final LearningProgressRepository repository;

  /// Loads current progress.
  Future<LearningProgress> load() => repository.loadProgress();

  /// Marks first-run onboarding completed.
  Future<void> completeOnboarding() {
    return repository.update(
      (progress) => progress.copyWith(onboardingCompleted: true),
    );
  }

  /// Marks [lessonId] completed.
  Future<void> completeLesson(String lessonId) {
    return setLessonStatus(lessonId, PracticeLessonStatus.completed);
  }

  /// Marks [lessonId] skipped.
  Future<void> skipLesson(String lessonId) {
    return setLessonStatus(lessonId, PracticeLessonStatus.skipped);
  }

  /// Removes a skipped status for [lessonId].
  Future<void> unskipLesson(String lessonId) {
    return setLessonStatus(lessonId, PracticeLessonStatus.notStarted);
  }

  /// Sets one lesson status.
  Future<void> setLessonStatus(String lessonId, PracticeLessonStatus status) {
    return repository.update(
      (progress) => progress.withLessonStatus(lessonId, status),
    );
  }
}
