import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/features/learning/models/practice_lesson_registry.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_board.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_board_grammar.dart';
import 'package:hareeg_table/ui/features/learning/practice/core_turn_practice_pack.dart';
import 'package:hareeg_table/ui/features/learning/practice/table_mechanics_practice_pack.dart';
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

    test('rejects a board that claims the same physical card twice', () {
      // A double-claimed card would otherwise materialise in two hands and
      // break card conservation silently.
      final eight = PracticeBoard.card(CardRank.eight, CardSuit.diamonds);
      expect(
        () => PracticeBoard.build(
          southHand: [eight],
          cpuSeedCards: {
            PlayerSeat.west: [eight],
          },
        ),
        throwsArgumentError,
      );
    });

    test('rejects CPU seed cards for the lesson seat', () {
      // A south entry would claim cards no hand materialises — they would
      // silently vanish from the board.
      expect(
        () => PracticeBoard.build(
          southHand: [PracticeBoard.card(CardRank.two, CardSuit.clubs)],
          cpuSeedCards: {
            PlayerSeat.south: [
              PracticeBoard.card(CardRank.three, CardSuit.clubs),
            ],
          },
        ),
        throwsArgumentError,
      );
    });

    test('rejects CPU seed cards past the dealt hand size', () {
      expect(
        () => PracticeBoard.build(
          southHand: [PracticeBoard.card(CardRank.two, CardSuit.clubs)],
          cpuSeedCards: {
            PlayerSeat.west: [
              for (final suit in CardSuit.values)
                for (final rank in CardRank.values)
                  if (!(rank == CardRank.two && suit == CardSuit.clubs))
                    PracticeBoard.card(rank, suit),
            ],
          },
        ),
        throwsArgumentError,
      );
    });

    test('dresses the pile under the top discard and conserves the cards', () {
      final under = [
        PracticeBoard.card(CardRank.jack, CardSuit.clubs),
        PracticeBoard.card(CardRank.four, CardSuit.diamonds),
      ];
      final top = PracticeBoard.card(CardRank.two, CardSuit.hearts);
      final snapshot = PracticeBoard.build(
        southHand: [PracticeBoard.card(CardRank.three, CardSuit.clubs)],
        priorDiscards: under,
        topDiscard: top,
      );

      expect(
        [for (final card in snapshot.discardPile) card.id],
        [...under.map((c) => c.id), top.id],
        reason: 'dressing sits beneath the top discard, in order',
      );
      final allIds = [
        for (final hand in snapshot.hands.values)
          for (final card in hand) card.id,
        for (final card in snapshot.stock) card.id,
        for (final card in snapshot.discardPile) card.id,
      ];
      expect(allIds, hasLength(106));
      expect(allIds.toSet(), hasLength(106));
    });

    test('rejects pile dressing that re-claims a named card', () {
      final five = PracticeBoard.card(CardRank.five, CardSuit.spades);
      expect(
        () => PracticeBoard.build(southHand: [five], priorDiscards: [five]),
        throwsArgumentError,
      );
    });

    test('builds identical boards on every call', () {
      final first = CoreTurnPracticePack.turnRhythm().buildSnapshot();
      final second = CoreTurnPracticePack.turnRhythm().buildSnapshot();

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

    test('pre-opened practice boards read as one dealt hand', () {
      final snapshot = TableMechanicsPracticePack.pendingDiscard().buildSnapshot();

      expect(
        PracticeBoardGrammar.handAndTableReadAsOneDeal(
          snapshot,
          PlayerSeat.south,
        ),
        isTrue,
      );
    });

    test('board audit reports declared grammar failures', () {
      final snapshot = TableMechanicsPracticePack.pendingDiscard().buildSnapshot();
      final audit = PracticeBoardGrammar.auditSnapshot(
        snapshot,
        const PracticeBoardAuditSpec(
          handAndTableSeats: {PlayerSeat.south},
          expectedTableValues: {PlayerSeat.south: 75},
        ),
      );

      expect(audit.passed, isFalse);
      expect(audit.failures, contains(contains('expected 75')));
    });
  });

  group('PracticeSession (turn rhythm)', () {
    test('offers only the step-allowed engine actions', () {
      final session = PracticeSession(script: CoreTurnPracticePack.turnRhythm());

      // Step 1 narrows the real draw-phase surface (draw or take-discard)
      // down to the taught move.
      expect(
        [for (final a in session.allowedActions) a.kind],
        [ClassicHareegActionKind.drawStock],
      );
    });

    test('draw then discard completes the lesson through the real engine', () {
      final session = PracticeSession(script: CoreTurnPracticePack.turnRhythm());
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
      final session = PracticeSession(script: CoreTurnPracticePack.turnRhythm());

      // Taking the discard is legal at the engine but not taught here.
      final result = session.submit(ClassicHareegActionIds.takeDiscard);

      expect(result.status, PracticeSubmitStatus.notAllowed);
      expect(result.applied, isFalse);
      expect(session.stepIndex, 0);
      expect(session.controller.pendingDiscard, isNull);
    });

    test('real engine rejections surface with their rules message', () {
      final session = PracticeSession(script: CoreTurnPracticePack.turnRhythm());
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

  group('PracticeLessonRegistry.nextScriptInPack', () {
    test('chains the scripted core turn pack lessons in order', () {
      expect(
        PracticeLessonRegistry.nextScriptInPack('turn-rhythm')?.lessonId,
        'first-meld',
      );
      expect(
        PracticeLessonRegistry.nextScriptInPack('first-meld')?.lessonId,
        'discard-opening',
      );
      expect(
        PracticeLessonRegistry.nextScriptInPack('discard-opening')?.lessonId,
        'bait-discard',
      );
      expect(
        PracticeLessonRegistry.nextScriptInPack('bait-discard')?.lessonId,
        'opening-51',
      );
    });

    test('chains the scripted table mechanics lessons in order', () {
      expect(
        PracticeLessonRegistry.nextScriptInPack('pending-discard')?.lessonId,
        'benchmark-pressure',
      );
      // The single-card cover lesson teaches the rule before the stacked
      // one widens it.
      expect(
        PracticeLessonRegistry.nextScriptInPack('benchmark-pressure')?.lessonId,
        'set-cover',
      );
      expect(
        PracticeLessonRegistry.nextScriptInPack('set-cover')?.lessonId,
        'sequence-cover',
      );
      expect(
        PracticeLessonRegistry.nextScriptInPack('sequence-cover')?.lessonId,
        'cover-discard-block',
      );
      expect(
        PracticeLessonRegistry.nextScriptInPack(
          'cover-discard-block',
        )?.lessonId,
        'joker-identity',
      );
      expect(
        PracticeLessonRegistry.nextScriptInPack('joker-identity')?.lessonId,
        'joker-replacement',
      );
    });

    test('stops at the pack boundary', () {
      // Finishing a pack is a deliberate stopping point; the continuation
      // never crosses into the next pack.
      expect(PracticeLessonRegistry.nextScriptInPack('opening-51'), isNull);
      expect(
        PracticeLessonRegistry.nextScriptInPack('joker-replacement'),
        isNull,
      );
    });

    test('returns null for unknown lessons', () {
      expect(PracticeLessonRegistry.nextScriptInPack('not-a-lesson'), isNull);
    });
  });
}
