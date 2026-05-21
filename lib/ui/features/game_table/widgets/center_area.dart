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

/// Central play surface: stock pile, discard pile, Fifty ring, and the
/// south seat's own meld lane.
class TableCenterArea extends StatelessWidget {
  /// Creates the centre area.
  const TableCenterArea({
    super.key,
    required this.theme,
    required this.stockCount,
    required this.topDiscard,
    required this.pendingDiscard,
    required this.southMelds,
    required this.fiftySecondsRemaining,
    required this.fiftyTotalSeconds,
    required this.fiftyPulse,
    required this.canDrawStock,
    required this.canTakeDiscard,
    required this.canClaimFifty,
    required this.onDrawStock,
    required this.onTakeDiscard,
    required this.onClaimFifty,
  });

  /// Active card theme.
  final HareegCardTheme theme;

  /// Stock pile size.
  final int stockCount;

  /// Top of the discard pile (null when empty).
  final HareegCard? topDiscard;

  /// Active pending discard (rendered with pending overlay).
  final HareegCard? pendingDiscard;

  /// South seat's own melds.
  final List<PlacedMeld> southMelds;

  /// Seconds remaining in the Fifty window, or null when no window.
  final int? fiftySecondsRemaining;

  /// Fifty timer total (seconds).
  final int fiftyTotalSeconds;

  /// True to fire the one-shot heat pulse.
  final bool fiftyPulse;

  /// True if the human can draw from stock.
  final bool canDrawStock;

  /// True if the human can take the top discard.
  final bool canTakeDiscard;

  /// True if the human can claim Fifty.
  final bool canClaimFifty;

  /// Draw-from-stock callback.
  final VoidCallback onDrawStock;

  /// Take-discard callback.
  final VoidCallback onTakeDiscard;

  /// Claim-Fifty callback.
  final VoidCallback onClaimFifty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(LoungeTokens.space2),
      decoration: BoxDecoration(
        color: LoungeTokens.feltSpotlight.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.25),
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: SizedBox(
            width: 480,
            height: 120,
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _StockPile(
                    theme: theme,
                    count: stockCount,
                    canDraw: canDrawStock,
                    onDraw: onDrawStock,
                  ),
                ),
                const SizedBox(width: LoungeTokens.space2),
                Expanded(
                  flex: 3,
                  child: _FiftyAndDiscard(
                    theme: theme,
                    topDiscard: topDiscard,
                    pendingDiscard: pendingDiscard,
                    fiftySecondsRemaining: fiftySecondsRemaining,
                    fiftyTotalSeconds: fiftyTotalSeconds,
                    fiftyPulse: fiftyPulse,
                    canTakeDiscard: canTakeDiscard,
                    canClaimFifty: canClaimFifty,
                    onTakeDiscard: onTakeDiscard,
                    onClaimFifty: onClaimFifty,
                  ),
                ),
                const SizedBox(width: LoungeTokens.space2),
                Expanded(
                  flex: 2,
                  child: _SouthMeldLane(theme: theme, melds: southMelds),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StockPile extends StatelessWidget {
  const _StockPile({
    required this.theme,
    required this.count,
    required this.canDraw,
    required this.onDraw,
  });

  final HareegCardTheme theme;
  final int count;
  final bool canDraw;
  final VoidCallback onDraw;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(strings.stock, style: LoungeTokens.bodyMuted),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: canDraw ? onDraw : null,
          behavior: HitTestBehavior.opaque,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: canDraw ? 1 : 0.6,
            child: _PileStack(
              theme: theme,
              count: count,
              faceDown: true,
              isInteractive: canDraw,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text('$count', style: LoungeTokens.numericChip),
      ],
    );
  }
}

class _FiftyAndDiscard extends StatelessWidget {
  const _FiftyAndDiscard({
    required this.theme,
    required this.topDiscard,
    required this.pendingDiscard,
    required this.fiftySecondsRemaining,
    required this.fiftyTotalSeconds,
    required this.fiftyPulse,
    required this.canTakeDiscard,
    required this.canClaimFifty,
    required this.onTakeDiscard,
    required this.onClaimFifty,
  });

