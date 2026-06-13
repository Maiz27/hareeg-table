import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../l10n/app_strings.dart';
import '../motion/motion_speed.dart';
import 'card_painting.dart';
import 'card_state.dart';
import 'card_theme.dart';
import 'suit_glyphs.dart';

/// Renders a single Hareeg card using the active [CardTheme].
///
/// Composes the theme's face/back paint with the state overlay defined by
/// the theme (or default) and a subtle state-change tween. The caller drives
/// visual state via [visualState]; this widget only keeps local timing state
/// for memory-joker reveal.
class HareegCardView extends StatefulWidget {
  /// Creates a card view.
  const HareegCardView({
    super.key,
    required this.theme,
    required this.card,
    this.variant = CardVariant.full,
    this.visualState = CardVisualState.normal,
    this.jokerDisplay,
    this.badge = CardBadge.none,
    this.faceDown = false,
    this.size = const Size(64, 92),
    this.semanticsLabel,
    this.coachRingColor,
  });

  /// Active theme.
  final HareegCardTheme theme;

  /// Card being rendered.
  final HareegCard card;

  /// Variant requested.
  final CardVariant variant;

  /// Visual state overlay.
  final CardVisualState visualState;

  /// Joker display override. Defaults to [JokerDisplayScope] when omitted.
  final JokerDisplay? jokerDisplay;

  /// Optional badge.
  final CardBadge badge;

  /// True to draw the card back regardless of [variant].
  final bool faceDown;

  /// Render size.
  final Size size;

  /// Optional accessibility label override.
  final String? semanticsLabel;

  /// Overrides the coach-highlight ring colour (used to distinguish meld
  /// groups). Only applies when [visualState] is
  /// [CardVisualState.coachHighlight]; null keeps the default teal.
  final Color? coachRingColor;

  @override
  State<HareegCardView> createState() => _HareegCardViewState();
}

