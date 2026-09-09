import '../game/classic_hareeg_match_snapshot.dart';
import 'replay_reconstruction.dart';

/// Why a replay frame cannot be branched from.
enum ReplayBranchRefusal {
  /// The match was already decided at this frame.
  ///
  /// Branching here would hand the player a finished match with nothing to
  /// change, so the affordance is refused rather than shown and ignored.
  matchAlreadyComplete,

  /// The round ended here and the timeline stops before the next deal.
  ///
  /// A finished round cannot be played on from: every seat's turn is over and
  /// the score is already taken. Normally the sandbox starts from the next
  /// round the timeline recorded — but if the recording ends at the boundary
  /// there is no next round to start from, and inventing one would be a
  /// different match.
  roundEndedWithoutNextRound,
}

/// A live sandbox seeded from one replay frame.
///
/// Pure: no Flutter, no repositories, no wall clock. The branch clock is an
/// argument, so the rebase can be asserted exactly instead of slept on.
class ReplayBranchSeed {
  const ReplayBranchSeed._({
    required this.snapshot,
    required this.frameIndex,
    required this.roundNumber,
    required this.branchStart,
    required this.fiftySecondsRemaining,
    required this.advancedPastRoundEnd,
  });

  /// Whether a branch may start at [frame].
  ///
  /// [nextFrame] is the timeline position immediately after it, or null at the
  /// end of the recording. It is **required** rather than optional because one
  /// of the two refusals is a property of what comes after the frame, and a
  /// caller that could omit it would silently get the old, broken answer.
  static ReplayBranchRefusal? refusalFor(
    ReplayFrame frame, {
    required ReplayFrame? nextFrame,
  }) {
    if (frame.matchWinner != null) {
      return ReplayBranchRefusal.matchAlreadyComplete;
    }
    if (_isRoundEnd(frame, nextFrame) && _nextRound(frame, nextFrame) == null) {
      return ReplayBranchRefusal.roundEndedWithoutNextRound;
    }
    return null;
  }

  /// Builds a seed for [frame], with the sandbox clock starting at
  /// [branchStart].
  ///
  /// Returns null when [refusalFor] refuses the position, so an unavailable
  /// branch is a value the caller must handle rather than a seed that quietly
  /// misbehaves.
  ///
  /// **A round-end frame starts the sandbox at the next round's deal.** The
  /// snapshot at such a frame describes a round that is *over*: a seat has an
  /// empty hand, the score is already taken, and nobody has a legal move.
  /// Restoring it hands the player a board they cannot play — and the
  /// controller cannot tell that it should not, because a snapshot has no
  /// field for "this round finished and here is its result", so it reopens the
  /// finished round as an unfinished one.
  ///
  /// Adopting the *next* frame's state instead is what B21 asks for: the
  /// branch advances into the next round exactly once, and it does so by
  /// taking the deal the timeline already recorded rather than by re-running
  /// the scoring on a round that was scored when it was played.
  static ReplayBranchSeed? fromFrame(
    ReplayFrame frame, {
    required ReplayFrame? nextFrame,
    required DateTime branchStart,
  }) {
    if (refusalFor(frame, nextFrame: nextFrame) != null) {
      return null;
    }
    final advanced = _nextRound(frame, nextFrame);
    // The position the sandbox actually starts from. It differs from the
    // branch point only at a round boundary.
    final start = advanced ?? frame;

    // The clock the start state should be read against. After a Fifty window
    // had to be expired mid-apply, the frame's own clock is past the jump;
    // `effectivePreActionClock` is the one that describes the state.
    final reference = start.effectivePreActionClock ?? start.clock;
    final remaining = start.fiftySecondsRemainingAt(reference);

    return ReplayBranchSeed._(
      snapshot: _rebase(
        start.snapshot,
        branchStart: branchStart,
        reference: reference,
      ),
      // The BRANCH POINT's index, not the start frame's: this is the position
      // the player chose and the one exiting must restore.
      frameIndex: frame.index,
      roundNumber: start.roundNumber,
      branchStart: branchStart,
      fiftySecondsRemaining: remaining,
      advancedPastRoundEnd: advanced != null,
    );
  }

  /// Whether [frame] is the last position of its round.
  ///
  /// Two shapes count. A recorded boundary is one where the next frame belongs
  /// to a later round. A recording that simply *stops* on a seat with an empty
  /// hand is also a finished round — nobody can move — and must not be
  /// mistaken for a playable position.
  static bool _isRoundEnd(ReplayFrame frame, ReplayFrame? nextFrame) {
    if (nextFrame != null) {
      return nextFrame.roundNumber > frame.roundNumber;
    }
    return frame.snapshot.hands.values.any((hand) => hand.isEmpty);
  }

  /// The deal that opens the round after [frame], or null when [frame] is not
  /// a round end or the recording stops first.
  static ReplayFrame? _nextRound(ReplayFrame frame, ReplayFrame? nextFrame) {
    if (nextFrame == null || !_isRoundEnd(frame, nextFrame)) {
      return null;
    }
    return nextFrame;
  }

  /// Match state the sandbox starts from, rebased onto the branch clock.
  final ClassicHareegMatchSnapshot snapshot;

  /// Timeline position this branch came from, for returning to review.
  ///
  /// Always the frame the player chose, even when the sandbox starts from the
  /// next round's deal: exiting must put the reviewer back where they were.
  final int frameIndex;

  /// Whether the branch point was a round end, so the sandbox starts at the
  /// next round's deal rather than at the chosen frame's own state.
  final bool advancedPastRoundEnd;

  /// Dealt round the branch point belongs to.
  final int roundNumber;

  /// Instant the sandbox clock starts at.
  final DateTime branchStart;

  /// Seconds left on an open Fifty window at the branch instant, or null when
  /// no window is open.
  ///
  /// Preserved exactly from the historical frame: a player who branched with
  /// four seconds left gets four seconds, not a fresh timer and not an
  /// already-expired one.
  final int? fiftySecondsRemaining;

  /// Moves the snapshot's clock-bearing fields onto the branch clock.
  ///
  /// Done by round-tripping through the snapshot's own codec rather than by
  /// re-listing its 26 constructor fields. Copying them by hand is how state
  /// gets silently dropped when a field is added later; the codec already
  /// enumerates every field and is itself tested, so this cannot fall behind.
  ///
  /// **The window is rebased by preserving elapsed time, not remaining time.**
  /// Deriving the new origin from `fiftySecondsRemaining` looks equivalent and
  /// is not: every instant inside the two-second post-expiry grace reports
  /// `remaining == 0`, so reconstructing from it would place the origin at
  /// exactly `branchStart - timer` and hand the window a fresh, full grace
  /// period. A window one second from vanishing would come back with two.
  /// Shifting the original elapsed duration keeps remaining time, grace
  /// position and the past-grace case all correct without special-casing any
  /// of them.
  static ClassicHareegMatchSnapshot _rebase(
    ClassicHareegMatchSnapshot snapshot, {
    required DateTime branchStart,
    required DateTime reference,
  }) {
    final json = Map<String, Object?>.of(snapshot.toJson());
    json['savedAt'] = branchStart.toIso8601String();

    final openedAt = snapshot.fiftyWindowOpenedAt;
    json['fiftyWindowOpenedAt'] = openedAt == null
        ? null
        : branchStart
              .subtract(reference.difference(openedAt))
              .toIso8601String();

    return ClassicHareegMatchSnapshot.fromJson(json);
  }
}
