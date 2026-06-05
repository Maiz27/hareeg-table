import '../../../../domain/classic_hareeg/game/classic_hareeg_action.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_round.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
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
      'pending-discard' => pendingDiscard(),
      'meld-picker' => meldPicker(),
      'opening-51' => openingTo51(),
      _ => null,
    };
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

  /// Pending discard: take it, then use it legally or return it.
  ///
  /// The top discard completes a set with two hand cards, so "use it" has an
  /// obvious payoff; the return path stays open and the final step accepts
  /// the extra stock draw that path requires. South starts opened so the
  /// meld is not staged behind the opening benchmark.
  static PracticeLessonScript pendingDiscard() {
    return PracticeLessonScript(
      lessonId: 'pending-discard',
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          PracticeBoard.card(CardRank.eight, CardSuit.clubs),
          PracticeBoard.card(CardRank.eight, CardSuit.hearts),
          PracticeBoard.card(CardRank.king, CardSuit.spades),
          PracticeBoard.card(CardRank.four, CardSuit.clubs),
        ],
        topDiscard: PracticeBoard.card(CardRank.eight, CardSuit.diamonds),
        openingState: PracticeBoard.openedFor(PlayerSeat.south),
      ),
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practicePendingStep1,
          successNote: (s) => s.practicePendingStep1Done,
          kinds: const {ClassicHareegActionKind.takeDiscard},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practicePendingStep2,
          hint: (s) => s.practicePendingStep2Hint,
          successNote: (s) => s.practicePendingStep2Done,
          kinds: const {
            ClassicHareegActionKind.playMeld,
            ClassicHareegActionKind.returnPendingDiscard,
          },
        ),
        // The meld path is already in action phase; the return path is back
        // in draw phase, so the step also allows the stock draw it needs.
        PracticeStep.kinds(
          prompt: (s) => s.practicePendingStep3,
          kinds: const {
            ClassicHareegActionKind.discard,
            ClassicHareegActionKind.drawStock,
          },
          isSatisfied: (context) => context.action.isSafeDiscard,
        ),
      ],
    );
  }

  /// Legal meld selection: turn exactly the right cards into one meld.
  static PracticeLessonScript meldPicker() {
    return PracticeLessonScript(
      lessonId: 'meld-picker',
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          PracticeBoard.card(CardRank.five, CardSuit.spades),
          PracticeBoard.card(CardRank.six, CardSuit.spades),
          PracticeBoard.card(CardRank.seven, CardSuit.spades),
          PracticeBoard.card(CardRank.nine, CardSuit.diamonds),
          PracticeBoard.card(CardRank.queen, CardSuit.clubs),
        ],
        topDiscard: PracticeBoard.card(CardRank.two, CardSuit.hearts),
        openingState: PracticeBoard.openedFor(PlayerSeat.south),
        turnPhase: TurnPhase.action,
      ),
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceMeldStep1,
          hint: (s) => s.practiceMeldStep1Hint,
          successNote: (s) => s.practiceMeldStep1Done,
          kinds: const {ClassicHareegActionKind.playMeld},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceMeldStep2,
          kinds: const {ClassicHareegActionKind.discard},
        ),
      ],
    );
  }

  /// Opening to 51: stage melds until their combined value reaches the
  /// requirement, then end the turn.
  static PracticeLessonScript openingTo51() {
    return PracticeLessonScript(
      lessonId: 'opening-51',
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          PracticeBoard.card(CardRank.king, CardSuit.spades),
          PracticeBoard.card(CardRank.king, CardSuit.diamonds),
          PracticeBoard.card(CardRank.king, CardSuit.hearts),
          PracticeBoard.card(CardRank.jack, CardSuit.clubs),
          PracticeBoard.card(CardRank.jack, CardSuit.diamonds),
          PracticeBoard.card(CardRank.jack, CardSuit.hearts),
          PracticeBoard.card(CardRank.three, CardSuit.clubs),
          PracticeBoard.card(CardRank.nine, CardSuit.hearts),
        ],
        topDiscard: PracticeBoard.card(CardRank.two, CardSuit.spades),
        turnPhase: TurnPhase.action,
      ),
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceOpeningStep1,
          hint: (s) => s.practiceOpeningStep1Hint,
          successNote: (s) => s.practiceOpeningStep1Done,
          kinds: const {ClassicHareegActionKind.playMeld},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceOpeningStep2,
          successNote: (s) => s.practiceOpeningStep2Done,
          kinds: const {ClassicHareegActionKind.playMeld},
          isSatisfied: (context) => context.controller.openingState.hasOpened(
            PlayerSeat.south,
          ),
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceOpeningStep3,
          kinds: const {ClassicHareegActionKind.discard},
        ),
      ],
    );
  }
}
