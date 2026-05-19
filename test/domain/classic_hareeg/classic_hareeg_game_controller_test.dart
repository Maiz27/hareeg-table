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
        legal.any((id) => id.contains('joker')),
        isFalse,
        reason: 'Jokers should never appear as legal normal discards.',
      );

      final joker = controller
          .handFor(PlayerSeat.south)
          .firstWhere((card) => card.isJoker);
      final result = controller.applyAction(
        '${ClassicHareegActionIds.discardPrefix}${joker.id}',
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
    savedAt: DateTime.utc(2026, 5, 19),
  );
}
