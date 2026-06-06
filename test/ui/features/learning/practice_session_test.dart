import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_board.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_scripts.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_session.dart';

void main() {
  group('PracticeBoard', () {
    test('conserves every physical card exactly once', () {
      final snapshot = PracticeBoard.build(
        southHand: [
          PracticeBoard.card(CardRank.three, CardSuit.clubs),
          PracticeBoard.card(CardRank.seven, CardSuit.diamonds),
        ],
        topDiscard: PracticeBoard.card(CardRank.five, CardSuit.hearts),
      );

      final allIds = <String>[
        for (final hand in snapshot.hands.values)
          for (final card in hand) card.id,
        for (final card in snapshot.stock) card.id,
        for (final card in snapshot.discardPile) card.id,
      ];

      // Two decks + two jokers under default setup.
      expect(allIds, hasLength(106));
      expect(allIds.toSet(), hasLength(106));
      expect(snapshot.hands[PlayerSeat.south], hasLength(2));
      expect(
        snapshot.discardPile.single.id,
        PracticeBoard.card(CardRank.five, CardSuit.hearts).id,
      );
    });

    test('builds identical boards on every call', () {
      final first = PracticeScripts.turnRhythm().buildSnapshot();
      final second = PracticeScripts.turnRhythm().buildSnapshot();

      expect(
        [for (final c in first.hands[PlayerSeat.south]!) c.id],
        [for (final c in second.hands[PlayerSeat.south]!) c.id],
      );
      expect(
        [for (final c in first.stock) c.id],
        [for (final c in second.stock) c.id],
      );
      expect(first.discardPile.single.id, second.discardPile.single.id);
    });
  });

  group('PracticeSession (turn rhythm)', () {
    test('offers only the step-allowed engine actions', () {
      final session = PracticeSession(script: PracticeScripts.turnRhythm());

      // Step 1 narrows the real draw-phase surface (draw or take-discard)
      // down to the taught move.
      expect(
        [for (final a in session.allowedActions) a.kind],
        [ClassicHareegActionKind.drawStock],
      );
    });

    test('draw then discard completes the lesson through the real engine', () {
      final session = PracticeSession(script: PracticeScripts.turnRhythm());
      final handBefore = session.controller.handFor(PlayerSeat.south).length;

      final draw = session.submit(ClassicHareegActionIds.drawStock);
      expect(draw.status, PracticeSubmitStatus.stepCompleted);
      expect(
        session.controller.handFor(PlayerSeat.south),
        hasLength(handBefore + 1),
      );
      expect(session.stepIndex, 1);

      // Step 2 offers exactly one discard action per hand card.
      final discardActions = session.allowedActions;
      expect(
        discardActions.every((a) => a.kind == ClassicHareegActionKind.discard),
        isTrue,
      );
      expect(discardActions, hasLength(handBefore + 1));

      final done = session.submit(discardActions.first.id);
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
      expect(session.isComplete, isTrue);
      expect(session.allowedActions, isEmpty);
    });

    test('actions outside the step are not applied', () {
      final session = PracticeSession(script: PracticeScripts.turnRhythm());

      // Taking the discard is legal at the engine but not taught here.
      final result = session.submit(ClassicHareegActionIds.takeDiscard);

      expect(result.status, PracticeSubmitStatus.notAllowed);
      expect(result.applied, isFalse);
      expect(session.stepIndex, 0);
      expect(session.controller.pendingDiscard, isNull);
    });

    test('real engine rejections surface with their rules message', () {
      final session = PracticeSession(script: PracticeScripts.turnRhythm());
      session.submit(ClassicHareegActionIds.drawStock);

      // A discard for a card south does not hold: allowed kind, rejected by
      // the rules engine.
      final bogus = PracticeBoard.card(CardRank.ace, CardSuit.spades);
      final result = session.submit(
        '${ClassicHareegActionIds.discardPrefix}${bogus.id}',
      );

      expect(result.status, PracticeSubmitStatus.rejected);
      expect(result.message, isNotEmpty);
      expect(session.stepIndex, 1, reason: 'step must not advance');
    });
  });

  group('PracticeScripts.nextScriptInPack', () {
    test('chains the scripted core turn pack lessons in order', () {
      expect(
        PracticeScripts.nextScriptInPack('turn-rhythm')?.lessonId,
        'pending-discard',
      );
      expect(
        PracticeScripts.nextScriptInPack('pending-discard')?.lessonId,
        'meld-picker',
      );
      expect(
        PracticeScripts.nextScriptInPack('meld-picker')?.lessonId,
        'opening-51',
      );
    });

    test('stops at the pack boundary', () {
      // Finishing a pack is a deliberate stopping point; the continuation
      // never crosses into the next pack.
      expect(PracticeScripts.nextScriptInPack('opening-51'), isNull);
    });

    test('returns null for unknown lessons', () {
      expect(PracticeScripts.nextScriptInPack('not-a-lesson'), isNull);
    });
  });
}
