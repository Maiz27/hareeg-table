import '../../../../domain/classic_hareeg/game/classic_hareeg_action.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_round.dart';
import '../../../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../domain/classic_hareeg/rules/opening_rules.dart';
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
      'benchmark-pressure' => benchmarkPressure(),
      'sequence-cover' => sequenceCover(),
      'set-cover' => setCover(),
      'cover-discard-block' => coverDiscardBlock(),
      'joker-identity' => jokerIdentity(),
      'joker-replacement' => jokerReplacement(),
      'final-discard' => finalDiscard(),
      'normal-finish' => normalFinish(),
      'fifty-claim' => fiftyClaim(),
      'fifty-scoring' => fiftyScoring(),
      // 'strictness-tiers' is an explainer panel, not a scripted hand; the
      // checklist routes it to the tier explainer screen directly.
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

  /// Benchmark pressure: east opened high, so 51 is no longer enough.
  ///
  /// East's three table melds total 75 and the live benchmark matches. South
  /// stages 30, then 51 — the old requirement — and only crosses at 81.
  static PracticeLessonScript benchmarkPressure() {
    return PracticeLessonScript(
      lessonId: 'benchmark-pressure',
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          PracticeBoard.card(CardRank.king, CardSuit.spades),
          PracticeBoard.card(CardRank.king, CardSuit.diamonds),
          PracticeBoard.card(CardRank.king, CardSuit.hearts),
          PracticeBoard.card(CardRank.seven, CardSuit.clubs),
          PracticeBoard.card(CardRank.seven, CardSuit.diamonds),
          PracticeBoard.card(CardRank.seven, CardSuit.hearts),
          PracticeBoard.card(CardRank.queen, CardSuit.spades),
          PracticeBoard.card(CardRank.queen, CardSuit.diamonds),
          PracticeBoard.card(CardRank.queen, CardSuit.hearts),
          PracticeBoard.card(CardRank.three, CardSuit.clubs),
          PracticeBoard.card(CardRank.nine, CardSuit.spades),
        ],
        topDiscard: PracticeBoard.card(CardRank.two, CardSuit.hearts),
        tableMelds: {
          PlayerSeat.east: [
            PlacedMeld.fromCards([
              PracticeBoard.card(CardRank.king, CardSuit.spades, deckIndex: 1),
              PracticeBoard.card(
                CardRank.king,
                CardSuit.diamonds,
                deckIndex: 1,
              ),
              PracticeBoard.card(CardRank.king, CardSuit.hearts, deckIndex: 1),
            ]),
            PlacedMeld.fromCards([
              PracticeBoard.card(CardRank.queen, CardSuit.spades, deckIndex: 1),
              PracticeBoard.card(
                CardRank.queen,
                CardSuit.diamonds,
                deckIndex: 1,
              ),
              PracticeBoard.card(CardRank.queen, CardSuit.hearts, deckIndex: 1),
            ]),
            PlacedMeld.fromCards([
              PracticeBoard.card(CardRank.five, CardSuit.clubs, deckIndex: 1),
              PracticeBoard.card(
                CardRank.five,
                CardSuit.diamonds,
                deckIndex: 1,
              ),
              PracticeBoard.card(CardRank.five, CardSuit.hearts, deckIndex: 1),
            ]),
          ],
        },
        openingState: PracticeBoard.raisedBenchmark(
          opener: PlayerSeat.east,
          currentRequirement: 75,
        ),
        turnPhase: TurnPhase.action,
      ),
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceBenchmarkStep1,
          hint: (s) => s.practiceBenchmarkStep1Hint,
          successNote: (s) => s.practiceBenchmarkStep1Done,
          kinds: const {ClassicHareegActionKind.playMeld},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceBenchmarkStep2,
          successNote: (s) => s.practiceBenchmarkStep2Done,
          kinds: const {ClassicHareegActionKind.playMeld},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceBenchmarkStep3,
          successNote: (s) => s.practiceBenchmarkStep3Done,
          kinds: const {ClassicHareegActionKind.playMeld},
          isSatisfied: (context) => context.controller.openingState.hasOpened(
            PlayerSeat.south,
          ),
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceBenchmarkStep4,
          kinds: const {ClassicHareegActionKind.discard},
        ),
      ],
    );
  }

  /// Sequence cover: extend east's 5-6-7 of diamonds with the neighboring 8.
  static PracticeLessonScript sequenceCover() {
    return PracticeLessonScript(
      lessonId: 'sequence-cover',
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          PracticeBoard.card(CardRank.eight, CardSuit.diamonds),
          PracticeBoard.card(CardRank.three, CardSuit.clubs),
          PracticeBoard.card(CardRank.jack, CardSuit.spades),
        ],
        topDiscard: PracticeBoard.card(CardRank.two, CardSuit.hearts),
        tableMelds: {
          PlayerSeat.east: [
            PlacedMeld.fromCards([
              PracticeBoard.card(CardRank.five, CardSuit.diamonds, deckIndex: 1),
              PracticeBoard.card(CardRank.six, CardSuit.diamonds, deckIndex: 1),
              PracticeBoard.card(
                CardRank.seven,
                CardSuit.diamonds,
                deckIndex: 1,
              ),
            ]),
          ],
        },
        openingState: PracticeBoard.openedSeats(const {
          PlayerSeat.south,
          PlayerSeat.east,
        }),
        turnPhase: TurnPhase.action,
      ),
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceSeqCoverStep1,
          hint: (s) => s.practiceSeqCoverStep1Hint,
          successNote: (s) => s.practiceSeqCoverStep1Done,
          kinds: const {ClassicHareegActionKind.placeCover},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceCoverFinishStep,
          kinds: const {ClassicHareegActionKind.discard},
        ),
      ],
    );
  }

  /// Set cover: extend east's three kings with the missing spade.
  static PracticeLessonScript setCover() {
    return PracticeLessonScript(
      lessonId: 'set-cover',
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          PracticeBoard.card(CardRank.king, CardSuit.spades),
          PracticeBoard.card(CardRank.four, CardSuit.diamonds),
          PracticeBoard.card(CardRank.nine, CardSuit.clubs),
        ],
        topDiscard: PracticeBoard.card(CardRank.two, CardSuit.hearts),
        tableMelds: {
          PlayerSeat.east: [
            PlacedMeld.fromCards([
              PracticeBoard.card(CardRank.king, CardSuit.clubs, deckIndex: 1),
              PracticeBoard.card(
                CardRank.king,
                CardSuit.diamonds,
                deckIndex: 1,
              ),
              PracticeBoard.card(CardRank.king, CardSuit.hearts, deckIndex: 1),
            ]),
          ],
        },
        openingState: PracticeBoard.openedSeats(const {
          PlayerSeat.south,
          PlayerSeat.east,
        }),
        turnPhase: TurnPhase.action,
      ),
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceSetCoverStep1,
          hint: (s) => s.practiceSetCoverStep1Hint,
          successNote: (s) => s.practiceSetCoverStep1Done,
          kinds: const {ClassicHareegActionKind.placeCover},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceCoverFinishStep,
          kinds: const {ClassicHareegActionKind.discard},
        ),
      ],
    );
  }

  /// Cover discard block: a card that extends a table meld cannot normally
  /// be thrown away.
  static PracticeLessonScript coverDiscardBlock() {
    return PracticeLessonScript(
      lessonId: 'cover-discard-block',
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          PracticeBoard.card(CardRank.eight, CardSuit.diamonds),
          PracticeBoard.card(CardRank.two, CardSuit.clubs),
        ],
        topDiscard: PracticeBoard.card(CardRank.two, CardSuit.hearts),
        tableMelds: {
          PlayerSeat.east: [
            PlacedMeld.fromCards([
              PracticeBoard.card(CardRank.five, CardSuit.diamonds, deckIndex: 1),
              PracticeBoard.card(CardRank.six, CardSuit.diamonds, deckIndex: 1),
              PracticeBoard.card(
                CardRank.seven,
                CardSuit.diamonds,
                deckIndex: 1,
              ),
            ]),
          ],
        },
        openingState: PracticeBoard.openedSeats(const {
          PlayerSeat.south,
          PlayerSeat.east,
        }),
        turnPhase: TurnPhase.action,
      ),
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceCoverBlockStep1,
          hint: (s) => s.practiceCoverBlockStep1Hint,
          kinds: const {ClassicHareegActionKind.discard},
        ),
      ],
    );
  }

  /// Joker identity: declare exactly what a placed joker represents.
  ///
  /// The advertised surface canonicalizes the set declaration to one suit;
  /// the step lists the other legal suit explicitly (mirroring the table
  /// UI's identity picker) so the player makes a real choice — both ids are
  /// validated by the engine on submit.
  static PracticeLessonScript jokerIdentity() {
    final sevenClubs = PracticeBoard.card(CardRank.seven, CardSuit.clubs);
    final sevenHearts = PracticeBoard.card(CardRank.seven, CardSuit.hearts);
    final joker = PracticeBoard.joker();
    return PracticeLessonScript(
      lessonId: 'joker-identity',
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          sevenClubs,
          sevenHearts,
          joker,
          PracticeBoard.card(CardRank.four, CardSuit.spades),
          PracticeBoard.card(CardRank.nine, CardSuit.hearts),
        ],
        topDiscard: PracticeBoard.card(CardRank.two, CardSuit.hearts),
        openingState: PracticeBoard.openedFor(PlayerSeat.south),
        turnPhase: TurnPhase.action,
      ),
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceJokerIdentityStep1,
          hint: (s) => s.practiceJokerIdentityStep1Hint,
          successNote: (s) => s.practiceJokerIdentityStep1Done,
          kinds: const {ClassicHareegActionKind.playMeldWithJoker},
          extraActionIds: (_) => [
            ClassicHareegActionIds.playMeldWithJokerIdentityActionId(
              cardIds: [sevenClubs.id, sevenHearts.id, joker.id],
              jokerId: joker.id,
              identity: const CardIdentity(
                rank: CardRank.seven,
                suit: CardSuit.spades,
              ),
            ),
          ],
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceCoverFinishStep,
          kinds: const {ClassicHareegActionKind.discard},
        ),
      ],
    );
  }

  /// Joker replacement: swap the real represented card for a table joker.
  static PracticeLessonScript jokerReplacement() {
    return PracticeLessonScript(
      lessonId: 'joker-replacement',
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          PracticeBoard.card(CardRank.seven, CardSuit.diamonds),
          PracticeBoard.card(CardRank.king, CardSuit.clubs),
          PracticeBoard.card(CardRank.two, CardSuit.spades),
        ],
        topDiscard: PracticeBoard.card(CardRank.two, CardSuit.hearts),
        tableMelds: {
          PlayerSeat.east: [
            PlacedMeld.fromCards([
              PracticeBoard.card(CardRank.seven, CardSuit.clubs, deckIndex: 1),
              PracticeBoard.card(CardRank.seven, CardSuit.hearts, deckIndex: 1),
              PracticeBoard.joker().asRepresenting(
                const CardIdentity(
                  rank: CardRank.seven,
                  suit: CardSuit.diamonds,
                ),
              ),
            ]),
          ],
        },
        openingState: PracticeBoard.openedSeats(const {
          PlayerSeat.south,
          PlayerSeat.east,
        }),
        turnPhase: TurnPhase.action,
      ),
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceJokerReplaceStep1,
          hint: (s) => s.practiceJokerReplaceStep1Hint,
          successNote: (s) => s.practiceJokerReplaceStep1Done,
          kinds: const {ClassicHareegActionKind.replaceJoker},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceJokerReplaceStep2,
          hint: (s) => s.practiceJokerReplaceStep2Hint,
          kinds: const {ClassicHareegActionKind.discard},
        ),
      ],
    );
  }

  /// The final discard: a finish always keeps one card to throw.
  static PracticeLessonScript finalDiscard() {
    return PracticeLessonScript(
      lessonId: 'final-discard',
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          PracticeBoard.card(CardRank.nine, CardSuit.clubs),
          PracticeBoard.card(CardRank.nine, CardSuit.diamonds),
          PracticeBoard.card(CardRank.nine, CardSuit.hearts),
          PracticeBoard.card(CardRank.five, CardSuit.spades),
        ],
        topDiscard: PracticeBoard.card(CardRank.two, CardSuit.hearts),
        openingState: PracticeBoard.openedFor(PlayerSeat.south),
        turnPhase: TurnPhase.action,
      ),
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceFinalDiscardStep1,
          hint: (s) => s.practiceFinalDiscardStep1Hint,
          successNote: (s) => s.practiceFinalDiscardStep1Done,
          kinds: const {ClassicHareegActionKind.playMeld},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceFinalDiscardStep2,
          kinds: const {ClassicHareegActionKind.discard},
        ),
      ],
      completionNote: (s, _) => s.practiceFinalDiscardCompletion,
    );
  }

  /// A clean normal finish, with the score outcome on the completion panel.
  static PracticeLessonScript normalFinish() {
    return PracticeLessonScript(
      lessonId: 'normal-finish',
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          PracticeBoard.card(CardRank.queen, CardSuit.clubs),
          PracticeBoard.card(CardRank.queen, CardSuit.diamonds),
          PracticeBoard.card(CardRank.queen, CardSuit.hearts),
          PracticeBoard.card(CardRank.three, CardSuit.clubs),
          PracticeBoard.card(CardRank.three, CardSuit.diamonds),
          PracticeBoard.card(CardRank.three, CardSuit.hearts),
          PracticeBoard.card(CardRank.seven, CardSuit.spades),
        ],
        topDiscard: PracticeBoard.card(CardRank.two, CardSuit.hearts),
        openingState: PracticeBoard.openedFor(PlayerSeat.south),
        turnPhase: TurnPhase.action,
      ),
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceNormalFinishStep1,
          kinds: const {ClassicHareegActionKind.playMeld},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceNormalFinishStep2,
          kinds: const {ClassicHareegActionKind.playMeld},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceNormalFinishStep3,
          kinds: const {ClassicHareegActionKind.discard},
        ),
      ],
      completionNote: (s, _) => s.practiceNormalFinishCompletion,
    );
  }

  /// Fifty timing: claim the previous discard before the window closes.
  ///
  /// [clock] feeds the window-open timestamp (tests inject a fake clock and
  /// pair it with the session's `now` to walk the window deterministically;
  /// the app uses real time).
  static PracticeLessonScript fiftyClaim({DateTime Function()? clock}) {
    final now = clock ?? DateTime.now;
    return PracticeLessonScript(
      lessonId: 'fifty-claim',
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          PracticeBoard.card(CardRank.eight, CardSuit.clubs),
          PracticeBoard.card(CardRank.eight, CardSuit.hearts),
          PracticeBoard.card(CardRank.queen, CardSuit.spades),
        ],
        topDiscard: PracticeBoard.card(CardRank.eight, CardSuit.diamonds),
        openingState: PracticeBoard.openedFor(PlayerSeat.south),
        setup: ClassicHareegSetup.defaults().copyWith(fiftyTimerSeconds: 8),
        roundNumber: 2,
        fiftyWindowOpenedAt: now(),
        fiftyWindowDiscarder: PlayerSeat.west,
      ),
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceFiftyClaimStep1,
          hint: (s) => s.practiceFiftyClaimStep1Hint,
          kinds: const {ClassicHareegActionKind.claimFifty},
        ),
      ],
      completionNote: (s, _) => s.practiceFiftyClaimCompletion,
    );
  }

  /// Fifty scoring: the same claim, watched through the score sheet.
  static PracticeLessonScript fiftyScoring({DateTime Function()? clock}) {
    final now = clock ?? DateTime.now;
    return PracticeLessonScript(
      lessonId: 'fifty-scoring',
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          PracticeBoard.card(CardRank.five, CardSuit.diamonds),
          PracticeBoard.card(CardRank.five, CardSuit.spades),
          PracticeBoard.card(CardRank.king, CardSuit.clubs),
        ],
        topDiscard: PracticeBoard.card(CardRank.five, CardSuit.hearts),
        openingState: PracticeBoard.openedFor(PlayerSeat.south),
        setup: ClassicHareegSetup.defaults().copyWith(fiftyTimerSeconds: 8),
        roundNumber: 2,
        fiftyWindowOpenedAt: now(),
        fiftyWindowDiscarder: PlayerSeat.west,
      ),
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceFiftyScoringStep1,
          kinds: const {ClassicHareegActionKind.claimFifty},
        ),
      ],
      completionNote: (s, controller) {
        final south = controller.scores[PlayerSeat.south] ?? 0;
        final west = controller.scores[PlayerSeat.west] ?? 0;
        return s.practiceFiftyScoringCompletion(south, west);
      },
    );
  }
}
