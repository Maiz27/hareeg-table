import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';
import 'package:hareeg_table/ui/core/cards/card_theme_registry.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/physical_table_playfield.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/south_hand_fan.dart';

/// Regression tests for the meld-expand visual crop:
/// tapping a placed meld used to enlarge the cards but the bottom edge of
/// the expanded stack was clipped where the south meld lane met the south
/// hand fan. These tests pin down "the expansion is fully visible inside
/// the playfield" — not just "the expanded key is reached".
void main() {
  testWidgets(
    'south meld expansion stays inside the playfield (no bottom crop)',
    (tester) async {
      // Five-card sequence so the expanded fan is visibly different from the
      // collapsed stack.
      final cards = [
        _card(CardRank.four, CardSuit.clubs, 110),
        _card(CardRank.five, CardSuit.clubs, 110),
        _card(CardRank.six, CardSuit.clubs, 110),
        _card(CardRank.seven, CardSuit.clubs, 110),
        _card(CardRank.eight, CardSuit.clubs, 110),
      ];
      final meld = PlacedMeld.fromCards(cards);

      const playfieldSize = Size(900, 500);
      await _pumpPlayfield(
        tester,
        tableMelds: {
          PlayerSeat.south: [meld],
        },
        size: playfieldSize,
      );

      await tester.tap(
        find.byKey(const ValueKey('table-meld-south-0-normal')),
      );
      await tester.pumpAndSettle();

      final expanded = find.byKey(
        const ValueKey('table-meld-south-0-expanded'),
      );
      expect(expanded, findsOneWidget);

      // The expanded meld cards must not overlap the south hand fan and must
      // not be cropped by the lane's scroll viewport. We assert two things:
      //
      // 1. The card's painted bottom edge is at or above the south hand
      //    fan's top edge (the lane boundary the user reports as the crop).
      // 2. The card's visual bottom is inside the south meld lane's
      //    ancestor clip rect — `tester.getRect` returns the logical
      //    render-box rect, which doesn't know about ancestor clipping,
      //    so we cross-check against `RenderObject.describeApproximatePaintClip`
      //    of every clip ancestor.
      final southHandRect = tester.getRect(find.byType(SouthHandFan));

      for (final label in const [
        'Four of Clubs',
        'Five of Clubs',
        'Six of Clubs',
        'Seven of Clubs',
        'Eight of Clubs',
      ]) {
        final cardFinder = find.bySemanticsLabel(label);
        expect(cardFinder, findsOneWidget, reason: 'meld card $label missing');

        final cardRect = tester.getRect(cardFinder);

        // 1. Painted bottom edge of the expanded card stays above the south
        // hand fan top edge. If it dips below, the user sees the meld
        // cropped/eaten by the hand area.
        expect(
          cardRect.bottom,
          lessThanOrEqualTo(southHandRect.top),
          reason:
              '$label expanded card extends into the south hand area. '
              'card=$cardRect southHand=$southHandRect — this is the '
              "user-reported 'cropped towards the bottom' regression.",
        );

        // 2. The card is fully inside every ancestor clip rect — if a
        // SingleChildScrollView (or similar) clips it, the painted region
        // is smaller than the logical rect and the card is visibly cropped.
        _expectNotClippedByAncestors(tester, cardFinder);
      }
    },
  );

  testWidgets(
    'east opponent meld expansion stays inside the playfield',
    (tester) async {
      final cards = [
        _card(CardRank.queen, CardSuit.hearts, 111),
        _card(CardRank.queen, CardSuit.diamonds, 111),
        _card(CardRank.queen, CardSuit.clubs, 111),
        _card(CardRank.queen, CardSuit.spades, 111),
      ];
      final meld = PlacedMeld.fromCards(cards);

      const playfieldSize = Size(900, 500);
      await _pumpPlayfield(
        tester,
        tableMelds: {
          PlayerSeat.east: [meld],
        },
        size: playfieldSize,
      );

      await tester.tap(
        find.byKey(const ValueKey('table-meld-east-0-normal')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('table-meld-east-0-expanded')),
        findsOneWidget,
      );

      // The east meld is rotated; its expansion grows along the visual
      // vertical axis. Assert each card is not cropped by an ancestor.
      for (final label in const [
        'Queen of Hearts',
        'Queen of Diamonds',
        'Queen of Clubs',
        'Queen of Spades',
      ]) {
        final cardFinder = find.bySemanticsLabel(label);
        expect(cardFinder, findsOneWidget, reason: 'opponent card $label missing');
        _expectNotClippedByAncestors(tester, cardFinder);
      }
    },
  );
}

/// Asserts that the widget under [finder] is fully inside every clipping
/// ancestor's clip rect. We walk up the render tree, collecting clip rects
/// from `describeApproximatePaintClip`, and require the widget's painted
/// bounds (its own size) to fit inside each one.
void _expectNotClippedByAncestors(WidgetTester tester, Finder finder) {
  final RenderBox box = tester.renderObject<RenderBox>(finder);
  final boxRect = box.localToGlobal(Offset.zero) & box.size;
  RenderObject? current = box.parent;
  RenderObject? lastChild = box;
  while (current != null) {
    final clip = current.describeApproximatePaintClip(lastChild!);
    if (clip != null) {
      // Translate the local clip rect into global coordinates via the
      // ancestor's transform.
      final transform = current.getTransformTo(null);
      final globalClip = MatrixUtils.transformRect(transform, clip);
      // Allow sub-pixel rounding tolerance; we are catching multi-pixel
      // crops here, not anti-alias bleed.
      final inflated = globalClip.inflate(0.5);
      expect(
        inflated.contains(boxRect.topLeft) &&
            inflated.contains(
              Offset(boxRect.right - 0.001, boxRect.bottom - 0.001),
            ),
        isTrue,
        reason:
            'Card painted at $boxRect is clipped by ancestor '
            '${current.runtimeType} clip $globalClip — the expanded meld '
            'is being cropped at the lane boundary.',
      );
    }
    lastChild = current;
    current = current.parent;
  }
}

Future<void> _pumpPlayfield(
  WidgetTester tester, {
  Map<PlayerSeat, List<PlacedMeld>> tableMelds = const {},
  Size size = const Size(900, 500),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: size.width,
          height: size.height,
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
              _card(CardRank.two, CardSuit.spades, 99),
              _card(CardRank.three, CardSuit.spades, 99),
              _card(CardRank.four, CardSuit.spades, 99),
              _card(CardRank.five, CardSuit.spades, 99),
            ],
            selectedIds: const {},
            onCardTap: (_) {},
            onCardLongPress: (_) {},
            onReorderHand: (_, _) {},
            canDiscardCard: (_) => false,
            canPlayCardOnTable: (_) => false,
            canPlaceMeldOnTable: (_) => false,
            canPlayCardOnMeld: (_, _, _) => false,
            canRetractMeld: (_, _) => false,
            onDiscardCard: (_) {},
            onPlayCardOnTable: (_) {},
            onPlayCardOnMeld: (_, _, _) {},
            onRetractMeld: (_, _) {},
            canDrawStock: false,
            canTakeDiscard: false,
            canReturnDiscard: false,
            canClaimFifty: false,
            canReturnOpeningMelds: false,
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
            isHumanTurn: false,
            isCpuRunning: false,
            currentSeat: PlayerSeat.south,
            activeSeats: PlayerSeat.values.toSet(),
          ),
        ),
      ),
    ),
  );
}

HareegCard _card(CardRank rank, CardSuit suit, int deckIndex) =>
    HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
