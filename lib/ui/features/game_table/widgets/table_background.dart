import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../../../core/theme/table_surface_theme.dart';

/// Static visual base of the table.
class TableBackground extends StatelessWidget {
  /// Creates a table background.
  const TableBackground({
    super.key,
    this.surface = TableSurfaceTheme.sandline,
    this.child,
  });

  /// Active table surface theme.
  final TableSurfaceTheme surface;

  /// Optional foreground content.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final background = switch (surface) {
      TableSurfaceTheme.sandline => const _SandlineSurface(),
      TableSurfaceTheme.felt => const _FeltSurface(),
      TableSurfaceTheme.wood => const _WoodSurface(),
      TableSurfaceTheme.sapphire => const _SapphireSurface(),
      TableSurfaceTheme.clay => const _ClaySurface(),
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

class _SandlineSurface extends StatelessWidget {
  const _SandlineSurface();

  static const _assetPath = 'assets/table_surfaces/sandline_lounge.webp';

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: LoungeTokens.feltGreen),
        Image.asset(
          _assetPath,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          excludeFromSemantics: true,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared frame: inner hairline, optional pinstripe, top/bottom motif strip,
// and four geometric corner ornaments. Each surface composes the same frame
// in its own accent tone so the brand mark stays consistent across themes.
// ---------------------------------------------------------------------------

class _TableFrame extends StatelessWidget {
  const _TableFrame({
    required this.hairline,
    required this.motifColor,
    this.hairlineOpacity = 0.32,
    this.motifBorderOpacity = 0.16,
    this.cornerOpacity = 0.22,
    this.innerPinstripe,
    this.innerPinstripeOpacity = 0.18,
  });

  final Color hairline;
  final Color motifColor;
  final double hairlineOpacity;
  final double motifBorderOpacity;
  final double cornerOpacity;
  final Color? innerPinstripe;
  final double innerPinstripeOpacity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: const EdgeInsets.all(LoungeTokens.space3),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
              border: Border.all(
                color: hairline.withValues(alpha: hairlineOpacity),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LoungeTokens.space2,
              ),
              child: Stack(
                children: [
                  if (innerPinstripe != null)
                    Padding(
                      padding: const EdgeInsets.all(5),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            LoungeTokens.radiusPanel - 5,
                          ),
                          border: Border.all(
                            color: innerPinstripe!.withValues(
                              alpha: innerPinstripeOpacity,
                            ),
                            width: 0.6,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 4,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      height: 8,
                      child: CustomPaint(
                        painter: GeometricMotifPainter(
                          variant: LoungeMotifVariant.border,
                          color: motifColor,
                          opacity: motifBorderOpacity,
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
                          color: motifColor,
                          opacity: motifBorderOpacity,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _CornerMotifs(color: motifColor, opacity: cornerOpacity),
      ],
    );
  }
}

class _CornerMotifs extends StatelessWidget {
  const _CornerMotifs({required this.color, required this.opacity});

  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    const cornerSize = 46.0;
    final cornerPainter = GeometricMotifPainter(
      variant: LoungeMotifVariant.corner,
      color: color,
      opacity: opacity,
    );
    final motif = SizedBox.square(
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

// ---------------------------------------------------------------------------
// 1. Dark felt — the lounge primary.
// ---------------------------------------------------------------------------

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
          Positioned.fill(child: CustomPaint(painter: _FeltFibers())),
          _FeltCenterHalo(),
          _TableFrame(
            hairline: LoungeTokens.sandLine,
            motifColor: LoungeTokens.sandLine,
            hairlineOpacity: 0.38,
            motifBorderOpacity: 0.18,
            cornerOpacity: 0.24,
            innerPinstripe: LoungeTokens.goldAccent,
            innerPinstripeOpacity: 0.22,
          ),
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
          center: Alignment(0, -0.12),
          radius: 1.0,
          colors: [
            Color(0xFF22564A),
            LoungeTokens.feltSpotlight,
            LoungeTokens.feltGreen,
            Color(0xFF0B221C),
            LoungeTokens.coffeeCharcoal,
          ],
          stops: [0, 0.22, 0.62, 0.9, 1],
        ),
      ),
    );
  }
}

class _FeltCenterHalo extends StatelessWidget {
  const _FeltCenterHalo();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.05),
          radius: 0.46,
          colors: [
            LoungeTokens.sandLine.withValues(alpha: 0.05),
            LoungeTokens.sandLine.withValues(alpha: 0.015),
            Colors.transparent,
          ],
          stops: const [0, 0.5, 1],
        ),
      ),
    );
  }
}

