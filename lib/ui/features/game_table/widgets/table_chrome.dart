import 'package:flutter/material.dart';

import '../../../../l10n/app_strings.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Top chrome bar: leave-table, current turn prompt, score + pause icons.
class TableChromeBar extends StatelessWidget {
  /// Creates the chrome bar.
  const TableChromeBar({
    super.key,
    required this.turnPrompt,
    required this.openingRequirement,
    required this.onLeave,
    required this.onOpenScores,
    required this.onOpenPause,
  });

  /// Sentence describing whose turn it is and what to do.
  final String turnPrompt;

  /// Active opening benchmark — rendered as a small chip on the right.
  final int openingRequirement;

  /// Tap-back / leave-table handler.
  final VoidCallback onLeave;

  /// Opens the in-game score overlay.
  final VoidCallback onOpenScores;

  /// Opens the pause overlay.
  final VoidCallback onOpenPause;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: LoungeTokens.space3),
        child: Row(
          children: [
            IconButton(
              tooltip: strings.leaveTable,
              onPressed: onLeave,
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: LoungeTokens.space2),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  turnPrompt,
                  key: ValueKey(turnPrompt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LoungeTokens.titleSmall,
                ),
              ),
            ),
            _OpeningBadge(value: openingRequirement),
            const SizedBox(width: LoungeTokens.space2),
            IconButton(
              tooltip: strings.scores,
              onPressed: onOpenScores,
              icon: const Icon(Icons.bar_chart_outlined),
            ),
            IconButton(
              tooltip: strings.pauseTable,
              onPressed: onOpenPause,
              icon: const Icon(Icons.pause_circle_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpeningBadge extends StatelessWidget {
  const _OpeningBadge({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LoungeTokens.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: LoungeTokens.feltRaised,
        borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
        border: Border.all(color: LoungeTokens.sandLine.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.flag_outlined,
            size: 14,
            color: LoungeTokens.goldAccent,
          ),
          const SizedBox(width: 4),
          Text('$value', style: LoungeTokens.numericChip),
        ],
      ),
    );
  }
}
