import '../../../../domain/classic_hareeg/game/classic_hareeg_action.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../domain/classic_hareeg/rules/opening_rules.dart';
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
///
/// The table mechanics pack assumes opening is understood and explores what
/// an open table allows: pending use-or-return, the moving benchmark,
/// covers (placing them, and the discard trap they create), and the two
/// joker moves. Whenever a lesson needs another seat's table state, a
/// scripted intro plays that seat's turn visibly; the player's own opened
/// status is the one piece of staged prior state — their earlier opening
/// sits on the table, totalling exactly the benchmark it implies.
abstract final class PracticeScripts {
  /// Script for [lessonId], or null while the lesson's pack has not shipped.
  static PracticeLessonScript? byId(String lessonId) {
    return switch (lessonId) {
      'turn-rhythm' => turnRhythm(),
      'first-meld' => firstMeld(),
      'discard-opening' => discardOpening(),
      'bait-discard' => baitDiscard(),
      'opening-51' => openingTo51(),
      'pending-discard' => pendingDiscard(),
      'benchmark-pressure' => benchmarkPressure(),
      'sequence-cover' => sequenceCover(),
      'set-cover' => setCover(),
      'cover-discard-block' => coverDiscardBlock(),
      'joker-identity' => jokerIdentity(),
      'joker-replacement' => jokerReplacement(),
      _ => null,
    };
  }

  /// Allows only a play-meld of exactly [cardIds] — for staging lessons
  /// whose copy and rings teach one specific meld per step, so an
  /// out-of-order set cannot silently complete a step its prompt is not
  /// describing.
  static bool Function(ClassicHareegActionDescriptor action) _playsExactly(
    Set<String> cardIds,
  ) {
    return (action) =>
        action.kind == ClassicHareegActionKind.playMeld &&
        action.cardIds.length == cardIds.length &&
        cardIds.containsAll(action.cardIds);
  }

