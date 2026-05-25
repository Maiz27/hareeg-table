import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../persistence/persistence_codec.dart';

/// Type of discard-memory event recorded during one round.
enum DiscardEventKind {
  /// A seat discarded a card to the pile.
  discard,

  /// A seat picked up the previous discard.
  pickup,
}

/// One attributed discard-memory event.
class DiscardEvent {
  /// Creates a discard-memory event.
  const DiscardEvent({
    required this.seat,
    required this.card,
    required this.kind,
    required this.sequence,
  });

  /// Restores an event from persisted JSON-compatible data.
  factory DiscardEvent.fromJson(Map<String, Object?> json) {
    final seat = PlayerSeat.fromName(asJsonString(json['seat']));
    final cardJson = asJsonMap(json['card']);
    final kindName = asJsonString(json['kind']);
    final sequence = asJsonInt(json['sequence']);
    if (seat == null ||
        cardJson == null ||
        kindName == null ||
        sequence == null) {
      throw const FormatException('Invalid discard event.');
    }
    final kind = _discardEventKindByName(kindName);
    if (kind == null) {
      throw FormatException('Unknown discard event kind: $kindName.');
    }
    return DiscardEvent(
      seat: seat,
      card: HareegCard.fromJson(cardJson),
      kind: kind,
      sequence: sequence,
    );
  }

  /// Seat that produced the event.
  final PlayerSeat seat;

  /// Card involved in the event.
  final HareegCard card;

  /// Event kind.
  final DiscardEventKind kind;

  /// Monotonic sequence number within this round.
  final int sequence;

  /// Converts the event to JSON-compatible data.
  Map<String, Object?> toJson() {
    return {
      'seat': seat.name,
      'card': card.toJson(),
      'kind': kind.name,
      'sequence': sequence,
    };
  }
}

DiscardEventKind? _discardEventKindByName(String name) {
  for (final kind in DiscardEventKind.values) {
    if (kind.name == name) {
      return kind;
    }
  }
  return null;
}

/// Read-only discard-memory view consumed by CPU strategies.
abstract interface class DiscardHistoryView {
  /// Last [n] discards by [seat], newest first.
  Iterable<HareegCard> lastDiscardsBy(PlayerSeat seat, int n);

  /// Last [n] discard-pile pickups by [seat], newest first.
  Iterable<HareegCard> lastPickupsBy(PlayerSeat seat, int n);

  /// Whether a concrete card identity has been seen in the pile this round.
  bool cardSeenAt(CardRank rank, CardSuit suit);

  /// Last event involving a concrete card identity, if any.
  DiscardEvent? lastSeenAt(CardRank rank, CardSuit suit);

  /// Count of discarded cards with [rank] this round.
  int discardsCount(CardRank rank);

  /// Number of jokers discarded this round.
  int get jokersDiscarded;
}

/// Empty discard-memory view used by tests and fallback adapters.
final class EmptyDiscardHistoryView implements DiscardHistoryView {
  /// Creates an empty discard-memory view.
  const EmptyDiscardHistoryView();

  @override
  Iterable<HareegCard> lastDiscardsBy(PlayerSeat seat, int n) => const [];

  @override
  Iterable<HareegCard> lastPickupsBy(PlayerSeat seat, int n) => const [];

  @override
  bool cardSeenAt(CardRank rank, CardSuit suit) => false;

  @override
  DiscardEvent? lastSeenAt(CardRank rank, CardSuit suit) => null;

  @override
  int discardsCount(CardRank rank) => 0;

  @override
  int get jokersDiscarded => 0;
}

/// Per-round, per-seat-attributed discard memory.
class DiscardHistory implements DiscardHistoryView {
  /// Creates an empty discard history.
  DiscardHistory()
    : _discardIndicesBySeat = _emptySeatIndexMap(),
      _pickupIndicesBySeat = _emptySeatIndexMap(),
      _countsByRank = List<int>.filled(CardRank.values.length, 0);

  /// Restores discard memory from persisted JSON-compatible data.
  ///
  /// The wire format only persists the chronological event stream; per-seat
  /// indices, rank counts, and identity counts are rebuilt by replaying each
  /// event in order so the live invariants stay defined in one place
  /// (recordDiscard/recordPickup).
  factory DiscardHistory.fromJson(Map<String, Object?> json) {
    final eventsJson = asJsonList(json['events']);
    if (eventsJson == null) {
      throw const FormatException('Invalid discard history events.');
    }
    final history = DiscardHistory();
    for (final raw in eventsJson) {
      final eventJson = asJsonMap(raw);
      if (eventJson == null) {
        throw const FormatException('Invalid discard event entry.');
      }
      final event = DiscardEvent.fromJson(eventJson);
      switch (event.kind) {
        case DiscardEventKind.discard:
          history.recordDiscard(event.seat, event.card);
        case DiscardEventKind.pickup:
          history.recordPickup(event.seat, event.card);
      }
    }
    return history;
  }

  final List<DiscardEvent> _events = [];
  final Map<PlayerSeat, List<int>> _discardIndicesBySeat;
  final Map<PlayerSeat, List<int>> _pickupIndicesBySeat;
  final List<int> _countsByRank;
  final Map<String, int> _identityCounts = {};
  int _jokersDiscarded = 0;
  int _nextSequence = 0;

