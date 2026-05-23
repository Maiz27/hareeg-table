import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/features/game_table/table_hand_interaction_state.dart';

void main() {
  group('ClassicHareegHandInteractionState', () {
    test('reset seeds display order from the requested sort mode', () {
      final fiveClubs = _card(CardRank.five, CardSuit.clubs, 1);
      final threeSpades = _card(CardRank.three, CardSuit.spades, 1);
      final threeHearts = _card(CardRank.three, CardSuit.hearts, 1);
      final state = ClassicHareegHandInteractionState();

      state.resetFromHand([
        fiveClubs,
        threeSpades,
        threeHearts,
      ], HandSortMode.byRank);

      expect(state.displayOrder, [
        threeHearts.id,
        threeSpades.id,
        fiveClubs.id,
      ]);
    });

    test('selected card ids are exposed in hand order, not tap order', () {
      final first = _card(CardRank.seven, CardSuit.clubs, 2);
      final second = _card(CardRank.eight, CardSuit.clubs, 2);
      final third = _card(CardRank.nine, CardSuit.clubs, 2);
      final state = ClassicHareegHandInteractionState()
        ..resetFromHand([first, second, third], HandSortMode.manual)
        ..toggleSelection(third)
        ..toggleSelection(first)
        ..toggleSelection(second);

      final snapshot = state.reconcile([first, second, third]);

      expect(snapshot.selectedIds, {first.id, second.id, third.id});
      expect(snapshot.selectedCardIds, [first.id, second.id, third.id]);
    });

    test('reconcile appends new cards and prunes missing selections', () {
      final removed = _card(CardRank.two, CardSuit.diamonds, 3);
      final kept = _card(CardRank.three, CardSuit.diamonds, 3);
      final added = _card(CardRank.four, CardSuit.diamonds, 3);
      final state = ClassicHareegHandInteractionState()
        ..resetFromHand([removed, kept], HandSortMode.manual)
        ..toggleSelection(removed)
        ..toggleSelection(kept);

      final snapshot = state.reconcile([kept, added]);

      expect(snapshot.orderedCards.map((card) => card.id), [kept.id, added.id]);
      expect(snapshot.selectedIds, {kept.id});
      expect(snapshot.selectedCardIds, [kept.id]);
      expect(state.displayOrder, [kept.id, added.id]);
    });

    test(
      'reorder updates display order and selected ids follow that order',
      () {
        final first = _card(CardRank.four, CardSuit.hearts, 4);
        final second = _card(CardRank.five, CardSuit.hearts, 4);
        final third = _card(CardRank.six, CardSuit.hearts, 4);
        final state = ClassicHareegHandInteractionState()
          ..resetFromHand([first, second, third], HandSortMode.manual)
          ..toggleSelection(first)
          ..toggleSelection(second)
          ..toggleSelection(third);

        final changed = state.reorder(first, 3);
        final snapshot = state.reconcile([first, second, third]);

        expect(changed, isTrue);
        expect(snapshot.orderedCards.map((card) => card.id), [
          second.id,
          third.id,
          first.id,
        ]);
        expect(snapshot.selectedCardIds, [second.id, third.id, first.id]);
      },
    );

    test(
      'action clearing preserves selection for draw and clears table play',
      () {
        final first = _card(CardRank.ten, CardSuit.spades, 5);
        final second = _card(CardRank.jack, CardSuit.spades, 5);
        final third = _card(CardRank.queen, CardSuit.spades, 5);
        final state = ClassicHareegHandInteractionState()
          ..resetFromHand([first, second, third], HandSortMode.manual)
          ..toggleSelection(first)
          ..toggleSelection(second)
          ..toggleSelection(third);

        state.clearSelectionForAction(ClassicHareegActionIds.drawStock);
        expect(state.reconcile([first, second, third]).selectedCardIds, [
          first.id,
          second.id,
          third.id,
        ]);

        state.clearSelectionForAction(
          ClassicHareegActionIds.playMeldActionId([
            first.id,
            second.id,
            third.id,
          ]),
        );

        expect(
          state.reconcile([first, second, third]).selectedCardIds,
          isEmpty,
        );
      },
    );
  });

  group('HandSorting', () {
    test('sorts by suit before rank in suit mode', () {
      final heartsFour = _card(CardRank.four, CardSuit.hearts, 6);
      final clubsKing = _card(CardRank.king, CardSuit.clubs, 6);
      final clubsTwo = _card(CardRank.two, CardSuit.clubs, 6);

      final sorted = HandSorting.sort([
        heartsFour,
        clubsKing,
        clubsTwo,
      ], HandSortMode.bySuit);

      expect(sorted.map((card) => card.id), [
        clubsTwo.id,
        clubsKing.id,
        heartsFour.id,
      ]);
    });
  });
}

HareegCard _card(CardRank rank, CardSuit suit, int deckIndex) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
