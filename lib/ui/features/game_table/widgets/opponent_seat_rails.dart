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
  });

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
      stackSize.width + (compact ? 18 : 24),
      stackSize.height + (compact ? 14 : 18),
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
            child: _CardBackStack(
              theme: theme,
              count: count,
              axis: Axis.horizontal,
              cardSize: cardSize,
              visibleCount: visibleCount,
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
  });

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
      stackSize.width + (compact ? 14 : 18),
      stackSize.height + (compact ? 18 : 24),
    );
    return Opacity(
      opacity: eliminated ? 0.28 : 1,
      child: Align(
        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
        child: _TurnCueFrame(
          active: active,
          thinking: thinking,
          size: cueSize,
          child: _CardBackStack(
            theme: theme,
            count: count,
            axis: Axis.vertical,
            cardSize: cardSize,
            visibleCount: visibleCount,
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

class _CardBackStack extends StatelessWidget {
  const _CardBackStack({
    required this.theme,
    required this.count,
    required this.axis,
    required this.cardSize,
    required this.visibleCount,
  });

  final HareegCardTheme theme;
  final int count;
  final Axis axis;
  final Size cardSize;
  final int visibleCount;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
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
                card: _backSeed(i),
                faceDown: true,
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
