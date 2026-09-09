import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/cards/card_view.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Top opponent hand rail (north seat). Renders a horizontal fan of face-down
/// card backs with a turn-aware glow frame.
class OpponentHandRail extends StatelessWidget {
  /// Creates a top opponent hand rail.
  const OpponentHandRail({
    super.key,
    required this.theme,
    required this.count,
    required this.cardSize,
    required this.active,
    required this.thinking,
    required this.eliminated,
    required this.compact,
    this.faceUpCards = const <HareegCard>[],
    this.onExpand,
    this.expandLabel = '',
  }) : assert(
         onExpand == null || expandLabel != '',
         'an interactive rail must carry a localized label',
       );

  /// Card theme used for face-down backs.
  final HareegCardTheme theme;

  /// Card count to render in the rail.
  final int count;

  /// Card size used by individual backs.
  final Size cardSize;

  /// Whether this seat is currently active.
  final bool active;

  /// Whether the CPU is thinking on this seat.
  final bool thinking;

  /// Whether this seat has been eliminated.
  final bool eliminated;

  /// Whether the table is rendering in compact mode.
  final bool compact;

  /// Cards to render face up, or empty for the normal hidden hand.
  final List<HareegCard> faceUpCards;

  /// Opens the read-only expanded view of a revealed hand. Null everywhere a
  /// hand is hidden, so there is nothing to open.
  final VoidCallback? onExpand;

  /// Localized label for the expansion affordance. Only read when [onExpand]
  /// is non-null, i.e. only in full-visibility study mode.
  final String expandLabel;

