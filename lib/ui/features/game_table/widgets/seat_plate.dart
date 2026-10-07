import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion/motion_speed.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Seat identity plate for a CPU seat (design contract section 7.2).
///
/// A medallion carrying the seat's running match score, ringed by an arc that
/// fills toward the elimination score and warms from sand to flame as the
/// seat nears it, plus a pill with the seat's current hand size. The plate
/// echoes the seat's turn state (gold edge and glow while active) so whose
/// turn it is reads at a glance even when the rail is busy.
///
/// Every animation here is implicit and finite, so a table test can still
/// settle while a CPU seat is thinking.
class SeatPlate extends StatelessWidget {
  /// Creates a seat plate.
  const SeatPlate({
    super.key,
    required this.label,
    required this.cardCount,
    required this.active,
    required this.thinking,
    required this.eliminated,
    required this.compact,
    this.score,
    this.eliminationScore = 31,
    this.axis = Axis.horizontal,
  });

  /// Accessible / tooltip name of the seat (for example "CPU North").
  final String label;

  /// Cards currently in the seat's hand.
  final int cardCount;

  /// Running match score, or null when the surface has no score to show.
  final int? score;

  /// Score at which a seat is eliminated; drives the danger arc.
  final int eliminationScore;

  /// Whether it is this seat's turn.
  final bool active;

  /// Whether the CPU on this seat is choosing a move.
  final bool thinking;

  /// Whether the seat is out of the match.
  final bool eliminated;

  /// Compact table layout.
  final bool compact;

  /// Horizontal puts the count pill beside the medallion (north seat);
  /// vertical stacks it underneath (west / east seats).
  final Axis axis;

  /// Medallion diameter for the given layout.
  static double medallionSize({required bool compact}) => compact ? 30 : 38;

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    final diameter = medallionSize(compact: compact);
    final value = score;
    final danger = value == null || eliminationScore <= 0
        ? 0.0
        : (value / eliminationScore).clamp(0.0, 1.0);
    final medallion = _Medallion(
      diameter: diameter,
      score: value,
      cardCount: cardCount,
      danger: danger,
      active: active && !eliminated,
      thinking: thinking && !eliminated,
      duration: motion.scale(LoungeTokens.motionEmphasis),
      curve: motion.curve(Curves.easeOutCubic),
    );
    final pill = _CountPill(
      count: cardCount,
      compact: compact,
      active: active && !eliminated,
    );
    final children = value == null
        ? <Widget>[medallion]
        : axis == Axis.horizontal
        ? <Widget>[medallion, SizedBox(width: compact ? 4 : 6), pill]
        : <Widget>[medallion, SizedBox(height: compact ? 3 : 4), pill];

    final scoreText = value == null ? '' : ' · $value';
    return Semantics(
      container: true,
      label: '$label$scoreText · $cardCount',
      child: ExcludeSemantics(
        child: Tooltip(
          message: '$label$scoreText',
          child: AnimatedOpacity(
            opacity: eliminated ? 0.35 : 1,
            duration: motion.scale(LoungeTokens.motionStandard),
            child: axis == Axis.horizontal
                ? Row(mainAxisSize: MainAxisSize.min, children: children)
                : Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );
  }
}

/// The score medallion shared by the seat plates and the score sheet: the
/// score, ringed by an arc that fills and warms toward elimination.
class ScoreMedallion extends StatelessWidget {
  /// Creates a score medallion.
  const ScoreMedallion({
    super.key,
    required this.diameter,
    required this.score,
    required this.eliminationScore,
    this.active = false,
  });

  /// Medallion diameter.
  final double diameter;

  /// Score shown in the medallion.
  final int score;

  /// Score at which a seat is eliminated.
  final int eliminationScore;

  /// Whether to draw the active (gold) edge and glow.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    return _Medallion(
      diameter: diameter,
      score: score,
      cardCount: 0,
      danger: eliminationScore <= 0
          ? 0
          : (score / eliminationScore).clamp(0.0, 1.0),
      active: active,
      thinking: false,
      duration: motion.scale(LoungeTokens.motionEmphasis),
      curve: motion.curve(Curves.easeOutCubic),
    );
  }
}

