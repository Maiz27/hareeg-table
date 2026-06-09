import '../game/classic_hareeg_match_snapshot.dart';
import '../game/classic_hareeg_round.dart';
import '../models/player_seat.dart';
import 'match_action_transcript.dart';
import 'match_diagnostic_event.dart';
import 'match_diagnostic_log.dart';

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

  /// Rolling, capped diagnostic event log included in exported reports.
  final MatchDiagnosticLog diagnostics;

  final List<MatchActionTranscriptEntry> _entries = [];
  ClassicHareegMatchSnapshot? _initialSnapshot;
  int _nextOrder = 0;

  /// Captures the match's starting state, the first time only.
  ///
  /// Called by each controller as it is constructed. Round 1 (or the resumed
  /// round, for a restored match) wins; later rounds are no-ops because the
  /// transcript replays forward from this single base snapshot.
  void captureInitialState(ClassicHareegMatchSnapshot snapshot) {
    _initialSnapshot ??= snapshot;
  }

  /// Appends a successfully-applied action to the transcript.
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
