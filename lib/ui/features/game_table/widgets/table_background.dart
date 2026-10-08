import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../../../core/theme/table_surface_theme.dart';

/// Static visual base of the table.
///
/// Paints the table as an object seen from the player's chair (design
/// contract section 7.3): the surface is foreshortened in perspective, lit by
/// a lamp above the centre, and framed by a rail that is thin on the far side
/// and deep on the near side. With [insetChild], the foreground sits inside
/// the rail, on the playing surface, rather than running under it.
class TableBackground extends StatelessWidget {
  /// Creates a table background.
  const TableBackground({
    super.key,
    this.surface = TableSurfaceTheme.sandline,
    this.insetChild = false,
    this.child,
  });

  /// Active table surface theme.
  final TableSurfaceTheme surface;

  /// Whether [child] is laid out inside the rail. Surfaces whose geometry is
  /// frozen (the replay screen) keep the full-bleed layout and a thin rail.
  final bool insetChild;

  /// Optional foreground content.
  final Widget? child;

  /// Rail thickness per side for a table of [size]: far (top) rail thinnest,
  /// near (bottom) rail deepest, so the frame itself reads in perspective.
  static EdgeInsets railInsets(Size size) {
    if (size.width < 500 || size.height < 260) {
      return const EdgeInsets.fromLTRB(5, 4, 5, 8);
    }
    if (size.height <= 380) {
      return const EdgeInsets.fromLTRB(11, 7, 11, 15);
    }
    return const EdgeInsets.fromLTRB(15, 9, 15, 21);
  }

  @override
  Widget build(BuildContext context) {
    final background = switch (surface) {
      TableSurfaceTheme.sandline => const _SandlineSurface(),
      TableSurfaceTheme.felt => const _FeltSurface(),
      TableSurfaceTheme.wood => const _WoodSurface(),
      TableSurfaceTheme.sapphire => const _SapphireSurface(),
      TableSurfaceTheme.clay => const _ClaySurface(),
    };
    final rail = _railFor(surface);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final insets = insetChild
            ? railInsets(size)
            : EdgeInsets.all(size.height <= 360 ? 7 : 10);
        final radius = _feltRadius(size);
        return Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFF0E0A07))),
            // The surface, foreshortened: the far side recedes, so the
            // medallion and weave read as a plane seen from the chair.
            Positioned.fill(
              child: Padding(
                padding: insets,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: RepaintBoundary(
                    child: _PerspectiveSurface(child: background),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: TableRimPainter(
                      rail: rail,
                      insets: insets,
                      radius: radius,
                    ),
                  ),
                ),
              ),
            ),
            if (child != null)
              Positioned.fill(
                child: insetChild
                    ? Padding(padding: insets, child: child)
                    : child!,
              ),
          ],
        );
      },
    );
  }

  static double _feltRadius(Size size) {
    if (size.width < 500 || size.height < 260) return 10;
    return size.height <= 380 ? 18 : 26;
  }

  static TableRail _railFor(TableSurfaceTheme surface) => switch (surface) {
    TableSurfaceTheme.wood => TableRail.oak,
    TableSurfaceTheme.sapphire => TableRail.ebony,
    _ => TableRail.walnut,
  };
}

/// Tilts a surface back in perspective, overscaled so the receding far edge
/// still covers the whole playing area.
class _PerspectiveSurface extends StatelessWidget {
  const _PerspectiveSurface({required this.child});

  final Widget child;

  /// Backward tilt of the playing surface, in radians.
  static const tilt = 0.55;

  @override
  Widget build(BuildContext context) {
    // Negative X rotation tips the top edge away from the viewer. Pivoting on
    // the centre keeps the surface's centre (its medallion) on the table's
    // centre, where the discard and stock sit; the overscale covers the far
    // corners the tilt pulls in.
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0011)
        ..rotateX(-tilt)
        ..scaleByDouble(1.45, 1.45, 1, 1),
      child: Stack(fit: StackFit.expand, children: [child, const _LampLight()]),
    );
  }
}

/// A warm pool of lamp light on the centre of the table, falling off to the
/// edges. Painted on the surface so it shares the surface's perspective.
class _LampLight extends StatelessWidget {
  const _LampLight();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, 0.15),
            radius: 0.85,
            colors: [
              Color(0x24FFD9A0),
              Color(0x0AFFD9A0),
              Color(0x00000000),
              Color(0x47000000),
            ],
            stops: [0, 0.35, 0.68, 1],
          ),
        ),
      ),
    );
  }
}

