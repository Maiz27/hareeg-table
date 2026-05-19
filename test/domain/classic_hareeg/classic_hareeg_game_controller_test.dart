import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_strategy.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';

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
        contains('${ClassicHareegActionIds.discardJokerPrefix}deck-0-joker-0'),
        reason: 'Jokers should be tagged separately from normal discards.',
      );

      final joker = controller
          .handFor(PlayerSeat.south)
          .firstWhere((card) => card.isJoker);
      final result = controller.applyAction(
        '${ClassicHareegActionIds.discardJokerPrefix}${joker.id}',
      );

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('Jokers cannot be discarded'));
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
        equals([
          ClassicHareegActionIds.usePendingDiscard,
          ClassicHareegActionIds.returnPendingDiscard,
        ]),
      );
    });

    test('returning a pending discard puts the card back on the pile', () {
      final controller = _freshControllerInActionPhase();
      final south = controller.handFor(PlayerSeat.south);
      final discarded = south.firstWhere((c) => !c.isJoker);
      controller.applyAction(
        '${ClassicHareegActionIds.discardPrefix}${discarded.id}',
      );
      controller.applyAction(ClassicHareegActionIds.takeDiscard);

      final stockBefore = controller.stockCount;
      final eastHandBefore = controller.cardCountFor(PlayerSeat.east);
      controller.applyAction(ClassicHareegActionIds.returnPendingDiscard);

      expect(controller.pendingDiscard, isNull);
      expect(controller.topDiscard?.id, discarded.id);
      expect(controller.stockCount, stockBefore - 1);
      expect(controller.cardCountFor(PlayerSeat.east), eastHandBefore);
    });

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

    test('cover discard candidates use the blocked-cover prefix', () {
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
      final result = controller.applyAction(
        '${ClassicHareegActionIds.discardBlockedCoverPrefix}${cover.id}',
      );

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('cover'));
    });

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

  group('ClassicHareegGameController round end', () {
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
}) {
  final round = ClassicHareegRound.deal(
    setup: ClassicHareegSetup.defaults(),
    seed: 5,
  );
  final defaults = <PlayerSeat, List<HareegCard>>{
    for (final entry in round.hands.entries)
      entry.key: List<HareegCard>.of(entry.value),
  };
  final hands = handsBuilder == null ? defaults : handsBuilder(defaults);
  return ClassicHareegMatchSnapshot(
    setup: round.setup,
    hands: hands,
    stock: round.stock,
    discardPile: round.discardPile,
    starter: round.starter,
    currentSeat: currentSeat,
    turnPhase: turnPhase,
    pendingDiscard: pendingDiscard,
    savedAt: DateTime.utc(2026, 5, 19),
  );
}

HareegCard _card(CardRank rank, CardSuit suit, int deckIndex) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
