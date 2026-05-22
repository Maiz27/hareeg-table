import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../l10n/app_strings.dart';
import '../motion/motion_speed.dart';
import '../scopes/app_scopes.dart';
import 'card_theme.dart';
import 'card_view.dart';

/// Choreography mode for [ShowcaseCardFan].
///
/// The fan resolves [ShowcaseFanMotion.none] when [MotionScope] reports
/// `reduced`, so callers can opt into motion without re-checking that flag.
enum ShowcaseFanMotion {
  /// Static rest pose. Identical to the pre-motion-seam behaviour.
  none,

  /// One-shot reveal: cards unfurl outward from the centre and settle.
  intro,

  /// Looping micro-motion: small angle / lift sway on the outer cards.
  idle,
}

/// Small fanned showcase hand used by the splash and main menu.
///
/// Geometry of the rest pose is fixed: five cards in a stable paint order,
/// each rotated and translated relative to the midpoint. Motion is applied as
/// an *additional* transform layered on top of the rest pose, so the static
/// layout that other surfaces depend on never drifts.
class ShowcaseCardFan extends StatefulWidget {
  /// Creates a themed showcase card fan.
  const ShowcaseCardFan({
    super.key,
    required this.width,
    required this.height,
    this.maxAngle = 0.52,
    this.stepSpread = 22,
    this.outerDrop = 10,
    this.motion = ShowcaseFanMotion.none,
  });

  /// Fan bounds.
  final double width;
  final double height;

  /// Half-angle of the outermost card from vertical, in radians.
  final double maxAngle;

  /// Horizontal offset between adjacent card pivots.
  final double stepSpread;

  /// Vertical drop applied to the outer cards so inner cards remain visible.
  final double outerDrop;

  /// Choreography applied on top of the rest pose.
  final ShowcaseFanMotion motion;

  /// Test bypass: when true, [ShowcaseFanMotion.idle] is treated as
  /// [ShowcaseFanMotion.none] so `pumpAndSettle` doesn't hang on the home
  /// screen's looping animation.
  ///
  /// Production code never touches this; tests using [HareegTableApp] flip it
  /// to true in their `main()`.
  @visibleForTesting
  static bool disableLoopingMotionForTesting = false;

  @override
  State<ShowcaseCardFan> createState() => _ShowcaseCardFanState();
}

