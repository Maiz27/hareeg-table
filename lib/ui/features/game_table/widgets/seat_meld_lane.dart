import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../domain/classic_hareeg/rules/cover_rules.dart';
import '../../../../domain/classic_hareeg/rules/opening_rules.dart'
    show PlacedMeld;
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_state.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/cards/card_view.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../coach/coach_highlighting.dart';
import '../seat_meld_arrangement.dart';
import '../table_meld_drop_target.dart';

/// Predicate that decides whether a dragged card may land on a specific table
/// meld target.
typedef TableMeldDropPredicate =
    bool Function(HareegCard card, TableMeldDropTarget target);

/// Handler invoked when a card is successfully dropped onto a table meld.
typedef TableMeldDropHandler =
    void Function(HareegCard card, TableMeldDropTarget target);

/// Predicate that decides whether a placed meld may be retracted.
typedef TableMeldRetractPredicate =
    bool Function(PlayerSeat owner, int meldIndex);

/// Handler invoked when the player retracts a placed meld.
typedef TableMeldRetractHandler =
    void Function(PlayerSeat owner, int meldIndex);

/// Lane of placed melds belonging to one seat.
///
/// Hosts the only stateful UI in the playfield: each meld lane tracks which
/// of its placed melds is currently expanded for inspection. The lane itself
/// is a `DragTarget` for new-meld plays; per-meld drops (covers and joker
/// replacements) are handled by the inner `_TableMeldStack`.
class SeatMeldLane extends StatefulWidget {
  /// Creates a seat meld lane.
  const SeatMeldLane({
    super.key,
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
    this.coachHighlighting = CoachHighlighting.none,
  });

  /// Card theme used to render meld cards.
  final HareegCardTheme theme;

  /// Seat that owns the melds in this lane.
  final PlayerSeat owner;

  /// Placed melds belonging to [owner], in placement order.
  final List<PlacedMeld> melds;

  /// Card size used by each meld.
  final Size cardSize;

  /// Whether the table is rendering in compact mode.
  final bool compact;

  /// Predicate for whether a dropped card opens a new meld on this lane.
  final bool Function(HareegCard card) canAcceptTable;

  /// Handler invoked when a card is dropped on the lane to open a new meld.
  final ValueChanged<HareegCard> onAcceptTable;

  /// Predicate for whether a dropped card may extend a specific meld.
  final TableMeldDropPredicate canAcceptMeld;

  /// Handler invoked when a card is dropped on a specific meld.
  final TableMeldDropHandler onAcceptMeld;

  /// Predicate for whether a specific meld may be retracted.
  final TableMeldRetractPredicate canRetractMeld;

  /// Handler invoked when a meld retraction is requested.
  final TableMeldRetractHandler onRetractMeld;

  /// Long-press handler for a card in any meld in this lane.
  final ValueChanged<HareegCard> onCardLongPress;

  /// Whether melds stack vertically (used by side lanes that scroll on Y).
  final bool stackVertically;

  /// Number of 90° clockwise turns to apply to each meld for side lanes.
  final int quarterTurns;

  /// Coach-highlight projection; the lane rings any of its meld cards the
  /// coach is pointing at (cover-target cards) in the teal keep hue.
  final CoachHighlighting coachHighlighting;

  @override
  State<SeatMeldLane> createState() => _SeatMeldLaneState();
}

class _SeatMeldLaneState extends State<SeatMeldLane> {
  int? _expandedMeldIndex;

