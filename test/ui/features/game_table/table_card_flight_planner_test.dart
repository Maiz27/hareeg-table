import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/features/game_table/animations/deal_choreography.dart';
import 'package:hareeg_table/ui/features/game_table/table_action_presentation_planner.dart';
import 'package:hareeg_table/ui/features/game_table/table_card_flight_planner.dart';

void main() {
  group('TableCardFlightPlanner', () {
    test('blocks rendering when no presentation flight is requested', () {
      final realization = _realize();

      expect(
        realization.scenario,
        TableCardFlightScenario.noPresentationFlight,
      );
      expect(realization.canRender, isFalse);
      expect(realization.card, isNull);
      expect(realization.presentation, isNull);
    });

    test('realizes stock draw as a face-down flight into the seat hand', () {
      final stockBack = _card(CardRank.ace, CardSuit.spades, 700);
      final landingSlot = _slot(PlayerSeat.north, index: 12, count: 13);

      final realization = _realize(
        presentation: const TableActionFlightPlan(
          source: TableActionFlightSource.stockBack,
          destination: TableActionFlightDestination.seatHand,
          seat: PlayerSeat.north,
        ),
        stockBack: stockBack,
        appendSlots: {PlayerSeat.north: landingSlot},
      );

      expect(realization.scenario, TableCardFlightScenario.stockBack);
      expect(realization.canRender, isTrue);
      expect(realization.card, same(stockBack));
      expect(realization.faceDown, isTrue);
      expect(realization.beginHandSlot, isNull);
      expect(realization.endHandSlot, same(landingSlot));
      expect(realization.endMeldSlot, isNull);
    });

    test('realizes visible top discard as an exposed hand landing', () {
      final discard = _card(CardRank.queen, CardSuit.clubs, 12);
      final landingSlot = _slot(PlayerSeat.south, index: 4, count: 5);

      final realization = _realize(
        presentation: const TableActionFlightPlan(
          source: TableActionFlightSource.topDiscard,
          destination: TableActionFlightDestination.seatHand,
          seat: PlayerSeat.south,
        ),
        topDiscard: discard,
        appendSlots: {PlayerSeat.south: landingSlot},
      );

      expect(realization.scenario, TableCardFlightScenario.visibleTopDiscard);
      expect(realization.canRender, isTrue);
      expect(realization.card, same(discard));
      expect(realization.faceDown, isFalse);
      expect(realization.endHandSlot, same(landingSlot));
    });

    test('blocks top discard flight when the discard pile is empty', () {
      final realization = _realize(
        presentation: const TableActionFlightPlan(
          source: TableActionFlightSource.topDiscard,
          destination: TableActionFlightDestination.seatHand,
          seat: PlayerSeat.south,
        ),
      );

      expect(realization.scenario, TableCardFlightScenario.missingTopDiscard);
      expect(realization.canRender, isFalse);
      expect(realization.endHandSlot, isNull);
    });

    test('starts pending discard returns from the visible south hand slot', () {
      final pendingDiscard = _card(CardRank.nine, CardSuit.diamonds, 20);
      final sourceSlot = _slot(PlayerSeat.south, index: 2, count: 5);

      final realization = _realize(
        presentation: const TableActionFlightPlan(
          source: TableActionFlightSource.pendingDiscard,
          destination: TableActionFlightDestination.discardPile,
          seat: PlayerSeat.south,
        ),
        pendingDiscard: pendingDiscard,
        southSlots: {pendingDiscard.id: sourceSlot},
      );

      expect(
        realization.scenario,
        TableCardFlightScenario.visiblePendingDiscard,
      );
      expect(realization.canRender, isTrue);
      expect(realization.card, same(pendingDiscard));
      expect(realization.beginHandSlot, same(sourceSlot));
      expect(realization.endHandSlot, isNull);
    });

    test('lands hand-to-table flights in the requested meld lane', () {
      final card = _card(CardRank.jack, CardSuit.hearts, 30);
      final sourceSlot = _slot(PlayerSeat.south, index: 1, count: 4);

      final realization = _realize(
        presentation: TableActionFlightPlan(
          source: TableActionFlightSource.handCard,
          destination: TableActionFlightDestination.tableMeld,
          seat: PlayerSeat.south,
          cardId: card.id,
          targetSeat: PlayerSeat.east,
          targetMeldIndex: 2,
        ),
        handCards: {
          PlayerSeat.south: {card.id: card},
        },
        southSlots: {card.id: sourceSlot},
      );

      expect(realization.scenario, TableCardFlightScenario.visibleHandCard);
      expect(realization.canRender, isTrue);
      expect(realization.card, same(card));
      expect(realization.beginHandSlot, same(sourceSlot));
      expect(realization.endMeldSlot?.seat, PlayerSeat.east);
      expect(realization.endMeldSlot?.index, 2);
    });

    test('uses face-down fallback for hidden CPU hand cards', () {
      final stockBack = _card(CardRank.ace, CardSuit.spades, 701);
      final sourceSlot = _slot(PlayerSeat.west, index: 5, count: 6);

      final realization = _realize(
        presentation: const TableActionFlightPlan(
          source: TableActionFlightSource.handCard,
          destination: TableActionFlightDestination.discardPile,
          seat: PlayerSeat.west,
          cardId: 'hidden-card',
          allowFaceDownFallback: true,
        ),
        stockBack: stockBack,
        lastSlots: {PlayerSeat.west: sourceSlot},
      );

      expect(
        realization.scenario,
        TableCardFlightScenario.faceDownHandFallback,
      );
      expect(realization.canRender, isTrue);
      expect(realization.card, same(stockBack));
      expect(realization.faceDown, isTrue);
      expect(realization.beginHandSlot, same(sourceSlot));
      expect(realization.endHandSlot, isNull);
    });

    test('blocks missing hand cards when no fallback is allowed', () {
      final realization = _realize(
        presentation: const TableActionFlightPlan(
          source: TableActionFlightSource.handCard,
          destination: TableActionFlightDestination.discardPile,
          seat: PlayerSeat.south,
          cardId: 'missing-card',
        ),
      );

      expect(realization.scenario, TableCardFlightScenario.missingHandCard);
      expect(realization.canRender, isFalse);
      expect(realization.card, isNull);
    });

    test('blocks hand-card flights that do not name a card id', () {
      final realization = _realize(
        presentation: const TableActionFlightPlan(
          source: TableActionFlightSource.handCard,
          destination: TableActionFlightDestination.discardPile,
          seat: PlayerSeat.south,
          allowFaceDownFallback: true,
        ),
      );

      expect(realization.scenario, TableCardFlightScenario.missingHandCardId);
      expect(realization.canRender, isFalse);
      expect(realization.card, isNull);
    });
  });
}

