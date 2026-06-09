import '../game/classic_hareeg_round.dart';
import '../models/player_seat.dart';
import '../persistence/persistence_codec.dart';

/// Stable category for a [MatchDiagnosticEvent].
///
/// Report tooling filters the diagnostic stream by category, so the set is
/// kept small and meaningful rather than mirroring every action kind.
enum MatchDiagnosticCategory {
  /// A rules-validation outcome: an illegal action or a penalty revert.
  rules,

  /// A scoring transition (penalty charge or round-result fold).
  scoring,

  /// A Fifty window opening, closing, or being claimed.
  fifty,

  /// A round finishing.
  finish,

  /// A save / load / resume boundary.
  persistence,

  /// A notable CPU decision.
  ai,

  /// A coaching hint trigger or coach feedback identifier.
  coach;

  /// Parses a serialized category name.
  static MatchDiagnosticCategory? fromName(String? name) {
    if (name == null) {
      return null;
    }
    for (final category in MatchDiagnosticCategory.values) {
      if (category.name == name) {
        return category;
      }
    }
    return null;
  }
}

/// One structured entry in the rolling match diagnostic log.
///
/// Events deliberately carry only game-state context (seat, round, phase, and a
/// small domain payload of card/action identifiers). They never contain
/// preferences, locale, player names, or other user-entered data so a report
/// can be attached to a bug report safely.
class MatchDiagnosticEvent {
  /// Creates a diagnostic event.
  const MatchDiagnosticEvent({
    required this.order,
    required this.category,
    required this.type,
    required this.roundNumber,
    this.seat,
    this.phase,
    this.data = const {},
  });

  /// Restores an event from JSON-compatible data.
  factory MatchDiagnosticEvent.fromJson(Map<String, Object?> json) {
    final order = asJsonInt(json['order']);
    final category = MatchDiagnosticCategory.fromName(
      asJsonString(json['category']),
    );
    final type = asJsonString(json['type']);
    final roundNumber = asJsonInt(json['roundNumber']);
    if (order == null ||
        category == null ||
        type == null ||
        roundNumber == null) {
      throw const FormatException('Invalid match diagnostic event.');
    }
    return MatchDiagnosticEvent(
      order: order,
      category: category,
      type: type,
      roundNumber: roundNumber,
      seat: PlayerSeat.fromName(asJsonString(json['seat'])),
      phase: TurnPhase.fromName(asJsonString(json['phase'])),
      data: asJsonMap(json['data']) ?? const {},
    );
  }

  /// Monotonic order assigned by the log; stable across serialization.
  final int order;

  /// Event category.
  final MatchDiagnosticCategory category;

  /// Stable event type within the category (e.g. `invalidAction`).
  final String type;

  /// One-based dealt round the event belongs to.
  final int roundNumber;

  /// Seat the event concerns, when applicable.
  final PlayerSeat? seat;

  /// Turn phase the event was captured in, when applicable.
  final TurnPhase? phase;

  /// Structured, JSON-safe payload of domain identifiers.
  final Map<String, Object?> data;

  /// Converts the event to JSON-compatible data.
  Map<String, Object?> toJson() => {
    'order': order,
    'category': category.name,
    'type': type,
    'roundNumber': roundNumber,
    if (seat != null) 'seat': seat!.name,
    if (phase != null) 'phase': phase!.name,
    if (data.isNotEmpty) 'data': data,
  };
}
