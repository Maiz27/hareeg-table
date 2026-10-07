import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/lounge_tokens.dart';
import 'motion_speed.dart';

/// Fireworks and confetti over a won match (design contract 6, celebrate).
///
/// Plays once, about three seconds, then paints nothing; never loops, so a
/// test can settle and the screen goes quiet for the player to read the
/// standings. Skipped entirely under reduced motion. Pointer-transparent.
class CelebrationFireworks extends StatefulWidget {
  /// Creates the celebration.
  const CelebrationFireworks({super.key, this.seed = 50});

  /// Seed for the burst layout, so a given celebration is reproducible.
  final int seed;

  /// Total run time at normal motion speed.
  static const duration = Duration(milliseconds: 3400);

  @override
  State<CelebrationFireworks> createState() => _CelebrationFireworksState();
}

class _CelebrationFireworksState extends State<CelebrationFireworks>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: CelebrationFireworks.duration,
  );
  late final _Show _show = _Show.generate(math.Random(widget.seed));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!MotionScope.of(context).reduced) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MotionScope.of(context).reduced) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _controller.isCompleted
              ? const SizedBox.expand()
              : CustomPaint(
                  size: Size.infinite,
                  painter: _FireworksPainter(_show, _controller.value),
                ),
        ),
      ),
    );
  }
}

const _palette = <Color>[
  LoungeTokens.goldAccent,
  Color(0xFFFFD98A),
  LoungeTokens.cardIvory,
  LoungeTokens.fiftyFlame,
  Color(0xFFE8B95A),
  Color(0xFFD94B3B),
  Color(0xFF5FA8D3),
];

class _Burst {
  _Burst(this.start, this.origin, this.peak, this.color, this.sparks);

  /// Launch time as a fraction of the show.
  final double start;
  final Offset origin;
  final Offset peak;
  final Color color;
  final List<Offset> sparks;
}

class _Confetto {
  _Confetto(this.x, this.delay, this.speed, this.drift, this.spin, this.color);

  final double x;
  final double delay;
  final double speed;
  final double drift;
  final double spin;
  final Color color;
}

class _Show {
  _Show(this.bursts, this.confetti);

  factory _Show.generate(math.Random rng) {
    final bursts = <_Burst>[
      for (var i = 0; i < 9; i++)
        _Burst(
          i * 0.075 + rng.nextDouble() * 0.04,
          Offset(0.15 + rng.nextDouble() * 0.7, 1.05),
          Offset(0.12 + rng.nextDouble() * 0.76, 0.12 + rng.nextDouble() * 0.3),
          _palette[rng.nextInt(_palette.length)],
          [
            for (var s = 0; s < 44; s++)
              Offset.fromDirection(
                s / 44 * math.pi * 2 + rng.nextDouble() * 0.2,
                0.6 + rng.nextDouble() * 0.5,
              ),
          ],
        ),
    ];
    final confetti = <_Confetto>[
      for (var i = 0; i < 90; i++)
        _Confetto(
          rng.nextDouble(),
          rng.nextDouble() * 0.45,
          0.7 + rng.nextDouble() * 0.6,
          (rng.nextDouble() - 0.5) * 0.12,
          (rng.nextDouble() - 0.5) * 18,
          _palette[rng.nextInt(_palette.length)],
        ),
    ];
    return _Show(bursts, confetti);
  }

  final List<_Burst> bursts;
  final List<_Confetto> confetti;
}

class _FireworksPainter extends CustomPainter {
  _FireworksPainter(this.show, this.t);

  final _Show show;
  final double t;

  static const _rise = 0.13;
  static const _burstLife = 0.32;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final glow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final dot = Paint();
    final scale = size.shortestSide * 0.55;