class _Medallion extends StatelessWidget {
  const _Medallion({
    required this.diameter,
    required this.score,
    required this.cardCount,
    required this.danger,
    required this.active,
    required this.thinking,
    required this.duration,
    required this.curve,
  });

  final double diameter;
  final int? score;
  final int cardCount;
  final double danger;
  final bool active;
  final bool thinking;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final glow = active ? (thinking ? 0.55 : 0.4) : 0.0;
    return AnimatedContainer(
      duration: duration,
      curve: curve,
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          ...LoungeTokens.elevationL2,
          if (active)
            BoxShadow(
              color: LoungeTokens.goldAccent.withValues(alpha: glow),
              blurRadius: thinking ? 18 : 12,
              spreadRadius: thinking ? 2 : 0.5,
            ),
        ],
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: danger),
        duration: duration,
        curve: curve,
        builder: (context, t, _) => CustomPaint(
          painter: _MedallionPainter(danger: t, active: active),
          child: Center(
            child: Text(
              '${score ?? cardCount}',
              style: LoungeTokens.numericDisplay.copyWith(
                fontSize:
                    diameter * (score != null && score! >= 10 ? 0.4 : 0.46),
                color: Color.lerp(
                  LoungeTokens.offWhiteText,
                  const Color(0xFFFFB08A),
                  ((t - 0.6) / 0.4).clamp(0.0, 1.0),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MedallionPainter extends CustomPainter {
  const _MedallionPainter({required this.danger, required this.active});

  final double danger;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Lacquered face: lit from above like everything else on the table.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.25, -0.45),
          radius: 1.0,
          colors: [Color(0xFF3A2A1C), LoungeTokens.coffeeCharcoal],
        ).createShader(rect),
    );

    // Track for the danger arc.
    final ringWidth = math.max(2.0, radius * 0.14);
    final ringRect = rect.deflate(ringWidth / 2 + 1);
    canvas.drawArc(
      ringRect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..color = LoungeTokens.sandLine.withValues(alpha: 0.16),
    );

    // Danger arc: how close the seat is to elimination.
    if (danger > 0) {
      final color = Color.lerp(
        LoungeTokens.sandLine,
        LoungeTokens.fiftyFlame,
        ((danger - 0.45) / 0.55).clamp(0.0, 1.0),
      )!;
      canvas.drawArc(
        ringRect,
        -math.pi / 2,
        math.pi * 2 * danger,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringWidth
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }

    // Outer edge: gold on the active seat, quiet sand otherwise.
    canvas.drawCircle(
      center,
      radius - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 1.6 : 1
        ..color = active
            ? LoungeTokens.goldAccent
            : LoungeTokens.sandLine.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant _MedallionPainter oldDelegate) =>
      oldDelegate.danger != danger || oldDelegate.active != active;
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.count,
    required this.compact,
    required this.active,
  });

  final int count;
  final bool compact;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 9.0 : 11.0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 7,
        vertical: compact ? 1.5 : 2.5,
      ),
      decoration: BoxDecoration(
        color: LoungeTokens.surfaceL2,
        borderRadius: BorderRadius.circular(LoungeTokens.radiusPill),
        border: Border.all(
          color: active
              ? LoungeTokens.goldAccent.withValues(alpha: 0.7)
              : LoungeTokens.edgeL2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A tiny card glyph so the number reads as "cards in hand".
          Container(
            width: iconSize * 0.72,
            height: iconSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(1.5),
              border: Border.all(color: LoungeTokens.sandLine, width: 1),
            ),
          ),
          SizedBox(width: compact ? 3 : 4),
          Text(
            '$count',
            style: LoungeTokens.numericChip.copyWith(
              fontSize: compact ? 10 : 11.5,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