  /// Allows only a represented-joker meld of exactly [cardIds], leaving the
  /// identity declaration open — a joker completes almost any selection, so
  /// a kind-only gate would light selections the prompt never described.
  static bool Function(ClassicHareegActionDescriptor action)
  _playsJokerMeldExactly(Set<String> cardIds) {
    return (action) =>
        action.kind == ClassicHareegActionKind.playMeldWithJoker &&
        action.cardIds.length == cardIds.length &&
        cardIds.containsAll(action.cardIds);
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
        // Each staging step offers exactly the meld its copy and rings
        // teach — playing the jacks first would otherwise complete the
        // kings step and leave every prompt after it describing the wrong
        // cards.
        PracticeStep(
          prompt: (s) => s.practiceOpeningStep1,
          hint: (s) => s.practiceOpeningStep1Hint,
          successNote: (s) => s.practiceOpeningStep1Done,
          allows: _playsExactly({for (final card in kings) card.id}),
          highlightCardIds: {for (final card in kings) card.id},
        ),
        PracticeStep(
          prompt: (s) => s.practiceOpeningStep2,
          successNote: (s) => s.practiceOpeningStep2Done,
          allows: _playsExactly({for (final card in jacks) card.id}),
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

  /// Pending discard, post-opening: a taken card is a choice, not a promise.
  ///
  /// The player is already opened — their earlier run and sevens sit on the
  /// table at exactly the 51 they imply. The lesson walks the return branch
  /// of use-or-return: take west's four, hand it back (a real rule then
  /// blocks re-taking it this turn), draw on, and prove the other half of
  /// post-opening freedom by melding a six-point set of twos that could
  /// never have opened. The use branch — melding the taken card — is the
  /// move discard-opening already taught.
  static PracticeLessonScript pendingDiscard() {
    // The player's prior opening: 10-J-Q of spades (30) + sevens (21) = 51.
    final priorRun = [
      PracticeBoard.card(CardRank.ten, CardSuit.spades),
      PracticeBoard.card(CardRank.jack, CardSuit.spades),
      PracticeBoard.card(CardRank.queen, CardSuit.spades),
    ];
    final priorSevens = [
      PracticeBoard.card(CardRank.seven, CardSuit.spades),
      PracticeBoard.card(CardRank.seven, CardSuit.diamonds),
      PracticeBoard.card(CardRank.seven, CardSuit.hearts),
    ];
    final twos = [
      PracticeBoard.card(CardRank.two, CardSuit.spades),
      PracticeBoard.card(CardRank.two, CardSuit.diamonds),
      PracticeBoard.card(CardRank.two, CardSuit.clubs),
    ];
    final fourHearts = PracticeBoard.card(CardRank.four, CardSuit.hearts);
    final fourDiamonds = PracticeBoard.card(CardRank.four, CardSuit.diamonds);
    final fourClubs = PracticeBoard.card(CardRank.four, CardSuit.clubs);
    return PracticeLessonScript(
      lessonId: 'pending-discard',
      buildSnapshot: () => PracticeBoard.build(
        // A pre-opened hand deals the real count: 14 dealt minus the six
        // cards already placed on the table.
        southHand: [
          // The pair west's four completes, and the ready low set that
          // shows any value melds once the player is open.
          fourHearts,
          fourDiamonds,
          ...twos,
          // Fillers: no meld, no second four, no heart two (the melded twos
          // accept it as a cover), and none of the table's cover cards (no
          // 9 or king of spades, no club seven) so every closing discard
          // stays safe.
          PracticeBoard.card(CardRank.eight, CardSuit.hearts),
          PracticeBoard.card(CardRank.queen, CardSuit.diamonds),
          PracticeBoard.card(CardRank.ace, CardSuit.clubs),
        ],
        tableMelds: {
          PlayerSeat.south: [
            PlacedMeld.fromCards(priorRun),
            PlacedMeld.fromCards(priorSevens),
          ],
        },
        openingState: PracticeBoard.openedFor(PlayerSeat.south),
        cpuSeedCards: {
          PlayerSeat.west: [fourClubs],
        },
        currentSeat: PlayerSeat.west,
      ),
      introActionIds: [
        ClassicHareegActionIds.drawStock,
        '${ClassicHareegActionIds.discardPrefix}${fourClubs.id}',
      ],
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practicePendingStep1,
          successNote: (s) => s.practicePendingStep1Done,
          kinds: const {ClassicHareegActionKind.takeDiscard},
          highlightCardIds: {fourHearts.id, fourDiamonds.id},
        ),
        // The escape hatch: a pending card can go back any time before it
        // touches the table — but a returned card cannot be re-taken this
        // turn (the engine blocks the stall), so the turn falls back to
        // the stock draw.
        PracticeStep.kinds(
          prompt: (s) => s.practicePendingStep2,
          hint: (s) => s.practicePendingStep2Hint,
          successNote: (s) => s.practicePendingStep2Done,
          kinds: const {ClassicHareegActionKind.returnPendingDiscard},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practicePendingStep3,
          kinds: const {ClassicHareegActionKind.drawStock},
        ),
        PracticeStep(
          prompt: (s) => s.practicePendingStep4,
          hint: (s) => s.practicePendingStep4Hint,
          successNote: (s) => s.practicePendingStep4Done,
          allows: _playsExactly({for (final card in twos) card.id}),
          highlightCardIds: {for (final card in twos) card.id},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceCoverFinishStep,
          hint: (s) => s.practiceTurnRhythmStep2Hint,
          kinds: const {ClassicHareegActionKind.discard},
        ),
      ],
    );
  }