/// Rail material painted around the table surface.
enum TableRail {
  /// Dark walnut leather rail with a brass inlay (lounge default).
  walnut(Color(0xFF1C120B), Color(0xFF4A2F1B), Color(0xFFC9A15A)),

  /// Deeper oak rail for the light wood tabletop.
  oak(Color(0xFF3B2614), Color(0xFF7A5634), Color(0xFFE3C48A)),

  /// Near-black rail with a cool silver inlay for the sapphire velvet.
  ebony(Color(0xFF0A0C12), Color(0xFF2A3042), Color(0xFFB9C2D6));

  const TableRail(this.outer, this.inner, this.inlay);

  /// Outer (shadowed) edge of the rail.
  final Color outer;

  /// Lit crest of the rail.
  final Color inner;

  /// Metal inlay hairline between rail and surface.
  final Color inlay;
}

/// Paints the rail around the surface: a rounded leather rail lit from the
/// lamp above, its inner wall visible on the far side, the shadow it casts
/// onto the surface, and a brass inlay at the seam.
class TableRimPainter extends CustomPainter {
  /// Creates a rim painter for [rail].
  const TableRimPainter({
    required this.rail,
    required this.insets,
    required this.radius,
  });

  /// Rail material.
  final TableRail rail;

  /// Rail thickness per side.
  final EdgeInsets insets;

  /// Corner radius of the playing surface.
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.shortestSide <= 0) return;
    final outer = Offset.zero & size;
    final surface = RRect.fromRectAndRadius(
      insets.deflateRect(outer),
      Radius.circular(radius),
    );

    // Rail body: everything outside the surface. Lit from above, so the near
    // rail's top face is brightest at its inner lip and falls into shadow at
    // the screen edge; the far rail is seen at a grazing angle and stays dark.
    final railPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(outer)
      ..addRRect(surface);
    canvas.drawPath(
      railPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            rail.outer,
            Color.lerp(rail.outer, rail.inner, 0.55)!,
            Color.lerp(rail.outer, rail.inner, 0.7)!,
            rail.inner,
            rail.outer,
          ],
          stops: [
            0,
            insets.top / size.height,
            0.5,
            1 - insets.bottom / size.height,
            1,
          ],
        ).createShader(outer),
    );

    // Rounded crest highlight running around the rail.
    final crest = RRect.fromLTRBR(
      surface.left - insets.left * 0.45,
      surface.top - insets.top * 0.45,
      surface.right + insets.right * 0.45,
      surface.bottom + insets.bottom * 0.45,
      Radius.circular(radius + insets.left * 0.45),
    );
    canvas.drawRRect(
      crest,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, insets.top * 0.45)
        ..color = Colors.white.withValues(alpha: 0.06)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );

    // Darkened outer edge where the rail turns down out of view.
    canvas.drawRect(
      outer.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.black.withValues(alpha: 0.45),
    );

    canvas.save();
    canvas.clipRRect(surface);
    // Inner wall of the far rail, visible from the chair.
    final wall = math.max(2.0, insets.top * 0.45);
    canvas.drawRect(
      Rect.fromLTWH(surface.left, surface.top, surface.width, wall),
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [rail.inner.withValues(alpha: 0.9), rail.outer],
            ).createShader(
              Rect.fromLTWH(surface.left, surface.top, surface.width, wall),
            ),
    );
    // Shadow the rail casts onto the surface: deepest under the far rail.
    final shadowDepth = math.max(6.0, insets.left * 1.1);
    for (var i = 0; i < 3; i++) {
      final spread = shadowDepth * (i + 1) * 0.6;
      canvas.drawRRect(
        surface.inflate(spread * 0.25),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = spread
          ..color = Colors.black.withValues(alpha: 0.12)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, spread * 0.5),
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(
        surface.left,
        surface.top,
        surface.width,
        shadowDepth * 2.5,
      ),
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.32),
                Colors.black.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromLTWH(
                surface.left,
                surface.top,
                surface.width,
                shadowDepth * 2.5,
              ),
            ),
    );
    canvas.restore();

    // Brass inlay at the seam.
    canvas.drawRRect(
      surface,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = rail.inlay.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(covariant TableRimPainter oldDelegate) =>
      oldDelegate.rail != rail ||
      oldDelegate.insets != insets ||
      oldDelegate.radius != radius;
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