class _ShowcaseCardFanState extends State<ShowcaseCardFan>
    with SingleTickerProviderStateMixin {
  static const _introBaseDuration = Duration(milliseconds: 760);
  static const _idleBaseDuration = Duration(milliseconds: 4800);

  AnimationController? _controller;
  ShowcaseFanMotion _activeMotion = ShowcaseFanMotion.none;

  static final List<HareegCard> _showcase = [
    HareegCard.standard(
      rank: CardRank.king,
      suit: CardSuit.spades,
      deckIndex: 0,
    ),
    HareegCard.standard(
      rank: CardRank.queen,
      suit: CardSuit.hearts,
      deckIndex: 0,
    ),
    const HareegCard.joker(deckIndex: 0, jokerIndex: 0),
    HareegCard.standard(
      rank: CardRank.jack,
      suit: CardSuit.diamonds,
      deckIndex: 0,
    ),
    HareegCard.standard(rank: CardRank.ace, suit: CardSuit.clubs, deckIndex: 0),
  ];

  static const _paintOrder = [0, 4, 1, 3, 2];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant ShowcaseCardFan oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.motion != widget.motion) {
      _syncMotion();
    }
  }

  void _syncMotion() {
    final motionSettings = MotionScope.of(context);
    var resolved = motionSettings.reduced
        ? ShowcaseFanMotion.none
        : widget.motion;
    if (resolved == ShowcaseFanMotion.idle &&
        ShowcaseCardFan.disableLoopingMotionForTesting) {
      resolved = ShowcaseFanMotion.none;
    }
    final base = _baseDurationFor(resolved);
    if (resolved == _activeMotion) {
      // Motion mode unchanged but the ambient [MotionScope] speed may have
      // shifted (e.g. user toggled Fast / Reduced from Settings). Keep the
      // existing controller running but refresh its duration so the loop
      // tracks the new scaled base.
      if (base != null && _controller != null) {
        _controller!.duration = motionSettings.scale(base);
      }
      return;
    }
    _activeMotion = resolved;
    _controller?.stop();
    _controller?.dispose();
    _controller = null;
    if (base == null) {
      return;
    }
    final controller = AnimationController(
      vsync: this,
      duration: motionSettings.scale(base),
    );
    _controller = controller;
    if (resolved == ShowcaseFanMotion.intro) {
      controller.forward(from: 0);
    } else {
      controller.repeat();
    }
  }

  Duration? _baseDurationFor(ShowcaseFanMotion motion) {
    switch (motion) {
      case ShowcaseFanMotion.intro:
        return _introBaseDuration;
      case ShowcaseFanMotion.idle:
        return _idleBaseDuration;
      case ShowcaseFanMotion.none:
        return null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = CardThemeScope.of(context);
    final strings = context.strings;
    final cardSize = Size(widget.width * 0.31, widget.height * 0.8);
    final midpoint = (_showcase.length - 1) / 2;

    return Semantics(
      label: strings.cardThemePreview(theme.label),
      excludeSemantics: true,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: _activeMotion == ShowcaseFanMotion.none || _controller == null
            ? _buildFan(theme, cardSize, midpoint, phase: 1.0)
            : AnimatedBuilder(
                animation: _controller!,
                builder: (context, _) => _buildFan(
                  theme,
                  cardSize,
                  midpoint,
                  phase: _controller!.value,
                ),
              ),
      ),
    );
  }

  Widget _buildFan(
    HareegCardTheme theme,
    Size cardSize,
    double midpoint, {
    required double phase,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        for (final index in _paintOrder)
          _FannedCardSlot(
            card: _showcase[index],
            theme: theme,
            size: cardSize,
            offsetFromCenter: index - midpoint,
            midpoint: midpoint,
            maxAngle: widget.maxAngle,
            stepSpread: widget.stepSpread,
            outerDrop: widget.outerDrop,
            motion: _slotMotion(index, phase),
          ),
      ],
    );
  }

  _SlotMotion _slotMotion(int cardIndex, double phase) {
    switch (_activeMotion) {
      case ShowcaseFanMotion.none:
        return _SlotMotion.rest;
      case ShowcaseFanMotion.intro:
        return _introMotion(cardIndex, phase);
      case ShowcaseFanMotion.idle:
        return _idleMotion(cardIndex, phase);
    }
  }

  _SlotMotion _introMotion(int cardIndex, double phase) {
    // Centre card unfurls first, then inner pair, then outer pair. Each card
    // gets a slightly overlapping span of the global phase so the fan opens
    // like a hand rather than five separate animations.
    final distFromCentre = (cardIndex - 2).abs(); // 0, 1, or 2
    // Picked so the outermost cards' local progress still reaches 1.0 when
    // the global phase hits 1.0 (otherwise the intro never resolves to the
    // exact rest pose). Max start = 0.20, span = 0.80, sum = 1.0.
    final start = distFromCentre * 0.10;
    const span = 0.80;
    final local = ((phase - start) / span).clamp(0.0, 1.0);
    // Translation easing — easeOutBack overshoots ~3% past the rest pose
    // then settles, giving the spread a confident "snap" at the end.
    final translateEase = Curves.easeOutBack.transform(local);
    // Opacity / vertical entry follow a clean easeOutCubic; we don't want
    // the cards fading in and out as the overshoot bounces.
    final positionEase = Curves.easeOutCubic.transform(local);
    final positionInverse = 1 - positionEase;
    return _SlotMotion(
      // Cards rise from below the rest pose. Outer cards travel slightly
      // further so they "sweep" up into place rather than slot straight in.
      extraDy: positionInverse *
          (widget.height * (0.34 + distFromCentre * 0.04)),
      // Hand tilts more dramatically while flying, settling at rest angle.
      extraAngle:
          positionInverse * 0.12 * (cardIndex < 2 ? 1 : -1),
      // Translation scale uses easeOutBack — outer cards briefly fan WIDER
      // than rest then settle. Centre card barely moves (overshoot is tiny).
      translateScale: 0.55 + 0.45 * translateEase,
      opacity: positionEase,
    );
  }

  _SlotMotion _idleMotion(int cardIndex, double phase) {
    // Two-wave breathing motion. The primary wave drives the lift/angle; the
    // smaller secondary wave at double frequency keeps it from feeling like
    // a metronome. Outer cards lead the inner ones via the per-index phase
    // offset and get more amplitude — the centre card sits almost still,
    // which reads as a hand subtly settling.
    final primary = math.sin(phase * 2 * math.pi + cardIndex * 0.7);
    final secondary = math.sin(phase * 4 * math.pi + cardIndex * 0.4);
    final wave = primary + secondary * 0.22;
    final outerness = ((cardIndex - 2).abs() / 2).toDouble(); // 0..1
    return _SlotMotion(
      extraDy: wave * 1.4 * (0.25 + outerness * 1.0),
      extraAngle: wave * 0.014 * (0.35 + outerness),
      // Faint breath in the fan spread — outer cards drift ±0.8% in/out.
      translateScale: 1.0 + primary * 0.008 * (0.4 + outerness * 0.7),
      opacity: 1.0,
    );
  }
}

@immutable
class _SlotMotion {
  const _SlotMotion({
    required this.extraDy,
    required this.extraAngle,
    required this.translateScale,
    required this.opacity,
  });

  static const rest = _SlotMotion(
    extraDy: 0,
    extraAngle: 0,
    translateScale: 1,
    opacity: 1,
  );

  final double extraDy;
  final double extraAngle;
  final double translateScale;
  final double opacity;
}

class _FannedCardSlot extends StatelessWidget {
  const _FannedCardSlot({
    required this.card,
    required this.theme,
    required this.size,
    required this.offsetFromCenter,
    required this.midpoint,
    required this.maxAngle,
    required this.stepSpread,
    required this.outerDrop,
    this.motion = _SlotMotion.rest,
  });

  final HareegCard card;
  final HareegCardTheme theme;
  final Size size;
  final double offsetFromCenter;
  final double midpoint;
  final double maxAngle;
  final double stepSpread;
  final double outerDrop;
  final _SlotMotion motion;

  @override
  Widget build(BuildContext context) {
    final normalized = offsetFromCenter / midpoint;
    final restDx = offsetFromCenter * stepSpread;
    final restDy = normalized.abs() * outerDrop;
    final restAngle = normalized * maxAngle;
    final slot = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            offset: Offset(0, 2),
            blurRadius: 3,
          ),
        ],
      ),
      child: HareegCardView(
        theme: theme,
        card: card,
        variant: CardVariant.picker,
        size: size,
        jokerDisplay: JokerDisplay.assisted,
      ),
    );
    return Transform.translate(
      offset: Offset(
        restDx * motion.translateScale,
        restDy + motion.extraDy,
      ),
      child: Transform.rotate(
        angle: restAngle + motion.extraAngle,
        alignment: Alignment.bottomCenter,
        child: motion.opacity == 1.0
            ? slot
            : Opacity(opacity: motion.opacity.clamp(0.0, 1.0), child: slot),
      ),
    );
  }
}