  @override
  Widget build(BuildContext context) {
    final visibleCount = compact ? 9 : 12;
    final stackSize = cardBackStackSize(
      count: count,
      axis: Axis.horizontal,
      cardSize: cardSize,
      visibleCount: visibleCount,
    );
    final cueSize = Size(
      math.max(stackSize.width + (compact ? 18 : 24), _expandFloor(onExpand)),
      math.max(stackSize.height + (compact ? 14 : 18), _expandFloor(onExpand)),
    );
    final height = math.max(
      cardSize.height + (compact ? 16 : 20),
      cueSize.height,
    );
    return SizedBox(
      height: height,
      child: Opacity(
        opacity: eliminated ? 0.28 : 1,
        child: Align(
          alignment: Alignment.topCenter,
          child: _TurnCueFrame(
            active: active,
            thinking: thinking,
            size: cueSize,
            child: _MaybeExpandable(
              onExpand: onExpand,
              label: expandLabel,
              child: _CardBackStack(
                theme: theme,
                count: count,
                axis: Axis.horizontal,
                cardSize: cardSize,
                visibleCount: visibleCount,
                faceUpCards: faceUpCards,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Side opponent hand rail (west/east). Renders a vertical stack of card backs
/// with the same turn-aware glow as [OpponentHandRail].
class OpponentSideRail extends StatelessWidget {
  /// Creates a side opponent rail.
  const OpponentSideRail({
    super.key,
    required this.theme,
    required this.count,
    required this.cardSize,
    required this.active,
    required this.thinking,
    required this.eliminated,
    required this.alignRight,
    required this.compact,
    this.faceUpCards = const <HareegCard>[],
    this.onExpand,
    this.expandLabel = '',
  }) : assert(
         onExpand == null || expandLabel != '',
         'an interactive rail must carry a localized label',
       );

  /// Card theme used for face-down backs.
  final HareegCardTheme theme;

  /// Card count to render in the rail.
  final int count;

  /// Card size used by individual backs.
  final Size cardSize;

  /// Whether this seat is currently active.
  final bool active;

  /// Whether the CPU is thinking on this seat.
  final bool thinking;

  /// Whether this seat has been eliminated.
  final bool eliminated;

  /// Whether the rail anchors to the right edge (east) or left edge (west).
  final bool alignRight;

  /// Whether the table is rendering in compact mode.
  final bool compact;

  /// Cards to render face up, or empty for the normal hidden hand.
  final List<HareegCard> faceUpCards;

  /// Opens the read-only expanded view of a revealed hand.
  final VoidCallback? onExpand;

  /// Localized label for the expansion affordance. Only read when [onExpand]
  /// is non-null, i.e. only in full-visibility study mode.
  final String expandLabel;

  @override
  Widget build(BuildContext context) {
    final visibleCount = compact ? 5 : 6;
    final stackSize = cardBackStackSize(
      count: count,
      axis: Axis.vertical,
      cardSize: cardSize,
      visibleCount: visibleCount,
    );
    final cueSize = Size(
      math.max(stackSize.width + (compact ? 14 : 18), _expandFloor(onExpand)),
      math.max(stackSize.height + (compact ? 18 : 24), _expandFloor(onExpand)),
    );
    return Opacity(
      opacity: eliminated ? 0.28 : 1,
      child: Align(
        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
        child: _TurnCueFrame(
          active: active,
          thinking: thinking,
          size: cueSize,
          child: _MaybeExpandable(
            onExpand: onExpand,
            label: expandLabel,
            child: _CardBackStack(
              theme: theme,
              count: count,
              axis: Axis.vertical,
              cardSize: cardSize,
              visibleCount: visibleCount,
              faceUpCards: faceUpCards,
            ),
          ),
        ),
      ),
    );
  }
}

/// Computes the bounding size for a fanned card-back stack.
Size cardBackStackSize({
  required int count,
  required Axis axis,
  required Size cardSize,
  required int visibleCount,
}) {
  if (count <= 0) {
    return Size.zero;
  }
  final shown = math.min(count, visibleCount);
  final gap = axis == Axis.horizontal ? cardSize.width * 0.38 : 16.0;
  return Size(
    axis == Axis.horizontal
        ? cardSize.width + (shown - 1) * gap
        : cardSize.width,
    axis == Axis.horizontal
        ? cardSize.height
        : cardSize.height + (shown - 1) * gap,
  );
}

/// Wraps a rail's cards in a read-only tap target, or leaves them untouched.
///
/// Expansion is a *viewing* affordance and stays one: it opens a sheet and
/// changes nothing. It exists only where [onExpand] is non-null, which is only
/// where a hand is already face up, so there is no route by which tapping an
/// opponent rail can act on that seat.
///
/// When it does exist it is a real control, not a bare gesture: it carries the
/// seat's localized name, announces itself as an enabled button, and reserves
/// the 44 dp minimum. A side rail is 32 dp wide, so without the floor the only
/// way to reach an opponent's hand would be to hit a target narrower than a
/// fingertip.
/// The 44 dp floor a rail must reserve when it carries a study affordance.
///
/// Zero when it does not: the blind and live rails keep exactly the geometry
/// they have always had, and only a rail a player can actually open grows to
/// a reachable size. Without this the frame hands the target whatever the
/// shrinking table left it — 40 dp at 320 dp wide, below the contracted floor.
double _expandFloor(VoidCallback? onExpand) =>
    onExpand == null ? 0 : _MaybeExpandable.minTapTarget;

class _MaybeExpandable extends StatelessWidget {
  const _MaybeExpandable({
    required this.child,
    required this.label,
    this.onExpand,
  });

  final Widget child;

  /// Localized name for the affordance, e.g. "Show East's hand".
  final String label;

  final VoidCallback? onExpand;

  /// Minimum hit and semantics extent for a new interactive control.
  static const double minTapTarget = 44;

  @override
  Widget build(BuildContext context) {
    final expand = onExpand;
    if (expand == null) {
      return child;
    }
    return Tooltip(
      message: label,
      // The name is on the Semantics below. Web renders label and tooltip
      // both as text, so carrying both announces the rail twice.
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: expand,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: minTapTarget,
              minHeight: minTapTarget,
            ),
            // Centered rather than stretched: the cards keep the size and
            // position the blind and live rails give them, and only the
            // reachable area around them grows.
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _TurnCueFrame extends StatelessWidget {
  const _TurnCueFrame({
    required this.active,
    required this.thinking,
    required this.size,
    required this.child,
  });

  final bool active;
  final bool thinking;
  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: size.width,
      height: size.height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active
            ? LoungeTokens.goldAccent.withValues(alpha: thinking ? 0.14 : 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: active
            ? Border.all(
                color: LoungeTokens.goldAccent.withValues(
                  alpha: thinking ? 0.70 : 0.52,
                ),
                width: thinking ? 1.6 : 1.2,
              )
            : null,
        boxShadow: active
            ? [
                BoxShadow(
                  color: LoungeTokens.goldAccent.withValues(
                    alpha: thinking ? 0.26 : 0.18,
                  ),
                  blurRadius: thinking ? 20 : 14,
                  spreadRadius: thinking ? 2 : 0,
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

/// The one place an opponent's cards are drawn.
///
/// Both rails funnel here, so face-up study rendering is a single additive
/// parameter rather than three parallel changes that could disagree. Left
/// empty — the default, and what every live, practice and blind surface
/// passes — every card is a back, and the real identities never reach the
/// widget tree at all: not the painter, not semantics, not a key.
class _CardBackStack extends StatelessWidget {
  const _CardBackStack({
    required this.theme,
    required this.count,
    required this.axis,
    required this.cardSize,
    required this.visibleCount,
    this.faceUpCards = const <HareegCard>[],
  });

  final HareegCardTheme theme;
  final int count;
  final Axis axis;
  final Size cardSize;
  final int visibleCount;

  /// Cards to render face up, or empty to render backs.
  final List<HareegCard> faceUpCards;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final reveal = faceUpCards.isNotEmpty;
    final shown = math.min(count, visibleCount);
    final gap = axis == Axis.horizontal ? cardSize.width * 0.38 : 16.0;
    final width = axis == Axis.horizontal
        ? cardSize.width + (shown - 1) * gap
        : cardSize.width;
    final height = axis == Axis.horizontal
        ? cardSize.height
        : cardSize.height + (shown - 1) * gap;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < shown; i++)
            Positioned(
              left: axis == Axis.horizontal ? i * gap : 0,
              top: axis == Axis.vertical ? i * gap : 0,
              child: HareegCardView(
                theme: theme,
                card: reveal && i < faceUpCards.length
                    ? faceUpCards[i]
                    : _backSeed(i),
                faceDown: !reveal || i >= faceUpCards.length,
                size: cardSize,
              ),
            ),
        ],
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
