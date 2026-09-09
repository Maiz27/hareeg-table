import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/history/match_history_outcomes.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Placeholder shown when a history-backed surface has nothing to show.
///
/// Deliberately separate from [HistoryFailurePanel]: an empty history and an
/// unreadable one are different facts, and telling a player "no saved matches
/// yet" when the index could not be read reads as "your matches are gone".
class HistoryEmptyPanel extends StatelessWidget {
  /// Creates an empty-state panel.
  const HistoryEmptyPanel({
    required this.title,
    required this.body,
    this.icon = Icons.inbox_outlined,
    super.key,
  });

  /// Headline copy.
  final String title;

  /// Explanatory copy.
  final String body;

  /// Leading glyph.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _CenteredPanel(
      icon: icon,
      iconColor: LoungeTokens.mutedText,
      title: title,
      body: body,
    );
  }
}

/// Panel shown when a history operation failed.
///
/// The failure kind decides both the copy and whether a retry is offered.
/// Retrying a [MatchHistoryFailureKind.corrupt] read returns the same bad
/// bytes, so offering one would be a promise the app cannot keep.
class HistoryFailurePanel extends StatelessWidget {
  /// Creates a failure panel.
  const HistoryFailurePanel({
    required this.failure,
    required this.onRetry,
    super.key,
  });

  /// The typed failure, kind included.
  final MatchHistoryFailure failure;

  /// Invoked when the player asks to retry. Only reachable for a retryable
  /// failure.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final retryable = failure.kind == MatchHistoryFailureKind.retryable;

    return _CenteredPanel(
      icon: retryable ? Icons.cloud_off_outlined : Icons.broken_image_outlined,
      iconColor: LoungeTokens.goldAccent,
      title: retryable
          ? strings.historyLoadFailedRetryableTitle
          : strings.historyLoadFailedCorruptTitle,
      body: retryable
          ? strings.historyLoadFailedRetryableBody
          : strings.historyLoadFailedCorruptBody,
      action: retryable
          ? FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 20),
              label: Text(strings.historyRetry),
            )
          : null,
    );
  }
}

/// Note shown while a statistics sample is too small to read much into.
class HistoryLowDataNote extends StatelessWidget {
  /// Creates the low-data note.
  const HistoryLowDataNote({required this.matches, super.key});

  /// Matches the figures are based on.
  final int matches;

  @override
  Widget build(BuildContext context) {
    return _InlineNote(
      icon: Icons.timeline_outlined,
      text: context.strings.statsLowDataNote(matches),
    );
  }
}

/// Discloses that a slice's Fifty figures cover fewer matches than it played.
///
/// Rendered per slice rather than once per screen: a single difficulty or
/// coaching group can hold every unmeasured match while the rest of the screen
/// is fully measured, and a screen-level banner would attach the caveat to the
/// wrong numbers.
class HistoryFiftySampleNote extends StatelessWidget {
  /// Creates the disclosure note.
  const HistoryFiftySampleNote({
    required this.measured,
    required this.played,
    super.key,
  });

  /// Matches whose Fifty counters were measured.
  final int measured;

  /// Matches in this slice.
  final int played;

  @override
  Widget build(BuildContext context) {
    return _InlineNote(
      icon: Icons.help_outline,
      text: context.strings.statsFiftyMeasuredNote(measured, played),
    );
  }
}

class _InlineNote extends StatelessWidget {
  const _InlineNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: LoungeTokens.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: LoungeTokens.mutedText),
          const SizedBox(width: LoungeTokens.space2),
          Expanded(
            child: Text(
              text,
              style: LoungeTokens.bodyMuted.copyWith(
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CenteredPanel extends StatelessWidget {
  const _CenteredPanel({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(LoungeTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: iconColor.withValues(alpha: 0.8)),
            const SizedBox(height: LoungeTokens.space4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: LoungeTokens.offWhiteText,
                fontSize: 19,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: LoungeTokens.space3),
            Text(
              body,
              textAlign: TextAlign.center,
              style: LoungeTokens.bodyMuted.copyWith(height: 1.45),
            ),
            if (action != null) ...[
              const SizedBox(height: LoungeTokens.space5),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