    for (final burst in show.bursts) {
      final local = t - burst.start;
      if (local < 0) continue;
      final origin = Offset(
        burst.origin.dx * size.width,
        burst.origin.dy * size.height,
      );
      final peak = Offset(
        burst.peak.dx * size.width,
        burst.peak.dy * size.height,
      );
      if (local < _rise) {
        // The rocket climbing, with a short fading trail.
        final p = Curves.easeOutCubic.transform(local / _rise);
        final head = Offset.lerp(origin, peak, p)!;
        final tail = Offset.lerp(origin, peak, math.max(0, p - 0.18))!;
        canvas.drawLine(
          tail,
          head,
          Paint()
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..shader = LinearGradient(
              colors: [burst.color.withValues(alpha: 0), burst.color],
            ).createShader(Rect.fromPoints(tail, head)),
        );
        continue;
      }
      final b = (local - _rise) / _burstLife;
      if (b > 1) continue;
      final spread = Curves.easeOutCubic.transform(b) * scale;
      final fall = b * b * scale * 0.35;
      final alpha = (1 - b).clamp(0.0, 1.0);
      // Flash at the moment of the burst.
      if (b < 0.18) {
        canvas.drawCircle(
          peak,
          scale * 0.18 * (1 - b / 0.18),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.5 * (1 - b / 0.18))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
        );
      }
      for (final spark in burst.sparks) {
        final p = peak + spark * spread + Offset(0, fall);
        glow.color = burst.color.withValues(alpha: alpha * 0.55);
        canvas.drawCircle(p, 5, glow);
        dot.color = Color.lerp(
          Colors.white,
          burst.color,
          0.35 + b * 0.65,
        )!.withValues(alpha: alpha);
        canvas.drawCircle(p, 2.4, dot);
      }
    }

    // Confetti drifting down across the whole screen.
    final piece = Paint();
    for (final c in show.confetti) {
      final local = (t - c.delay) / (1 - c.delay);
      if (local <= 0 || local >= 1) continue;
      final y = -0.05 + local * c.speed * 1.2;
      if (y > 1.05) continue;
      final x = c.x + math.sin(local * 9 + c.spin) * 0.02 + c.drift * local;
      final fade = local > 0.8 ? (1 - local) / 0.2 : 1.0;
      piece.color = c.color.withValues(alpha: 0.9 * fade);
      canvas.save();
      canvas.translate(x * size.width, y * size.height);
      canvas.rotate(local * c.spin);
      // Flipping in 3D: the visible width breathes as the piece turns.
      final w = 7 * (0.35 + 0.65 * math.cos(local * c.spin * 1.7).abs());
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: w, height: 4),
        piece,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _FireworksPainter oldDelegate) =>
      oldDelegate.t != t;
}

/// The Fifty strike: the table's loudest moment (design contract 1, heat on
/// purpose). A flame flash, a shockwave from the table's centre, a "50"
/// stamped down in the display face, and a spray of embers. Plays once and
/// calls [onDone]. Skipped under reduced motion (a brief glow only).
class FiftyStrike extends StatefulWidget {
  /// Creates the strike.
  const FiftyStrike({super.key, this.onDone});

  /// Called when the strike has finished.
  final VoidCallback? onDone;

  /// Total run time at normal motion speed.
  static const duration = Duration(milliseconds: 1500);

  @override
  State<FiftyStrike> createState() => _FiftyStrikeState();
}

