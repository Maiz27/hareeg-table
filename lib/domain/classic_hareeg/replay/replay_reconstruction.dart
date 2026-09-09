import '../game/classic_hareeg_game_controller.dart';
import '../game/classic_hareeg_match_snapshot.dart';
import '../game/round_seed_algorithm.dart';
import '../game/classic_hareeg_discard_history.dart';
import '../game/classic_hareeg_round.dart' show TurnPhase;
import '../models/playing_card.dart';
import '../rules/opening_rules.dart' show OpeningState, PlacedMeld;
import '../models/player_seat.dart';
import '../reporting/match_action_transcript.dart';

/// The synthetic instant every replay starts from.
///
/// Replay must not depend on wall-clock timing, so the whole reconstruction
/// runs on a steadily advancing synthetic clock. This is the same epoch the
/// pre-Sprint-05 `replayTranscript` used, kept identical so reconstructed
/// snapshots stay byte-comparable with archived expectations.
final DateTime replayClockEpoch = DateTime.utc(2026, 1, 1);

/// Extra time added when a Fifty window has to be expired mid-replay.
const int replayFiftyExpiryPaddingSeconds = 30;

/// How long an expired Fifty window stays visible at zero.
///
/// Must match `ClassicHareegGameController._fiftyCueExpiryGraceSeconds`: a
/// review that disagreed with the live table about when a window is gone would
/// describe a position the player never saw.
const int replayFiftyCueExpiryGraceSeconds = 2;

/// What a frame represents.
enum ReplayFrameKind {
  /// The transcript's base state, before any recorded action.
  initial,

  /// The deterministic deal that opened a later round.
  roundStart,

  /// The state produced by applying one recorded action.
  actionApplied,
}

/// Why a reconstruction refused to produce a timeline.
enum ReplayTimelineFailureKind {
  /// The rules engine rejected a recorded action.
  actionRejected,

  /// The transcript expected another round but the match had ended.
  roundUnavailable,

  /// The entry names a seat the reconstructed state was not on.
  seatMismatch,

  /// The entry names a turn phase the reconstructed state was not in.
  phaseMismatch,

  /// The entry names a round earlier than the reconstructed round.
  roundRegression,
}

/// One reachable position in a replay.
///
/// Every kind is a normal step position: the viewer does not distinguish
/// "real" frames from markers, so seeking is uniform.
class ReplayFrame {
  /// Creates a frame.
  const ReplayFrame({
    required this.index,
    required this.kind,
    required this.roundNumber,
    required this.snapshot,
    required this.clock,
    this.appliedEntry,
    this.matchWinner,
    this.effectivePreActionClock,
  });

  /// Dense 0-based position in the timeline.
  final int index;

  /// What this frame represents.
  final ReplayFrameKind kind;

  /// One-based dealt round this frame belongs to.
  final int roundNumber;

  /// Match state at this position.
  ///
  /// For [ReplayFrameKind.initial] this is the archived base snapshot exactly
  /// as it was stored, so it keeps its original historical `savedAt`. For
  /// reconstructed frames the snapshot was stamped with [clock].
  final ClassicHareegMatchSnapshot snapshot;

  /// Effective replay clock when this frame was produced.
  ///
  /// This is the synthetic reconstruction clock, **not** a claim about
  /// `snapshot.savedAt`: frame 0 carries an archived snapshot whose own
  /// timestamp predates this run by however long ago the match was played.
  final DateTime clock;

  /// The action this frame applied, non-null exactly for
  /// [ReplayFrameKind.actionApplied].
  final MatchActionTranscriptEntry? appliedEntry;

  /// Winner the reconstructed match had reached at this frame, if any.
  final PlayerSeat? matchWinner;

  /// Clock in force immediately *before* this action was applied, when the
  /// Fifty window had to be expired first.
  ///
  /// Null when no expiry was needed, which is the ordinary case. It exists
  /// because the expiry happens *during* the apply: a reader that took the
  /// previous frame's clock would report a remaining time from before the jump
  /// that produced the state it is describing.
  final DateTime? effectivePreActionClock;