  /// Benchmark pressure: a valid meld is not enough once someone opened big.
  ///
  /// West's scripted intro opens with three melds that cross the 51 line
  /// only on the last play, so the engine itself raises the live benchmark
  /// to their 75 total. The player's six-heart run is a legal 54 — over the
  /// base rule, under the raised bar — and the lesson has them stage it,
  /// reads the shortfall back, and teaches the retract as the deliberate
  /// way out (the one step whose taught move is a take-back).
  static PracticeLessonScript benchmarkPressure() {
    final westRun = [
      PracticeBoard.card(CardRank.four, CardSuit.spades),
      PracticeBoard.card(CardRank.five, CardSuit.spades),
      PracticeBoard.card(CardRank.six, CardSuit.spades),
    ];
    final westAces = [
      PracticeBoard.card(CardRank.ace, CardSuit.spades),
      PracticeBoard.card(CardRank.ace, CardSuit.diamonds),
      PracticeBoard.card(CardRank.ace, CardSuit.hearts),
    ];
    final westKings = [
      PracticeBoard.card(CardRank.king, CardSuit.spades),
      PracticeBoard.card(CardRank.king, CardSuit.diamonds),
      PracticeBoard.card(CardRank.king, CardSuit.hearts),
    ];
    final westThrow = PracticeBoard.card(CardRank.two, CardSuit.diamonds);
    // The player's run: 7-8-9-10-J-Q of hearts = 54.
    final heartRun = [
      PracticeBoard.card(CardRank.seven, CardSuit.hearts),
      PracticeBoard.card(CardRank.eight, CardSuit.hearts),
      PracticeBoard.card(CardRank.nine, CardSuit.hearts),
      PracticeBoard.card(CardRank.ten, CardSuit.hearts),
      PracticeBoard.card(CardRank.jack, CardSuit.hearts),
      PracticeBoard.card(CardRank.queen, CardSuit.hearts),
    ];
    return PracticeLessonScript(
      lessonId: 'benchmark-pressure',
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          ...heartRun,
          // Fillers: no second meld, no west cover cards (no club ace or
          // king, no 3 or 7 of spades), and no 6 of hearts that would grow
          // the taught run past its narrated six cards.
          PracticeBoard.card(CardRank.two, CardSuit.clubs),
          PracticeBoard.card(CardRank.three, CardSuit.diamonds),
          PracticeBoard.card(CardRank.four, CardSuit.clubs),
          PracticeBoard.card(CardRank.five, CardSuit.diamonds),
          PracticeBoard.card(CardRank.eight, CardSuit.spades),
          PracticeBoard.card(CardRank.nine, CardSuit.clubs),
          PracticeBoard.card(CardRank.ten, CardSuit.diamonds),
          PracticeBoard.card(CardRank.queen, CardSuit.spades),
        ],
        cpuSeedCards: {
          PlayerSeat.west: [...westRun, ...westAces, ...westKings, westThrow],
        },
        currentSeat: PlayerSeat.west,
      ),
      // Smallest meld first: the staged total must cross 51 only on the
      // final play, or the opening would seal early at a lower benchmark.
      introActionIds: [
        ClassicHareegActionIds.drawStock,
        ClassicHareegActionIds.playMeldActionId([
          for (final card in westRun) card.id,
        ]),
        ClassicHareegActionIds.playMeldActionId([
          for (final card in westAces) card.id,
        ]),
        ClassicHareegActionIds.playMeldActionId([
          for (final card in westKings) card.id,
        ]),
        '${ClassicHareegActionIds.discardPrefix}${westThrow.id}',
      ],
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceBenchmarkStep1,
          kinds: const {ClassicHareegActionKind.drawStock},
        ),
        PracticeStep(
          prompt: (s) => s.practiceBenchmarkStep2,
          hint: (s) => s.practiceBenchmarkStep2Hint,
          successNote: (s) => s.practiceBenchmarkStep2Done,
          allows: _playsExactly({for (final card in heartRun) card.id}),
          highlightCardIds: {for (final card in heartRun) card.id},
        ),
        // The retract as the taught move: the step filter names the
        // take-back kinds, so they advance here instead of holding as
        // corrections. Both gestures count — the undo pill returns every
        // staged meld, and tapping the staged run itself returns that one
        // play (a playtest stranded here when only the pill was listed).
        PracticeStep.kinds(
          prompt: (s) => s.practiceBenchmarkStep3,
          hint: (s) => s.practiceBenchmarkStep3Hint,
          successNote: (s) => s.practiceBenchmarkStep3Done,
          kinds: const {
            ClassicHareegActionKind.returnOpeningMelds,
            ClassicHareegActionKind.returnTablePlay,
          },
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceBenchmarkStep4,
          hint: (s) => s.practiceTurnRhythmStep2Hint,
          kinds: const {ClassicHareegActionKind.discard},
        ),
      ],
    );
  }

  /// Stacked covers: one turn can grow several melds.
  ///
  /// The follow-up to the single-card cover lesson. West's intro opens an
  /// eights set plus the 8-9-10 of diamonds (exactly 51); the player —
  /// opened earlier with two heart runs totalling their own exact 51 —
  /// stacks the jack AND queen onto the run's high end, then fills the
  /// eights set with the second deck's 8 of diamonds: three covers, two
  /// melds, one turn.
  static PracticeLessonScript sequenceCover() {
    final priorLowRun = [
      PracticeBoard.card(CardRank.six, CardSuit.hearts),
      PracticeBoard.card(CardRank.seven, CardSuit.hearts),
      PracticeBoard.card(CardRank.eight, CardSuit.hearts),
    ];
    final priorHighRun = [
      PracticeBoard.card(CardRank.jack, CardSuit.hearts),
      PracticeBoard.card(CardRank.queen, CardSuit.hearts),
      PracticeBoard.card(CardRank.king, CardSuit.hearts),
    ];
    final westEights = [
      PracticeBoard.card(CardRank.eight, CardSuit.spades),
      PracticeBoard.card(CardRank.eight, CardSuit.clubs),
      PracticeBoard.card(CardRank.eight, CardSuit.hearts, deckIndex: 1),
    ];
    final westRun = [
      PracticeBoard.card(CardRank.eight, CardSuit.diamonds),
      PracticeBoard.card(CardRank.nine, CardSuit.diamonds),
      PracticeBoard.card(CardRank.ten, CardSuit.diamonds),
    ];
    final westThrow = PracticeBoard.card(CardRank.four, CardSuit.hearts);
    final jackDiamonds = PracticeBoard.card(CardRank.jack, CardSuit.diamonds);
    final queenDiamonds = PracticeBoard.card(
      CardRank.queen,
      CardSuit.diamonds,
    );
    final eightDiamonds = PracticeBoard.card(
      CardRank.eight,
      CardSuit.diamonds,
      deckIndex: 1,
    );
    return PracticeLessonScript(
      lessonId: 'sequence-cover',
      buildSnapshot: () => PracticeBoard.build(
        // A pre-opened hand deals the real count: 14 dealt minus the six
        // cards already placed on the table.
        southHand: [
          jackDiamonds,
          queenDiamonds,
          eightDiamonds,
          // Fillers: no meld, and none of the table's remaining cover
          // cards — the hearts runs' ends (5, 9, 10, ace of hearts), the
          // run's other neighbors (7 of diamonds, and the king that
          // becomes legal once the queen lands).
          PracticeBoard.card(CardRank.two, CardSuit.hearts),
          PracticeBoard.card(CardRank.three, CardSuit.clubs),
          PracticeBoard.card(CardRank.seven, CardSuit.clubs),
          PracticeBoard.card(CardRank.nine, CardSuit.spades),
          PracticeBoard.card(CardRank.ace, CardSuit.clubs),
        ],
        tableMelds: {
          PlayerSeat.south: [
            PlacedMeld.fromCards(priorLowRun),
            PlacedMeld.fromCards(priorHighRun),
          ],
        },
        openingState: PracticeBoard.openedFor(PlayerSeat.south),
        cpuSeedCards: {
          PlayerSeat.west: [...westEights, ...westRun, westThrow],
        },
        currentSeat: PlayerSeat.west,
      ),
      introActionIds: [
        ClassicHareegActionIds.drawStock,
        ClassicHareegActionIds.playMeldActionId([
          for (final card in westEights) card.id,
        ]),
        ClassicHareegActionIds.playMeldActionId([
          for (final card in westRun) card.id,
        ]),
        '${ClassicHareegActionIds.discardPrefix}${westThrow.id}',
      ],
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceTurnRhythmStep1,
          kinds: const {ClassicHareegActionKind.drawStock},
        ),
        // The run grows by two — one card at a time or both in one drop;
        // the step holds until the jack and queen are both on the table.
        PracticeStep(
          prompt: (s) => s.practiceSeqCoverStep1,
          hint: (s) => s.practiceSeqCoverStep1Hint,
          successNote: (s) => s.practiceSeqCoverStep1Done,
          holdNote: (s) => s.practiceSeqCoverStep1Hold,
          allows: (action) =>
              action.kind == ClassicHareegActionKind.placeCover &&
              action.cardIds.every(
                (id) => id == jackDiamonds.id || id == queenDiamonds.id,
              ),
          isSatisfied: (context) {
            final run = context.controller.tableMeldsFor(PlayerSeat.west)[1];
            final ids = {for (final card in run.cards) card.id};
            return ids.contains(jackDiamonds.id) &&
                ids.contains(queenDiamonds.id);
          },
          highlightCardIds: {
            jackDiamonds.id,
            queenDiamonds.id,
            for (final card in westRun) card.id,
          },
        ),
        PracticeStep(
          prompt: (s) => s.practiceSeqCoverStep2,
          hint: (s) => s.practiceSeqCoverStep2Hint,
          successNote: (s) => s.practiceSeqCoverStep2Done,
          allows: (action) =>
              action.kind == ClassicHareegActionKind.placeCover &&
              action.cardIds.length == 1 &&
              action.cardIds.single == eightDiamonds.id,
          highlightCardIds: {
            eightDiamonds.id,
            for (final card in westEights) card.id,
          },
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceCoverFinishStep,
          hint: (s) => s.practiceTurnRhythmStep2Hint,
          kinds: const {ClassicHareegActionKind.discard},
        ),
      ],
    );
  }

  /// Set cover: fill the missing suit of another player's set.
  ///
  /// West's intro opens a club run plus three kings (exactly 51); the
  /// player — opened earlier with a tens set and a diamond run at their own
  /// exact 51 — completes the kings with the club king.
  static PracticeLessonScript setCover() {
    final priorTens = [
      PracticeBoard.card(CardRank.ten, CardSuit.spades),
      PracticeBoard.card(CardRank.ten, CardSuit.diamonds),
      PracticeBoard.card(CardRank.ten, CardSuit.hearts),
    ];
    final priorRun = [
      PracticeBoard.card(CardRank.six, CardSuit.diamonds),
      PracticeBoard.card(CardRank.seven, CardSuit.diamonds),
      PracticeBoard.card(CardRank.eight, CardSuit.diamonds),
    ];
    final westRun = [
      PracticeBoard.card(CardRank.six, CardSuit.clubs),
      PracticeBoard.card(CardRank.seven, CardSuit.clubs),
      PracticeBoard.card(CardRank.eight, CardSuit.clubs),
    ];
    final westKings = [
      PracticeBoard.card(CardRank.king, CardSuit.spades),
      PracticeBoard.card(CardRank.king, CardSuit.diamonds),
      PracticeBoard.card(CardRank.king, CardSuit.hearts),
    ];
    final westThrow = PracticeBoard.card(CardRank.two, CardSuit.hearts);
    final kingClubs = PracticeBoard.card(CardRank.king, CardSuit.clubs);
    return PracticeLessonScript(
      lessonId: 'set-cover',
      buildSnapshot: () => PracticeBoard.build(
        // A pre-opened hand deals the real count: 14 dealt minus the six
        // cards already placed on the table.
        southHand: [
          kingClubs,
          // Fillers: no meld, and none of the table's cover cards (no club
          // 5 or 9 for west's run, no diamond 5 or 9 for the player's own
          // run, no fourth ten) — the kings' only missing suit is the
          // taught club king, and the cover fills the set completely.
          PracticeBoard.card(CardRank.two, CardSuit.spades),
          PracticeBoard.card(CardRank.three, CardSuit.diamonds),
          PracticeBoard.card(CardRank.four, CardSuit.hearts),
          PracticeBoard.card(CardRank.seven, CardSuit.spades),
          PracticeBoard.card(CardRank.nine, CardSuit.spades),
          PracticeBoard.card(CardRank.jack, CardSuit.clubs),
          PracticeBoard.card(CardRank.ace, CardSuit.hearts),
        ],
        tableMelds: {
          PlayerSeat.south: [
            PlacedMeld.fromCards(priorTens),
            PlacedMeld.fromCards(priorRun),
          ],
        },
        openingState: PracticeBoard.openedFor(PlayerSeat.south),
        cpuSeedCards: {
          PlayerSeat.west: [...westRun, ...westKings, westThrow],
        },
        currentSeat: PlayerSeat.west,
      ),
      introActionIds: [
        ClassicHareegActionIds.drawStock,
        ClassicHareegActionIds.playMeldActionId([
          for (final card in westRun) card.id,
        ]),
        ClassicHareegActionIds.playMeldActionId([
          for (final card in westKings) card.id,
        ]),
        '${ClassicHareegActionIds.discardPrefix}${westThrow.id}',
      ],
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceTurnRhythmStep1,
          kinds: const {ClassicHareegActionKind.drawStock},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceSetCoverStep1,
          hint: (s) => s.practiceSetCoverStep1Hint,
          successNote: (s) => s.practiceSetCoverStep1Done,
          kinds: const {ClassicHareegActionKind.placeCover},
          highlightCardIds: {
            kingClubs.id,
            for (final card in westKings) card.id,
          },
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceCoverFinishStep,
          hint: (s) => s.practiceTurnRhythmStep2Hint,
          kinds: const {ClassicHareegActionKind.discard},
        ),
      ],
    );
  }

  /// Cover discard block: a card the table can use cannot be thrown away.
  ///
  /// West's intro opens a heart run plus a tens set (exactly 51). The
  /// player is NOT opened: their ten of hearts would complete west's set,
  /// so it can be neither placed (covers need an opened player) nor
  /// discarded — the full weight of being stuck behind the benchmark.
  static PracticeLessonScript coverDiscardBlock() {
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
    return PracticeLessonScript(
      lessonId: 'cover-discard-block',
      buildSnapshot: () => PracticeBoard.build(
        southHand: [
          tenHearts,
          // Fillers: no meld (the player must stay unopened all lesson) and
          // no other cover of west's melds (no 5 or 9 of hearts), so the
          // trapped ten is the only card the pile refuses.
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
      ),
      introActionIds: [
        ClassicHareegActionIds.drawStock,
        ClassicHareegActionIds.playMeldActionId([
          for (final card in westRun) card.id,
        ]),
        ClassicHareegActionIds.playMeldActionId([
          for (final card in westTens) card.id,
        ]),
        '${ClassicHareegActionIds.discardPrefix}${westThrow.id}',
      ],
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceTurnRhythmStep1,
          kinds: const {ClassicHareegActionKind.drawStock},
        ),
        // One discard step carries the lesson: the trapped ten rings beside
        // the set it would complete, the player tries it, the pile refuses,
        // and any other card ends the turn. Real rules feedback, not a
        // scripted simulation.
        PracticeStep.kinds(
          prompt: (s) => s.practiceCoverBlockStep1,
          hint: (s) => s.practiceCoverBlockStep1Hint,
          kinds: const {ClassicHareegActionKind.discard},
          highlightCardIds: {
            tenHearts.id,
            for (final card in westTens) card.id,
          },
        ),
      ],
    );
  }

  /// Joker identity: a melded joker is exactly what its owner declares.
  ///
  /// The player opened earlier with two sets totalling their exact 51, and
  /// now melds two sevens plus a joker — the identity picker offers both
  /// missing sevens, and either declaration completes the step. The choice
  /// itself is the lesson, so the step leaves it open.
  static PracticeLessonScript jokerIdentity() {
    final priorEights = [
      PracticeBoard.card(CardRank.eight, CardSuit.spades),
      PracticeBoard.card(CardRank.eight, CardSuit.diamonds),
      PracticeBoard.card(CardRank.eight, CardSuit.hearts),
    ];
    final priorNines = [
      PracticeBoard.card(CardRank.nine, CardSuit.spades),
      PracticeBoard.card(CardRank.nine, CardSuit.diamonds),
      PracticeBoard.card(CardRank.nine, CardSuit.clubs),
    ];
    final sevenClubs = PracticeBoard.card(CardRank.seven, CardSuit.clubs);
    final sevenHearts = PracticeBoard.card(CardRank.seven, CardSuit.hearts);
    final joker = PracticeBoard.joker();
    return PracticeLessonScript(
      lessonId: 'joker-identity',
      buildSnapshot: () => PracticeBoard.build(
        // A pre-opened hand deals the real count: 14 dealt minus the six
        // cards already placed on the table.
        southHand: [
          sevenClubs,
          sevenHearts,
          joker,
          // Fillers: no meld, no extra seven, and none of the table's cover
          // cards (no club eight, no heart nine) — the sevens-plus-joker is
          // the only meld the hand can produce.
          PracticeBoard.card(CardRank.two, CardSuit.spades),
          PracticeBoard.card(CardRank.two, CardSuit.hearts),
          PracticeBoard.card(CardRank.six, CardSuit.diamonds),
          PracticeBoard.card(CardRank.jack, CardSuit.hearts),
          PracticeBoard.card(CardRank.ace, CardSuit.spades),
        ],
        topDiscard: PracticeBoard.card(CardRank.three, CardSuit.clubs),
        tableMelds: {
          PlayerSeat.south: [
            PlacedMeld.fromCards(priorEights),
            PlacedMeld.fromCards(priorNines),
          ],
        },
        openingState: PracticeBoard.openedFor(PlayerSeat.south),
      ),
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceTurnRhythmStep1,
          kinds: const {ClassicHareegActionKind.drawStock},
        ),
        PracticeStep(
          prompt: (s) => s.practiceJokerIdentityStep1,
          hint: (s) => s.practiceJokerIdentityStep1Hint,
          successNote: (s) => s.practiceJokerIdentityStep1Done,
          allows: _playsJokerMeldExactly({
            sevenClubs.id,
            sevenHearts.id,
            joker.id,
          }),
          highlightCardIds: {sevenClubs.id, sevenHearts.id, joker.id},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceCoverFinishStep,
          hint: (s) => s.practiceTurnRhythmStep2Hint,
          kinds: const {ClassicHareegActionKind.discard},
        ),
      ],
    );
  }

  /// Joker replacement: reclaim a table joker with the card it represents.
  ///
  /// West's intro opens a sevens set whose joker visibly stands in for the
  /// diamond seven, then aces to seal an exact 51. The player — opened
  /// earlier with queens and a spade run — holds the real diamond seven and
  /// swaps it in. The close is a real choice: the freed joker can bridge
  /// the held 8 and 10 of hearts as a nine (the previous lesson taught
  /// declarations) or stay banked — either way the turn ends with a plain
  /// discard, because a joker itself never leaves as one.
  static PracticeLessonScript jokerReplacement() {
    final priorQueens = [
      PracticeBoard.card(CardRank.queen, CardSuit.spades),
      PracticeBoard.card(CardRank.queen, CardSuit.diamonds),
      PracticeBoard.card(CardRank.queen, CardSuit.hearts),
    ];
    final priorRun = [
      PracticeBoard.card(CardRank.six, CardSuit.spades),
      PracticeBoard.card(CardRank.seven, CardSuit.spades),
      PracticeBoard.card(CardRank.eight, CardSuit.spades),
    ];
    final sevenClubs = PracticeBoard.card(CardRank.seven, CardSuit.clubs);
    final sevenHearts = PracticeBoard.card(CardRank.seven, CardSuit.hearts);
    final joker = PracticeBoard.joker();
    final westAces = [
      PracticeBoard.card(CardRank.ace, CardSuit.spades),
      PracticeBoard.card(CardRank.ace, CardSuit.diamonds),
      PracticeBoard.card(CardRank.ace, CardSuit.hearts),
    ];
    final westThrow = PracticeBoard.card(CardRank.three, CardSuit.spades);
    final sevenDiamonds = PracticeBoard.card(
      CardRank.seven,
      CardSuit.diamonds,
    );
    final eightHearts = PracticeBoard.card(CardRank.eight, CardSuit.hearts);
    final tenHearts = PracticeBoard.card(CardRank.ten, CardSuit.hearts);
    return PracticeLessonScript(
      lessonId: 'joker-replacement',
      buildSnapshot: () => PracticeBoard.build(
        // A pre-opened hand deals the real count: 14 dealt minus the six
        // cards already placed on the table.
        southHand: [
          sevenDiamonds,
          // The 8-10 heart gap the reclaimed joker can bridge as a nine.
          eightHearts,
          tenHearts,
          // Fillers: no meld, and none of the table's cover cards (no club
          // queen, no spade 5 or 9, no club ace, no second-deck spade or
          // diamond seven) so the closing discard stays free.
          PracticeBoard.card(CardRank.two, CardSuit.hearts),
          PracticeBoard.card(CardRank.three, CardSuit.diamonds),
          PracticeBoard.card(CardRank.four, CardSuit.spades),
          PracticeBoard.card(CardRank.six, CardSuit.clubs),
          PracticeBoard.card(CardRank.king, CardSuit.hearts),
        ],
        tableMelds: {
          PlayerSeat.south: [
            PlacedMeld.fromCards(priorQueens),
            PlacedMeld.fromCards(priorRun),
          ],
        },
        openingState: PracticeBoard.openedFor(PlayerSeat.south),
        cpuSeedCards: {
          PlayerSeat.west: [sevenClubs, sevenHearts, joker, ...westAces, westThrow],
        },
        currentSeat: PlayerSeat.west,
      ),
      // West melds the joker first — the player watches the declaration
      // happen — then seals with the aces and throws a safe card.
      introActionIds: [
        ClassicHareegActionIds.drawStock,
        ClassicHareegActionIds.playMeldWithJokerIdentityActionId(
          cardIds: [sevenClubs.id, sevenHearts.id, joker.id],
          jokerId: joker.id,
          identity: const CardIdentity(
            rank: CardRank.seven,
            suit: CardSuit.diamonds,
          ),
        ),
        ClassicHareegActionIds.playMeldActionId([
          for (final card in westAces) card.id,
        ]),
        '${ClassicHareegActionIds.discardPrefix}${westThrow.id}',
      ],
      steps: [
        PracticeStep.kinds(
          prompt: (s) => s.practiceTurnRhythmStep1,
          kinds: const {ClassicHareegActionKind.drawStock},
        ),
        PracticeStep.kinds(
          prompt: (s) => s.practiceJokerReplaceStep1,
          hint: (s) => s.practiceJokerReplaceStep1Hint,
          successNote: (s) => s.practiceJokerReplaceStep1Done,
          kinds: const {ClassicHareegActionKind.replaceJoker},
          highlightCardIds: {sevenDiamonds.id, joker.id},
        ),
        // The close is a real decision: bridge the 8-10 of hearts with the
        // joker as a nine, or bank it — the step accepts the meld but only
        // the discard ends the turn, and the banner reacts when the bridge
        // lands so the player still knows how to finish. The joker's nine
        // is its only legal identity here, so the surface advertises the
        // play as a plain meld id — the gate accepts the trio either way.
        PracticeStep(
          prompt: (s) => s.practiceJokerReplaceStep2,
          hint: (s) => s.practiceJokerReplaceStep2Hint,
          holdNote: (s) => s.practiceJokerReplaceStep2Hold,
          allows: (action) =>
              action.kind == ClassicHareegActionKind.discard ||
              _playsExactly({
                eightHearts.id,
                tenHearts.id,
                joker.id,
              })(action) ||
              _playsJokerMeldExactly({
                eightHearts.id,
                tenHearts.id,
                joker.id,
              })(action),
          isSatisfied: (context) => context.action.isDiscard,
          highlightCardIds: {eightHearts.id, tenHearts.id, joker.id},
        ),
      ],
    );
  }
}
