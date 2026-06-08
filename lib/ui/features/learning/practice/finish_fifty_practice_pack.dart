import '../../../../domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_round.dart';
import '../../../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../domain/classic_hareeg/rules/opening_rules.dart';
import 'practice_board.dart';
import 'practice_lesson_script.dart';
import 'practice_script_authoring.dart';

/// Finish and Fifty guided-practice scripts in checklist order.
///
/// The finish & Fifty pack plays end states: boards open mid-endgame (small
/// hands, a dressed discard pile carrying the shed-card story, short CPU
/// hands on the seat badges) and the round genuinely ends — the engine
/// applies the real scoring the completion panel reads back.
abstract final class FinishFiftyPracticePack {
  /// The final discard: a finish always keeps one last card to throw.
  ///
  /// A deep-endgame board mid-turn: every played turn pairs its draw with
  /// its discard, so the player's hand plus their own table cards must read
  /// as one dealt 14 — plus the card just drawn. Here the table carries
  /// three earlier melds at exactly 51 (eleven cards) and the hand is down
  /// to four. Meld the nines, and the rules leave exactly one legal way
  /// out: the last card leaves as a discard, never a play. The engine
  /// genuinely ends the round.
  static PracticeLessonScript finalDiscard() {
    final priorThrees = [
      PracticeBoard.card(CardRank.three, CardSuit.spades),
      PracticeBoard.card(CardRank.three, CardSuit.diamonds),
      PracticeBoard.card(CardRank.three, CardSuit.hearts),
    ];
    final priorFours = [
      PracticeBoard.card(CardRank.four, CardSuit.spades),
      PracticeBoard.card(CardRank.four, CardSuit.hearts),
      PracticeBoard.card(CardRank.four, CardSuit.clubs),
    ];
    // The diamond run keeps the 5 of spades the lesson holds back for the
    // throw safely outside every cover.
    final priorRun = [
      PracticeBoard.card(CardRank.four, CardSuit.diamonds),
      PracticeBoard.card(CardRank.five, CardSuit.diamonds),
      PracticeBoard.card(CardRank.six, CardSuit.diamonds),
      PracticeBoard.card(CardRank.seven, CardSuit.diamonds),
      PracticeBoard.card(CardRank.eight, CardSuit.diamonds),
    ];
    final nines = [
      PracticeBoard.card(CardRank.nine, CardSuit.clubs),
      PracticeBoard.card(CardRank.nine, CardSuit.diamonds),
      PracticeBoard.card(CardRank.nine, CardSuit.hearts),
    ];
    final ninesIds = {for (final card in nines) card.id};
    final fiveSpades = PracticeBoard.card(CardRank.five, CardSuit.spades);
    return PracticeLessonScript(
      lessonId: 'final-discard',
      taughtMelds: [ninesIds],
      buildSnapshot: () => PracticeBoard.build(
        // Mid-turn accounting: 11 table cards + 4 in hand = 14 dealt plus
        // the card this turn's draw just added.
        southHand: [...nines, fiveSpades],
        // The round's discard history: every turn before this one ended
        // with a throw.
        priorDiscards: [
          PracticeBoard.card(CardRank.jack, CardSuit.clubs),
          PracticeBoard.card(CardRank.ten, CardSuit.clubs),
          PracticeBoard.card(CardRank.queen, CardSuit.diamonds),
          PracticeBoard.card(CardRank.six, CardSuit.spades),
        ],
        topDiscard: PracticeBoard.card(CardRank.two, CardSuit.hearts),
        tableMelds: {
          PlayerSeat.south: [
            PlacedMeld.fromCards(priorThrees),
            PlacedMeld.fromCards(priorFours),
            PlacedMeld.fromCards(priorRun),
          ],
        },
        openingState: PracticeBoard.openedFor(PlayerSeat.south),
        // Mid-turn: the draw already happened, the finish is the lesson.
        turnPhase: TurnPhase.action,
      ),
      boardAuditSpec: PracticeScriptAuthoring.southOpened51MidTurn,
      steps: [
        PracticeStep(
          prompt: (s) => s.practiceFinalDiscardStep1,
          hint: (s) => s.practiceFinalDiscardStep1Hint,
          successNote: (s) => s.practiceFinalDiscardStep1Done,
          allows: PracticeScriptAuthoring.playsExactly(ninesIds),
          isDemonstrated: PracticeScriptAuthoring.tableHolds(
            PlayerSeat.south,
            ninesIds,
          ),
          highlightCardIds: ninesIds,
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceFinalDiscardStep2,
          hint: (s) => s.practiceTurnRhythmStep2Hint,
          kinds: const {ClassicHareegActionKind.discard},
          highlightCardIds: {fiveSpades.id},
          // Only the round actually ending proves the finish.
          isSatisfied: (context) => context.controller.isRoundOver,
        ),
      ],
      completionNote: (s, _) => s.practiceFinalDiscardCompletion,
    );
  }

