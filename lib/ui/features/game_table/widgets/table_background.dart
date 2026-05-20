import 'package:flutter/material.dart';

import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../../../core/theme/table_surface_theme.dart';

/// Static visual base of the table.
class TableBackground extends StatelessWidget {
  /// Creates a table background.
  const TableBackground({
    super.key,
    this.surface = TableSurfaceTheme.felt,
    this.child,
  });

  /// Active table surface theme.
  final TableSurfaceTheme surface;

  /// Optional foreground content.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final background = switch (surface) {
      TableSurfaceTheme.felt => const _FeltSurface(),
      TableSurfaceTheme.wood => const _WoodSurface(),
    };

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: background),
        if (child != null) Positioned.fill(child: child!),
      ],
    );
  }
}

class _FeltSurface extends StatelessWidget {
  const _FeltSurface();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: LoungeTokens.feltGreen),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _FeltGradient(),
          Positioned.fill(child: _BorderPattern()),
          Positioned.fill(child: _CornerMotifs()),
        ],
      ),
    );
  }
}

class _FeltGradient extends StatelessWidget {
  const _FeltGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.1),
          radius: 0.95,
          colors: [
            LoungeTokens.feltSpotlight,
            LoungeTokens.feltGreen,
            LoungeTokens.coffeeCharcoal,
          ],
          stops: [0, 0.65, 1],
        ),
      ),
    );
  }
}

class _BorderPattern extends StatelessWidget {
  const _BorderPattern();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(LoungeTokens.space3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
          border: Border.all(
            color: LoungeTokens.sandLine.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: LoungeTokens.space2),
          child: Stack(
            children: [
              Positioned(
                top: 4,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: 8,
                  child: CustomPaint(
                    painter: GeometricMotifPainter(
                      variant: LoungeMotifVariant.border,
                      opacity: 0.18,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 4,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: 8,
                  child: CustomPaint(
                    painter: GeometricMotifPainter(
                      variant: LoungeMotifVariant.border,
                      opacity: 0.18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CornerMotifs extends StatelessWidget {
  const _CornerMotifs();

  @override
  Widget build(BuildContext context) {
    const cornerSize = 44.0;
    const cornerPainter = GeometricMotifPainter(
      variant: LoungeMotifVariant.corner,
      opacity: 0.22,
    );
    final motif = const SizedBox.square(
      dimension: cornerSize,
      child: CustomPaint(painter: cornerPainter),
    );

    return Padding(
      padding: const EdgeInsets.all(LoungeTokens.space5),
      child: Stack(
        children: [
          Align(alignment: Alignment.topLeft, child: motif),
          Align(
            alignment: Alignment.topRight,
            child: Transform(
              transform: Matrix4.diagonal3Values(-1, 1, 1),
              alignment: Alignment.center,
              child: motif,
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Transform(
              transform: Matrix4.diagonal3Values(1, -1, 1),
              alignment: Alignment.center,
              child: motif,
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Transform(
              transform: Matrix4.diagonal3Values(-1, -1, 1),
              alignment: Alignment.center,
              child: motif,
            ),
          ),
        ],
      ),
    );
  }
}

class _WoodSurface extends StatelessWidget {
  const _WoodSurface();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Color(0xFFE4D5C2)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: CustomPaint(painter: _WoodGrain())),
          Positioned.fill(child: _SoftVignette()),
          Positioned(
            top: -18,
            right: -14,
            child: SizedBox(
              width: 190,
              height: 142,
              child: CustomPaint(painter: _LeafCluster()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftVignette extends StatelessWidget {
  const _SoftVignette();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          radius: 1.25,
          center: const Alignment(0.05, -0.08),
          colors: [
            Colors.white.withValues(alpha: 0.14),
            Colors.transparent,
            LoungeTokens.coffeeCharcoal.withValues(alpha: 0.13),
          ],
          stops: const [0, 0.64, 1],
        ),
      ),
    );
  }
}

class _WoodGrain extends CustomPainter {
  const _WoodGrain();

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()..color = const Color(0xFFE4D5C2);
    canvas.drawRect(Offset.zero & size, base);

    final plankPaint = Paint()
      ..color = const Color(0xFFB99F80).withValues(alpha: 0.18)
      ..strokeWidth = 1;
    final plankWidth = size.width / 7.2;
    for (var x = plankWidth; x < size.width; x += plankWidth) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), plankPaint);
    }

    final grainPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.9
      ..color = const Color(0xFF9B8063).withValues(alpha: 0.18);
    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: 0.16);

    for (var i = 0; i < 34; i++) {
      final y = (i + 0.45) * size.height / 34;
      final wobble = (i.isEven ? 18.0 : -14.0);
      final path = Path()
        ..moveTo(-20, y)
        ..cubicTo(
          size.width * 0.25,
          y + wobble,
          size.width * 0.55,
          y - wobble * 0.55,
          size.width + 20,
          y + wobble * 0.32,
        );
      canvas.drawPath(path, i.isEven ? grainPaint : highlightPaint);
    }

    final knotPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = const Color(0xFF8D7055).withValues(alpha: 0.12);
    for (final knot in const [
      Offset(0.18, 0.24),
      Offset(0.52, 0.42),
      Offset(0.74, 0.68),
    ]) {
      final center = Offset(knot.dx * size.width, knot.dy * size.height);
      canvas.drawOval(
        Rect.fromCenter(center: center, width: 76, height: 22),
        knotPaint,
      );
      canvas.drawOval(
        Rect.fromCenter(center: center, width: 42, height: 11),
        knotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LeafCluster extends CustomPainter {
  const _LeafCluster();

  @override
  void paint(Canvas canvas, Size size) {
    final stemPaint = Paint()
      ..color = const Color(0xFF2F6E43).withValues(alpha: 0.34)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final leafPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF6CA85B), Color(0xFF2D6B3F)],
      ).createShader(Offset.zero & size);

    for (var i = 0; i < 7; i++) {
      final start = Offset(size.width * 0.88, size.height * (0.18 + i * 0.09));
      final end = Offset(size.width * (0.22 + i * 0.06), size.height * 0.84);
      canvas.drawLine(start, end, stemPaint);
      _drawLeaf(
        canvas,
        leafPaint,
        Offset(size.width * (0.28 + i * 0.08), size.height * (0.16 + i * 0.06)),
        24 + i * 1.2,
        -0.68 + i * 0.08,
      );
    }
  }

  void _drawLeaf(
    Canvas canvas,
    Paint paint,
    Offset center,
    double length,
    double rotation,
  ) {
    final width = length * 0.28;
    final path = Path()
      ..moveTo(0, -length / 2)
      ..cubicTo(width, -length * 0.22, width, length * 0.22, 0, length / 2)
      ..cubicTo(-width, length * 0.22, -width, -length * 0.22, 0, -length / 2)
      ..close();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.12), 3, false);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
