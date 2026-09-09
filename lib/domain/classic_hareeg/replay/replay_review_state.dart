import 'match_replay_timeline.dart';

/// Where a reviewer is standing in a replay, and where they can go next.
///
/// Immutable and pure: every move returns a new state. Navigation lives here
/// rather than in the viewer so the widget only renders and forwards commands,
/// and so "what does Back do at a round start" has one answer instead of one
/// per button.
class ReplayReviewState {
  const ReplayReviewState._(this.timeline, this.cursor);

  /// Starts a review at the first frame.
  factory ReplayReviewState.atStart(MatchReplayTimeline timeline) =>
      ReplayReviewState._(timeline, 0);

  /// The timeline being reviewed.
  final MatchReplayTimeline timeline;

  /// Index of the frame currently shown.
  final int cursor;

  /// Frame currently shown.
  ReplayFrame get frame => timeline.frameAt(cursor);

  /// Frame immediately before the cursor, or null at the very start.
  ///
  /// This is the pre-action state a reviewer reasons from.
  ReplayFrame? get previousFrame =>
      cursor == 0 ? null : timeline.frameAt(cursor - 1);

  /// Total number of positions.
  int get length => timeline.length;

  /// One-based step number for display.
  int get stepNumber => cursor + 1;

  /// Round the cursor is in.
  int get roundNumber => frame.roundNumber;

  /// Whether a next frame exists.
  bool get canStepForward => cursor < length - 1;

  /// Whether a previous frame exists.
  bool get canStepBack => cursor > 0;

  /// Whether a later round exists.
  bool get canGoNextRound => _nextRoundNumber() != null;

  /// Whether there is anywhere for a "previous round" press to go.
  ///
  /// True while the cursor is past its own round's start (the press rewinds to
  /// the start of this round) and while an earlier round exists.
  bool get canGoPreviousRound => _previousRoundTarget() != cursor;

  /// Moves one frame forward, or stays put at the end.
  ReplayReviewState stepForward() => seekTo(cursor + 1);

  /// Moves one frame back, or stays put at the start.
  ReplayReviewState stepBack() => seekTo(cursor - 1);

  /// Jumps to the first frame.
  ReplayReviewState seekToStart() => seekTo(0);

  /// Jumps to the last frame.
  ReplayReviewState seekToEnd() => seekTo(length - 1);

  /// Jumps to [index], clamped into range.
  ///
  /// Clamping rather than throwing because a slider drag and a saved position
  /// are both legitimate sources of an out-of-range request, and neither is a
  /// programming error worth crashing a review over.
  ReplayReviewState seekTo(int index) {
    final clamped = index < 0
        ? 0
        : index > length - 1
        ? length - 1
        : index;
    return clamped == cursor ? this : ReplayReviewState._(timeline, clamped);
  }

  /// Jumps to the start of the next round, or stays put in the last round.
  ReplayReviewState nextRound() {
    final round = _nextRoundNumber();
    if (round == null) {
      return this;
    }
    return seekTo(timeline.startIndexOfRound(round) ?? cursor);
  }

  /// Rewinds to the start of the current round, or to the previous round's
  /// start when already there.
  ///
  /// This is how a track-skip control behaves, and it is what makes a single
  /// button useful for both "restart this round" and "go back one round".
  ReplayReviewState previousRound() => seekTo(_previousRoundTarget());

  int? _nextRoundNumber() {
    for (final round in timeline.roundNumbers) {
      if (round > roundNumber) {
        return round;
      }
    }
    return null;
  }

  int _previousRoundTarget() {
    final currentStart = timeline.startIndexOfRound(roundNumber) ?? 0;
    if (cursor > currentStart) {
      return currentStart;
    }
    int? previous;
    for (final round in timeline.roundNumbers) {
      if (round < roundNumber) {
        previous = round;
      }
    }
    if (previous == null) {
      return cursor;
    }
    return timeline.startIndexOfRound(previous) ?? cursor;
  }
}
