import '../../../domain/classic_hareeg/history/match_history_outcomes.dart';
import '../../../domain/classic_hareeg/history/match_history_summary.dart';

/// What a history-backed surface should render right now.
///
/// Pure and Flutter-free so the mapping can be tested without pumping a widget,
/// and so the one decision that matters — a failure is not an empty history —
/// is provable in isolation.
sealed class MatchHistoryViewState {
  const MatchHistoryViewState();

  /// Maps a repository outcome to a view state.
  factory MatchHistoryViewState.fromOutcome(MatchHistoryListOutcome outcome) {
    return switch (outcome) {
      MatchHistoryListed(:final summaries) when summaries.isEmpty =>
        const MatchHistoryEmpty(),
      MatchHistoryListed(:final summaries) => MatchHistoryLoaded(summaries),
      // Never MatchHistoryEmpty. "No saved matches yet" over an index that
      // could not be read tells the player their history was deleted.
      MatchHistoryListFailed(:final failure) => MatchHistoryFailed(failure),
    };
  }
}

/// The listing has not answered yet.
class MatchHistoryLoading extends MatchHistoryViewState {
  /// Creates the loading state.
  const MatchHistoryLoading();
}

/// The listing succeeded and there is nothing stored.
class MatchHistoryEmpty extends MatchHistoryViewState {
  /// Creates the empty state.
  const MatchHistoryEmpty();
}

/// The listing succeeded with at least one match.
class MatchHistoryLoaded extends MatchHistoryViewState {
  /// Creates the loaded state.
  const MatchHistoryLoaded(this.summaries);

  /// Summaries in the order the repository returned them, newest first.
  ///
  /// Deliberately not re-sorted. Ordering has one owner, and it is the
  /// repository.
  final List<MatchHistorySummary> summaries;
}

/// The listing failed.
class MatchHistoryFailed extends MatchHistoryViewState {
  /// Creates the failed state.
  const MatchHistoryFailed(this.failure);

  /// The typed failure, kind included.
  ///
  /// The kind is carried rather than flattened because it changes what the
  /// player is told and what they are offered: retrying a [
  /// MatchHistoryFailureKind.corrupt] read returns the same bad bytes, so
  /// offering a retry would be a false promise.
  final MatchHistoryFailure failure;

  /// Whether retrying could plausibly help.
  bool get isRetryable => failure.kind == MatchHistoryFailureKind.retryable;
}
