import 'package:flutter/material.dart';

import '../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../l10n/app_strings.dart';
import '../scopes/app_scopes.dart';
import 'card_theme.dart';
import 'card_view.dart';

/// Small fanned showcase hand used by the splash and main menu.
class ShowcaseCardFan extends StatelessWidget {
  /// Creates a themed showcase card fan.
  const ShowcaseCardFan({
    super.key,
    required this.width,
    required this.height,
    this.maxAngle = 0.52,
    this.stepSpread = 22,
    this.outerDrop = 10,
  });

  /// Fan bounds.
  final double width;
  final double height;

  /// Half-angle of the outermost card from vertical, in radians.
  final double maxAngle;

  /// Horizontal offset between adjacent card pivots.
  final double stepSpread;

  /// Vertical drop applied to the outer cards so inner cards remain visible.
  final double outerDrop;

  static final List<HareegCard> _showcase = [
    HareegCard.standard(
      rank: CardRank.king,
      suit: CardSuit.spades,
      deckIndex: 0,
    ),
    HareegCard.standard(
      rank: CardRank.queen,
      suit: CardSuit.hearts,
      deckIndex: 0,
    ),
    const HareegCard.joker(deckIndex: 0, jokerIndex: 0),
    HareegCard.standard(
      rank: CardRank.jack,
      suit: CardSuit.diamonds,
      deckIndex: 0,
    ),
    HareegCard.standard(rank: CardRank.ace, suit: CardSuit.clubs, deckIndex: 0),
  ];

  static const _paintOrder = [0, 4, 1, 3, 2];

  @override
  Widget build(BuildContext context) {
    final theme = CardThemeScope.of(context);
    final strings = context.strings;
    final cardSize = Size(width * 0.31, height * 0.8);
    final midpoint = (_showcase.length - 1) / 2;

    return Semantics(
      label: strings.cardThemePreview(theme.label),
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            for (final index in _paintOrder)
              _FannedCardSlot(
                card: _showcase[index],
                theme: theme,
                size: cardSize,
                offsetFromCenter: index - midpoint,
                midpoint: midpoint,
                maxAngle: maxAngle,
                stepSpread: stepSpread,
                outerDrop: outerDrop,
              ),
          ],
        ),
      ),
    );
  }
}

class _FannedCardSlot extends StatelessWidget {
  const _FannedCardSlot({
    required this.card,
    required this.theme,
    required this.size,
    required this.offsetFromCenter,
    required this.midpoint,
    required this.maxAngle,
    required this.stepSpread,
    required this.outerDrop,
  });

  final HareegCard card;
  final HareegCardTheme theme;
  final Size size;
  final double offsetFromCenter;
  final double midpoint;
  final double maxAngle;
  final double stepSpread;
  final double outerDrop;

  @override
  Widget build(BuildContext context) {
    final normalized = offsetFromCenter / midpoint;
    return Transform.translate(
      offset: Offset(
        offsetFromCenter * stepSpread,
        normalized.abs() * outerDrop,
      ),
      child: Transform.rotate(
        angle: normalized * maxAngle,
        alignment: Alignment.bottomCenter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                offset: Offset(0, 2),
                blurRadius: 3,
              ),
            ],
          ),
          child: HareegCardView(
            theme: theme,
            card: card,
            variant: CardVariant.picker,
            size: size,
            jokerDisplay: JokerDisplay.assisted,
          ),
        ),
      ),
    );
  }
}
