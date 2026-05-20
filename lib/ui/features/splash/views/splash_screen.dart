import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/motion/motion_speed.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Flutter splash shown on first frame.
///
/// Sits between the native launch screen (charcoal background + icon stamp)
/// and the home screen. Plays one quiet Fifty heat pulse around the wordmark
/// and a sand-line corner ornament fade, then crossfades to the home route.
/// Reduced motion replaces the pulse with an instant fade. Tap anywhere to
/// skip.
class SplashScreen extends StatefulWidget {
  /// Creates the splash screen.
  const SplashScreen({super.key, required this.onContinue});

  /// Called when the splash should hand off to the next route.
  final VoidCallback onContinue;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _wordmarkFade;
  late final Animation<double> _heatPulse;
  late final Animation<double> _cornerFade;
  bool _handedOff = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: TableMotion.splashDwell,
    );
    _wordmarkFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
    );
    _cornerFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.05, 0.55, curve: Curves.easeOut),
    );
    _heatPulse = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 0.95, curve: Curves.easeInOut),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _handOff();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    final motion = MotionScope.of(context);
    if (motion.reduced) {
      _handOff();
      return;
    }
    _controller
      ..duration = motion.scale(TableMotion.splashDwell)
      ..forward();
  }

  void _handOff() {
    if (_handedOff || !mounted) {
      return;
    }
    _handedOff = true;
    widget.onContinue();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoungeTokens.coffeeCharcoal,
      body: GestureDetector(
        onTap: _handOff,
        behavior: HitTestBehavior.opaque,
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  _CornerOrnaments(opacity: _cornerFade.value),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _FannedCards(opacity: _wordmarkFade.value),
                        const SizedBox(height: LoungeTokens.space5),
                        _Wordmark(
                          opacity: _wordmarkFade.value,
                          pulse: _heatPulse.value,
                        ),
                        const SizedBox(height: LoungeTokens.space3),
                        Opacity(
                          opacity: _wordmarkFade.value * 0.8,
                          child: const Text(
                            'Offline Classic Hareeg',
                            style: LoungeTokens.bodyMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: LoungeTokens.space4,
                    left: 0,
                    right: 0,
                    child: Opacity(
                      opacity: _wordmarkFade.value * 0.55,
                      child: const Center(
                        child: Text(
                          'Tap to continue',
                          style: TextStyle(
                            color: LoungeTokens.mutedText,
                            fontSize: 12,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CornerOrnaments extends StatelessWidget {
  const _CornerOrnaments({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    final motif = SizedBox.square(
      dimension: 56,
      child: CustomPaint(
        painter: GeometricMotifPainter(
          variant: LoungeMotifVariant.corner,
          color: LoungeTokens.sandLine,
          opacity: opacity * 0.7,
          strokeWidth: 1.0,
        ),
      ),
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

class _FannedCards extends StatelessWidget {
  const _FannedCards({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: SizedBox(
        width: 200,
        height: 90,
        child: CustomPaint(painter: _FannedCardsPainter()),
      ),
    );
  }
}

class _FannedCardsPainter extends CustomPainter {
  static const _cardCount = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final cardWidth = size.width * 0.32;
    final cardHeight = size.height * 0.95;
    final center = Offset(size.width / 2, size.height);
    const fanArc = 0.55;

    for (var i = 0; i < _cardCount; i++) {
      final t = (i - (_cardCount - 1) / 2) / (_cardCount - 1);
      final angle = t * fanArc;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      canvas.translate(-cardWidth / 2, -cardHeight);

      final rect = Rect.fromLTWH(0, 0, cardWidth, cardHeight);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));

      final shadow = Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawRRect(rrect.shift(const Offset(0, 1.5)), shadow);

      final fill = Paint()..color = LoungeTokens.cardIvory;
      canvas.drawRRect(rrect, fill);

      final stroke = Paint()
        ..color = LoungeTokens.sandLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawRRect(rrect, stroke);

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.opacity, required this.pulse});

  final double opacity;
  final double pulse;

  @override
  Widget build(BuildContext context) {
    final glowSize = 72.0 + math.sin(pulse * math.pi) * 14.0;
    final glowOpacity = (math.sin(pulse * math.pi) * 0.65).clamp(0.0, 0.65);

    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: glowSize,
          height: glowSize,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  LoungeTokens.fiftyFlame.withValues(alpha: glowOpacity),
                  LoungeTokens.fiftyFlame.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        Opacity(
          opacity: opacity,
          child: const _WordmarkText(),
        ),
      ],
    );
  }
}

class _WordmarkText extends StatelessWidget {
  const _WordmarkText();

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: const TextSpan(
        children: [
          TextSpan(
            text: 'Hareeg ',
            style: TextStyle(
              color: LoungeTokens.offWhiteText,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          TextSpan(
            text: 'Table',
            style: TextStyle(
              color: LoungeTokens.goldAccent,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
