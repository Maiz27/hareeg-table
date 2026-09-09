import 'package:flutter/material.dart';

import '../../../../l10n/app_strings.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../replay_hud_layout.dart';
import 'replay_hud_clusters.dart';

/// The progress hairline: 3 dp, full width, and completely inert.
///
/// It absorbs nothing, so it may span the South hand without stealing a touch
/// from it. The touchable part of seeking is [ReplayScrubTarget], which the
/// collision map places somewhere it covers nothing at all.
class ReplayProgressHairline extends StatelessWidget {
  /// Creates the hairline.
  const ReplayProgressHairline({required this.progress, super.key});

  /// Fraction of the match reviewed, 0..1.
  final double progress;

  static const double height = 3;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          backgroundColor: LoungeTokens.sandLine.withValues(alpha: 0.18),
          color: LoungeTokens.sandLine,
          minHeight: height,
        ),
      ),
    );
  }
}

/// The one interactive seek affordance.
///
/// A single 44 x 44 target rather than a run along the bottom edge: eligibility
/// now subtracts every protected rendered rectangle, not just the South hand's
/// span, and exactly one segment survives that at each approved short size. A
/// size where none survives is classified docked, so this never renders in a
/// place it would cover something.
class ReplayScrubTarget extends StatelessWidget {
  /// Creates the scrub target.
  const ReplayScrubTarget({
    required this.label,
    required this.onTap,
    super.key,
  });

  /// Localized tooltip and semantics label, carrying the full position value.
  final String label;

  /// Opens the expanded scrubber.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ReplayHudLayout.minTapTarget,
      height: ReplayHudLayout.minTapTarget,
      child: Semantics(
        label: label,
        button: true,
        // Always available, and it has to say so. `onTap` is required here, so
        // unlike the eight rail actions this control has no disabled state —
        // but a node that declares no enabled state at all reports
        // `isEnabled: false`, which is not what a screen reader should hear
        // about the one control that never goes away.
        enabled: true,
        child: Tooltip(
          message: label,
          // Same discipline as the rail: the 44 dp target is transparent and
          // fully hit-testable, and only the inner box is painted. That is what
          // puts visible air between Last and the scrub without moving either
          // accepted rectangle.
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              // Opaque only within its own rect: the target absorbs the taps it
              // is given and nothing else.
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Center(
                child: IgnorePointer(
                  child: Container(
                    width: ReplayRailButton.chromeExtent,
                    height: ReplayRailButton.chromeExtent,
                    decoration: BoxDecoration(
                      color: LoungeTokens.coffeeCharcoal.withValues(
                        alpha: 0.94,
                      ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.timeline,
                        size: 22,
                        color: LoungeTokens.sandLine,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The expanded scrubber: the transient presentation of the one seek
/// affordance, never a second permanent one.
///
/// Auto-dismisses when the drag is released, **except** while keyboard or
/// switch focus remains inside it — a focus user would otherwise be thrown out
/// of the control they are still operating. When that focus later leaves, the
/// overlay closes then instead: holding it open for focus and never releasing
/// it would leave the band sitting on the reviewer's hand indefinitely.
///
/// The caller sizes it. It is allowed to cover the rendered South hand while
/// open and nothing else, so the rectangle comes from the collision map rather
/// than from the bottom of the screen.
class ReplayScrubOverlay extends StatefulWidget {
  /// Creates the expanded scrubber.
  const ReplayScrubOverlay({
    required this.cursor,
    required this.length,
    required this.onSeek,
    required this.onDismiss,
    super.key,
  });

  /// Current frame index.
  final int cursor;

  /// Total frames.
  final int length;

  /// Requests a jump to a frame index.
  final ValueChanged<int> onSeek;

  /// Closes the overlay.
  final VoidCallback onDismiss;

  /// The overlay never grows past this.
  static const double maxHeight = 64;

  @override
  State<ReplayScrubOverlay> createState() => _ReplayScrubOverlayState();
}

class _ReplayScrubOverlayState extends State<ReplayScrubOverlay> {
  bool _hasFocus = false;

  void _onFocusChange(bool value) {
    final lost = _hasFocus && !value;
    setState(() => _hasFocus = value);
    // The other half of A29's focus rule, and the half that was missing:
    // focus holds the overlay open while it is being operated, so focus
    // leaving is what ends that hold. Without this the overlay stays up for
    // good once a focus user has touched it.
    if (lost && mounted) {
      widget.onDismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final maxIndex = (widget.length - 1).toDouble();

    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: ReplayScrubOverlay.maxHeight,
      ),
      child: Container(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.94),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Semantics(
          label: strings.replaySeek,
          child: Tooltip(
            message: strings.replaySeek,
            child: Focus(
              onFocusChange: _onFocusChange,
              child: Slider(
                value: widget.cursor.toDouble().clamp(0, maxIndex),
                max: maxIndex <= 0 ? 1 : maxIndex,
                onChanged: (value) => widget.onSeek(value.round()),
                // Releasing the drag puts the table back, unless focus is still
                // parked in here.
                onChangeEnd: (_) {
                  if (!_hasFocus) {
                    widget.onDismiss();
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
