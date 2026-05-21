import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/lounge_tokens.dart';

/// Variant of the shared lounge motif.
///
/// The same nested-arch geometric shape is reused everywhere a cultural mark
/// is wanted: faint corner ornaments on menus, a centre medallion on the
/// default card back, and a thin pattern border at the table frame edge. One
/// motif keeps the visual identity tight — see `docs/design/direction.md`.
enum LoungeMotifVariant {
  /// Single ornament tucked into a corner of a panel or menu surface.
  corner,

  /// Centre medallion used on the default card back and splash mark.
  medallion,

  /// Thin border pattern used along the long edge of a panel or table frame.
  border,
}

/// Shared geometric motif drawn via [CustomPainter].
///
/// Stroke-only and self-similar so it scales from a 12 dp corner glyph to a
/// 200 dp splash medallion without losing readability. Always draws with the
/// sand-line stroke colour at a low opacity; callers can override [opacity]
/// to fade further behind menu content.
class GeometricMotifPainter extends CustomPainter {
  /// Creates a motif painter.
  const GeometricMotifPainter({
    this.variant = LoungeMotifVariant.medallion,
    this.color = LoungeTokens.sandLine,
    this.opacity = 0.45,
    this.strokeWidth = 1.2,
    this.density = 3,
  });

  /// Layout variant.
  final LoungeMotifVariant variant;

  /// Stroke colour.
  final Color color;

  /// Stroke opacity (0..1). The base sand-line is already restrained; default
  /// 0.45 puts the motif as a quiet accent, not the focal element.
  final double opacity;

  /// Stroke width in logical pixels.
  final double strokeWidth;

  /// How many nested rings the medallion should contain (clamped to 2..6).
  final int density;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.shortestSide <= 0) {
      return;
    }
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    switch (variant) {
      case LoungeMotifVariant.corner:
        _paintCorner(canvas, size, paint);
      case LoungeMotifVariant.medallion:
        _paintMedallion(canvas, size, paint);
      case LoungeMotifVariant.border:
        _paintBorder(canvas, size, paint);
    }
  }

  void _paintCorner(Canvas canvas, Size size, Paint paint) {
    final s = size.shortestSide;
    final origin = Offset.zero;
    final path = Path()
      ..moveTo(origin.dx, origin.dy + s * 0.7)
      ..lineTo(origin.dx, origin.dy)
      ..lineTo(origin.dx + s * 0.7, origin.dy);

    final arch = Path();
    arch.moveTo(origin.dx + s * 0.18, origin.dy + s * 0.6);
    arch.quadraticBezierTo(
      origin.dx + s * 0.18,
      origin.dy + s * 0.18,
      origin.dx + s * 0.6,
      origin.dy + s * 0.18,
    );

    final inner = Path();
    inner.moveTo(origin.dx + s * 0.32, origin.dy + s * 0.55);
    inner.quadraticBezierTo(
      origin.dx + s * 0.32,
      origin.dy + s * 0.32,
      origin.dx + s * 0.55,
      origin.dy + s * 0.32,
    );

    canvas.drawPath(path, paint);
    canvas.drawPath(arch, paint);
    canvas.drawPath(inner, paint);

    final dot = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(origin.dx + s * 0.4, origin.dy + s * 0.4), 1.4, dot);
  }

  void _paintMedallion(Canvas canvas, Size size, Paint paint) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final rings = density.clamp(2, 6);

    canvas.drawCircle(center, radius * 0.95, paint);

    for (var i = 0; i < rings; i++) {
      final t = (i + 1) / (rings + 1);
      final petalRadius = radius * (0.45 + 0.5 * t);
      _drawPetals(canvas, center, petalRadius, 8, paint);
    }

    final core = Paint()
      ..color = color.withValues(alpha: (opacity + 0.15).clamp(0.0, 1.0))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.08, core);
  }

  void _drawPetals(
    Canvas canvas,
    Offset center,
    double radius,
    int count,
    Paint paint,
  ) {
    final path = Path();
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * math.pi * 2;
      final tipX = center.dx + math.cos(angle) * radius;
      final tipY = center.dy + math.sin(angle) * radius;
      final baseAngleA = angle - math.pi / count;
      final baseAngleB = angle + math.pi / count;
      final baseRadius = radius * 0.55;
      final baseAx = center.dx + math.cos(baseAngleA) * baseRadius;
      final baseAy = center.dy + math.sin(baseAngleA) * baseRadius;
      final baseBx = center.dx + math.cos(baseAngleB) * baseRadius;
      final baseBy = center.dy + math.sin(baseAngleB) * baseRadius;
      path.moveTo(baseAx, baseAy);
      path.quadraticBezierTo(tipX, tipY, baseBx, baseBy);
    }
    canvas.drawPath(path, paint);
  }

  void _paintBorder(Canvas canvas, Size size, Paint paint) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final amplitude = size.height / 2.4;
    final centerY = size.height / 2;
    const minSpacing = 18.0;
    final repeats = math.max(2, (size.width / minSpacing).floor());
    final step = size.width / repeats;

    final path = Path()..moveTo(0, centerY);
    for (var i = 0; i < repeats; i++) {
      final startX = i * step;
      final midX = startX + step / 2;
      final endX = startX + step;
      final controlY = (i.isEven ? centerY - amplitude : centerY + amplitude);
      path.quadraticBezierTo(midX, controlY, endX, centerY);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant GeometricMotifPainter oldDelegate) {
    return oldDelegate.variant != variant ||
        oldDelegate.color != color ||
        oldDelegate.opacity != opacity ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.density != density;
  }
}

/// Convenience widget that paints a [GeometricMotifPainter] sized to the
/// box. Useful for placing the motif inside an [Align] or [Stack] without
/// writing a [CustomPaint] every time.
class LoungeMotif extends StatelessWidget {
  /// Creates a sized motif.
  const LoungeMotif({
    super.key,
    this.variant = LoungeMotifVariant.medallion,
    this.color = LoungeTokens.sandLine,
    this.opacity = 0.45,
    this.strokeWidth = 1.2,
    this.density = 3,
    this.size,
  });

  /// Motif variant.
  final LoungeMotifVariant variant;

  /// Stroke colour.
  final Color color;

  /// Stroke opacity.
  final double opacity;

  /// Stroke width.
  final double strokeWidth;

  /// Density (only used by [LoungeMotifVariant.medallion]).
  final int density;

  /// Optional explicit size. If null, the motif expands to its parent.
  final Size? size;

  @override
  Widget build(BuildContext context) {
    final painter = GeometricMotifPainter(
      variant: variant,
      color: color,
      opacity: opacity,
      strokeWidth: strokeWidth,
      density: density,
    );
    final paint = CustomPaint(painter: painter);
    if (size == null) {
      return SizedBox.expand(child: paint);
    }
    return SizedBox(width: size!.width, height: size!.height, child: paint);
  }
}
