import 'package:flutter/material.dart';

import '../../../domain/classic_hareeg/models/playing_card.dart';

/// Shared suit glyph painting helpers used by code-rendered themes.
///
/// Returns a [Path] for each suit centered in a unit square (0..1 in both
/// axes). Callers can scale and translate as needed without each theme
/// re-deriving the geometry. The four shapes are tuned for clarity at small
/// sizes — compact meld cards stay legible at 18 dp glyphs.
abstract final class SuitGlyphs {
  /// Returns a path for the suit, sized to fit a 1x1 square.
  static Path pathFor(CardSuit suit) {
    return switch (suit) {
      CardSuit.spades => _spadesPath(),
      CardSuit.hearts => _heartsPath(),
      CardSuit.diamonds => _diamondsPath(),
      CardSuit.clubs => _clubsPath(),
    };
  }

  /// Compact symbol used in inline labels (e.g., 'AS').
  static String symbolFor(CardSuit suit) {
    return switch (suit) {
      CardSuit.spades => '♠',
      CardSuit.hearts => '♥',
      CardSuit.diamonds => '♦',
      CardSuit.clubs => '♣',
    };
  }

  static Path _spadesPath() {
    final path = Path();
    path.moveTo(0.5, 0.05);
    path.cubicTo(0.95, 0.45, 1.05, 0.65, 0.62, 0.78);
    path.cubicTo(0.58, 0.82, 0.6, 0.88, 0.72, 0.95);
    path.lineTo(0.28, 0.95);
    path.cubicTo(0.4, 0.88, 0.42, 0.82, 0.38, 0.78);
    path.cubicTo(-0.05, 0.65, 0.05, 0.45, 0.5, 0.05);
    path.close();
    return path;
  }

  static Path _heartsPath() {
    final path = Path();
    path.moveTo(0.5, 0.95);
    path.cubicTo(-0.05, 0.6, 0.05, 0.15, 0.5, 0.3);
    path.cubicTo(0.95, 0.15, 1.05, 0.6, 0.5, 0.95);
    path.close();
    return path;
  }

  static Path _diamondsPath() {
    final path = Path();
    path.moveTo(0.5, 0.05);
    path.lineTo(0.9, 0.5);
    path.lineTo(0.5, 0.95);
    path.lineTo(0.1, 0.5);
    path.close();
    return path;
  }

  static Path _clubsPath() {
    final path = Path();
    path.addOval(Rect.fromCircle(center: const Offset(0.5, 0.28), radius: 0.18));
    path.addOval(Rect.fromCircle(center: const Offset(0.3, 0.58), radius: 0.18));
    path.addOval(Rect.fromCircle(center: const Offset(0.7, 0.58), radius: 0.18));
    path.moveTo(0.42, 0.7);
    path.cubicTo(0.4, 0.85, 0.45, 0.9, 0.5, 0.95);
    path.cubicTo(0.55, 0.9, 0.6, 0.85, 0.58, 0.7);
    path.close();
    return path;
  }
}
