import 'package:flutter/material.dart';

import '../../../domain/classic_hareeg/models/playing_card.dart';
import '../motif/geometric_motif_painter.dart';
import '../theme/lounge_tokens.dart';
import 'card_state.dart';
import 'card_theme.dart';
import 'suit_glyphs.dart';

/// Shared card painting helpers used by every code-rendered theme.
///
/// Provides background fills, corner rank/suit indices, centre pip layouts,
/// joker treatments, default card-back rendering, and the state-overlay
/// painter that wraps the face. Per-theme palette differences flow in via
/// [CardThemePalette].
class CardThemePalette {
  /// Creates a palette descriptor.
  const CardThemePalette({
    required this.faceBackground,
    required this.faceBorder,
    required this.faceShadow,
    required this.redSuit,
    required this.blackSuit,
    required this.jokerAccent,
    required this.backPrimary,
    required this.backSecondary,
    required this.backOrnament,
    required this.faceText,
    this.minimalGlyph = false,
    this.faceBorderWidth = 1.2,
  });

  /// Card face fill.
  final Color faceBackground;

  /// Card face border colour.
  final Color faceBorder;

  /// Card face border width.
  final double faceBorderWidth;

  /// Drop shadow colour underneath the face.
  final Color faceShadow;

  /// Colour for hearts / diamonds.
  final Color redSuit;

  /// Colour for spades / clubs.
  final Color blackSuit;

  /// Accent colour for jokers.
  final Color jokerAccent;

  /// Primary card-back tint.
  final Color backPrimary;

  /// Secondary back tint (used for a subtle gradient).
  final Color backSecondary;

  /// Sand-line tone for the back ornament strokes.
  final Color backOrnament;

  /// Text colour for the rank label / joker word.
  final Color faceText;

  /// If true, the centre pip layout is replaced by a single oversized glyph
  /// (used by the Minimal Symbols theme).
  final bool minimalGlyph;

  /// Returns the suit colour.
  Color colorFor(CardSuit suit) {
    return switch (suit) {
      CardSuit.hearts || CardSuit.diamonds => redSuit,
      CardSuit.spades || CardSuit.clubs => blackSuit,
    };
  }
}

/// Static helpers that paint generic card surfaces given a [CardThemePalette].
abstract final class CardPainting {
  /// Draws the card body (background, border, shadow) sized to [request.size].
  static void paintBody(
    Canvas canvas,
    CardRenderRequest request,
    CardThemePalette palette,
  ) {
    final size = request.size;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(_radiusFor(size)),
    );

    final shadow = Paint()
      ..color = palette.faceShadow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
    canvas.drawRRect(rrect.shift(const Offset(0, 1.2)), shadow);

    final background = Paint()..color = palette.faceBackground;
    canvas.drawRRect(rrect, background);