  /// Seconds left on an open Fifty window at [reference], or null when no
  /// window is visible.
  ///
  /// Mirrors `ClassicHareegGameController.fiftySecondsRemaining` exactly,
  /// including its brief post-expiry grace: the live table holds the ring at
  /// zero for a moment so expiry is legible, then stops showing a window at
  /// all. Clamping to zero forever instead would keep reporting an open window
  /// for the rest of the match — and after a retry advances the clock past
  /// expiry, that is precisely when a false window would appear.
  int? fiftySecondsRemainingAt(DateTime reference) {
    final openedAt = snapshot.fiftyWindowOpenedAt;
    if (openedAt == null) {
      return null;
    }
    final elapsed = reference.difference(openedAt).inSeconds;
    final remaining = snapshot.setup.fiftyTimerSeconds - elapsed;
    if (remaining >= 0) {
      return remaining;
    }
    final graceElapsed = elapsed - snapshot.setup.fiftyTimerSeconds;
    return graceElapsed <= replayFiftyCueExpiryGraceSeconds ? 0 : null;
  }

  /// Seconds left on an open Fifty window, measured at this frame's clock.
  int? get fiftySecondsRemaining => fiftySecondsRemainingAt(clock);
}

/// A refusal to reconstruct, with enough detail to diagnose it.
///
/// [message] is diagnostic text, not user copy: it embeds raw action ids and
/// engine wording. The UI maps [kind] to localized copy instead.
class ReplayTimelineFailure {
  /// Creates a failure.
  const ReplayTimelineFailure({
    required this.kind,
    required this.frameIndex,
    required this.message,
    this.entry,
    this.partialSnapshot,
  });

  /// Why reconstruction stopped.
  final ReplayTimelineFailureKind kind;

  /// The entry that could not be applied, when one is implicated.
  final MatchActionTranscriptEntry? entry;

  /// How many frames had been produced before the refusal.
  final int frameIndex;

  /// State reached before the refusal, for diagnostics only. No surface
  /// renders this as a replay — a truncated match shown as the match is worse
  /// than an honest refusal.
  final ClassicHareegMatchSnapshot? partialSnapshot;

  /// Diagnostic detail. Never user-facing.
  final String message;
}

/// Hands one recorded action to the rules engine.
///
/// Injectable purely so a test can provoke the Fifty expire-and-retry path,
/// which is unreachable from driver-generated transcripts: it exists for
/// matches recorded against a wall clock, where time really did pass between
/// the discard and the action. A probe over 8229 entries from eight completed
/// matches hit it zero times.
///
/// The seam is the *call*, not the controller, so an injecting test still runs
/// a genuine controller and genuine rules — it only decides, once, to answer
/// "not yet".
typedef ReplayApplyHook =
    ApplyActionResult Function(
      ClassicHareegGameController controller,
      String actionId,
    );

ApplyActionResult _defaultApply(
  ClassicHareegGameController controller,
  String actionId,
) {
  return controller.applyAction(actionId);
}

/// The one place a transcript is turned back into match states.
///
/// Both the synchronous verifier and the asynchronous viewer drain this same
/// machine one [advance] at a time, so there is a single round-crossing rule,
/// a single application seam, a single retry, and a single clock. A second
/// loop somewhere else would be a second match-state path.
class ReplayReconstruction {
  /// Creates a reconstruction over [transcript].
  ReplayReconstruction(
    this.transcript, {
    ReplayApplyHook applyHook = _defaultApply,
  }) : _applyHook = applyHook {
    _clock = replayClockEpoch;
    _controller = ClassicHareegGameController.fromSnapshot(
      _initialFor(RoundSeedAlgorithm.exact32),
      now: _now,
    );
  }

  /// Transcript being reconstructed.
  final MatchActionTranscript transcript;

  final ReplayApplyHook _applyHook;
  final List<ReplayFrame> _frames = [];

  late ClassicHareegGameController _controller;
  late DateTime _clock;
  int _entryIndex = 0;
  bool _emittedInitial = false;
  bool _finished = false;
  bool _cancelled = false;
  ReplayTimelineFailure? _failure;
  bool _triedLegacyWeb = false;

