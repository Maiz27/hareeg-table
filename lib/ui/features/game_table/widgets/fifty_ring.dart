import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion/motion_speed.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Fifty / Khamsin status visual.
///
/// Renders a circular timer ring around the "50" token, sweeping from full
/// to empty as the claim window counts down. The ring stays linear and runs
/// even in reduced motion because it carries essential turn information.
///
/// When [pulse] is true, a single 1.4 s heat halo plays around the ring
/// (skipped under reduced motion). Use this for the moment of a successful
/// claim — never as ambient decoration.
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

  /// True to play the one-shot heat halo.
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

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 6;

    // Pulse halo first (outside the ring).
    if (pulse > 0) {
      final haloRadius = radius + 6 + math.sin(pulse * math.pi) * 8;
      final haloAlpha = (math.sin(pulse * math.pi) * 0.55).clamp(0.0, 0.55);
      final halo = Paint()
        ..color = LoungeTokens.fiftyFlame.withValues(alpha: haloAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawCircle(center, haloRadius, halo);
    }

    // Background ring.
    final bg = Paint()
      ..color = LoungeTokens.sandLine.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bg);

    // Progress arc.
    final arc = Paint()
      ..color = LoungeTokens.fiftyFlame
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final sweep = progress * math.pi * 2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      arc,
    );

    // Inner disc.
    final disc = Paint()
      ..color = LoungeTokens.coffeeCharcoal
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 6, disc);

    // Inner ring stroke.
    final innerStroke = Paint()
      ..color = LoungeTokens.fiftyFlame.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius - 6, innerStroke);
  }

  @override
  bool shouldRepaint(covariant _FiftyRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.pulse != pulse;
  }
}
