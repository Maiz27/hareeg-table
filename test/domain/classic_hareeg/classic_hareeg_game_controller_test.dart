import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_strategy.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

void main() {
  group('ClassicHareegGameController legal action enforcement', () {
    test('rejects normal joker discards under any preset', () {
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              defaults[PlayerSeat.south]!.firstWhere((c) => !c.isJoker),
              HareegCard.joker(deckIndex: 0, jokerIndex: 0),
              defaults[PlayerSeat.south]!.firstWhere(
                (c) => !c.isJoker,
                orElse: () => throw 'no card',
              ),
            ].followedBy(defaults[PlayerSeat.south]!.skip(2)).toList(),
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
        ),
      );

      final legal = controller.legalActionIdsFor(PlayerSeat.south);
      expect(
        legal,
        isNot(
          contains(
            '${ClassicHareegActionIds.discardJokerPrefix}deck-0-joker-0',
          ),
        ),
        reason: 'Normal joker discards are hard-blocked in every preset.',
      );

      final joker = controller
          .handFor(PlayerSeat.south)
          .firstWhere((card) => card.isJoker);
      final result = controller.applyAction(
        '${ClassicHareegActionIds.discardJokerPrefix}${joker.id}',
      );

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('not legal'));
      expect(controller.handFor(PlayerSeat.south), contains(joker));
    });

    test(
      'legalActionIdsFor in action phase enumerates each non-joker card',
      () {
        final controller = _freshControllerInActionPhase();

        final hand = controller.handFor(PlayerSeat.south);
        final nonJokerCount = hand.where((card) => !card.isJoker).length;

        final legal = controller.legalActionIdsFor(PlayerSeat.south);
        final discards = legal
            .where((id) => id.startsWith(ClassicHareegActionIds.discardPrefix))
            .toList();

        expect(discards, hasLength(nonJokerCount));
      },
    );

    test('cpuActionIdsFor keeps CPU action turns bounded', () {
      final largeHand = [
        for (final suit in [CardSuit.hearts, CardSuit.diamonds])
          for (final rank in [
            CardRank.three,
            CardRank.four,
            CardRank.five,
            CardRank.six,
            CardRank.seven,
            CardRank.eight,
            CardRank.nine,
            CardRank.ten,
          ])
            _card(rank, suit, suit.index + 60),
        _card(CardRank.two, CardSuit.clubs, 60),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.north: largeHand,
          },
          currentSeat: PlayerSeat.north,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.north),
        ),
      );

      final cpuActions = controller.cpuActionIdsFor(PlayerSeat.north);
      final meldActions = cpuActions.where(
        (id) => id.startsWith(ClassicHareegActionIds.playMeldPrefix),
      );

      expect(cpuActions, isNotEmpty);
      expect(meldActions, hasLength(1));
      expect(
        cpuActions.where(
          (id) => ClassicHareegActionIds.discardCardId(id) != null,
        ),
        isNotEmpty,
      );
      expect(cpuActions.length, lessThanOrEqualTo(largeHand.length + 3));
    });

    test('CPU draw-phase Fifty proof stays bounded for dense hands', () {
      final now = DateTime.utc(2026, 5, 21, 12);
      final discarded = _card(CardRank.six, CardSuit.spades, 180);
      final denseHand = [
        _card(CardRank.six, CardSuit.clubs, 180),
        _card(CardRank.six, CardSuit.diamonds, 180),
        _card(CardRank.five, CardSuit.hearts, 181),
        _card(CardRank.seven, CardSuit.hearts, 181),
        _card(CardRank.queen, CardSuit.spades, 181),
        _card(CardRank.six, CardSuit.hearts, 181),
        _card(CardRank.eight, CardSuit.clubs, 180),
        _card(CardRank.six, CardSuit.hearts, 180),
        _card(CardRank.jack, CardSuit.diamonds, 181),
        _card(CardRank.six, CardSuit.spades, 181),
        _card(CardRank.three, CardSuit.clubs, 181),
        _card(CardRank.four, CardSuit.hearts, 180),
        _card(CardRank.king, CardSuit.spades, 181),
        _card(CardRank.two, CardSuit.diamonds, 180),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {...defaults, PlayerSeat.west: denseHand},
          discardPile: [discarded],
          stock: [_card(CardRank.king, CardSuit.clubs, 180)],
          currentSeat: PlayerSeat.west,
          turnPhase: TurnPhase.draw,
          savedAt: now,
          fiftyWindowOpenedAt: now,
        ),
        now: () => now,
      );

      final watch = Stopwatch()..start();
      final cpuActions = controller.cpuActionIdsFor(PlayerSeat.west);
      watch.stop();

      expect(cpuActions, contains(ClassicHareegActionIds.drawStock));
      expect(cpuActions, contains(ClassicHareegActionIds.takeDiscard));
      expect(cpuActions, isNot(contains(ClassicHareegActionIds.claimFifty)));
      expect(watch.elapsedMilliseconds, lessThan(250));
    });

    test('CPU draw-phase Fifty proof rejects log-style nonfinish quickly', () {
      final now = DateTime.utc(2026, 5, 21, 12);
      final discarded = _card(CardRank.king, CardSuit.diamonds, 190);
      final logStyleHand = [
        _card(CardRank.four, CardSuit.diamonds, 190),
        _card(CardRank.four, CardSuit.hearts, 190),
        _card(CardRank.seven, CardSuit.clubs, 190),
        _card(CardRank.ten, CardSuit.diamonds, 190),
        _card(CardRank.ten, CardSuit.clubs, 190),
        _card(CardRank.seven, CardSuit.hearts, 190),
        _card(CardRank.four, CardSuit.clubs, 190),
        _card(CardRank.seven, CardSuit.spades, 190),
        const HareegCard.joker(deckIndex: 190, jokerIndex: 0),
        _card(CardRank.two, CardSuit.clubs, 190),
        _card(CardRank.five, CardSuit.diamonds, 190),
        _card(CardRank.queen, CardSuit.spades, 190),
        _card(CardRank.ace, CardSuit.hearts, 190),
        _card(CardRank.king, CardSuit.spades, 190),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.west: logStyleHand,
          },
          discardPile: [discarded],
          stock: [_card(CardRank.two, CardSuit.spades, 190)],
          currentSeat: PlayerSeat.west,
          turnPhase: TurnPhase.draw,
          savedAt: now,
          fiftyWindowOpenedAt: now,
        ),
        now: () => now,
      );

      final watch = Stopwatch()..start();
      final cpuActions = controller.cpuActionIdsFor(PlayerSeat.west);
      watch.stop();

      expect(cpuActions, contains(ClassicHareegActionIds.drawStock));
      expect(cpuActions, contains(ClassicHareegActionIds.takeDiscard));
      expect(cpuActions, isNot(contains(ClassicHareegActionIds.claimFifty)));
      expect(watch.elapsedMilliseconds, lessThan(250));
    });

    test('a successful human discard advances the seat and turn phase', () {
      final controller = _freshControllerInActionPhase();
      final hand = controller.handFor(PlayerSeat.south);
      final card = hand.firstWhere((c) => !c.isJoker);

      final result = controller.applyAction(
        '${ClassicHareegActionIds.discardPrefix}${card.id}',
      );

      expect(result.isSuccess, isTrue);
      expect(controller.currentSeat, PlayerSeat.east);
      expect(controller.turnPhase, TurnPhase.draw);
      expect(controller.topDiscard?.id, card.id);
    });

    test('applying an unrelated action id reports failure', () {
      final controller = _freshControllerInActionPhase();

      final result = controller.applyAction('nope');

      expect(result.isSuccess, isFalse);
    });

    test('only the immediate next seat may take the previous discard', () {
      final controller = _freshControllerInActionPhase();
      final hand = controller.handFor(PlayerSeat.south);
      final card = hand.firstWhere((c) => !c.isJoker);
      controller.applyAction(
        '${ClassicHareegActionIds.discardPrefix}${card.id}',
      );

      expect(
        controller.legalActionIdsFor(PlayerSeat.east),
        contains(ClassicHareegActionIds.takeDiscard),
      );
      expect(
        controller.legalActionIdsFor(PlayerSeat.north),
        isEmpty,
        reason: 'It is not yet North\'s turn.',
      );
    });

    test('pending state limits legal actions to use or return', () {
      final controller = _freshControllerInActionPhase();
      final south = controller.handFor(PlayerSeat.south);
      final discardedByHuman = south.firstWhere((c) => !c.isJoker);
      controller.applyAction(
        '${ClassicHareegActionIds.discardPrefix}${discardedByHuman.id}',
      );

      final result = controller.applyAction(ClassicHareegActionIds.takeDiscard);

      expect(result.isSuccess, isTrue);
      expect(controller.pendingDiscard?.id, discardedByHuman.id);
      expect(
        controller.legalActionIdsFor(PlayerSeat.east),
        equals([ClassicHareegActionIds.returnPendingDiscard]),
      );
    });

    test('returning a pending discard goes back to draw decision', () {
      final controller = _freshControllerInActionPhase();
      final south = controller.handFor(PlayerSeat.south);
      final discarded = south.firstWhere((c) => !c.isJoker);
      controller.applyAction(
        '${ClassicHareegActionIds.discardPrefix}${discarded.id}',
      );
      final stockBeforeTake = controller.stockCount;
      final eastHandBeforeTake = controller.cardCountFor(PlayerSeat.east);
      controller.applyAction(ClassicHareegActionIds.takeDiscard);

      controller.applyAction(ClassicHareegActionIds.returnPendingDiscard);

      expect(controller.pendingDiscard, isNull);
      expect(controller.topDiscard?.id, discarded.id);
      expect(controller.stockCount, stockBeforeTake);
      expect(controller.cardCountFor(PlayerSeat.east), eastHandBeforeTake);
      expect(controller.turnPhase, TurnPhase.draw);
      // After returning a pending discard, the seat must draw from stock —
      // re-taking the same top card would let the CPU loop forever between
      // take-discard and return-pending-discard. The guard re-arms as soon
      // as someone discards a new card on top of the pile.
      final postReturnControls = controller.controlActionIdsFor(
        PlayerSeat.east,
      );
      expect(postReturnControls, contains(ClassicHareegActionIds.drawStock));
      expect(
        postReturnControls,
        isNot(contains(ClassicHareegActionIds.takeDiscard)),
      );

      final takeAgain = controller.applyAction(
        ClassicHareegActionIds.takeDiscard,
      );

      expect(takeAgain.isSuccess, isFalse);
    });

    test(
      're-take guard clears once a fresh discard lands on top of the pile',
      () {
        final controller = _freshControllerInActionPhase();
        final south = controller.handFor(PlayerSeat.south);
        final discarded = south.firstWhere((c) => !c.isJoker);
        controller.applyAction(
          '${ClassicHareegActionIds.discardPrefix}${discarded.id}',
        );
        controller.applyAction(ClassicHareegActionIds.takeDiscard);
        controller.applyAction(ClassicHareegActionIds.returnPendingDiscard);
        // East just returned the card → still can't re-take.
        expect(
          controller.controlActionIdsFor(PlayerSeat.east),
          isNot(contains(ClassicHareegActionIds.takeDiscard)),
        );

        // East draws stock and discards a different card; the discard pile
        // now has a new top. The guard should rearm — north (the next seat)
        // can take the top because they didn't return it.
        controller.applyAction(ClassicHareegActionIds.drawStock);
        final eastHand = controller.handFor(PlayerSeat.east);
        final eastDiscardCard = eastHand.firstWhere(
          (c) => !c.isJoker && c.id != discarded.id,
        );
        controller.applyAction(
          '${ClassicHareegActionIds.discardPrefix}${eastDiscardCard.id}',
        );
        expect(
          controller.controlActionIdsFor(PlayerSeat.north),
          contains(ClassicHareegActionIds.takeDiscard),
        );
      },
    );

    test('playing a valid meld removes cards and keeps the turn active', () {
      final meldCards = [
        _card(CardRank.seven, CardSuit.clubs, 20),
        _card(CardRank.seven, CardSuit.diamonds, 20),
        _card(CardRank.seven, CardSuit.hearts, 20),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...meldCards, ...defaults[PlayerSeat.south]!],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );

      final result = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(controller.currentSeat, PlayerSeat.south);
      expect(controller.turnPhase, TurnPhase.action);
      expect(controller.tableMeldsFor(PlayerSeat.south), hasLength(1));
      expect(
        controller.tableMeldsFor(PlayerSeat.south).single.valueSnapshot,
        21,
      );
      expect(
        controller.handFor(PlayerSeat.south).map((card) => card.id),
        isNot(containsAll(meldCards.map((card) => card.id))),
      );
    });

    test('playing a three-card sequence is legal', () {
      final meldCards = [
        _card(CardRank.five, CardSuit.clubs, 23),
        _card(CardRank.six, CardSuit.clubs, 23),
        _card(CardRank.seven, CardSuit.clubs, 23),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...meldCards, ...defaults[PlayerSeat.south]!],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );

      final result = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(
        controller.tableMeldsFor(PlayerSeat.south).single.cards,
        hasLength(3),
      );
    });

    test('playing a sequence with one obvious joker assigns its identity', () {
      final joker = HareegCard.joker(deckIndex: 25, jokerIndex: 0);
      final meldCards = [
        _card(CardRank.nine, CardSuit.spades, 25),
        _card(CardRank.ten, CardSuit.spades, 25),
        joker,
        _card(CardRank.queen, CardSuit.spades, 25),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...meldCards, ...defaults[PlayerSeat.south]!],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );

      final selectedIds = meldCards.map((card) => card.id).toList();
      final validation = controller.meldValidationFor(
        PlayerSeat.south,
        selectedIds,
      );
      final result = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(selectedIds),
      );

      expect(validation.isValid, isTrue);
      expect(validation.message, contains('Joker as JS'));
      expect(result.isSuccess, isTrue);
      expect(
        controller
            .tableMeldsFor(PlayerSeat.south)
            .single
            .cards
            .map((card) => card.label),
        ['9S', '10S', 'J(JS)', 'QS'],
      );
      expect(
        controller.tableMeldsFor(PlayerSeat.south).single.valueSnapshot,
        39,
      );
    });

    test('playing a three-card sequence with one obvious joker is legal', () {
      final joker = HareegCard.joker(deckIndex: 26, jokerIndex: 0);
      final meldCards = [
        _card(CardRank.ten, CardSuit.spades, 26),
        joker,
        _card(CardRank.queen, CardSuit.spades, 26),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...meldCards, ...defaults[PlayerSeat.south]!],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );

      final result = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(
        controller
            .tableMeldsFor(PlayerSeat.south)
            .single
            .cards
            .map((card) => card.label),
        ['10S', 'J(JS)', 'QS'],
      );
    });

    test('ambiguous joker melds require an explicit represented identity', () {
      final joker = HareegCard.joker(deckIndex: 28, jokerIndex: 0);
      final meldCards = [
        _card(CardRank.seven, CardSuit.clubs, 28),
        joker,
        _card(CardRank.seven, CardSuit.diamonds, 28),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...meldCards, ...defaults[PlayerSeat.south]!],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );
      final selectedIds = meldCards.map((card) => card.id).toList();

      final options = controller.jokerRepresentationOptionsFor(
        PlayerSeat.south,
        selectedIds,
      );
      final blocked = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(selectedIds),
      );
      final played = controller.applyAction(
        ClassicHareegActionIds.playMeldWithJokerIdentityActionId(
          cardIds: selectedIds,
          jokerId: joker.id,
          identity: options.first,
        ),
      );

      expect(options.map((identity) => identity.label), ['7H', '7S']);
      expect(blocked.isSuccess, isFalse);
      expect(blocked.message, contains('Choose'));
      expect(played.isSuccess, isTrue);
      expect(
        controller
            .tableMeldsFor(PlayerSeat.south)
            .single
            .cards
            .map((card) => card.label),
        ['7D', '7C', 'J(7H)'],
      );
    });

    test('same-suit face-card joker sequence exposes both edge choices', () {
      final joker = HareegCard.joker(deckIndex: 130, jokerIndex: 0);
      final meldCards = [
        _card(CardRank.jack, CardSuit.hearts, 130),
        _card(CardRank.queen, CardSuit.hearts, 130),
        joker,
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              ...meldCards,
              _card(CardRank.four, CardSuit.clubs, 130),
            ],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );
      final selectedIds = meldCards.map((card) => card.id).toList();

      final options = controller.jokerRepresentationOptionsFor(
        PlayerSeat.south,
        selectedIds,
      );
      final plainPlay = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(selectedIds),
      );
      final chosenPlay = controller.applyAction(
        ClassicHareegActionIds.playMeldWithJokerIdentityActionId(
          cardIds: selectedIds,
          jokerId: joker.id,
          identity: const CardIdentity(
            rank: CardRank.king,
            suit: CardSuit.hearts,
          ),
        ),
      );

      expect(options.map((identity) => identity.label), ['10H', 'KH']);
      expect(plainPlay.isSuccess, isFalse);
      expect(plainPlay.message, contains('Choose'));
      expect(chosenPlay.isSuccess, isTrue);
      expect(
        controller
            .tableMeldsFor(PlayerSeat.south)
            .single
            .cards
            .map((card) => card.label),
        ['JH', 'QH', 'J(KH)'],
      );
    });

    test('two-joker meld actions apply every represented joker', () {
      const firstJoker = HareegCard.joker(deckIndex: 150, jokerIndex: 0);
      const secondJoker = HareegCard.joker(deckIndex: 150, jokerIndex: 1);
      final twoClubs = _card(CardRank.two, CardSuit.clubs, 150);
      final threeClubs = _card(CardRank.three, CardSuit.clubs, 150);
      final finalDiscard = _card(CardRank.king, CardSuit.hearts, 150);
      final meldCards = [twoClubs, threeClubs, firstJoker, secondJoker];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...meldCards, finalDiscard],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );
      final selectedIds = meldCards.map((card) => card.id).toList();

      final choices = controller.jokerMeldChoicesFor(
        PlayerSeat.south,
        selectedIds,
      );
      final play = controller.applyAction(choices.first.actionId);

      expect(choices, hasLength(2));
      expect(play.isSuccess, isTrue);
      expect(controller.handFor(PlayerSeat.south), [finalDiscard]);
      expect(
        controller
            .tableMeldsFor(PlayerSeat.south)
            .single
            .cards
            .map((card) => card.label),
        ['J(AC)', '2C', '3C', 'J(4C)'],
      );
    });

    test('three-joker meld actions apply every represented joker', () {
      const firstJoker = HareegCard.joker(deckIndex: 151, jokerIndex: 0);
      const secondJoker = HareegCard.joker(deckIndex: 151, jokerIndex: 1);
      const thirdJoker = HareegCard.joker(deckIndex: 151, jokerIndex: 2);
      final sevenClubs = _card(CardRank.seven, CardSuit.clubs, 151);
      final finalDiscard = _card(CardRank.king, CardSuit.hearts, 151);
      final meldCards = [sevenClubs, firstJoker, secondJoker, thirdJoker];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...meldCards, finalDiscard],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );
      final selectedIds = meldCards.map((card) => card.id).toList();

      final choices = controller.jokerMeldChoicesFor(
        PlayerSeat.south,
        selectedIds,
      );
      final play = controller.applyAction(choices.first.actionId);

      expect(choices, isNotEmpty);
      expect(choices.first.assignments, hasLength(3));
      expect(play.isSuccess, isTrue);
      expect(controller.handFor(PlayerSeat.south), [finalDiscard]);
      expect(
        controller
            .tableMeldsFor(PlayerSeat.south)
            .single
            .cards
            .map((card) => card.label)
            .toSet(),
        {'7C', 'J(7D)', 'J(7H)', 'J(7S)'},
      );
    });

    test('cpu meld search can choose multiple unresolved jokers', () {
      const firstJoker = HareegCard.joker(deckIndex: 152, jokerIndex: 0);
      const secondJoker = HareegCard.joker(deckIndex: 152, jokerIndex: 1);
      final sevenClubs = _card(CardRank.seven, CardSuit.clubs, 152);
      final finalDiscard = _card(CardRank.king, CardSuit.hearts, 152);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              sevenClubs,
              firstJoker,
              secondJoker,
              finalDiscard,
            ],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );

      final actionId = controller
          .cpuActionIdsFor(PlayerSeat.south)
          .firstWhere(
            (id) =>
                ClassicHareegActionIds.describe(id).kind ==
                ClassicHareegActionKind.playMeldWithJoker,
          );
      final choice = ClassicHareegActionIds.jokerMeldChoice(actionId)!;
      final play = controller.applyAction(actionId);

      expect(choice.assignments, hasLength(2));
      expect(play.isSuccess, isTrue);
      expect(controller.handFor(PlayerSeat.south), [finalDiscard]);
      expect(
        controller
            .tableMeldsFor(PlayerSeat.south)
            .single
            .cards
            .where((card) => card.isJoker)
            .map((card) => card.representedIdentity)
            .whereType<CardIdentity>(),
        hasLength(2),
      );
    });

    test('mixed-suit face-card joker sequence has no meld action', () {
      final joker = HareegCard.joker(deckIndex: 131, jokerIndex: 0);
      final meldCards = [
        _card(CardRank.jack, CardSuit.diamonds, 131),
        _card(CardRank.queen, CardSuit.hearts, 131),
        joker,
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              ...meldCards,
              _card(CardRank.four, CardSuit.clubs, 131),
            ],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );
      final selectedIds = meldCards.map((card) => card.id).toList();

      expect(
        controller.jokerRepresentationOptionsFor(PlayerSeat.south, selectedIds),
        isEmpty,
      );
      expect(
        controller.selectedMeldActionIdFor(PlayerSeat.south, selectedIds),
        isNull,
      );
      expect(
        controller
            .applyAction(ClassicHareegActionIds.playMeldActionId(selectedIds))
            .isSuccess,
        isFalse,
      );
    });

    test('exact selected joker meld action resolves ambiguous final set', () {
      final joker = HareegCard.joker(deckIndex: 128, jokerIndex: 0);
      final meldCards = [
        _card(CardRank.ace, CardSuit.hearts, 128),
        _card(CardRank.ace, CardSuit.spades, 128),
        joker,
      ];
      final finalDiscard = _card(CardRank.four, CardSuit.clubs, 128);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...meldCards, finalDiscard],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );

      final actionId = controller.selectedMeldActionIdFor(
        PlayerSeat.south,
        meldCards.map((card) => card.id).toList(),
      );

      expect(
        actionId,
        startsWith(ClassicHareegActionIds.playMeldWithJokerPrefix),
      );
      expect(
        ClassicHareegActionIds.jokerMeldChoice(actionId!)?.identity.rank,
        CardRank.ace,
      );

      final play = controller.applyAction(actionId);
      final discard = controller.applyAction(
        '${ClassicHareegActionIds.discardPrefix}${finalDiscard.id}',
      );

      expect(play.isSuccess, isTrue);
      expect(discard.isSuccess, isTrue);
      expect(controller.isRoundOver, isTrue);
      expect(controller.roundOutcome, RoundOutcomeType.normalFinish);
    });

    test('opened player can take back a new meld placed this turn', () {
      final joker = HareegCard.joker(deckIndex: 129, jokerIndex: 0);
      final aceHearts = _card(CardRank.ace, CardSuit.hearts, 129);
      final aceSpades = _card(CardRank.ace, CardSuit.spades, 129);
      final selectedIds = [aceHearts.id, aceSpades.id, joker.id];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              aceHearts,
              aceSpades,
              joker,
              ...defaults[PlayerSeat.south]!,
            ],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );

      final play = controller.applyAction(
        ClassicHareegActionIds.playMeldWithJokerIdentityActionId(
          cardIds: selectedIds,
          jokerId: joker.id,
          identity: const CardIdentity(
            rank: CardRank.ace,
            suit: CardSuit.diamonds,
          ),
        ),
      );

      expect(play.isSuccess, isTrue);
      expect(
        controller.canReturnTablePlayFromMeld(PlayerSeat.south, 0),
        isTrue,
      );

      final returned = controller.applyAction(
        ClassicHareegActionIds.returnTablePlayActionId(
          owner: PlayerSeat.south,
          meldIndex: 0,
        ),
      );

      expect(returned.isSuccess, isTrue);
      expect(controller.tableMeldsFor(PlayerSeat.south), isEmpty);
      expect(
        controller.handFor(PlayerSeat.south).map((card) => card.id),
        containsAll(selectedIds),
      );
      expect(
        controller.handFor(PlayerSeat.south).firstWhere((card) => card.isJoker),
        joker,
      );
    });

    test('opened players can replace represented table jokers', () {
      final joker = HareegCard.joker(deckIndex: 29, jokerIndex: 0);
      final replacement = _card(CardRank.seven, CardSuit.clubs, 30);
      final meldCards = [
        _card(CardRank.six, CardSuit.clubs, 29),
        joker,
        _card(CardRank.eight, CardSuit.clubs, 29),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              ...meldCards,
              replacement,
              ...defaults[PlayerSeat.south]!,
            ],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );
      controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );

      final actionId = controller.jokerReplacementActionIdFor(
        PlayerSeat.south,
        [replacement.id],
      );
      final result = controller.applyAction(actionId!);

      expect(result.isSuccess, isTrue);
      expect(
        controller
            .tableMeldsFor(PlayerSeat.south)
            .single
            .cards
            .map((card) => card.label),
        ['6C', '7C', '8C'],
      );
      expect(
        controller.handFor(PlayerSeat.south).any((card) => card.isJoker),
        isTrue,
      );
    });

    test('selected cover cards can extend an existing meld', () {
      final meldCards = [
        _card(CardRank.five, CardSuit.clubs, 24),
        _card(CardRank.six, CardSuit.clubs, 24),
        _card(CardRank.seven, CardSuit.clubs, 24),
        _card(CardRank.eight, CardSuit.clubs, 24),
      ];
      final covers = [
        _card(CardRank.nine, CardSuit.clubs, 24),
        _card(CardRank.ten, CardSuit.clubs, 24),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              ...meldCards,
              ...covers,
              ...defaults[PlayerSeat.south]!,
            ],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );
      controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );

      final coverAction = controller.coverActionIdFor(
        PlayerSeat.south,
        covers.map((card) => card.id).toList(),
      );
      expect(coverAction, isNotNull);

      final result = controller.applyAction(coverAction!);

      expect(result.isSuccess, isTrue);
      final tableMeld = controller.tableMeldsFor(PlayerSeat.south).single;
      expect(tableMeld.cards.map((card) => card.label), [
        '5C',
        '6C',
        '7C',
        '8C',
        '9C',
        '10C',
      ]);
      expect(
        controller.handFor(PlayerSeat.south).map((card) => card.id),
        isNot(containsAll(covers.map((card) => card.id))),
      );
    });

    test('cover actions can target a specific matching opponent meld', () {
      final eastMeld = [
        _card(CardRank.three, CardSuit.clubs, 31),
        _card(CardRank.four, CardSuit.clubs, 31),
        _card(CardRank.five, CardSuit.clubs, 31),
      ];
      final westMeld = [
        _card(CardRank.three, CardSuit.clubs, 32),
        _card(CardRank.four, CardSuit.clubs, 32),
        _card(CardRank.five, CardSuit.clubs, 32),
      ];
      final cover = _card(CardRank.six, CardSuit.clubs, 33);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [cover, ...defaults[PlayerSeat.south]!],
          },
          tableMelds: {
            PlayerSeat.east: [PlacedMeld.fromCards(eastMeld)],
            PlayerSeat.west: [PlacedMeld.fromCards(westMeld)],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );

      final actionId = controller.coverActionIdForMeldTarget(
        seat: PlayerSeat.south,
        cardIds: [cover.id],
        targetSeat: PlayerSeat.west,
        meldIndex: 0,
      );

      expect(actionId, isNotNull);
      expect(
        ClassicHareegActionIds.coverActionTarget(actionId!)?.targetSeat,
        PlayerSeat.west,
      );

      final result = controller.applyAction(actionId);

      expect(result.isSuccess, isTrue);
      expect(
        controller
            .tableMeldsFor(PlayerSeat.west)
            .single
            .cards
            .map((card) => card.label),
        ['3C', '4C', '5C', '6C'],
      );
      expect(
        controller.tableMeldsFor(PlayerSeat.east).single.cards,
        hasLength(3),
      );
    });

    test('ace can cover the high end of a face-card sequence', () {
      final tableMeld = [
        _card(CardRank.jack, CardSuit.spades, 141),
        _card(CardRank.queen, CardSuit.spades, 141),
        _card(CardRank.king, CardSuit.spades, 141),
      ];
      final aceCover = _card(CardRank.ace, CardSuit.spades, 141);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [aceCover, ...defaults[PlayerSeat.south]!],
          },
          tableMelds: {
            PlayerSeat.east: [PlacedMeld.fromCards(tableMeld)],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );

      final actionId = controller.coverActionIdForMeldTarget(
        seat: PlayerSeat.south,
        cardIds: [aceCover.id],
        targetSeat: PlayerSeat.east,
        meldIndex: 0,
      );

      expect(actionId, isNotNull);
      expect(controller.applyAction(actionId!).isSuccess, isTrue);
      expect(
        controller
            .tableMeldsFor(PlayerSeat.east)
            .single
            .cards
            .map((card) => card.label),
        ['JS', 'QS', 'KS', 'AS'],
      );
    });

    test('set covers reject duplicate visual cards from another deck', () {
      final tableMeld = [
        _card(CardRank.jack, CardSuit.hearts, 142),
        _card(CardRank.jack, CardSuit.clubs, 142),
        _card(CardRank.jack, CardSuit.spades, 142),
      ];
      final duplicateHeart = _card(CardRank.jack, CardSuit.hearts, 143);
      final missingDiamond = _card(CardRank.jack, CardSuit.diamonds, 143);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              duplicateHeart,
              missingDiamond,
              ...defaults[PlayerSeat.south]!,
            ],
          },
          tableMelds: {
            PlayerSeat.east: [PlacedMeld.fromCards(tableMeld)],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );

      final duplicateAction = controller.coverActionIdForMeldTarget(
        seat: PlayerSeat.south,
        cardIds: [duplicateHeart.id],
        targetSeat: PlayerSeat.east,
        meldIndex: 0,
      );
      final forcedDuplicate = ClassicHareegActionIds.placeCoverActionId(
        targetSeat: PlayerSeat.east,
        meldIndex: 0,
        cardIds: [duplicateHeart.id],
      );
      final diamondAction = controller.coverActionIdForMeldTarget(
        seat: PlayerSeat.south,
        cardIds: [missingDiamond.id],
        targetSeat: PlayerSeat.east,
        meldIndex: 0,
      );

      expect(duplicateAction, isNull);
      expect(controller.applyAction(forcedDuplicate).isSuccess, isFalse);
      expect(diamondAction, isNotNull);
      expect(controller.applyAction(diamondAction!).isSuccess, isTrue);
      expect(
        controller
            .tableMeldsFor(PlayerSeat.east)
            .single
            .cards
            .map((card) => card.effectiveIdentity!.key)
            .toSet(),
        {'jack-clubs', 'jack-diamonds', 'jack-hearts', 'jack-spades'},
      );
    });

    for (final strictness in [
      TableStrictness.coaching,
      TableStrictness.strict,
    ]) {
      test('turn cover can be returned in ${strictness.name} mode', () {
        final eastMeld = [
          _card(CardRank.three, CardSuit.clubs, 132),
          _card(CardRank.four, CardSuit.clubs, 132),
          _card(CardRank.five, CardSuit.clubs, 132),
        ];
        final cover = _card(CardRank.six, CardSuit.clubs, 132);
        final controller = ClassicHareegGameController.fromSnapshot(
          _snapshot(
            setup: ClassicHareegSetup.defaults().copyWith(
              tableStrictness: strictness,
            ),
            handsBuilder: (defaults) => {
              ...defaults,
              PlayerSeat.south: [cover, ...defaults[PlayerSeat.south]!],
            },
            tableMelds: {
              PlayerSeat.east: [PlacedMeld.fromCards(eastMeld)],
            },
            currentSeat: PlayerSeat.south,
            turnPhase: TurnPhase.action,
            openingState: _opened(PlayerSeat.south),
          ),
        );

        final coverAction = controller.coverActionIdForMeldTarget(
          seat: PlayerSeat.south,
          cardIds: [cover.id],
          targetSeat: PlayerSeat.east,
          meldIndex: 0,
        );
        expect(controller.applyAction(coverAction!).isSuccess, isTrue);

        expect(
          controller.controlActionIdsFor(PlayerSeat.south),
          contains(ClassicHareegActionIds.returnOpeningMelds),
        );
        expect(
          controller.canReturnTablePlayFromMeld(PlayerSeat.east, 0),
          isTrue,
        );

        final returned = controller.applyAction(
          ClassicHareegActionIds.returnOpeningMelds,
        );

        expect(returned.isSuccess, isTrue);
        expect(
          controller
              .tableMeldsFor(PlayerSeat.east)
              .single
              .cards
              .map((card) => card.label),
          ['3C', '4C', '5C'],
        );
        expect(
          controller.handFor(PlayerSeat.south).map((card) => card.id),
          contains(cover.id),
        );
        expect(
          controller.controlActionIdsFor(PlayerSeat.south),
          isNot(contains(ClassicHareegActionIds.returnOpeningMelds)),
        );
      });
    }

    test('specific turn cover retract only returns covers on that meld', () {
      final eastMeld = [
        _card(CardRank.three, CardSuit.clubs, 134),
        _card(CardRank.four, CardSuit.clubs, 134),
        _card(CardRank.five, CardSuit.clubs, 134),
      ];
      final westMeld = [
        _card(CardRank.three, CardSuit.diamonds, 134),
        _card(CardRank.four, CardSuit.diamonds, 134),
        _card(CardRank.five, CardSuit.diamonds, 134),
      ];
      final eastCover = _card(CardRank.six, CardSuit.clubs, 134);
      final westCover = _card(CardRank.six, CardSuit.diamonds, 134);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              eastCover,
              westCover,
              ...defaults[PlayerSeat.south]!,
            ],
          },
          tableMelds: {
            PlayerSeat.east: [PlacedMeld.fromCards(eastMeld)],
            PlayerSeat.west: [PlacedMeld.fromCards(westMeld)],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );

      final eastAction = controller.coverActionIdForMeldTarget(
        seat: PlayerSeat.south,
        cardIds: [eastCover.id],
        targetSeat: PlayerSeat.east,
        meldIndex: 0,
      );
      final westAction = controller.coverActionIdForMeldTarget(
        seat: PlayerSeat.south,
        cardIds: [westCover.id],
        targetSeat: PlayerSeat.west,
        meldIndex: 0,
      );
      expect(controller.applyAction(eastAction!).isSuccess, isTrue);
      expect(controller.applyAction(westAction!).isSuccess, isTrue);

      final returned = controller.applyAction(
        ClassicHareegActionIds.returnTablePlayActionId(
          owner: PlayerSeat.east,
          meldIndex: 0,
        ),
      );

      expect(returned.isSuccess, isTrue);
      expect(
        controller
            .tableMeldsFor(PlayerSeat.east)
            .single
            .cards
            .map((card) => card.label),
        ['3C', '4C', '5C'],
      );
      expect(
        controller
            .tableMeldsFor(PlayerSeat.west)
            .single
            .cards
            .map((card) => card.label),
        ['3D', '4D', '5D', '6D'],
      );
      final handIds = controller
          .handFor(PlayerSeat.south)
          .map((card) => card.id);
      expect(handIds, contains(eastCover.id));
      expect(handIds, isNot(contains(westCover.id)));
      expect(controller.canReturnTablePlayFromMeld(PlayerSeat.west, 0), isTrue);
    });

    test('turn cover cannot be returned in hard table mode', () {
      final eastMeld = [
        _card(CardRank.three, CardSuit.clubs, 133),
        _card(CardRank.four, CardSuit.clubs, 133),
        _card(CardRank.five, CardSuit.clubs, 133),
      ];
      final cover = _card(CardRank.six, CardSuit.clubs, 133);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          setup: ClassicHareegSetup.defaults().copyWith(
            tableStrictness: TableStrictness.table,
          ),
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [cover, ...defaults[PlayerSeat.south]!],
          },
          tableMelds: {
            PlayerSeat.east: [PlacedMeld.fromCards(eastMeld)],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );

      final coverAction = controller.coverActionIdForMeldTarget(
        seat: PlayerSeat.south,
        cardIds: [cover.id],
        targetSeat: PlayerSeat.east,
        meldIndex: 0,
      );
      expect(controller.applyAction(coverAction!).isSuccess, isTrue);

      expect(
        controller.controlActionIdsFor(PlayerSeat.south),
        isNot(contains(ClassicHareegActionIds.returnOpeningMelds)),
      );
      expect(
        controller.canReturnTablePlayFromMeld(PlayerSeat.east, 0),
        isFalse,
      );

      final returned = controller.applyAction(
        ClassicHareegActionIds.returnOpeningMelds,
      );

      expect(returned.isSuccess, isFalse);
      expect(
        controller
            .tableMeldsFor(PlayerSeat.east)
            .single
            .cards
            .map((card) => card.label),
        ['3C', '4C', '5C', '6C'],
      );
      expect(
        controller.handFor(PlayerSeat.south).map((card) => card.id),
        isNot(contains(cover.id)),
      );
    });

    test('an obvious joker cover receives a represented identity', () {
      final joker = HareegCard.joker(deckIndex: 34, jokerIndex: 0);
      final meldCards = [
        _card(CardRank.ace, CardSuit.clubs, 34),
        _card(CardRank.two, CardSuit.clubs, 34),
        _card(CardRank.three, CardSuit.clubs, 34),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              ...meldCards,
              joker,
              ...defaults[PlayerSeat.south]!,
            ],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );
      controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );

      final coverAction = controller.coverActionIdFor(PlayerSeat.south, [
        joker.id,
      ]);
      final result = controller.applyAction(coverAction!);

      expect(result.isSuccess, isTrue);
      expect(
        controller
            .tableMeldsFor(PlayerSeat.south)
            .single
            .cards
            .map((card) => card.label),
        ['AC', '2C', '3C', 'J(4C)'],
      );
    });

    test('active snapshots reset current-turn covers before resume', () {
      final tableMeld = [
        _card(CardRank.six, CardSuit.clubs, 144),
        _card(CardRank.seven, CardSuit.clubs, 144),
        _card(CardRank.eight, CardSuit.clubs, 144),
      ];
      final cover = _card(CardRank.nine, CardSuit.clubs, 144);
      final finalDiscard = _card(CardRank.two, CardSuit.spades, 144);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [cover, finalDiscard],
          },
          tableMelds: {
            PlayerSeat.east: [PlacedMeld.fromCards(tableMeld)],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );
      final coverAction = controller.coverActionIdForMeldTarget(
        seat: PlayerSeat.south,
        cardIds: [cover.id],
        targetSeat: PlayerSeat.east,
        meldIndex: 0,
      );
      expect(controller.applyAction(coverAction!).isSuccess, isTrue);
      expect(controller.handFor(PlayerSeat.south), [finalDiscard]);

      final saved = controller.toSnapshot();

      expect(saved.hands[PlayerSeat.south]!.map((card) => card.id), [
        cover.id,
        finalDiscard.id,
      ]);
      expect(
        saved.tableMelds[PlayerSeat.east]!.single.cards.map(
          (card) => card.label,
        ),
        ['6C', '7C', '8C'],
      );

      final resumed = ClassicHareegGameController.fromSnapshot(saved);
      final resumedCoverAction = resumed.coverActionIdForMeldTarget(
        seat: PlayerSeat.south,
        cardIds: [cover.id],
        targetSeat: PlayerSeat.east,
        meldIndex: 0,
      );
      expect(resumed.applyAction(resumedCoverAction!).isSuccess, isTrue);
      expect(
        resumed
            .applyAction(
              '${ClassicHareegActionIds.discardPrefix}${finalDiscard.id}',
            )
            .isSuccess,
        isTrue,
      );
      expect(resumed.roundOutcome, RoundOutcomeType.normalFinish);
    });

    test(
      'table penalty cover discards use blocked-cover prefix and add +3',
      () {
        final meldCards = [
          _card(CardRank.five, CardSuit.clubs, 27),
          _card(CardRank.six, CardSuit.clubs, 27),
          _card(CardRank.seven, CardSuit.clubs, 27),
        ];
        final cover = _card(CardRank.eight, CardSuit.clubs, 27);
        final controller = ClassicHareegGameController.fromSnapshot(
          _snapshot(
            handsBuilder: (defaults) => {
              ...defaults,
              PlayerSeat.south: [
                ...meldCards,
                cover,
                ...defaults[PlayerSeat.south]!,
              ],
            },
            currentSeat: PlayerSeat.south,
            turnPhase: TurnPhase.action,
            openingState: _opened(PlayerSeat.south),
            setup: ClassicHareegSetup.defaults().copyWith(
              tableStrictness: TableStrictness.strict,
            ),
          ),
        );
        controller.applyAction(
          ClassicHareegActionIds.playMeldActionId(
            meldCards.map((card) => card.id),
          ),
        );

        final legal = controller.legalActionIdsFor(PlayerSeat.south);
        expect(
          legal,
          contains(
            '${ClassicHareegActionIds.discardBlockedCoverPrefix}${cover.id}',
          ),
        );
        final southCardCountBefore = controller.cardCountFor(PlayerSeat.south);
        final topDiscardBefore = controller.topDiscard?.id;
        final currentSeatBefore = controller.currentSeat;
        final result = controller.applyAction(
          '${ClassicHareegActionIds.discardBlockedCoverPrefix}${cover.id}',
        );

        // Strict revert: penalty applied to the score, action undone — the
        // cover card stays in the seat's hand, the discard pile top is
        // unchanged, and the turn is still south's so they can pick a legal
        // discard. The UI uses revertedCardId to flash the wrong card.
        expect(result.isSuccess, isTrue);
        expect(result.wasReverted, isTrue);
        expect(result.revertedCardId, cover.id);
        expect(controller.scores[PlayerSeat.south], 3);
        expect(controller.topDiscard?.id, topDiscardBefore);
        expect(controller.cardCountFor(PlayerSeat.south), southCardCountBefore);
        expect(controller.currentSeat, currentSeatBefore);
      },
    );

    test(
      'cover and joker replacement discard is advertised once and penalized once',
      () {
        const represented = CardIdentity(
          rank: CardRank.eight,
          suit: CardSuit.clubs,
        );
        const tableJoker = HareegCard.joker(
          deckIndex: 137,
          jokerIndex: 0,
          representedIdentity: represented,
        );
        final sequenceMeld = [
          _card(CardRank.five, CardSuit.clubs, 137),
          _card(CardRank.six, CardSuit.clubs, 137),
          _card(CardRank.seven, CardSuit.clubs, 137),
        ];
        final jokerSet = [
          tableJoker,
          _card(CardRank.eight, CardSuit.diamonds, 137),
          _card(CardRank.eight, CardSuit.spades, 137),
        ];
        final blocked = _card(CardRank.eight, CardSuit.clubs, 138);
        final controller = ClassicHareegGameController.fromSnapshot(
          _snapshot(
            handsBuilder: (defaults) => {
              ...defaults,
              PlayerSeat.south: [blocked, ...defaults[PlayerSeat.south]!],
            },
            tableMelds: {
              PlayerSeat.east: [
                PlacedMeld.fromCards(sequenceMeld),
                PlacedMeld.fromCards(jokerSet),
              ],
            },
            currentSeat: PlayerSeat.south,
            turnPhase: TurnPhase.action,
            openingState: _opened(PlayerSeat.south),
            setup: ClassicHareegSetup.defaults().copyWith(
              tableStrictness: TableStrictness.strict,
            ),
          ),
        );

        final actionId =
            '${ClassicHareegActionIds.discardBlockedCoverPrefix}${blocked.id}';
        final matchingActions = controller
            .legalActionIdsFor(PlayerSeat.south)
            .where(
              (id) => ClassicHareegActionIds.discardCardId(id) == blocked.id,
            )
            .toList(growable: false);

        expect(matchingActions, [actionId]);

        final southCountBefore = controller.cardCountFor(PlayerSeat.south);
        final topBefore = controller.topDiscard?.id;
        final result = controller.applyAction(actionId);

        // Strict revert: penalty hit the score, the action did not happen.
        // Hand size, top discard, and the current seat are all unchanged.
        expect(result.isSuccess, isTrue);
        expect(result.wasReverted, isTrue);
        expect(result.revertedCardId, blocked.id);
        expect(controller.scores[PlayerSeat.south], 3);
        expect(controller.topDiscard?.id, topBefore);
        expect(controller.cardCountFor(PlayerSeat.south), southCountBefore);
      },
    );

    test(
      'assisted mode blocks discarding a card that can replace a table joker',
      () {
        const represented = CardIdentity(
          rank: CardRank.two,
          suit: CardSuit.clubs,
        );
        const tableJoker = HareegCard.joker(
          deckIndex: 135,
          jokerIndex: 0,
          representedIdentity: represented,
        );
        final tableMeld = [
          _card(CardRank.two, CardSuit.diamonds, 135),
          tableJoker,
          _card(CardRank.two, CardSuit.spades, 135),
        ];
        final replacement = _card(CardRank.two, CardSuit.clubs, 136);
        final controller = ClassicHareegGameController.fromSnapshot(
          _snapshot(
            handsBuilder: (defaults) => {
              ...defaults,
              PlayerSeat.south: [replacement, ...defaults[PlayerSeat.south]!],
            },
            tableMelds: {
              PlayerSeat.east: [PlacedMeld.fromCards(tableMeld)],
            },
            currentSeat: PlayerSeat.south,
            turnPhase: TurnPhase.action,
            openingState: _opened(PlayerSeat.south),
          ),
        );

        expect(
          controller
              .legalActionIdsFor(PlayerSeat.south)
              .where(
                (id) =>
                    ClassicHareegActionIds.discardCardId(id) == replacement.id,
              ),
          isEmpty,
        );

        final result = controller.applyAction(
          '${ClassicHareegActionIds.discardPrefix}${replacement.id}',
        );

        expect(result.isSuccess, isFalse);
        expect(controller.topDiscard?.id, isNot(replacement.id));
      },
    );

    test(
      'assisted mode allows discarding duplicate visual cards already in a represented-joker set',
      () {
        const represented = CardIdentity(
          rank: CardRank.jack,
          suit: CardSuit.clubs,
        );
        const tableJoker = HareegCard.joker(
          deckIndex: 137,
          jokerIndex: 0,
          representedIdentity: represented,
        );
        final tableMeld = [
          tableJoker,
          _card(CardRank.jack, CardSuit.hearts, 137),
          _card(CardRank.jack, CardSuit.spades, 137),
        ];
        final duplicateJack = _card(CardRank.jack, CardSuit.hearts, 138);
        final trueCover = _card(CardRank.jack, CardSuit.diamonds, 138);
        final trueReplacement = _card(CardRank.jack, CardSuit.clubs, 138);
        final controller = ClassicHareegGameController.fromSnapshot(
          _snapshot(
            handsBuilder: (defaults) => {
              ...defaults,
              PlayerSeat.south: [
                duplicateJack,
                trueCover,
                trueReplacement,
                ...defaults[PlayerSeat.south]!,
              ],
            },
            tableMelds: {
              PlayerSeat.east: [PlacedMeld.fromCards(tableMeld)],
            },
            currentSeat: PlayerSeat.south,
            turnPhase: TurnPhase.action,
            openingState: _opened(PlayerSeat.south),
          ),
        );

        final legal = controller.controlActionIdsFor(PlayerSeat.south);

        expect(
          legal,
          contains(
            '${ClassicHareegActionIds.discardPrefix}${duplicateJack.id}',
          ),
        );
        expect(
          legal.where(
            (id) =>
                ClassicHareegActionIds.discardCardId(id) == trueCover.id ||
                ClassicHareegActionIds.discardCardId(id) == trueReplacement.id,
          ),
          isEmpty,
        );

        final result = controller.applyAction(
          '${ClassicHareegActionIds.discardPrefix}${duplicateJack.id}',
        );

        expect(result.isSuccess, isTrue);
        expect(controller.topDiscard?.id, duplicateJack.id);
      },
    );

    test(
      'game flow keeps covers, joker replacements, and duplicate-card discards distinct',
      () {
        const represented = CardIdentity(
          rank: CardRank.jack,
          suit: CardSuit.clubs,
        );
        const tableJoker = HareegCard.joker(
          deckIndex: 139,
          jokerIndex: 0,
          representedIdentity: represented,
        );
        final sequenceMeld = [
          _card(CardRank.five, CardSuit.clubs, 139),
          _card(CardRank.six, CardSuit.clubs, 139),
          _card(CardRank.seven, CardSuit.clubs, 139),
        ];
        final jokerSet = [
          tableJoker,
          _card(CardRank.jack, CardSuit.hearts, 139),
          _card(CardRank.jack, CardSuit.spades, 139),
        ];
        final sequenceCover = _card(CardRank.eight, CardSuit.clubs, 140);
        final jokerReplacement = _card(CardRank.jack, CardSuit.clubs, 140);
        final duplicateJack = _card(CardRank.jack, CardSuit.hearts, 140);
        final controller = ClassicHareegGameController.fromSnapshot(
          _snapshot(
            handsBuilder: (defaults) => {
              ...defaults,
              PlayerSeat.south: [
                sequenceCover,
                jokerReplacement,
                duplicateJack,
                ...defaults[PlayerSeat.south]!,
              ],
            },
            tableMelds: {
              PlayerSeat.east: [
                PlacedMeld.fromCards(sequenceMeld),
                PlacedMeld.fromCards(jokerSet),
              ],
            },
            currentSeat: PlayerSeat.south,
            turnPhase: TurnPhase.action,
            openingState: _opened(PlayerSeat.south),
          ),
        );

        final control = controller.controlActionIdsFor(PlayerSeat.south);
        expect(
          control,
          contains(
            '${ClassicHareegActionIds.discardPrefix}${duplicateJack.id}',
          ),
        );
        expect(
          control.where(
            (id) =>
                ClassicHareegActionIds.discardCardId(id) == sequenceCover.id ||
                ClassicHareegActionIds.discardCardId(id) == jokerReplacement.id,
          ),
          isEmpty,
        );

        final coverAction = controller.coverActionIdForMeldTarget(
          seat: PlayerSeat.south,
          cardIds: [sequenceCover.id],
          targetSeat: PlayerSeat.east,
          meldIndex: 0,
        );
        final replaceAction = controller.jokerReplacementActionIdForMeldTarget(
          seat: PlayerSeat.south,
          cardIds: [jokerReplacement.id],
          targetSeat: PlayerSeat.east,
          meldIndex: 1,
        );

        expect(coverAction, isNotNull);
        expect(replaceAction, isNotNull);
        expect(controller.applyAction(coverAction!).isSuccess, isTrue);
        expect(controller.applyAction(replaceAction!).isSuccess, isTrue);

        final discard = controller.applyAction(
          '${ClassicHareegActionIds.discardPrefix}${duplicateJack.id}',
        );

        expect(discard.isSuccess, isTrue);
        expect(controller.topDiscard?.id, duplicateJack.id);
        expect(
          controller.tableMeldsFor(PlayerSeat.east)[0].cards,
          contains(sequenceCover),
        );
        expect(
          controller.tableMeldsFor(PlayerSeat.east)[1].cards,
          contains(jokerReplacement),
        );
        expect(
          controller.handFor(PlayerSeat.south).where((card) => card.isJoker),
          isNotEmpty,
        );
      },
    );

    test('pending discard must be part of the played meld', () {
      final pending = _card(CardRank.eight, CardSuit.clubs, 21);
      final otherMeld = [
        _card(CardRank.seven, CardSuit.clubs, 22),
        _card(CardRank.seven, CardSuit.diamonds, 22),
        _card(CardRank.seven, CardSuit.hearts, 22),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              pending,
              ...otherMeld,
              ...defaults[PlayerSeat.south]!,
            ],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          pendingDiscard: pending,
        ),
      );

      final result = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          otherMeld.map((card) => card.id),
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('picked up discard'));
      expect(controller.pendingDiscard?.id, pending.id);
      expect(controller.tableMeldsFor(PlayerSeat.south), isEmpty);
    });
  });

  group('ClassicHareegGameController CPU integration', () {
    test(
      'CPU strategy only produces legal actions across a full table cycle',
      () {
        final controller = _freshControllerInActionPhase();
        const strategy = ClassicHareegCpuStrategy();

        // Human discards a non-joker.
        final south = controller.handFor(PlayerSeat.south);
        controller.applyAction(
          '${ClassicHareegActionIds.discardPrefix}'
          '${south.firstWhere((c) => !c.isJoker).id}',
        );
        final stockAfterHumanDiscard = controller.stockCount;

        var safety = 0;
        while (controller.currentSeat != PlayerSeat.south && safety < 64) {
          final seat = controller.currentSeat;
          final legal = controller.legalActionIdsFor(seat);
          expect(
            legal,
            isNotEmpty,
            reason: 'CPU seat $seat must have at least one legal action.',
          );

          final intent = strategy.chooseMove(
            CpuTurnSnapshot(
              seat: seat,
              legalActionIds: legal,
              difficulty: controller.setup.cpuDifficulty,
            ),
          );

          expect(
            legal,
            contains(intent.actionId),
            reason: 'CPU strategy must pick from the legal action list.',
          );

          final result = controller.applyAction(intent.actionId);
          expect(
            result.isSuccess,
            isTrue,
            reason:
                'CPU action ${intent.actionId} should be applied. '
                '${result.message}',
          );
          safety += 1;
        }

        expect(controller.currentSeat, PlayerSeat.south);
        expect(controller.turnPhase, TurnPhase.draw);
        expect(controller.stockCount, stockAfterHumanDiscard - 3);
      },
    );
  });

  group('ClassicHareegGameController Fifty and mistake presets', () {
    test('wrong Fifty claims in table penalty mode add +3', () {
      final now = DateTime.utc(2026, 5, 19, 12);
      final discarded = _card(CardRank.nine, CardSuit.clubs, 31);
      final setup = ClassicHareegSetup.defaults().copyWith(
        tableStrictness: TableStrictness.strict,
      );
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          setup: setup,
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.east: [
              _card(CardRank.two, CardSuit.hearts, 31),
              _card(CardRank.four, CardSuit.diamonds, 31),
              _card(CardRank.king, CardSuit.spades, 31),
            ],
          },
          discardPile: [discarded],
          currentSeat: PlayerSeat.east,
          turnPhase: TurnPhase.draw,
          savedAt: now,
          fiftyWindowOpenedAt: now,
        ),
        now: () => now,
      );

      expect(
        controller.legalActionIdsFor(PlayerSeat.east),
        contains(ClassicHareegActionIds.claimFifty),
      );

      final result = controller.applyAction(ClassicHareegActionIds.claimFifty);

      expect(result.isSuccess, isTrue);
      expect(controller.scores[PlayerSeat.east], 3);
      expect(controller.isRoundOver, isFalse);
      expect(controller.currentSeat, PlayerSeat.east);
    });

    test('hard table wrong Fifty claims add +17 and can end the round', () {
      final now = DateTime.utc(2026, 5, 19, 12);
      final discarded = _card(CardRank.nine, CardSuit.clubs, 231);
      final setup = ClassicHareegSetup.defaults().copyWith(
        tableStrictness: TableStrictness.table,
      );
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          setup: setup,
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.east: [
              _card(CardRank.two, CardSuit.hearts, 231),
              _card(CardRank.four, CardSuit.diamonds, 231),
              _card(CardRank.king, CardSuit.spades, 231),
            ],
          },
          activeSeats: const [PlayerSeat.south, PlayerSeat.east],
          discardPile: [discarded],
          currentSeat: PlayerSeat.east,
          turnPhase: TurnPhase.draw,
          savedAt: now,
          fiftyWindowOpenedAt: now,
        ),
        now: () => now,
      );

      final result = controller.applyAction(ClassicHareegActionIds.claimFifty);

      expect(result.isSuccess, isTrue);
      expect(controller.scoreView.previousScores[PlayerSeat.east], 17);
      expect(controller.roundOutcome, RoundOutcomeType.normalFinish);
      expect(controller.roundResult?.winner, PlayerSeat.south);
      expect(controller.legalActionIdsFor(PlayerSeat.east), isEmpty);
    });

    test('expired Fifty hides claim but keeps normal pickup available', () {
      var now = DateTime.utc(2026, 5, 19, 12);
      final discarded = _card(CardRank.nine, CardSuit.clubs, 32);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.east: [
              _card(CardRank.seven, CardSuit.clubs, 32),
              _card(CardRank.eight, CardSuit.clubs, 32),
              _card(CardRank.two, CardSuit.hearts, 32),
            ],
          },
          discardPile: [discarded],
          currentSeat: PlayerSeat.east,
          turnPhase: TurnPhase.draw,
          savedAt: now,
          fiftyWindowOpenedAt: now,
        ),
        now: () => now,
      );

      expect(
        controller.legalActionIdsFor(PlayerSeat.east),
        contains(ClassicHareegActionIds.claimFifty),
      );

      now = now.add(const Duration(seconds: 4));
      final legal = controller.legalActionIdsFor(PlayerSeat.east);

      expect(controller.fiftySecondsRemaining, 0);
      expect(legal, isNot(contains(ClassicHareegActionIds.claimFifty)));
      expect(legal, contains(ClassicHareegActionIds.takeDiscard));

      now = now.add(const Duration(seconds: 3));
      expect(controller.fiftySecondsRemaining, isNull);
    });

    test('restored expired Fifty window stays expired', () {
      final now = DateTime.utc(2026, 5, 19, 12);
      final discarded = _card(CardRank.nine, CardSuit.clubs, 45);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.east: [
              _card(CardRank.seven, CardSuit.clubs, 45),
              _card(CardRank.eight, CardSuit.clubs, 45),
              _card(CardRank.two, CardSuit.hearts, 45),
            ],
          },
          discardPile: [discarded],
          currentSeat: PlayerSeat.east,
          turnPhase: TurnPhase.draw,
          savedAt: now,
          fiftyWindowOpenedAt: now.subtract(const Duration(seconds: 5)),
        ),
        now: () => now,
      );

      final legal = controller.legalActionIdsFor(PlayerSeat.east);

      expect(legal, isNot(contains(ClassicHareegActionIds.claimFifty)));
      expect(legal, contains(ClassicHareegActionIds.takeDiscard));
    });

    test('Fifty finish progress is carried into the next round snapshot', () {
      final now = DateTime.utc(2026, 5, 19, 12);
      final discarded = _card(CardRank.nine, CardSuit.clubs, 132);
      final eastFinishCards = [
        _card(CardRank.seven, CardSuit.clubs, 132),
        _card(CardRank.eight, CardSuit.clubs, 132),
        _card(CardRank.two, CardSuit.hearts, 132),
      ];
      final southCards = [
        for (var i = 0; i < 11; i += 1)
          _card(
            CardRank.values[i % CardRank.values.length],
            CardSuit.spades,
            300 + i,
          ),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: southCards,
            PlayerSeat.east: eastFinishCards,
          },
          discardPile: [discarded],
          currentSeat: PlayerSeat.east,
          turnPhase: TurnPhase.draw,
          roundNumber: 2,
          savedAt: now,
          fiftyWindowOpenedAt: now,
        ),
        now: () => now,
      );

      final result = controller.applyAction(ClassicHareegActionIds.claimFifty);
      final progress = controller.roundProgress;
      final next = controller.nextRoundSnapshot(savedAt: now);

      expect(result.isSuccess, isTrue);
      expect(controller.roundOutcome, RoundOutcomeType.fiftyFinish);
      expect(controller.scores[PlayerSeat.east], -3);
      expect(controller.scores[PlayerSeat.south], 14);
      expect(progress?.scores[PlayerSeat.east], -3);
      expect(progress?.scores[PlayerSeat.south], 14);
      expect(next?.scores[PlayerSeat.east], -3);
      expect(next?.scores[PlayerSeat.south], 14);
    });

    test('hard table mistakes add +17 and remove the player from round', () {
      final meldCards = [
        _card(CardRank.five, CardSuit.clubs, 33),
        _card(CardRank.six, CardSuit.clubs, 33),
        _card(CardRank.seven, CardSuit.clubs, 33),
      ];
      final cover = _card(CardRank.eight, CardSuit.clubs, 33);
      final setup = ClassicHareegSetup.defaults().copyWith(
        tableStrictness: TableStrictness.table,
      );
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          setup: setup,
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              ...meldCards,
              cover,
              ...defaults[PlayerSeat.south]!,
            ],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );
      controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );

      final result = controller.applyAction(
        '${ClassicHareegActionIds.discardBlockedCoverPrefix}${cover.id}',
      );

      expect(result.isSuccess, isTrue);
      expect(controller.scores[PlayerSeat.south], 17);
      expect(controller.currentSeat, PlayerSeat.east);
      expect(controller.legalActionIdsFor(PlayerSeat.south), isEmpty);
      expect(controller.tableMeldsFor(PlayerSeat.south), hasLength(1));
    });
  });

  group('ClassicHareegGameController round end', () {
    test('placing every remaining card is blocked without a final discard', () {
      final meldCards = [
        _card(CardRank.five, CardSuit.clubs, 39),
        _card(CardRank.six, CardSuit.clubs, 39),
        _card(CardRank.seven, CardSuit.clubs, 39),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: meldCards,
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );

      final result = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('final discard'));
      expect(controller.isRoundOver, isFalse);
      expect(controller.cardCountFor(PlayerSeat.south), 3);
    });

    test('final discard after playing cards ends the round', () {
      final meldCards = [
        _card(CardRank.five, CardSuit.clubs, 40),
        _card(CardRank.six, CardSuit.clubs, 40),
        _card(CardRank.seven, CardSuit.clubs, 40),
      ];
      final finalDiscard = _card(CardRank.two, CardSuit.hearts, 40);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...meldCards, finalDiscard],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );

      final play = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );
      final discard = controller.applyAction(
        '${ClassicHareegActionIds.discardPrefix}${finalDiscard.id}',
      );

      expect(play.isSuccess, isTrue);
      expect(discard.isSuccess, isTrue);
      expect(controller.isRoundOver, isTrue);
      expect(controller.roundOutcome, RoundOutcomeType.normalFinish);
      expect(controller.roundResult?.winner, PlayerSeat.south);
      expect(controller.roundResult?.remainingCardCounts[PlayerSeat.south], 0);
      expect(controller.legalActionIdsFor(PlayerSeat.east), isEmpty);
    });

    test('perfect-hand final discard bypasses opening requirement', () {
      final meldCards = [
        _card(CardRank.five, CardSuit.clubs, 41),
        _card(CardRank.six, CardSuit.clubs, 41),
        _card(CardRank.seven, CardSuit.clubs, 41),
      ];
      final finalDiscard = _card(CardRank.two, CardSuit.hearts, 41);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...meldCards, finalDiscard],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
        ),
      );

      controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );
      final result = controller.applyAction(
        '${ClassicHareegActionIds.discardPrefix}${finalDiscard.id}',
      );

      expect(result.isSuccess, isTrue);
      expect(controller.isRoundOver, isTrue);
      expect(controller.openingState.hasOpened(PlayerSeat.south), isFalse);
      expect(controller.roundResult?.winner, PlayerSeat.south);
    });

    test('multiple selected melds can satisfy opening together', () {
      final firstMeld = [
        _card(CardRank.ten, CardSuit.clubs, 42),
        _card(CardRank.ten, CardSuit.diamonds, 42),
        _card(CardRank.ten, CardSuit.hearts, 42),
      ];
      final secondMeld = [
        _card(CardRank.nine, CardSuit.clubs, 42),
        _card(CardRank.nine, CardSuit.diamonds, 42),
        _card(CardRank.nine, CardSuit.hearts, 42),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              ...firstMeld,
              ...secondMeld,
              ...defaults[PlayerSeat.south]!,
            ],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
        ),
      );

      final result = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          [...firstMeld, ...secondMeld].map((card) => card.id),
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(controller.openingState.hasOpened(PlayerSeat.south), isTrue);
      expect(controller.tableMeldsFor(PlayerSeat.south), hasLength(2));
      expect(controller.openingState.currentRequirement, 57);
    });

    test('multi-meld opening can place explicit joker in one meld', () {
      const joker = HareegCard.joker(deckIndex: 191, jokerIndex: 0);
      final fourSet = [
        _card(CardRank.four, CardSuit.diamonds, 191),
        _card(CardRank.four, CardSuit.hearts, 191),
        _card(CardRank.four, CardSuit.clubs, 191),
      ];
      final sevenSet = [
        _card(CardRank.seven, CardSuit.clubs, 191),
        _card(CardRank.seven, CardSuit.hearts, 191),
        _card(CardRank.seven, CardSuit.spades, 191),
      ];
      final tenSetWithJoker = [
        _card(CardRank.ten, CardSuit.diamonds, 191),
        _card(CardRank.ten, CardSuit.clubs, 191),
        joker,
      ];
      final finalDiscard = _card(CardRank.two, CardSuit.spades, 191);
      final selectedCards = [...fourSet, ...sevenSet, ...tenSetWithJoker];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...selectedCards, finalDiscard],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
        ),
      );

      final result = controller.applyAction(
        ClassicHareegActionIds.playMeldWithJokerIdentityActionId(
          cardIds: selectedCards.map((card) => card.id),
          jokerId: joker.id,
          identity: const CardIdentity(
            rank: CardRank.ten,
            suit: CardSuit.hearts,
          ),
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(controller.openingState.hasOpened(PlayerSeat.south), isTrue);
      expect(controller.tableMeldsFor(PlayerSeat.south), hasLength(3));
      expect(
        controller
            .tableMeldsFor(PlayerSeat.south)
            .last
            .cards
            .map((card) => card.label),
        ['10D', '10C', 'J(10H)'],
      );
      expect(controller.handFor(PlayerSeat.south), [finalDiscard]);
    });

    test('restored unlocked benchmark reflects first opener table total', () {
      final ownerMelds = [
        PlacedMeld.fromCards([
          _card(CardRank.ten, CardSuit.clubs, 142),
          _card(CardRank.ten, CardSuit.diamonds, 142),
          _card(CardRank.ten, CardSuit.hearts, 142),
        ]),
        PlacedMeld.fromCards([
          _card(CardRank.nine, CardSuit.clubs, 142),
          _card(CardRank.ten, CardSuit.clubs, 143),
          _card(CardRank.jack, CardSuit.clubs, 142),
        ]),
        PlacedMeld.fromCards([
          _card(CardRank.two, CardSuit.hearts, 142),
          _card(CardRank.three, CardSuit.hearts, 142),
          _card(CardRank.four, CardSuit.hearts, 142),
        ]),
      ];
      expect(
        ownerMelds.fold<int>(0, (total, meld) => total + meld.totalValue),
        68,
      );

      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          tableMelds: {PlayerSeat.east: ownerMelds},
          openingState: const OpeningState(
            baseRequirement: 51,
            currentRequirement: 54,
            benchmarkOwner: PlayerSeat.east,
            openedSeats: {PlayerSeat.east},
          ),
        ),
      );

      expect(controller.openingState.currentRequirement, 68);

      final lockedController = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          tableMelds: {PlayerSeat.east: ownerMelds},
          openingState: const OpeningState(
            baseRequirement: 51,
            currentRequirement: 54,
            benchmarkOwner: PlayerSeat.east,
            isLocked: true,
            openedSeats: {PlayerSeat.east, PlayerSeat.west},
          ),
        ),
      );

      expect(lockedController.openingState.currentRequirement, 54);
    });

    test('legal meld actions include larger and multi-meld opening plays', () {
      final clubRun = [
        _card(CardRank.seven, CardSuit.clubs, 46),
        _card(CardRank.eight, CardSuit.clubs, 46),
        _card(CardRank.nine, CardSuit.clubs, 46),
        _card(CardRank.ten, CardSuit.clubs, 46),
        _card(CardRank.jack, CardSuit.clubs, 46),
        _card(CardRank.queen, CardSuit.clubs, 46),
      ];
      final tenSet = [
        _card(CardRank.ten, CardSuit.clubs, 47),
        _card(CardRank.ten, CardSuit.diamonds, 47),
        _card(CardRank.ten, CardSuit.hearts, 47),
      ];
      final nineSet = [
        _card(CardRank.nine, CardSuit.clubs, 48),
        _card(CardRank.nine, CardSuit.diamonds, 48),
        _card(CardRank.nine, CardSuit.hearts, 48),
      ];
      final finalDiscard = _card(CardRank.two, CardSuit.spades, 46);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...clubRun, ...tenSet, ...nineSet, finalDiscard],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
        ),
      );

      final legal = controller.legalActionIdsFor(PlayerSeat.south);

      expect(
        legal,
        contains(
          ClassicHareegActionIds.playMeldActionId(
            clubRun.map((card) => card.id),
          ),
        ),
      );
      expect(
        legal,
        contains(
          ClassicHareegActionIds.playMeldActionId(
            [...tenSet, ...nineSet].map((card) => card.id),
          ),
        ),
      );
    });

    test('opening can be staged across separate meld plays', () {
      final pickedUpTen = _card(CardRank.ten, CardSuit.diamonds, 44);
      final tenSet = [
        _card(CardRank.ten, CardSuit.clubs, 44),
        _card(CardRank.ten, CardSuit.hearts, 44),
        pickedUpTen,
      ];
      final diamondRun = [
        _card(CardRank.four, CardSuit.diamonds, 44),
        _card(CardRank.five, CardSuit.diamonds, 44),
        _card(CardRank.six, CardSuit.diamonds, 44),
        _card(CardRank.seven, CardSuit.diamonds, 44),
        _card(CardRank.eight, CardSuit.diamonds, 44),
        _card(CardRank.nine, CardSuit.diamonds, 44),
      ];
      final finalDiscard = _card(CardRank.two, CardSuit.spades, 44);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...tenSet, ...diamondRun, finalDiscard],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          pendingDiscard: pickedUpTen,
        ),
      );

      final staged = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(tenSet.map((card) => card.id)),
      );

      expect(staged.isSuccess, isTrue);
      expect(staged.message, contains('Opening 30/51'));
      expect(controller.pendingDiscard, isNull);
      expect(controller.openingState.hasOpened(PlayerSeat.south), isFalse);
      expect(controller.tableMeldsFor(PlayerSeat.south), hasLength(1));
      expect(
        controller
            .legalActionIdsFor(PlayerSeat.south)
            .where((id) => ClassicHareegActionIds.discardCardId(id) != null),
        isEmpty,
      );

      final opened = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          diamondRun.map((card) => card.id),
        ),
      );

      expect(opened.isSuccess, isTrue);
      expect(opened.message, contains('Opened at 69'));
      expect(controller.openingState.hasOpened(PlayerSeat.south), isTrue);
      expect(controller.tableMeldsFor(PlayerSeat.south), hasLength(2));
      expect(
        controller
            .legalActionIdsFor(PlayerSeat.south)
            .any((id) => ClassicHareegActionIds.discardCardId(id) != null),
        isTrue,
      );
    });

    test('incomplete opening melds can be taken back', () {
      final clubRun = [
        _card(CardRank.ten, CardSuit.clubs, 49),
        _card(CardRank.jack, CardSuit.clubs, 49),
        _card(CardRank.queen, CardSuit.clubs, 49),
      ];
      final nineSet = [
        _card(CardRank.nine, CardSuit.clubs, 49),
        _card(CardRank.nine, CardSuit.diamonds, 49),
        _card(CardRank.nine, CardSuit.hearts, 49),
      ];
      final remainingCards = [
        _card(CardRank.two, CardSuit.spades, 49),
        _card(CardRank.three, CardSuit.spades, 49),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...clubRun, ...nineSet, ...remainingCards],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: const OpeningState(
            baseRequirement: 51,
            currentRequirement: 60,
            benchmarkOwner: PlayerSeat.north,
            openedSeats: {PlayerSeat.north},
          ),
        ),
      );

      controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(clubRun.map((card) => card.id)),
      );
      final staged = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(nineSet.map((card) => card.id)),
      );

      expect(staged.message, contains('Opening 57/60'));
      expect(
        controller.controlActionIdsFor(PlayerSeat.south),
        contains(ClassicHareegActionIds.returnOpeningMelds),
      );
      expect(
        controller
            .legalActionIdsFor(PlayerSeat.south)
            .where((id) => id.startsWith(ClassicHareegActionIds.discardPrefix)),
        isEmpty,
      );

      final returned = controller.applyAction(
        ClassicHareegActionIds.returnOpeningMelds,
      );

      expect(returned.isSuccess, isTrue);
      expect(controller.tableMeldsFor(PlayerSeat.south), isEmpty);
      expect(controller.cardCountFor(PlayerSeat.south), 8);
      expect(controller.pendingDiscard, isNull);
      expect(
        controller.controlActionIdsFor(PlayerSeat.south),
        isNot(contains(ClassicHareegActionIds.returnOpeningMelds)),
      );
      expect(
        controller
            .controlActionIdsFor(PlayerSeat.south)
            .where((id) => id.startsWith(ClassicHareegActionIds.discardPrefix)),
        isNotEmpty,
      );
    });

    test('specific staged opening meld can be taken back alone', () {
      final tenSet = [
        _card(CardRank.ten, CardSuit.clubs, 149),
        _card(CardRank.ten, CardSuit.diamonds, 149),
        _card(CardRank.ten, CardSuit.hearts, 149),
      ];
      final nineSet = [
        _card(CardRank.nine, CardSuit.clubs, 149),
        _card(CardRank.nine, CardSuit.diamonds, 149),
        _card(CardRank.nine, CardSuit.hearts, 149),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              ...tenSet,
              ...nineSet,
              _card(CardRank.two, CardSuit.spades, 149),
              _card(CardRank.three, CardSuit.spades, 149),
            ],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: const OpeningState(
            baseRequirement: 51,
            currentRequirement: 70,
            benchmarkOwner: PlayerSeat.north,
            openedSeats: {PlayerSeat.north},
          ),
        ),
      );

      expect(
        controller
            .applyAction(
              ClassicHareegActionIds.playMeldActionId(
                tenSet.map((card) => card.id),
              ),
            )
            .isSuccess,
        isTrue,
      );
      expect(
        controller
            .applyAction(
              ClassicHareegActionIds.playMeldActionId(
                nineSet.map((card) => card.id),
              ),
            )
            .isSuccess,
        isTrue,
      );

      final returned = controller.applyAction(
        ClassicHareegActionIds.returnTablePlayActionId(
          owner: PlayerSeat.south,
          meldIndex: 0,
        ),
      );

      expect(returned.isSuccess, isTrue);
      expect(
        controller
            .tableMeldsFor(PlayerSeat.south)
            .single
            .cards
            .map((card) => card.label),
        ['9D', '9C', '9H'],
      );
      final handIds = controller
          .handFor(PlayerSeat.south)
          .map((card) => card.id);
      expect(handIds, containsAll(tenSet.map((card) => card.id)));
      expect(handIds, isNot(contains(nineSet.first.id)));
      expect(
        controller.controlActionIdsFor(PlayerSeat.south),
        contains(ClassicHareegActionIds.returnOpeningMelds),
      );
    });

    test('taking back opening melds restores a consumed pending discard', () {
      final pickedUpTen = _card(CardRank.ten, CardSuit.clubs, 50);
      final clubRun = [
        pickedUpTen,
        _card(CardRank.jack, CardSuit.clubs, 50),
        _card(CardRank.queen, CardSuit.clubs, 50),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              ...clubRun,
              _card(CardRank.two, CardSuit.spades, 50),
            ],
          },
          pendingDiscard: pickedUpTen,
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: const OpeningState(
            baseRequirement: 51,
            currentRequirement: 60,
            benchmarkOwner: PlayerSeat.north,
            openedSeats: {PlayerSeat.north},
          ),
        ),
      );

      controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(clubRun.map((card) => card.id)),
      );
      final returned = controller.applyAction(
        ClassicHareegActionIds.returnOpeningMelds,
      );

      expect(returned.isSuccess, isTrue);
      expect(controller.pendingDiscard?.id, pickedUpTen.id);
      expect(
        controller.controlActionIdsFor(PlayerSeat.south),
        contains(ClassicHareegActionIds.returnPendingDiscard),
      );
    });

    test('next round snapshot keeps scores and active seats', () {
      final meldCards = [
        _card(CardRank.five, CardSuit.clubs, 43),
        _card(CardRank.six, CardSuit.clubs, 43),
        _card(CardRank.seven, CardSuit.clubs, 43),
      ];
      final finalDiscard = _card(CardRank.two, CardSuit.hearts, 43);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...meldCards, finalDiscard],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
          scores: {
            PlayerSeat.south: 4,
            PlayerSeat.east: 5,
            PlayerSeat.north: 6,
            PlayerSeat.west: 7,
          },
          activeSeats: [PlayerSeat.south, PlayerSeat.east, PlayerSeat.north],
        ),
      );
      controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );
      controller.applyAction(
        '${ClassicHareegActionIds.discardPrefix}${finalDiscard.id}',
      );

      final next = controller.nextRoundSnapshot();

      expect(next, isNotNull);
      expect(next!.scores[PlayerSeat.south], 3);
      expect(next.activeSeats, [
        PlayerSeat.south,
        PlayerSeat.east,
        PlayerSeat.north,
      ]);
      expect(next.starter, PlayerSeat.south);
      expect(next.roundNumber, 2);
    });

    test('south crossing elimination flips isHumanEliminated on round end', () {
      // South sits at 30 (one point shy of 31) and east finishes the round
      // with south still holding two non-joker cards worth +1 each. The
      // resulting +2 pushes south to 32, which is the score-elimination
      // condition the spectator-skip product flow keys off of.
      final meldCards = [
        _card(CardRank.five, CardSuit.clubs, 44),
        _card(CardRank.six, CardSuit.clubs, 44),
        _card(CardRank.seven, CardSuit.clubs, 44),
      ];
      final finalDiscard = _card(CardRank.two, CardSuit.hearts, 44);
      final southHoldOne = _card(CardRank.three, CardSuit.spades, 44);
      final southHoldTwo = _card(CardRank.four, CardSuit.spades, 44);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [southHoldOne, southHoldTwo],
            PlayerSeat.east: [...meldCards, finalDiscard],
          },
          currentSeat: PlayerSeat.east,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.east),
          scores: {
            PlayerSeat.south: 30,
            PlayerSeat.east: 0,
            PlayerSeat.north: 0,
            PlayerSeat.west: 0,
          },
        ),
      );

      // Mid-round: nothing scored yet, so south is not yet eliminated.
      expect(controller.isHumanEliminated, isFalse);

      final play = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );
      final discard = controller.applyAction(
        '${ClassicHareegActionIds.discardPrefix}${finalDiscard.id}',
      );

      expect(play.isSuccess, isTrue);
      expect(discard.isSuccess, isTrue);
      expect(controller.isRoundOver, isTrue);
      expect(controller.roundOutcome, RoundOutcomeType.normalFinish);
      expect(controller.roundResult?.winner, PlayerSeat.east);

      final progress = controller.roundProgress;
      expect(progress, isNotNull);
      // South's score crossed 31 (30 + 2 = 32), so the progression rules
      // dropped it from activeSeats.
      expect(progress!.activeSeats, isNot(contains(PlayerSeat.south)));
      // Match isn't over yet — east/north/west are still active — but the
      // human is out for good. The controller surfaces that combination
      // through isHumanEliminated so the table screen can short-circuit
      // straight to the match-over surface.
      expect(progress.matchWinner, isNull);
      expect(controller.isHumanEliminated, isTrue);
    });

    test('stock exhaustion in draw phase ends the round as a draw', () {
      // Build a snapshot where stock is empty and South is in draw phase
      // because West just discarded. Stock exhaustion + no finish logic
      // ends the round as a draw under the rules engine.
      final base = _freshSnapshot();
      final stockToHand = base.stock.toList();
      final exhausted = ClassicHareegMatchSnapshot(
        setup: base.setup,
        hands: {
          ...base.hands,
          PlayerSeat.south: [...base.hands[PlayerSeat.south]!, ...stockToHand],
        },
        stock: const [],
        discardPile: [
          // Place at least one card so we can identify previous-seat.
          // Use any non-joker from East's hand.
          base.hands[PlayerSeat.east]!.firstWhere((c) => !c.isJoker),
        ],
        starter: base.starter,
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        savedAt: base.savedAt,
      );

      final controller = ClassicHareegGameController.fromSnapshot(exhausted);

      expect(controller.isRoundOver, isTrue);
      expect(controller.roundOutcome, RoundOutcomeType.draw);
      expect(controller.legalActionIdsFor(PlayerSeat.south), isEmpty);
    });
  });
}

