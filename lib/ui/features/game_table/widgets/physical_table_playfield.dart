import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../domain/classic_hareeg/rules/opening_rules.dart'
    show PlacedMeld;
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_state.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/cards/card_view.dart';
import '../../../core/theme/lounge_tokens.dart';
import 'fifty_ring.dart';
import 'opponent_seat_rails.dart';

typedef TableMeldDropPredicate =
    bool Function(HareegCard card, PlayerSeat owner, int meldIndex);

typedef TableMeldDropHandler =
    void Function(HareegCard card, PlayerSeat owner, int meldIndex);

typedef TableMeldRetractPredicate =
    bool Function(PlayerSeat owner, int meldIndex);

typedef TableMeldRetractHandler =
    void Function(PlayerSeat owner, int meldIndex);

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
              child: _StockPile(
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
              child: _DiscardPile(
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
              child: _SeatMeldLane(
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
                child: _SeatMeldLane(
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
                child: _SeatMeldLane(
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
              child: _SeatMeldLane(
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
                child: _FiftyCue(
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
                  child: _MeldSuggestionRack(
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
              child: _SideControls(
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

class _StockPile extends StatelessWidget {
  const _StockPile({
    required this.theme,
    required this.count,
    required this.cardSize,
    required this.compact,
    required this.canDraw,
    required this.onDraw,
  });

  final HareegCardTheme theme;
  final int count;
  final Size cardSize;
  final bool compact;
  final bool canDraw;
  final VoidCallback onDraw;

  @override
  Widget build(BuildContext context) {
    // Stock pile: card stack with the remaining-count badge overlaid on top
    // so the corner reads as a single object instead of pile + label.
    return Tooltip(
      message: context.strings.drawStock,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canDraw ? onDraw : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          opacity: canDraw ? 1 : 0.58,
          child: SizedBox(
            width: cardSize.width + 12,
            height: cardSize.height + 10,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 2; i >= 0; i--)
                  Positioned(
                    left: i * 3,
                    top: (2 - i) * 3,
                    child: HareegCardView(
                      theme: theme,
                      card: _backSeed(i + 10),
                      faceDown: true,
                      size: cardSize,
                      visualState: canDraw
                          ? CardVisualState.coverTarget
                          : CardVisualState.normal,
                    ),
                  ),
                Positioned(
                  top: 4,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _CountBadge(value: '$count', compact: compact),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscardPile extends StatelessWidget {
  const _DiscardPile({
    required this.theme,
    required this.discardPile,
    required this.topDiscard,
    required this.pendingDiscard,
    required this.cardSize,
    required this.canTake,
    required this.canReturn,
    required this.onTake,
    required this.onReturn,
    required this.canAcceptDiscard,
    required this.onAcceptDiscard,
    required this.onCardLongPress,
    required this.compact,
  });

  final HareegCardTheme theme;
  final List<HareegCard> discardPile;
  final HareegCard? topDiscard;
  final HareegCard? pendingDiscard;
  final Size cardSize;
  final bool canTake;
  final bool canReturn;
  final VoidCallback onTake;
  final VoidCallback onReturn;
  final bool Function(HareegCard card) canAcceptDiscard;
  final ValueChanged<HareegCard> onAcceptDiscard;
  final ValueChanged<HareegCard> onCardLongPress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // We show at most two cards: the prior discard as a quiet ghost below
    // and the active top card (or pending discard) above it. This matches
    // the reference's clean centre — players don't need to see the whole
    // discard history at the table.
    final history = discardPile;
    final topCard = pendingDiscard ?? topDiscard;
    HareegCard? ghostCard;
    if (pendingDiscard != null) {
      ghostCard = history.isNotEmpty ? history.last : null;
    } else if (history.length >= 2) {
      ghostCard = history[history.length - 2];
    }
    final pileWidth = cardSize.width + (compact ? 34 : 44);
    final pileHeight = cardSize.height + (compact ? 30 : 40);
    // Drop area extends slightly past the visible pile so the player does not
    // have to land on exact pixels but still cleanly excludes the centre
    // felt. This is the ONLY discard DragTarget in the playfield, so a card
    // released on the pile gets routed correctly.
    // The drop hit area is intentionally larger than the visible pile so
    // the player doesn't need pixel-precise aim — any release within the
    // generous box discards.
    final hitWidth = pileWidth + (compact ? 60 : 90);
    final hitHeight = pileHeight + (compact ? 50 : 70);
    return DragTarget<HareegCard>(
      key: const ValueKey('discard-pile-drop-target'),
      onWillAcceptWithDetails: (details) => canAcceptDiscard(details.data),
      onAcceptWithDetails: (details) => onAcceptDiscard(details.data),
      builder: (context, candidates, _) {
        final hot = candidates.isNotEmpty;
        return SizedBox(
          width: hitWidth,
          height: hitHeight,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Drop ring stays close to the visible pile so the player
              // sees where the card will land; the actual hit area is the
              // wider SizedBox above.
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                width: cardSize.width + (hot ? 34 : 20),
                height: cardSize.height + (hot ? 34 : 20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hot
                      ? LoungeTokens.goldAccent.withValues(alpha: 0.12)
                      : LoungeTokens.coffeeCharcoal.withValues(alpha: 0.06),
                  border: Border.all(
                    color: hot
                        ? LoungeTokens.goldAccent.withValues(alpha: 0.6)
                        : Colors.transparent,
                    width: 1.4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: hot
                          ? LoungeTokens.goldAccent.withValues(alpha: 0.18)
                          : Colors.black.withValues(alpha: 0.18),
                      blurRadius: hot ? 18 : 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: pendingDiscard != null && canReturn
                    ? onReturn
                    : canTake
                    ? onTake
                    : null,
                onLongPress: topCard == null
                    ? null
                    : () => onCardLongPress(topCard),
                child: SizedBox.expand(
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      if (topCard == null)
                        _EmptyDiscard(size: cardSize)
                      else ...[
                        if (ghostCard != null)
                          Transform.translate(
                            offset: Offset(compact ? -8 : -10, compact ? 4 : 6),
                            child: Transform.rotate(
                              angle: -0.06,
                              child: Opacity(
                                opacity: 0.45,
                                child: HareegCardView(
                                  theme: theme,
                                  card: ghostCard,
                                  size: cardSize,
                                ),
                              ),
                            ),
                          ),
                        Transform.translate(
                          offset: Offset(0, pendingDiscard != null ? -6 : -2),
                          child: Transform.rotate(
                            angle: pendingDiscard != null ? -0.04 : 0.03,
                            child: HareegCardView(
                              theme: theme,
                              card: topCard,
                              size: cardSize,
                              visualState: pendingDiscard != null
                                  ? CardVisualState.pending
                                  : canTake
                                  ? CardVisualState.coverTarget
                                  : CardVisualState.normal,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FiftyCue extends StatelessWidget {
  const _FiftyCue({
    required this.secondsRemaining,
    required this.totalSeconds,
    required this.pulse,
    required this.diameter,
    required this.canClaim,
    required this.onClaim,
  });

  final int secondsRemaining;
  final int totalSeconds;
  final bool pulse;
  final double diameter;
  final bool canClaim;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('fifty-cue'),
      behavior: HitTestBehavior.opaque,
      onTap: canClaim ? onClaim : null,
      child: FiftyRing(
        secondsRemaining: secondsRemaining,
        totalSeconds: totalSeconds,
        pulse: pulse,
        diameter: diameter,
      ),
    );
  }
}

class _EmptyDiscard extends StatelessWidget {
  const _EmptyDiscard({required this.size});

  final Size size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.22),
          width: 1.2,
        ),
      ),
    );
  }
}

class _SeatMeldLane extends StatefulWidget {
  const _SeatMeldLane({
    required this.theme,
    required this.owner,
    required this.melds,
    required this.cardSize,
    required this.compact,
    required this.canAcceptTable,
    required this.onAcceptTable,
    required this.canAcceptMeld,
    required this.onAcceptMeld,
    required this.canRetractMeld,
    required this.onRetractMeld,
    required this.onCardLongPress,
    required this.stackVertically,
    this.quarterTurns = 0,
  });

  final HareegCardTheme theme;
  final PlayerSeat owner;
  final List<PlacedMeld> melds;
  final Size cardSize;
  final bool compact;
  final bool Function(HareegCard card) canAcceptTable;
  final ValueChanged<HareegCard> onAcceptTable;
  final TableMeldDropPredicate canAcceptMeld;
  final TableMeldDropHandler onAcceptMeld;
  final TableMeldRetractPredicate canRetractMeld;
  final TableMeldRetractHandler onRetractMeld;
  final ValueChanged<HareegCard> onCardLongPress;
  final bool stackVertically;
  final int quarterTurns;

  @override
  State<_SeatMeldLane> createState() => _SeatMeldLaneState();
}

class _SeatMeldLaneState extends State<_SeatMeldLane> {
  int? _expandedMeldIndex;

  @override
  void didUpdateWidget(covariant _SeatMeldLane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.owner != widget.owner) {
      _expandedMeldIndex = null;
      return;
    }
    final expanded = _expandedMeldIndex;
    if (expanded != null && expanded >= widget.melds.length) {
      _expandedMeldIndex = null;
    }
  }

  void _toggleExpanded(int index) {
    setState(() {
      _expandedMeldIndex = _expandedMeldIndex == index ? null : index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<HareegCard>(
      onWillAcceptWithDetails: (details) => widget.canAcceptTable(details.data),
      onAcceptWithDetails: (details) => widget.onAcceptTable(details.data),
      builder: (context, candidates, rejected) {
        final hot = candidates.isNotEmpty;
        final lane = AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.all(widget.compact ? 3 : 5),
          decoration: BoxDecoration(
            color: hot
                ? LoungeTokens.goldAccent.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hot
                  ? LoungeTokens.goldAccent.withValues(alpha: 0.46)
                  : Colors.transparent,
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final sideFacing = widget.quarterTurns % 2 != 0;
              final meldWidgets = [
                for (var index = 0; index < widget.melds.length; index++)
                  _TableMeldStack(
                    key: ValueKey(
                      'table-meld-${widget.owner.name}-$index-'
                      '${_expandedMeldIndex == index ? 'expanded' : 'normal'}',
                    ),
                    theme: widget.theme,
                    owner: widget.owner,
                    meldIndex: index,
                    meld: widget.melds[index],
                    cardSize: widget.cardSize,
                    compact: widget.compact,
                    canAccept: widget.canAcceptMeld,
                    onAccept: widget.onAcceptMeld,
                    canRetract: widget.canRetractMeld(widget.owner, index),
                    onRetract: () => widget.onRetractMeld(widget.owner, index),
                    onCardLongPress: widget.onCardLongPress,
                    expanded: _expandedMeldIndex == index,
                    onToggleExpanded: () => _toggleExpanded(index),
                    vertical: widget.stackVertically,
                    quarterTurns: widget.quarterTurns,
                  ),
                if (widget.melds.isEmpty &&
                    widget.owner == PlayerSeat.south &&
                    hot)
                  SizedBox(
                    width: widget.compact ? 70 : 92,
                    height: widget.compact ? 36 : 46,
                  ),
              ];
              final content = Wrap(
                alignment: WrapAlignment.center,
                runAlignment: WrapAlignment.center,
                spacing: widget.compact ? 7 : 10,
                runSpacing: widget.compact ? 8 : 12,
                children: meldWidgets,
              );

              if (sideFacing) {
                return SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth,
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: meldWidgets,
                    ),
                  ),
                );
              }

              if (widget.stackVertically) {
                return SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth,
                      minHeight: constraints.maxHeight,
                    ),
                    child: Align(alignment: Alignment.center, child: content),
                  ),
                );
              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Align(alignment: Alignment.center, child: content),
                ),
              );
            },
          ),
        );
        return lane;
      },
    );
  }
}

class _TableMeldStack extends StatelessWidget {
  const _TableMeldStack({
    super.key,
    required this.theme,
    required this.owner,
    required this.meldIndex,
    required this.meld,
    required this.cardSize,
    required this.compact,
    required this.canAccept,
    required this.onAccept,
    required this.onCardLongPress,
    required this.expanded,
    this.canRetract = false,
    this.onRetract,
    this.onToggleExpanded,
    this.vertical = false,
    this.quarterTurns = 0,
  });

  final HareegCardTheme theme;
  final PlayerSeat owner;
  final int meldIndex;
  final PlacedMeld meld;
  final Size cardSize;
  final bool compact;
  final TableMeldDropPredicate canAccept;
  final TableMeldDropHandler onAccept;
  final ValueChanged<HareegCard> onCardLongPress;
  final bool expanded;
  final bool canRetract;
  final VoidCallback? onRetract;
  final VoidCallback? onToggleExpanded;

  /// When true, cards stack downward (used for west/east opponent lanes
  /// that sit along the side edges of the table).
  final bool vertical;
  final int quarterTurns;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final cards = meld.cards;
    final sideFacing = quarterTurns % 2 != 0;
    final expandedScale = expanded ? (compact ? 1.16 : 1.26) : 1.0;
    final effectiveCardSize = Size(
      cardSize.width * expandedScale,
      cardSize.height * expandedScale,
    );
    final horizontalGap = sideFacing
        ? effectiveCardSize.width * (expanded ? 0.92 : 0.68)
        : effectiveCardSize.width * (expanded ? 0.72 : 0.43);
    final gap = vertical
        ? effectiveCardSize.height * (expanded ? 0.58 : 0.32)
        : horizontalGap;
    final width = vertical
        ? effectiveCardSize.width
        : effectiveCardSize.width + math.max(0, cards.length - 1) * gap;
    final height = vertical
        ? effectiveCardSize.height + math.max(0, cards.length - 1) * gap
        : effectiveCardSize.height;
    final accent = _seatAccent(owner);
    return DragTarget<HareegCard>(
      onWillAcceptWithDetails: (details) =>
          canAccept(details.data, owner, meldIndex),
      onAcceptWithDetails: (details) =>
          onAccept(details.data, owner, meldIndex),
      builder: (context, candidates, rejected) {
        final hot = candidates.isNotEmpty;
        final retractable = canRetract && onRetract != null;
        final bodyWidth = vertical ? width : width + (expanded ? 14 : 10);
        final bodyHeight = vertical ? height + (expanded ? 14 : 10) : height;
        final body = AnimatedScale(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          scale: hot ? 1.04 : 1,
          child: SizedBox(
            width: bodyWidth,
            height: bodyHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Drop / take-back hint frame. Stays invisible during normal
                // play so melds float on the felt the way the reference
                // shows them; only fires up when the player can take the
                // meld back or has a card dragged over it for a cover.
                if (hot || retractable)
                  Positioned.fill(
                    top: compact ? 6 : 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: hot
                            ? LoungeTokens.goldAccent.withValues(alpha: 0.18)
                            : LoungeTokens.goldAccent.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: hot
                              ? LoungeTokens.goldAccent.withValues(alpha: 0.7)
                              : LoungeTokens.goldAccent.withValues(alpha: 0.4),
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                for (var i = 0; i < cards.length; i++)
                  Positioned(
                    left: vertical ? 0 : i * gap,
                    top: vertical ? i * gap : 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: () => onCardLongPress(cards[i]),
                      child: HareegCardView(
                        theme: theme,
                        card: cards[i],
                        size: effectiveCardSize,
                      ),
                    ),
                  ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${meld.totalValue}',
                      style: TextStyle(
                        color: owner == PlayerSeat.south
                            ? LoungeTokens.coffeeCharcoal
                            : LoungeTokens.offWhiteText,
                        fontSize: compact ? 9 : 10,
                        height: 1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                if (retractable)
                  Positioned(
                    left: compact ? -7 : -8,
                    top: compact ? -7 : -8,
                    child: Tooltip(
                      message: strings.takeThisMeldBack,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onRetract,
                        child: SizedBox.square(
                          dimension: compact ? 24 : 28,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: LoungeTokens.coffeeCharcoal.withValues(
                                  alpha: 0.90,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: LoungeTokens.goldAccent.withValues(
                                    alpha: 0.44,
                                  ),
                                ),
                              ),
                              child: Icon(
                                Icons.undo_rounded,
                                size: compact ? 11 : 12,
                                color: LoungeTokens.goldAccent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );

        final orientedBody = quarterTurns == 0
            ? body
            : SizedBox(
                width: bodyHeight + (compact ? 8 : 10),
                height: bodyWidth + (compact ? 8 : 10),
                child: Center(
                  child: RotatedBox(quarterTurns: quarterTurns, child: body),
                ),
              );

        final expandable = onToggleExpanded != null;
        final interactiveBody = expandable
            ? Tooltip(
                message: expanded ? strings.collapseMeld : strings.expandMeld,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggleExpanded,
                  child: orientedBody,
                ),
              )
            : orientedBody;

        return interactiveBody;
      },
    );
  }
}

class _MeldSuggestionRack extends StatelessWidget {
  const _MeldSuggestionRack({
    required this.theme,
    required this.suggestions,
    required this.cardSize,
    required this.onTapSuggestion,
    required this.onCardLongPress,
  });

  final HareegCardTheme theme;
  final List<TableMeldSuggestion> suggestions;
  final Size cardSize;
  final ValueChanged<String> onTapSuggestion;
  final ValueChanged<HareegCard> onCardLongPress;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 140),
      child: Container(
        key: ValueKey(suggestions.map((s) => s.actionId).join('|')),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final suggestion in suggestions.take(3)) ...[
                _SuggestionGroup(
                  theme: theme,
                  suggestion: suggestion,
                  cardSize: cardSize,
                  onTap: () => onTapSuggestion(suggestion.actionId),
                  onCardLongPress: onCardLongPress,
                ),
                const SizedBox(width: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionGroup extends StatelessWidget {
  const _SuggestionGroup({
    required this.theme,
    required this.suggestion,
    required this.cardSize,
    required this.onTap,
    required this.onCardLongPress,
  });

  final HareegCardTheme theme;
  final TableMeldSuggestion suggestion;
  final Size cardSize;
  final VoidCallback onTap;
  final ValueChanged<HareegCard> onCardLongPress;

  @override
  Widget build(BuildContext context) {
    final cards = suggestion.cards;
    final gap = cardSize.width * 0.50;
    final width = cardSize.width + math.max(0, cards.length - 1) * gap;
    return Tooltip(
      message: context.strings.playMeld,
      child: GestureDetector(
        key: ValueKey('meld-suggestion-${suggestion.actionId}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: cardSize.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < cards.length; i++)
                Positioned(
                  left: i * gap,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPress: () => onCardLongPress(cards[i]),
                    child: HareegCardView(
                      theme: theme,
                      card: cards[i],
                      jokerDisplay: JokerDisplay.assisted,
                      size: cardSize,
                      visualState: CardVisualState.coverTarget,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideControls extends StatelessWidget {
  const _SideControls({
    required this.meldRequirement,
    required this.meldSelectionValue,
    required this.meldSelectionValid,
    required this.meldSelectionHasOpened,
    required this.onPlaySelectedMeld,
    required this.compact,
    required this.canReturnOpeningMelds,
    required this.onReturnOpeningMelds,
  });

  final int meldRequirement;
  final int? meldSelectionValue;
  final bool meldSelectionValid;
  final bool meldSelectionHasOpened;
  final VoidCallback? onPlaySelectedMeld;
  final bool compact;
  final bool canReturnOpeningMelds;
  final VoidCallback onReturnOpeningMelds;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MeldCtaButton(
          requirement: meldRequirement,
          selectionValue: meldSelectionValue,
          selectionValid: meldSelectionValid,
          hasOpened: meldSelectionHasOpened,
          onTap: onPlaySelectedMeld,
          compact: compact,
        ),
        if (canReturnOpeningMelds) ...[
          SizedBox(height: compact ? 4 : 6),
          Tooltip(
            message: context.strings.takeBackMelds,
            child: _IconTablePill(
              icon: Icons.undo_rounded,
              compact: compact,
              onTap: onReturnOpeningMelds,
            ),
          ),
        ],
      ],
    );
  }
}

class _TablePill extends StatelessWidget {
  const _TablePill({required this.compact, required this.child});

  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 30 : 34,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: IconTheme(
        data: const IconThemeData(color: LoungeTokens.coffeeCharcoal),
        child: DefaultTextStyle(
          style: const TextStyle(color: LoungeTokens.coffeeCharcoal),
          child: child,
        ),
      ),
    );
  }
}

class _IconTablePill extends StatelessWidget {
  const _IconTablePill({
    required this.icon,
    required this.compact,
    required this.onTap,
  });

  final IconData icon;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: _TablePill(
          compact: compact,
          child: Icon(icon, size: compact ? 16 : 18),
        ),
      ),
    );
  }
}

/// Bottom-right Meld chip. When the human seat has selected a complete legal
/// meld, becomes a tappable confirmation CTA showing the played value;
/// otherwise renders the current opening requirement as a static reference.
class _MeldCtaButton extends StatelessWidget {
  const _MeldCtaButton({
    required this.requirement,
    required this.selectionValue,
    required this.selectionValid,
    required this.hasOpened,
    required this.onTap,
    required this.compact,
  });

  final int requirement;
  final int? selectionValue;
  final bool selectionValid;
  final bool hasOpened;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final isCta = selectionValid && onTap != null;
    final displayValue = selectionValue ?? requirement;
    final caption = isCta
        ? (hasOpened ? strings.playMeld : strings.openMeld)
        : (hasOpened ? strings.meld : strings.openNeed);
    final background = isCta
        ? LoungeTokens.goldAccent
        : LoungeTokens.coffeeCharcoal.withValues(alpha: 0.92);
    final foreground = isCta
        ? LoungeTokens.coffeeCharcoal
        : LoungeTokens.offWhiteText;

    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      height: compact ? 40 : 48,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCta
              ? Colors.white.withValues(alpha: 0.32)
              : Colors.white.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: isCta
                ? LoungeTokens.goldAccent.withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.16),
            blurRadius: isCta ? 12 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              caption,
              style: TextStyle(
                color: foreground,
                fontSize: compact ? 8.5 : 10,
                fontWeight: FontWeight.w800,
                height: 1,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$displayValue',
              style: TextStyle(
                color: foreground,
                fontSize: compact ? 14 : 17,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );

    if (!isCta) return body;

    return Tooltip(
      message: strings.playSelectedMeld,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: body,
        ),
      ),
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

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.value, required this.compact});

  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value,
        style: TextStyle(
          color: LoungeTokens.offWhiteText,
          fontSize: compact ? 10 : 12,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

HareegCard _backSeed(int index) {
  return HareegCard.standard(
    rank: CardRank.ace,
    suit: CardSuit.spades,
    deckIndex: 500 + index,
  );
}

Color _seatAccent(PlayerSeat seat) {
  return switch (seat) {
    PlayerSeat.south => LoungeTokens.goldAccent,
    PlayerSeat.east => const Color(0xFF2F5F6D),
    PlayerSeat.north => LoungeTokens.coffeeCharcoal,
    PlayerSeat.west => LoungeTokens.indigoAccent,
  };
}