    final border = Paint()
      ..color = palette.faceBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = palette.faceBorderWidth;
    canvas.drawRRect(rrect, border);
  }

  /// Paints a standard face: corner indices, centre pips, watermark.
  static void paintStandardFace(
    Canvas canvas,
    CardRenderRequest request,
    CardThemePalette palette,
  ) {
    final identity = request.card.effectiveIdentity;
    if (identity == null) {
      paintJokerFace(canvas, request, palette);
      return;
    }
    final suitColor = palette.colorFor(identity.suit);
    _paintCorners(canvas, request, palette, identity, suitColor);

    if (palette.minimalGlyph || request.variant != CardVariant.full) {
      _paintCenterGlyph(canvas, request, identity, suitColor);
    } else {
      _paintCenterPips(canvas, request, identity, suitColor);
    }

    if (request.card.isJoker) {
      _paintJokerBadge(canvas, request, palette);
    }

    if (request.badge == CardBadge.deckCopy) {
      _paintDeckCopyDot(canvas, request, palette);
    }
  }

  /// Paints a joker face (no real suit / rank).
  static void paintJokerFace(
    Canvas canvas,
    CardRenderRequest request,
    CardThemePalette palette,
  ) {
    final size = request.size;
    final paint = Paint()..color = palette.jokerAccent.withValues(alpha: 0.16);
    canvas.drawCircle(size.center(Offset.zero), size.shortestSide * 0.32, paint);

    final stroke = Paint()
      ..color = palette.jokerAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(size.center(Offset.zero), size.shortestSide * 0.32, stroke);

    final tp = TextPainter(
      text: TextSpan(
        text: 'J',
        style: TextStyle(
          color: palette.jokerAccent,
          fontWeight: FontWeight.w900,
          fontSize: size.shortestSide * 0.42,
          letterSpacing: -1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        (size.width - tp.width) / 2,
        (size.height - tp.height) / 2,
      ),
    );

    final represented = request.card.representedIdentity;
    if (represented != null && request.jokerDisplay != JokerDisplay.unassigned) {
      _paintJokerRepresented(canvas, request, palette, represented);
    }
  }

  /// Paints the default geometric-motif card back.
  static void paintBack(
    Canvas canvas,
    CardRenderRequest request,
    CardThemePalette palette,
  ) {
    final size = request.size;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(_radiusFor(size)),
    );
    final shadow = Paint()
      ..color = palette.faceShadow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4);
    canvas.drawRRect(rrect.shift(const Offset(0, 1.4)), shadow);

    final gradient = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [palette.backPrimary, palette.backSecondary],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(rrect, gradient);

    final border = Paint()
      ..color = palette.backOrnament
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(rrect.deflate(2.5), border);

    canvas.save();
    final inset = size.shortestSide * 0.14;
    canvas.translate(inset, inset);
    final medallionSize = Size(
      size.width - inset * 2,
      size.height - inset * 2,
    );
    GeometricMotifPainter(
      variant: LoungeMotifVariant.medallion,
      color: palette.backOrnament,
      opacity: 0.7,
      strokeWidth: 1.0,
      density: 3,
    ).paint(canvas, medallionSize);
    canvas.restore();
  }

  /// Applies the state outline / glow / tint described by [overlay].
  static void paintStateOverlay(
    Canvas canvas,
    Size size,
    CardStateOverlayStyle overlay,
  ) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(_radiusFor(size)),
    );

    final tint = overlay.tint;
    if (tint != null) {
      canvas.drawRRect(rrect, Paint()..color = tint);
    }

    final glow = overlay.glow;
    if (glow != null) {
      final glowPaint = Paint()
        ..color = glow
        ..style = PaintingStyle.stroke
        ..strokeWidth = overlay.outlineWidth + 4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawRRect(rrect, glowPaint);
    }

    if (overlay.outlineWidth > 0 && overlay.outline.a > 0) {
      final outline = Paint()
        ..color = overlay.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = overlay.outlineWidth;
      canvas.drawRRect(rrect, outline);
    }
  }

  // -- internals -----------------------------------------------------------

  static double _radiusFor(Size size) =>
      (size.shortestSide * 0.12).clamp(4.0, LoungeTokens.radiusCard);

  static void _paintCorners(
    Canvas canvas,
    CardRenderRequest request,
    CardThemePalette palette,
    CardIdentity identity,
    Color suitColor,
  ) {
    final size = request.size;
    final fontSize = (size.shortestSide * 0.26).clamp(9.0, 18.0);
    final glyphSize = (size.shortestSide * 0.22).clamp(6.0, 14.0);
    final padding = size.shortestSide * 0.08;

    final rankLabel = identity.rank.label;
    final span = TextSpan(
      text: rankLabel,
      style: TextStyle(
        color: palette.faceText,
        fontWeight: FontWeight.w800,
        fontSize: fontSize,
        height: 1.0,
        letterSpacing: -0.3,
      ),
    );

    final topPainter = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout();
    topPainter.paint(canvas, Offset(padding, padding * 0.6));

    canvas.save();
    canvas.translate(
      padding + glyphSize * 0.05,
      padding * 0.6 + topPainter.height,
    );
    _paintSuitGlyph(canvas, identity.suit, suitColor, glyphSize);
    canvas.restore();

    // Bottom-right rotated 180 degrees for traditional readability.
    canvas.save();
    canvas.translate(size.width, size.height);
    canvas.rotate(3.141592653589793);
    topPainter.paint(canvas, Offset(padding, padding * 0.6));
    canvas.translate(
      padding + glyphSize * 0.05,
      padding * 0.6 + topPainter.height,
    );
    _paintSuitGlyph(canvas, identity.suit, suitColor, glyphSize);
    canvas.restore();
  }

  static void _paintCenterGlyph(
    Canvas canvas,
    CardRenderRequest request,
    CardIdentity identity,
    Color color,
  ) {
    final size = request.size;
    final rankSize = size.shortestSide * 0.55;
    final tp = TextPainter(
      text: TextSpan(
        text: identity.rank.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: rankSize,
          height: 1.0,
          letterSpacing: -1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        (size.width - tp.width) / 2,
        (size.height - tp.height) / 2 - size.height * 0.06,
      ),
    );

    final glyph = size.shortestSide * 0.18;
    canvas.save();
    canvas.translate(
      (size.width - glyph) / 2,
      size.height * 0.65,
    );
    _paintSuitGlyph(canvas, identity.suit, color, glyph);
    canvas.restore();
  }

  static void _paintCenterPips(
    Canvas canvas,
    CardRenderRequest request,
    CardIdentity identity,
    Color color,
  ) {
    final size = request.size;
    final positions = _pipPositionsFor(identity.rank);
    if (positions.isEmpty) {
      _paintCenterGlyph(canvas, request, identity, color);
      return;
    }
    final pipSize = size.shortestSide * 0.18;
    for (final pos in positions) {
      canvas.save();
      final cx = size.width * pos.dx;
      final cy = size.height * pos.dy;
      canvas.translate(cx - pipSize / 2, cy - pipSize / 2);
      if (pos.dy > 0.5) {
        canvas.translate(pipSize, pipSize);
        canvas.rotate(3.141592653589793);
      }
      _paintSuitGlyph(canvas, identity.suit, color, pipSize);
      canvas.restore();
    }
  }

  static void _paintSuitGlyph(
    Canvas canvas,
    CardSuit suit,
    Color color,
    double size,
  ) {
    final path = SuitGlyphs.pathFor(suit);
    canvas.save();
    canvas.scale(size, size);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  static void _paintJokerBadge(
    Canvas canvas,
    CardRenderRequest request,
    CardThemePalette palette,
  ) {
    // No-op for now; the joker face draws its own treatment.
  }

  static void _paintJokerRepresented(
    Canvas canvas,
    CardRenderRequest request,
    CardThemePalette palette,
    CardIdentity represented,
  ) {
    final size = request.size;
    final fade = request.jokerDisplay == JokerDisplay.memoryReveal ? 0.55 : 0.95;
    final color = palette.colorFor(represented.suit).withValues(alpha: fade);
    final tp = TextPainter(
      text: TextSpan(
        text: '${represented.rank.label}${SuitGlyphs.symbolFor(represented.suit)}',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: size.shortestSide * 0.18,
          letterSpacing: -0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        (size.width - tp.width) / 2,
        size.height * 0.78,
      ),
    );
  }

  static void _paintDeckCopyDot(
    Canvas canvas,
    CardRenderRequest request,
    CardThemePalette palette,
  ) {
    final size = request.size;
    final deckIndex = request.card.deckIndex;
    final colors = const [
      LoungeTokens.indigoAccent,
      LoungeTokens.fiftyFlame,
      LoungeTokens.goldAccent,
      LoungeTokens.sandLine,
    ];
    final color = colors[deckIndex % colors.length];
    final paint = Paint()..color = color.withValues(alpha: 0.7);
    canvas.drawCircle(
      Offset(size.width - 8, 8),
      2.4,
      paint,
    );
  }

  static List<Offset> _pipPositionsFor(CardRank rank) {
    // Centre-pip layouts roughly mirror a traditional playing card.
    switch (rank) {
      case CardRank.ace:
        return const [Offset(0.5, 0.5)];
      case CardRank.two:
        return const [Offset(0.5, 0.3), Offset(0.5, 0.7)];
      case CardRank.three:
        return const [Offset(0.5, 0.25), Offset(0.5, 0.5), Offset(0.5, 0.75)];
      case CardRank.four:
        return const [
          Offset(0.33, 0.3),
          Offset(0.67, 0.3),
          Offset(0.33, 0.7),
          Offset(0.67, 0.7),
        ];
      case CardRank.five:
        return const [
          Offset(0.33, 0.3),
          Offset(0.67, 0.3),
          Offset(0.5, 0.5),
          Offset(0.33, 0.7),
          Offset(0.67, 0.7),
        ];
      case CardRank.six:
        return const [
          Offset(0.33, 0.28),
          Offset(0.67, 0.28),
          Offset(0.33, 0.5),
          Offset(0.67, 0.5),
          Offset(0.33, 0.72),
          Offset(0.67, 0.72),
        ];
      case CardRank.seven:
        return const [
          Offset(0.33, 0.25),
          Offset(0.67, 0.25),
          Offset(0.5, 0.38),
          Offset(0.33, 0.5),
          Offset(0.67, 0.5),
          Offset(0.33, 0.75),
          Offset(0.67, 0.75),
        ];
      case CardRank.eight:
        return const [
          Offset(0.33, 0.24),
          Offset(0.67, 0.24),
          Offset(0.5, 0.36),
          Offset(0.33, 0.48),
          Offset(0.67, 0.48),
          Offset(0.5, 0.64),
          Offset(0.33, 0.76),
          Offset(0.67, 0.76),
        ];
      case CardRank.nine:
        return const [
          Offset(0.33, 0.22),
          Offset(0.67, 0.22),
          Offset(0.33, 0.4),
          Offset(0.67, 0.4),
          Offset(0.5, 0.5),
          Offset(0.33, 0.6),
          Offset(0.67, 0.6),
          Offset(0.33, 0.78),
          Offset(0.67, 0.78),
        ];
      case CardRank.ten:
        return const [
          Offset(0.33, 0.2),
          Offset(0.67, 0.2),
          Offset(0.33, 0.38),
          Offset(0.67, 0.38),
          Offset(0.5, 0.3),
          Offset(0.5, 0.7),
          Offset(0.33, 0.62),
          Offset(0.67, 0.62),
          Offset(0.33, 0.8),
          Offset(0.67, 0.8),
        ];
      case CardRank.jack:
      case CardRank.queen:
      case CardRank.king:
        return const [];
    }
  }
}
