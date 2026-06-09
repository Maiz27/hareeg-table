import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion/motion_speed.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Fifty / Khamsin status visual.
///
/// Renders a circular timer ring around the seconds-remaining token, sweeping
/// from full to empty as the claim window counts down. The ring stays linear
/// and runs even in reduced motion because it carries essential turn
/// information.
///
/// The ring reads as a small flame: the progress arc runs a gold→orange→red
/// fire gradient inside a warm halo, so claiming Fifty is a visually distinct,
/// deliberate target separate from picking the card up off the pile.
///
/// When [pulse] is true, a one-shot heat flare plays around the ring (skipped
/// under reduced motion). Use this for the moment of a successful claim — never
/// as ambient decoration. The ring intentionally has no looping animation so it
/// settles for `pumpAndSettle` and never spins frames on the table.
class FiftyRing extends StatefulWidget {
  /// Creates a Fifty ring.
  const FiftyRing({
    super.key,
    required this.secondsRemaining,
    required this.totalSeconds,
    this.pulse = false,
    this.diameter = 96,
  });

  /// Seconds left on the claim window. Null hides the ring entirely.
  final int? secondsRemaining;

  /// Total seconds the timer started at (from setup.fiftyTimerSeconds).
  final int totalSeconds;

  /// True to play the one-shot heat flare.
  final bool pulse;

  /// Outer diameter of the ring.
  final double diameter;

  @override
  State<FiftyRing> createState() => _FiftyRingState();
}

class _FiftyRingState extends State<FiftyRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: TableMotion.fiftyHeatPulse,
    );
  }

  @override
  void didUpdateWidget(covariant FiftyRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !oldWidget.pulse) {
      _pulseController
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.secondsRemaining;
    if (remaining == null) {
      return const SizedBox.shrink();
    }
    final motion = MotionScope.of(context);
    final progress = widget.totalSeconds <= 0
        ? 0.0
        : (remaining / widget.totalSeconds).clamp(0.0, 1.0);

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulseValue = motion.reduced ? 0.0 : _pulseController.value;
        return SizedBox.square(
          dimension: widget.diameter,
          child: CustomPaint(
            painter: _FiftyRingPainter(
              progress: progress,
              pulse: pulseValue,
            ),
            child: Center(
              child: Text(
                '$remaining',
                style: const TextStyle(
                  color: LoungeTokens.offWhiteText,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FiftyRingPainter extends CustomPainter {
  _FiftyRingPainter({required this.progress, required this.pulse});

  final double progress;
  final double pulse;

  // Fire palette: bright gold tip → orange body → deep-red base.
  static const _flameColors = [
    LoungeTokens.goldAccent,
    LoungeTokens.fiftyFlame,
    LoungeTokens.deepRed,
    LoungeTokens.fiftyFlame,
    LoungeTokens.goldAccent,
  ];
  static const _flameStops = [0.0, 0.28, 0.5, 0.72, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 6;
    final ringRect = Rect.fromCircle(center: center, radius: radius);

    // Steady flame glow that gives the ring its "hot" read: a soft red outer
    // wash plus a brighter orange band hugging the ring.
    final outerGlow = Paint()
      ..color = LoungeTokens.deepRed.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawCircle(center, radius + 5, outerGlow);
    final innerGlow = Paint()
      ..color = LoungeTokens.fiftyFlame.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center, radius + 2, innerGlow);

    // One-shot success flare (outside the steady glow).
    if (pulse > 0) {
      final flareRadius = radius + 8 + math.sin(pulse * math.pi) * 10;
      final flareAlpha = (math.sin(pulse * math.pi) * 0.6).clamp(0.0, 0.6);
      final flare = Paint()
        ..color = LoungeTokens.goldAccent.withValues(alpha: flareAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(center, flareRadius, flare);
    }

    // Background ring.
    final bg = Paint()
      ..color = LoungeTokens.sandLine.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bg);

    // Progress arc, drawn with the fire gradient so the live countdown is the
    // flame itself. The gradient is rotated so the bright gold tip rides the
    // leading (12 o'clock) edge.
    final arc = Paint()
      ..shader = const SweepGradient(
        colors: _flameColors,
        stops: _flameStops,
        transform: GradientRotation(-math.pi / 2),
      ).createShader(ringRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    final sweep = progress * math.pi * 2;
    canvas.drawArc(ringRect, -math.pi / 2, sweep, false, arc);

    // Inner disc + a faint flame inner stroke.
    final disc = Paint()
      ..color = LoungeTokens.coffeeCharcoal
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 6, disc);
    final innerStroke = Paint()
      ..color = LoungeTokens.fiftyFlame.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius - 6, innerStroke);
  }

  @override
  bool shouldRepaint(covariant _FiftyRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.pulse != pulse;
  }
}
