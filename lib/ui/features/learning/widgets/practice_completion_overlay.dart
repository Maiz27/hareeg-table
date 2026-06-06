import 'package:flutter/material.dart';

import '../../../../l10n/app_strings.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Full-table overlay shown when the final practice step is demonstrated.
///
/// Offers the pack's next lesson when one is available (so a learner can run
/// a whole pack back to back), a replay on a fresh board, and the way back
/// to the practice hub. Rendered by the game table's overlay stack in
/// practice mode; match overlays (round result, score) never show during a
/// lesson.
class PracticeCompletionOverlay extends StatelessWidget {
  /// Creates the completion overlay.
  const PracticeCompletionOverlay({
    super.key,
    required this.onReplay,
    this.onNext,
    required this.onDone,
  });

  /// Restarts the lesson on a fresh board.
  final VoidCallback onReplay;

  /// Continues straight into the pack's next lesson; null at a pack boundary
  /// (finishing a pack is a deliberate stopping point) or while the next
  /// lesson's script has not shipped.
  final VoidCallback? onNext;

  /// Returns to the practice hub.
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Container(
      key: const ValueKey('practice-completion-overlay'),
      color: Colors.black.withValues(alpha: 0.62),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          margin: const EdgeInsets.all(LoungeTokens.space5),
          padding: const EdgeInsets.all(LoungeTokens.space5),
          decoration: BoxDecoration(
            color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
            border: Border.all(
              color: LoungeTokens.goldAccent.withValues(alpha: 0.5),
              width: 1.2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.check_circle_outline,
                size: 40,
                color: LoungeTokens.goldAccent,
              ),
              const SizedBox(height: LoungeTokens.space3),
              Text(
                strings.practiceLessonCompleteTitle,
                textAlign: TextAlign.center,
                style: LoungeTokens.heading,
              ),
              const SizedBox(height: LoungeTokens.space2),
              Text(
                strings.practiceLessonCompleteBody,
                textAlign: TextAlign.center,
                style: LoungeTokens.bodyMuted,
              ),
              const SizedBox(height: LoungeTokens.space5),
              if (onNext != null) ...[
                FilledButton.icon(
                  onPressed: onNext,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(strings.practiceNextLesson),
                ),
                const SizedBox(height: LoungeTokens.space3),
                OutlinedButton.icon(
                  onPressed: onReplay,
                  icon: const Icon(Icons.replay_outlined, size: 18),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: LoungeTokens.goldAccent,
                    side: BorderSide(
                      color: LoungeTokens.goldAccent.withValues(alpha: 0.6),
                    ),
                  ),
                  label: Text(strings.practiceReplayLesson),
                ),
              ] else ...[
                FilledButton.icon(
                  onPressed: onReplay,
                  icon: const Icon(Icons.replay_outlined),
                  label: Text(strings.practiceReplayLesson),
                ),
              ],
              const SizedBox(height: LoungeTokens.space3),
              OutlinedButton(
                onPressed: onDone,
                style: OutlinedButton.styleFrom(
                  foregroundColor: LoungeTokens.goldAccent,
                  side: BorderSide(
                    color: LoungeTokens.goldAccent.withValues(alpha: 0.6),
                  ),
                ),
                child: Text(strings.practiceBackToList),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
