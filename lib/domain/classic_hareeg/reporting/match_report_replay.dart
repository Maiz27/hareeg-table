import '../game/classic_hareeg_game_controller.dart';
import '../game/classic_hareeg_match_snapshot.dart';
import '../models/player_seat.dart';
import 'classic_hareeg_match_report.dart';
import 'match_action_transcript.dart';

/// Outcome class for a transcript replay.
enum MatchReportReplayStatus {
  /// The reconstructed state matched the reported snapshot.
  matched,

  /// Replay completed but the reconstructed state diverged.
  mismatch,

  /// Replay could not run because the report carries no transcript.
  noTranscript,
}

/// Result of replaying a report's action transcript.
///
/// On a mismatch, [mismatches] holds human-readable lines covering round, seat,
/// turn phase, scores, and relevant table state so a reproduction failure
/// points at the specific divergence instead of a bare assertion.
class MatchReportReplayResult {
  /// Creates a replay result.
  const MatchReportReplayResult({
    required this.status,
    this.mismatches = const [],
    this.reconstructed,
    this.note,
  });

  /// Replay outcome.
  final MatchReportReplayStatus status;

  /// Human-readable divergence lines, empty when [matches] is true.
  final List<String> mismatches;

  /// Reconstructed final snapshot, when replay ran to completion.
  final ClassicHareegMatchSnapshot? reconstructed;

  /// Optional explanation (e.g. why replay could not run).
  final String? note;

  /// Whether replay confirmed the reported state.
  bool get matches => status == MatchReportReplayStatus.matched;
}

/// Replays [report]'s transcript and compares the reconstructed state to the
/// report snapshot.
///
/// Returns [MatchReportReplayStatus.noTranscript] when the report has no
/// transcript to replay. Otherwise restores the transcript's base snapshot,
/// applies every recorded action (crossing rounds via the deterministic
/// next-round deal), and diffs the result against [report]'s snapshot.
MatchReportReplayResult replayMatchReport(ClassicHareegMatchReport report) {
  final transcript = report.transcript;
  if (transcript == null) {
    return const MatchReportReplayResult(
      status: MatchReportReplayStatus.noTranscript,
      note: 'Report has no action transcript to replay.',
    );
  }
  return replayTranscript(transcript, expected: report.snapshot);
}

/// Replays a [transcript] from its base snapshot, optionally comparing the
/// reconstructed state to [expected].
///
/// When [expected] is null the result is always
/// [MatchReportReplayStatus.matched] with the reconstructed snapshot attached,
/// so callers can inspect the replayed state without a reference snapshot.
MatchReportReplayResult replayTranscript(
  MatchActionTranscript transcript, {
  ClassicHareegMatchSnapshot? expected,
}) {
  // A synthetic, steadily advancing clock — mirrors the full-match driver so
  // Fifty windows behave during replay without depending on wall-clock timing.
  var clock = DateTime.utc(2026, 1, 1);
  DateTime now() => clock;

  var controller = ClassicHareegGameController.fromSnapshot(
    transcript.initialSnapshot,
    now: now,
  );

  for (final entry in transcript.entries) {
    // Cross deterministic round boundaries until the controller is on the
    // round this entry belongs to.
    while (controller.roundNumber < entry.roundNumber) {
      final next = controller.nextRoundSnapshot(savedAt: now());
      if (next == null) {
        return MatchReportReplayResult(
          status: MatchReportReplayStatus.mismatch,
          mismatches: [
            'Transcript expected round ${entry.roundNumber} but the match '
                'ended after round ${controller.roundNumber}.',
          ],
          reconstructed: controller.toSnapshot(savedAt: now()),
        );
      }
      controller = ClassicHareegGameController.fromSnapshot(next, now: now);
    }

    var result = controller.applyAction(entry.actionId);
    if (!result.isSuccess) {
      // A non-claim action that the original applied after the Fifty window
      // expired by wall-clock can read as illegal while the synthetic window
      // is still open. Expire the window and retry once, as the driver does.
      if (controller.fiftyClaimant != null) {
        clock = clock.add(
          Duration(seconds: controller.setup.fiftyTimerSeconds + 30),
        );
        result = controller.applyAction(entry.actionId);
      }
    }
    if (!result.isSuccess) {
      return MatchReportReplayResult(
        status: MatchReportReplayStatus.mismatch,
        mismatches: [
          'Action ${entry.order} (${entry.actionId}) by ${entry.seat.name} '
              'in round ${entry.roundNumber} was rejected during replay: '
              '${result.message}',
        ],
        reconstructed: controller.toSnapshot(savedAt: now()),
      );
    }
    clock = clock.add(const Duration(seconds: 1));
  }

  final reconstructed = controller.toSnapshot(savedAt: now());
  if (expected == null) {
    return MatchReportReplayResult(
      status: MatchReportReplayStatus.matched,
      reconstructed: reconstructed,
    );
  }

  final mismatches = describeSnapshotMismatch(
    expected: expected,
    actual: reconstructed,
  );
  return MatchReportReplayResult(
    status: mismatches.isEmpty
        ? MatchReportReplayStatus.matched
        : MatchReportReplayStatus.mismatch,
    mismatches: mismatches,
    reconstructed: reconstructed,
  );
}

