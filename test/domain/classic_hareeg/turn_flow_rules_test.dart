import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/turn_flow_rules.dart';

void main() {
  group('ClassicHareegTurnFlowRules', () {
    test('non-starter draw phase exposes draw and legal discard pickup', () {
      final state = drawState();

      expect(state.legalActionIds, contains('draw-stock'));
      expect(state.legalActionIds, contains('take-discard'));
    });

    test('only immediate next player can take previous discard', () {
      final illegal = drawState(currentSeat: PlayerSeat.north);

      expect(
        () => ClassicHareegTurnFlowRules.takePreviousDiscard(illegal),
        throwsStateError,
      );
    });

    test('taking previous discard enters pending state', () {
      final state = ClassicHareegTurnFlowRules.takePreviousDiscard(drawState());

      expect(state.phase, ClassicTurnPhase.action);
      expect(state.pendingDiscard?.card.label, '9C');
      expect(state.discardPile, isEmpty);
      expect(state.legalActionIds, [
        'use-pending-discard',
        'return-pending-discard',
      ]);
    });

    test('pending state does not expose return when stock is empty', () {
      final pending = ClassicHareegTurnFlowRules.takePreviousDiscard(
        drawState(stock: const []),
      );

      expect(pending.legalActionIds, ['use-pending-discard']);
    });

    test('returning pending discard restores discard and draws stock', () {
      final pending = ClassicHareegTurnFlowRules.takePreviousDiscard(
        drawState(),
      );
      final returned = ClassicHareegTurnFlowRules.returnPendingDiscardAndDraw(
        pending,
      );

      expect(returned.pendingDiscard, isNull);
      expect(returned.discardPile.last.label, '9C');
      expect(returned.hand.length, pending.hand.length);
      expect(returned.stock.length, pending.stock.length - 1);
      expect(returned.phase, ClassicTurnPhase.action);
    });

    test('returning pending discard removes exactly one matching card', () {
      final pendingCard = card(CardRank.nine, CardSuit.clubs);
      final duplicate = card(CardRank.nine, CardSuit.clubs, deckIndex: 1);
      final state = ClassicTurnFlowState(
        currentSeat: PlayerSeat.east,
        phase: ClassicTurnPhase.action,
        hand: [pendingCard, duplicate],
        stock: [card(CardRank.two, CardSuit.clubs)],
        discardPile: const [],
        previousDiscardSeat: PlayerSeat.south,
        pendingDiscard: PendingDiscard(
          card: pendingCard,
          fromSeat: PlayerSeat.south,
        ),
      );

      final returned = ClassicHareegTurnFlowRules.returnPendingDiscardAndDraw(
        state,
      );

      expect(returned.hand.any((card) => card.id == pendingCard.id), isFalse);
      expect(returned.hand.any((card) => card.id == duplicate.id), isTrue);
      expect(returned.hand.length, 2);
    });

    test(
      'returning pending discard fails when the card is missing from hand',
      () {
        final pendingCard = card(CardRank.nine, CardSuit.clubs);
        final state = ClassicTurnFlowState(
          currentSeat: PlayerSeat.east,
          phase: ClassicTurnPhase.action,
          hand: [card(CardRank.five, CardSuit.hearts)],
          stock: [card(CardRank.two, CardSuit.clubs)],
          discardPile: const [],
          previousDiscardSeat: PlayerSeat.south,
          pendingDiscard: PendingDiscard(
            card: pendingCard,
            fromSeat: PlayerSeat.south,
          ),
        );

        expect(
          () => ClassicHareegTurnFlowRules.returnPendingDiscardAndDraw(state),
          throwsStateError,
        );
      },
    );

    test('player cannot draw stock after taking discard', () {
      final pending = ClassicHareegTurnFlowRules.takePreviousDiscard(
        drawState(),
      );

      expect(
        () => ClassicHareegTurnFlowRules.drawStock(pending),
        throwsStateError,
      );
    });

    test('taking discard can open when the pending card is used legally', () {
      final pending = ClassicHareegTurnFlowRules.takePreviousDiscard(
        drawState(
          hand: [
            card(CardRank.nine, CardSuit.diamonds),
            card(CardRank.nine, CardSuit.hearts),
            card(CardRank.ten, CardSuit.clubs),
            card(CardRank.jack, CardSuit.clubs),
            card(CardRank.queen, CardSuit.clubs),
          ],
        ),
      );
      final openingMelds = [
        PlacedMeld.fromCards([
          pending.pendingDiscard!.card,
          card(CardRank.nine, CardSuit.diamonds),
          card(CardRank.nine, CardSuit.hearts),
        ]),
        PlacedMeld.fromCards([
          card(CardRank.ten, CardSuit.clubs),
          card(CardRank.jack, CardSuit.clubs),
          card(CardRank.queen, CardSuit.clubs),
        ]),
      ];

      expect(
        ClassicHareegTurnFlowRules.canUsePendingDiscardToOpen(
          turnState: pending,
          openingState: OpeningState.initial(51),
          openingMelds: openingMelds,
        ),
        isTrue,
      );
    });
  });
}

ClassicTurnFlowState drawState({
  PlayerSeat currentSeat = PlayerSeat.east,
  List<HareegCard>? hand,
  List<HareegCard>? stock,
}) {
  return ClassicTurnFlowState(
    currentSeat: currentSeat,
    phase: ClassicTurnPhase.draw,
    hand: hand ?? [card(CardRank.five, CardSuit.hearts)],
    stock:
        stock ??
        [
          card(CardRank.two, CardSuit.clubs),
          card(CardRank.three, CardSuit.clubs),
        ],
    discardPile: [card(CardRank.nine, CardSuit.clubs)],
    previousDiscardSeat: PlayerSeat.south,
  );
}

HareegCard card(CardRank rank, CardSuit suit, {int deckIndex = 0}) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
