import 'dart:math' as math;

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
    final represented = request.card.representedIdentity;
    final showRepresented =
        represented != null && request.jokerDisplay != JokerDisplay.unassigned;

    _paintJokerCorners(canvas, request, palette);

    // Lift the joker mark slightly when a represented identity is shown so
    // both elements share the visual centre instead of stacking lop-sided.
    final centerY = showRepresented ? size.height * 0.46 : size.height * 0.5;
    final center = Offset(size.width / 2, centerY);
    final radius = size.shortestSide * 0.3;

    final fill = Paint()..color = palette.jokerAccent.withValues(alpha: 0.16);
    canvas.drawCircle(center, radius, fill);

    final stroke = Paint()
      ..color = palette.jokerAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, size.shortestSide * 0.035);
    canvas.drawCircle(center, radius, stroke);

    final tp = TextPainter(
      text: TextSpan(
        text: 'J',
        style: TextStyle(
          color: palette.jokerAccent,
          fontWeight: FontWeight.w900,
          fontSize: size.shortestSide * 0.42,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Optical lift: the "J" sits slightly low inside its text box, so nudge
    // it up so the painted glyph aligns with the circle's centre.
    tp.paint(
      canvas,
      Offset(
        center.dx - tp.width / 2,
        center.dy - tp.height / 2 - size.shortestSide * 0.02,
      ),
    );

    if (showRepresented) {
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
    final shortSide = size.shortestSide;
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

    // Twin hairline frame: outer ornament line + a fainter inner echo. Reads
    // as a deliberate sand-line bezel at every supported size rather than a
    // single floating stroke.
    final borderInset = (shortSide * 0.06).clamp(2.0, 5.0);
    final outerFrame = Paint()
      ..color = palette.backOrnament.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(rrect.deflate(borderInset), outerFrame);

    final innerFrame = Paint()
      ..color = palette.backOrnament.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawRRect(rrect.deflate(borderInset + 2.0), innerFrame);

    // Centre the medallion on both axes so it reads centred on portrait
    // cards (the previous square inset based on shortestSide left noticeable
    // dead space at the top and bottom of tall cards).
    final medallionDiameter = shortSide - borderInset * 2 - shortSide * 0.18;
    final medallionSize = Size(medallionDiameter, medallionDiameter);
    canvas.save();
    canvas.translate(
      (size.width - medallionDiameter) / 2,
      (size.height - medallionDiameter) / 2,
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
    final shortSide = size.shortestSide;
    final fontSize = (shortSide * 0.26).clamp(10.0, 18.0);
    final glyphSize = (shortSide * 0.22).clamp(7.0, 14.0);
    final padX = shortSide * 0.09;
    final padY = shortSide * 0.07;
    final rankToGlyphGap = shortSide * 0.04;

    final span = TextSpan(
      text: identity.rank.label,
      style: TextStyle(
        color: palette.faceText,
        fontWeight: FontWeight.w800,
        fontSize: fontSize,
        height: 1.0,
        letterSpacing: -0.3,
      ),
    );

    void paintIndex() {
      final painter = TextPainter(text: span, textDirection: TextDirection.ltr)
        ..layout();

      // Rank sits in the upper-left of the index well.
      final rankOffset = Offset(padX, padY);
      painter.paint(canvas, rankOffset);

      // Suit glyph optically centred under the rank's own centre, so wide
      // labels ("10") and narrow ones ("A") read as one unit.
      final rankCenterX = rankOffset.dx + painter.width / 2;
      final glyphLeft = rankCenterX - glyphSize / 2;
      final glyphTop = rankOffset.dy + painter.height + rankToGlyphGap;

      canvas.save();
      canvas.translate(glyphLeft, glyphTop);
      _paintSuitGlyph(canvas, identity.suit, suitColor, glyphSize);
      canvas.restore();
    }

    paintIndex();

    // Bottom-right index rotated 180° so the rank still reads upright when
    // the card is held by the opposite player.
    canvas.save();
    canvas.translate(size.width, size.height);
    canvas.rotate(math.pi);
    paintIndex();
    canvas.restore();
  }

  static void _paintCenterGlyph(
    Canvas canvas,
    CardRenderRequest request,
    CardIdentity identity,
    Color color,
  ) {
    final size = request.size;
    final shortSide = size.shortestSide;
    final rankSize = shortSide * 0.52;
    final glyphSize = shortSide * 0.22;
    final gap = shortSide * 0.06;

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

    // Treat the rank label + suit pip as one group and centre the group
    // inside the card. Avoids the rank floating above with the pip far
    // below at a magic 0.65 anchor.
    final groupHeight = tp.height + gap + glyphSize;
    final groupTop = (size.height - groupHeight) / 2;

    tp.paint(canvas, Offset((size.width - tp.width) / 2, groupTop));

    canvas.save();
    canvas.translate((size.width - glyphSize) / 2, groupTop + tp.height + gap);
    _paintSuitGlyph(canvas, identity.suit, color, glyphSize);
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
        canvas.rotate(math.pi);
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

  /// Draws the joker's corner indices: a jester-cap silhouette in both the
  /// top-left and (rotated 180°) bottom-right corners. Sits in the same
  /// corner well as a standard card's rank/pip stack but as a single glyph,
  /// so the joker never reads as a Jack.
  static void _paintJokerCorners(
    Canvas canvas,
    CardRenderRequest request,
    CardThemePalette palette,
  ) {
    final size = request.size;
    final shortSide = size.shortestSide;
    // Cap occupies roughly the visual mass of a rank letter + suit pip on a
    // standard card, with clamps so picker-scale cards still get a legible
    // silhouette and full-scale cards don't crowd the centre treatment.
    final capSize = (shortSide * 0.34).clamp(13.0, 26.0);
    final padX = shortSide * 0.08;
    final padY = shortSide * 0.07;

    void paintCorner() {
      canvas.save();
      canvas.translate(padX, padY);
      _paintJokerCap(canvas, capSize, palette.jokerAccent);
      canvas.restore();
    }

    paintCorner();

    // Bottom-right index rotated 180° so the cap still points "up" when
    // the card is held by the opposite seat.
    canvas.save();
    canvas.translate(size.width, size.height);
    canvas.rotate(math.pi);
    paintCorner();
    canvas.restore();
  }

  /// Paints a jester cap inside a 1× [size] square. Three upward spikes —
  /// outer two leaning outward, centre pointing up — anchored by a short
  /// band along the bottom. Small bells perch at each spike tip so the
  /// silhouette reads as "jester hat" at full size; at picker scale the
  /// bells fuse into the tips and the cap shape carries the meaning.
  static void _paintJokerCap(Canvas canvas, double size, Color color) {
    final s = size;
    final fill = Paint()..color = color;

    final cap = Path()
      ..moveTo(s * 0.12, s * 0.86)
      ..lineTo(s * 0.06, s * 0.66) // left band shoulder
      ..lineTo(s * 0.10, s * 0.30) // left spike tip (leans outward)
      ..lineTo(s * 0.36, s * 0.66) // left valley at band top
      ..lineTo(s * 0.50, s * 0.20) // centre spike tip
      ..lineTo(s * 0.64, s * 0.66) // right valley at band top
      ..lineTo(s * 0.90, s * 0.30) // right spike tip
      ..lineTo(s * 0.94, s * 0.66) // right band shoulder
      ..lineTo(s * 0.88, s * 0.86)
      ..close();
    canvas.drawPath(cap, fill);

    final bellRadius = s * 0.085;
    canvas.drawCircle(Offset(s * 0.10, s * 0.22), bellRadius, fill);
    canvas.drawCircle(Offset(s * 0.50, s * 0.12), bellRadius, fill);
    canvas.drawCircle(Offset(s * 0.90, s * 0.22), bellRadius, fill);
  }

  static void _paintJokerRepresented(
    Canvas canvas,
    CardRenderRequest request,
    CardThemePalette palette,
    CardIdentity represented,
  ) {
    final size = request.size;
    final shortSide = size.shortestSide;
    final fade = request.jokerDisplay == JokerDisplay.memoryReveal
        ? 0.90
        : 0.95;
    final opacity = (fade * request.revealOpacity).clamp(0.0, 1.0);
    if (opacity <= 0.0) {
      return;
    }
    final color = palette.colorFor(represented.suit).withValues(alpha: opacity);
    final labelSize = shortSide * 0.2;
    final glyphSize = shortSide * 0.18;
    final gap = shortSide * 0.04;

    final tp = TextPainter(
      text: TextSpan(
        text: represented.rank.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: labelSize,
          height: 1.0,
          letterSpacing: -0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Render the represented identity as rank + path-rendered pip so the
    // pip weight matches every other suit glyph on the card (the Unicode
    // suit characters used previously came from the body font and drifted
    // in width/colour against the painted shapes).
    final groupWidth = tp.width + gap + glyphSize;
    final groupLeft = (size.width - groupWidth) / 2;
    final centerY = size.height * 0.82;

    tp.paint(canvas, Offset(groupLeft, centerY - tp.height / 2));

    canvas.save();
    canvas.translate(groupLeft + tp.width + gap, centerY - glyphSize / 2);
    _paintSuitGlyph(canvas, represented.suit, color, glyphSize);
    canvas.restore();
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
    final shortSide = size.shortestSide;
    final inset = shortSide * 0.07;
    final dotRadius = shortSide * 0.022;
    canvas.drawCircle(
      Offset(size.width - inset, inset),
      dotRadius,
      paint,
    );
  }

  static List<Offset> _pipPositionsFor(CardRank rank) {
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