/// Tiny short strokes pseudo-randomly seeded so the felt looks woven rather
/// than flat. Half are highlights, half are recesses — at very low alpha so
/// the texture reads as material grain, not noise.
class _FeltFibers extends CustomPainter {
  const _FeltFibers();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.shortestSide <= 0) {
      return;
    }
    final rng = math.Random(7426);
    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.025)
      ..strokeWidth = 0.6
      ..strokeCap = StrokeCap.round;
    final recess = Paint()
      ..color = Colors.black.withValues(alpha: 0.05)
      ..strokeWidth = 0.6
      ..strokeCap = StrokeCap.round;

    final count = (size.width * size.height / 2400).round().clamp(180, 1400);
    for (var i = 0; i < count; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final angle = rng.nextDouble() * math.pi * 2;
      final len = 2.0 + rng.nextDouble() * 3.0;
      final dx = math.cos(angle) * len;
      final dy = math.sin(angle) * len;
      canvas.drawLine(
        Offset(x, y),
        Offset(x + dx, y + dy),
        i.isEven ? highlight : recess,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 2. Light wood — physical tabletop with overhead light + herbal accent.
// ---------------------------------------------------------------------------

class _WoodSurface extends StatelessWidget {
  const _WoodSurface();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Color(0xFFE6D1B0)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: CustomPaint(painter: _WoodGrain())),
          _WoodOverheadLight(),
          _WoodEdgeBevel(),
          Positioned(
            top: -16,
            right: -10,
            child: SizedBox(
              width: 180,
              height: 132,
              child: CustomPaint(painter: _HerbSprig()),
            ),
          ),
          _TableFrame(
            hairline: Color(0xFF6B4825),
            motifColor: Color(0xFF8C5C2E),
            hairlineOpacity: 0.32,
            motifBorderOpacity: 0.20,
            cornerOpacity: 0.28,
          ),
        ],
      ),
    );
  }
}

class _WoodOverheadLight extends StatelessWidget {
  const _WoodOverheadLight();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.45),
          radius: 1.05,
          colors: [
            const Color(0xFFFFF4DA).withValues(alpha: 0.22),
            const Color(0xFFFFF4DA).withValues(alpha: 0.06),
            Colors.transparent,
          ],
          stops: const [0, 0.35, 1],
        ),
      ),
    );
  }
}

class _WoodEdgeBevel extends StatelessWidget {
  const _WoodEdgeBevel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          radius: 1.15,
          center: const Alignment(0, 0),
          colors: [
            Colors.transparent,
            Colors.transparent,
            const Color(0xFF4A2E14).withValues(alpha: 0.10),
            const Color(0xFF2E1A0B).withValues(alpha: 0.28),
          ],
          stops: const [0, 0.55, 0.85, 1],
        ),
      ),
    );
  }
}

class _WoodGrain extends CustomPainter {
  const _WoodGrain();

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()..color = const Color(0xFFE6D1B0);
    canvas.drawRect(Offset.zero & size, base);

    // Soft warm bands giving the wood a slightly varied tone across planks.
    final bandLight = Paint()
      ..color = const Color(0xFFEFD9B6).withValues(alpha: 0.55)
      ..strokeWidth = 0
      ..style = PaintingStyle.fill;
    final bandDark = Paint()
      ..color = const Color(0xFFC9AA84).withValues(alpha: 0.28)
      ..strokeWidth = 0
      ..style = PaintingStyle.fill;

