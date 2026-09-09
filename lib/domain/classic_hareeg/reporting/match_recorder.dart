import '../game/classic_hareeg_action.dart';
import '../game/classic_hareeg_match_snapshot.dart';
import '../game/classic_hareeg_round.dart';
import '../history/match_fifty_counters.dart';
import '../models/player_seat.dart';
import '../persistence/persistence_codec.dart';
import 'match_action_transcript.dart';
import 'match_diagnostic_event.dart';
import 'match_diagnostic_log.dart';

/// Schema version implemented by the recorder state wire format.
const int matchRecorderStateVersion = 1;

/// The part of a [MatchRecorder] that must outlive the process.
///
/// Before this existed, the recorder was created by the game screen and died
/// with it, so a match closed and resumed lost every action from before the
/// close and could never replay as a whole. Persisting this alongside the
/// resume data is what makes a transcript span the entire match.
class MatchRecorderState {
  /// Creates recorder state.
  MatchRecorderState({
    required this.initialSnapshot,
    required Iterable<MatchActionTranscriptEntry> entries,
    required this.nextOrder,
    required this.fiftyCounters,
  }) : entries = List.unmodifiable(entries);

  /// Restores recorder state from JSON-compatible data.
  factory MatchRecorderState.fromJson(Map<String, Object?> json) {
    final version = asJsonInt(json['version']);
    if (version != matchRecorderStateVersion) {
      throw FormatException(
        'Unsupported recorder state version $version; '
        'expected $matchRecorderStateVersion.',
      );
    }

    final nextOrder = asJsonInt(json['nextOrder']);
    final rawEntries = asJsonList(json['entries']);
    final countersJson = asJsonMap(json['fiftyCounters']);
    if (nextOrder == null || rawEntries == null || countersJson == null) {
      throw const FormatException('Invalid recorder state.');
    }
    if (nextOrder < 0) {
      throw FormatException('Invalid recorder state order: $nextOrder.');
    }

    final rawInitial = json['initialSnapshot'];
    final initialJson = asJsonMap(rawInitial);
    if (rawInitial != null && initialJson == null) {
      throw const FormatException('Invalid recorder initial snapshot.');
    }

    final entries = <MatchActionTranscriptEntry>[];
    var previousOrder = -1;
    for (final raw in rawEntries) {
      final entry = MatchActionTranscriptEntry.fromJson(
        asJsonMap(raw) ??
            (throw const FormatException('Invalid recorder entry.')),
      );
      // Order is a strictly increasing match-wide counter. A duplicate or a
      // step backwards means the state was reordered or merged, and restoring
      // it would append onto a transcript that no longer describes one match.
      if (entry.order <= previousOrder) {
        throw FormatException(
          'Non-monotonic recorder entry order: ${entry.order} '
          'after $previousOrder.',
        );
      }
      previousOrder = entry.order;
      entries.add(entry);
    }

    // A stale counter would make the next recorded action collide with, or sit
    // before, an action already in the transcript.
    if (nextOrder <= previousOrder) {
      throw FormatException(
        'Recorder next order $nextOrder is not past the last '
        'recorded order $previousOrder.',
      );
    }

    return MatchRecorderState(
      initialSnapshot: initialJson == null
          ? null
          : ClassicHareegMatchSnapshot.fromJson(initialJson),
      entries: entries,
      nextOrder: nextOrder,
      fiftyCounters: MatchFiftyCounters.fromJson(countersJson),
    );
  }

  /// Match state before the first recorded action, when one was captured.
  final ClassicHareegMatchSnapshot? initialSnapshot;

  /// Actions recorded so far.
  final List<MatchActionTranscriptEntry> entries;

  /// Order the next recorded action will take.
  ///
  /// Carried explicitly rather than derived from `entries.length` so a restored
  /// recorder continues the match-wide counter instead of restarting it.
  final int nextOrder;

  /// Per-seat Fifty tally.
  ///
  /// The recorder state is the single canonical owner of these counters.
  /// Nothing else stores its own copy — a second copy is a second thing to keep
  /// in sync, and the two would eventually disagree.
  final MatchFiftyCounters fiftyCounters;

  /// Converts the state to JSON-compatible data.
  Map<String, Object?> toJson() => {
    'version': matchRecorderStateVersion,
    if (initialSnapshot != null) 'initialSnapshot': initialSnapshot!.toJson(),
    'entries': [for (final entry in entries) entry.toJson()],
    'nextOrder': nextOrder,
    'fiftyCounters': fiftyCounters.toJson(),
  };
}

/// Accumulates a match's diagnostic event log and replayable action transcript.
///
/// One recorder outlives the per-round controllers: the game screen creates it
/// at match start and hands the same instance to each round's controller, so
/// the transcript and diagnostics span the whole match instead of resetting on
/// every deal. The controller records into it at the single `applyAction` seam;
/// the UI records coach and persistence boundaries directly.
///
/// The recorder lives in the rules-engine layer and stays Flutter-free
/// (ADR-0001): it only depends on domain models.
class MatchRecorder {
  /// Creates a recorder with a diagnostic log capped at [diagnosticCapacity].
  MatchRecorder({int diagnosticCapacity = 200})
    : diagnostics = MatchDiagnosticLog(capacity: diagnosticCapacity);

