import 'dart:ui';

import '../../../domain/classic_hareeg/models/playing_card.dart';

/// Classic English-pattern pip layouts for the numbered ranks.
abstract final class CardPipLayout {
  /// Centre-pip positions for [rank] as fractions of the card's width and
  /// height. Court cards return an empty list (they paint a single glyph).
  static List<Offset> positionsFor(CardRank rank) {
    // Pip layouts follow the classic English-pattern deck. Outer rows hug
    // the top and bottom edges so the centre of the face can breathe, and
    // the pip painter rotates anything below the midline so suit glyphs
    // face the holder. The column stops 0.32 / 0.68 and edge rows at 0.2 /
    // 0.8 stay consistent across ranks so the eye reads each card as part
    // of the same family.
    const colLeft = 0.32;
    const colRight = 0.68;
    const colMid = 0.5;
    const rowTop = 0.2;
    const rowBottom = 0.8;
    switch (rank) {
      case CardRank.ace:
        return const [Offset(colMid, 0.5)];
      case CardRank.two:
        return const [Offset(colMid, rowTop), Offset(colMid, rowBottom)];
      case CardRank.three:
        return const [
          Offset(colMid, rowTop),
          Offset(colMid, 0.5),
          Offset(colMid, rowBottom),
        ];
      case CardRank.four:
        return const [
          Offset(colLeft, rowTop),
          Offset(colRight, rowTop),
          Offset(colLeft, rowBottom),
          Offset(colRight, rowBottom),
        ];
      case CardRank.five:
        return const [
          Offset(colLeft, rowTop),
          Offset(colRight, rowTop),
          Offset(colMid, 0.5),
          Offset(colLeft, rowBottom),
          Offset(colRight, rowBottom),
        ];
      case CardRank.six:
        return const [
          Offset(colLeft, rowTop),
          Offset(colRight, rowTop),
          Offset(colLeft, 0.5),
          Offset(colRight, 0.5),
          Offset(colLeft, rowBottom),
          Offset(colRight, rowBottom),
        ];
      case CardRank.seven:
        // 2 + 1 + 2 + 2 — the upper-half singleton is the visual signature
        // that makes a 7 readable at a glance.
        return const [
          Offset(colLeft, rowTop),
          Offset(colRight, rowTop),
          Offset(colMid, 0.35),
          Offset(colLeft, 0.5),
          Offset(colRight, 0.5),
          Offset(colLeft, rowBottom),
          Offset(colRight, rowBottom),
        ];
      case CardRank.eight:
        // 2 + 1 + 2 + 1 + 2 — symmetric around the midline.
        return const [
          Offset(colLeft, rowTop),
          Offset(colRight, rowTop),
          Offset(colMid, 0.35),
          Offset(colLeft, 0.5),
          Offset(colRight, 0.5),
          Offset(colMid, 0.65),
          Offset(colLeft, rowBottom),
          Offset(colRight, rowBottom),
        ];
      case CardRank.nine:
        // 2 + 2 + 1 + 2 + 2 — two quad clusters with a centre pip.
        return const [
          Offset(colLeft, rowTop),
          Offset(colRight, rowTop),
          Offset(colLeft, 0.4),
          Offset(colRight, 0.4),
          Offset(colMid, 0.5),
          Offset(colLeft, 0.6),
          Offset(colRight, 0.6),
          Offset(colLeft, rowBottom),
          Offset(colRight, rowBottom),
        ];
      case CardRank.ten:
        // 2 + 1 + 2 + 2 + 1 + 2 — classic English-pattern 10 with the
        // singletons tucked between the outer and inner pairs.
        return const [
          Offset(colLeft, rowTop),
          Offset(colRight, rowTop),
          Offset(colMid, 0.32),
          Offset(colLeft, 0.44),
          Offset(colRight, 0.44),
          Offset(colLeft, 0.56),
          Offset(colRight, 0.56),
          Offset(colMid, 0.68),
          Offset(colLeft, rowBottom),
          Offset(colRight, rowBottom),
        ];
      case CardRank.jack:
      case CardRank.queen:
      case CardRank.king:
        return const [];
    }
  }
}
