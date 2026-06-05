import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_scripts.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_session.dart';

HareegCard _card(CardRank rank, CardSuit suit) =>
    HareegCard.standard(rank: rank, suit: suit, deckIndex: 0);

String _discardId(HareegCard card) =>
    '${ClassicHareegActionIds.discardPrefix}${card.id}';

String _meldId(List<HareegCard> cards) =>
    ClassicHareegActionIds.playMeldActionId(cards.map((c) => c.id));

void main() {
  group('pending-discard lesson', () {
    final eightClubs = _card(CardRank.eight, CardSuit.clubs);
    final eightHearts = _card(CardRank.eight, CardSuit.hearts);
    final eightDiamonds = _card(CardRank.eight, CardSuit.diamonds);
    final kingSpades = _card(CardRank.king, CardSuit.spades);

    test('use path: take, meld the eights, discard', () {
      final session = PracticeSession(script: PracticeScripts.pendingDiscard());

      expect(
        [for (final a in session.allowedActions) a.kind],
        [ClassicHareegActionKind.takeDiscard],
        reason: 'step 1 teaches taking over drawing',
      );

      final take = session.submit(ClassicHareegActionIds.takeDiscard);
      expect(take.status, PracticeSubmitStatus.stepCompleted);
      expect(session.controller.pendingDiscard?.id, eightDiamonds.id);

      final meld = session.submit(
        _meldId([eightClubs, eightHearts, eightDiamonds]),
      );
      expect(meld.status, PracticeSubmitStatus.stepCompleted);
      expect(session.controller.pendingDiscard, isNull);

      final done = session.submit(_discardId(kingSpades));
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });

    test('return path: take, return, draw, discard', () {
      final session = PracticeSession(script: PracticeScripts.pendingDiscard());

      session.submit(ClassicHareegActionIds.takeDiscard);
      final returned = session.submit(
        ClassicHareegActionIds.returnPendingDiscard,
      );
      expect(returned.status, PracticeSubmitStatus.stepCompleted);
      expect(session.controller.topDiscard?.id, eightDiamonds.id);

      // Back in draw phase: the final step accepts the draw, then completes
      // on the discard.
      final draw = session.submit(ClassicHareegActionIds.drawStock);
      expect(draw.status, PracticeSubmitStatus.accepted);

      final done = session.submit(_discardId(kingSpades));
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });

    test('wrong path: drawing in step 1 is not offered or applied', () {
      final session = PracticeSession(script: PracticeScripts.pendingDiscard());

      final result = session.submit(ClassicHareegActionIds.drawStock);

      expect(result.status, PracticeSubmitStatus.notAllowed);
      expect(session.stepIndex, 0);
    });

    test('wrong path: an invalid meld with the pending card is rejected by '
        'the rules engine', () {
      final session = PracticeSession(script: PracticeScripts.pendingDiscard());
      session.submit(ClassicHareegActionIds.takeDiscard);

      final result = session.submit(
        _meldId([eightClubs, eightHearts, kingSpades]),
      );

      expect(result.status, PracticeSubmitStatus.rejected);
      expect(result.message, isNotEmpty);
      expect(session.stepIndex, 1, reason: 'step must not advance');
    });
  });

  group('meld-picker lesson', () {
    final fiveSpades = _card(CardRank.five, CardSuit.spades);
    final sixSpades = _card(CardRank.six, CardSuit.spades);
    final sevenSpades = _card(CardRank.seven, CardSuit.spades);
    final nineDiamonds = _card(CardRank.nine, CardSuit.diamonds);

    test('playing the exact legal run completes the lesson', () {
      final session = PracticeSession(script: PracticeScripts.meldPicker());

      final meld = session.submit(
        _meldId([fiveSpades, sixSpades, sevenSpades]),
      );
      expect(meld.status, PracticeSubmitStatus.stepCompleted);
      expect(
        session.controller.tableMeldsFor(PlayerSeat.south),
        hasLength(1),
      );

      final done = session.submit(_discardId(nineDiamonds));
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });

    test('wrong path: a broken selection is rejected by the validator', () {
      final session = PracticeSession(script: PracticeScripts.meldPicker());

      final result = session.submit(
        _meldId([fiveSpades, sixSpades, nineDiamonds]),
      );

      expect(result.status, PracticeSubmitStatus.rejected);
      expect(result.message, isNotEmpty);
      expect(session.controller.tableMeldsFor(PlayerSeat.south), isEmpty);
    });
  });

  group('opening-51 lesson', () {
    final kings = [
      _card(CardRank.king, CardSuit.spades),
      _card(CardRank.king, CardSuit.diamonds),
      _card(CardRank.king, CardSuit.hearts),
    ];
    final jacks = [
      _card(CardRank.jack, CardSuit.clubs),
      _card(CardRank.jack, CardSuit.diamonds),
      _card(CardRank.jack, CardSuit.hearts),
    ];
    final threeClubs = _card(CardRank.three, CardSuit.clubs);

    test('staging 30 then 60 opens through the real benchmark', () {
      final session = PracticeSession(script: PracticeScripts.openingTo51());

      final first = session.submit(_meldId(kings));
      expect(first.status, PracticeSubmitStatus.stepCompleted);
      expect(
        session.controller.openingState.hasOpened(PlayerSeat.south),
        isFalse,
        reason: '30 staged is below the 51 requirement',
      );

      final second = session.submit(_meldId(jacks));
      expect(second.status, PracticeSubmitStatus.stepCompleted);
      expect(
        session.controller.openingState.hasOpened(PlayerSeat.south),
        isTrue,
        reason: '60 total satisfies the benchmark',
      );

      final done = session.submit(_discardId(threeClubs));
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });

    test('wrong path: discarding below the benchmark is not offered', () {
      final session = PracticeSession(script: PracticeScripts.openingTo51());
      session.submit(_meldId(kings));

      final result = session.submit(_discardId(threeClubs));

      expect(result.status, PracticeSubmitStatus.notAllowed);
      expect(
        session.controller.openingState.hasOpened(PlayerSeat.south),
        isFalse,
      );
    });

    test('wrong path: a mixed selection is rejected by the validator', () {
      final session = PracticeSession(script: PracticeScripts.openingTo51());
      session.submit(_meldId(kings));

      final result = session.submit(
        _meldId([jacks[0], jacks[1], threeClubs]),
      );

      expect(result.status, PracticeSubmitStatus.rejected);
      expect(result.message, isNotEmpty);
    });
  });

  group('lesson scripts registry', () {
    test('the core turn pack is fully scripted', () {
      for (final id in [
        'turn-rhythm',
        'pending-discard',
        'meld-picker',
        'opening-51',
      ]) {
        expect(
          PracticeScripts.byId(id),
          isNotNull,
          reason: '$id must be playable',
        );
      }
    });

    test('every script replays an identical deterministic board', () {
      for (final id in [
        'pending-discard',
        'meld-picker',
        'opening-51',
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
  });
}
