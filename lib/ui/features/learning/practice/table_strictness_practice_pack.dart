import '../../../../domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import '../../../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import 'practice_board.dart';
import 'practice_lesson_script.dart';
import 'practice_script_authoring.dart';

/// Table-strictness guided-practice scripts in checklist order.
///
/// The strictness pack picks up where `cover-discard-block` left off: Standard
/// hard-blocks throwing a card the table can use, so the player never sees the
/// move land. The two scripted demos here move the same trapped-cover board to
/// the stricter tiers, where the throw IS offered — and let the player make it
/// on purpose to watch the price the engine charges. Strict reverts the throw
/// for +3; Table accepts it for +17 and removes the seat from the round. Both
/// reuse `TableMechanicsPracticePack.coverDiscardBlock`'s board (south unopened,
/// holding the 10♥ that would complete west's scripted tens set), changing only
/// the table's strictness tier so the escalation reads as one rule turned up.
abstract final class TableStrictnessPracticePack {
  /// Builds the shared trapped-cover board at [tier].
  ///
  /// West opens a 6-7-8♥ run plus a 10♠/10♦/10♣ set (exactly 51) through the
  /// scripted intro; south is unopened, holding the 10♥ that would complete the
  /// tens — a cover it can neither place (covers need an opened player) nor
  /// throw away (the table can use it). At Strict/Table the engine advertises
  /// the throw as a paid mistake, which is the whole lesson.
  static _StrictnessBoard _board(TableStrictness tier) {
    final westRun = [
      PracticeBoard.card(CardRank.six, CardSuit.hearts),
      PracticeBoard.card(CardRank.seven, CardSuit.hearts),
      PracticeBoard.card(CardRank.eight, CardSuit.hearts),
    ];
    final westTens = [
      PracticeBoard.card(CardRank.ten, CardSuit.spades),
      PracticeBoard.card(CardRank.ten, CardSuit.diamonds),
      PracticeBoard.card(CardRank.ten, CardSuit.clubs),
    ];
    final westThrow = PracticeBoard.card(CardRank.two, CardSuit.clubs);
    final tenHearts = PracticeBoard.card(CardRank.ten, CardSuit.hearts);
    return _StrictnessBoard(
      westRun: westRun,
      westTens: westTens,
      westThrow: westThrow,
      tenHearts: tenHearts,
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          tenHearts,
          // Fillers: no meld (south must stay unopened all lesson) and no
          // other cover of west's melds (no 5 or 9 of hearts), so the trapped
          // ten is the only card the pile refuses.
          PracticeBoard.card(CardRank.two, CardSuit.spades),
          PracticeBoard.card(CardRank.two, CardSuit.diamonds),
          PracticeBoard.card(CardRank.three, CardSuit.diamonds),
          PracticeBoard.card(CardRank.four, CardSuit.clubs),
          PracticeBoard.card(CardRank.five, CardSuit.spades),
          PracticeBoard.card(CardRank.six, CardSuit.diamonds),
          PracticeBoard.card(CardRank.seven, CardSuit.clubs),
          PracticeBoard.card(CardRank.eight, CardSuit.spades),
          PracticeBoard.card(CardRank.nine, CardSuit.diamonds),
          PracticeBoard.card(CardRank.jack, CardSuit.clubs),
          PracticeBoard.card(CardRank.queen, CardSuit.hearts),
          PracticeBoard.card(CardRank.king, CardSuit.diamonds),
          PracticeBoard.card(CardRank.ace, CardSuit.spades),
        ],
        cpuSeedCards: {
          PlayerSeat.west: [...westRun, ...westTens, westThrow],
        },
        currentSeat: PlayerSeat.west,
        setup: ClassicHareegSetup.defaults().copyWith(tableStrictness: tier),
      ),
    );
  }

  /// Scripted intro: west draws, opens its run then its tens, throws a safe
  /// card, and hands the turn to south.
  static List<String> _intro(_StrictnessBoard board) {
    return [
      ClassicHareegActionIds.drawStock,
      ClassicHareegActionIds.playMeldActionId([
        for (final card in board.westRun) card.id,
      ]),
      ClassicHareegActionIds.playMeldActionId([
        for (final card in board.westTens) card.id,
      ]),
      '${ClassicHareegActionIds.discardPrefix}${board.westThrow.id}',
    ];
  }

  /// Strict tier: the trapped-cover throw costs +3, then is reverted.
  ///
  /// Standard blocked this throw outright; Strict lets it land as a paid
  /// mistake. The single post-draw step teaches the throw itself: dragging the
  /// trapped ten to the pile charges +3 and snaps the card back (the engine
  /// reverts it), and that penalty completes the lesson. The step opts into
  /// `completesOnPenalty` so the session counts the reverted throw as the
  /// demonstrated move instead of collapsing it to a rejection. The score
  /// sheet then reveals the +3 on south's row before the completion panel —
  /// the same flow as `tablePenalty`, only the price differs.
  static PracticeLessonScript strictPenalty() {
    final board = _board(TableStrictness.strict);
    return PracticeLessonScript(
      lessonId: 'strict-penalty',
      // The trapped ten is never legally melded: the whole hand stays
      // meld-free.
      taughtMelds: const [],
      buildSnapshot: board.buildSnapshot,
      boardAuditSpec: PracticeScriptAuthoring.allHandsStayFull,
      introActionIds: _intro(board),
      showScoresOnCompletion: true,
      completionNote: (s, _) => s.practiceStrictPenaltyCompletion,
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceTurnRhythmStep1,
          kinds: const {ClassicHareegActionKind.drawStock},
        ),
        // The cover throw is the taught move: it reverts for +3 but completes
        // the lesson. `completesOnPenalty` lets the session treat the reverted
        // throw as the demonstrated move — `isSatisfied` checks the +3 landed —
        // so the lesson finishes on the penalty instead of stalling.
        PracticeStep(
          prompt: (s) => s.practiceStrictPenaltyStep1,
          hint: (s) => s.practiceStrictPenaltyStep1Hint,
          successNote: (s) => s.practiceStrictPenaltyStep1Done,
          completesOnPenalty: true,
          allows: (action) =>
              action.kind == ClassicHareegActionKind.discardBlockedCover,
          isSatisfied: (context) => context.result.revertedCardId != null,
          // Group 0: the trapped ten you hold. Group 1: west's set it would
          // complete — the reason the throw is penalised.
          highlightGroups: [
            {board.tenHearts.id},
            {for (final card in board.westTens) card.id},
          ],
        ),
      ],
    );
  }

  /// Table tier: the trapped-cover throw costs +17 and removes the seat.
  ///
  /// The harshest table: Strict reverted the throw, but Table accepts it. The
  /// throw lands (the ten leaves the hand, the +17 hits the score), the engine
  /// removes south from the round, and the lesson completes the instant that
  /// round-out lands. There is no safe-throw step — the penalty IS the end.
  static PracticeLessonScript tablePenalty() {
    final board = _board(TableStrictness.table);
    return PracticeLessonScript(
      lessonId: 'table-penalty',
      taughtMelds: const [],
      buildSnapshot: board.buildSnapshot,
      boardAuditSpec: PracticeScriptAuthoring.allHandsStayFull,
      introActionIds: _intro(board),
      showScoresOnCompletion: true,
      completionNote: (s, _) => s.practiceTablePenaltyCompletion,
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceTurnRhythmStep1,
          kinds: const {ClassicHareegActionKind.drawStock},
        ),
        // The cover throw is the taught move here: it goes through, prices the
        // seat +17, and takes south out of the round. The step completes the
        // instant the round-out lands — not on round-over (three CPUs play on).
        PracticeStep(
          prompt: (s) => s.practiceTablePenaltyStep1,
          hint: (s) => s.practiceTablePenaltyStep1Hint,
          successNote: (s) => s.practiceTablePenaltyStep1Done,
          allows: (action) =>
              action.kind == ClassicHareegActionKind.discardBlockedCover,
          isSatisfied: (context) =>
              context.controller.removedSeats.contains(PlayerSeat.south),
          highlightGroups: [
            {board.tenHearts.id},
            {for (final card in board.westTens) card.id},
          ],
        ),
      ],
    );
  }
}

/// Shared trapped-cover board pieces for the two strictness demos.
class _StrictnessBoard {
  _StrictnessBoard({
    required this.westRun,
    required this.westTens,
    required this.westThrow,
    required this.tenHearts,
    required this.buildSnapshot,
  });

  final List<HareegCard> westRun;
  final List<HareegCard> westTens;
  final HareegCard westThrow;
  final HareegCard tenHearts;
  final ClassicHareegMatchSnapshot Function() buildSnapshot;
}
