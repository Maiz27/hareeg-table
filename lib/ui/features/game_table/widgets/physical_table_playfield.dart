import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../domain/classic_hareeg/rules/opening_rules.dart'
    show PlacedMeld;
import '../../../core/cards/card_state.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/cards/card_view.dart';
import '../../../core/theme/lounge_tokens.dart';
import 'opponent_seat_rails.dart';
import 'seat_meld_lane.dart';
import 'south_meld_controls.dart';
import 'table_center_area.dart';

export 'seat_meld_lane.dart'
    show
        TableMeldDropPredicate,
        TableMeldDropHandler,
        TableMeldRetractPredicate,
        TableMeldRetractHandler;

/// A legal meld option rendered as cards on the table, not as a command row.
@immutable
class TableMeldSuggestion {
  /// Creates a meld suggestion.
  const TableMeldSuggestion({required this.actionId, required this.cards});

  /// Controller action to run when this exact group is chosen.
  final String actionId;

  /// Physical cards in the option.
  final List<HareegCard> cards;
}

/// Physical table layout for the active Classic Hareeg round.
class PhysicalTablePlayfield extends StatelessWidget {
  /// Creates the table playfield.
  const PhysicalTablePlayfield({
    super.key,
    required this.theme,
    required this.stockCount,
    required this.discardPile,
    required this.topDiscard,
    required this.pendingDiscard,
    required this.cardCounts,
    required this.tableMelds,
    required this.southCards,
    required this.selectedIds,
    required this.onCardTap,
    required this.onCardLongPress,
    required this.onReorderHand,
    required this.canDiscardCard,
    required this.canPlayCardOnTable,
    required this.canPlaceMeldOnTable,
    required this.canPlayCardOnMeld,
    required this.canRetractMeld,
    required this.onDiscardCard,
    required this.onPlayCardOnTable,
    required this.onPlayCardOnMeld,
    required this.onRetractMeld,
    required this.canDrawStock,
    required this.canTakeDiscard,
    required this.canReturnDiscard,
    required this.canClaimFifty,
    required this.canReturnOpeningMelds,
    required this.onDrawStock,
    required this.onTakeDiscard,
    required this.onReturnDiscard,
    required this.onClaimFifty,
    required this.onReturnOpeningMelds,
    required this.fiftySecondsRemaining,
    required this.fiftyTotalSeconds,
    required this.fiftyPulse,
    required this.meldRequirement,
    required this.meldSelectionValue,
    required this.meldSelectionValid,
    required this.meldSelectionHasOpened,
    required this.onPlaySelectedMeld,
    required this.meldSuggestions,
    required this.showMeldSuggestions,
    required this.onMeldSuggestion,
    required this.isHumanTurn,
    required this.isCpuRunning,
    required this.currentSeat,
    required this.activeSeats,
  });

  /// Active card theme.
  final HareegCardTheme theme;

  /// Cards remaining in stock.
  final int stockCount;

  /// Face-up discard pile, ordered from oldest to newest.
  final List<HareegCard> discardPile;

  /// Top face-up discard.
  final HareegCard? topDiscard;

  /// Pending discard that must be used or returned.
  final HareegCard? pendingDiscard;

  /// Current hand size per seat.
  final Map<PlayerSeat, int> cardCounts;

  /// Melds on the table, grouped by owner.
  final Map<PlayerSeat, List<PlacedMeld>> tableMelds;

  /// South hand in display order.
  final List<HareegCard> southCards;

  /// Selected card ids in the human hand.
  final Set<String> selectedIds;

  /// Tap fallback for selecting cards.
  final ValueChanged<HareegCard> onCardTap;

  /// Long-press handler for inspecting a visible card.
  final ValueChanged<HareegCard> onCardLongPress;

  /// Player-initiated reorder inside the hand. Receives the dragged card
  /// and the target slot index in the displayed hand order; the orchestrator
  /// persists the change in its local hand order list.
  final void Function(HareegCard card, int targetIndex) onReorderHand;

  /// Whether a card can be dropped onto the discard pile.
  final bool Function(HareegCard card) canDiscardCard;

  /// Whether a card can be dropped onto the table meld surface (covers /
  /// replacements / new melds — used by the runtime to actually dispatch
  /// when the player releases on the lane).
  final bool Function(HareegCard card) canPlayCardOnTable;

  /// Whether a card can be dropped to place a NEW meld (no covers / no
  /// joker replacements). Used as the highlight predicate on the south
  /// seat's wide meld lane so the lane does not glow when the dragged card
  /// is only a cover candidate.
  final bool Function(HareegCard card) canPlaceMeldOnTable;

