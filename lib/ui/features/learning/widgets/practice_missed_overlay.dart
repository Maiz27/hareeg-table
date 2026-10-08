import 'package:flutter/material.dart';

import '../../../../l10n/app_strings.dart';
import '../../../core/panels/lounge_medallion.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Full-table overlay shown when a practice lesson dead-ends — the taught
/// move left the rules surface for good (a Fifty window expired before the
/// claim), so the only honest way forward is a fresh board.
///
/// Mirrors the completion overlay's shell so both lesson endings speak the
/// same visual language; the icon and the step's dead-end note carry the
/// "too late" framing. Rendered by the game table's overlay stack in
/// practice mode.
class PracticeMissedOverlay extends StatelessWidget {
  /// Creates the missed-lesson overlay.
  const PracticeMissedOverlay({
    super.key,
    required this.note,
    required this.onRestart,
    required this.onDone,
  });

  /// The step's dead-end explanation (what closed and why restarting helps).
  final String note;

  /// Restarts the lesson on a fresh board.
  final VoidCallback onRestart;

  /// Returns to the practice hub.
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Container(
      key: const ValueKey('practice-missed-overlay'),
      color: Colors.black.withValues(alpha: 0.62),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          margin: const EdgeInsets.all(LoungeTokens.space5),
          padding: const EdgeInsets.all(LoungeTokens.space5),
          decoration: loungeLitPanel(
            glow: LoungeTokens.invalidAction,
            strength: 0.1,
          ),
          // Scrollable so the panel never overflows a short landscape
          // viewport.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: LoungeMedallion(
                    icon: Icons.timer_off_outlined,
                    size: 56,
                    tone: LoungeMedallionTone.alert,
                  ),
                ),
                const SizedBox(height: LoungeTokens.space3),
                Text(
                  note,
                  textAlign: TextAlign.center,
                  style: LoungeTokens.bodyMuted,
                ),
                const SizedBox(height: LoungeTokens.space5),
                FilledButton.icon(
                  onPressed: onRestart,
                  icon: const Icon(Icons.replay_outlined),
                  label: Text(strings.practiceRestartLesson),
                ),
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
      ),
    );
  }
}
