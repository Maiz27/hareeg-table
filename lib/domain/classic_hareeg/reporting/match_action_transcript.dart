import '../game/classic_hareeg_match_snapshot.dart';
import '../game/classic_hareeg_round.dart';
import '../models/player_seat.dart';
import '../persistence/persistence_codec.dart';

/// Schema version implemented by the action transcript wire format.
const int matchActionTranscriptVersion = 1;

/// One domain-level action in a replayable match transcript.
///
/// Entries describe the actual game action applied at the rules-engine seam —
/// not UI gestures, drag paths, tap coordinates, animation timings, or widget
/// state. Player and CPU actions use the identical shape, so the same replay
/// path reconstructs either.
class MatchActionTranscriptEntry {
  /// Creates a transcript entry.
  const MatchActionTranscriptEntry({
    required this.order,
    required this.seat,
    required this.roundNumber,
    required this.phase,
    required this.actionId,
  });

  /// Restores an entry from JSON-compatible data.
  factory MatchActionTranscriptEntry.fromJson(Map<String, Object?> json) {
    final order = asJsonInt(json['order']);
    final seat = PlayerSeat.fromName(asJsonString(json['seat']));
    final roundNumber = asJsonInt(json['roundNumber']);
    final phase = TurnPhase.fromName(asJsonString(json['phase']));
    final actionId = asJsonString(json['actionId']);
    if (order == null ||
        seat == null ||
        roundNumber == null ||
        phase == null ||
        actionId == null) {
      throw const FormatException('Invalid match transcript entry.');
    }
    return MatchActionTranscriptEntry(
      order: order,
      seat: seat,
      roundNumber: roundNumber,
      phase: phase,
      actionId: actionId,
    );
  }

  /// Monotonic order across the whole match.
  final int order;

  /// Seat that acted.
  final PlayerSeat seat;

  /// One-based dealt round the action belonged to.
  final int roundNumber;

  /// Turn phase before the action was applied.
  final TurnPhase phase;

  /// Action id applied at the controller seam.
  final String actionId;

  /// Converts the entry to JSON-compatible data.
  Map<String, Object?> toJson() => {
    'order': order,
    'seat': seat.name,
    'roundNumber': roundNumber,
    'phase': phase.name,
    'actionId': actionId,
  };
}

/// A deterministic, domain-level action transcript for a match.
///
/// The transcript pairs a base [initialSnapshot] — the match state before any
/// recorded action — with the ordered [entries] applied from there. Replaying
/// the entries against the base snapshot (with the deterministic next-round
/// deal between rounds) reconstructs the reported match state without depending
/// on UI gestures or animation timing.
class MatchActionTranscript {
  /// Creates a transcript.
  MatchActionTranscript({
    required this.initialSnapshot,
    required Iterable<MatchActionTranscriptEntry> entries,
  }) : entries = List.unmodifiable(entries);

  /// Restores a transcript from JSON-compatible data.
  factory MatchActionTranscript.fromJson(Map<String, Object?> json) {
    final version = asJsonInt(json['version']);
    if (version != matchActionTranscriptVersion) {
      throw FormatException(
        'Unsupported match transcript version $version; '
        'expected $matchActionTranscriptVersion.',
      );
    }
    final initialJson = asJsonMap(json['initialSnapshot']);
    final entriesJson = asJsonList(json['entries']);
    if (initialJson == null || entriesJson == null) {
      throw const FormatException('Invalid match transcript.');
    }
    return MatchActionTranscript(
      initialSnapshot: ClassicHareegMatchSnapshot.fromJson(initialJson),
      entries: [
        for (final raw in entriesJson)
          MatchActionTranscriptEntry.fromJson(
            asJsonMap(raw) ??
                (throw const FormatException('Invalid transcript entry.')),
          ),
      ],
    );
  }

  /// Match state before the first recorded action.
  final ClassicHareegMatchSnapshot initialSnapshot;

  /// Ordered actions applied from [initialSnapshot].
  final List<MatchActionTranscriptEntry> entries;

  /// Whether the transcript holds no actions.
  bool get isEmpty => entries.isEmpty;

  /// Converts the transcript to JSON-compatible data.
  Map<String, Object?> toJson() => {
    'version': matchActionTranscriptVersion,
    'initialSnapshot': initialSnapshot.toJson(),
    'entries': [for (final entry in entries) entry.toJson()],
  };
}
