import 'package:flutter/material.dart';

/// Player-selectable motion speed used for table animations.
///
/// `normal` runs at the durations listed in `docs/design/direction.md`.
/// `fast` multiplies durations by 0.6. `reduced` drops to 0.35 and replaces
/// easing curves with a linear ramp to honour vestibular-sensitivity needs.
enum MotionSpeed {
  /// Default speed.
  normal('Normal', 1.0),

  /// Quick-but-still-animated speed.
  fast('Fast', 0.6),

  /// Reduced motion: very short tweens, linear curves, no idle pulses.
  reduced('Reduced', 0.35);

  const MotionSpeed(this.label, this.multiplier);

  /// Settings label.
  final String label;

  /// Duration multiplier vs. the design-doc normal value.
  final double multiplier;

  /// Restores the enum from its persisted name.
  static MotionSpeed fromName(String? name) {
    for (final value in MotionSpeed.values) {
      if (value.name == name) {
        return value;
      }
    }
    return MotionSpeed.normal;
  }
}

/// Resolved motion settings shared down the widget tree.
///
/// Created by [MotionScope] so widgets can query a single [Duration] without
/// re-deriving the multiplier on every frame. The [reduced] flag is true when
/// either the user picked [MotionSpeed.reduced] or the OS reported
/// `MediaQuery.disableAnimations` (per WCAG `prefers-reduced-motion`).
@immutable
class MotionSettings {
  /// Creates resolved motion settings.
  const MotionSettings({required this.speed, required this.osReducedMotion});

  /// User-selected speed.
  final MotionSpeed speed;

  /// True when the platform reports `MediaQuery.disableAnimations`.
  final bool osReducedMotion;

  /// Effective speed once OS reduced-motion is applied.
  MotionSpeed get effectiveSpeed =>
      osReducedMotion ? MotionSpeed.reduced : speed;

  /// Convenience flag.
  bool get reduced => effectiveSpeed == MotionSpeed.reduced;

  /// Scales a base duration by the effective multiplier.
  Duration scale(Duration base) {
    final ms = (base.inMilliseconds * effectiveSpeed.multiplier).round();
    return Duration(milliseconds: ms);
  }

  /// Returns the curve to use for a given base curve, swapping to linear in
  /// reduced mode so easing does not introduce additional movement.
  Curve curve(Curve base) => reduced ? Curves.linear : base;

  @override
  bool operator ==(Object other) {
    return other is MotionSettings &&
        other.speed == speed &&
        other.osReducedMotion == osReducedMotion;
  }

  @override
  int get hashCode => Object.hash(speed, osReducedMotion);
}

/// Inherited motion scope.
///
/// Wrap the app shell once with [MotionScope] and any descendant widget can
/// call `MotionScope.of(context)` to scale durations and choose curves
/// without holding a reference to the preferences repository.
class MotionScope extends InheritedWidget {
  /// Creates a motion scope.
  const MotionScope({super.key, required this.settings, required super.child});

  /// Resolved settings exposed to descendants.
  final MotionSettings settings;

  /// Reads the nearest [MotionSettings] (falls back to normal speed +
  /// OS-aware reduced flag pulled from the ambient [MediaQuery]).
  static MotionSettings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MotionScope>();
    if (scope != null) {
      return scope.settings;
    }
    final disable = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return MotionSettings(speed: MotionSpeed.normal, osReducedMotion: disable);
  }

  @override
  bool updateShouldNotify(covariant MotionScope oldWidget) {
    return oldWidget.settings != settings;
  }
}

/// Canonical animation durations used across the table.
///
/// All values are the `Normal` speed from `docs/design/direction.md`. Call
/// `MotionSettings.scale(...)` (via [MotionScope.of]) to apply the speed
/// multiplier where the animation actually runs.
abstract final class TableMotion {
  /// Deal one card.
  static const dealCard = Duration(milliseconds: 220);

  /// Draw from stock.
  static const drawStock = Duration(milliseconds: 180);

  /// Take a discard.
  static const takeDiscard = Duration(milliseconds: 200);

  /// Discard a card.
  static const discardCard = Duration(milliseconds: 200);

  /// Place a meld (per-card stagger handled separately).
  static const meldPlacement = Duration(milliseconds: 240);

  /// Per-card stagger when placing a meld.
  static const meldStagger = Duration(milliseconds: 40);

  /// Place a cover.
  static const coverPlacement = Duration(milliseconds: 200);

  /// Joker replacement two-card swap.
  static const jokerReplacement = Duration(milliseconds: 260);

  /// Pending discard returning to the pile.
  static const pendingReturn = Duration(milliseconds: 180);

  /// CPU read-pause before any action becomes visible.
  static const cpuReadPause = Duration(milliseconds: 320);

  /// CPU move tween duration.
  static const cpuMove = Duration(milliseconds: 120);

  /// CPU card-flight duration in normal turn pacing.
  static const cpuFlight = Duration(milliseconds: 200);

  /// Fast CPU read-pause before each visible action.
  static const fastCpuReadPause = Duration(milliseconds: 100);

  /// Fast CPU pause between visible actions.
  static const fastCpuActionGap = Duration(milliseconds: 140);

  /// Fast CPU card-flight duration.
  static const fastCpuFlight = Duration(milliseconds: 160);

  /// Fifty heat pulse on claim.
  static const fiftyHeatPulse = Duration(milliseconds: 1400);

  /// State-change tween used for card selection / hover overlays.
  static const cardStateTween = Duration(milliseconds: 140);

  /// Splash dwell time before crossfading to the home screen.
  static const splashDwell = Duration(milliseconds: 1200);

  /// Overlay (score / pause) open / close.
  static const overlay = Duration(milliseconds: 220);
}