  final HareegCardTheme theme;
  final HareegCard? topDiscard;
  final HareegCard? pendingDiscard;
  final int? fiftySecondsRemaining;
  final int fiftyTotalSeconds;
  final bool fiftyPulse;
  final bool canTakeDiscard;
  final bool canClaimFifty;
  final VoidCallback onTakeDiscard;
  final VoidCallback onClaimFifty;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final hasFifty = fiftySecondsRemaining != null;
    final displayCard = pendingDiscard ?? topDiscard;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(strings.discard, style: LoungeTokens.bodyMuted),
        const SizedBox(height: 4),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (displayCard != null)
                GestureDetector(
                  onTap: canTakeDiscard ? onTakeDiscard : null,
                  behavior: HitTestBehavior.opaque,
                  child: HareegCardView(
                    theme: theme,
                    card: displayCard,
                    variant: CardVariant.full,
                    size: const Size(54, 78),
                    visualState: pendingDiscard != null
                        ? CardVisualState.pending
                        : (canTakeDiscard
                              ? CardVisualState.coverTarget
                              : CardVisualState.normal),
                  ),
                )
              else
                const _EmptyDiscardPlaceholder(),
              if (hasFifty)
                Positioned(
                  right: 0,
                  top: 0,
                  child: GestureDetector(
                    onTap: canClaimFifty ? onClaimFifty : null,
                    child: FiftyRing(
                      secondsRemaining: fiftySecondsRemaining,
                      totalSeconds: fiftyTotalSeconds,
                      pulse: fiftyPulse,
                      diameter: 56,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SouthMeldLane extends StatelessWidget {
  const _SouthMeldLane({required this.theme, required this.melds});

  final HareegCardTheme theme;
  final List<PlacedMeld> melds;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.meldZone, style: LoungeTokens.bodyMuted),
        const SizedBox(height: 4),
        Expanded(
          child: melds.isEmpty
              ? const _EmptyMeldsPlaceholder()
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      for (final meld in melds) ...[
                        _SouthMeld(theme: theme, cards: meld.cards),
                        const SizedBox(width: LoungeTokens.space2),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _SouthMeld extends StatelessWidget {
  const _SouthMeld({required this.theme, required this.cards});

  final HareegCardTheme theme;
  final List<HareegCard> cards;

  static const _cardSize = Size(34, 50);

  @override
  Widget build(BuildContext context) {
    final overlap = _cardSize.width * 0.55;
    return SizedBox(
      height: _cardSize.height,
      width: _cardSize.width + overlap * (cards.length - 1),
      child: Stack(
        children: [
          for (var i = 0; i < cards.length; i++)
            Positioned(
              left: i * overlap,
              child: HareegCardView(
                theme: theme,
                card: cards[i],
                variant: CardVariant.compact,
                size: _cardSize,
              ),
            ),
        ],
      ),
    );
  }
}

class _PileStack extends StatelessWidget {
  const _PileStack({
    required this.theme,
    required this.count,
    required this.faceDown,
    required this.isInteractive,
  });

  final HareegCardTheme theme;
  final int count;
  final bool faceDown;
  final bool isInteractive;

  @override
  Widget build(BuildContext context) {
    final layers = count.clamp(0, 4);
    if (layers == 0) {
      return const _EmptyDiscardPlaceholder();
    }
    final tokenCard = HareegCard.standard(
      rank: CardRank.ace,
      suit: CardSuit.spades,
      deckIndex: 0,
    );
    return SizedBox(
      width: 52,
      height: 70,
      child: Stack(
        children: [
          for (var i = 0; i < layers; i++)
            Positioned(
              left: i * 2.0,
              top: i * 1.0,
              child: HareegCardView(
                theme: theme,
                card: tokenCard,
                variant: CardVariant.full,
                faceDown: faceDown,
                size: const Size(46, 67),
                visualState: i == layers - 1 && isInteractive
                    ? CardVisualState.coverTarget
                    : CardVisualState.normal,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyDiscardPlaceholder extends StatelessWidget {
  const _EmptyDiscardPlaceholder();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Container(
      width: 46,
      height: 67,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LoungeTokens.radiusCard),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.45),
          width: 1.2,
        ),
        color: LoungeTokens.coffeeCharcoal,
      ),
      alignment: Alignment.center,
      child: Text(strings.empty, style: LoungeTokens.bodyMuted),
    );
  }
}

class _EmptyMeldsPlaceholder extends StatelessWidget {
  const _EmptyMeldsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LoungeTokens.radiusCard),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.25),
        ),
      ),
      alignment: Alignment.center,
      child: Text(strings.noMeldsYet, style: LoungeTokens.bodyMuted),
    );
  }
}

/// Re-export for orchestrator convenience: which seat owns the south meld
/// lane displayed in the centre area.
const PlayerSeat southMeldOwner = PlayerSeat.south;
