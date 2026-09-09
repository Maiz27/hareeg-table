import '../../../domain/classic_hareeg/history/match_history_outcomes.dart';
import '../../../domain/classic_hareeg/replay/match_replay_timeline.dart';
import '../../../domain/classic_hareeg/replay/replay_review_state.dart';

/// Why a replay cannot be shown.
///
/// A closed set of typed reasons, deliberately not a message. The failures
/// underneath carry engine text full of raw action ids and English wording;
/// rendering that would leak internals into both languages. The UI maps these
/// values to localized copy instead.
enum ReplayUnavailableReason {
  /// The stored replay is missing, unreadable, or not this match's.
  replayDataUnusable,

  /// The replay decoded, but the match could not be rebuilt from it.
  reconstructionFailed,

  /// The replay decoded, but an entry does not describe the state it claims.
  metadataInvalid,
}

/// What the replay screen is showing.
sealed class ReplayViewerViewState {
  /// Creates a state.
  const ReplayViewerViewState();

  /// Maps a repository open outcome to a screen state.
  ///
  /// The reason is derived from the *outcome type*, never by reading the
  /// failure's message. The repository distinguishes a missing file from
  /// undecodable bytes only by its English prose, and parsing that would make
  /// the UI depend on wording nobody thinks of as an interface.
  static ReplayViewerViewState fromOpenOutcome(MatchReplayOpenOutcome outcome) {
    return switch (outcome) {
      MatchReplayUnavailable() => const ReplayViewerUnavailable(
        ReplayUnavailableReason.replayDataUnusable,
      ),
      MatchReplayOpenFailed(:final failure) => ReplayViewerFailed(failure),
      // A decoded record still has to rebuild before there is anything to show,
      // so the caller continues from here.
      MatchReplayOpened() => const ReplayViewerLoading(),
    };
  }

  /// Maps a reconstruction failure to the reason shown to the player.
  static ReplayUnavailableReason reasonFor(ReplayTimelineFailureKind kind) {
    return switch (kind) {
      ReplayTimelineFailureKind.actionRejected ||
      ReplayTimelineFailureKind.roundUnavailable =>
        ReplayUnavailableReason.reconstructionFailed,
      ReplayTimelineFailureKind.seatMismatch ||
      ReplayTimelineFailureKind.phaseMismatch ||
      ReplayTimelineFailureKind.roundRegression =>
        ReplayUnavailableReason.metadataInvalid,
    };
  }
}

/// The replay is being loaded and rebuilt.
class ReplayViewerLoading extends ReplayViewerViewState {
  /// Creates a loading state.
  const ReplayViewerLoading({this.rebuiltFrames = 0});

  /// Frames rebuilt so far, for a progress hint on a long match.
  final int rebuiltFrames;
}

/// The match is reconstructed and reviewable.
class ReplayViewerReady extends ReplayViewerViewState {
  /// Creates a ready state.
  const ReplayViewerReady(this.review);

  /// Where the reviewer is standing.
  final ReplayReviewState review;

  /// The reconstructed match.
  MatchReplayTimeline get timeline => review.timeline;
}

/// The replay exists in history but cannot be shown.
///
/// Distinct from [ReplayViewerFailed]: this entry has been repaired and will
/// not offer a replay again, which is a different thing to tell the player than
/// "something went wrong, try again".
class ReplayViewerUnavailable extends ReplayViewerViewState {
  /// Creates an unavailable state.
  const ReplayViewerUnavailable(this.reason);

  /// Why it cannot be shown.
  final ReplayUnavailableReason reason;
}

/// Loading failed for a reason that says nothing about the replay itself.
class ReplayViewerFailed extends ReplayViewerViewState {
  /// Creates a failed state.
  const ReplayViewerFailed(this.failure);

  /// The typed failure.
  final MatchHistoryFailure failure;

  /// Whether trying again could plausibly work.
  ///
  /// Retrying a corrupt read just reads the same bytes, so only a retryable
  /// failure gets an affordance — the distinction Sprint 03 established for
  /// listing and deletion.
  bool get isRetryable => failure.kind == MatchHistoryFailureKind.retryable;
}
