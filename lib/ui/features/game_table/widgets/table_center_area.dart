import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_state.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/cards/card_view.dart';
import '../../../core/theme/lounge_tokens.dart';
import 'fifty_ring.dart';

/// Bottom-left stock pile with a remaining-count badge and draw tap.
class TableStockPile extends StatelessWidget {
  /// Creates a stock pile.
  const TableStockPile({
    super.key,
    required this.theme,
    required this.count,
    required this.cardSize,
    required this.compact,
    required this.canDraw,
    required this.onDraw,
  });

  /// Card theme used for placeholder backs.
  final HareegCardTheme theme;

  /// Remaining stock count to display.
  final int count;

  /// Card size used by each back.
  final Size cardSize;

  /// Whether the table is rendering in compact mode.
  final bool compact;

  /// Whether a stock draw is currently legal.
  final bool canDraw;

  /// Callback fired when the player taps to draw.
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

/// Centre discard pile, the only discard `DragTarget` in the playfield.
///
/// Shows at most the top card (or pending-discard ghost) plus the previous
/// discard as a quiet ghost below. The drop hit area is intentionally larger
/// than the visible pile so the player doesn't need pixel-precise aim — any
/// release within the generous box discards.
class TableDiscardPile extends StatelessWidget {
  /// Creates a discard pile.
  const TableDiscardPile({
    super.key,
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

  /// Card theme used for face-up rendering.
  final HareegCardTheme theme;

  /// Discard pile from oldest to newest.
  final List<HareegCard> discardPile;

  /// Live top of the discard pile, or null when empty.
  final HareegCard? topDiscard;

  /// Pending discard awaiting use-or-return, if any.
  final HareegCard? pendingDiscard;

  /// Card size used for the visible top/ghost cards.
  final Size cardSize;

  /// Whether the player may currently take the discard.
  final bool canTake;

  /// Whether the player may currently return a pending discard.
  final bool canReturn;

  /// Callback fired when the player taps to take the discard.
  final VoidCallback onTake;

  /// Callback fired when the player taps to return the pending discard.
  final VoidCallback onReturn;

  /// Predicate for whether a drop card is a legal discard.
  final bool Function(HareegCard card) canAcceptDiscard;

  /// Callback fired when a card is dropped onto the discard pile.
  final ValueChanged<HareegCard> onAcceptDiscard;

  /// Callback fired when the top card is long-pressed.
  final ValueChanged<HareegCard> onCardLongPress;

  /// Whether the table is rendering in compact mode.
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

/// Tap-to-claim Fifty cue overlaid above the discard pile.
class TableFiftyCue extends StatelessWidget {
  /// Creates a Fifty cue.
  const TableFiftyCue({
    super.key,
    required this.secondsRemaining,
    required this.totalSeconds,
    required this.pulse,
    required this.diameter,
    required this.canClaim,
    required this.onClaim,
  });

  /// Seconds left in the active Fifty window.
  final int secondsRemaining;

  /// Configured Fifty window duration.
  final int totalSeconds;

  /// Whether the ring should pulse for visibility.
  final bool pulse;

  /// Diameter of the ring container.
  final double diameter;

  /// Whether claiming Fifty is currently legal.
  final bool canClaim;

  /// Callback fired when the cue is tapped.
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
