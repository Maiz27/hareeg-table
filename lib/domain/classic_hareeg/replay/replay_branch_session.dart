import 'replay_branch_seed.dart';
import 'replay_reconstruction.dart';

/// One run of a branch sandbox: what it started from, and what has happened
/// since.
///
/// Pure: no Flutter, no repositories, no wall clock. It holds the three facts
/// the host has to get right and that are easy to get wrong by hand — has this
/// sandbox diverged, is its coach on, and what does restarting reset — so they
/// are unit-testable without pumping a widget tree.
///
/// It deliberately knows nothing about visibility. Blind versus study is a
/// rendering choice that the table's mode already encodes, and duplicating it
/// here would create a second place for it to be wrong.
class ReplayBranchSession {
  ReplayBranchSession._({
    required this.frame,
    required this.nextFrame,
    required this.seed,
    required this.coachEligible,
  }) : _coachEnabled = coachEligible;

  /// Starts a sandbox from [frame], with its clock beginning at [branchStart].
  ///
  /// Returns null when the frame refuses to be branched from, so an
  /// unavailable branch is a value the caller must handle rather than a
  /// session that quietly misbehaves.
  ///
  /// [coachEligible] comes from the archived summary's `coachWasEnabled` and
  /// nothing else: a sandbox cannot grant coaching the real match never had.
  static ReplayBranchSession? start({
    required ReplayFrame frame,
    required ReplayFrame? nextFrame,
    required bool coachEligible,
    required DateTime branchStart,
  }) {
    final seed = ReplayBranchSeed.fromFrame(
      frame,
      nextFrame: nextFrame,
      branchStart: branchStart,
    );
    if (seed == null) {
      return null;
    }
    return ReplayBranchSession._(
      frame: frame,
      nextFrame: nextFrame,
      seed: seed,
      coachEligible: coachEligible,
    );
  }

  /// The replay frame this sandbox branched from.
  ///
  /// Kept, not just its seed, because a restart has to rebuild the seed
  /// against a fresh clock rather than replay a stale one.
  final ReplayFrame frame;

  /// The timeline position after [frame], or null at the end of the recording.
  ///
  /// Carried so a restart rebuilds the seed the same way the first entry did.
  /// Without it a sandbox branched at a round end would restart into the
  /// finished round it was created to skip past.
  final ReplayFrame? nextFrame;

  /// State the table starts from, rebased onto the branch clock.
  final ReplayBranchSeed seed;

  /// Whether the archived match had coaching available.
  final bool coachEligible;

  bool _coachEnabled;
  bool _diverged = false;

  /// Whether the live coach is currently on.
  ///
  /// Starts equal to [coachEligible] and is session-only: nothing here reaches
  /// a preferences store, so a sandbox cannot change what the player's real
  /// tables do.
  bool get coachEnabled => _coachEnabled;

  /// Whether any action has actually been applied in this sandbox.
  ///
  /// Applied actions, not pointer activity: opening a sandbox, looking at it
  /// and leaving changes nothing, and should not be confirmed as though it
  /// did.
  bool get hasDiverged => _diverged;

  /// Timeline position to return to on exit.
  int get frameIndex => seed.frameIndex;

  /// Turns the session coach on or off. A no-op when the archived match had
  /// none, so an ineligible sandbox cannot be switched into one.
  void setCoachEnabled(bool value) {
    if (!coachEligible) {
      return;
    }
    _coachEnabled = value;
  }

  /// Records that an action applied. Idempotent once armed.
  void recordAppliedAction() {
    _diverged = true;
  }

  /// A fresh run from the same branch point.
  ///
  /// Returns a new session rather than mutating this one, so "restart resets
  /// divergence and the coach" is a property of the type instead of a
  /// checklist the host has to remember. The seed is rebuilt against
  /// [branchStart] so an open Fifty window gets its historical remaining time
  /// again rather than whatever is left of the previous run's.
  ReplayBranchSession restart({required DateTime branchStart}) {
    // The frame was branchable when this session started and frames are
    // immutable, so this cannot refuse.
    return ReplayBranchSession.start(
      frame: frame,
      nextFrame: nextFrame,
      coachEligible: coachEligible,
      branchStart: branchStart,
    )!;
  }
}
