import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';
import 'package:hareeg_table/ui/core/cards/card_theme_registry.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/physical_table_playfield.dart';

/// Regression test for the placed-meld frame's trailing dead space: the
/// take-back ring around a retractable meld used to extend past the last
/// card (the meld body reserved slack for the value badge), so the gold
/// frame showed empty space on the fan's high side — the same dead-space
/// family as the suggestion rack's trailing separator, fixed in HT-46 but
/// not carried to the placed-meld stack.
void main() {
  testWidgets('the retractable meld frame ends at the last card', (
    tester,
  ) async {
    final cards = [
      _card(CardRank.king, CardSuit.spades),
      _card(CardRank.king, CardSuit.diamonds),
      _card(CardRank.king, CardSuit.hearts),
    ];
    await _pumpPlayfield(
      tester,
      tableMelds: {
        PlayerSeat.south: [PlacedMeld.fromCards(cards)],
      },
      canRetract: true,
    );

    final stackRect = tester.getRect(
      find.byKey(const ValueKey('table-meld-south-0-normal')),
    );
    // The fan overlaps left-to-right, so the last card's right edge is the
    // fan's true extent — the frame must stop there, not at badge slack.
    final lastCardRect = tester.getRect(
      find.bySemanticsLabel('King of Hearts'),
    );

    expect(
      stackRect.right,
      moreOrLessEquals(lastCardRect.right, epsilon: 0.5),
      reason:
          'the meld frame paints ${stackRect.right - lastCardRect.right}px '
          'past the last card — the ring shows trailing dead space',
    );
  });
}

Future<void> _pumpPlayfield(
  WidgetTester tester, {
  Map<PlayerSeat, List<PlacedMeld>> tableMelds = const {},
  bool canRetract = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 500,
          child: PhysicalTablePlayfield(
            theme: CardThemeRegistry.byId(null),
            stockCount: 30,
            discardPile: const [],
            topDiscard: null,
            pendingDiscard: null,
            cardCounts: const {
              PlayerSeat.south: 4,
              PlayerSeat.east: 14,
              PlayerSeat.north: 14,
              PlayerSeat.west: 14,
            },
            tableMelds: tableMelds,
            southCards: [
              _card(CardRank.two, CardSuit.spades),
              _card(CardRank.three, CardSuit.spades),
              _card(CardRank.four, CardSuit.spades),
              _card(CardRank.five, CardSuit.spades),
            ],
            selectedIds: const {},
            onCardTap: (_) {},
            onCardLongPress: (_) {},
            onReorderHand: (_, _) {},
            canDiscardCard: (_) => false,
            canPlayCardOnTable: (_) => false,
            canPlaceMeldOnTable: (_) => false,
            canPlayCardOnMeld: (_, _) => false,
            canRetractMeld: (_, _) => canRetract,
            onDiscardCard: (_) {},
            onPlayCardOnTable: (_) {},
            onPlayCardOnMeld: (_, _) {},
            onRetractMeld: (_, _) {},
            canDrawStock: false,
            canTakeDiscard: false,
            canReturnDiscard: false,
            canClaimFifty: false,
            canReturnOpeningMelds: canRetract,
            onDrawStock: () {},
            onTakeDiscard: () {},
            onReturnDiscard: () {},
            onClaimFifty: () {},
            onReturnOpeningMelds: () {},
            fiftySecondsRemaining: null,
            fiftyTotalSeconds: 50,
            fiftyPulse: false,
            meldRequirement: 51,
            meldSelectionValue: null,
            meldSelectionValid: false,
            meldSelectionHasOpened: false,
            onPlaySelectedMeld: null,
            meldSuggestions: const [],
            showMeldSuggestions: false,
            onMeldSuggestion: (_) {},
            isHumanTurn: true,
            isCpuRunning: false,
            currentSeat: PlayerSeat.south,
            activeSeats: PlayerSeat.values.toSet(),
          ),
        ),
      ),
    ),
  );
}

HareegCard _card(CardRank rank, CardSuit suit) =>
    HareegCard.standard(rank: rank, suit: suit, deckIndex: 0);