  ClassicHareegMatchSnapshot _initialFor(RoundSeedAlgorithm fallback) {
    final initial = transcript.initialSnapshot;
    if (initial.roundSeedAlgorithm != null) return initial;
    return ClassicHareegMatchSnapshot.fromJson({
      ...initial.toJson(),
      'roundSeedAlgorithm': fallback.name,
    });
  }

  DateTime _now() => _clock;

  /// Frames produced so far.
  List<ReplayFrame> get frames => List.unmodifiable(_frames);
  int get frameCount => _frames.length;

  /// Whether every entry has been consumed.
  bool get isDone => _finished || _failure != null || _cancelled;

  /// Why reconstruction refused, when it did.
  ReplayTimelineFailure? get failure => _failure;

  /// Whether the drain was abandoned.
  bool get isCancelled => _cancelled;

  /// Abandons the reconstruction. Further [advance] calls do nothing, so a
  /// completion arriving after a viewer is disposed cannot resume work.
  void cancel() => _cancelled = true;

  /// Produces at most one frame.
  ///
  /// Returns true when a frame was produced, false when the machine is done,
  /// has failed, or was cancelled.
  bool advance() {
    final produced = _advance();
    if (_failure != null &&
        !_triedLegacyWeb &&
        transcript.initialSnapshot.roundSeedAlgorithm == null &&
        _controller.roundNumber > transcript.initialSnapshot.roundNumber &&
        _applyHook == _defaultApply) {
      // Old archives omitted their platform's seed arithmetic. Retry the one
      // historical alternative, from the beginning, never splice two deals or
      // waive an illegal action. Explicitly versioned recordings never retry.
      _triedLegacyWeb = true;
      _clock = replayClockEpoch;
      _controller = ClassicHareegGameController.fromSnapshot(
        _initialFor(RoundSeedAlgorithm.legacyWeb),
        now: _now,
      );
      _frames.clear();
      _entryIndex = 0;
      _emittedInitial = false;
      _finished = false;
      _failure = null;
      return _advance();
    }
    return produced;
  }

  bool _advance() {
    if (isDone) {
      return false;
    }

    if (!_emittedInitial) {
      _emittedInitial = true;
      _emit(
        kind: ReplayFrameKind.initial,
        roundNumber: transcript.initialSnapshot.roundNumber,
        // The archived snapshot is carried through untouched, keeping the
        // `savedAt` it was stored with.
        snapshot: _triedLegacyWeb
            ? _initialFor(RoundSeedAlgorithm.legacyWeb)
            : transcript.initialSnapshot,
      );
      return true;
    }

    if (_entryIndex >= transcript.entries.length) {
      _finished = true;
      return false;
    }

    final entry = transcript.entries[_entryIndex];

    // One round crossing per advance, so a multi-round gap still yields
    // control between deals.
    if (_controller.roundNumber < entry.roundNumber) {
      final next = _controller.nextRoundSnapshot(savedAt: _clock);
      if (next == null) {
        _fail(
          kind: ReplayTimelineFailureKind.roundUnavailable,
          // Wording preserved from the pre-Sprint-05 implementation so
          // existing diagnostic expectations keep matching.
          message:
              'Transcript expected round ${entry.roundNumber} but the match '
              'ended after round ${_controller.roundNumber}.',
        );
        return false;
      }
      _controller = ClassicHareegGameController.fromSnapshot(next, now: _now);
      _emit(
        kind: ReplayFrameKind.roundStart,
        roundNumber: _controller.roundNumber,
        snapshot: next,
      );
      return true;
    }

    final metadataFailure = _validateMetadata(entry);
    if (metadataFailure != null) {
      _failure = metadataFailure;
      return false;
    }

    // The Fifty retry, preserved exactly: an action the original applied after
    // the window expired by wall clock can read as illegal while the synthetic
    // window is still open.
    DateTime? effectivePreActionClock;
    var result = _applyOnce(entry.actionId);
    if (!result.isSuccess && _controller.fiftyClaimant != null) {
      _clock = _clock.add(
        Duration(
          seconds:
              _controller.setup.fiftyTimerSeconds +
              replayFiftyExpiryPaddingSeconds,
        ),
      );
      effectivePreActionClock = _clock;
      result = _applyOnce(entry.actionId);
    }
    if (!result.isSuccess) {
      _fail(
        kind: ReplayTimelineFailureKind.actionRejected,
        entry: entry,
        message:
            'Action ${entry.order} (${entry.actionId}) by ${entry.seat.name} '
            'in round ${entry.roundNumber} was rejected during replay: '
            '${result.message}',
      );
      return false;
    }

    _clock = _clock.add(const Duration(seconds: 1));
    _entryIndex += 1;
    _emit(
      kind: ReplayFrameKind.actionApplied,
      roundNumber: entry.roundNumber,
      snapshot: _controller.toPositionSnapshot(savedAt: _clock),
      appliedEntry: entry,
      effectivePreActionClock: effectivePreActionClock,
    );
    return true;
  }