    final plankPaint = Paint()
      ..color = const Color(0xFF8E6A45).withValues(alpha: 0.14)
      ..strokeWidth = 1;
    final plankShadow = Paint()
      ..color = const Color(0xFF4A2E14).withValues(alpha: 0.10)
      ..strokeWidth = 1.4;
    final plankCount = 7.0;
    final plankWidth = size.width / plankCount;
    for (var i = 0; i < plankCount; i++) {
      final x = i * plankWidth;
      final paint = i.isEven ? bandLight : bandDark;
      canvas.drawRect(Rect.fromLTWH(x, 0, plankWidth, size.height), paint);
      if (i > 0) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), plankShadow);
        canvas.drawLine(
          Offset(x + 0.6, 0),
          Offset(x + 0.6, size.height),
          plankPaint,
        );
      }
    }

    // Curved long-grain lines. Strokes alternate between recess and
    // highlight to give the wood depth without looking striped.
    final grainPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.7
      ..color = const Color(0xFF8E6A45).withValues(alpha: 0.16);
    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.65
      ..color = Colors.white.withValues(alpha: 0.14);

    final rng = math.Random(2418);
    for (var i = 0; i < 38; i++) {
      final y = (i + 0.4) * size.height / 38;
      final wobble = (i.isEven ? 14.0 : -12.0) + rng.nextDouble() * 6;
      final wobble2 = -wobble * 0.5 + rng.nextDouble() * 4;
      final path = Path()
        ..moveTo(-20, y)
        ..cubicTo(
          size.width * 0.25,
          y + wobble,
          size.width * 0.6,
          y + wobble2,
          size.width + 20,
          y + wobble * 0.28,
        );
      canvas.drawPath(path, i.isEven ? grainPaint : highlightPaint);
    }

    // Three asymmetric knots, with a quiet inner ring for realism.
    final knotPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xFF6B4825).withValues(alpha: 0.16);
    final knotShadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFF6B4825).withValues(alpha: 0.10);
    for (final knot in const [
      Offset(0.16, 0.22),
      Offset(0.54, 0.46),
      Offset(0.78, 0.72),
    ]) {
      final center = Offset(knot.dx * size.width, knot.dy * size.height);
      canvas.drawOval(
        Rect.fromCenter(center: center, width: 78, height: 22),
        knotPaint,
      );
      canvas.drawOval(
        Rect.fromCenter(center: center, width: 50, height: 14),
        knotShadow,
      );
      canvas.drawOval(
        Rect.fromCenter(center: center, width: 24, height: 7),
        knotShadow,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Refined mint-sprig cluster — tighter geometry, softer green range, and a
/// dropped shadow that grounds it into the wood instead of floating.
class _HerbSprig extends CustomPainter {
  const _HerbSprig();

  @override
  void paint(Canvas canvas, Size size) {
    final stemPaint = Paint()
      ..color = const Color(0xFF294F2D).withValues(alpha: 0.42)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final leafPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF7DB068), Color(0xFF2F6B3F)],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ).createShader(Offset.zero & size);
    final leafEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = const Color(0xFF1F4A2A).withValues(alpha: 0.35);

    for (var i = 0; i < 6; i++) {
      final start = Offset(size.width * 0.92, size.height * (0.16 + i * 0.10));
      final end = Offset(size.width * (0.28 + i * 0.07), size.height * 0.88);
      canvas.drawLine(start, end, stemPaint);
      _drawLeaf(
        canvas,
        leafPaint,
        leafEdge,
        Offset(
          size.width * (0.32 + i * 0.085),
          size.height * (0.18 + i * 0.06),
        ),
        22 + i * 1.1,
        -0.62 + i * 0.07,
      );
    }
  }

  void _drawLeaf(
    Canvas canvas,
    Paint fill,
    Paint edge,
    Offset center,
    double length,
    double rotation,
  ) {
    final width = length * 0.30;
    final path = Path()
      ..moveTo(0, -length / 2)
      ..cubicTo(width, -length * 0.20, width, length * 0.22, 0, length / 2)
      ..cubicTo(-width, length * 0.22, -width, -length * 0.20, 0, -length / 2)
      ..close();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.16), 3, false);
    canvas.drawPath(path, fill);
    canvas.drawPath(path, edge);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 3. Midnight sapphire — cool dark velvet alternative to felt.
// ---------------------------------------------------------------------------

class _SapphireSurface extends StatelessWidget {
  const _SapphireSurface();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Color(0xFF0F1E33)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _SapphireGradient(),
          Positioned.fill(child: CustomPaint(painter: _VelvetWeave())),
          _SapphireCenterHalo(),
          _TableFrame(
            hairline: Color(0xFFB9C5D5),
            motifColor: Color(0xFFB9C5D5),
            hairlineOpacity: 0.30,
            motifBorderOpacity: 0.16,
            cornerOpacity: 0.22,
            innerPinstripe: Color(0xFF7CA0CC),
            innerPinstripeOpacity: 0.22,
          ),
        ],
      ),
    );
  }
}

