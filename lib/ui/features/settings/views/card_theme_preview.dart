import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../core/cards/card_state.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/cards/card_view.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Trio of cards used to preview a [HareegCardTheme] in the picker.
class CardThemePreview extends StatelessWidget {
  /// Creates a preview.
  const CardThemePreview({super.key, required this.theme});

  /// Theme being previewed.
  final HareegCardTheme theme;

  static final _cards = [
    HareegCard.standard(
      rank: CardRank.ace,
      suit: CardSuit.spades,
      deckIndex: 0,
    ),
    HareegCard.standard(
      rank: CardRank.king,
      suit: CardSuit.hearts,
      deckIndex: 0,
    ),
    const HareegCard.joker(deckIndex: 0, jokerIndex: 0),
  ];

  static const _size = Size(38, 56);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size.width * 3 + LoungeTokens.space2 * 2,
      height: _size.height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _cards.length; i++) ...[
            HareegCardView(
              theme: theme,
              card: _cards[i],
              variant: CardVariant.picker,
              size: _size,
              visualState: i == 1
                  ? CardVisualState.selected
                  : CardVisualState.normal,
              jokerDisplay: JokerDisplay.assisted,
            ),
            if (i < _cards.length - 1)
              const SizedBox(width: LoungeTokens.space2),
          ],
        ],
      ),
    );
  }
}
