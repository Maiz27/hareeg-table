import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../app/app_routes.dart';
import '../../../../data/persistence/match_history_repository.dart';
import '../../../../domain/classic_hareeg/history/match_history_outcomes.dart';
import '../../../../domain/classic_hareeg/history/match_history_summary.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../match_history_view_state.dart';
import '../widgets/history_state_panels.dart';
import '../widgets/match_history_entry_card.dart';

/// Browses completed matches from their stored summaries.
///
/// Summary-only by construction: nothing here opens a replay record, and the
/// order is whatever the repository returned. Sorting lives in the repository
/// and stays there, so history cannot end up with two orderings that disagree.
class MatchHistoryScreen extends StatefulWidget {
  /// Creates the history browser.
  const MatchHistoryScreen({required this.historyRepository, super.key});

  /// Completed-match storage.
  final MatchHistoryRepository historyRepository;

  @override
  State<MatchHistoryScreen> createState() => _MatchHistoryScreenState();
}

class _MatchHistoryScreenState extends State<MatchHistoryScreen> {
  MatchHistoryViewState _state = const MatchHistoryLoading();

  @override
  void initState() {
    super.initState();
    AppOrientation.usePortrait();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const MatchHistoryLoading());

    MatchHistoryListOutcome outcome;
    try {
      outcome = await widget.historyRepository.listSummaries();
    } catch (error, stackTrace) {
      // The repository is contracted to translate storage errors into typed
      // outcomes, so reaching here means something escaped that boundary.
      // Reporting it as a retryable failure is honest; rendering an empty
      // history would not be.
      debugPrint('Failed to list match history: $error');
      debugPrintStack(stackTrace: stackTrace);
      outcome = MatchHistoryListFailed(
        MatchHistoryFailure(
          kind: MatchHistoryFailureKind.retryable,
          message: 'History listing threw.',
          cause: error,
        ),
      );
    }

    if (!mounted) {
      return;
    }
    setState(() => _state = MatchHistoryViewState.fromOutcome(outcome));
  }

  /// Opens the replay, then re-lists on return.
  ///
  /// The re-list matters: opening a replay that turns out to be unusable
  /// repairs the entry, and coming back to a stale list would still show it as
  /// replayable.
  Future<void> _openReplay(MatchHistorySummary summary) async {
    await Navigator.of(context).pushNamed(AppRoutes.replay, arguments: summary);
    if (!mounted) {
      return;
    }
    await _load();
  }

  Future<void> _confirmDelete(MatchHistorySummary summary) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: LoungeTokens.coffeeCharcoal,
        title: Text(
          strings.historyDeleteConfirmTitle,
          style: const TextStyle(color: LoungeTokens.offWhiteText),
        ),
        content: Text(
          strings.historyDeleteConfirmBody,
          style: LoungeTokens.bodyMuted,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.historyCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.historyDelete),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }
    await _delete(summary);
  }

  Future<void> _delete(MatchHistorySummary summary) async {
    MatchHistoryDeleteOutcome outcome;
    try {
      outcome = await widget.historyRepository.deleteMatch(summary.matchId);
    } catch (error, stackTrace) {
      debugPrint('Failed to delete match ${summary.matchId}: $error');
      debugPrintStack(stackTrace: stackTrace);
      outcome = MatchHistoryDeleteFailed(
        MatchHistoryFailure(
          kind: MatchHistoryFailureKind.retryable,
          message: 'Match deletion threw.',
          matchId: summary.matchId,
          cause: error,
        ),
      );
    }

    if (!mounted) {
      return;
    }

    switch (outcome) {
      case MatchHistoryDeleted():
        // Re-list rather than removing the row locally, so what the player
        // sees afterwards is what storage actually holds.
        await _load();
      case MatchHistoryDeleteFailed(:final failure):
        _showDeleteFailure(failure, summary);
    }
  }

  void _showDeleteFailure(
    MatchHistoryFailure failure,
    MatchHistorySummary summary,
  ) {
    final strings = context.strings;
    final retryable = failure.kind == MatchHistoryFailureKind.retryable;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          retryable
              ? strings.historyDeleteFailedRetryable
              : strings.historyDeleteFailedCorrupt,
        ),
        duration: const Duration(seconds: 6),
        // A corrupt index reads the same bad bytes every time, so there is
        // nothing honest to offer. Only a retryable failure gets an action.
        action: retryable
            ? SnackBarAction(
                label: strings.historyRetry,
                onPressed: () => _delete(summary),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Scaffold(
      backgroundColor: LoungeTokens.feltGreen,
      appBar: AppBar(
        backgroundColor: LoungeTokens.coffeeCharcoal,
        foregroundColor: LoungeTokens.offWhiteText,
        title: Text(strings.historyTitle),
        actions: [
          IconButton(
            // Replaces rather than pushes: History and Statistics are peers,
            // so toggling between them must not build a stack the player has
            // to unwind one Back at a time.
            onPressed: () => Navigator.of(
              context,
            ).pushReplacementNamed(AppRoutes.statistics),
            icon: const Icon(Icons.insights_outlined),
            tooltip: strings.statisticsMenuLabel,
            color: LoungeTokens.sandLine,
          ),
        ],
      ),
      body: SafeArea(child: _body(strings)),
    );
  }

  Widget _body(AppStrings strings) {
    return switch (_state) {
      MatchHistoryLoading() => const Center(child: CircularProgressIndicator()),
      MatchHistoryEmpty() => HistoryEmptyPanel(
        title: strings.historyEmptyTitle,
        body: strings.historyEmptyBody,
      ),
      MatchHistoryFailed(:final failure) => HistoryFailurePanel(
        failure: failure,
        onRetry: _load,
      ),
      MatchHistoryLoaded(:final summaries) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          LoungeTokens.space4,
          LoungeTokens.space4,
          LoungeTokens.space4,
          LoungeTokens.space6,
        ),
        itemCount: summaries.length,
        itemBuilder: (context, index) {
          final summary = summaries[index];
          return MatchHistoryEntryCard(
            key: ValueKey(summary.matchId),
            summary: summary,
            onDelete: () => _confirmDelete(summary),
            onReplay: summary.replayable ? () => _openReplay(summary) : null,
          );
        },
      ),
    };
  }
}