  /// Whether a card can be dropped onto a specific placed meld.
  final TableMeldDropPredicate canPlayCardOnMeld;

  /// Whether a specific placed meld can be taken back this turn.
  final TableMeldRetractPredicate canRetractMeld;

  /// Runs the discard/return-pending action for a dropped card.
  final ValueChanged<HareegCard> onDiscardCard;

  /// Runs a table play action for a dropped card or selected group.
  final ValueChanged<HareegCard> onPlayCardOnTable;

  /// Runs a cover/replacement action for a specific placed meld.
  final TableMeldDropHandler onPlayCardOnMeld;

  /// Runs the take-back action for a specific placed meld.
  final TableMeldRetractHandler onRetractMeld;

  /// True when stock can be drawn.
  final bool canDrawStock;

  /// True when the top discard can be taken.
  final bool canTakeDiscard;

  /// True when the pending discard can be returned.
  final bool canReturnDiscard;

  /// True when Fifty can be claimed.
  final bool canClaimFifty;

  /// True when staged opening melds can be taken back.
  final bool canReturnOpeningMelds;

  /// Draw callback.
  final VoidCallback onDrawStock;

  /// Take discard callback.
  final VoidCallback onTakeDiscard;

  /// Return pending discard callback.
  final VoidCallback onReturnDiscard;

  /// Fifty callback.
  final VoidCallback onClaimFifty;

  /// Return opening melds callback.
  final VoidCallback onReturnOpeningMelds;

  /// Seconds left in the Fifty window.
  final int? fiftySecondsRemaining;

  /// Total Fifty timer duration.
  final int fiftyTotalSeconds;

  /// One-shot Fifty pulse flag.
  final bool fiftyPulse;

  /// Current opening requirement.
  final int meldRequirement;

  /// Value of the currently selected meld when valid, else null.
  final int? meldSelectionValue;

  /// True when the selected cards form a single playable meld action.
  final bool meldSelectionValid;

  /// True when the south seat has already opened this round.
  final bool meldSelectionHasOpened;

  /// Tap handler that plays the currently selected meld, or null when no
  /// valid selection is in flight.
  final VoidCallback? onPlaySelectedMeld;

  /// Legal table meld options for the current selected cards.
  final List<TableMeldSuggestion> meldSuggestions;

  /// Whether suggestions are allowed by table-aid preferences.
  final bool showMeldSuggestions;

  /// Runs a suggested meld action.
  final ValueChanged<String> onMeldSuggestion;

  /// Whether the human seat can interact now.
  final bool isHumanTurn;

  /// Whether a CPU action loop is currently running.
  final bool isCpuRunning;

  /// Seat whose turn is active.
  final PlayerSeat currentSeat;