  @override
  void didUpdateWidget(covariant SeatMeldLane oldWidget) {
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
                    coachHighlighting: widget.coachHighlighting,
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
                // Side (east/west) melds fill centred columns that grow
                // toward the table centre instead of a single tall strip.
                // The arrangement is computed by the shared
                // `SeatMeldArrangement` model — the same model the flight
                // geometry reads — so each meld is drawn exactly where its
                // placement flight lands. `Clip.none` keeps a tapped
                // (expanded) meld from being cropped; the vertical scroll is
                // only a fallback for the rare case the columns still
                // overflow the lane height.
                final meldGap = widget.compact ? 8.0 : 12.0;
                final columnGap = widget.compact ? 8.0 : 12.0;
                final laneSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                final footprints = [
                  for (final meld in widget.melds)
                    SeatMeldArrangement.footprint(
                      cardSize: widget.cardSize,
                      cardCount: meld.cards.length,
                      compact: widget.compact,
                      sideFacing: true,
                    ),
                ];
                final layout = SeatMeldArrangement.side(
                  laneSize: laneSize,
                  footprints: footprints,
                  meldGap: meldGap,
                  columnGap: columnGap,
                  // East (quarterTurns 3) hugs the right rail and grows left
                  // toward centre; west (quarterTurns 1) hugs the left rail.
                  growFromRailRight: widget.quarterTurns == 3,
                );
                return SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  physics: const BouncingScrollPhysics(),
                  child: SizedBox(
                    width: laneSize.width,
                    height: layout.contentSize.height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (
                          var i = 0;
                          i < meldWidgets.length && i < layout.slots.length;
                          i++
                        )
                          Positioned(
                            left: layout.slots[i].left,
                            top: layout.slots[i].top,
                            child: meldWidgets[i],
                          ),
                      ],
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

              // `Clip.none` lets an expanded meld stack overflow vertically
              // past the lane's height without being cropped by the scroll
              // viewport — see the regression test in
              // test/ui/features/game_table/meld_expand_no_crop_test.dart.
              //
              // South melds also bottom-anchor so the lane's extra
              // headroom (allocated for expansion by the playfield) sits
              // ABOVE the cards, never below them — keeping the resting
              // cards at their visual home next to the hand fan while
              // letting the expansion grow up into the empty
              // table-center band.
              final isSouthLane = widget.owner == PlayerSeat.south;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                clipBehavior: Clip.none,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Align(
                    alignment: isSouthLane
                        ? Alignment.bottomCenter
                        : Alignment.center,
                    child: content,
                  ),
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

class _TableMeldStack extends StatefulWidget {
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
    this.coachHighlighting = CoachHighlighting.none,
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

  /// Coach-highlight projection; rings this meld's cover-target cards in teal.
  final CoachHighlighting coachHighlighting;

  @override
  State<_TableMeldStack> createState() => _TableMeldStackState();
}

class _TableMeldStackState extends State<_TableMeldStack> {
  final _targetKey = GlobalKey();
  CoverPlacement? _hoverPlacement;
  bool _hoverAccepts = true;

  void _clearHover() {
    if (_hoverPlacement == null && _hoverAccepts) {
      return;
    }
    setState(() {
      _hoverPlacement = null;
      _hoverAccepts = true;
    });
  }

  /// Computes the drop target for the current drag location. Returns null if
  /// the render box isn't ready yet (theoretically not possible once a drag is
  /// in flight, but the [RenderBox] cast is nullable).
  TableMeldDropTarget? _targetFor(DragTargetDetails<HareegCard> details) {
    final box = _targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return null;
    }
    final local = box.globalToLocal(details.offset);
    return TableMeldDropTargetPlanner.targetForLocalPosition(
      owner: widget.owner,
      meldIndex: widget.meldIndex,
      cardCount: widget.meld.cards.length,
      localPosition: local,
      bounds: box.size,
      vertical: widget.vertical,
      quarterTurns: widget.quarterTurns,
    );
  }

  void _updateHover(DragTargetDetails<HareegCard> details) {
    final target = _targetFor(details);
    if (target == null) return;
    final placement = target.coverPlacement;
    final accepts = widget.canAccept(details.data, target);
    if (_hoverPlacement == placement && _hoverAccepts == accepts) {
      return;
    }
    setState(() {
      _hoverPlacement = placement;
      _hoverAccepts = accepts;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final owner = widget.owner;
    final meldIndex = widget.meldIndex;
    final meld = widget.meld;
    final cardSize = widget.cardSize;
    final compact = widget.compact;
    final canAccept = widget.canAccept;
    final onAccept = widget.onAccept;
    final onCardLongPress = widget.onCardLongPress;
    final expanded = widget.expanded;
    final canRetract = widget.canRetract;
    final onRetract = widget.onRetract;
    final onToggleExpanded = widget.onToggleExpanded;
    final vertical = widget.vertical;
    final quarterTurns = widget.quarterTurns;
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
      key: _targetKey,
      onWillAcceptWithDetails: (details) {
        final target =
            _targetFor(details) ??
            TableMeldDropTarget(
              owner: owner,
              meldIndex: meldIndex,
              coverPlacement: _hoverPlacement,
            );
        return canAccept(details.data, target);
      },
      onMove: _updateHover,
      onLeave: (_) => _clearHover(),
      onAcceptWithDetails: (details) {
        final target =
            _targetFor(details) ??
            TableMeldDropTarget(
              owner: owner,
              meldIndex: meldIndex,
              coverPlacement: _hoverPlacement,
            );
        onAccept(details.data, target);
        _clearHover();
      },
      builder: (context, candidates, rejected) {
        final hot = candidates.isNotEmpty;
        final retractable = canRetract && onRetract != null;
        // The body hugs the card fan exactly: trailing slack here painted
        // the take-back/drop frame past the last card (the same dead-space
        // family as the suggestion rack's trailing separator). The value
        // badge overlays the fan's corner instead of claiming its own lane.
        final bodyWidth = width;
        final bodyHeight = height;
        final hoverPlacement = _hoverPlacement;
        final hoverColor = _hoverAccepts
            ? LoungeTokens.goldAccent
            : LoungeTokens.deepRed;
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
                if (hot &&
                    (hoverPlacement == CoverPlacement.lowEnd ||
                        hoverPlacement == CoverPlacement.highEnd))
                  _CoverEdgeIndicator(
                    placement: hoverPlacement!,
                    vertical: vertical || sideFacing,
                    compact: compact,
                    color: hoverColor,
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
                        visualState: widget.coachHighlighting.highlights(
                              cards[i].id,
                            )
                            ? CardVisualState.coachHighlight
                            : CardVisualState.normal,
                        // A grouped cover-target meld rings in its own palette
                        // hue (a cover lesson's group 1, or the live coach's
                        // cover hint) instead of the default teal.
                        coachRingColor: widget.coachHighlighting.ringColorFor(
                          cards[i].id,
                        ),
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

Color _seatAccent(PlayerSeat seat) {
  return switch (seat) {
    PlayerSeat.south => LoungeTokens.goldAccent,
    PlayerSeat.east => const Color(0xFF2F5F6D),
    PlayerSeat.north => LoungeTokens.coffeeCharcoal,
    PlayerSeat.west => LoungeTokens.indigoAccent,
  };
}

class _CoverEdgeIndicator extends StatelessWidget {
  const _CoverEdgeIndicator({
    required this.placement,
    required this.vertical,
    required this.compact,
    required this.color,
  });

  final CoverPlacement placement;
  final bool vertical;
  final bool compact;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final thickness = compact ? 4.0 : 5.0;
    final inset = compact ? 4.0 : 5.0;
    final decoration = BoxDecoration(
      color: color.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(99),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.30),
          blurRadius: 10,
          spreadRadius: 1,
        ),
      ],
    );

    if (vertical) {
      return Positioned(
        left: inset,
        right: inset,
        top: placement == CoverPlacement.lowEnd ? 0 : null,
        bottom: placement == CoverPlacement.highEnd ? 0 : null,
        height: thickness,
        child: DecoratedBox(decoration: decoration),
      );
    }

    return Positioned(
      top: inset,
      bottom: inset,
      left: placement == CoverPlacement.lowEnd ? 0 : null,
      right: placement == CoverPlacement.highEnd ? 0 : null,
      width: thickness,
      child: DecoratedBox(decoration: decoration),
    );
  }
}
