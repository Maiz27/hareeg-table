import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../core/cards/card_state.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/cards/card_view.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../coach/coach_highlighting.dart';
import '../table_view_scale.dart';

/// South player's hand, rendered as a flex-gap fan across the bottom of the
/// table. Each card is a `DragTarget` so the player can reorder by dragging
/// onto another slot, and a trailing drop zone lets the player append to the
/// end of the hand.
class SouthHandFan extends StatelessWidget {
  /// Creates the south hand fan.
  const SouthHandFan({
    super.key,
    required this.theme,
    required this.cards,
    required this.selectedIds,
    required this.pendingId,
    required this.cardSize,
    required this.draggable,
    required this.onTap,
    required this.onLongPress,
    required this.onReorder,
    this.flashCardId,
    this.coachHighlighting = CoachHighlighting.none,
  });

  /// Card theme used to render hand cards.
  final HareegCardTheme theme;

  /// Cards in current display order.
  final List<HareegCard> cards;

  /// Selected physical card ids.
  final Set<String> selectedIds;

  /// Pending discard id (renders with [CardVisualState.pending]), if any.
  final String? pendingId;

  /// Card size used by each hand card.
  final Size cardSize;

  /// Whether cards may be dragged for reordering or table play.
  final bool draggable;

  /// Tap fallback for selecting cards.
  final ValueChanged<HareegCard> onTap;

  /// Long-press handler for inspecting a card.
  final ValueChanged<HareegCard> onLongPress;

  /// Called when the player drops `card` onto the slot at `targetIndex` in
  /// the displayed hand order. The orchestrator updates its display order
  /// accordingly; the engine's hand list is unchanged.
  final void Function(HareegCard card, int targetIndex) onReorder;

  /// Card id to flash as invalid — used to highlight a card that just got
  /// the Strict-tier +3 reject. Cleared on a timer by the orchestrator.
  final String? flashCardId;

  /// Coach-highlight projection for the active hint. Resolves which hand cards
  /// ring and in which hue (teal keep / per-meld palette / warm discard);
  /// rendered when a card is not in a higher-priority state.
  final CoachHighlighting coachHighlighting;

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
                          flashInvalid: flashCardId == cards[i].id,
                          coachHighlight: coachHighlighting.highlights(
                            cards[i].id,
                          ),
                          // Warm discard hue, else a meld-group hue, else null
                          // for the default teal coach overlay — the precedence
                          // lives in CoachHighlighting.ringColorFor.
                          coachRingColor: coachHighlighting.ringColorFor(
                            cards[i].id,
                          ),
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
    this.flashInvalid = false,
    this.coachHighlight = false,
    this.coachRingColor,
  });

  final HareegCardTheme theme;
  final HareegCard card;
  final bool selected;
  final bool pending;
  final Size size;
  final bool draggable;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// True when the coaching tier is pointing at this card. Lower priority than
  /// invalid / pending / selected so a card the player is actively working
  /// with keeps its own state.
  final bool coachHighlight;

  /// Per-meld coach ring colour, or null for the default teal.
  final Color? coachRingColor;

  /// True when another card is being dragged over this position; the card
  /// shifts right slightly so the player can see where the dropped card
  /// will land.
  final bool insertGapBefore;

  /// True while this card should render with the invalid-state overlay as a
  /// transient "this discard was rejected" cue (Strict +3 mistake).
  final bool flashInvalid;

  @override
  Widget build(BuildContext context) {
    final state = flashInvalid
        ? CardVisualState.invalid
        : pending
        ? CardVisualState.pending
        : selected
        ? CardVisualState.selected
        : coachHighlight
        ? CardVisualState.coachHighlight
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
          coachRingColor: coachRingColor,
        ),
      ),
    );

    if (!draggable) return face;
    // The feedback rides the root overlay, outside the web "zoom to fill"
    // transform, so it must scale itself (and its grab anchor) to match the
    // cards painted on the table. 1.0 on native, where the table isn't scaled.
    final tableScale = TableViewScale.of(context);
    final feedbackSize = size * tableScale;
    return Draggable<HareegCard>(
      key: ValueKey('south-hand-drag-${card.id}'),
      data: card,
      maxSimultaneousDrags: 1,
      rootOverlay: true,
      // Default anchor is in the child's (unscaled) coordinate space; scale it
      // so the enlarged feedback still sits under the finger where it was
      // grabbed.
      dragAnchorStrategy: (draggable, context, position) =>
          childDragAnchorStrategy(draggable, context, position) * tableScale,
      feedback: Material(
        color: Colors.transparent,
        elevation: 10,
        borderRadius: BorderRadius.circular(
          LoungeTokens.radiusCard * tableScale,
        ),
        child: Transform.scale(
          scale: 1.07,
          child: HareegCardView(
            theme: theme,
            card: card,
            size: feedbackSize,
            visualState: state,
            coachRingColor: coachRingColor,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.24, child: face),
      child: face,
    );
  }
}