class _HareegCardViewState extends State<HareegCardView>
    with SingleTickerProviderStateMixin {
  /// Fade-in window before the cue settles at full opacity.
  static const _fadeInDuration = Duration(milliseconds: 200);

  /// Fade-out window after the hold expires.
  static const _fadeOutDuration = Duration(milliseconds: 400);

  AnimationController? _cueController;
  Animation<double>? _cueOpacity;
  JokerDisplay? _lastResolvedJokerDisplay;
  Duration? _lastResolvedCueDuration;
  bool _memoryRevealQuieted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final resolvedDisplay =
        widget.jokerDisplay ?? JokerDisplayScope.of(context);
    final resolvedCueDuration = JokerDisplayScope.cueDurationOf(context);
    final displayChanged = _lastResolvedJokerDisplay != resolvedDisplay;
    final durationChanged = _lastResolvedCueDuration != resolvedCueDuration;
    if (displayChanged || durationChanged) {
      _lastResolvedJokerDisplay = resolvedDisplay;
      _lastResolvedCueDuration = resolvedCueDuration;
      _memoryRevealQuieted = false;
      _syncCue();
    } else if (_cueController == null && _shouldMemoryReveal) {
      _syncCue();
    }
  }

  @override
  void didUpdateWidget(covariant HareegCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final cardChanged =
        oldWidget.card.id != widget.card.id ||
        oldWidget.card.representedIdentity != widget.card.representedIdentity;
    final displayChanged = oldWidget.jokerDisplay != widget.jokerDisplay;
    if (cardChanged || displayChanged) {
      // Re-resolve from scope when the override is removed; falling back
      // to the cached value would keep the prior override pinned forever.
      _lastResolvedJokerDisplay =
          widget.jokerDisplay ?? JokerDisplayScope.of(context);
      _memoryRevealQuieted = false;
      _syncCue();
    }
  }

  @override
  void dispose() {
    _cueController?.dispose();
    super.dispose();
  }

  bool get _shouldMemoryReveal {
    final display =
        widget.jokerDisplay ??
        _lastResolvedJokerDisplay ??
        JokerDisplay.assisted;
    return widget.card.isJoker &&
        widget.card.representedIdentity != null &&
        display == JokerDisplay.memoryReveal;
  }

  void _syncCue() {
    _cueController?.dispose();
    _cueController = null;
    _cueOpacity = null;
    if (!_shouldMemoryReveal) {
      _memoryRevealQuieted = false;
      return;
    }
    final hold = _lastResolvedCueDuration;
    if (hold == null) {
      return;
    }
    final motion = MotionScope.of(context);
    final fadeIn = motion.scale(_fadeInDuration);
    final fadeOut = motion.scale(_fadeOutDuration);
    final scaledHold = motion.scale(hold);
    final controller = AnimationController(
      vsync: this,
      duration: fadeIn + scaledHold + fadeOut,
    );
    final fadeInWeight = fadeIn.inMilliseconds.toDouble().clamp(1.0, 1e9);
    final holdWeight = scaledHold.inMilliseconds.toDouble().clamp(1.0, 1e9);
    final fadeOutWeight = fadeOut.inMilliseconds.toDouble().clamp(1.0, 1e9);
    final opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0),
        weight: fadeInWeight,
      ),
      TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: holdWeight,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0),
        weight: fadeOutWeight,
      ),
    ]).animate(controller);
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _memoryRevealQuieted = true);
      }
    });
    _cueController = controller;
    _cueOpacity = opacity;
    controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    final baseOverlay = widget.theme.overlayFor(widget.visualState);
    final resolvedOverlay = CardContrastScope.enabledOf(context)
        ? HighContrastCardStateOverlays.resolve(widget.visualState, baseOverlay)
        : baseOverlay;
    // A per-meld coach ring colour recolours the highlight without touching
    // the theme's overlay map, so grouped opening/finish hints can ring each
    // meld distinctly while every other state stays as the theme defines it.
    final ringColor = widget.coachRingColor;
    final overlay =
        widget.visualState == CardVisualState.coachHighlight && ringColor != null
        ? CardStateOverlayStyle(
            outline: ringColor,
            outlineWidth: resolvedOverlay.outlineWidth,
            glow: ringColor.withValues(alpha: 0.5),
          )
        : resolvedOverlay;
    final scopedJokerDisplay =
        widget.jokerDisplay ?? JokerDisplayScope.of(context);
    final effectiveJokerDisplay = _shouldMemoryReveal && _memoryRevealQuieted
        ? JokerDisplay.unassigned
        : scopedJokerDisplay;
    final opacityAnimation = _cueOpacity;
    final cueActive =
        _shouldMemoryReveal && !_memoryRevealQuieted && opacityAnimation != null;
    final label =
        widget.semanticsLabel ??
        _defaultSemanticsLabel(context, effectiveJokerDisplay);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: label,
      child: AnimatedSwitcher(
        duration: motion.scale(const Duration(milliseconds: 120)),
        switchInCurve: motion.curve(Curves.easeOut),
        switchOutCurve: motion.curve(Curves.easeIn),
        child: SizedBox.fromSize(
          key: ValueKey(
            '${widget.theme.id}-${widget.card.id}-'
            '${widget.visualState}-$effectiveJokerDisplay',
          ),
          size: widget.size,
          child: cueActive
              ? AnimatedBuilder(
                  animation: opacityAnimation,
                  builder: (context, _) => _buildSurface(
                    effectiveJokerDisplay,
                    opacityAnimation.value,
                    overlay,
                  ),
                )
              : _buildSurface(effectiveJokerDisplay, 1.0, overlay),
        ),
      ),
    );
  }

  Widget _buildSurface(
    JokerDisplay effectiveJokerDisplay,
    double revealOpacity,
    CardStateOverlayStyle overlay,
  ) {
    final request = CardRenderRequest(
      card: widget.card,
      variant: widget.variant,
      size: widget.size,
      visualState: widget.visualState,
      jokerDisplay: effectiveJokerDisplay,
      badge: widget.badge,
      faceDown: widget.faceDown,
      revealOpacity: revealOpacity,
    );
    final assetPath = widget.theme.imageAssetFor(request);
    if (assetPath == null) {
      return CustomPaint(
        painter: _CardThemePainter(
          theme: widget.theme,
          request: request,
          overlay: overlay,
        ),
        size: widget.size,
      );
    }
    return _AssetCardSurface(
      assetPath: assetPath,
      request: request,
      overlay: overlay,
    );
  }

  String _defaultSemanticsLabel(
    BuildContext context,
    JokerDisplay jokerDisplay,
  ) {
    final strings = context.strings;
    if (widget.faceDown) return strings.faceDownCard;
    if (widget.card.isJoker) {
      final represented = widget.card.representedIdentity;
      if (represented != null && jokerDisplay != JokerDisplay.unassigned) {
        return strings.jokerRepresenting(strings.cardName(represented));
      }
      return strings.joker;
    }
    final identity = widget.card.effectiveIdentity!;
    return strings.cardName(identity);
  }
}

class _AssetCardSurface extends StatelessWidget {
  const _AssetCardSurface({
    required this.assetPath,
    required this.request,
    required this.overlay,
  });

  final String assetPath;
  final CardRenderRequest request;
  final CardStateOverlayStyle overlay;

