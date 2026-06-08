import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/features/learning/models/practice_catalog.dart';
import 'package:hareeg_table/ui/features/learning/models/practice_lesson_registry.dart';
import 'package:hareeg_table/ui/features/learning/practice/core_turn_practice_pack.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_session.dart';

import '../../../support/practice_lesson_harness.dart';

void main() {
  group('first-meld lesson', () {
    final heartRun = [
      practiceCard(CardRank.nine, CardSuit.hearts),
      practiceCard(CardRank.ten, CardSuit.hearts),
      practiceCard(CardRank.jack, CardSuit.hearts),
      practiceCard(CardRank.queen, CardSuit.hearts),
      practiceCard(CardRank.king, CardSuit.hearts),
      practiceCard(CardRank.ace, CardSuit.hearts),
    ];
    final twoClubs = practiceCard(CardRank.two, CardSuit.clubs);

    test('draw, open with the 59 run, discard', () {
      final session = PracticeSession(script: CoreTurnPracticePack.firstMeld());

      expect(
        session.controller.handFor(PlayerSeat.south),
        hasLength(14),
        reason: 'opening lessons deal the real hand size',
      );
      expect(
        [for (final a in session.allowedActions) a.kind],
        [ClassicHareegActionKind.drawStock],
        reason: 'the turn still starts with a draw',
      );

      final draw = session.submit(ClassicHareegActionIds.drawStock);
      expect(draw.status, PracticeSubmitStatus.stepCompleted);

      final meld = session.submit(practiceMeldId(heartRun));
      expect(meld.status, PracticeSubmitStatus.stepCompleted);
      expect(
        session.controller.openingState.hasOpened(PlayerSeat.south),
        isTrue,
        reason: '59 clears the 51 benchmark in a single play',
      );

      final done = session.submit(practiceDiscardId(twoClubs));
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });

    test('wrong path: melding before the draw is not offered', () {
      final session = PracticeSession(script: CoreTurnPracticePack.firstMeld());

      final result = session.submit(practiceMeldId(heartRun));

      expect(result.status, PracticeSubmitStatus.notAllowed);
      expect(session.stepIndex, 0);
    });

    test('wrong path: an extra card breaks the run at the validator', () {
      final session = PracticeSession(script: CoreTurnPracticePack.firstMeld());
      session.submit(ClassicHareegActionIds.drawStock);

      final result = session.submit(practiceMeldId([...heartRun, twoClubs]));

      expect(result.status, PracticeSubmitStatus.rejected);
      expect(result.message, isNotEmpty);
      expect(session.controller.tableMeldsFor(PlayerSeat.south), isEmpty);
    });

    test('wrong split: a valid partial run stages, the take-back recovers it,'
        ' and the full run still opens', () {
      // The trap a real playtest hit: K-Q-J of hearts is itself a legal run,
      // but it stages at 30 and the leftover 9-10-A can never meld — without
      // a take-back the lesson would strand.
      final session = PracticeSession(script: CoreTurnPracticePack.firstMeld());
      session.submit(ClassicHareegActionIds.drawStock);

      final partial = session.submit(
        practiceMeldId([heartRun[4], heartRun[3], heartRun[2]]),
      );
      expect(
        partial.status,
        PracticeSubmitStatus.accepted,
        reason: 'staging applies but does not demonstrate the opening',
      );
      expect(session.controller.tableMeldsFor(PlayerSeat.south), hasLength(1));

      // The correction is always offered and never advances the step.
      final undo = session.submit(ClassicHareegActionIds.returnOpeningMelds);
      expect(undo.status, PracticeSubmitStatus.corrected);
      expect(session.controller.tableMeldsFor(PlayerSeat.south), isEmpty);
      expect(session.stepIndex, 1, reason: 'still on the meld step');

      final meld = session.submit(practiceMeldId(heartRun));
      expect(meld.status, PracticeSubmitStatus.stepCompleted);
      final done = session.submit(practiceDiscardId(twoClubs));
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });
  });

  group('discard-opening lesson', () {
    final queens = [
      practiceCard(CardRank.queen, CardSuit.spades),
      practiceCard(CardRank.queen, CardSuit.diamonds),
      practiceCard(CardRank.queen, CardSuit.hearts),
    ];
    final eightClubs = practiceCard(CardRank.eight, CardSuit.clubs);
    final eightHearts = practiceCard(CardRank.eight, CardSuit.hearts);
    final eightDiamonds = practiceCard(CardRank.eight, CardSuit.diamonds);
    final twoHearts = practiceCard(CardRank.two, CardSuit.hearts);

    test('the intro plays west throwing the eight onto an empty pile', () {
      final session = PracticeSession(script: CoreTurnPracticePack.discardOpening());

      expect(session.controller.currentSeat, PlayerSeat.west);
      expect(
        session.controller.discardPile,
        isEmpty,
        reason: 'the player watches the eight land, not finds it pre-baked',
      );

      runPracticeIntro(session);

      expect(session.controller.topDiscard?.id, eightDiamonds.id);
    });

    test('take the eight, open with both sets, discard', () {
      final session = PracticeSession(script: CoreTurnPracticePack.discardOpening());
      runPracticeIntro(session);

      expect(
        [for (final a in session.allowedActions) a.kind],
        [ClassicHareegActionKind.takeDiscard],
        reason: 'step 1 teaches taking the card that opens',
      );

      final take = session.submit(ClassicHareegActionIds.takeDiscard);
      expect(take.status, PracticeSubmitStatus.stepCompleted);
      expect(session.controller.pendingDiscard?.id, eightDiamonds.id);

      // The eights stage at 24: pending resolved, opening not yet — the
      // lesson moves to its dedicated queens step.
      final eights = session.submit(
        practiceMeldId([eightClubs, eightHearts, eightDiamonds]),
      );
      expect(eights.status, PracticeSubmitStatus.stepCompleted);
      expect(session.controller.pendingDiscard, isNull);
      expect(
        session.controller.openingState.hasOpened(PlayerSeat.south),
        isFalse,
        reason: '24 staged is below the 51 requirement',
      );

      final queensMeld = session.submit(practiceMeldId(queens));
      expect(queensMeld.status, PracticeSubmitStatus.stepCompleted);
      expect(
        session.controller.openingState.hasOpened(PlayerSeat.south),
        isTrue,
        reason: '24 + 30 = 54, past the benchmark',
      );

      final done = session.submit(practiceDiscardId(twoHearts));
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });

    test('wrong path: drawing in step 1 is not offered', () {
      final session = PracticeSession(script: CoreTurnPracticePack.discardOpening());
      runPracticeIntro(session);

      final result = session.submit(ClassicHareegActionIds.drawStock);

      expect(result.status, PracticeSubmitStatus.notAllowed);
      expect(session.stepIndex, 0);
    });

    test('wrong path: the queens stay off-step until the taken eight is '
        'melded', () {
      final session = PracticeSession(script: CoreTurnPracticePack.discardOpening());
      runPracticeIntro(session);
      session.submit(ClassicHareegActionIds.takeDiscard);

      // Under the relaxed taken-discard rule the queens are LEGAL here, but
      // the lesson pins this step to the eights — the taught move is using
      // the taken card in the meld it completes.
      final result = session.submit(practiceMeldId(queens));

      expect(result.status, PracticeSubmitStatus.notAllowed);
      expect(session.stepIndex, 1, reason: 'step must not advance');
    });
  });

  group('bait-discard lesson', () {
    final queenSpades = practiceCard(CardRank.queen, CardSuit.spades);
    final sevens = [
      practiceCard(CardRank.seven, CardSuit.spades),
      practiceCard(CardRank.seven, CardSuit.clubs),
      practiceCard(CardRank.seven, CardSuit.hearts),
    ];

    test('the intro plays west genuinely opening at exactly the 51 '
        'benchmark, then throwing the bait', () {
      final session = PracticeSession(script: CoreTurnPracticePack.baitDiscard());

      expect(session.controller.currentSeat, PlayerSeat.west);
      expect(
        session.controller.tableMeldsFor(PlayerSeat.west),
        isEmpty,
        reason: 'the opening happens on screen, not pre-baked',
      );

      runPracticeIntro(session);

      expect(
        session.controller.openingState.hasOpened(PlayerSeat.west),
        isTrue,
      );
      final melds = session.controller.tableMeldsFor(PlayerSeat.west);
      expect(melds, hasLength(2));
      expect(
        melds.fold<int>(0, (sum, meld) => sum + meld.totalValue),
        51,
        reason: 'a visible opening must satisfy the requirement it displays',
      );
      expect(
        session.controller.topDiscard?.id,
        practiceCard(CardRank.seven, CardSuit.hearts).id,
      );
    });

    test('the bait stays dark: only the draw is offered, then a discard', () {
      final session = PracticeSession(script: CoreTurnPracticePack.baitDiscard());
      runPracticeIntro(session);

      expect(
        [for (final a in session.allowedActions) a.kind],
        [ClassicHareegActionKind.drawStock],
        reason: 'taking the seven must not be offered',
      );

      final take = session.submit(ClassicHareegActionIds.takeDiscard);
      expect(take.status, PracticeSubmitStatus.notAllowed);
      expect(session.controller.pendingDiscard, isNull);

      final draw = session.submit(ClassicHareegActionIds.drawStock);
      expect(draw.status, PracticeSubmitStatus.stepCompleted);

      final done = session.submit(practiceDiscardId(queenSpades));
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });

    test('wrong path: staging the sevens mid-lesson is not offered', () {
      final session = PracticeSession(script: CoreTurnPracticePack.baitDiscard());
      runPracticeIntro(session);
      session.submit(ClassicHareegActionIds.drawStock);

      // Even engine-legal staging (21 below the benchmark) is off-script:
      // the lesson teaches the discard, and the sevens are short anyway.
      final result = session.submit(practiceMeldId(sevens));

      expect(result.status, PracticeSubmitStatus.notAllowed);
      expect(session.controller.tableMeldsFor(PlayerSeat.south), isEmpty);
    });
  });

  group('opening-51 lesson', () {
    final kings = [
      practiceCard(CardRank.king, CardSuit.spades),
      practiceCard(CardRank.king, CardSuit.diamonds),
      practiceCard(CardRank.king, CardSuit.hearts),
    ];
    final jacks = [
      practiceCard(CardRank.jack, CardSuit.clubs),
      practiceCard(CardRank.jack, CardSuit.diamonds),
      practiceCard(CardRank.jack, CardSuit.hearts),
    ];
    final threeClubs = practiceCard(CardRank.three, CardSuit.clubs);

    test('draw, stage 30, reach 60, discard', () {
      final session = PracticeSession(script: CoreTurnPracticePack.openingTo51());

      expect(session.controller.handFor(PlayerSeat.south), hasLength(14));
      final draw = session.submit(ClassicHareegActionIds.drawStock);
      expect(draw.status, PracticeSubmitStatus.stepCompleted);

      final first = session.submit(practiceMeldId(kings));
      expect(first.status, PracticeSubmitStatus.stepCompleted);
      expect(
        session.controller.openingState.hasOpened(PlayerSeat.south),
        isFalse,
        reason: '30 staged is below the 51 requirement',
      );

      final second = session.submit(practiceMeldId(jacks));
      expect(second.status, PracticeSubmitStatus.stepCompleted);
      expect(
        session.controller.openingState.hasOpened(PlayerSeat.south),
        isTrue,
        reason: '60 total satisfies the benchmark',
      );

      final done = session.submit(practiceDiscardId(threeClubs));
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });

    // Setup moves in wrong-path tests assert their status: a silently
    // regressed setup would otherwise let the notAllowed checks pass for
    // the wrong reason.
    void advance(PracticeSession session, String actionId) {
      expect(
        session.submit(actionId).status,
        PracticeSubmitStatus.stepCompleted,
        reason: 'setup action $actionId must complete before the wrong path',
      );
    }

    test('wrong path: discarding below the benchmark is not offered', () {
      final session = PracticeSession(script: CoreTurnPracticePack.openingTo51());
      advance(session, ClassicHareegActionIds.drawStock);
      advance(session, practiceMeldId(kings));

      final result = session.submit(practiceDiscardId(threeClubs));

      expect(result.status, PracticeSubmitStatus.notAllowed);
      expect(
        session.controller.openingState.hasOpened(PlayerSeat.south),
        isFalse,
      );
    });

    test('wrong path: each staging step offers exactly its own meld', () {
      final session = PracticeSession(script: CoreTurnPracticePack.openingTo51());
      advance(session, ClassicHareegActionIds.drawStock);

      // Jacks first would complete a step whose copy and rings describe the
      // kings — the step gate keeps the order the lesson narrates.
      final jacksFirst = session.submit(practiceMeldId(jacks));
      expect(jacksFirst.status, PracticeSubmitStatus.notAllowed);
      expect(session.controller.tableMeldsFor(PlayerSeat.south), isEmpty);

      advance(session, practiceMeldId(kings));

      // A selection that is not exactly the jacks stays off the surface.
      final mixed = session.submit(
        practiceMeldId([jacks[0], jacks[1], threeClubs]),
      );
      expect(mixed.status, PracticeSubmitStatus.notAllowed);
      expect(
        session.controller.openingState.hasOpened(PlayerSeat.south),
        isFalse,
      );
    });
  });

  group('lesson scripts registry', () {
    test('the core turn pack is fully scripted', () {
      for (final id in [
        'turn-rhythm',
        'first-meld',
        'discard-opening',
        'bait-discard',
        'opening-51',
      ]) {
        expect(
          PracticeLessonRegistry.scriptFor(id),
          isNotNull,
          reason: '$id must be playable',
        );
      }
    });

    test('every planned lesson is playable: scripted, or a reading panel', () {
      for (final lesson in PracticeCatalog.lessons) {
        if (lesson.delivery.isReadingPanel) {
          // A reading panel with its own route, not a scripted hand.
          expect(PracticeLessonRegistry.scriptFor(lesson.id), isNull);
          continue;
        }
        expect(
          PracticeLessonRegistry.scriptFor(lesson.id),
          isNotNull,
          reason: '${lesson.id} must be playable',
        );
      }
    });

    test('every script replays an identical deterministic board', () {
      for (final id in [
        'first-meld',
        'discard-opening',
        'bait-discard',
        'opening-51',
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
  });
}
