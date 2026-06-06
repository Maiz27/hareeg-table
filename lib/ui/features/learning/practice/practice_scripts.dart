import '../../../../domain/classic_hareeg/game/classic_hareeg_action.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../models/practice_catalog.dart';
import 'practice_board.dart';
import 'practice_lesson_script.dart';

/// Registry of playable practice lesson scripts, keyed by catalog lesson id.
///
/// Lessons without a script yet show a coming-soon notice in the checklist;
/// each practice pack slice (HT-46..HT-48) registers its scripts here.
///
/// The core turn pack teaches strictly in order: the draw → discard loop,
/// then a first opening from the player's own hand, then an opening that
/// leans on the discard pile, then judging when the pile is a trap, and
/// finally multi-meld staging. Opening lessons deal the real 14-card hand —
/// only the loop lesson trims the hand so the heartbeat stays in focus.
abstract final class PracticeScripts {
  /// Script for [lessonId], or null while the lesson's pack has not shipped.
  static PracticeLessonScript? byId(String lessonId) {
    return switch (lessonId) {
      'turn-rhythm' => turnRhythm(),
      'first-meld' => firstMeld(),
      'discard-opening' => discardOpening(),
      'bait-discard' => baitDiscard(),
      'opening-51' => openingTo51(),
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
  /// The proving lesson for the scenario harness (HT-45). The teaching hand
  /// deliberately holds no meld and stays small so the focus is purely the
  /// draw → discard heartbeat.
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

  /// First opening meld: a real 14-card hand already holds a six-card run
  /// worth 59 — past the 51 benchmark in one play. Draw, place it, discard.
  ///
  /// A five-card royal run is only 50 under the card values (ace counts 10),
  /// so the sixth card is the quiet first taste of opening arithmetic.
  static PracticeLessonScript firstMeld() {
    // The ready opening run: 9-10-J-Q-K-A of hearts = 59.
    final heartRun = [
      PracticeBoard.card(CardRank.nine, CardSuit.hearts),
      PracticeBoard.card(CardRank.ten, CardSuit.hearts),
      PracticeBoard.card(CardRank.jack, CardSuit.hearts),
      PracticeBoard.card(CardRank.queen, CardSuit.hearts),
      PracticeBoard.card(CardRank.king, CardSuit.hearts),
      PracticeBoard.card(CardRank.ace, CardSuit.hearts),
    ];
    return PracticeLessonScript(
      lessonId: 'first-meld',
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          ...heartRun,
          // Fillers: no second meld, no run cover (8 of hearts stays out so
          // the closing discard can never hit the cover-discard block).
          PracticeBoard.card(CardRank.two, CardSuit.clubs),
          PracticeBoard.card(CardRank.three, CardSuit.spades),
          PracticeBoard.card(CardRank.four, CardSuit.diamonds),
          PracticeBoard.card(CardRank.five, CardSuit.spades),
          PracticeBoard.card(CardRank.seven, CardSuit.clubs),
          PracticeBoard.card(CardRank.nine, CardSuit.diamonds),
          PracticeBoard.card(CardRank.jack, CardSuit.spades),
          PracticeBoard.card(CardRank.queen, CardSuit.diamonds),
        ],
        topDiscard: PracticeBoard.card(CardRank.six, CardSuit.spades),
      ),
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceTurnRhythmStep1,
          kinds: const {ClassicHareegActionKind.drawStock},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceFirstMeldStep2,
          hint: (s) => s.practiceFirstMeldStep2Hint,
          successNote: (s) => s.practiceFirstMeldStep2Done,
          // A valid partial run (K-Q-J) stages below the benchmark and would
          // otherwise leave the static prompt repeating itself — react with
          // the way out instead.
          holdNote: (s) => s.practiceFirstMeldStep2Hold,
          kinds: const {ClassicHareegActionKind.playMeld},
          highlightCardIds: {for (final card in heartRun) card.id},
          // Staging below the benchmark applies but does not demonstrate the
          // opening; the step holds until the table is actually open.
          isSatisfied: (context) => context.controller.openingState.hasOpened(
            PlayerSeat.south,
          ),
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceFirstMeldStep3,
          hint: (s) => s.practiceTurnRhythmStep2Hint,
          kinds: const {ClassicHareegActionKind.discard},
        ),
      ],
    );
  }

  /// Opening from the discard: west visibly draws and throws the eight that
  /// turns a held pair into a set — queens (30) plus eights (24) open at 54.
  ///
  /// First contact with take-discard, taught in the only context a new
  /// player has a reason to take: the card opens the table. Where the
  /// first-meld lesson taught a one-suit sequence, this one opens with two
  /// rank sets, so the player meets both meld shapes early. The scripted
  /// intro plays west's turn for real, so the player watches the discard
  /// land instead of finding it pre-baked on the pile.
  static PracticeLessonScript discardOpening() {
    // A ready set of queens (30) and a pair of eights waiting for west's
    // third eight (24) — together 54, past the 51 benchmark.
    final queens = [
      PracticeBoard.card(CardRank.queen, CardSuit.spades),
      PracticeBoard.card(CardRank.queen, CardSuit.diamonds),
      PracticeBoard.card(CardRank.queen, CardSuit.hearts),
    ];
    final eightPair = [
      PracticeBoard.card(CardRank.eight, CardSuit.clubs),
      PracticeBoard.card(CardRank.eight, CardSuit.hearts),
    ];
    final eightDiamonds = PracticeBoard.card(
      CardRank.eight,
      CardSuit.diamonds,
    );
    return PracticeLessonScript(
      lessonId: 'discard-opening',
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          ...queens,
          ...eightPair,
          // Fillers: no third meld, and neither set's cover card (no queen
          // of clubs, no eight of spades) so the closing discard always has
          // safe cards.
          PracticeBoard.card(CardRank.two, CardSuit.hearts),
          PracticeBoard.card(CardRank.three, CardSuit.spades),
          PracticeBoard.card(CardRank.four, CardSuit.diamonds),
          PracticeBoard.card(CardRank.five, CardSuit.hearts),
          PracticeBoard.card(CardRank.six, CardSuit.spades),
          PracticeBoard.card(CardRank.nine, CardSuit.diamonds),
          PracticeBoard.card(CardRank.ten, CardSuit.hearts),
          PracticeBoard.card(CardRank.jack, CardSuit.spades),
          PracticeBoard.card(CardRank.ace, CardSuit.diamonds),
        ],
        cpuSeedCards: {
          PlayerSeat.west: [eightDiamonds],
        },
        currentSeat: PlayerSeat.west,
      ),
      introActionIds: [
        ClassicHareegActionIds.drawStock,
        '${ClassicHareegActionIds.discardPrefix}${eightDiamonds.id}',
      ],
      steps: [
        // Stepwise guidance, one meld per step (the opening-51 pattern):
        // ringing the whole 54 at once invites mis-grouping the cards.
        PracticeStep.kinds(
          prompt: (s) => s.practiceDiscardOpeningStep1,
          successNote: (s) => s.practiceDiscardOpeningStep1Done,
          kinds: const {ClassicHareegActionKind.takeDiscard},
          // The pair the take completes rings alongside the pile.
          highlightCardIds: {for (final card in eightPair) card.id},
        ),
        // The engine forces the pending eight into the first play, so any
        // successful meld here is the eights — staged at 24.
        PracticeStep.kinds(
          prompt: (s) => s.practiceDiscardOpeningStep2,
          hint: (s) => s.practiceDiscardOpeningStep2Hint,
          successNote: (s) => s.practiceDiscardOpeningStep2Done,
          kinds: const {ClassicHareegActionKind.playMeld},
          highlightCardIds: {
            for (final card in eightPair) card.id,
            eightDiamonds.id,
          },
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceDiscardOpeningStep3,
          successNote: (s) => s.practiceDiscardOpeningStep3Done,
          kinds: const {ClassicHareegActionKind.playMeld},
          highlightCardIds: {for (final card in queens) card.id},
          isSatisfied: (context) => context.controller.openingState.hasOpened(
            PlayerSeat.south,
          ),
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceDiscardOpeningStep4,
          hint: (s) => s.practiceTurnRhythmStep2Hint,
          kinds: const {ClassicHareegActionKind.discard},
        ),
      ],
    );
  }

  /// The bait discard: the pile pairs with the hand, but even used it stays
  /// far below the benchmark — the correct move is to leave it and draw.
  ///
  /// The scripted intro has west genuinely open on the table — kings plus a
  /// 6-7-8 run, exactly the 51 benchmark, so the displayed requirement stays
  /// coherent — and then throw the tempting seven. The player's first look
  /// at what an opened seat is allowed to do is a real turn, not pre-baked
  /// table state.
  static PracticeLessonScript baitDiscard() {
    final westKings = [
      PracticeBoard.card(CardRank.king, CardSuit.hearts),
      PracticeBoard.card(CardRank.king, CardSuit.diamonds),
      PracticeBoard.card(CardRank.king, CardSuit.spades),
    ];
    final westRun = [
      PracticeBoard.card(CardRank.six, CardSuit.diamonds),
      PracticeBoard.card(CardRank.seven, CardSuit.diamonds),
      PracticeBoard.card(CardRank.eight, CardSuit.diamonds),
    ];
    final sevenHearts = PracticeBoard.card(CardRank.seven, CardSuit.hearts);
    return PracticeLessonScript(
      lessonId: 'bait-discard',
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          // The tempting pair: with the discarded seven it makes 21 — far
          // short of the 51 needed to open.
          PracticeBoard.card(CardRank.seven, CardSuit.spades),
          PracticeBoard.card(CardRank.seven, CardSuit.clubs),
          // Fillers: no meld anywhere, and none of west's cover cards
          // (no king of clubs, no 5 or 9 of diamonds) so every closing
          // discard stays safe.
          PracticeBoard.card(CardRank.two, CardSuit.spades),
          PracticeBoard.card(CardRank.two, CardSuit.diamonds),
          PracticeBoard.card(CardRank.three, CardSuit.hearts),
          PracticeBoard.card(CardRank.four, CardSuit.clubs),
          PracticeBoard.card(CardRank.four, CardSuit.diamonds),
          PracticeBoard.card(CardRank.five, CardSuit.hearts),
          PracticeBoard.card(CardRank.six, CardSuit.clubs),
          PracticeBoard.card(CardRank.eight, CardSuit.spades),
          PracticeBoard.card(CardRank.nine, CardSuit.hearts),
          PracticeBoard.card(CardRank.ten, CardSuit.spades),
          PracticeBoard.card(CardRank.jack, CardSuit.hearts),
          PracticeBoard.card(CardRank.queen, CardSuit.spades),
        ],
        cpuSeedCards: {
          PlayerSeat.west: [...westKings, ...westRun, sevenHearts],
        },
        currentSeat: PlayerSeat.west,
      ),
      introActionIds: [
        ClassicHareegActionIds.drawStock,
        ClassicHareegActionIds.playMeldActionId([
          for (final card in westKings) card.id,
        ]),
        ClassicHareegActionIds.playMeldActionId([
          for (final card in westRun) card.id,
        ]),
        '${ClassicHareegActionIds.discardPrefix}${sevenHearts.id}',
      ],
      steps: [
        // Only the stock draw is offered: taking the bait stays dark and the
        // prompt carries the judgment being taught.
        PracticeStep.kinds(
          prompt: (s) => s.practiceBaitStep1,
          successNote: (s) => s.practiceBaitStep1Done,
          kinds: const {ClassicHareegActionKind.drawStock},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceBaitStep2,
          hint: (s) => s.practiceTurnRhythmStep2Hint,
          kinds: const {ClassicHareegActionKind.discard},
        ),
      ],
    );
  }

  /// Opening to 51 by staging: no single meld reaches the benchmark, so the
  /// kings and jacks stack up within one turn before the opening seals.
  static PracticeLessonScript openingTo51() {
    final kings = [
      PracticeBoard.card(CardRank.king, CardSuit.spades),
      PracticeBoard.card(CardRank.king, CardSuit.diamonds),
      PracticeBoard.card(CardRank.king, CardSuit.hearts),
    ];
    final jacks = [
      PracticeBoard.card(CardRank.jack, CardSuit.clubs),
      PracticeBoard.card(CardRank.jack, CardSuit.diamonds),
      PracticeBoard.card(CardRank.jack, CardSuit.hearts),
    ];
    return PracticeLessonScript(
      lessonId: 'opening-51',
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          ...kings,
          ...jacks,
          // Fillers: no third meld, no king or jack covers in hand.
          PracticeBoard.card(CardRank.two, CardSuit.hearts),
          PracticeBoard.card(CardRank.three, CardSuit.clubs),
          PracticeBoard.card(CardRank.four, CardSuit.spades),
          PracticeBoard.card(CardRank.five, CardSuit.clubs),
          PracticeBoard.card(CardRank.six, CardSuit.hearts),
          PracticeBoard.card(CardRank.eight, CardSuit.spades),
          PracticeBoard.card(CardRank.nine, CardSuit.hearts),
          PracticeBoard.card(CardRank.ten, CardSuit.diamonds),
        ],
        topDiscard: PracticeBoard.card(CardRank.two, CardSuit.spades),
      ),
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceTurnRhythmStep1,
          kinds: const {ClassicHareegActionKind.drawStock},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceOpeningStep1,
          hint: (s) => s.practiceOpeningStep1Hint,
          successNote: (s) => s.practiceOpeningStep1Done,
          kinds: const {ClassicHareegActionKind.playMeld},
          highlightCardIds: {for (final card in kings) card.id},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceOpeningStep2,
          successNote: (s) => s.practiceOpeningStep2Done,
          holdNote: (s) => s.practiceOpeningStepHold,
          kinds: const {ClassicHareegActionKind.playMeld},
          highlightCardIds: {for (final card in jacks) card.id},
          isSatisfied: (context) => context.controller.openingState.hasOpened(
            PlayerSeat.south,
          ),
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceOpeningStep3,
          hint: (s) => s.practiceTurnRhythmStep2Hint,
          kinds: const {ClassicHareegActionKind.discard},
        ),
      ],
    );
  }
}
