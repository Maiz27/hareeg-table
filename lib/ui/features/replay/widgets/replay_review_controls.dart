import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/replay/replay_review_state.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Transport controls for stepping through a reconstructed match.
///
/// Compact by design: the table underneath is the thing being reviewed, so the
/// controls sit in one low strip rather than competing with it.
///
/// Every button is icon-only for space, which makes the semantic labels
/// load-bearing rather than decorative — without them the whole strip is
/// unreadable to a screen reader.
class ReplayReviewControls extends StatelessWidget {
  /// Creates the control strip.
  const ReplayReviewControls({
    required this.review,
    required this.positionLabel,
    required this.frameDescription,
    required this.onSeek,
    super.key,
  });

  /// Current review position.
  final ReplayReviewState review;

  /// Localized "Round 3 · 214 of 1721" line.
  final String positionLabel;

  /// Localized description of the current frame.
  final String frameDescription;

  /// Requests a jump to a frame index.
  final ValueChanged<int> onSeek;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final maxIndex = (review.length - 1).toDouble();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.92),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            positionLabel,
            style: LoungeTokens.bodyMuted,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            frameDescription,
            style: LoungeTokens.body,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Semantics(
            label: strings.replaySeek,
            child: Slider(
              value: review.cursor.toDouble().clamp(0, maxIndex),
              max: maxIndex <= 0 ? 1 : maxIndex,
              onChanged: (value) => onSeek(value.round()),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ControlButton(
                icon: Icons.first_page,
                label: strings.replayFirst,
                onPressed: review.canStepBack ? () => onSeek(0) : null,
              ),
              _ControlButton(
                icon: Icons.skip_previous,
                label: strings.replayPreviousRound,
                onPressed: review.canGoPreviousRound
                    ? () => onSeek(review.previousRound().cursor)
                    : null,
              ),
              _ControlButton(
                icon: Icons.chevron_left,
                label: strings.replayPrevious,
                onPressed: review.canStepBack
                    ? () => onSeek(review.cursor - 1)
                    : null,
              ),
              _ControlButton(
                icon: Icons.chevron_right,
                label: strings.replayNext,
                onPressed: review.canStepForward
                    ? () => onSeek(review.cursor + 1)
                    : null,
              ),
              _ControlButton(
                icon: Icons.skip_next,
                label: strings.replayNextRound,
                onPressed: review.canGoNextRound
                    ? () => onSeek(review.nextRound().cursor)
                    : null,
              ),
              _ControlButton(
                icon: Icons.last_page,
                label: strings.replayLast,
                onPressed: review.canStepForward
                    ? () => onSeek(review.length - 1)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: IconButton(
        icon: Icon(icon),
        color: LoungeTokens.sandLine,
        // Named for a screen reader, and given the same minimum touch area the
        // rest of the app uses.
        tooltip: null,
        onPressed: onPressed,
        constraints: const BoxConstraints(
          minWidth: LoungeTokens.tapTargetCardShort,
          minHeight: LoungeTokens.tapTargetCardShort,
        ),
        padding: EdgeInsets.zero,
        iconSize: 22,
      ),
    );
  }
}
