import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/replay/replay_review_state.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../replay_card_layout.dart';

/// Renders a timeline glyph pointing the way the timeline runs.
///
/// Material opts several transport glyphs into `matchTextDirection`, so under
/// Arabic `first_page`, `last_page`, `chevron_left` and `chevron_right` would
/// flip while `skip_previous` and `skip_next` do not, and Next would point
/// backwards beside a Previous round that points the right way. The timeline
/// runs one way whichever way the language reads, so its arrows are pinned
/// left-to-right — and so is the row and the scrubber they sit beside.
class ReplayTimelineGlyph extends StatelessWidget {
  /// Creates a timeline glyph.
  const ReplayTimelineGlyph({required this.icon, this.color, super.key});

  /// The glyph.
  final IconData icon;

  /// Glyph colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Icon(icon, size: 22, color: color),
    );
  }
}

/// One transport control: a 44 dp target with round chrome painted inside it.
///
/// Icon-only, which makes the tooltip and the semantics label load-bearing:
/// without them the row is unreadable to a screen reader. [emphasized] marks
/// the single-step pair, the moves a reviewer makes most — ringed and lit
/// gold — while round and end jumps stay quiet sand outlines.
class ReplayTransportButton extends StatelessWidget {
  /// Creates a transport control.
  const ReplayTransportButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.emphasized = false,
    super.key,
  });

  /// The glyph.
  final IconData icon;

  /// Localized tooltip and semantics label.
  final String label;

  /// Null disables the action; it stays visible either way.
  final VoidCallback? onPressed;

  /// Lights the control gold.
  final bool emphasized;

  /// Side of the painted chrome: the target less the inset either side.
  static const double chromeExtent =
      ReplayCardMetrics.tapTarget - ReplayCardMetrics.chromeInset * 2;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final glyphColor = !enabled
        ? LoungeTokens.sandLine.withValues(alpha: 0.3)
        : emphasized
        ? LoungeTokens.goldAccent
        : LoungeTokens.sandLine;
    return SizedBox.square(
      dimension: ReplayCardMetrics.tapTarget,
      child: Tooltip(
        message: label,
        // `Tooltip` publishes its message as a semantics *tooltip*, and an
        // icon-only button publishes a node with no label at all — so the
        // label is merged onto the button's own node, one announcement.
        excludeFromSemantics: true,
        child: MergeSemantics(
          child: Semantics(
            label: label,
            button: true,
            enabled: enabled,
            // Transparent, and the full 44 dp: the ink and the hit test cover
            // the whole target while only the inner circle is painted.
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onPressed,
                customBorder: const CircleBorder(),
                child: Center(
                  child: Container(
                    width: chromeExtent,
                    height: chromeExtent,
                    decoration: _chrome(enabled: enabled),
                    child: Center(
                      child: ReplayTimelineGlyph(icon: icon, color: glyphColor),
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

  BoxDecoration _chrome({required bool enabled}) {
    if (!emphasized) {
      // Secondary: an outline only, so the step pair carries the weight.
      return BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: enabled ? 0.22 : 0.1),
        ),
      );
    }
    return BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(
            LoungeTokens.coffeeCharcoal,
            LoungeTokens.goldAccent,
            enabled ? 0.2 : 0.06,
          )!,
          LoungeTokens.coffeeCharcoal,
        ],
      ),
      border: Border.all(
        color: enabled
            ? LoungeTokens.goldAccent.withValues(alpha: 0.65)
            : LoungeTokens.sandLine.withValues(alpha: 0.14),
      ),
      boxShadow: enabled ? LoungeTokens.elevationL2 : null,
    );
  }
}

/// The six transport actions, in timeline order.
///
/// One list rather than six call sites, so every arrangement of the card
/// offers the same actions with the same labels and the same emphasis.
List<ReplayTransportButton> replayTransportButtons({
  required AppStrings strings,
  required ReplayReviewState review,
  required ValueChanged<int> onSeek,
}) {
  return [
    ReplayTransportButton(
      icon: Icons.first_page,
      label: strings.replayFirst,
      onPressed: review.canStepBack ? () => onSeek(0) : null,
    ),
    ReplayTransportButton(
      icon: Icons.skip_previous,
      label: strings.replayPreviousRound,
      onPressed: review.canGoPreviousRound
          ? () => onSeek(review.previousRound().cursor)
          : null,
    ),
    ReplayTransportButton(
      icon: Icons.chevron_left,
      label: strings.replayPrevious,
      emphasized: true,
      onPressed: review.canStepBack ? () => onSeek(review.cursor - 1) : null,
    ),
    ReplayTransportButton(
      icon: Icons.chevron_right,
      label: strings.replayNext,
      emphasized: true,
      onPressed: review.canStepForward ? () => onSeek(review.cursor + 1) : null,
    ),
    ReplayTransportButton(
      icon: Icons.skip_next,
      label: strings.replayNextRound,
      onPressed: review.canGoNextRound
          ? () => onSeek(review.nextRound().cursor)
          : null,
    ),
    ReplayTransportButton(
      icon: Icons.last_page,
      label: strings.replayLast,
      onPressed: review.canStepForward ? () => onSeek(review.length - 1) : null,
    ),
  ];
}

/// The timeline scrubber: the one continuous seek affordance.
///
/// Laid out left to right in both languages, like the transport glyphs.
class ReplayScrubber extends StatelessWidget {
  /// Creates the scrubber.
  const ReplayScrubber({required this.review, required this.onSeek, super.key});

  /// Current review position.
  final ReplayReviewState review;

  /// Requests a jump to a frame index.
  final ValueChanged<int> onSeek;

  @override
  Widget build(BuildContext context) {
    final maxIndex = (review.length - 1).toDouble();
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Semantics(
        label: context.strings.replaySeek,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            activeTrackColor: LoungeTokens.goldAccent,
            inactiveTrackColor: LoungeTokens.sandLine.withValues(alpha: 0.22),
            thumbColor: LoungeTokens.goldAccent,
            overlayColor: LoungeTokens.goldAccent.withValues(alpha: 0.14),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            value: review.cursor.toDouble().clamp(0, maxIndex),
            max: maxIndex <= 0 ? 1 : maxIndex,
            onChanged: (value) => onSeek(value.round()),
          ),
        ),
      ),
    );
  }
}
