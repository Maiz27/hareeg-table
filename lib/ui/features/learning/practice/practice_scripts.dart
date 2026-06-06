import '../../../../domain/classic_hareeg/game/classic_hareeg_action.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../models/practice_catalog.dart';
import 'practice_board.dart';
import 'practice_lesson_script.dart';

/// Registry of playable practice lesson scripts, keyed by catalog lesson id.
///
/// Lessons without a script yet show a coming-soon notice in the checklist;
/// each practice pack slice (HT-46..HT-48) registers its scripts here.
abstract final class PracticeScripts {
  /// Script for [lessonId], or null while the lesson's pack has not shipped.
  static PracticeLessonScript? byId(String lessonId) {
    return switch (lessonId) {
      'turn-rhythm' => turnRhythm(),
      _ => null,
    };
  }

  /// Script for the lesson after [lessonId] within the same practice pack.
  ///
  /// Returns null at the pack boundary (finishing a pack is a deliberate
  /// stopping point) or when the next lesson's script has not shipped yet.
  /// Drives the completion overlay's "next lesson" continuation.
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
    return byId(pack[index + 1].id);
  }

  /// Turn rhythm: draw from stock, then end the turn with a discard.
  ///
  /// The proving lesson for the scenario harness (HT-45); the rest of the
  /// core turn pack lands with HT-46. The teaching hand deliberately holds no
  /// meld so the focus stays on the draw → discard heartbeat.
  static PracticeLessonScript turnRhythm() {
    return PracticeLessonScript(
      lessonId: 'turn-rhythm',
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          PracticeBoard.card(CardRank.three, CardSuit.clubs),
          PracticeBoard.card(CardRank.seven, CardSuit.diamonds),
          PracticeBoard.card(CardRank.ten, CardSuit.spades),
          PracticeBoard.card(CardRank.king, CardSuit.hearts),
        ],
        topDiscard: PracticeBoard.card(CardRank.five, CardSuit.hearts),
      ),
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceTurnRhythmStep1,
          successNote: (s) => s.practiceTurnRhythmStep1Done,
          kinds: const {ClassicHareegActionKind.drawStock},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceTurnRhythmStep2,
          hint: (s) => s.practiceTurnRhythmStep2Hint,
          kinds: const {ClassicHareegActionKind.discard},
        ),
      ],
    );
  }
}
