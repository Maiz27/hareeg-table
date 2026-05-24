import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_discard_history.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

void main() {
  group('DiscardHistory', () {
    test('lastDiscardsBy returns cards in reverse chronological order', () {
      final history = DiscardHistory();
      final seven = _card(CardRank.seven, CardSuit.spades, 1);
      final eight = _card(CardRank.eight, CardSuit.spades, 1);

      history
        ..recordDiscard(PlayerSeat.north, seven)
        ..recordDiscard(PlayerSeat.north, eight);

      expect(history.lastDiscardsBy(PlayerSeat.north, 2), [eight, seven]);
    });

    test('lastDiscardsBy clamps to available count', () {
      final history = DiscardHistory();
      final seven = _card(CardRank.seven, CardSuit.spades, 2);
      final eight = _card(CardRank.eight, CardSuit.spades, 2);

      history
        ..recordDiscard(PlayerSeat.north, seven)
        ..recordDiscard(PlayerSeat.north, eight);

      expect(history.lastDiscardsBy(PlayerSeat.north, 5), [eight, seven]);
    });

    test('lastPickupsBy records take-previous-discard memory', () {
      final history = DiscardHistory();
      final nine = _card(CardRank.nine, CardSuit.hearts, 3);

      history
        ..recordDiscard(PlayerSeat.east, nine)
        ..recordPickup(PlayerSeat.north, nine);

      expect(history.lastPickupsBy(PlayerSeat.north, 1), [nine]);
    });

    test('retract undoes pickup while keeping original discard event', () {
      final history = DiscardHistory();
      final nine = _card(CardRank.nine, CardSuit.hearts, 4);

      history
        ..recordDiscard(PlayerSeat.east, nine)
        ..recordPickup(PlayerSeat.north, nine)
        ..retract(
          seat: PlayerSeat.north,
          card: nine,
          kind: DiscardEventKind.pickup,
        );

      expect(history.lastPickupsBy(PlayerSeat.north, 1), isEmpty);
      expect(history.events.map((event) => event.kind), [
        DiscardEventKind.discard,
      ]);
      expect(history.events.single.seat, PlayerSeat.east);
      expect(history.events.single.card, nine);
    });

    test('cardSeenAt and discardsCount track real card discards only', () {
      final history = DiscardHistory();
      final sevenSpades = _card(CardRank.seven, CardSuit.spades, 5);
      final sevenHearts = _card(CardRank.seven, CardSuit.hearts, 5);
      final sevenDiamonds = _card(CardRank.seven, CardSuit.diamonds, 5);

      expect(history.cardSeenAt(CardRank.seven, CardSuit.spades), isFalse);

      history
        ..recordDiscard(PlayerSeat.south, sevenSpades)
        ..recordDiscard(PlayerSeat.east, sevenHearts)
        ..recordDiscard(PlayerSeat.west, sevenDiamonds)
        ..recordDiscard(
          PlayerSeat.north,
          const HareegCard.joker(deckIndex: 5, jokerIndex: 0),
        );

      expect(history.cardSeenAt(CardRank.seven, CardSuit.spades), isTrue);
      expect(
        history.lastSeenAt(CardRank.seven, CardSuit.hearts)?.card,
        sevenHearts,
      );
      expect(history.discardsCount(CardRank.seven), 3);
      expect(history.jokersDiscarded, 1);
    });

    test('resetForNewRound clears events and counters', () {
      final history = DiscardHistory();
      final card = _card(CardRank.five, CardSuit.clubs, 6);
      history.recordDiscard(PlayerSeat.south, card);

      history.resetForNewRound();

      expect(history.events, isEmpty);
      expect(history.lastDiscardsBy(PlayerSeat.south, 1), isEmpty);
      expect(history.cardSeenAt(CardRank.five, CardSuit.clubs), isFalse);
      expect(history.discardsCount(CardRank.five), 0);
    });
  });

  group('ClassicHareegGameController discard history', () {
    test('records successful discards through the controller', () {
      final discarded = _card(CardRank.five, CardSuit.clubs, 20);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              discarded,
              _card(CardRank.king, CardSuit.hearts, 20),
            ],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
        ),
      );

      final result = controller.applyAction(
        '${ClassicHareegActionIds.discardPrefix}${discarded.id}',
      );

      expect(result.isSuccess, isTrue);
      expect(controller.discardHistory.lastDiscardsBy(PlayerSeat.south, 1), [
        discarded,
      ]);
      expect(
        controller.discardHistory.cardSeenAt(CardRank.five, CardSuit.clubs),
        isTrue,
      );
    });

    test('records and retracts pickup when pending discard is returned', () {
      final discarded = _card(CardRank.nine, CardSuit.clubs, 21);
      final controller = _controllerForEastPickup(discarded: discarded);

      final take = controller.applyAction(ClassicHareegActionIds.takeDiscard);
      final returned = controller.applyAction(
        ClassicHareegActionIds.returnPendingDiscard,
      );

      expect(take.isSuccess, isTrue);
      expect(returned.isSuccess, isTrue);
      expect(controller.topDiscard, discarded);
      expect(
        controller.discardHistory.lastPickupsBy(PlayerSeat.east, 1),
        isEmpty,
      );
    });

    test('keeps pickup memory when the pending discard is consumed', () {
      final discarded = _card(CardRank.nine, CardSuit.clubs, 22);
      final nineDiamonds = _card(CardRank.nine, CardSuit.diamonds, 22);
      final nineHearts = _card(CardRank.nine, CardSuit.hearts, 22);
      final controller = _controllerForEastPickup(
        discarded: discarded,
        eastHand: [
          nineDiamonds,
          nineHearts,
          _card(CardRank.two, CardSuit.spades, 22),
        ],
        openingState: _opened(PlayerSeat.east),
      );

      final take = controller.applyAction(ClassicHareegActionIds.takeDiscard);
      final meld = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId([
          discarded.id,
          nineDiamonds.id,
          nineHearts.id,
        ]),
      );

      expect(take.isSuccess, isTrue);
      expect(meld.isSuccess, isTrue);
      expect(controller.discardHistory.lastPickupsBy(PlayerSeat.east, 1), [
        discarded,
      ]);
      expect(controller.pendingDiscard, isNull);
    });

    test('new round controllers start with empty discard history', () {
      final meldCards = [
        _card(CardRank.five, CardSuit.clubs, 23),
        _card(CardRank.six, CardSuit.clubs, 23),
        _card(CardRank.seven, CardSuit.clubs, 23),
      ];
      final finalDiscard = _card(CardRank.two, CardSuit.hearts, 23);
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

      controller
        ..applyAction(
          ClassicHareegActionIds.playMeldActionId(
            meldCards.map((card) => card.id),
          ),
        )
        ..applyAction(
          '${ClassicHareegActionIds.discardPrefix}${finalDiscard.id}',
        );

      final nextSnapshot = controller.nextRoundSnapshot();
      final nextController = ClassicHareegGameController.fromSnapshot(
        nextSnapshot!,
      );

      expect(
        controller.discardHistory.cardSeenAt(CardRank.two, CardSuit.hearts),
        isTrue,
      );
      expect(
        nextController.discardHistory.lastDiscardsBy(PlayerSeat.south, 1),
        isEmpty,
      );
      expect(
        nextController.discardHistory.cardSeenAt(CardRank.two, CardSuit.hearts),
        isFalse,
      );
    });
  });
}

