import 'match_history_summary.dart';
import 'match_replay_record.dart';

/// Why a match-history operation could not complete.
enum MatchHistoryFailureKind {
  /// The backing store failed and the operation may succeed if retried.
  ///
  /// This is the important one. A storage failure is a statement about the
  /// storage, not about the data — it must never be read as "the replay is
  /// gone", because acting on that would delete or downgrade a record that was
  /// merely unreachable for a moment.
  retryable,

  /// Stored bytes were read successfully but do not decode.
  ///
  /// Unlike [retryable], this *is* evidence about the data: retrying reads the
  /// same bad bytes.
  corrupt,
}

/// A typed match-history failure.
///
/// Storage exceptions are translated into these at the repository boundary, so
/// no caller ever has to catch a `ReplayFileStoreException` or a raw key-value
/// error to work out what happened.
class MatchHistoryFailure {
  /// Creates a failure.
  const MatchHistoryFailure({
    required this.kind,
    required this.message,
    this.matchId,
    this.cause,
  });

  /// Whether retrying could help.
  final MatchHistoryFailureKind kind;

  /// Human-readable detail.
  final String message;

  /// The match the operation targeted, when it had one.
  final String? matchId;

  /// The underlying error.
  final Object? cause;

  @override
  String toString() {
    final target = matchId == null ? '' : ' (match: $matchId)';
    return 'MatchHistoryFailure[${kind.name}]$target: $message';
  }
}

/// Result of publishing a pending match archive.
sealed class MatchArchivePublishOutcome {
  const MatchArchivePublishOutcome();
}

/// Nothing was waiting to be published.
class MatchArchiveNothingPending extends MatchArchivePublishOutcome {
  /// Creates the no-op outcome.
  const MatchArchiveNothingPending();
}

/// The match was published, with a replay record.
class MatchArchivePublished extends MatchArchivePublishOutcome {
  /// Creates a published outcome.
  const MatchArchivePublished(this.summary);

  /// The published summary.
  final MatchHistorySummary summary;
}

/// The match was published without a replay record.
///
/// Its transcript was absent, incomplete, or failed verification, so the
/// summary is visible and honest rather than offering a replay that cannot open.
class MatchArchivePublishedNonReplayable extends MatchArchivePublishOutcome {
  /// Creates a non-replayable published outcome.
  const MatchArchivePublishedNonReplayable(this.summary, this.reason);

  /// The published summary, with `replayable: false`.
  final MatchHistorySummary summary;

  /// Why no replay was written.
  final String reason;
}

/// The match was already published; publication was a no-op.
class MatchArchiveAlreadyPublished extends MatchArchivePublishOutcome {
  /// Creates an already-published outcome.
  const MatchArchiveAlreadyPublished(this.summary);

  /// The existing summary.
  final MatchHistorySummary summary;
}

/// Publication failed and the pending record was left in place for retry.
class MatchArchivePublishFailed extends MatchArchivePublishOutcome {
  /// Creates a failed outcome.
  const MatchArchivePublishFailed(this.failure);

  /// What went wrong.
  final MatchHistoryFailure failure;
}

/// Result of listing history.
sealed class MatchHistoryListOutcome {
  const MatchHistoryListOutcome();
}

/// History listed successfully.
class MatchHistoryListed extends MatchHistoryListOutcome {
  /// Creates a listed outcome.
  const MatchHistoryListed({
    required this.summaries,
    required this.repairedMatchIds,
  });

  /// Summaries, newest first.
  final List<MatchHistorySummary> summaries;

  /// Matches repaired to non-replayable during this listing.
  final List<String> repairedMatchIds;
}

/// Listing failed. Nothing was mutated.
class MatchHistoryListFailed extends MatchHistoryListOutcome {
  /// Creates a failed listing outcome.
  const MatchHistoryListFailed(this.failure);

  /// What went wrong.
  final MatchHistoryFailure failure;
}

/// Result of opening a replay.
sealed class MatchReplayOpenOutcome {
  const MatchReplayOpenOutcome();
}

/// The replay loaded.
class MatchReplayOpened extends MatchReplayOpenOutcome {
  /// Creates an opened outcome.
  const MatchReplayOpened(this.record);

  /// The loaded replay record.
  final MatchReplayRecord record;
}

/// The replay is definitively gone or unreadable, and the summary was repaired.
class MatchReplayUnavailable extends MatchReplayOpenOutcome {
  /// Creates an unavailable outcome.
  const MatchReplayUnavailable(this.summary, this.reason);

  /// The repaired summary, now non-replayable.
  final MatchHistorySummary summary;

  /// Why the replay is unavailable.
  final String reason;
}

/// Opening failed transiently. The summary was left alone.
class MatchReplayOpenFailed extends MatchReplayOpenOutcome {
  /// Creates a failed open outcome.
  const MatchReplayOpenFailed(this.failure);

  /// What went wrong.
  final MatchHistoryFailure failure;
}

/// Result of deleting a history entry.
sealed class MatchHistoryDeleteOutcome {
  const MatchHistoryDeleteOutcome();
}

/// Both records are gone.
class MatchHistoryDeleted extends MatchHistoryDeleteOutcome {
  /// Creates a deleted outcome.
  const MatchHistoryDeleted();

  /// Whether a replay file actually existed and was removed.
  bool get removedReplay => true;
}

/// Deletion failed. The entry is still listed and can be retried.
class MatchHistoryDeleteFailed extends MatchHistoryDeleteOutcome {
  /// Creates a failed deletion outcome.
  const MatchHistoryDeleteFailed(this.failure);

  /// What went wrong.
  final MatchHistoryFailure failure;
}

/// Result of repairing a replay that exists but cannot be used.
sealed class MatchReplayRepairOutcome {
  /// Creates an outcome.
  const MatchReplayRepairOutcome();
}

/// The summary is now durably marked non-replayable.
class MatchReplayRepaired extends MatchReplayRepairOutcome {
  /// Creates a repaired outcome.
  const MatchReplayRepaired(this.summary);

  /// The rewritten summary.
  final MatchHistorySummary summary;
}

/// The repair could not be completed.
///
/// The entry is deliberately left as it was. Reporting a repair that did not
/// happen would send the player back to a list that still offers the dead
/// link, with nothing to retry.
class MatchReplayRepairFailed extends MatchReplayRepairOutcome {
  /// Creates a failed repair.
  const MatchReplayRepairFailed(this.failure);

  /// Why the repair failed.
  final MatchHistoryFailure failure;
}