  /// A clean normal finish: empty the hand through melds, go out on the
  /// last discard, and read the score consequence off the completion panel.
  ///
  /// Mid-turn accounting again: the earlier opening (aces plus a club run,
  /// exactly 51) plus nine hand cards = 14 dealt plus this turn's draw. The
  /// hand finishes in two plays — the queens, then a five-card heart run —
  /// with the spare seven left to throw.
  static PracticeLessonScript normalFinish() {
    final priorAces = [
      PracticeBoard.card(CardRank.ace, CardSuit.spades),
      PracticeBoard.card(CardRank.ace, CardSuit.diamonds),
      PracticeBoard.card(CardRank.ace, CardSuit.hearts),
    ];
    final priorRun = [
      PracticeBoard.card(CardRank.six, CardSuit.clubs),
      PracticeBoard.card(CardRank.seven, CardSuit.clubs),
      PracticeBoard.card(CardRank.eight, CardSuit.clubs),
    ];
    final queens = [
      PracticeBoard.card(CardRank.queen, CardSuit.clubs),
      PracticeBoard.card(CardRank.queen, CardSuit.diamonds),
      PracticeBoard.card(CardRank.queen, CardSuit.hearts),
    ];
    final queenIds = {for (final card in queens) card.id};
    final heartRun = [
      PracticeBoard.card(CardRank.four, CardSuit.hearts),
      PracticeBoard.card(CardRank.five, CardSuit.hearts),
      PracticeBoard.card(CardRank.six, CardSuit.hearts),
      PracticeBoard.card(CardRank.seven, CardSuit.hearts),
      PracticeBoard.card(CardRank.eight, CardSuit.hearts),
    ];
    final heartRunIds = {for (final card in heartRun) card.id};
    final sevenSpades = PracticeBoard.card(CardRank.seven, CardSuit.spades);
    return PracticeLessonScript(
      lessonId: 'normal-finish',
      taughtMelds: [queenIds, heartRunIds],
      buildSnapshot: () => PracticeBoard.build(
        // Mid-turn accounting: 6 table cards + 9 in hand = 14 dealt plus
        // the card this turn's draw just added.
        southHand: [...queens, ...heartRun, sevenSpades],
        priorDiscards: [
          PracticeBoard.card(CardRank.ten, CardSuit.diamonds),
          PracticeBoard.card(CardRank.jack, CardSuit.hearts),
          PracticeBoard.card(CardRank.two, CardSuit.diamonds),
        ],
        topDiscard: PracticeBoard.card(CardRank.two, CardSuit.spades),
        tableMelds: {
          PlayerSeat.south: [
            PlacedMeld.fromCards(priorAces),
            PlacedMeld.fromCards(priorRun),
          ],
        },
        openingState: PracticeBoard.openedFor(PlayerSeat.south),
        turnPhase: TurnPhase.action,
      ),
      boardAuditSpec: PracticeScriptAuthoring.southOpened51MidTurnNoPileMinimum,
      steps: [
        // One meld per step, each ringing only its own cards (the
        // stepwise-highlighting rule).
        PracticeStep(
          prompt: (s) => s.practiceNormalFinishStep1,
          successNote: (s) => s.practiceNormalFinishStep1Done,
          allows: PracticeScriptAuthoring.playsExactly(queenIds),
          isDemonstrated: PracticeScriptAuthoring.tableHolds(
            PlayerSeat.south,
            queenIds,
          ),
          highlightCardIds: queenIds,
        ),
        PracticeStep(
          prompt: (s) => s.practiceNormalFinishStep2,
          hint: (s) => s.practiceNormalFinishStep2Hint,
          allows: PracticeScriptAuthoring.playsExactly(heartRunIds),
          isDemonstrated: PracticeScriptAuthoring.tableHolds(
            PlayerSeat.south,
            heartRunIds,
          ),
          highlightCardIds: heartRunIds,
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceNormalFinishStep3,
          hint: (s) => s.practiceTurnRhythmStep2Hint,
          kinds: const {ClassicHareegActionKind.discard},
          highlightCardIds: {sevenSpades.id},
          isSatisfied: (context) => context.controller.isRoundOver,
        ),
      ],
      // A normal finish scores like a real round (winner -1, losers add their
      // leftover cards); open the real score sheet so the player reads the
      // consequence where a match would show it, not just in the panel note.
      completionNote: (s, _) => s.practiceNormalFinishCompletion,
      showScoresOnCompletion: true,
    );
  }