ClassicHareegGameController _freshControllerInActionPhase() {
  return ClassicHareegGameController.fromRound(
    ClassicHareegRound.deal(setup: ClassicHareegSetup.defaults(), seed: 5),
  );
}

ClassicHareegMatchSnapshot _freshSnapshot() {
  final round = ClassicHareegRound.deal(
    setup: ClassicHareegSetup.defaults(),
    seed: 5,
  );
  return ClassicHareegMatchSnapshot(
    setup: round.setup,
    hands: round.hands,
    stock: round.stock,
    discardPile: round.discardPile,
    starter: round.starter,
    currentSeat: round.currentSeat,
    turnPhase: round.turnPhase,
    savedAt: DateTime.utc(2026, 5, 19),
  );
}

ClassicHareegMatchSnapshot _snapshot({
  Map<PlayerSeat, List<HareegCard>> Function(
    Map<PlayerSeat, List<HareegCard>> defaults,
  )?
  handsBuilder,
  PlayerSeat currentSeat = PlayerSeat.south,
  TurnPhase turnPhase = TurnPhase.action,
  HareegCard? pendingDiscard,
  OpeningState? openingState,
  Map<PlayerSeat, List<PlacedMeld>>? tableMelds,
  Map<PlayerSeat, int>? scores,
  List<PlayerSeat>? activeSeats,
  ClassicHareegSetup? setup,
  List<HareegCard>? discardPile,
  List<HareegCard>? stock,
  int roundNumber = 1,
  DateTime? savedAt,
  DateTime? fiftyWindowOpenedAt,
}) {
  final effectiveSetup = setup ?? ClassicHareegSetup.defaults();
  final round = ClassicHareegRound.deal(setup: effectiveSetup, seed: 5);
  final defaults = <PlayerSeat, List<HareegCard>>{
    for (final entry in round.hands.entries)
      entry.key: List<HareegCard>.of(entry.value),
  };
  final hands = handsBuilder == null ? defaults : handsBuilder(defaults);
  return ClassicHareegMatchSnapshot(
    setup: effectiveSetup,
    hands: hands,
    stock: stock ?? round.stock,
    discardPile: discardPile ?? round.discardPile,
    tableMelds: tableMelds ?? const {},
    starter: round.starter,
    currentSeat: currentSeat,
    turnPhase: turnPhase,
    pendingDiscard: pendingDiscard,
    openingState: openingState,
    scores: scores ?? const {},
    activeSeats:
        activeSeats ??
        const [
          PlayerSeat.south,
          PlayerSeat.east,
          PlayerSeat.north,
          PlayerSeat.west,
        ],
    roundNumber: roundNumber,
    fiftyWindowOpenedAt: fiftyWindowOpenedAt,
    savedAt: savedAt ?? DateTime.utc(2026, 5, 19),
  );
}

OpeningState _opened(PlayerSeat seat) {
  return ClassicHareegOpeningRules.applyOpening(
    state: OpeningState.initial(51),
    seat: seat,
    melds: [const PlacedMeld(cards: [], valueSnapshot: 51)],
  );
}

HareegCard _card(CardRank rank, CardSuit suit, int deckIndex) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
