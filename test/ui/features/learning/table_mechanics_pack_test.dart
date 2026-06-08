import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/features/learning/models/practice_lesson_registry.dart';
import 'package:hareeg_table/ui/features/learning/practice/table_mechanics_practice_pack.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_session.dart';

import '../../../support/practice_lesson_harness.dart';

void main() {
  group('pending-discard lesson', () {
    final fourHearts = practiceCard(CardRank.four, CardSuit.hearts);
    final fourDiamonds = practiceCard(CardRank.four, CardSuit.diamonds);
    final fourClubs = practiceCard(CardRank.four, CardSuit.clubs);
    final fours = [fourHearts, fourDiamonds, fourClubs];
    final twos = [
      practiceCard(CardRank.two, CardSuit.spades),
      practiceCard(CardRank.two, CardSuit.diamonds),
      practiceCard(CardRank.two, CardSuit.clubs),
    ];
    final aceClubs = practiceCard(CardRank.ace, CardSuit.clubs);

    test('the player starts visibly opened at exactly 51, and the intro '
        'plays west throwing the four onto an empty pile', () {
      final session = PracticeSession(script: TableMechanicsPracticePack.pendingDiscard());

      expect(
        session.controller.openingState.hasOpened(PlayerSeat.south),
        isTrue,
        reason: 'post-opening freedom is the lesson premise',
      );
      expect(
        practiceTableValueFor(session, PlayerSeat.south),
        51,
        reason: 'a visible opening must total the requirement it implies',
      );
      expect(session.controller.discardPile, isEmpty);

      runPracticeIntro(session);

      expect(session.controller.topDiscard?.id, fourClubs.id);
    });

    test('take, hand it back, draw on, meld the free six, discard', () {
      final session = PracticeSession(script: TableMechanicsPracticePack.pendingDiscard());
      runPracticeIntro(session);

      final take = session.submit(ClassicHareegActionIds.takeDiscard);
      expect(take.status, PracticeSubmitStatus.stepCompleted);
      expect(session.controller.pendingDiscard?.id, fourClubs.id);

      // The taught return is a step move, not a correction: pending-discard
      // returns are how the rules work, not a practice-only take-back.
      final handBack = session.submit(
        ClassicHareegActionIds.returnPendingDiscard,
      );
      expect(handBack.status, PracticeSubmitStatus.stepCompleted);
      expect(session.controller.pendingDiscard, isNull);
      expect(
        session.controller.topDiscard?.id,
        fourClubs.id,
        reason: 'the returned four lands back on top of the pile',
      );

      // The real anti-stall rule the copy leans on: a returned card cannot
      // be re-taken this turn.
      expect(
        session.controller.legalActionIdsFor(PlayerSeat.south),
        isNot(contains(ClassicHareegActionIds.takeDiscard)),
      );

      final draw = session.submit(ClassicHareegActionIds.drawStock);
      expect(draw.status, PracticeSubmitStatus.stepCompleted);

      final meld = session.submit(practiceMeldId(twos));
      expect(meld.status, PracticeSubmitStatus.stepCompleted);
      expect(
        practiceTableValueFor(session, PlayerSeat.south),
        57,
        reason: '51 from the prior opening plus the free six-point twos',
      );

      final done = session.submit(practiceDiscardId(aceClubs));
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });

    test('wrong path: melding while the lesson teaches the return stays '
        'dark, and taking instead of drawing is not even legal', () {
      final session = PracticeSession(script: TableMechanicsPracticePack.pendingDiscard());
      runPracticeIntro(session);
      session.submit(ClassicHareegActionIds.takeDiscard);

      // Step 2 teaches the escape hatch; melding the fours is engine-legal
      // (the pending four leads the play) but off-script here.
      final earlyMeld = session.submit(practiceMeldId(fours));
      expect(earlyMeld.status, PracticeSubmitStatus.notAllowed);
      expect(session.stepIndex, 1);

      session.submit(ClassicHareegActionIds.returnPendingDiscard);

      // Step 3 falls back to the draw; re-taking the returned four is
      // blocked by the engine itself, so the step never offers it.
      final retake = session.submit(ClassicHareegActionIds.takeDiscard);
      expect(retake.status, PracticeSubmitStatus.notAllowed);
      expect(session.stepIndex, 2);
    });
  });

  group('benchmark-pressure lesson', () {
    final heartRun = [
      practiceCard(CardRank.seven, CardSuit.hearts),
      practiceCard(CardRank.eight, CardSuit.hearts),
      practiceCard(CardRank.nine, CardSuit.hearts),
      practiceCard(CardRank.ten, CardSuit.hearts),
      practiceCard(CardRank.jack, CardSuit.hearts),
      practiceCard(CardRank.queen, CardSuit.hearts),
    ];
    final queenSpades = practiceCard(CardRank.queen, CardSuit.spades);

    test('the intro opens west at 75 through the real engine, raising the '
        'live benchmark', () {
      final session = PracticeSession(
        script: TableMechanicsPracticePack.benchmarkPressure(),
      );

      expect(
        session.controller.openingState.currentRequirement,
        51,
        reason: 'the raise must happen on screen, not pre-baked',
      );

      runPracticeIntro(session);

      expect(
        session.controller.openingState.hasOpened(PlayerSeat.west),
        isTrue,
      );
      expect(practiceTableValueFor(session, PlayerSeat.west), 75);
      expect(
        session.controller.openingState.currentRequirement,
        75,
        reason: 'opening above the base raises the bar for everyone else',
      );
    });

    test('draw, stage the legal-but-short run, retract it as the taught '
        'move, discard', () {
      final session = PracticeSession(
        script: TableMechanicsPracticePack.benchmarkPressure(),
      );
      runPracticeIntro(session);

      final draw = session.submit(ClassicHareegActionIds.drawStock);
      expect(draw.status, PracticeSubmitStatus.stepCompleted);

      final stage = session.submit(practiceMeldId(heartRun));
      expect(
        stage.status,
        PracticeSubmitStatus.stepCompleted,
        reason: 'staging is the taught move; the react is the next step',
      );
      expect(session.controller.tableMeldsFor(PlayerSeat.south), hasLength(1));
      expect(
        session.controller.openingState.hasOpened(PlayerSeat.south),
        isFalse,
        reason: '54 stays under the raised 75 bar',
      );

      // The retract: normally a correction, here the step's own taught
      // move — it must advance the lesson, not hold it.
      expect(
        session.offersActionId(ClassicHareegActionIds.returnOpeningMelds),
        isTrue,
      );
      final retract = session.submit(ClassicHareegActionIds.returnOpeningMelds);
      expect(retract.status, PracticeSubmitStatus.stepCompleted);
      expect(session.controller.tableMeldsFor(PlayerSeat.south), isEmpty);

      final done = session.submit(practiceDiscardId(queenSpades));
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
      expect(
        session.controller.openingState.hasOpened(PlayerSeat.south),
        isFalse,
        reason: 'the lesson ends with the player still unopened, by design',
      );
    });

    test('wrong path: a partial slice of the run stays off the surface', () {
      final session = PracticeSession(
        script: TableMechanicsPracticePack.benchmarkPressure(),
      );
      runPracticeIntro(session);
      session.submit(ClassicHareegActionIds.drawStock);

      final partial = session.submit(practiceMeldId(heartRun.sublist(0, 3)));
      expect(partial.status, PracticeSubmitStatus.notAllowed);
      expect(session.controller.tableMeldsFor(PlayerSeat.south), isEmpty);
    });

    test('retracting by tapping the staged run itself also advances — a '
        'playtest stranded here when only the undo pill counted', () {
      final session = PracticeSession(
        script: TableMechanicsPracticePack.benchmarkPressure(),
      );
      runPracticeIntro(session);
      session.submit(ClassicHareegActionIds.drawStock);
      session.submit(practiceMeldId(heartRun));

      // The per-meld take-back gesture submits a return-table-play id, not
      // return-opening-melds; the step must accept both or the lesson
      // strands with nothing staged and nothing allowed.
      final retract = session.submit(
        ClassicHareegActionIds.returnTablePlayActionId(
          owner: PlayerSeat.south,
          meldIndex: 0,
        ),
      );
      expect(retract.status, PracticeSubmitStatus.stepCompleted);
      expect(session.controller.tableMeldsFor(PlayerSeat.south), isEmpty);

      final done = session.submit(practiceDiscardId(queenSpades));
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });
  });

  group('sequence-cover lesson (stacked covers)', () {
    final jackDiamonds = practiceCard(CardRank.jack, CardSuit.diamonds);
    final queenDiamonds = practiceCard(CardRank.queen, CardSuit.diamonds);
    final eightDiamonds = practiceCard(
      CardRank.eight,
      CardSuit.diamonds,
      deckIndex: 1,
    );
    final aceClubs = practiceCard(CardRank.ace, CardSuit.clubs);

    String coverId(int meldIndex, List<HareegCard> cards) {
      return ClassicHareegActionIds.placeCoverActionId(
        targetSeat: PlayerSeat.west,
        meldIndex: meldIndex,
        cardIds: [for (final card in cards) card.id],
      );
    }

    test('west opens at exactly 51 on screen; the player stacks two covers '
        'on the run one at a time, fills the set, and discards', () {
      final session = PracticeSession(script: TableMechanicsPracticePack.sequenceCover());

      expect(session.controller.tableMeldsFor(PlayerSeat.west), isEmpty);
      runPracticeIntro(session);
      expect(practiceTableValueFor(session, PlayerSeat.west), 51);
      expect(
        practiceTableValueFor(session, PlayerSeat.south),
        51,
        reason: 'the player\'s prior opening keeps the chrome honest',
      );

      final draw = session.submit(ClassicHareegActionIds.drawStock);
      expect(draw.status, PracticeSubmitStatus.stepCompleted);

      // West staged the eights first, so the diamond run is meld index 1.
      // The jack alone applies but leaves the step holding for the queen.
      final jack = session.submit(coverId(1, [jackDiamonds]));
      expect(
        jack.status,
        PracticeSubmitStatus.accepted,
        reason: 'the step holds until both stacked covers land',
      );
      final queen = session.submit(coverId(1, [queenDiamonds]));
      expect(queen.status, PracticeSubmitStatus.stepCompleted);
      final run = session.controller.tableMeldsFor(PlayerSeat.west)[1];
      expect(run.cards, hasLength(5));
      expect(run.totalValue, 47, reason: '8+9+10 plus jack and queen');

      // Second target, same turn: the duplicate-deck eight fills the set.
      final eight = session.submit(coverId(0, [eightDiamonds]));
      expect(eight.status, PracticeSubmitStatus.stepCompleted);
      final eights = session.controller.tableMeldsFor(PlayerSeat.west)[0];
      expect(eights.cards, hasLength(4));

      final done = session.submit(practiceDiscardId(aceClubs));
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });

    test('both run covers land in a single drop too', () {
      final session = PracticeSession(script: TableMechanicsPracticePack.sequenceCover());
      runPracticeIntro(session);
      session.submit(ClassicHareegActionIds.drawStock);

      final both = session.submit(coverId(1, [jackDiamonds, queenDiamonds]));
      expect(both.status, PracticeSubmitStatus.stepCompleted);
      expect(
        session.controller.tableMeldsFor(PlayerSeat.west)[1].cards,
        hasLength(5),
      );
    });

    test('wrong path: the set-fill eight stays dark during the run step, '
        'and discarding stays dark until both steps finish', () {
      final session = PracticeSession(script: TableMechanicsPracticePack.sequenceCover());
      runPracticeIntro(session);
      session.submit(ClassicHareegActionIds.drawStock);

      // Engine-legal right now, but the step teaches the run first.
      final early = session.submit(coverId(0, [eightDiamonds]));
      expect(early.status, PracticeSubmitStatus.notAllowed);

      final discard = session.submit(practiceDiscardId(aceClubs));
      expect(discard.status, PracticeSubmitStatus.notAllowed);
      expect(session.stepIndex, 1);
    });
  });

  group('set-cover lesson', () {
    final kingClubs = practiceCard(CardRank.king, CardSuit.clubs);
    final aceHearts = practiceCard(CardRank.ace, CardSuit.hearts);

    test('the club king fills west\'s kings to all four suits', () {
      final session = PracticeSession(script: TableMechanicsPracticePack.setCover());
      runPracticeIntro(session);
      expect(practiceTableValueFor(session, PlayerSeat.west), 51);
      expect(practiceTableValueFor(session, PlayerSeat.south), 51);

      session.submit(ClassicHareegActionIds.drawStock);

      // West staged the club run first, so the kings are meld index 1.
      final cover = session.submit(
        ClassicHareegActionIds.placeCoverActionId(
          targetSeat: PlayerSeat.west,
          meldIndex: 1,
          cardIds: [kingClubs.id],
        ),
      );
      expect(cover.status, PracticeSubmitStatus.stepCompleted);
      final kings = session.controller.tableMeldsFor(PlayerSeat.west)[1];
      expect(kings.cards, hasLength(4));
      expect(
        {for (final card in kings.cards) card.effectiveIdentity?.suit},
        CardSuit.values.toSet(),
        reason: 'a covered set holds all four suits',
      );

      final done = session.submit(practiceDiscardId(aceHearts));
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });
  });

  group('cover-discard-block lesson', () {
    final tenHearts = practiceCard(CardRank.ten, CardSuit.hearts);
    final aceSpades = practiceCard(CardRank.ace, CardSuit.spades);

    test('the trapped ten can be neither discarded nor placed; any other '
        'card ends the turn', () {
      final session = PracticeSession(
        script: TableMechanicsPracticePack.coverDiscardBlock(),
      );
      runPracticeIntro(session);
      expect(practiceTableValueFor(session, PlayerSeat.west), 51);
      expect(
        session.controller.openingState.hasOpened(PlayerSeat.south),
        isFalse,
        reason: 'unopened is the point: the cover is stuck in hand',
      );

      session.submit(ClassicHareegActionIds.drawStock);

      // The real rules surface refuses the ten outright: no discard id for
      // it is even enumerated, while other discards are.
      final legal = session.controller.legalActionIdsFor(PlayerSeat.south);
      expect(legal, isNot(contains(practiceDiscardId(tenHearts))));
      expect(legal, contains(practiceDiscardId(aceSpades)));
      // And an unopened player gets no cover offer for it either.
      expect(
        legal.where(
          (id) => id.startsWith(ClassicHareegActionIds.placeCoverPrefix),
        ),
        isEmpty,
      );

      // Forcing the blocked discard anyway hits the engine's refusal.
      final blocked = session.submit(practiceDiscardId(tenHearts));
      expect(blocked.status, PracticeSubmitStatus.rejected);
      expect(blocked.message, isNotEmpty);
      expect(session.isComplete, isFalse);

      final done = session.submit(practiceDiscardId(aceSpades));
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });
  });

  group('joker-identity lesson', () {
    final sevenClubs = practiceCard(CardRank.seven, CardSuit.clubs);
    final sevenHearts = practiceCard(CardRank.seven, CardSuit.hearts);

    String identityMeldId(CardSuit suit) {
      return ClassicHareegActionIds.playMeldWithJokerIdentityActionId(
        cardIds: [sevenClubs.id, sevenHearts.id, practiceJoker().id],
        jokerId: practiceJoker().id,
        identity: CardIdentity(rank: CardRank.seven, suit: suit),
      );
    }

    test('both identity declarations are offered; either completes the '
        'step', () {
      final session = PracticeSession(script: TableMechanicsPracticePack.jokerIdentity());
      expect(practiceTableValueFor(session, PlayerSeat.south), 51);

      session.submit(ClassicHareegActionIds.drawStock);

      // The picker's two real choices both pass the step gate — the open
      // choice IS the lesson.
      expect(session.offersActionId(identityMeldId(CardSuit.diamonds)), isTrue);
      expect(session.offersActionId(identityMeldId(CardSuit.spades)), isTrue);

      final declared = session.submit(identityMeldId(CardSuit.diamonds));
      expect(declared.status, PracticeSubmitStatus.stepCompleted);
      final placed = session.controller.tableMeldsFor(PlayerSeat.south).last;
      final placedJoker = placed.cards.firstWhere((card) => card.isJoker);
      expect(
        placedJoker.representedIdentity,
        const CardIdentity(rank: CardRank.seven, suit: CardSuit.diamonds),
      );

      final done = session.submit(
        practiceDiscardId(practiceCard(CardRank.ace, CardSuit.spades)),
      );
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });

    test('wrong path: the joker gluing a different pair stays dark', () {
      final session = PracticeSession(script: TableMechanicsPracticePack.jokerIdentity());
      session.submit(ClassicHareegActionIds.drawStock);

      // The hand's twos plus the joker make a real set, but the step gate
      // pins the exact taught cards — a kind-only gate would light this.
      final offScript = session.submit(
        ClassicHareegActionIds.playMeldWithJokerIdentityActionId(
          cardIds: [
            practiceCard(CardRank.two, CardSuit.spades).id,
            practiceCard(CardRank.two, CardSuit.hearts).id,
            practiceJoker().id,
          ],
          jokerId: practiceJoker().id,
          identity: const CardIdentity(
            rank: CardRank.two,
            suit: CardSuit.clubs,
          ),
        ),
      );
      expect(offScript.status, PracticeSubmitStatus.notAllowed);
      expect(session.controller.tableMeldsFor(PlayerSeat.south), hasLength(2));
    });
  });

  group('joker-replacement lesson', () {
    final sevenDiamonds = practiceCard(CardRank.seven, CardSuit.diamonds);
    final eightHearts = practiceCard(CardRank.eight, CardSuit.hearts);
    final tenHearts = practiceCard(CardRank.ten, CardSuit.hearts);
    final kingHearts = practiceCard(CardRank.king, CardSuit.hearts);

    String bridgeMeldId() {
      return ClassicHareegActionIds.playMeldWithJokerIdentityActionId(
        cardIds: [eightHearts.id, tenHearts.id, practiceJoker().id],
        jokerId: practiceJoker().id,
        identity: const CardIdentity(
          rank: CardRank.nine,
          suit: CardSuit.hearts,
        ),
      );
    }

    PracticeSession swappedSession() {
      final session = PracticeSession(
        script: TableMechanicsPracticePack.jokerReplacement(),
      );
      runPracticeIntro(session);
      session.submit(ClassicHareegActionIds.drawStock);
      final swap = session.submit(
        ClassicHareegActionIds.replaceJokerActionId(
          targetSeat: PlayerSeat.west,
          meldIndex: 0,
          cardId: sevenDiamonds.id,
        ),
      );
      expect(swap.status, PracticeSubmitStatus.stepCompleted);
      return session;
    }

    test('the intro melds west\'s joker as the diamond seven on screen', () {
      final session = PracticeSession(
        script: TableMechanicsPracticePack.jokerReplacement(),
      );
      expect(session.controller.tableMeldsFor(PlayerSeat.west), isEmpty);

      runPracticeIntro(session);

      expect(practiceTableValueFor(session, PlayerSeat.west), 51);
      final sevens = session.controller.tableMeldsFor(PlayerSeat.west).first;
      final placedJoker = sevens.cards.firstWhere((card) => card.isJoker);
      expect(
        placedJoker.representedIdentity,
        const CardIdentity(rank: CardRank.seven, suit: CardSuit.diamonds),
      );
    });

    test('swap the real seven in, then bank the joker and close', () {
      final session = swappedSession();
      final sevens = session.controller.tableMeldsFor(PlayerSeat.west).first;
      expect(
        sevens.cards.any((card) => card.isJoker),
        isFalse,
        reason: 'the real seven replaced the joker in the table set',
      );
      expect(
        session.controller
            .handFor(PlayerSeat.south)
            .any((card) => card.isJoker),
        isTrue,
        reason: 'the freed joker joined the player\'s hand',
      );

      // The freed joker is blocked as a discard — the step's closing rule.
      final jokerThrow = session.submit(practiceDiscardId(practiceJoker()));
      expect(jokerThrow.status, PracticeSubmitStatus.rejected);
      expect(jokerThrow.message, isNotEmpty);

      final done = session.submit(practiceDiscardId(kingHearts));
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });

    test('or bridge the 8-10 of hearts with the joker as a nine, then '
        'close', () {
      final session = swappedSession();

      // The use branch: a free post-opening meld through the picker's only
      // identity. It applies but holds the step — the turn still ends with
      // a discard.
      final bridge = session.submit(bridgeMeldId());
      expect(bridge.status, PracticeSubmitStatus.accepted);
      final placed = session.controller.tableMeldsFor(PlayerSeat.south).last;
      final placedJoker = placed.cards.firstWhere((card) => card.isJoker);
      expect(
        placedJoker.representedIdentity,
        const CardIdentity(rank: CardRank.nine, suit: CardSuit.hearts),
      );

      final done = session.submit(practiceDiscardId(kingHearts));
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });
  });

  group('lesson scripts registry', () {
    test('the table mechanics pack is fully scripted', () {
      for (final id in [
        'pending-discard',
        'benchmark-pressure',
        'sequence-cover',
        'set-cover',
        'cover-discard-block',
        'joker-identity',
        'joker-replacement',
      ]) {
        expect(
          PracticeLessonRegistry.scriptFor(id),
          isNotNull,
          reason: '$id must be playable',
        );
      }
    });

    test(
      'a pre-opened player holds the dealt hand minus their table cards',
      () {
        // A playtest flagged the giveaway: six of "your" cards on the table
        // while the hand still fans the full fourteen. Hand plus placed cards
        // must always account for exactly one deal.
        for (final id in [
          'pending-discard',
          'benchmark-pressure',
          'sequence-cover',
          'set-cover',
          'cover-discard-block',
          'joker-identity',
          'joker-replacement',
        ]) {
          final snapshot = PracticeLessonRegistry.scriptFor(
            id,
          )!.buildSnapshot();
          expectPracticeBoardSnapshotAudit(
            snapshot,
            handAndTableSeats: {PlayerSeat.south},
            reason: '$id must deal a hand that accounts for its table cards',
          );
        }
      },
    );

    test('every pack-two script replays an identical deterministic board', () {
      for (final id in [
        'pending-discard',
        'benchmark-pressure',
        'sequence-cover',
        'set-cover',
        'cover-discard-block',
        'joker-identity',
        'joker-replacement',
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