  /// Perfect hand: a whole hand of melds finishes without ever opening.
  ///
  /// South never opened, yet every card melds and the four sets total 47 —
  /// below the 51 benchmark. The player stages each set in turn (the table
  /// advertises every one as a legal single meld); the opening climbs
  /// 8 → 20 → 32 → 47 and never seals, but laying the whole hand finishes the
  /// round outright through the perfect-hand bypass when the spare king leaves
  /// as a plain discard. The seats that never opened pay their full hand
  /// count, so a perfect close still stings the room.
  static PracticeLessonScript perfectHandFinish() {
    final twos = [
      PracticeBoard.card(CardRank.two, CardSuit.clubs),
      PracticeBoard.card(CardRank.two, CardSuit.diamonds),
      PracticeBoard.card(CardRank.two, CardSuit.hearts),
      PracticeBoard.card(CardRank.two, CardSuit.spades),
    ];
    final threes = [
      PracticeBoard.card(CardRank.three, CardSuit.clubs),
      PracticeBoard.card(CardRank.three, CardSuit.diamonds),
      PracticeBoard.card(CardRank.three, CardSuit.hearts),
      PracticeBoard.card(CardRank.three, CardSuit.spades),
    ];
    final fours = [
      PracticeBoard.card(CardRank.four, CardSuit.clubs),
      PracticeBoard.card(CardRank.four, CardSuit.diamonds),
      PracticeBoard.card(CardRank.four, CardSuit.hearts),
    ];
    final fives = [
      PracticeBoard.card(CardRank.five, CardSuit.clubs),
      PracticeBoard.card(CardRank.five, CardSuit.diamonds),
      PracticeBoard.card(CardRank.five, CardSuit.hearts),
    ];
    final twosIds = {for (final card in twos) card.id};
    final threesIds = {for (final card in threes) card.id};
    final foursIds = {for (final card in fours) card.id};
    final fivesIds = {for (final card in fives) card.id};
    final meldCards = [...twos, ...threes, ...fours, ...fives];
    final kingSpades = PracticeBoard.card(CardRank.king, CardSuit.spades);
    return PracticeLessonScript(
      lessonId: 'perfect-hand-finish',
      // The four sets total 47, below 51; the king is the lone filler that
      // leaves as the finishing throw.
      taughtMelds: [twosIds, threesIds, foursIds, fivesIds],
      buildSnapshot: () => PracticeBoard.build(
        // Unopened mid-turn: nothing on the table, 14 dealt cards plus the
        // card this turn's draw just added.
        southHand: [...meldCards, kingSpades],
        priorDiscards: [
          PracticeBoard.card(CardRank.jack, CardSuit.clubs),
          PracticeBoard.card(CardRank.ten, CardSuit.diamonds),
          PracticeBoard.card(CardRank.queen, CardSuit.hearts),
          PracticeBoard.card(CardRank.nine, CardSuit.spades),
        ],
        topDiscard: PracticeBoard.card(CardRank.six, CardSuit.clubs),
        // No openedFor: south stays unopened, and the perfect hand bypasses
        // the benchmark entirely.
        turnPhase: TurnPhase.action,
      ),
      boardAuditSpec: PracticeScriptAuthoring.southUnopenedMidTurn,
      steps: [
        // Each set stages as its own single meld — the table never surfaces a
        // 14-card bundle to gestures. One step per set, exactly like
        // openingTo51's staging: the opening climbs 8 → 20 → 32 → 47 and never
        // seals (south never opens), so the staged plays satisfy by default on
        // the allowed play, just as openingTo51's non-final meld does.
        PracticeStep(
          prompt: (s) => s.practicePerfectHandTwos,
          hint: (s) => s.practicePerfectHandTwosHint,
          successNote: (s) => s.practicePerfectHandTwosDone,
          allows: PracticeScriptAuthoring.playsExactly(twosIds),
          isDemonstrated: PracticeScriptAuthoring.tableHolds(
            PlayerSeat.south,
            twosIds,
          ),
          highlightCardIds: twosIds,
        ),
        PracticeStep(
          prompt: (s) => s.practicePerfectHandThrees,
          hint: (s) => s.practicePerfectHandThreesHint,
          successNote: (s) => s.practicePerfectHandThreesDone,
          allows: PracticeScriptAuthoring.playsExactly(threesIds),
          isDemonstrated: PracticeScriptAuthoring.tableHolds(
            PlayerSeat.south,
            threesIds,
          ),
          highlightCardIds: threesIds,
        ),
        PracticeStep(
          prompt: (s) => s.practicePerfectHandFours,
          hint: (s) => s.practicePerfectHandFoursHint,
          successNote: (s) => s.practicePerfectHandFoursDone,
          allows: PracticeScriptAuthoring.playsExactly(foursIds),
          isDemonstrated: PracticeScriptAuthoring.tableHolds(
            PlayerSeat.south,
            foursIds,
          ),
          highlightCardIds: foursIds,
        ),
        PracticeStep(
          prompt: (s) => s.practicePerfectHandFives,
          hint: (s) => s.practicePerfectHandFivesHint,
          successNote: (s) => s.practicePerfectHandFivesDone,
          allows: PracticeScriptAuthoring.playsExactly(fivesIds),
          isDemonstrated: PracticeScriptAuthoring.tableHolds(
            PlayerSeat.south,
            fivesIds,
          ),
          highlightCardIds: fivesIds,
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practicePerfectHandStep2,
          hint: (s) => s.practiceTurnRhythmStep2Hint,
          kinds: const {ClassicHareegActionKind.discard},
          highlightCardIds: {kingSpades.id},
          isSatisfied: (context) => context.controller.isRoundOver,
        ),
      ],
      completionNote: (s, _) => s.practicePerfectHandCompletion,
      showScoresOnCompletion: true,
    );
  }

