import 'package:flutter/material.dart';

import '../../../domain/classic_hareeg/models/playing_card.dart';
import '../motion/motion_speed.dart';
import 'card_painting.dart';
import 'card_state.dart';
import 'card_theme.dart';

/// Renders a single Hareeg card using the active [CardTheme].
///
/// Composes the theme's face/back paint with the state overlay defined by
/// the theme (or default) and a subtle state-change tween. Stateless: the
/// caller drives visual state via [visualState].
class HareegCardView extends StatelessWidget {
  /// Creates a card view.
  const HareegCardView({
    super.key,
    required this.theme,
    required this.card,
    this.variant = CardVariant.full,
    this.visualState = CardVisualState.normal,
    this.jokerDisplay = JokerDisplay.assisted,
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

  /// Joker display mode.
  final JokerDisplay jokerDisplay;

  /// Optional badge.
  final CardBadge badge;

  /// True to draw the card back regardless of [variant].
  final bool faceDown;

  /// Render size.
  final Size size;

  /// Optional accessibility label override.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    final overlay = theme.overlayFor(visualState);
    final request = CardRenderRequest(
      card: card,
      variant: variant,
      size: size,
      visualState: visualState,
      jokerDisplay: jokerDisplay,
      badge: badge,
      faceDown: faceDown,
    );

    final assetPath = theme.imageAssetFor(request);
    final surface = assetPath == null
        ? CustomPaint(
            painter: _CardThemePainter(
              theme: theme,
              request: request,
              overlay: overlay,
            ),
            size: size,
          )
        : _AssetCardSurface(
            assetPath: assetPath,
            request: request,
            overlay: overlay,
          );

    final label = semanticsLabel ?? _defaultSemanticsLabel();
    return Semantics(
      label: label,
      child: AnimatedSwitcher(
        duration: motion.scale(const Duration(milliseconds: 120)),
        switchInCurve: motion.curve(Curves.easeOut),
        switchOutCurve: motion.curve(Curves.easeIn),
        child: SizedBox.fromSize(
          key: ValueKey('${theme.id}-${card.id}-$visualState-$jokerDisplay'),
          size: size,
          child: surface,
        ),
      ),
    );
  }

  String _defaultSemanticsLabel() {
    if (faceDown) return 'Face-down card';
    if (card.isJoker) {
      final represented = card.representedIdentity;
      if (represented != null) {
        return 'Joker representing ${represented.label}';
      }
      return 'Joker';
    }
    final identity = card.effectiveIdentity!;
    return '${_rankWord(identity.rank)} of ${_suitWord(identity.suit)}';
  }

  static String _rankWord(CardRank rank) {
    return switch (rank) {
      CardRank.ace => 'Ace',
      CardRank.two => 'Two',
      CardRank.three => 'Three',
      CardRank.four => 'Four',
      CardRank.five => 'Five',
      CardRank.six => 'Six',
      CardRank.seven => 'Seven',
      CardRank.eight => 'Eight',
      CardRank.nine => 'Nine',
      CardRank.ten => 'Ten',
      CardRank.jack => 'Jack',
      CardRank.queen => 'Queen',
      CardRank.king => 'King',
    };
  }

  static String _suitWord(CardSuit suit) {
    return switch (suit) {
      CardSuit.spades => 'Spades',
      CardSuit.hearts => 'Hearts',
      CardSuit.diamonds => 'Diamonds',
      CardSuit.clubs => 'Clubs',
    };
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