  /// The single place this codebase hands a recorded action back to the rules
  /// engine. The retry goes through here too, so there is one seam rather than
  /// one seam and a near-copy of it.
  ApplyActionResult _applyOnce(String actionId) =>
      _applyHook(_controller, actionId);

  /// Checks that an entry's metadata describes the state it is about to be
  /// applied to.
  ///
  /// Decoding validates enum *shape*, not correspondence to reconstructed
  /// state, so without this a decodable transcript could attribute a legal
  /// South action to East, render the wrong actor, and feed that to the
  /// analysis coach.
  ///
  /// Equality is the right relation because the recorder captures
  /// seat/phase/round from the controller *before* applying: a probe over 4751
  /// entries from six completed matches found zero mismatches of any kind.
  ///
  /// `legalActionIdsFor` is deliberately NOT used here. The same probe found it
  /// omits 105 of those 4751 real action ids — every `play-meld` form — so a
  /// legality check would reject genuine history.
  ReplayTimelineFailure? _validateMetadata(MatchActionTranscriptEntry entry) {
    if (entry.seat != _controller.currentSeat) {
      return _failureFor(
        ReplayTimelineFailureKind.seatMismatch,
        entry,
        'seat',
        _controller.currentSeat.name,
        entry.seat.name,
      );
    }
    if (entry.phase != _controller.turnPhase) {
      return _failureFor(
        ReplayTimelineFailureKind.phaseMismatch,
        entry,
        'turn phase',
        _controller.turnPhase.name,
        entry.phase.name,
      );
    }
    if (entry.roundNumber != _controller.roundNumber) {
      return _failureFor(
        ReplayTimelineFailureKind.roundRegression,
        entry,
        'round',
        '${_controller.roundNumber}',
        '${entry.roundNumber}',
      );
    }
    return null;
  }

  ReplayTimelineFailure _failureFor(
    ReplayTimelineFailureKind kind,
    MatchActionTranscriptEntry entry,
    String field,
    String expected,
    String found,
  ) {
    return ReplayTimelineFailure(
      kind: kind,
      entry: entry,
      frameIndex: _frames.length,
      partialSnapshot: _controller.toSnapshot(savedAt: _clock),
      message:
          'Transcript entry ${entry.order} names $field "$found" but the '
          'reconstructed match was at "$expected".',
    );
  }