  /// Seats still active in the match.
  final Set<PlayerSeat> activeSeats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth;
        final tableHeight = constraints.maxHeight;
        final compact = tableHeight <= 360 || tableWidth <= 700;
        final tableCardSize = compact ? const Size(40, 56) : const Size(50, 70);
        final meldCardSize = compact ? const Size(32, 44) : const Size(38, 54);
        final sideMeldCardSize = compact
            ? const Size(28, 40)
            : const Size(34, 48);
        final handCardSize = compact ? const Size(36, 50) : const Size(48, 68);
        final opponentCardSize = compact
            ? const Size(26, 36)
            : const Size(32, 44);
        final sideRailWidth = compact ? 46.0 : 56.0;
        // Side control rail is intentionally small — it only carries the
        // Meld CTA. Sort lives in Settings now; the player rearranges by
        // dragging cards in their hand. Sizes match the reference's
        // unobtrusive bottom-right pill.
        final controlWidth = compact ? 60.0 : 72.0;
        final bottomHandHeight = handCardSize.height + (compact ? 12 : 18);
        final edgeInset = (tableWidth * 0.026)
            .clamp(compact ? 14.0 : 20.0, compact ? 30.0 : 52.0)
            .toDouble();
        final topInset = (tableHeight * 0.032)
            .clamp(compact ? 8.0 : 12.0, compact ? 16.0 : 28.0)
            .toDouble();
        // Stock pile lives at the literal bottom-left corner (see the PRD
        // wood reference). The hand starts to the right of the corner pile.
        // Everything above stock on the left edge belongs to the west seat
        // (rail + meld lane).
        final stockBottom = compact ? 6.0 : 10.0;
        final stockReservedHeight = tableCardSize.height + (compact ? 32 : 42);
        final southMeldBottom = handCardSize.height + (compact ? 2.0 : 6.0);
        final southMeldHeight = compact ? 50.0 : 60.0;
        // Side rail (opponent hand) shrinks to a compact deck-stack hint —
        // 5 backs in compact, 6 in regular — and is centered on the table's
        // vertical axis. Earlier versions anchored this under the north hand,
        // which made west/east drift upward instead of mirroring the fixed
        // four-seat geometry.
        final sideRailVisibleCount = compact ? 5 : 6;
        const sideRailGap = 16.0;
        final sideRailHeight =
            opponentCardSize.height + (sideRailVisibleCount - 1) * sideRailGap;
        final sideRailMinTop =
            topInset + opponentCardSize.height + (compact ? 8.0 : 12.0);
        final sideRailMaxTop =
            tableHeight -
            stockBottom -
            stockReservedHeight -
            sideRailHeight -
            (compact ? 8.0 : 12.0);
        final sideRailTop = ((tableHeight - sideRailHeight) * 0.5)
            .clamp(sideRailMinTop, math.max(sideRailMinTop, sideRailMaxTop))
            .toDouble();
        // West/east meld lanes use the full safe vertical budget between the
        // north hand and the south hand. The rail itself stays centered; the
        // meld lane should only scroll when it exhausts this whole side area.
        final sideMeldTop = topInset + (compact ? 2.0 : 4.0);
        final sideMeldBottomSafe = tableHeight - (compact ? 12.0 : 16.0);
        final sideMeldHeight = math.max(0.0, sideMeldBottomSafe - sideMeldTop);
        final sideMeldWidth = sideMeldCardSize.height + (compact ? 20.0 : 22.0);
        final sideMeldGap = compact ? 6.0 : 10.0;
        final horizontalMeldInset = (tableWidth * 0.25)
            .clamp(compact ? 126.0 : 210.0, compact ? 180.0 : 390.0)
            .toDouble();
        // Discard pile occupies a generous hit rectangle so the player can
        // drop within a wide forgiving zone around the visible pile.
        final pileWidth = tableCardSize.width + (compact ? 34 : 44);
        final pileHeight = tableCardSize.height + (compact ? 30 : 40);
        final discardHitWidth = pileWidth + (compact ? 60 : 90);
        final discardHitHeight = pileHeight + (compact ? 50 : 70);
        final discardLeft = (tableWidth - discardHitWidth) * 0.5;
        final discardTop = (tableHeight - discardHitHeight) * 0.5;
        final controlBottom = (tableHeight * 0.035)
            .clamp(compact ? 12.0 : 18.0, compact ? 24.0 : 34.0)
            .toDouble();
        final handRightInset =
            controlWidth + edgeInset + (compact ? 10.0 : 16.0);
        final handHorizontalInset = math.max(
          handRightInset,
          compact ? 70.0 : 96.0,
        );
        final meldSuggestionBottom = southMeldBottom + (compact ? 12.0 : 18.0);
        final fiftyDiameter = compact ? 42.0 : 54.0;
        final visibleDiscardLeft =
            discardLeft + (discardHitWidth - pileWidth) / 2;
        final visibleDiscardTop =
            discardTop + (discardHitHeight - pileHeight) / 2;
        final fiftyCueLeft =
            (visibleDiscardLeft + pileWidth - fiftyDiameter * 0.55)
                .clamp(0.0, tableWidth - fiftyDiameter)
                .toDouble();
        final fiftyCueTop = (visibleDiscardTop - fiftyDiameter * 0.35)
            .clamp(0.0, tableHeight - fiftyDiameter)
            .toDouble();
        final activeFiftySeconds = isHumanTurn ? fiftySecondsRemaining : null;