  @override
  Widget build(BuildContext context) {
    final represented = request.card.representedIdentity;
    final showBadge =
        request.card.isJoker &&
        represented != null &&
        request.jokerDisplay != JokerDisplay.unassigned &&
        request.revealOpacity > 0.0;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          assetPath,
          fit: BoxFit.contain,
          // On web/desktop the table scales up and cubic filtering keeps the
          // pip/index detail clean. On native the cards downscale hard
          // (256px source into a small slot) where medium's mipmapped
          // bilinear is both sharper and cheaper, so keep the validated
          // medium there.
          filterQuality: kIsWeb ? FilterQuality.high : FilterQuality.medium,
        ),
        if (showBadge)
          if (request.revealOpacity >= 1.0)
            _RepresentedJokerBadge(identity: represented, size: request.size)
          else
            Opacity(
              opacity: request.revealOpacity.clamp(0.0, 1.0),
              child: _RepresentedJokerBadge(
                identity: represented,
                size: request.size,
              ),
            ),
        CustomPaint(painter: _CardStateOverlayPainter(overlay: overlay)),
      ],
    );
  }
}

class _RepresentedJokerBadge extends StatelessWidget {
  const _RepresentedJokerBadge({required this.identity, required this.size});

  final CardIdentity identity;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final labelSize = (size.shortestSide * 0.22).clamp(8.0, 14.0);
    final glyphSize = (size.shortestSide * 0.18).clamp(7.0, 12.0);
    final suitColor = switch (identity.suit) {
      CardSuit.hearts || CardSuit.diamonds => const Color(0xFFB84234),
      CardSuit.spades || CardSuit.clubs => const Color(0xFFF8F1E4),
    };
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: EdgeInsets.only(bottom: size.height * 0.09),
        padding: EdgeInsets.symmetric(
          horizontal: size.width * 0.08,
          vertical: size.height * 0.015,
        ),
        decoration: BoxDecoration(
          color: const Color(0xE61F1A14),
          borderRadius: BorderRadius.circular(size.shortestSide * 0.12),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                identity.rank.label,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFFF8F1E4),
                  fontSize: labelSize,
                  height: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(width: size.shortestSide * 0.035),
              CustomPaint(
                size: Size.square(glyphSize),
                painter: _InlineSuitGlyphPainter(
                  suit: identity.suit,
                  color: suitColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineSuitGlyphPainter extends CustomPainter {
  const _InlineSuitGlyphPainter({required this.suit, required this.color});

  final CardSuit suit;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width, size.height);
    canvas.drawPath(
      SuitGlyphs.pathFor(suit),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _InlineSuitGlyphPainter oldDelegate) {
    return oldDelegate.suit != suit || oldDelegate.color != color;
  }
}

class _CardStateOverlayPainter extends CustomPainter {
  _CardStateOverlayPainter({required this.overlay});

  final CardStateOverlayStyle overlay;

  @override
  void paint(Canvas canvas, Size size) {
    CardPainting.paintStateOverlay(canvas, size, overlay);
  }

  @override
  bool shouldRepaint(covariant _CardStateOverlayPainter oldDelegate) {
    return oldDelegate.overlay.outline != overlay.outline ||
        oldDelegate.overlay.outlineWidth != overlay.outlineWidth ||
        oldDelegate.overlay.glow != overlay.glow ||
        oldDelegate.overlay.tint != overlay.tint;
  }
}

class _CardThemePainter extends CustomPainter {
  _CardThemePainter({
    required this.theme,
    required this.request,
    required this.overlay,
  });

  final HareegCardTheme theme;
  final CardRenderRequest request;
  final CardStateOverlayStyle overlay;

  @override
  void paint(Canvas canvas, Size size) {
    theme.paint(canvas, request);
    CardPainting.paintStateOverlay(canvas, size, overlay);
  }

  @override
  bool shouldRepaint(covariant _CardThemePainter oldDelegate) {
    return oldDelegate.theme.id != theme.id ||
        oldDelegate.request.visualState != request.visualState ||
        oldDelegate.request.size != request.size ||
        oldDelegate.request.faceDown != request.faceDown ||
        oldDelegate.request.jokerDisplay != request.jokerDisplay ||
        oldDelegate.request.badge != request.badge ||
        oldDelegate.request.revealOpacity != request.revealOpacity ||
        // The overlay can change without the visual state changing — a per-meld
        // coach ring colour recolours the highlight while the state stays
        // `coachHighlight`. Compare its fields (as _CardStateOverlayPainter does)
        // so a ring-colour change repaints instead of leaving a stale ring.
        oldDelegate.overlay.outline != overlay.outline ||
        oldDelegate.overlay.outlineWidth != overlay.outlineWidth ||
        oldDelegate.overlay.glow != overlay.glow ||
        oldDelegate.overlay.tint != overlay.tint;
  }
}