  /// Joker out: a joker cannot be thrown in play, but it may be your close.
  ///
  /// A deep-endgame board, south opened, hand down to a completable set plus
  /// the joker. The eights go down, leaving the joker alone — and the engine
  /// offers it as a plain discard, the one moment a joker may leave the hand:
  /// the finishing throw. (During normal play the pile always refuses it.)
  static PracticeLessonScript jokerFinalDiscard() {
    final priorSixes = [
      PracticeBoard.card(CardRank.six, CardSuit.clubs),
      PracticeBoard.card(CardRank.six, CardSuit.diamonds),
      PracticeBoard.card(CardRank.six, CardSuit.hearts),
    ];
    final priorQueens = [
      PracticeBoard.card(CardRank.queen, CardSuit.clubs),
      PracticeBoard.card(CardRank.queen, CardSuit.diamonds),
      PracticeBoard.card(CardRank.queen, CardSuit.spades),
    ];
    final priorRun = [
      PracticeBoard.card(CardRank.four, CardSuit.spades),
      PracticeBoard.card(CardRank.five, CardSuit.spades),
      PracticeBoard.card(CardRank.six, CardSuit.spades),
      PracticeBoard.card(CardRank.seven, CardSuit.spades),
      PracticeBoard.card(CardRank.eight, CardSuit.spades),
    ];
    final eights = [
      PracticeBoard.card(CardRank.eight, CardSuit.clubs),
      PracticeBoard.card(CardRank.eight, CardSuit.diamonds),
      PracticeBoard.card(CardRank.eight, CardSuit.hearts),
    ];
    final eightsIds = {for (final card in eights) card.id};
    final joker = PracticeBoard.joker();
    return PracticeLessonScript(
      lessonId: 'joker-final-discard',
      // The lone joker is filler — one joker forms no meld — and it leaves as
      // the finishing throw.
      taughtMelds: [eightsIds],
      buildSnapshot: () => PracticeBoard.build(
        // Mid-turn accounting: 11 table cards + 4 in hand = 14 dealt plus
        // the card this turn's draw just added.
        southHand: [...eights, joker],
        priorDiscards: [
          PracticeBoard.card(CardRank.jack, CardSuit.diamonds),
          PracticeBoard.card(CardRank.ten, CardSuit.hearts),
          PracticeBoard.card(CardRank.nine, CardSuit.clubs),
          PracticeBoard.card(CardRank.two, CardSuit.spades),
        ],
        topDiscard: PracticeBoard.card(CardRank.three, CardSuit.diamonds),
        tableMelds: {
          PlayerSeat.south: [
            PlacedMeld.fromCards(priorSixes),
            PlacedMeld.fromCards(priorQueens),
            PlacedMeld.fromCards(priorRun),
          ],
        },
        openingState: PracticeBoard.openedFor(PlayerSeat.south),
        turnPhase: TurnPhase.action,
      ),
      boardAuditSpec: PracticeScriptAuthoring.southOpenedMidTurnNoValue,
      steps: [
        PracticeStep(
          prompt: (s) => s.practiceJokerOutStep1,
          hint: (s) => s.practiceJokerOutStep1Hint,
          successNote: (s) => s.practiceJokerOutStep1Done,
          allows: PracticeScriptAuthoring.playsExactly(eightsIds),
          isDemonstrated: PracticeScriptAuthoring.tableHolds(
            PlayerSeat.south,
            eightsIds,
          ),
          highlightCardIds: eightsIds,
        ),
        // The joker leaves as a plain discard — the only legal way a joker
        // ever goes to the pile, and only because it closes the round.
        PracticeStep.kinds(
          prompt: (s) => s.practiceJokerOutStep2,
          hint: (s) => s.practiceJokerOutStep2Hint,
          kinds: const {ClassicHareegActionKind.discard},
          highlightCardIds: {joker.id},
          isSatisfied: (context) => context.controller.isRoundOver,
        ),
      ],
      completionNote: (s, _) => s.practiceJokerOutCompletion,
    );
  }