TableCardFlightRealization _realize({
  TableActionFlightPlan? presentation,
  HareegCard? stockBack,
  HareegCard? topDiscard,
  HareegCard? pendingDiscard,
  Map<PlayerSeat, Map<String, HareegCard>> handCards = const {},
  Map<String, SeatHandFlightSlot> southSlots = const {},
  Map<PlayerSeat, SeatHandFlightSlot> appendSlots = const {},
  Map<PlayerSeat, SeatHandFlightSlot> lastSlots = const {},
}) {
  return TableCardFlightPlanner.realize(
    presentation: presentation,
    stockBack: stockBack ?? _card(CardRank.ace, CardSuit.spades, 702),
    topDiscard: topDiscard,
    pendingDiscard: pendingDiscard,
    handCardFor: (seat, cardId) => handCards[seat]?[cardId],
    southHandCardSlotFor: (cardId) => southSlots[cardId],
    appendHandSlotFor: (seat) =>
        appendSlots[seat] ?? _slot(seat, index: 0, count: 1),
    lastHandSlotFor: (seat) => lastSlots[seat],
  );
}

SeatHandFlightSlot _slot(
  PlayerSeat seat, {
  required int index,
  required int count,
}) {
  return SeatHandFlightSlot(seat: seat, index: index, count: count);
}

HareegCard _card(CardRank rank, CardSuit suit, int deckIndex) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