class _SapphireGradient extends StatelessWidget {
  const _SapphireGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.12),
          radius: 1.0,
          colors: [
            Color(0xFF2A4374),
            Color(0xFF1F3458),
            Color(0xFF132440),
            Color(0xFF07101D),
          ],
          stops: [0, 0.28, 0.72, 1],
        ),
      ),
    );
  }
}

class _SapphireCenterHalo extends StatelessWidget {
  const _SapphireCenterHalo();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.05),
          radius: 0.44,
          colors: [
            const Color(0xFFC8D6EA).withValues(alpha: 0.055),
            const Color(0xFFC8D6EA).withValues(alpha: 0.018),
            Colors.transparent,
          ],
          stops: const [0, 0.55, 1],
        ),
      ),
    );
  }
}

/// Fine diagonal cross-weave that reads as deep velvet. Two interleaved
/// directions at very low alpha keep the surface from looking digital.
class _VelvetWeave extends CustomPainter {
  const _VelvetWeave();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.shortestSide <= 0) {
      return;
    }
    final paintA = Paint()
      ..color = const Color(0xFF6F8DB6).withValues(alpha: 0.07)
      ..strokeWidth = 0.6;
    final paintB = Paint()
      ..color = Colors.black.withValues(alpha: 0.10)
      ..strokeWidth = 0.6;

    const spacing = 7.0;
    final diag = size.width + size.height;
    for (var d = -size.height; d < diag; d += spacing) {
      canvas.drawLine(
        Offset(d, 0),
        Offset(d + size.height, size.height),
        paintA,
      );
    }
    for (var d = -size.height; d < diag; d += spacing) {
      canvas.drawLine(
        Offset(d, size.height),
        Offset(d + size.height, 0),
        paintB,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 4. Crimson clay — warm Sudanese earthenware surface.
// ---------------------------------------------------------------------------

class _ClaySurface extends StatelessWidget {
  const _ClaySurface();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Color(0xFF8E4A30)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _ClayGradient(),
          Positioned.fill(child: CustomPaint(painter: _ClaySpeckle())),
          _ClayCenterStamp(),
          _TableFrame(
            hairline: Color(0xFFD9B07A),
            motifColor: Color(0xFFE8C68A),
            hairlineOpacity: 0.36,
            motifBorderOpacity: 0.22,
            cornerOpacity: 0.28,
            innerPinstripe: Color(0xFF8E5430),
            innerPinstripeOpacity: 0.30,
          ),
        ],
      ),
    );
  }
}

class _ClayGradient extends StatelessWidget {
  const _ClayGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.12),
          radius: 1.0,
          colors: [
            Color(0xFFA85E40),
            Color(0xFF8E4A30),
            Color(0xFF5F2E1C),
            Color(0xFF2E1308),
          ],
          stops: [0, 0.32, 0.82, 1],
        ),
      ),
    );
  }
}

class _ClayCenterStamp extends StatelessWidget {
  const _ClayCenterStamp();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.square(
        dimension: 320,
        child: CustomPaint(
          painter: GeometricMotifPainter(
            variant: LoungeMotifVariant.medallion,
            color: const Color(0xFFE8C68A),
            opacity: 0.045,
            strokeWidth: 1.2,
            density: 4,
          ),
        ),
      ),
    );
  }
}

/// Pseudo-random speckle pattern evoking fired clay — uneven highlight dots
/// over a darker base, kept very low alpha so the speckle is felt, not seen.
class _ClaySpeckle extends CustomPainter {
  const _ClaySpeckle();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.shortestSide <= 0) {
      return;
    }
    final rng = math.Random(5031);
    final highlight = Paint()
      ..color = const Color(0xFFE8C68A).withValues(alpha: 0.045)
      ..style = PaintingStyle.fill;
    final recess = Paint()
      ..color = const Color(0xFF2A0F06).withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;

    final count = (size.width * size.height / 1900).round().clamp(220, 1600);
    for (var i = 0; i < count; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = 0.4 + rng.nextDouble() * 1.2;
      canvas.drawCircle(Offset(x, y), r, i.isEven ? highlight : recess);
    }

    // A few larger pottery flecks for tactile variation.
    final fleck = Paint()
      ..color = const Color(0xFF3A1408).withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    for (var i = 0; i < 24; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final w = 1.4 + rng.nextDouble() * 1.8;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: w, height: w * 0.55),
        fleck,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