  /// Rebuilds a recorder from persisted [state].
  ///
  /// The diagnostic log is deliberately *not* restored: it is a capped rolling
  /// buffer for the current session's troubleshooting, not durable match data.
  /// The transcript and the Fifty counters are what must survive.
  factory MatchRecorder.restore(
    MatchRecorderState state, {
    int diagnosticCapacity = 200,
  }) {
    final recorder = MatchRecorder(diagnosticCapacity: diagnosticCapacity)
      .._initialSnapshot = state.initialSnapshot
      .._nextOrder = state.nextOrder
      .._fiftyCounters = state.fiftyCounters
      .._restored = true;
    recorder._entries.addAll(state.entries);
    return recorder;
  }

  /// Rolling, capped diagnostic event log included in exported reports.
  final MatchDiagnosticLog diagnostics;

  final List<MatchActionTranscriptEntry> _entries = [];
  ClassicHareegMatchSnapshot? _initialSnapshot;
  int _nextOrder = 0;
  MatchFiftyCounters _fiftyCounters = MatchFiftyCounters.empty();
  bool _restored = false;

  /// Per-seat Fifty attempts and successes accumulated this match.
  MatchFiftyCounters get fiftyCounters => _fiftyCounters;

  /// Captures the match's starting state, the first time only.
  ///
  /// Called by each controller as it is constructed. Round 1 (or the resumed
  /// round, for a restored match) wins; later rounds are no-ops because the
  /// transcript replays forward from this single base snapshot.
  ///
  /// A restored recorder ignores this entirely. Its base snapshot is the one
  /// the match actually started from; letting the resumed round overwrite it
  /// would rebase the transcript mid-match and throw away every earlier action.
  void captureInitialState(ClassicHareegMatchSnapshot snapshot) {
    if (_restored) {
      return;
    }
    _initialSnapshot ??= snapshot;
  }

  /// Appends a successfully-applied action to the transcript.
  ///
  /// An explicit claim-fifty action counts as a Fifty attempt here, at the one
  /// place every applied action passes through, so an attempt cannot be missed
  /// by a caller forgetting to tally it separately.
  void recordAction({
    required PlayerSeat seat,
    required int roundNumber,
    required TurnPhase phase,
    required String actionId,
  }) {
    _entries.add(
      MatchActionTranscriptEntry(
        order: _nextOrder++,
        seat: seat,
        roundNumber: roundNumber,
        phase: phase,
        actionId: actionId,
      ),
    );

    if (actionId == ClassicHareegActionIds.claimFifty) {
      _fiftyCounters = _fiftyCounters.withAttempt(seat);
    }
  }

  /// Records that [seat]'s earlier Fifty claim was proven in its favour.
  ///
  /// Separate from [recordAction] because the proof arrives later, when the
  /// round resolves. Only an explicit claim can succeed: a windowed take that
  /// happens to be a Fifty was never a claim and is not counted.
  void recordFiftySuccess(PlayerSeat seat) {
    _fiftyCounters = _fiftyCounters.withSuccess(seat);
  }

  /// A legacy save can resume an in-flight claim with no recorder history.
  /// Such a claim must not manufacture an attempt or make completion throw.
  bool hasRecordedFiftyClaim(PlayerSeat seat, int roundNumber) => _entries.any(
    (entry) =>
        entry.seat == seat &&
        entry.roundNumber == roundNumber &&
        entry.actionId == ClassicHareegActionIds.claimFifty,
  );

  /// Captures the durable part of this recorder.
  MatchRecorderState toState() {
    return MatchRecorderState(
      initialSnapshot: _initialSnapshot,
      entries: _entries,
      nextOrder: _nextOrder,
      fiftyCounters: _fiftyCounters,
    );
  }

  /// Replayable transcript captured so far, or null when nothing is recordable
  /// yet (no base snapshot, or no actions applied).
  MatchActionTranscript? get transcript {
    final initial = _initialSnapshot;
    if (initial == null || _entries.isEmpty) {
      return null;
    }
    return MatchActionTranscript(initialSnapshot: initial, entries: _entries);
  }

  /// Records a coaching hint trigger or coach feedback identifier.
  void recordCoachHint({
    required int roundNumber,
    required String hintId,
    PlayerSeat? seat,
    TurnPhase? phase,
    Map<String, Object?> data = const {},
  }) {
    diagnostics.record(
      category: MatchDiagnosticCategory.coach,
      type: 'coachHint',
      roundNumber: roundNumber,
      seat: seat,
      phase: phase,
      // Canonical hintId wins: a stray 'hintId' in caller data must not
      // override the function's argument, so it is spread first.
      data: {...data, 'hintId': hintId},
    );
  }

  /// Records a save / load / resume persistence boundary.
  void recordPersistence({
    required String type,
    required int roundNumber,
    PlayerSeat? seat,
    Map<String, Object?> data = const {},
  }) {
    diagnostics.record(
      category: MatchDiagnosticCategory.persistence,
      type: type,
      roundNumber: roundNumber,
      seat: seat,
      data: data,
    );
  }
}
