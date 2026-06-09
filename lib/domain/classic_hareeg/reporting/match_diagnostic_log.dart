import '../game/classic_hareeg_round.dart';
import '../models/player_seat.dart';
import '../persistence/persistence_codec.dart';
import 'match_diagnostic_event.dart';

/// Capped, ordered ring buffer of [MatchDiagnosticEvent]s.
///
/// The log keeps the most recent [capacity] events so an exported report stays
/// small enough to share while still describing the context immediately before
/// a problem was reported. Older events are dropped once the cap is exceeded;
/// [droppedCount] records how many so tooling can show that the log was
/// truncated rather than implying it captured the whole match.
class MatchDiagnosticLog {
  /// Creates a diagnostic log capped at [capacity] events.
  MatchDiagnosticLog({this.capacity = 200})
    : assert(capacity > 0, 'Diagnostic log capacity must be positive.');

  /// Restores a log from JSON-compatible data.
  factory MatchDiagnosticLog.fromJson(Map<String, Object?> json) {
    final capacity = asJsonInt(json['capacity']) ?? 200;
    final eventsJson = asJsonList(json['events']) ?? const [];
    final log = MatchDiagnosticLog(capacity: capacity < 1 ? 200 : capacity);
    var maxOrder = -1;
    for (final raw in eventsJson) {
      final map = asJsonMap(raw);
      if (map == null) {
        throw const FormatException('Invalid match diagnostic event entry.');
      }
      final event = MatchDiagnosticEvent.fromJson(map);
      log._events.add(event);
      if (event.order > maxOrder) {
        maxOrder = event.order;
      }
    }
    log._nextOrder = maxOrder + 1;
    log._droppedCount = asJsonInt(json['droppedCount']) ?? 0;
    return log;
  }

  /// Maximum number of events retained.
  final int capacity;

  final List<MatchDiagnosticEvent> _events = [];
  int _nextOrder = 0;
  int _droppedCount = 0;

  /// Recorded events, oldest first.
  List<MatchDiagnosticEvent> get events => List.unmodifiable(_events);

  /// Number of events dropped because the cap was exceeded.
  int get droppedCount => _droppedCount;

  /// Whether the log holds no events.
  bool get isEmpty => _events.isEmpty;

  /// Records a structured event, assigning the next monotonic order.
  ///
  /// Returns the recorded event. Drops the oldest event(s) when the cap is
  /// exceeded, incrementing [droppedCount].
  MatchDiagnosticEvent record({
    required MatchDiagnosticCategory category,
    required String type,
    required int roundNumber,
    PlayerSeat? seat,
    TurnPhase? phase,
    Map<String, Object?> data = const {},
  }) {
    final event = MatchDiagnosticEvent(
      order: _nextOrder++,
      category: category,
      type: type,
      roundNumber: roundNumber,
      seat: seat,
      phase: phase,
      data: data,
    );
    _events.add(event);
    while (_events.length > capacity) {
      _events.removeAt(0);
      _droppedCount++;
    }
    return event;
  }

  /// Converts the log to JSON-compatible data.
  Map<String, Object?> toJson() => {
    'capacity': capacity,
    'droppedCount': _droppedCount,
    'events': [for (final event in _events) event.toJson()],
  };
}
