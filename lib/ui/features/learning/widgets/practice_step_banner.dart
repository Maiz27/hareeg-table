import 'package:flutter/material.dart';

import '../../../../l10n/app_strings.dart';
import '../../../core/motion/motion_speed.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Persistent step prompt shown over the table during a practice lesson.
///
/// Borrows the coach overlay's visual shell (slim top-center strip over the
/// north rail, accent border, pointer-transparent) but presents the lesson
/// step instead of an advisor insight. Two columns: the badge column carries
/// the icon with the step counter under it; the text column carries the
/// step's prompt with its guidance line under it. Unlike the coach it stays
/// up through the player's own card flights — the instruction must not blink
/// away while the taught move animates.
class PracticeStepBanner extends StatelessWidget {
  /// Creates a practice step banner.
  const PracticeStepBanner({
    super.key,
    required this.stepIndex,
    required this.stepCount,
    required this.prompt,
    this.hint,
    this.reaction,
    required this.highContrast,
  });

  /// Zero-based index of the active step (drives the entrance animation).
  final int stepIndex;

  /// Total steps in the lesson.
  final int stepCount;

  /// Step instruction.
  final String prompt;

  /// Optional extra guidance under the prompt.
  final String? hint;

  /// Reaction to the player's last move (e.g. "that staged below the
  /// benchmark — the undo pill takes it back"). Takes the guidance line's
  /// slot in the accent hue so the banner visibly answers what just
  /// happened instead of repeating static text.
  final String? reaction;

  /// Whether high-contrast card cues are enabled (strengthens the panel).
  final bool highContrast;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final motion = MotionScope.of(context);
    const accent = LoungeTokens.goldAccent;
    final panelColor = LoungeTokens.coffeeCharcoal.withValues(
      alpha: highContrast ? 0.97 : 0.92,
    );
    final stepLabel = strings.practiceStepLabel(stepIndex + 1, stepCount);
    final guidance = reaction ?? hint;

    final panel = DecoratedBox(
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
        border: Border.all(color: accent.withValues(alpha: 0.55), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LoungeTokens.space4,
          vertical: LoungeTokens.space2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Badge column: icon with the step counter beneath it.
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.school_outlined, size: 20, color: accent),
                const SizedBox(height: 2),
                Text(
                  stepLabel.toUpperCase(),
                  style: const TextStyle(
                    color: accent,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(width: LoungeTokens.space3),
            // Text column: the prompt with its guidance line beneath it.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: LoungeTokens.offWhiteText,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  if (guidance != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      guidance,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: reaction != null
                          ? LoungeTokens.bodyMuted.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w600,
                            )
                          : LoungeTokens.bodyMuted,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // Re-run the entrance whenever the step advances or the banner reacts.
    final animated = TweenAnimationBuilder<double>(
      key: ValueKey('practice-step-anim-$stepIndex-${reaction != null}'),
      tween: Tween(begin: 0, end: 1),
      duration: motion.scale(const Duration(milliseconds: 180)),
      curve: motion.curve(Curves.easeOutCubic),
      builder: (context, t, child) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 8.0),
            child: child,
          ),
        );
      },
      child: Semantics(
        liveRegion: true,
        label: '$stepLabel. $prompt.${guidance == null ? '' : ' $guidance'}',
        child: panel,
      ),
    );

    return Positioned.fill(
      child: IgnorePointer(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxHeight <= 360 || constraints.maxWidth <= 700;
              // Same band the coach callout uses: pinned over the north rail,
              // clear of the discard, meld lanes, and the player's hand, with
              // side insets that clear the corner chrome buttons.
              return Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: compact ? 54 : 66,
                    right: compact ? 54 : 66,
                    top: compact ? 4 : 8,
                  ),
                  child: SizedBox(width: double.infinity, child: animated),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
