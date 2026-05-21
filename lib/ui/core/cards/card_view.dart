import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../l10n/app_strings.dart';
import '../motion/motion_speed.dart';
import 'card_painting.dart';
import 'card_state.dart';
import 'card_theme.dart';

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

  @override
  State<HareegCardView> createState() => _HareegCardViewState();
}

class _HareegCardViewState extends State<HareegCardView> {
  static const _memoryRevealDuration = Duration(milliseconds: 1600);

  Timer? _memoryRevealTimer;
  JokerDisplay? _lastResolvedJokerDisplay;
  bool _memoryRevealQuieted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final resolvedDisplay =
        widget.jokerDisplay ?? JokerDisplayScope.of(context);
    if (_lastResolvedJokerDisplay != resolvedDisplay) {
      _lastResolvedJokerDisplay = resolvedDisplay;
      _memoryRevealQuieted = false;
      _syncMemoryRevealTimer();
    } else if (_memoryRevealTimer == null && _shouldMemoryReveal) {
      _syncMemoryRevealTimer();
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
      _lastResolvedJokerDisplay =
          widget.jokerDisplay ?? _lastResolvedJokerDisplay;
      _memoryRevealQuieted = false;
      _syncMemoryRevealTimer();
    }
  }

  @override
  void dispose() {
    _memoryRevealTimer?.cancel();
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

  void _syncMemoryRevealTimer() {
    _memoryRevealTimer?.cancel();
    _memoryRevealTimer = null;
    if (!_shouldMemoryReveal) {
      _memoryRevealQuieted = false;
      return;
    }
    _memoryRevealTimer = Timer(_memoryRevealDuration, () {
      if (!mounted) return;
      setState(() => _memoryRevealQuieted = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    final overlay = widget.theme.overlayFor(widget.visualState);
    final scopedJokerDisplay =
        widget.jokerDisplay ?? JokerDisplayScope.of(context);
    final effectiveJokerDisplay = _shouldMemoryReveal && _memoryRevealQuieted
        ? JokerDisplay.unassigned
        : scopedJokerDisplay;
    final request = CardRenderRequest(
      card: widget.card,
      variant: widget.variant,
      size: widget.size,
      visualState: widget.visualState,
      jokerDisplay: effectiveJokerDisplay,
      badge: widget.badge,
      faceDown: widget.faceDown,
    );

    final assetPath = widget.theme.imageAssetFor(request);
    final surface = assetPath == null
        ? CustomPaint(
            painter: _CardThemePainter(
              theme: widget.theme,
              request: request,
              overlay: overlay,
            ),
            size: widget.size,
          )
        : _AssetCardSurface(
            assetPath: assetPath,
            request: request,
            overlay: overlay,
          );

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
          child: surface,
        ),
      ),
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
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          assetPath,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
        if (request.card.isJoker &&
            represented != null &&
            request.jokerDisplay != JokerDisplay.unassigned)
          _RepresentedJokerBadge(identity: represented, size: request.size),
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
        child: Text(
          identity.label,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: const Color(0xFFF8F1E4),
            fontSize: labelSize,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
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
        oldDelegate.request.badge != request.badge;
  }
}
