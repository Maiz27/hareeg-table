import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_action_candidates.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_scripts.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_session.dart';

HareegCard _card(CardRank rank, CardSuit suit, {int deckIndex = 0}) =>
    HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);

String _discardId(HareegCard card) =>
    '${ClassicHareegActionIds.discardPrefix}${card.id}';

String _meldId(List<HareegCard> cards) =>
    ClassicHareegActionIds.playMeldActionId(cards.map((c) => c.id));

void main() {
  group('benchmark-pressure lesson', () {
    final kings = [
      _card(CardRank.king, CardSuit.spades),
      _card(CardRank.king, CardSuit.diamonds),
      _card(CardRank.king, CardSuit.hearts),
    ];
    final sevens = [
      _card(CardRank.seven, CardSuit.clubs),
      _card(CardRank.seven, CardSuit.diamonds),
      _card(CardRank.seven, CardSuit.hearts),
    ];
    final queens = [
      _card(CardRank.queen, CardSuit.spades),
      _card(CardRank.queen, CardSuit.diamonds),
      _card(CardRank.queen, CardSuit.hearts),
    ];

    test('51 staged is not enough against the raised benchmark', () {
      final session = PracticeSession(
        script: PracticeScripts.benchmarkPressure(),
      );

      expect(
        session.controller.openingState.currentRequirement,
        75,
        reason: 'east already raised the live requirement',
      );

      expect(
        session.submit(_meldId(kings)).status,
        PracticeSubmitStatus.stepCompleted,
      );
      expect(
        session.submit(_meldId(sevens)).status,
        PracticeSubmitStatus.stepCompleted,
      );
      expect(
        session.controller.openingState.hasOpened(PlayerSeat.south),
        isFalse,
        reason: '51 staged stays below the raised 75 benchmark',
      );

      expect(
        session.submit(_meldId(queens)).status,
        PracticeSubmitStatus.stepCompleted,
      );
      expect(
        session.controller.openingState.hasOpened(PlayerSeat.south),
        isTrue,
        reason: '81 crosses the raised benchmark',
      );

      final done = session.submit(
        _discardId(_card(CardRank.three, CardSuit.clubs)),
      );
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });

    test('wrong path: discarding below the raised benchmark is not offered', () {
      final session = PracticeSession(
        script: PracticeScripts.benchmarkPressure(),
      );
      session.submit(_meldId(kings));
      session.submit(_meldId(sevens));

      final result = session.submit(
        _discardId(_card(CardRank.three, CardSuit.clubs)),
      );

      expect(result.status, PracticeSubmitStatus.notAllowed);
    });
  });

  group('sequence-cover lesson', () {
    test('the direct neighbor extends the run through the real cover rules', () {
      final session = PracticeSession(script: PracticeScripts.sequenceCover());
      final eight = _card(CardRank.eight, CardSuit.diamonds);

      final coverActions = session.allowedActions;
      expect(coverActions, isNotEmpty);
      expect(
        coverActions.every(
          (a) => a.kind == ClassicHareegActionKind.placeCover,
        ),
        isTrue,
      );

      // The selection-matching surface offers the cover for the 8♦ alone.
      final candidates = practiceActionCandidates(
        allowed: coverActions,
        selectedCardIds: {eight.id},
      );
      expect(candidates, hasLength(1));

      final cover = session.submit(candidates.single.actionId);
      expect(cover.status, PracticeSubmitStatus.stepCompleted);
      expect(
        session.controller
            .tableMeldsFor(PlayerSeat.east)
            .single
            .cards
            .map((c) => c.id),
        contains(eight.id),
      );

      final done = session.submit(
        _discardId(_card(CardRank.three, CardSuit.clubs)),
      );
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });

    test('wrong path: a non-neighbor card matches no cover action', () {
      final session = PracticeSession(script: PracticeScripts.sequenceCover());
      final jack = _card(CardRank.jack, CardSuit.spades);

      final candidates = practiceActionCandidates(
        allowed: session.allowedActions,
        selectedCardIds: {jack.id},
      );

      expect(candidates, isEmpty, reason: 'J♠ does not touch the 5-6-7♦ run');
    });
  });

  group('set-cover lesson', () {
    test('the missing suit extends the set', () {
      final session = PracticeSession(script: PracticeScripts.setCover());
      final kingSpades = _card(CardRank.king, CardSuit.spades);

      final candidates = practiceActionCandidates(
        allowed: session.allowedActions,
        selectedCardIds: {kingSpades.id},
      );
      expect(candidates, hasLength(1));

      final cover = session.submit(candidates.single.actionId);
      expect(cover.status, PracticeSubmitStatus.stepCompleted);
      expect(
        session.controller.tableMeldsFor(PlayerSeat.east).single.cards,
        hasLength(4),
      );

      final done = session.submit(
        _discardId(_card(CardRank.four, CardSuit.diamonds)),
      );
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });

    test('wrong path: a filler card matches no cover action', () {
      final session = PracticeSession(script: PracticeScripts.setCover());
      final nine = _card(CardRank.nine, CardSuit.clubs);

      final candidates = practiceActionCandidates(
        allowed: session.allowedActions,
        selectedCardIds: {nine.id},
      );

      expect(candidates, isEmpty);
    });
  });

  group('cover-discard-block lesson', () {
    test('the cover card has no legal discard; the safe card completes', () {
      final session = PracticeSession(
        script: PracticeScripts.coverDiscardBlock(),
      );
      final eight = _card(CardRank.eight, CardSuit.diamonds);
      final two = _card(CardRank.two, CardSuit.clubs);

      // The engine never advertises a plain discard for the cover card under
      // the Coaching tier — that absence is the lesson.
      final discardActions = session.allowedActions;
      expect(
        discardActions.map((a) => a.cardId),
        isNot(contains(eight.id)),
        reason: 'the 8♦ extends the table run, so its discard is blocked',
      );
      expect(discardActions.map((a) => a.cardId), contains(two.id));

      final done = session.submit(_discardId(two));
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });

    test('wrong path: forcing the blocked discard is rejected by the rules', () {
      final session = PracticeSession(
        script: PracticeScripts.coverDiscardBlock(),
      );
      final eight = _card(CardRank.eight, CardSuit.diamonds);

      final result = session.submit(_discardId(eight));

      expect(result.status, PracticeSubmitStatus.rejected);
      expect(result.message, isNotEmpty);
    });
  });

  group('joker-identity lesson', () {
    test('each legal declaration is offered and either completes the step', () {
      final session = PracticeSession(script: PracticeScripts.jokerIdentity());
      final sevenClubs = _card(CardRank.seven, CardSuit.clubs);
      final sevenHearts = _card(CardRank.seven, CardSuit.hearts);
      final joker = HareegCard.joker(deckIndex: 0, jokerIndex: 0);

      final candidates = practiceActionCandidates(
        allowed: session.allowedActions,
        selectedCardIds: {sevenClubs.id, sevenHearts.id, joker.id},
      );
      final identities = [
        for (final c in candidates) c.action.jokerMeldChoice!.identity.key,
      ];
      expect(
        identities.toSet(),
        {'seven-diamonds', 'seven-spades'},
        reason: 'both missing suits are legal declarations',
      );

      final declared = session.submit(candidates.first.actionId);
      expect(declared.status, PracticeSubmitStatus.stepCompleted);
      final placedJoker = session.controller
          .tableMeldsFor(PlayerSeat.south)
          .single
          .cards
          .firstWhere((c) => c.isJoker);
      expect(placedJoker.effectiveIdentity, isNotNull);

      final done = session.submit(
        _discardId(_card(CardRank.four, CardSuit.spades)),
      );
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });

    test('wrong path: an undeclared joker meld is not the taught action', () {
      final session = PracticeSession(script: PracticeScripts.jokerIdentity());
      final sevenClubs = _card(CardRank.seven, CardSuit.clubs);
      final sevenHearts = _card(CardRank.seven, CardSuit.hearts);
      final joker = HareegCard.joker(deckIndex: 0, jokerIndex: 0);

      // A plain play-meld id without a declaration is outside the step.
      final result = session.submit(
        _meldId([sevenClubs, sevenHearts, joker]),
      );

      expect(result.status, PracticeSubmitStatus.notAllowed);
    });
  });

  group('joker-replacement lesson', () {
    test('the real represented card reclaims the joker', () {
      final session = PracticeSession(
        script: PracticeScripts.jokerReplacement(),
      );
      final sevenDiamonds = _card(CardRank.seven, CardSuit.diamonds);

      final candidates = practiceActionCandidates(
        allowed: session.allowedActions,
        selectedCardIds: {sevenDiamonds.id},
      );
      expect(candidates, hasLength(1));
      expect(
        candidates.single.action.kind,
        ClassicHareegActionKind.replaceJoker,
      );

      final replaced = session.submit(candidates.single.actionId);
      expect(replaced.status, PracticeSubmitStatus.stepCompleted);
      expect(
        session.controller.handFor(PlayerSeat.south).any((c) => c.isJoker),
        isTrue,
        reason: 'the freed joker joins the hand',
      );
      expect(
        session.controller
            .tableMeldsFor(PlayerSeat.east)
            .single
            .cards
            .any((c) => c.isJoker),
        isFalse,
        reason: 'the real 7♦ replaced the table joker',
      );

      final done = session.submit(
        _discardId(_card(CardRank.king, CardSuit.clubs)),
      );
      expect(done.status, PracticeSubmitStatus.lessonCompleted);
    });

    test('wrong path: the freed joker still cannot be discarded normally', () {
      final session = PracticeSession(
        script: PracticeScripts.jokerReplacement(),
      );
      final sevenDiamonds = _card(CardRank.seven, CardSuit.diamonds);
      final candidates = practiceActionCandidates(
        allowed: session.allowedActions,
        selectedCardIds: {sevenDiamonds.id},
      );
      session.submit(candidates.single.actionId);

      final joker = session.controller
          .handFor(PlayerSeat.south)
          .firstWhere((c) => c.isJoker);
      final result = session.submit(_discardId(joker));

      expect(result.status, PracticeSubmitStatus.rejected);
      expect(result.message, isNotEmpty);
    });
  });

  group('lesson scripts registry', () {
    test('the table mechanics pack is fully scripted and deterministic', () {
      for (final id in [
        'benchmark-pressure',
        'sequence-cover',
        'set-cover',
        'cover-discard-block',
        'joker-identity',
        'joker-replacement',
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
