import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_scripts.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_session.dart';

HareegCard _card(CardRank rank, CardSuit suit) =>
    HareegCard.standard(rank: rank, suit: suit, deckIndex: 0);

String _discardId(HareegCard card) =>
    '${ClassicHareegActionIds.discardPrefix}${card.id}';

String _meldId(List<HareegCard> cards) =>
    ClassicHareegActionIds.playMeldActionId(cards.map((c) => c.id));

int _tableValueFor(PracticeSession session, PlayerSeat seat) {
  return session.controller
      .tableMeldsFor(seat)
      .fold<int>(0, (sum, meld) => sum + meld.totalValue);
}

int _tableCardCountFor(PracticeSession session, PlayerSeat seat) {
  return session.controller
      .tableMeldsFor(seat)
      .fold<int>(0, (sum, meld) => sum + meld.cards.length);
}

/// Applies the script's intro the way the table's scripted CPU presenter
/// does: straight through the controller, in order, expecting every action
/// to be legal and the turn to land on the player.
void _runIntro(PracticeSession session) {
  for (final actionId in session.script.introActionIds) {
    final result = session.controller.applyAction(actionId);
    expect(
      result.isSuccess,
      isTrue,
      reason: 'intro action $actionId must be legal: ${result.message}',
    );
  }
  expect(
    session.controller.currentSeat,
    PlayerSeat.south,
    reason: 'the intro must hand the turn to the player',
  );
}

/// A controllable clock for walking the Fifty window deterministically: the
/// intro's discard stamps the window-open time through the same injected
/// `now` the expiry check reads.
class _FakeClock {
  DateTime current = DateTime.utc(2026, 1, 1, 12);

  DateTime now() => current;

  void advance(Duration delta) => current = current.add(delta);
}