        // Discard drop is handled by [_DiscardPile] itself so a card released
        // ON the pile gets routed (the previous wide field rectangle was
        // hidden behind the pile's tap gesture detector and the drop
        // candidate never reached it).
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: topInset,
              left: 0,
              right: 0,
              child: OpponentHandRail(
                theme: theme,
                count: cardCounts[PlayerSeat.north] ?? 0,
                cardSize: opponentCardSize,
                active: currentSeat == PlayerSeat.north,
                thinking: isCpuRunning && currentSeat == PlayerSeat.north,
                eliminated: !activeSeats.contains(PlayerSeat.north),
                compact: compact,
              ),
            ),
            Positioned(
              left: edgeInset,
              top: sideRailTop,
              width: sideRailWidth,
              height: sideRailHeight,
              child: SizedBox.expand(
                key: const ValueKey('west-opponent-rail'),
                child: OpponentSideRail(
                  theme: theme,
                  count: cardCounts[PlayerSeat.west] ?? 0,
                  cardSize: opponentCardSize,
                  active: currentSeat == PlayerSeat.west,
                  thinking: isCpuRunning && currentSeat == PlayerSeat.west,
                  eliminated: !activeSeats.contains(PlayerSeat.west),
                  alignRight: false,
                  compact: compact,
                ),
              ),
            ),
            Positioned(
              right: edgeInset,
              top: sideRailTop,
              width: sideRailWidth,
              height: sideRailHeight,
              child: SizedBox.expand(
                key: const ValueKey('east-opponent-rail'),
                child: OpponentSideRail(
                  theme: theme,
                  count: cardCounts[PlayerSeat.east] ?? 0,
                  cardSize: opponentCardSize,
                  active: currentSeat == PlayerSeat.east,
                  thinking: isCpuRunning && currentSeat == PlayerSeat.east,
                  eliminated: !activeSeats.contains(PlayerSeat.east),
                  alignRight: true,
                  compact: compact,
                ),
              ),
            ),
            Positioned(
              left: compact ? 6 : 10,
              bottom: stockBottom,
              child: TableStockPile(
                theme: theme,
                count: stockCount,
                cardSize: tableCardSize,
                compact: compact,
                canDraw: isHumanTurn && canDrawStock,
                onDraw: onDrawStock,
              ),
            ),
            Positioned(
              top: discardTop,
              left: discardLeft,
              child: TableDiscardPile(
                theme: theme,
                discardPile: discardPile,
                topDiscard: topDiscard,
                pendingDiscard: pendingDiscard,
                cardSize: tableCardSize,
                canTake: isHumanTurn && canTakeDiscard,
                canReturn: isHumanTurn && canReturnDiscard,
                onTake: onTakeDiscard,
                onReturn: onReturnDiscard,
                onCardLongPress: onCardLongPress,
                canAcceptDiscard: canDiscardCard,
                onAcceptDiscard: onDiscardCard,
                compact: compact,
              ),
            ),
            Positioned(
              top: topInset + opponentCardSize.height + (compact ? 18 : 24),
              left: horizontalMeldInset,
              right: horizontalMeldInset,
              height: compact ? 58 : 70,
              child: SeatMeldLane(
                theme: theme,
                owner: PlayerSeat.north,
                melds: tableMelds[PlayerSeat.north] ?? const <PlacedMeld>[],
                cardSize: meldCardSize,
                compact: compact,
                canAcceptTable: (_) => false,
                onAcceptTable: onPlayCardOnTable,
                canAcceptMeld: canPlayCardOnMeld,
                onAcceptMeld: onPlayCardOnMeld,
                canRetractMeld: canRetractMeld,
                onRetractMeld: onRetractMeld,
                onCardLongPress: onCardLongPress,
                stackVertically: false,
              ),
            ),
            Positioned(
              left: edgeInset + sideRailWidth + sideMeldGap,
              top: sideMeldTop,
              width: sideMeldWidth,
              height: sideMeldHeight,
              child: SizedBox.expand(
                key: const ValueKey('west-meld-lane'),
                child: SeatMeldLane(
                  theme: theme,
                  owner: PlayerSeat.west,
                  melds: tableMelds[PlayerSeat.west] ?? const <PlacedMeld>[],
                  cardSize: sideMeldCardSize,
                  compact: compact,
                  canAcceptTable: (_) => false,
                  onAcceptTable: onPlayCardOnTable,
                  canAcceptMeld: canPlayCardOnMeld,
                  onAcceptMeld: onPlayCardOnMeld,
                  canRetractMeld: canRetractMeld,
                  onRetractMeld: onRetractMeld,
                  onCardLongPress: onCardLongPress,
                  stackVertically: false,
                  quarterTurns: 1,
                ),
              ),
            ),
            Positioned(
              right: edgeInset + sideRailWidth + sideMeldGap,
              top: sideMeldTop,
              width: sideMeldWidth,
              height: sideMeldHeight,
              child: SizedBox.expand(
                key: const ValueKey('east-meld-lane'),
                child: SeatMeldLane(
                  theme: theme,
                  owner: PlayerSeat.east,
                  melds: tableMelds[PlayerSeat.east] ?? const <PlacedMeld>[],
                  cardSize: sideMeldCardSize,
                  compact: compact,
                  canAcceptTable: (_) => false,
                  onAcceptTable: onPlayCardOnTable,
                  canAcceptMeld: canPlayCardOnMeld,
                  onAcceptMeld: onPlayCardOnMeld,
                  canRetractMeld: canRetractMeld,
                  onRetractMeld: onRetractMeld,
                  onCardLongPress: onCardLongPress,
                  stackVertically: false,
                  quarterTurns: 3,
                ),
              ),
            ),
            Positioned(
              left: horizontalMeldInset,
              right: horizontalMeldInset,
              bottom: southMeldBottom,
              height: southMeldHeight,
              child: SeatMeldLane(
                theme: theme,
                owner: PlayerSeat.south,
                melds: tableMelds[PlayerSeat.south] ?? const <PlacedMeld>[],
                cardSize: meldCardSize,
                compact: compact,
                // Lane glow is reserved for new-meld drops; covers and
                // joker replacements light up the per-meld stack instead.
                canAcceptTable: canPlaceMeldOnTable,
                onAcceptTable: onPlayCardOnTable,
                canAcceptMeld: canPlayCardOnMeld,
                onAcceptMeld: onPlayCardOnMeld,
                canRetractMeld: canRetractMeld,
                onRetractMeld: onRetractMeld,
                onCardLongPress: onCardLongPress,
                stackVertically: false,
              ),
            ),
            if (activeFiftySeconds != null)
              Positioned(
                left: fiftyCueLeft,
                top: fiftyCueTop,
                child: TableFiftyCue(
                  secondsRemaining: activeFiftySeconds,
                  totalSeconds: fiftyTotalSeconds,
                  pulse: fiftyPulse,
                  diameter: fiftyDiameter,
                  canClaim: canClaimFifty,
                  onClaim: onClaimFifty,
                ),
              ),
            // Meld picker rack stays close to the south meld lane; it is a
            // transient popover and can overlap the lane briefly.
            if (showMeldSuggestions && meldSuggestions.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: meldSuggestionBottom,
                child: Center(
                  child: MeldSuggestionRack(
                    theme: theme,
                    suggestions: meldSuggestions,
                    cardSize: compact ? const Size(26, 36) : const Size(30, 42),
                    onTapSuggestion: onMeldSuggestion,
                    onCardLongPress: onCardLongPress,
                  ),
                ),
              ),
            Positioned(
              right: edgeInset,
              bottom: controlBottom,
              width: controlWidth,
              child: SouthSideControls(
                meldRequirement: meldRequirement,
                meldSelectionValue: meldSelectionValue,
                meldSelectionValid: meldSelectionValid,
                meldSelectionHasOpened: meldSelectionHasOpened,
                onPlaySelectedMeld: onPlaySelectedMeld,
                compact: compact,
                canReturnOpeningMelds: isHumanTurn && canReturnOpeningMelds,
                onReturnOpeningMelds: onReturnOpeningMelds,
              ),
            ),
            Positioned(
              left: handHorizontalInset,
              right: handHorizontalInset,
              bottom: compact ? 0 : 2,
              height: bottomHandHeight,
              child: _HumanTurnAura(
                active: isHumanTurn,
                child: _HumanHandFan(
                  theme: theme,
                  cards: southCards,
                  selectedIds: selectedIds,
                  pendingId: pendingDiscard?.id,
                  cardSize: handCardSize,
                  draggable: true,
                  onTap: onCardTap,
                  onLongPress: onCardLongPress,
                  onReorder: onReorderHand,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}



class _HumanHandFan extends StatelessWidget {
  const _HumanHandFan({
    required this.theme,
    required this.cards,
    required this.selectedIds,
    required this.pendingId,
    required this.cardSize,
    required this.draggable,
    required this.onTap,
    required this.onLongPress,
    required this.onReorder,
  });

  final HareegCardTheme theme;
  final List<HareegCard> cards;
  final Set<String> selectedIds;
  final String? pendingId;
  final Size cardSize;
  final bool draggable;
  final ValueChanged<HareegCard> onTap;
  final ValueChanged<HareegCard> onLongPress;

  /// Called when the player drops `card` onto the slot at `targetIndex` in
  /// the displayed hand order. The orchestrator updates its display order
  /// accordingly; the engine's hand list is unchanged.
  final void Function(HareegCard card, int targetIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = cards.length;
        // Spread the hand across as much of the available width as possible
        // while keeping enough overlap that the rank corner of each card
        // remains tappable. The reference layout keeps ~18-25% overlap when
        // there is room, which means the player can scan their hand at a
        // glance without scrolling.
        final minGap = cardSize.width * 0.42;
        final preferredGap = cardSize.width * 0.78;
        final available = math.max(0.0, constraints.maxWidth - 8);
        final fittedGap = count <= 1
            ? 0.0
            : ((available - cardSize.width) / (count - 1))
                  .clamp(minGap, preferredGap)
                  .toDouble();
        final stripWidth = cardSize.width + math.max(0, count - 1) * fittedGap;
        final canvasWidth = math.max(stripWidth, available);
        final start = math.max(0.0, (canvasWidth - stripWidth) / 2);
        final trailingDropWidth = cardSize.width * 0.7;
        final trailingDropLeft =
            start + math.max(0, count - 1) * fittedGap + cardSize.width;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: SizedBox(
            width: canvasWidth + 8 + trailingDropWidth,
            height: constraints.maxHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < cards.length; i++)
                  Positioned(
                    key: ValueKey('south-hand-position-${cards[i].id}'),
                    left: start + i * fittedGap,
                    bottom: 2,
                    child: DragTarget<HareegCard>(
                      key: ValueKey('south-hand-drop-${cards[i].id}'),
                      onWillAcceptWithDetails: (details) =>
                          draggable && details.data.id != cards[i].id,
                      onAcceptWithDetails: (details) =>
                          onReorder(details.data, i),
                      builder: (context, candidates, _) {
                        return _DraggableHandCard(
                          theme: theme,
                          card: cards[i],
                          selected: selectedIds.contains(cards[i].id),
                          pending: pendingId == cards[i].id,
                          insertGapBefore: candidates.isNotEmpty,
                          size: cardSize,
                          draggable: draggable,
                          onTap: () => onTap(cards[i]),
                          onLongPress: () => onLongPress(cards[i]),
                        );
                      },
                    ),
                  ),
                Positioned(
                  left: trailingDropLeft,
                  bottom: 2,
                  width: trailingDropWidth,
                  height: cardSize.height,
                  child: DragTarget<HareegCard>(
                    key: const ValueKey('south-hand-trailing-drop-target'),
                    onWillAcceptWithDetails: (details) =>
                        draggable && details.data.id != cards.last.id,
                    onAcceptWithDetails: (details) =>
                        onReorder(details.data, cards.length),
                    builder: (context, candidates, _) {
                      return const SizedBox.expand();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DraggableHandCard extends StatelessWidget {
  const _DraggableHandCard({
    required this.theme,
    required this.card,
    required this.selected,
    required this.pending,
    required this.size,
    required this.draggable,
    required this.onTap,
    required this.onLongPress,
    this.insertGapBefore = false,
  });

  final HareegCardTheme theme;
  final HareegCard card;
  final bool selected;
  final bool pending;
  final Size size;
  final bool draggable;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// True when another card is being dragged over this position; the card
  /// shifts right slightly so the player can see where the dropped card
  /// will land.
  final bool insertGapBefore;

  @override
  Widget build(BuildContext context) {
    final state = pending
        ? CardVisualState.pending
        : selected
        ? CardVisualState.selected
        : CardVisualState.normal;
    final dx = insertGapBefore ? size.width * 0.35 : 0.0;
    final dy = selected ? -8.0 : 0.0;
    final face = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(dx, dy, 0),
        child: HareegCardView(
          theme: theme,
          card: card,
          size: size,
          visualState: state,
        ),
      ),
    );

    if (!draggable) return face;
    return Draggable<HareegCard>(
      key: ValueKey('south-hand-drag-${card.id}'),
      data: card,
      maxSimultaneousDrags: 1,
      rootOverlay: true,
      feedback: Material(
        color: Colors.transparent,
        elevation: 10,
        borderRadius: BorderRadius.circular(LoungeTokens.radiusCard),
        child: Transform.scale(
          scale: 1.07,
          child: HareegCardView(
            theme: theme,
            card: card,
            size: size,
            visualState: state,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.24, child: face),
      child: face,
    );
  }
}

/// No-op pass-through that used to draw a turn indicator. Removed per
/// player feedback: the active CTAs (Meld chip, stock + discard rings,
/// selected-card lift) carry the turn cue without an extra accent.
class _HumanTurnAura extends StatelessWidget {
  const _HumanTurnAura({required this.active, required this.child});

  // ignore: unused_element_parameter
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
