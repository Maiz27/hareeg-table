import 'practice_catalog.dart';
import 'practice_lesson_delivery.dart';
import '../practice/practice_lesson_script.dart';

export 'practice_lesson_delivery.dart';

/// Registry joining catalog entries to their concrete lesson delivery.
abstract final class PracticeLessonRegistry {
  /// Stable checklist lesson id for the strictness reading panel.
  static const strictnessTiersLessonId = 'strictness-tiers';

  /// Delivery for [lessonId].
  static PracticeLessonDelivery deliveryFor(String lessonId) {
    return PracticeCatalog.byId(lessonId)?.delivery ??
        const PracticeLessonDelivery.unavailable();
  }

  /// Script for [lessonId], or null when the lesson is not scripted.
  static PracticeLessonScript? scriptFor(String lessonId) {
    return deliveryFor(lessonId).buildScript();
  }

  /// Script for the lesson after [lessonId] within the same practice pack.
  ///
  /// Returns null at the pack boundary or when the next lesson is not a
  /// scripted table lesson.
  static PracticeLessonScript? nextScriptInPack(String lessonId) {
    final lesson = PracticeCatalog.byId(lessonId);
    if (lesson == null) {
      return null;
    }
    final pack = PracticeCatalog.lessonsIn(lesson.pack);
    final index = pack.indexWhere((entry) => entry.id == lessonId);
    if (index == -1 || index + 1 >= pack.length) {
      return null;
    }
    return scriptFor(pack[index + 1].id);
  }
}