  /// Returns [snapshot] with every collection — including the ones nested
  /// inside table melds — made unmodifiable.
  ///
  /// A frame is a historical position: a reviewer stepping around must find it
  /// exactly as it was. `ClassicHareegMatchSnapshot` keeps the collections it
  /// is handed, so without this a caller could reach into any frame, including
  /// the archived initial one, and quietly rewrite the past.
  static ClassicHareegMatchSnapshot _frozen(
    ClassicHareegMatchSnapshot snapshot,
  ) {
    Map<PlayerSeat, List<HareegCard>> frozenHands() => Map.unmodifiable({
      for (final entry in snapshot.hands.entries)
        entry.key: List<HareegCard>.unmodifiable(entry.value),
    });

    Map<PlayerSeat, List<PlacedMeld>> frozenMelds() => Map.unmodifiable({
      for (final entry in snapshot.tableMelds.entries)
        entry.key: List<PlacedMeld>.unmodifiable([
          for (final meld in entry.value)
            PlacedMeld(
              cards: List<HareegCard>.unmodifiable(meld.cards),
              valueSnapshot: meld.valueSnapshot,
              coverValue: meld.coverValue,
            ),
        ]),
    });

    OpeningState? frozenOpeningState() {
      final opening = snapshot.openingState;
      if (opening == null) {
        return null;
      }
      return OpeningState(
        baseRequirement: opening.baseRequirement,
        currentRequirement: opening.currentRequirement,
        openedSeats: Set<PlayerSeat>.unmodifiable(opening.openedSeats),
        benchmarkOwner: opening.benchmarkOwner,
        isLocked: opening.isLocked,
      );
    }

    return ClassicHareegMatchSnapshot(
      setup: snapshot.setup,
      hands: frozenHands(),
      roundSeedAlgorithm: snapshot.roundSeedAlgorithm,
      turnJournal: snapshot.turnJournal?.frozen(),
      previousDiscardSeat: snapshot.previousDiscardSeat,
      discardNextSequence: snapshot.discardNextSequence,
      lastReturnedPendingDiscard: snapshot.lastReturnedPendingDiscard,
      stock: List<HareegCard>.unmodifiable(snapshot.stock),
      discardPile: List<HareegCard>.unmodifiable(snapshot.discardPile),
      starter: snapshot.starter,
      currentSeat: snapshot.currentSeat,
      turnPhase: snapshot.turnPhase,
      savedAt: snapshot.savedAt,
      seed: snapshot.seed,
      tableMelds: frozenMelds(),
      pendingDiscard: snapshot.pendingDiscard,
      // `OpeningState` keeps the set it is handed, so passing it through would
      // leave one collection in the graph still mutable — and one is enough to
      // rewrite a historical frame.
      openingState: frozenOpeningState(),
      scores: Map<PlayerSeat, int>.unmodifiable(snapshot.scores),
      activeSeats: List<PlayerSeat>.unmodifiable(snapshot.activeSeats),
      roundNumber: snapshot.roundNumber,
      removedSeats: List<PlayerSeat>.unmodifiable(snapshot.removedSeats),
      fiftyWindowOpenedAt: snapshot.fiftyWindowOpenedAt,
      fiftyWindowDiscarder: snapshot.fiftyWindowDiscarder,
      fiftyWindowIsFirstDealtRound: snapshot.fiftyWindowIsFirstDealtRound,
      activeFiftyClaimCardId: snapshot.activeFiftyClaimCardId,
      activeFiftyClaimDiscarder: snapshot.activeFiftyClaimDiscarder,
      activeFiftyClaimIsFirstDealtRound:
          snapshot.activeFiftyClaimIsFirstDealtRound,
      activeFiftyProofActions: snapshot.activeFiftyProofActions == null
          ? null
          : List.unmodifiable(snapshot.activeFiftyProofActions!),
      windowedTakeCardId: snapshot.windowedTakeCardId,
      windowedTakeDiscarder: snapshot.windowedTakeDiscarder,
      windowedTakeIsFirstDealtRound: snapshot.windowedTakeIsFirstDealtRound,
      discardHistoryEvents: List<DiscardEvent>.unmodifiable(
        snapshot.discardHistoryEvents,
      ),
    );
  }

  void _emit({
    required ReplayFrameKind kind,
    required int roundNumber,
    required ClassicHareegMatchSnapshot snapshot,
    MatchActionTranscriptEntry? appliedEntry,
    DateTime? effectivePreActionClock,
  }) {
    _frames.add(
      ReplayFrame(
        index: _frames.length,
        kind: kind,
        roundNumber: roundNumber,
        snapshot: _frozen(snapshot),
        clock: _clock,
        appliedEntry: appliedEntry,
        matchWinner: _controller.scoreView.progress?.matchWinner,
        effectivePreActionClock: effectivePreActionClock,
      ),
    );
  }

  void _fail({
    required ReplayTimelineFailureKind kind,
    required String message,
    MatchActionTranscriptEntry? entry,
  }) {
    _failure = ReplayTimelineFailure(
      kind: kind,
      entry: entry,
      frameIndex: _frames.length,
      partialSnapshot: _controller.toSnapshot(savedAt: _clock),
      message: message,
    );
  }
}

/// Turn phase re-export so replay consumers do not reach into the round file
/// for a type the frame model already exposes.
typedef ReplayTurnPhase = TurnPhase;