/// Returns human-readable lines describing how [actual] diverges from
/// [expected], or an empty list when the meaningful game state matches.
///
/// Volatile fields (save timestamp, Fifty window clock readings) are ignored —
/// only reproducible game state is compared.
List<String> describeSnapshotMismatch({
  required ClassicHareegMatchSnapshot expected,
  required ClassicHareegMatchSnapshot actual,
}) {
  final lines = <String>[];

  if (expected.roundNumber != actual.roundNumber) {
    lines.add(
      'round: expected ${expected.roundNumber}, got ${actual.roundNumber}',
    );
  }
  if (expected.currentSeat != actual.currentSeat) {
    lines.add(
      'current seat: expected ${expected.currentSeat.name}, '
      'got ${actual.currentSeat.name}',
    );
  }
  if (expected.turnPhase != actual.turnPhase) {
    lines.add(
      'turn phase: expected ${expected.turnPhase.name}, '
      'got ${actual.turnPhase.name}',
    );
  }

  for (final seat in PlayerSeat.values) {
    final want = expected.scores[seat] ?? 0;
    final got = actual.scores[seat] ?? 0;
    if (want != got) {
      lines.add('score ${seat.name}: expected $want, got $got');
    }
  }

  final wantRemoved = _seatNames(expected.removedSeats);
  final gotRemoved = _seatNames(actual.removedSeats);
  if (!_listEquals(wantRemoved, gotRemoved)) {
    lines.add('removed seats: expected $wantRemoved, got $gotRemoved');
  }
  final wantActive = expected.activeSeats.map((s) => s.name).toList();
  final gotActive = actual.activeSeats.map((s) => s.name).toList();
  if (!_listEquals(wantActive, gotActive)) {
    lines.add('active seats: expected $wantActive, got $gotActive');
  }

  if (expected.pendingDiscard?.id != actual.pendingDiscard?.id) {
    lines.add(
      'pending discard: expected ${expected.pendingDiscard?.id}, '
      'got ${actual.pendingDiscard?.id}',
    );
  }

  for (final seat in PlayerSeat.values) {
    final want = _sortedIds(expected.hands[seat]?.map((c) => c.id));
    final got = _sortedIds(actual.hands[seat]?.map((c) => c.id));
    if (!_listEquals(want, got)) {
      lines.add('hand ${seat.name}: expected $want, got $got');
    }
  }

  final wantStock = _sortedIds(expected.stock.map((c) => c.id));
  final gotStock = _sortedIds(actual.stock.map((c) => c.id));
  if (!_listEquals(wantStock, gotStock)) {
    lines.add('stock count: expected ${wantStock.length}, '
        'got ${gotStock.length}');
  }

  final wantDiscard = expected.discardPile.map((c) => c.id).toList();
  final gotDiscard = actual.discardPile.map((c) => c.id).toList();
  if (!_listEquals(wantDiscard, gotDiscard)) {
    lines.add('discard pile: expected $wantDiscard, got $gotDiscard');
  }

  for (final seat in PlayerSeat.values) {
    final want = _meldSignature(expected, seat);
    final got = _meldSignature(actual, seat);
    if (!_listEquals(want, got)) {
      lines.add('table melds ${seat.name}: expected $want, got $got');
    }
  }

  return lines;
}

List<String> _meldSignature(ClassicHareegMatchSnapshot snapshot, PlayerSeat seat) {
  final melds = snapshot.tableMelds[seat] ?? const [];
  return [for (final meld in melds) meld.cards.map((c) => c.id).join('+')];
}

List<String> _sortedIds(Iterable<String>? ids) {
  final list = (ids ?? const []).toList()..sort();
  return list;
}

List<String> _seatNames(List<PlayerSeat> seats) {
  return (seats.map((s) => s.name).toList())..sort();
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
