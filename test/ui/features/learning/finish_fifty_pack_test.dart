import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_board.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_scripts.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_session.dart';

HareegCard _card(CardRank rank, CardSuit suit) =>
    HareegCard.standard(rank: rank, suit: suit, deckIndex: 0);

String _discardId(HareegCard card) =>
    '${ClassicHareegActionIds.discardPrefix}${card.id}';

String _meldId(List<HareegCard> cards) =>
    ClassicHareegActionIds.playMeldActionId(cards.map((c) => c.id));

void main() {
  group('final-discard lesson', () {
    final nines = [
      _card(CardRank.nine, CardSuit.clubs),
      _card(CardRank.nine, CardSuit.diamonds),
      _card(CardRank.nine, CardSuit.hearts),
    ];
    final fiveSpades = _card(CardRank.five, CardSuit.spades);

    test('meld then final discard wins the round', () {
      final session = PracticeSession(script: PracticeScripts.finalDiscard());

      expect(
        session.submit(_meldId(nines)).status,
        PracticeSubmitStatus.stepCompleted,
      );
      expect(session.controller.isRoundOver, isFalse);

      final done = session.submit(_discardId(fiveSpades));
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
      expect(session.controller.isRoundOver, isTrue);
      expect(session.controller.scores[PlayerSeat.south], -1);
    });

    test('wrong path: a broken meld with the spare card is rejected', () {
      final session = PracticeSession(script: PracticeScripts.finalDiscard());

      final result = session.submit(
        _meldId([nines[0], nines[1], fiveSpades]),
      );

      expect(result.status, PracticeSubmitStatus.rejected);
      expect(result.message, isNotEmpty);
    });

    test('rule check: playing every card without a final discard is refused '
        'by the engine', () {
      // Not a lesson flow — a direct controller assertion that the rule the
      // lesson teaches is real: a hand cannot empty itself through melds.
      final controller = ClassicHareegGameController.fromSnapshot(
        PracticeBoard.build(
          southHand: nines,
          topDiscard: _card(CardRank.two, CardSuit.hearts),
          openingState: PracticeBoard.openedFor(PlayerSeat.south),
          turnPhase: TurnPhase.action,
        ),
      );

      final result = controller.applyAction(_meldId(nines));

      expect(result.isSuccess, isFalse);
      expect(result.message, isNotEmpty);
      expect(controller.handFor(PlayerSeat.south), hasLength(3));
    });
  });

  group('normal-finish lesson', () {
    test('two melds and the final discard score -1 for the winner', () {
      final session = PracticeSession(script: PracticeScripts.normalFinish());

      expect(
        session
            .submit(
              _meldId([
                _card(CardRank.queen, CardSuit.clubs),
                _card(CardRank.queen, CardSuit.diamonds),
                _card(CardRank.queen, CardSuit.hearts),
              ]),
            )
            .status,
        PracticeSubmitStatus.stepCompleted,
      );
      expect(
        session
            .submit(
              _meldId([
                _card(CardRank.three, CardSuit.clubs),
                _card(CardRank.three, CardSuit.diamonds),
                _card(CardRank.three, CardSuit.hearts),
              ]),
            )
            .status,
        PracticeSubmitStatus.stepCompleted,
      );

      final done = session.submit(
        _discardId(_card(CardRank.seven, CardSuit.spades)),
      );
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
      expect(session.controller.scores[PlayerSeat.south], -1);
      // Everyone else pays their leftover card count (dummy CPU hands of 5).
      expect(session.controller.scores[PlayerSeat.east], 5);
    });

    test('wrong path: discarding before both melds is not offered', () {
      final session = PracticeSession(script: PracticeScripts.normalFinish());

      final result = session.submit(
        _discardId(_card(CardRank.seven, CardSuit.spades)),
      );

      expect(result.status, PracticeSubmitStatus.notAllowed);
    });
  });

  group('fifty-claim lesson', () {
    final windowOpened = DateTime.utc(2026, 6, 5, 12, 0, 0);

    test('claiming inside the window finishes the round as Fifty', () {
      final script = PracticeScripts.fiftyClaim(clock: () => windowOpened);
      final session = PracticeSession(
        script: script,
        now: () => windowOpened.add(const Duration(seconds: 2)),
      );

      expect(session.controller.fiftySecondsRemaining, 6);
      expect(
        [for (final a in session.allowedActions) a.kind],
        [ClassicHareegActionKind.claimFifty],
      );

      final done = session.submit(ClassicHareegActionIds.claimFifty);
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
      expect(session.controller.isRoundOver, isTrue);
      expect(
        session.controller.scores[PlayerSeat.south],
        -3,
        reason: 'round 2 Fifty pays the winner -3',
      );
    });

    test('missed window: the claim disappears and a forced claim is '
        'rejected', () {
      final script = PracticeScripts.fiftyClaim(clock: () => windowOpened);
      final session = PracticeSession(
        script: script,
        now: () => windowOpened.add(const Duration(seconds: 30)),
      );

      expect(session.controller.fiftySecondsRemaining, isNull);
      expect(session.allowedActions, isEmpty, reason: 'dead end → restart');

      final result = session.submit(ClassicHareegActionIds.claimFifty);
      expect(result.status, PracticeSubmitStatus.rejected);
      expect(result.message, isNotEmpty);
      expect(session.controller.isRoundOver, isFalse);
    });

    test('restarting after a miss rebuilds a live window', () {
      var callCount = 0;
      // The script clock advances on each build: the first run's window is
      // long past for the session clock, the second run's is fresh.
      DateTime clock() {
        callCount += 1;
        return callCount == 1
            ? windowOpened
            : windowOpened.add(const Duration(seconds: 60));
      }

      final script = PracticeScripts.fiftyClaim(clock: clock);
      DateTime sessionNow() => windowOpened.add(const Duration(seconds: 61));

      final missed = PracticeSession(script: script, now: sessionNow);
      expect(missed.allowedActions, isEmpty);

      final retry = PracticeSession(script: script, now: sessionNow);
      expect(retry.allowedActions, isNotEmpty, reason: 'fresh window');
      expect(
        retry.submit(ClassicHareegActionIds.claimFifty).status,
        PracticeSubmitStatus.lessonCompleted,
      );
    });
  });

  group('fifty-scoring lesson', () {
    final windowOpened = DateTime.utc(2026, 6, 5, 12, 0, 0);

    test('the completion note carries the real ledger impact', () {
      final script = PracticeScripts.fiftyScoring(clock: () => windowOpened);
      final session = PracticeSession(
        script: script,
        now: () => windowOpened.add(const Duration(seconds: 1)),
      );

      final done = session.submit(ClassicHareegActionIds.claimFifty);
      expect(done.status, PracticeSubmitStatus.lessonCompleted);

      expect(session.controller.scores[PlayerSeat.south], -3);
      // The discarder pays leftover card count plus 3 (dummy hand of 5).
      expect(session.controller.scores[PlayerSeat.west], 8);

      final note = script.completionNote!(
        AppStrings.english,
        session.controller,
      );
      expect(note, contains('-3'));
      expect(note, contains('You -3 · West 8'));
    });
  });

  group('lesson scripts registry', () {
    test('the finish and Fifty pack is fully scripted and deterministic', () {
      for (final id in [
        'final-discard',
        'normal-finish',
        'fifty-claim',
        'fifty-scoring',
      ]) {
        expect(PracticeScripts.byId(id), isNotNull, reason: '$id playable');
        final first = PracticeScripts.byId(id)!.buildSnapshot();
        final second = PracticeScripts.byId(id)!.buildSnapshot();
        expect(
          [for (final c in first.hands[PlayerSeat.south]!) c.id],
          [for (final c in second.hands[PlayerSeat.south]!) c.id],
          reason: '$id south hand must be deterministic',
        );
      }
    });
  });
}
