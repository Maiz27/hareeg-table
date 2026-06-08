import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/learning/models/practice_lesson_registry.dart';
import 'package:hareeg_table/ui/features/learning/practice/finish_fifty_practice_pack.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_session.dart';

import '../../../support/practice_lesson_harness.dart';

void main() {
  group('final-discard lesson', () {
    final nines = [
      practiceCard(CardRank.nine, CardSuit.clubs),
      practiceCard(CardRank.nine, CardSuit.diamonds),
      practiceCard(CardRank.nine, CardSuit.hearts),
    ];
    final fiveSpades = practiceCard(CardRank.five, CardSuit.spades);

    test('the mid-turn board accounts for every card: 11 opened at exactly '
        '51 plus 4 in hand = the dealt 14 plus the draw', () {
      final session = PracticeSession(script: FinishFiftyPracticePack.finalDiscard());
      final controller = session.controller;

      expect(controller.openingState.hasOpened(PlayerSeat.south), isTrue);
      expectPracticeBoardSnapshotAudit(
        controller.toSnapshot(),
        handAndTableSeats: {PlayerSeat.south},
        extraCardsInHand: {PlayerSeat.south: 1},
        expectedTableValues: {PlayerSeat.south: 51},
        fullHandSeats: {PlayerSeat.east, PlayerSeat.north, PlayerSeat.west},
        minimumDiscardPileSize: 5,
        reason: 'final-discard board must read like a live late-round turn',
      );
    });

    test(
      'meld the nines, then the last card leaves as the winning discard',
      () {
        final session = PracticeSession(script: FinishFiftyPracticePack.finalDiscard());

        final meld = session.submit(practiceMeldId(nines));
        expect(meld.status, PracticeSubmitStatus.stepCompleted);
        expect(session.controller.handFor(PlayerSeat.south), hasLength(1));

        final out = session.submit(practiceDiscardId(fiveSpades));
        expect(out.status, PracticeSubmitStatus.lessonCompleted);
        expect(session.controller.isRoundOver, isTrue);
        expect(session.controller.roundOutcome, RoundOutcomeType.normalFinish);
        expect(session.controller.roundResult?.winner, PlayerSeat.south);
      },
    );

    test('retracting the nines walks the lesson back to the meld step', () {
      final session = PracticeSession(script: FinishFiftyPracticePack.finalDiscard());
      session.submit(practiceMeldId(nines));
      expect(session.stepIndex, 1);

      // The nines landed as the fourth meld on south's table.
      final retract = session.submit(
        ClassicHareegActionIds.returnTablePlayActionId(
          owner: PlayerSeat.south,
          meldIndex: 3,
        ),
      );
      expect(retract.status, PracticeSubmitStatus.corrected);
      expect(
        session.stepIndex,
        0,
        reason: 'the prompt must follow the cards back into the hand',
      );
      expect(session.controller.handFor(PlayerSeat.south), hasLength(4));

      // Discarding now cannot fake-complete the lesson: the meld step is
      // active again and does not offer discards.
      final stray = session.submit(practiceDiscardId(fiveSpades));
      expect(stray.status, PracticeSubmitStatus.notAllowed);

      // Replay the nines and finish for real.
      session.submit(practiceMeldId(nines));
      final out = session.submit(practiceDiscardId(fiveSpades));
      expect(out.status, PracticeSubmitStatus.lessonCompleted);
      expect(session.controller.isRoundOver, isTrue);
    });

    test('wrong path: throwing a card before the nines stays dark', () {
      final session = PracticeSession(script: FinishFiftyPracticePack.finalDiscard());

      final early = session.submit(practiceDiscardId(fiveSpades));
      expect(early.status, PracticeSubmitStatus.notAllowed);
      expect(session.stepIndex, 0);
      expect(
        session.offersActionId(practiceDiscardId(fiveSpades)),
        isFalse,
        reason: 'the affordance gate must darken the early throw',
      );
    });
  });

  group('normal-finish lesson', () {
    final queens = [
      practiceCard(CardRank.queen, CardSuit.clubs),
      practiceCard(CardRank.queen, CardSuit.diamonds),
      practiceCard(CardRank.queen, CardSuit.hearts),
    ];
    final heartRun = [
      practiceCard(CardRank.four, CardSuit.hearts),
      practiceCard(CardRank.five, CardSuit.hearts),
      practiceCard(CardRank.six, CardSuit.hearts),
      practiceCard(CardRank.seven, CardSuit.hearts),
      practiceCard(CardRank.eight, CardSuit.hearts),
    ];
    final sevenSpades = practiceCard(CardRank.seven, CardSuit.spades);

    test(
      'queens, heart run, out — and the engine scores the room for real',
      () {
        final session = PracticeSession(script: FinishFiftyPracticePack.normalFinish());

        expect(practiceTableValueFor(session, PlayerSeat.south), 51);
        expect(
          practiceTableCardCountFor(session, PlayerSeat.south) +
              session.controller.handFor(PlayerSeat.south).length,
          15,
          reason: 'hand + own table = 14 dealt + this turn\'s draw',
        );

        final first = session.submit(practiceMeldId(queens));
        expect(first.status, PracticeSubmitStatus.stepCompleted);
        final second = session.submit(practiceMeldId(heartRun));
        expect(second.status, PracticeSubmitStatus.stepCompleted);
        final out = session.submit(practiceDiscardId(sevenSpades));
        expect(out.status, PracticeSubmitStatus.lessonCompleted);

        expect(session.controller.isRoundOver, isTrue);
        expect(session.controller.roundOutcome, RoundOutcomeType.normalFinish);
        // The winner takes -1; every other seat adds its leftover card count
        // (full unopened 14-card hands).
        expect(session.controller.scores[PlayerSeat.south], -1);
        expect(session.controller.scores[PlayerSeat.east], 14);
        expect(session.controller.scores[PlayerSeat.north], 14);
        expect(session.controller.scores[PlayerSeat.west], 14);
      },
    );

    test('a deep retract regresses to the queens, and the still-placed run '
        'is not re-taught on the way forward', () {
      final session = PracticeSession(script: FinishFiftyPracticePack.normalFinish());
      session.submit(practiceMeldId(queens));
      session.submit(practiceMeldId(heartRun));
      expect(session.stepIndex, 2);

      // Take back the queens (third meld on the table) while the lesson is
      // already asking for the closing discard.
      final retract = session.submit(
        ClassicHareegActionIds.returnTablePlayActionId(
          owner: PlayerSeat.south,
          meldIndex: 2,
        ),
      );
      expect(retract.status, PracticeSubmitStatus.corrected);
      expect(
        session.stepIndex,
        0,
        reason: 'the queens step is the first undone outcome',
      );

      // Replaying the queens skips straight over the run step — its melds
      // never left the table — and lands on the discard.
      final replay = session.submit(practiceMeldId(queens));
      expect(replay.status, PracticeSubmitStatus.stepCompleted);
      expect(
        session.stepIndex,
        2,
        reason: 'a still-demonstrated step must not be re-taught',
      );

      final out = session.submit(practiceDiscardId(sevenSpades));
      expect(out.status, PracticeSubmitStatus.lessonCompleted);
    });

    test('wrong path: the heart run stays dark while the prompt teaches the '
        'queens', () {
      final session = PracticeSession(script: FinishFiftyPracticePack.normalFinish());

      final early = session.submit(practiceMeldId(heartRun));
      expect(early.status, PracticeSubmitStatus.notAllowed);
      expect(session.stepIndex, 0);
    });
  });

  group('perfect-hand-finish lesson', () {
    final twos = [
      practiceCard(CardRank.two, CardSuit.clubs),
      practiceCard(CardRank.two, CardSuit.diamonds),
      practiceCard(CardRank.two, CardSuit.hearts),
      practiceCard(CardRank.two, CardSuit.spades),
    ];
    final threes = [
      practiceCard(CardRank.three, CardSuit.clubs),
      practiceCard(CardRank.three, CardSuit.diamonds),
      practiceCard(CardRank.three, CardSuit.hearts),
      practiceCard(CardRank.three, CardSuit.spades),
    ];
    final fours = [
      practiceCard(CardRank.four, CardSuit.clubs),
      practiceCard(CardRank.four, CardSuit.diamonds),
      practiceCard(CardRank.four, CardSuit.hearts),
    ];
    final fives = [
      practiceCard(CardRank.five, CardSuit.clubs),
      practiceCard(CardRank.five, CardSuit.diamonds),
      practiceCard(CardRank.five, CardSuit.hearts),
    ];
    final kingSpades = practiceCard(CardRank.king, CardSuit.spades);

    test('the board reads as an unopened sub-51 hand, one over-dealt', () {
      final session = PracticeSession(
        script: FinishFiftyPracticePack.perfectHandFinish(),
      );

      expect(
        session.controller.openingState.hasOpened(PlayerSeat.south),
        isFalse,
        reason: 'a perfect hand finishes without ever opening',
      );
      expectPracticeBoardSnapshotAudit(
        session.controller.toSnapshot(),
        handAndTableSeats: {PlayerSeat.south},
        extraCardsInHand: {PlayerSeat.south: 1},
        fullHandSeats: {PlayerSeat.east, PlayerSeat.north, PlayerSeat.west},
        minimumDiscardPileSize: 5,
        reason: 'perfect-hand board must read like an over-dealt mid turn',
      );
    });

    test('stage each set in turn, never reach 51, then throw the king to win',
        () {
      final session = PracticeSession(
        script: FinishFiftyPracticePack.perfectHandFinish(),
      );

      // Each set stages as its own single meld — the real gesture path — and
      // the opening never seals (south stays unopened the whole way).
      final twosMeld = session.submit(practiceMeldId(twos));
      expect(twosMeld.status, PracticeSubmitStatus.stepCompleted);
      final threesMeld = session.submit(practiceMeldId(threes));
      expect(threesMeld.status, PracticeSubmitStatus.stepCompleted);
      final foursMeld = session.submit(practiceMeldId(fours));
      expect(foursMeld.status, PracticeSubmitStatus.stepCompleted);
      final fivesMeld = session.submit(practiceMeldId(fives));
      expect(fivesMeld.status, PracticeSubmitStatus.stepCompleted);
      expect(
        session.controller.openingState.hasOpened(PlayerSeat.south),
        isFalse,
        reason: 'staging 47 never crosses the 51 opening',
      );
      expect(session.controller.handFor(PlayerSeat.south), hasLength(1));

      final out = session.submit(practiceDiscardId(kingSpades));
      expect(out.status, PracticeSubmitStatus.lessonCompleted);
      expect(session.controller.isRoundOver, isTrue);
      expect(session.controller.roundOutcome, RoundOutcomeType.normalFinish);
      expect(session.controller.roundResult?.winner, PlayerSeat.south);
    });
  });

  group('joker-final-discard lesson', () {
    final eights = [
      practiceCard(CardRank.eight, CardSuit.clubs),
      practiceCard(CardRank.eight, CardSuit.diamonds),
      practiceCard(CardRank.eight, CardSuit.hearts),
    ];
    final joker = practiceJoker();

    test('meld the eights, then the joker leaves as the closing throw', () {
      final session = PracticeSession(
        script: FinishFiftyPracticePack.jokerFinalDiscard(),
      );

      expect(
        session.controller.openingState.hasOpened(PlayerSeat.south),
        isTrue,
      );

      final meld = session.submit(practiceMeldId(eights));
      expect(meld.status, PracticeSubmitStatus.stepCompleted);

      final out = session.submit(practiceDiscardId(joker));
      expect(out.status, PracticeSubmitStatus.lessonCompleted);
      expect(session.controller.isRoundOver, isTrue);
      expect(session.controller.roundOutcome, RoundOutcomeType.normalFinish);
      expect(session.controller.roundResult?.winner, PlayerSeat.south);
    });
  });

  group('fifty-claim lesson', () {
    final eightDiamonds = practiceCard(CardRank.eight, CardSuit.diamonds);
    final eightPair = [
      practiceCard(CardRank.eight, CardSuit.clubs),
      practiceCard(CardRank.eight, CardSuit.hearts),
    ];
    final twos = [
      practiceCard(CardRank.two, CardSuit.spades),
      practiceCard(CardRank.two, CardSuit.diamonds),
      practiceCard(CardRank.two, CardSuit.hearts),
    ];
    final queenSpades = practiceCard(CardRank.queen, CardSuit.spades);

    test('the turn-start board accounts for every card and west\'s scripted '
        'throw opens the real 8-second window', () {
      final clock = PracticeTestClock();
      final session = PracticeSession(
        script: FinishFiftyPracticePack.fiftyClaim(),
        now: clock.now,
      );

      expect(practiceTableValueFor(session, PlayerSeat.south), 51);
      expect(
        practiceTableCardCountFor(session, PlayerSeat.south) +
            session.controller.handFor(PlayerSeat.south).length,
        14,
        reason: 'turn start: hand + own table = the dealt 14',
      );
      expect(session.controller.fiftySecondsRemaining, isNull);
      expect(
        session.isDeadEnd,
        isFalse,
        reason: 'the predicate must not fire while west owns the turn',
      );

      runPracticeIntro(session);

      expect(session.controller.topDiscard?.id, eightDiamonds.id);
      expect(
        session.controller.fiftySecondsRemaining,
        8,
        reason: 'the throw itself stamps the practice-length window',
      );
      expect(session.controller.fiftyClaimant, PlayerSeat.south);
      expect(
        session.controller.handFor(PlayerSeat.west),
        hasLength(14),
        reason: 'west drew and threw: the unopened hand stays at 14',
      );
    });

    test('the practice ring counts down for real, then holds at 3 forever', () {
      final clock = PracticeTestClock();
      final session = PracticeSession(
        script: FinishFiftyPracticePack.fiftyClaim(),
        now: clock.now,
      );
      runPracticeIntro(session);

      clock.advance(const Duration(seconds: 2));
      expect(
        session.controller.fiftySecondsRemaining,
        6,
        reason: 'the ring must visibly count before the hold',
      );

      clock.advance(const Duration(minutes: 5));
      expect(
        session.controller.fiftySecondsRemaining,
        3,
        reason: 'practice holds the window instead of expiring it',
      );
      expect(session.isDeadEnd, isFalse);

      // The held window still claims — reading slowly costs nothing.
      final claim = session.submit(ClassicHareegActionIds.claimFifty);
      expect(claim.status, PracticeSubmitStatus.stepCompleted);
    });

    test('claim, then prove it: the eights, the twos, the queen out', () {
      final clock = PracticeTestClock();
      final session = PracticeSession(
        script: FinishFiftyPracticePack.fiftyClaim(),
        now: clock.now,
      );
      runPracticeIntro(session);
      clock.advance(const Duration(seconds: 3));

      // The claim only takes the card: an untimed proof turn begins with
      // the thrown eight as the pending discard.
      final claim = session.submit(ClassicHareegActionIds.claimFifty);
      expect(claim.status, PracticeSubmitStatus.stepCompleted);
      expect(session.controller.isFiftyProofTurn, isTrue);
      expect(session.controller.pendingDiscard?.id, eightDiamonds.id);
      expect(
        session.controller.fiftySecondsRemaining,
        isNull,
        reason: 'the timer only races the call — the proof is untimed',
      );
      expect(
        session.isDeadEnd,
        isFalse,
        reason: 'a window-less proof turn is not a missed window',
      );

      // Off-proof throws stay dark: the lesson pins the taught order.
      final early = session.submit(practiceDiscardId(queenSpades));
      expect(early.status, PracticeSubmitStatus.notAllowed);

      final eights = session.submit(
        practiceMeldId([...eightPair, eightDiamonds]),
      );
      expect(eights.status, PracticeSubmitStatus.stepCompleted);
      final twosMeld = session.submit(practiceMeldId(twos));
      expect(twosMeld.status, PracticeSubmitStatus.stepCompleted);

      final out = session.submit(practiceDiscardId(queenSpades));
      expect(out.status, PracticeSubmitStatus.lessonCompleted);
      expect(session.controller.isRoundOver, isTrue);
      expect(session.controller.roundOutcome, RoundOutcomeType.fiftyFinish);
      expect(session.controller.roundResult?.winner, PlayerSeat.south);
      expect(session.controller.handFor(PlayerSeat.south), isEmpty);
      expect(
        session.controller.tableMeldsFor(PlayerSeat.south),
        hasLength(4),
        reason: 'the eights and the twos both reached the table',
      );
    });

    test('retracting mid-proof restores the claimed card and walks the '
        'prompt back', () {
      final clock = PracticeTestClock();
      final session = PracticeSession(
        script: FinishFiftyPracticePack.fiftyClaim(),
        now: clock.now,
      );
      runPracticeIntro(session);
      session.submit(ClassicHareegActionIds.claimFifty);
      session.submit(practiceMeldId([...eightPair, eightDiamonds]));
      expect(session.stepIndex, 2, reason: 'on the twos step');

      // Take the eights back: the engine hands the claimed card back to
      // pending and the lesson regresses to the eights step.
      final retract = session.submit(
        ClassicHareegActionIds.returnTablePlayActionId(
          owner: PlayerSeat.south,
          meldIndex: 2,
        ),
      );
      expect(retract.status, PracticeSubmitStatus.corrected);
      expect(session.stepIndex, 1);
      expect(session.controller.pendingDiscard?.id, eightDiamonds.id);
      expect(session.controller.isFiftyProofTurn, isTrue);

      // Replay the proof to the end.
      session.submit(practiceMeldId([...eightPair, eightDiamonds]));
      session.submit(practiceMeldId(twos));
      final out = session.submit(practiceDiscardId(queenSpades));
      expect(out.status, PracticeSubmitStatus.lessonCompleted);
      expect(session.controller.roundOutcome, RoundOutcomeType.fiftyFinish);
    });

    test('without the practice hold the window expires into the dead end', () {
      final clock = PracticeTestClock();
      final session = PracticeSession(
        script: FinishFiftyPracticePack.fiftyClaim(pauseTimer: false),
        now: clock.now,
      );
      runPracticeIntro(session);

      clock.advance(const Duration(seconds: 5));
      expect(
        session.isDeadEnd,
        isFalse,
        reason: 'three seconds still on the ring',
      );

      // Past the window and its expiry-cue grace: the claim is gone for
      // good — the engine refuses it and the step can never complete.
      clock.advance(const Duration(seconds: 30));
      expect(session.isDeadEnd, isTrue);
      final late = session.submit(ClassicHareegActionIds.claimFifty);
      expect(late.status, PracticeSubmitStatus.rejected);

      // A fresh run restarts clean: window not yet open, no dead end.
      final replay = PracticeSession(
        script: FinishFiftyPracticePack.fiftyClaim(),
        now: clock.now,
      );
      expect(replay.isDeadEnd, isFalse);
    });
  });

  group('fifty-scoring lesson', () {
    final fivePair = [
      practiceCard(CardRank.five, CardSuit.diamonds),
      practiceCard(CardRank.five, CardSuit.spades),
    ];
    final fiveHearts = practiceCard(CardRank.five, CardSuit.hearts);
    final kingClubs = practiceCard(CardRank.king, CardSuit.clubs);

    test('the proven claim writes the double-edged scores the completion '
        'note reads back', () {
      final clock = PracticeTestClock();
      final session = PracticeSession(
        script: FinishFiftyPracticePack.fiftyScoring(),
        now: clock.now,
      );
      expect(practiceTableValueFor(session, PlayerSeat.south), 51);
      expect(
        practiceTableCardCountFor(session, PlayerSeat.south) +
            session.controller.handFor(PlayerSeat.south).length,
        14,
      );
      runPracticeIntro(session);

      final claim = session.submit(ClassicHareegActionIds.claimFifty);
      expect(claim.status, PracticeSubmitStatus.stepCompleted);
      final fives = session.submit(practiceMeldId([...fivePair, fiveHearts]));
      expect(fives.status, PracticeSubmitStatus.stepCompleted);
      final out = session.submit(practiceDiscardId(kingClubs));
      expect(out.status, PracticeSubmitStatus.lessonCompleted);
      expect(session.controller.roundOutcome, RoundOutcomeType.fiftyFinish);

      // Round 2, so no first-dealt-round exception: the claimant takes -3,
      // the discarder adds their full unopened hand plus 3, and the
      // bystanders add their counts.
      final scores = session.controller.scores;
      expect(scores[PlayerSeat.south], -3);
      expect(scores[PlayerSeat.west], 17);
      expect(scores[PlayerSeat.north], 14);
      expect(scores[PlayerSeat.east], 14);

      // The numbers live on the score sheet the lesson reveals first; the
      // completion note keeps only the rule behind them.
      expect(session.script.showScoresOnCompletion, isTrue);
      final note = session.script.completionNote!(
        AppStrings.english,
        session.controller,
      );
      expect(note, contains('-3'));
      expect(note, contains('plus 3'));
    });
  });

  group('lesson scripts registry (finish & Fifty)', () {
    test('every pack lesson replays an identical deterministic board', () {
      for (final id in [
        'final-discard',
        'normal-finish',
        'perfect-hand-finish',
        'joker-final-discard',
        'fifty-claim',
        'fifty-scoring',
      ]) {
        final first = PracticeLessonRegistry.scriptFor(id)!.buildSnapshot();
        final second = PracticeLessonRegistry.scriptFor(id)!.buildSnapshot();
        expect(
          [for (final c in first.hands[PlayerSeat.south]!) c.id],
          [for (final c in second.hands[PlayerSeat.south]!) c.id],
          reason: '$id south hand must be deterministic',
        );
        expect(
          [for (final c in first.stock) c.id],
          [for (final c in second.stock) c.id],
          reason: '$id stock must be deterministic',
        );
      }
    });

    test('the pack chains lesson to lesson and stops before the explainer', () {
      expect(
        PracticeLessonRegistry.nextScriptInPack('final-discard')?.lessonId,
        'normal-finish',
      );
      expect(
        PracticeLessonRegistry.nextScriptInPack('normal-finish')?.lessonId,
        'perfect-hand-finish',
      );
      expect(
        PracticeLessonRegistry.nextScriptInPack('perfect-hand-finish')
            ?.lessonId,
        'joker-final-discard',
      );
      expect(
        PracticeLessonRegistry.nextScriptInPack('joker-final-discard')
            ?.lessonId,
        'fifty-claim',
      );
      expect(
        PracticeLessonRegistry.nextScriptInPack('fifty-claim')?.lessonId,
        'fifty-scoring',
      );
      expect(
        PracticeLessonRegistry.nextScriptInPack('fifty-scoring'),
        isNull,
        reason: 'strictness-tiers is a reading panel, not a scripted hand',
      );
    });
  });
}
