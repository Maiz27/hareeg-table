import 'package:flutter/services.dart';

/// Logical haptic events used at the table.
///
/// Mapped to platform [HapticFeedback] calls in [TableHaptics]. Kept enum-led
/// so the call sites read intent rather than impact strength, and a future
/// change to the mapping only happens in one place.
enum TableHapticEvent {
  /// Selecting or deselecting a card.
  cardTap,

  /// Tapping a primary control button (draw, discard, take).
  buttonTap,

  /// Drawing a card from stock.
  drawCard,

  /// Illegal action attempt.
  illegalAction,

  /// Pending discard returned to the pile.
  pendingReturn,

  /// Snap-back from an invalid drop target.
  snapBack,

  /// Successful Fifty claim.
  fiftyClaim,

  /// Round ends (any outcome).
  roundEnd,
}

/// Lightweight wrapper around [HapticFeedback] that respects a runtime
/// enabled toggle. No package dependency required — the Flutter framework
/// already exposes `selectionClick`, `lightImpact`, `mediumImpact`,
/// `heavyImpact`, and `vibrate`.
class TableHaptics {
  /// Creates a haptics gateway with the toggle initially enabled.
  TableHaptics({this.enabled = true});

  /// Current toggle state. Set directly to update.
  bool enabled;

  /// Fires the platform haptic mapped to [event] when enabled.
  Future<void> fire(TableHapticEvent event) {
    if (!enabled) {
      return Future<void>.value();
    }
    return switch (event) {
      TableHapticEvent.cardTap => HapticFeedback.selectionClick(),
      TableHapticEvent.buttonTap => HapticFeedback.lightImpact(),
      TableHapticEvent.drawCard => HapticFeedback.lightImpact(),
      TableHapticEvent.illegalAction => HapticFeedback.mediumImpact(),
      TableHapticEvent.pendingReturn => HapticFeedback.mediumImpact(),
      TableHapticEvent.snapBack => HapticFeedback.mediumImpact(),
      TableHapticEvent.fiftyClaim => HapticFeedback.heavyImpact(),
      TableHapticEvent.roundEnd => HapticFeedback.vibrate(),
    };
  }
}