void main() {
  group('final-discard lesson', () {
    final nines = [
      _card(CardRank.nine, CardSuit.clubs),
      _card(CardRank.nine, CardSuit.diamonds),
      _card(CardRank.nine, CardSuit.hearts),
    ];
    final fiveSpades = _card(CardRank.five, CardSuit.spades);

    test('the mid-turn board accounts for every card: 11 opened at exactly '
        '51 plus 4 in hand = the dealt 14 plus the draw', () {
      final session = PracticeSession(script: PracticeScripts.finalDiscard());
      final controller = session.controller;

      expect(controller.openingState.hasOpened(PlayerSeat.south), isTrue);
      expect(
        _tableValueFor(session, PlayerSeat.south),
        51,
        reason: 'a visible opening must total the requirement it implies',
      );
      expect(
        _tableCardCountFor(session, PlayerSeat.south) +
            controller.handFor(PlayerSeat.south).length,
        15,
        reason: 'hand + own table = 14 dealt + this turn\'s draw',
      );
      expect(
        controller.discardPile,
        hasLength(5),
        reason: 'a late-round pile carries the table\'s throw history',
      );
      for (final seat in [PlayerSeat.east, PlayerSeat.north, PlayerSeat.west]) {
        expect(
          controller.handFor(seat),
          hasLength(14),
          reason: 'an unopened seat still holds its full deal',
        );
      }
    });

    test(
      'meld the nines, then the last card leaves as the winning discard',
      () {
        final session = PracticeSession(script: PracticeScripts.finalDiscard());

        final meld = session.submit(_meldId(nines));
        expect(meld.status, PracticeSubmitStatus.stepCompleted);
        expect(session.controller.handFor(PlayerSeat.south), hasLength(1));

        final out = session.submit(_discardId(fiveSpades));
        expect(out.status, PracticeSubmitStatus.lessonCompleted);
        expect(session.controller.isRoundOver, isTrue);
        expect(session.controller.roundOutcome, RoundOutcomeType.normalFinish);
        expect(session.controller.roundResult?.winner, PlayerSeat.south);
      },
    );

    test('retracting the nines walks the lesson back to the meld step', () {
      final session = PracticeSession(script: PracticeScripts.finalDiscard());
      session.submit(_meldId(nines));
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
      final stray = session.submit(_discardId(fiveSpades));
      expect(stray.status, PracticeSubmitStatus.notAllowed);

      // Replay the nines and finish for real.
      session.submit(_meldId(nines));
      final out = session.submit(_discardId(fiveSpades));
      expect(out.status, PracticeSubmitStatus.lessonCompleted);
      expect(session.controller.isRoundOver, isTrue);
    });

    test('wrong path: throwing a card before the nines stays dark', () {
      final session = PracticeSession(script: PracticeScripts.finalDiscard());

      final early = session.submit(_discardId(fiveSpades));
      expect(early.status, PracticeSubmitStatus.notAllowed);
      expect(session.stepIndex, 0);
      expect(
        session.offersActionId(_discardId(fiveSpades)),
        isFalse,
        reason: 'the affordance gate must darken the early throw',
      );
    });
  });

  group('normal-finish lesson', () {
    final queens = [
      _card(CardRank.queen, CardSuit.clubs),
      _card(CardRank.queen, CardSuit.diamonds),
      _card(CardRank.queen, CardSuit.hearts),
    ];
    final heartRun = [
      _card(CardRank.four, CardSuit.hearts),
      _card(CardRank.five, CardSuit.hearts),
      _card(CardRank.six, CardSuit.hearts),
      _card(CardRank.seven, CardSuit.hearts),
      _card(CardRank.eight, CardSuit.hearts),
    ];
    final sevenSpades = _card(CardRank.seven, CardSuit.spades);

    test(
      'queens, heart run, out — and the engine scores the room for real',
      () {
        final session = PracticeSession(script: PracticeScripts.normalFinish());

        expect(_tableValueFor(session, PlayerSeat.south), 51);
        expect(
          _tableCardCountFor(session, PlayerSeat.south) +
              session.controller.handFor(PlayerSeat.south).length,
          15,
          reason: 'hand + own table = 14 dealt + this turn\'s draw',
        );

        final first = session.submit(_meldId(queens));
        expect(first.status, PracticeSubmitStatus.stepCompleted);
        final second = session.submit(_meldId(heartRun));
        expect(second.status, PracticeSubmitStatus.stepCompleted);
        final out = session.submit(_discardId(sevenSpades));
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
      final session = PracticeSession(script: PracticeScripts.normalFinish());
      session.submit(_meldId(queens));
      session.submit(_meldId(heartRun));
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
      final replay = session.submit(_meldId(queens));
      expect(replay.status, PracticeSubmitStatus.stepCompleted);
      expect(
        session.stepIndex,
        2,
        reason: 'a still-demonstrated step must not be re-taught',
      );

      final out = session.submit(_discardId(sevenSpades));
      expect(out.status, PracticeSubmitStatus.lessonCompleted);
    });

    test('wrong path: the heart run stays dark while the prompt teaches the '
        'queens', () {
      final session = PracticeSession(script: PracticeScripts.normalFinish());

      final early = session.submit(_meldId(heartRun));
      expect(early.status, PracticeSubmitStatus.notAllowed);
      expect(session.stepIndex, 0);
    });
  });

  group('fifty-claim lesson', () {
    final eightDiamonds = _card(CardRank.eight, CardSuit.diamonds);
    final eightPair = [
      _card(CardRank.eight, CardSuit.clubs),
      _card(CardRank.eight, CardSuit.hearts),
    ];
    final twos = [
      _card(CardRank.two, CardSuit.spades),
      _card(CardRank.two, CardSuit.diamonds),
      _card(CardRank.two, CardSuit.hearts),
    ];
    final queenSpades = _card(CardRank.queen, CardSuit.spades);

    test('the turn-start board accounts for every card and west\'s scripted '
        'throw opens the real 8-second window', () {
      final clock = _FakeClock();
      final session = PracticeSession(
        script: PracticeScripts.fiftyClaim(),
        now: clock.now,
      );

      expect(_tableValueFor(session, PlayerSeat.south), 51);
      expect(
        _tableCardCountFor(session, PlayerSeat.south) +
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

      _runIntro(session);

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
      final clock = _FakeClock();
      final session = PracticeSession(
        script: PracticeScripts.fiftyClaim(),
        now: clock.now,
      );
      _runIntro(session);

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
      final clock = _FakeClock();
      final session = PracticeSession(
        script: PracticeScripts.fiftyClaim(),
        now: clock.now,
      );
      _runIntro(session);
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
      final early = session.submit(_discardId(queenSpades));
      expect(early.status, PracticeSubmitStatus.notAllowed);

      final eights = session.submit(_meldId([...eightPair, eightDiamonds]));
      expect(eights.status, PracticeSubmitStatus.stepCompleted);
      final twosMeld = session.submit(_meldId(twos));
      expect(twosMeld.status, PracticeSubmitStatus.stepCompleted);

      final out = session.submit(_discardId(queenSpades));
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
      final clock = _FakeClock();
      final session = PracticeSession(
        script: PracticeScripts.fiftyClaim(),
        now: clock.now,
      );
      _runIntro(session);
      session.submit(ClassicHareegActionIds.claimFifty);
      session.submit(_meldId([...eightPair, eightDiamonds]));
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
      session.submit(_meldId([...eightPair, eightDiamonds]));
      session.submit(_meldId(twos));
      final out = session.submit(_discardId(queenSpades));
      expect(out.status, PracticeSubmitStatus.lessonCompleted);
      expect(session.controller.roundOutcome, RoundOutcomeType.fiftyFinish);
    });

    test('without the practice hold the window expires into the dead end', () {
      final clock = _FakeClock();
      final session = PracticeSession(
        script: PracticeScripts.fiftyClaim(pauseTimer: false),
        now: clock.now,
      );
      _runIntro(session);

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
        script: PracticeScripts.fiftyClaim(),
        now: clock.now,
      );
      expect(replay.isDeadEnd, isFalse);
    });
  });

  group('fifty-scoring lesson', () {
    final fivePair = [
      _card(CardRank.five, CardSuit.diamonds),
      _card(CardRank.five, CardSuit.spades),
    ];
    final fiveHearts = _card(CardRank.five, CardSuit.hearts);
    final kingClubs = _card(CardRank.king, CardSuit.clubs);

    test('the proven claim writes the double-edged scores the completion '
        'note reads back', () {
      final clock = _FakeClock();
      final session = PracticeSession(
        script: PracticeScripts.fiftyScoring(),
        now: clock.now,
      );
      expect(_tableValueFor(session, PlayerSeat.south), 51);
      expect(
        _tableCardCountFor(session, PlayerSeat.south) +
            session.controller.handFor(PlayerSeat.south).length,
        14,
      );
      _runIntro(session);

      final claim = session.submit(ClassicHareegActionIds.claimFifty);
      expect(claim.status, PracticeSubmitStatus.stepCompleted);
      final fives = session.submit(_meldId([...fivePair, fiveHearts]));
      expect(fives.status, PracticeSubmitStatus.stepCompleted);
      final out = session.submit(_discardId(kingClubs));
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
        'fifty-claim',
        'fifty-scoring',
      ]) {
        final first = PracticeScripts.byId(id)!.buildSnapshot();
        final second = PracticeScripts.byId(id)!.buildSnapshot();
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
        PracticeScripts.nextScriptInPack('final-discard')?.lessonId,
        'normal-finish',
      );
      expect(
        PracticeScripts.nextScriptInPack('normal-finish')?.lessonId,
        'fifty-claim',
      );
      expect(
        PracticeScripts.nextScriptInPack('fifty-claim')?.lessonId,
        'fifty-scoring',
      );
      expect(
        PracticeScripts.nextScriptInPack('fifty-scoring'),
        isNull,
        reason: 'strictness-tiers is a reading panel, not a scripted hand',
      );
    });
  });
}
