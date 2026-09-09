import '../game/classic_hareeg_match_snapshot.dart';
import '../models/player_seat.dart';
import '../reporting/match_action_transcript.dart';
import '../reporting/snapshot_mismatch.dart';
import 'replay_reconstruction.dart';

export 'replay_reconstruction.dart'
    show
        ReplayApplyHook,
        ReplayFrame,
        ReplayFrameKind,
        ReplayTimelineFailure,
        ReplayTimelineFailureKind,
        replayClockEpoch,
        replayFiftyExpiryPaddingSeconds;

/// Result of asking for a timeline.
sealed class ReplayTimelineOutcome {
  /// Creates an outcome.
  const ReplayTimelineOutcome();
}

/// The transcript reconstructed cleanly.
class ReplayTimelineBuilt extends ReplayTimelineOutcome {
  /// Creates a successful outcome.
  const ReplayTimelineBuilt(this.timeline);

  /// The reconstructed timeline.
  final MatchReplayTimeline timeline;
}

/// The transcript could not be reconstructed.
///
/// No timeline is produced at all. Reconstruction is all-or-nothing because a
/// truncated match rendered as the match would misinform the player more
/// quietly than an honest refusal does.
class ReplayTimelineFailed extends ReplayTimelineOutcome {
  /// Creates a failed outcome.
  const ReplayTimelineFailed(this.failure);

  /// Why reconstruction refused.
  final ReplayTimelineFailure failure;
}

/// Every reachable position in one completed match, plus the verification the
/// archive path already needed.
///
/// This is the single owner of "a transcript turned back into match states".
/// `replayTranscript` verifies through it, the viewer navigates through it,
/// and a later branch sandbox will seed from it.
class MatchReplayTimeline {
  MatchReplayTimeline._(this._frames, this._roundStartIndexes);

  final List<ReplayFrame> _frames;
  final Map<int, int> _roundStartIndexes;

  /// Every frame, in order.
  List<ReplayFrame> get frames => List.unmodifiable(_frames);

  /// Number of reachable positions.
  int get length => _frames.length;

  /// Frame at [index].
  ReplayFrame frameAt(int index) => _frames[index];

  /// Final reconstructed state.
  ClassicHareegMatchSnapshot get finalSnapshot => _frames.last.snapshot;

  /// Winner the replayed match actually reached, when it reached one.
  PlayerSeat? get matchWinner => _frames.last.matchWinner;

  /// Rounds present, ascending and duplicate-free.
  List<int> get roundNumbers {
    final rounds = _roundStartIndexes.keys.toList()..sort();
    return List.unmodifiable(rounds);
  }

  /// Index of the frame that opens [round], or null when the round is absent.
  ///
  /// The transcript's first round opens at the initial frame; later rounds open
  /// at their round-start frame.
  int? startIndexOfRound(int round) => _roundStartIndexes[round];

  /// Round the frame at [index] belongs to.
  int roundOfFrame(int index) => _frames[index].roundNumber;

  /// Compares the final reconstructed state to [expected].
  ///
  /// Delegates to the existing comparator rather than restating a field list,
  /// so history and replay can never disagree about what "the same state"
  /// means.
  List<String> verifyAgainst(ClassicHareegMatchSnapshot expected) {
    return describeSnapshotMismatch(expected: expected, actual: finalSnapshot);
  }

  static MatchReplayTimeline _fromFrames(List<ReplayFrame> frames) {
    final starts = <int, int>{};
    for (final frame in frames) {
      starts.putIfAbsent(frame.roundNumber, () => frame.index);
    }
    return MatchReplayTimeline._(List.of(frames), starts);
  }

  /// Reconstructs [transcript] synchronously.
  ///
  /// Suitable for verification and tests. A UI must not call this for a full
  /// match: draining ~1700 frames in one go blocks the isolate. Use
  /// [IncrementalTimelineBuild] there.
  static ReplayTimelineOutcome build(
    MatchActionTranscript transcript, {
    ReplayApplyHook? applyHook,
  }) {
    final machine = applyHook == null
        ? ReplayReconstruction(transcript)
        : ReplayReconstruction(transcript, applyHook: applyHook);
    while (machine.advance()) {
      // Drain to completion.
    }
    return _outcomeOf(machine)!;
  }

  static ReplayTimelineOutcome? _outcomeOf(ReplayReconstruction machine) {
    if (machine.isCancelled) {
      return null;
    }
    final failure = machine.failure;
    if (failure != null) {
      return ReplayTimelineFailed(failure);
    }
    return ReplayTimelineBuilt(_fromFrames(machine.frames));
  }
}

/// A cancellable, chunked drain of the same reconstruction machine.
///
/// The UI uses this so a long match stays interactive while it loads. It is a
/// different *drain* of one state machine, not a second reconstruction: the
/// round crossing, apply seam, retry and clock all still live in
/// [ReplayReconstruction].
class IncrementalTimelineBuild {
  /// Creates a chunked build.
  ///
  /// [chunkSize] frames are produced between yields. [yieldTo] exists so a
  /// test can count yields and prove the work is actually spread out.
  IncrementalTimelineBuild(
    MatchActionTranscript transcript, {
    this.chunkSize = 24,
    this.timeBudget,
    this.onProgress,
    Future<void> Function()? yieldTo,
    ReplayApplyHook? applyHook,
  }) : _yieldTo = yieldTo ?? _microtaskYield,
       _machine = applyHook == null
           ? ReplayReconstruction(transcript)
           : ReplayReconstruction(transcript, applyHook: applyHook) {
    if (chunkSize < 1) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'Must be at least 1.');
    }
  }

  /// Frames produced between yields.
  final int chunkSize;

  /// Optional elapsed-time ceiling between actions. A single engine action
  /// remains atomic, but a slow action cannot multiply into a 24-action stall.
  final Duration? timeBudget;
  final void Function(int frames)? onProgress;

  final Future<void> Function() _yieldTo;
  final ReplayReconstruction _machine;
  int _yieldCount = 0;

  static Future<void> _microtaskYield() => Future<void>.delayed(Duration.zero);

  /// How many times the drain gave the event loop a turn.
  int get yieldCount => _yieldCount;

  /// Frames produced so far, for progress reporting.
  int get producedFrames => _machine.frameCount;

  /// Abandons the build. [run] completes with null.
  void cancel() => _machine.cancel();

  /// Drains the machine in chunks, yielding between them.
  ///
  /// Completes with null when cancelled, so a caller disposed mid-build has
  /// nothing to apply.
  Future<ReplayTimelineOutcome?> run() async {
    while (true) {
      var produced = 0;
      final watch = Stopwatch()..start();
      while (produced < chunkSize && _machine.advance()) {
        produced += 1;
        if (timeBudget != null && watch.elapsed >= timeBudget!) break;
      }
      onProgress?.call(producedFrames);
      if (_machine.isDone) {
        return MatchReplayTimeline._outcomeOf(_machine);
      }
      _yieldCount += 1;
      await _yieldTo();
      if (_machine.isCancelled) {
        return null;
      }
    }
  }
}