  /// Full chronological event stream, oldest first.
  Iterable<DiscardEvent> get events => List.unmodifiable(_events);

  /// Records a card discarded by [seat].
  void recordDiscard(PlayerSeat seat, HareegCard card) {
    final event = _append(
      seat: seat,
      card: card,
      kind: DiscardEventKind.discard,
    );
    _discardIndicesBySeat[seat]!.add(_events.length - 1);
    _addDiscardIdentity(event.card);
  }

  /// Records a previous-discard pickup by [seat].
  void recordPickup(PlayerSeat seat, HareegCard card) {
    _append(seat: seat, card: card, kind: DiscardEventKind.pickup);
    _pickupIndicesBySeat[seat]!.add(_events.length - 1);
  }

  /// Retracts the most recently recorded matching event.
  ///
  /// A missing event is tolerated so restored matches with a pending discard
  /// but intentionally fresh CPU memory can still return that discard.
  void retract({
    required PlayerSeat seat,
    required HareegCard card,
    required DiscardEventKind kind,
  }) {
    if (_events.isEmpty) {
      return;
    }

    final event = _events.last;
    assert(
      event.seat == seat && event.card.id == card.id && event.kind == kind,
      'Discard history retract must target the latest matching event.',
    );
    if (event.seat != seat || event.card.id != card.id || event.kind != kind) {
      return;
    }

    _events.removeLast();
    switch (kind) {
      case DiscardEventKind.discard:
        _discardIndicesBySeat[seat]!.removeLast();
        _removeDiscardIdentity(event.card);
      case DiscardEventKind.pickup:
        _pickupIndicesBySeat[seat]!.removeLast();
    }
  }

  /// Clears all per-round memory.
  void resetForNewRound() {
    _events.clear();
    for (final indices in _discardIndicesBySeat.values) {
      indices.clear();
    }
    for (final indices in _pickupIndicesBySeat.values) {
      indices.clear();
    }
    for (var i = 0; i < _countsByRank.length; i += 1) {
      _countsByRank[i] = 0;
    }
    _identityCounts.clear();
    _jokersDiscarded = 0;
    _nextSequence = 0;
  }

  @override
  Iterable<HareegCard> lastDiscardsBy(PlayerSeat seat, int n) {
    return _lastCardsFor(_discardIndicesBySeat[seat] ?? const [], n);
  }

  @override
  Iterable<HareegCard> lastPickupsBy(PlayerSeat seat, int n) {
    return _lastCardsFor(_pickupIndicesBySeat[seat] ?? const [], n);
  }

  @override
  bool cardSeenAt(CardRank rank, CardSuit suit) {
    return (_identityCounts[CardIdentity(rank: rank, suit: suit).key] ?? 0) > 0;
  }

  @override
  DiscardEvent? lastSeenAt(CardRank rank, CardSuit suit) {
    final identity = CardIdentity(rank: rank, suit: suit);
    for (var i = _events.length - 1; i >= 0; i -= 1) {
      final event = _events[i];
      if (event.card.identity == identity) {
        return event;
      }
    }
    return null;
  }

  @override
  int discardsCount(CardRank rank) => _countsByRank[rank.index];

  @override
  int get jokersDiscarded => _jokersDiscarded;

  /// Converts discard memory to JSON-compatible data.
  ///
  /// Only the chronological event stream is persisted — derived indices and
  /// rank/identity counts are rebuilt from the events on restore. Keeping
  /// the wire format minimal lets [DiscardHistory.fromJson] route through
  /// the same `recordDiscard` / `recordPickup` paths the live engine uses,
  /// so the live invariants never get out of sync with the persisted form.
  Map<String, Object?> toJson() {
    return {
      'events': [for (final event in _events) event.toJson()],
    };
  }

  DiscardEvent _append({
    required PlayerSeat seat,
    required HareegCard card,
    required DiscardEventKind kind,
  }) {
    final event = DiscardEvent(
      seat: seat,
      card: card,
      kind: kind,
      sequence: _nextSequence,
    );
    _nextSequence += 1;
    _events.add(event);
    return event;
  }

  Iterable<HareegCard> _lastCardsFor(List<int> indices, int n) sync* {
    if (n <= 0) {
      return;
    }
    var emitted = 0;
    for (var i = indices.length - 1; i >= 0 && emitted < n; i -= 1) {
      yield _events[indices[i]].card;
      emitted += 1;
    }
  }

  void _addDiscardIdentity(HareegCard card) {
    final identity = card.identity;
    if (identity == null) {
      _jokersDiscarded += 1;
      return;
    }
    _countsByRank[identity.rank.index] += 1;
    _identityCounts.update(
      identity.key,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  void _removeDiscardIdentity(HareegCard card) {
    final identity = card.identity;
    if (identity == null) {
      _jokersDiscarded -= 1;
      return;
    }
    _countsByRank[identity.rank.index] -= 1;
    final count = _identityCounts[identity.key] ?? 0;
    if (count <= 1) {
      _identityCounts.remove(identity.key);
    } else {
      _identityCounts[identity.key] = count - 1;
    }
  }
}

Map<PlayerSeat, List<int>> _emptySeatIndexMap() {
  return {for (final seat in PlayerSeat.values) seat: <int>[]};
}