class _FiftyStrikeState extends State<FiftyStrike>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: FiftyStrike.duration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) widget.onDone?.call();
        });
  final _embers = <Offset>[];
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(5050);
    for (var i = 0; i < 46; i++) {
      _embers.add(
        Offset.fromDirection(
          rng.nextDouble() * math.pi * 2,
          0.45 + rng.nextDouble() * 0.6,
        ),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final motion = MotionScope.of(context);
    _controller.duration = motion.reduced
        ? const Duration(milliseconds: 500)
        : FiftyStrike.duration;
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MotionScope.of(context).reduced;
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            return Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _StrikePainter(t, reduced ? const [] : _embers),
                ),
                if (!reduced) _stamp(t),
              ],
            );
          },
        ),
      ),
    );
  }

  /// "50" slammed onto the table: drops from large with a hard landing, holds,
  /// then burns off.
  Widget _stamp(double t) {
    const land = 0.16;
    final double scale;
    final double opacity;
    if (t < land) {
      final p = Curves.easeInCubic.transform(t / land);
      scale = 2.4 - 1.4 * p;
      opacity = p;
    } else if (t < 0.24) {
      // Recoil on impact.
      final p = (t - land) / 0.08;
      scale = 1 + 0.08 * math.sin(p * math.pi);
      opacity = 1;
    } else {
      scale = 1 + (t - 0.24) * 0.12;
      opacity = t < 0.7 ? 1 : (1 - (t - 0.7) / 0.3).clamp(0.0, 1.0);
    }
    return Center(
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFFFE3A0),
                LoungeTokens.fiftyFlame,
                Color(0xFFA92E24),
              ],
            ).createShader(rect),
            child: Text(
              '50',
              style: LoungeTokens.display.copyWith(
                fontSize: 120,
                color: Colors.white,
                height: 1,
                decoration: TextDecoration.none,
                shadows: [
                  Shadow(
                    color: LoungeTokens.fiftyFlame.withValues(alpha: 0.9),
                    blurRadius: 30,
                  ),
                  const Shadow(
                    color: Color(0xAA000000),
                    offset: Offset(0, 6),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StrikePainter extends CustomPainter {
  _StrikePainter(this.t, this.embers);

  final double t;
  final List<Offset> embers;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = size.center(Offset.zero);
    final reach = size.longestSide * 0.6;

    // Flame flash washing over the table, peaking at impact.
    final flash = t < 0.16 ? t / 0.16 : (1 - (t - 0.16) / 0.5).clamp(0.0, 1.0);
    if (flash > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            colors: [
              LoungeTokens.fiftyFlame.withValues(alpha: 0.45 * flash),
              LoungeTokens.deepRed.withValues(alpha: 0.22 * flash),
              Colors.transparent,
            ],
            stops: const [0, 0.45, 1],
          ).createShader(Rect.fromCircle(center: center, radius: reach)),
      );
    }

    // Two shockwave rings from the moment of impact.
    for (final delay in const [0.16, 0.26]) {
      final p = (t - delay) / 0.45;
      if (p <= 0 || p >= 1) continue;
      final r = Curves.easeOutCubic.transform(p) * reach;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10 * (1 - p) + 1
          ..color = Color.lerp(
            const Color(0xFFFFD98A),
            LoungeTokens.fiftyFlame,
            p,
          )!.withValues(alpha: 0.7 * (1 - p))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // Embers thrown out from the stamp, falling and cooling.
    final e = (t - 0.16) / 0.84;
    if (e > 0 && e < 1) {
      final spread = Curves.easeOutCubic.transform(e) * reach * 0.55;
      final fall = e * e * reach * 0.25;
      final paint = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      for (final ember in embers) {
        final p = center + ember * spread + Offset(0, fall);
        paint.color = Color.lerp(
          const Color(0xFFFFE3A0),
          LoungeTokens.deepRed,
          e,
        )!.withValues(alpha: (1 - e) * 0.95);
        canvas.drawCircle(p, 2.6 * (1 - e * 0.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StrikePainter oldDelegate) =>
      oldDelegate.t != t;
}

/// Shakes [child] once, briefly, each time [serial] changes: the table taking
/// the Fifty's hit. Still under reduced motion.
class ImpactShake extends StatelessWidget {
  /// Creates an impact shake.
  const ImpactShake({super.key, required this.serial, required this.child});

  /// Changes to trigger a shake; 0 never shakes.
  final int serial;

  /// Content to shake.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (serial == 0 || MotionScope.of(context).reduced) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(serial),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 560),
      // Begins as the stamp lands (about 240 ms into the strike).
      curve: const Interval(0.43, 1),
      builder: (context, t, child) {
        final amplitude = t <= 0 || t >= 1 ? 0.0 : 7 * (1 - t);
        return Transform.translate(
          offset: Offset(
            math.sin(t * math.pi * 9) * amplitude,
            math.cos(t * math.pi * 7) * amplitude * 0.5,
          ),
          child: child,
        );
      },
      child: child,
    );
  }
}
