import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../domain/classic_hareeg/rules/opening_rules.dart'
    show PlacedMeld;
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/cards/card_view.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Layout orientation for an opponent seat.
enum OpponentSeatOrientation { west, north, east }

/// Opponent seat panel. Single-column for west/east, single-row for north.
///
/// Uses fixed-pixel inner sizing to stay overflow-free across viewport sizes
/// without needing IntrinsicWidth / IntrinsicHeight passes. Final tactile
/// polish (deck-back fan curvature, opponent meld lane expansion behaviour)
/// is left for the manual maintainer pass — see the PR notes.
class OpponentSeatPanel extends StatelessWidget {
  /// Creates an opponent seat panel.
  const OpponentSeatPanel({
    super.key,
    required this.seat,
    required this.label,
    required this.cardCount,
    required this.orientation,
    required this.theme,
    required this.isCurrentTurn,
    required this.isThinking,
    required this.isEliminated,
    required this.melds,
    this.onTapMelds,
  });

  /// Seat identity.
  final PlayerSeat seat;

  /// Display label.
  final String label;

  /// Card count.
  final int cardCount;

  /// Layout orientation.
  final OpponentSeatOrientation orientation;

  /// Active card theme.
  final HareegCardTheme theme;

  /// True if this seat is taking its turn.
  final bool isCurrentTurn;

  /// True if the CPU is currently thinking on this seat.
  final bool isThinking;

  /// True if this seat is eliminated.
  final bool isEliminated;

  /// Melds owned by this seat.
  final List<PlacedMeld> melds;

  /// Tap callback to focus the meld zone.
  final VoidCallback? onTapMelds;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final isHorizontal = orientation == OpponentSeatOrientation.north;
    final body = isHorizontal
        ? _horizontalBody(strings)
        : _verticalBody(strings);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(
        horizontal: LoungeTokens.space2,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: LoungeTokens.feltRaised.withValues(
          alpha: isEliminated ? 0.4 : 0.6,
        ),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
        border: Border.all(
          color: isCurrentTurn
              ? LoungeTokens.goldAccent
              : LoungeTokens.sandLine.withValues(alpha: 0.35),
          width: isCurrentTurn ? 2 : 1,
        ),
      ),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: isEliminated ? 0.45 : 1.0,
        child: body,
      ),
    );
  }

  Widget _horizontalBody(AppStrings strings) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _badge(),
        _MiniHand(
          theme: theme,
          count: cardCount,
          cardSize: const Size(20, 28),
          spacing: 4,
        ),
        _meldsCountChip(strings),
      ],
    );
  }

  Widget _verticalBody(AppStrings strings) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _badge(),
        const SizedBox(height: 6),
        _MiniHand(
          theme: theme,
          count: cardCount,
          cardSize: const Size(24, 34),
          spacing: 5,
          maxWidth: 80,
        ),
        const SizedBox(height: 6),
        _meldsCountChip(strings),
        if (isEliminated) ...[
          const SizedBox(height: 6),
          Text(
            strings.eliminated,
            style: const TextStyle(
              color: LoungeTokens.mutedText,
              fontSize: 10,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ],
    );
  }

  Widget _badge() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.smart_toy,
          size: 13,
          color: isCurrentTurn
              ? LoungeTokens.goldAccent
              : LoungeTokens.mutedText,
        ),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isCurrentTurn
                  ? LoungeTokens.offWhiteText
                  : LoungeTokens.mutedText,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 0.6,
            ),
          ),
        ),
        if (isThinking) ...[
          const SizedBox(width: 4),
          const SizedBox(
            width: 7,
            height: 7,
            child: CircularProgressIndicator(
              strokeWidth: 1.4,
              color: LoungeTokens.goldAccent,
            ),
          ),
        ],
      ],
    );
  }

  Widget _meldsCountChip(AppStrings strings) {
    return GestureDetector(
      onTap: onTapMelds,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: LoungeTokens.coffeeCharcoal,
          borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
          border: Border.all(
            color: LoungeTokens.sandLine.withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          strings.meldsAndCardsCount(melds.length, cardCount),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: LoungeTokens.offWhiteText,
            fontWeight: FontWeight.w700,
            fontSize: 11,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

class _MiniHand extends StatelessWidget {
  const _MiniHand({
    required this.theme,
    required this.count,
    required this.cardSize,
    required this.spacing,
    this.maxWidth = 200,
  });

  final HareegCardTheme theme;
  final int count;
  final Size cardSize;
  final double spacing;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return SizedBox(width: cardSize.width, height: cardSize.height);
    }
    final visible = count.clamp(1, 6);
    final stripWidth =
        cardSize.width + (visible - 1) * (cardSize.width - spacing);
    final width = stripWidth.clamp(cardSize.width, maxWidth).toDouble();
    final placeholder = HareegCard.standard(
      rank: CardRank.ace,
      suit: CardSuit.spades,
      deckIndex: 0,
    );
    return SizedBox(
      width: width,
      height: cardSize.height,
      child: ClipRect(
        child: Stack(
          children: [
            for (var i = 0; i < visible; i++)
              Positioned(
                left: i * (cardSize.width - spacing),
                top: 0,
                child: HareegCardView(
                  theme: theme,
                  card: placeholder,
                  variant: CardVariant.compact,
                  faceDown: true,
                  size: cardSize,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