  /// Fifty timing: claim the previous discard before the window closes,
  /// then prove the finish by hand.
  ///
  /// West's scripted turn throws the eight the player's hand can finish
  /// around, and the throw itself opens the real claim window — the flame
  /// ring counts down for real, then holds at three so reading the prompt
  /// is never punished (a match gives four uninterrupted seconds; the hint
  /// says the table is waiting). The claim only takes the card; the proof
  /// is the player's to lay down, untimed: the eights the claimed card
  /// completes, the twos, and the queen leaves as the finishing throw.
  static PracticeLessonScript fiftyClaim({bool pauseTimer = true}) {
    final priorSevens = [
      PracticeBoard.card(CardRank.seven, CardSuit.clubs),
      PracticeBoard.card(CardRank.seven, CardSuit.diamonds),
      PracticeBoard.card(CardRank.seven, CardSuit.hearts),
    ];
    final priorRun = [
      PracticeBoard.card(CardRank.four, CardSuit.spades),
      PracticeBoard.card(CardRank.five, CardSuit.spades),
      PracticeBoard.card(CardRank.six, CardSuit.spades),
      PracticeBoard.card(CardRank.seven, CardSuit.spades),
      PracticeBoard.card(CardRank.eight, CardSuit.spades),
    ];
    final eightPair = [
      PracticeBoard.card(CardRank.eight, CardSuit.clubs),
      PracticeBoard.card(CardRank.eight, CardSuit.hearts),
    ];
    final twos = [
      PracticeBoard.card(CardRank.two, CardSuit.spades),
      PracticeBoard.card(CardRank.two, CardSuit.diamonds),
      PracticeBoard.card(CardRank.two, CardSuit.hearts),
    ];
    final eightDiamonds = PracticeBoard.card(CardRank.eight, CardSuit.diamonds);
    final eightsIds = {for (final card in eightPair) card.id, eightDiamonds.id};
    final twosIds = {for (final card in twos) card.id};
    final queenSpades = PracticeBoard.card(CardRank.queen, CardSuit.spades);
    return PracticeLessonScript(
      lessonId: 'fifty-claim',
      taughtMelds: [eightsIds, twosIds],
      buildSnapshot: () => PracticeBoard.build(
        // Turn-start accounting: 8 table cards + 6 in hand = the dealt 14
        // (the claim happens instead of this turn's draw).
        southHand: [...eightPair, ...twos, queenSpades],
        priorDiscards: [
          PracticeBoard.card(CardRank.three, CardSuit.hearts),
          PracticeBoard.card(CardRank.jack, CardSuit.diamonds),
          PracticeBoard.card(CardRank.ten, CardSuit.hearts),
          PracticeBoard.card(CardRank.king, CardSuit.diamonds),
          PracticeBoard.card(CardRank.six, CardSuit.hearts),
        ],
        tableMelds: {
          PlayerSeat.south: [
            PlacedMeld.fromCards(priorSevens),
            PlacedMeld.fromCards(priorRun),
          ],
        },
        openingState: PracticeBoard.openedFor(PlayerSeat.south),
        cpuSeedCards: {
          PlayerSeat.west: [eightDiamonds],
        },
        currentSeat: PlayerSeat.west,
        // The window math is real, so the lesson dodges the first-dealt-
        // round -1/-3 exception by playing a later round.
        roundNumber: 2,
        setup: ClassicHareegSetup.defaults().copyWith(fiftyTimerSeconds: 8),
      ),
      boardAuditSpec: PracticeScriptAuthoring.southOpened51LateTurnStart,
      introActionIds: [
        ClassicHareegActionIds.drawStock,
        '${ClassicHareegActionIds.discardPrefix}${eightDiamonds.id}',
      ],
      fiftyTimerPausesAtSeconds: pauseTimer ? 3 : null,
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceFiftyClaimStep1,
          hint: (s) => s.practiceFiftyClaimStep1Hint,
          deadEndNote: (s) => s.practiceFiftyMissed,
          kinds: const {ClassicHareegActionKind.claimFifty},
          highlightCardIds: {for (final card in eightPair) card.id},
          // The claim leaves the rules surface for good when the window
          // dies on the player's turn; only a fresh board restores it.
          // Unreachable while the timer holds — kept as the safety net.
          // (Once the claim applies the step advances, so the predicate
          // never sees the proof turn's window-less board.)
          isDeadEnd: (controller) =>
              controller.currentSeat == PlayerSeat.south &&
              controller.fiftySecondsRemaining == null,
        ),
        // The proof, one meld per step: the claimed card's meld first —
        // any order is legal under the engine, but the taught line starts
        // where the claim points.
        PracticeStep(
          prompt: (s) => s.practiceFiftyClaimStep2,
          hint: (s) => s.practiceFiftyClaimStep2Hint,
          successNote: (s) => s.practiceFiftyClaimStep2Done,
          allows: PracticeScriptAuthoring.playsExactly(eightsIds),
          isDemonstrated: PracticeScriptAuthoring.tableHolds(
            PlayerSeat.south,
            eightsIds,
          ),
          highlightCardIds: eightsIds,
        ),
        PracticeStep(
          prompt: (s) => s.practiceFiftyClaimStep3,
          hint: (s) => s.practicePendingStep4Hint,
          allows: PracticeScriptAuthoring.playsExactly(twosIds),
          isDemonstrated: PracticeScriptAuthoring.tableHolds(
            PlayerSeat.south,
            twosIds,
          ),
          highlightCardIds: twosIds,
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceFiftyClaimStep4,
          hint: (s) => s.practiceTurnRhythmStep2Hint,
          kinds: const {ClassicHareegActionKind.discard},
          highlightCardIds: {queenSpades.id},
          isSatisfied: (context) => context.controller.isRoundOver,
        ),
      ],
      completionNote: (s, _) => s.practiceFiftyClaimCompletion,
    );
  }

  /// Fifty scoring: the same claim, watched through the score sheet.
  ///
  /// Scores start from zero so the sheet reads as the round's own effect:
  /// the claimant's -3, and the discarder's full unopened hand plus 3 —
  /// the punishment is the lesson. The REAL score sheet opens over the
  /// finished board before the completion panel, so the numbers are read
  /// where a match would show them.
  static PracticeLessonScript fiftyScoring({bool pauseTimer = true}) {
    final priorThrees = [
      PracticeBoard.card(CardRank.three, CardSuit.spades),
      PracticeBoard.card(CardRank.three, CardSuit.diamonds),
      PracticeBoard.card(CardRank.three, CardSuit.hearts),
    ];
    final priorFours = [
      PracticeBoard.card(CardRank.four, CardSuit.spades),
      PracticeBoard.card(CardRank.four, CardSuit.diamonds),
      PracticeBoard.card(CardRank.four, CardSuit.hearts),
    ];
    final priorRun = [
      PracticeBoard.card(CardRank.four, CardSuit.clubs),
      PracticeBoard.card(CardRank.five, CardSuit.clubs),
      PracticeBoard.card(CardRank.six, CardSuit.clubs),
      PracticeBoard.card(CardRank.seven, CardSuit.clubs),
      PracticeBoard.card(CardRank.eight, CardSuit.clubs),
    ];
    final fivePair = [
      PracticeBoard.card(CardRank.five, CardSuit.diamonds),
      PracticeBoard.card(CardRank.five, CardSuit.spades),
    ];
    final fiveHearts = PracticeBoard.card(CardRank.five, CardSuit.hearts);
    final fivesIds = {for (final card in fivePair) card.id, fiveHearts.id};
    final kingClubs = PracticeBoard.card(CardRank.king, CardSuit.clubs);
    return PracticeLessonScript(
      lessonId: 'fifty-scoring',
      taughtMelds: [fivesIds],
      buildSnapshot: () => PracticeBoard.build(
        // Turn-start accounting: 11 table cards + 3 in hand = the dealt 14.
        southHand: [...fivePair, kingClubs],
        priorDiscards: [
          PracticeBoard.card(CardRank.two, CardSuit.clubs),
          PracticeBoard.card(CardRank.nine, CardSuit.hearts),
          PracticeBoard.card(CardRank.jack, CardSuit.spades),
          PracticeBoard.card(CardRank.six, CardSuit.diamonds),
          PracticeBoard.card(CardRank.ten, CardSuit.spades),
        ],
        tableMelds: {
          PlayerSeat.south: [
            PlacedMeld.fromCards(priorThrees),
            PlacedMeld.fromCards(priorFours),
            PlacedMeld.fromCards(priorRun),
          ],
        },
        openingState: PracticeBoard.openedFor(PlayerSeat.south),
        cpuSeedCards: {
          PlayerSeat.west: [fiveHearts],
        },
        currentSeat: PlayerSeat.west,
        roundNumber: 2,
        setup: ClassicHareegSetup.defaults().copyWith(fiftyTimerSeconds: 8),
      ),
      boardAuditSpec: PracticeScriptAuthoring.southOpened51LateTurnStart,
      introActionIds: [
        ClassicHareegActionIds.drawStock,
        '${ClassicHareegActionIds.discardPrefix}${fiveHearts.id}',
      ],
      fiftyTimerPausesAtSeconds: pauseTimer ? 3 : null,
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceFiftyScoringStep1,
          hint: (s) => s.practiceFiftyClaimStep1Hint,
          deadEndNote: (s) => s.practiceFiftyMissed,
          kinds: const {ClassicHareegActionKind.claimFifty},
          highlightCardIds: {for (final card in fivePair) card.id},
          isDeadEnd: (controller) =>
              controller.currentSeat == PlayerSeat.south &&
              controller.fiftySecondsRemaining == null,
        ),
        // The short proof: one set, then the throw the score sheet reads.
        PracticeStep(
          prompt: (s) => s.practiceFiftyScoringStep2,
          hint: (s) => s.practiceFiftyScoringStep2Hint,
          allows: PracticeScriptAuthoring.playsExactly(fivesIds),
          isDemonstrated: PracticeScriptAuthoring.tableHolds(
            PlayerSeat.south,
            fivesIds,
          ),
          highlightCardIds: fivesIds,
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceFiftyScoringStep3,
          hint: (s) => s.practiceTurnRhythmStep2Hint,
          kinds: const {ClassicHareegActionKind.discard},
          highlightCardIds: {kingClubs.id},
          isSatisfied: (context) => context.controller.isRoundOver,
        ),
      ],
      // The numbers live on the score sheet the lesson opens first; the
      // panel keeps only the rule behind them.
      completionNote: (s, _) => s.practiceFiftyScoringCompletion,
      showScoresOnCompletion: true,
    );
  }
}