ClassicHareegGameController _controllerForEastPickup({
  required HareegCard discarded,
  List<HareegCard>? eastHand,
  OpeningState? openingState,
}) {
  return ClassicHareegGameController.fromSnapshot(
    _snapshot(
      handsBuilder: (defaults) => {
        ...defaults,
        PlayerSeat.east:
            eastHand ??
            [
              _card(CardRank.two, CardSuit.hearts, 24),
              _card(CardRank.four, CardSuit.diamonds, 24),
            ],
      },
      discardPile: [discarded],
      currentSeat: PlayerSeat.east,
      turnPhase: TurnPhase.draw,
      openingState: openingState,
    ),
  );
}

ClassicHareegMatchSnapshot _snapshot({
  Map<PlayerSeat, List<HareegCard>> Function(
    Map<PlayerSeat, List<HareegCard>> defaults,
  )?
  handsBuilder,
  PlayerSeat currentSeat = PlayerSeat.south,
  TurnPhase turnPhase = TurnPhase.action,
  OpeningState? openingState,
  List<HareegCard>? discardPile,
}) {
  final setup = ClassicHareegSetup.defaults();
  final round = ClassicHareegRound.deal(setup: setup, seed: 5);
  final defaults = <PlayerSeat, List<HareegCard>>{
    for (final entry in round.hands.entries)
      entry.key: List<HareegCard>.of(entry.value),
  };
  final hands = handsBuilder == null ? defaults : handsBuilder(defaults);
  return ClassicHareegMatchSnapshot(
    setup: setup,
    hands: hands,
    stock: round.stock,
    discardPile: discardPile ?? round.discardPile,
    starter: round.starter,
    currentSeat: currentSeat,
    turnPhase: turnPhase,
    openingState: openingState,
    savedAt: DateTime.utc(2026, 5, 23),
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
