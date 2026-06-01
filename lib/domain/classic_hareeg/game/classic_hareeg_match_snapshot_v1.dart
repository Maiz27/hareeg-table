import '../models/classic_hareeg_setup.dart';
import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../persistence/persistence_codec.dart';
import '../rules/opening_rules.dart';
import 'classic_hareeg_discard_history.dart';
import 'classic_hareeg_match_snapshot.dart';
import 'classic_hareeg_round.dart';

/// Saved-match schema version implemented by this file.
///
/// Bump and add a sibling file (e.g. `..._v2.dart`) when the wire format
/// changes; the dispatcher in [ClassicHareegMatchSnapshot.fromJson] decides
/// which decoder to run based on this number.
const int matchSnapshotV1Version = 1;

/// Decodes a v1-format saved match JSON object.
///
/// Throws [FormatException] when required fields are missing, the wrong type,
/// or fail to parse. Optional fields fall back to safe defaults so a long-
/// running install survives schema additions made on the same major version.
ClassicHareegMatchSnapshot decodeMatchSnapshotV1(Map<String, Object?> json) {
  final version = asJsonInt(json['version']);
  if (version != matchSnapshotV1Version) {
    throw const FormatException('Unsupported saved match version.');
  }

  final setupJson = asJsonMap(json['setup']);
  final handsJson = asJsonMap(json['hands']);
  final stockJson = asJsonList(json['stock']);
  final discardJson = asJsonList(json['discardPile']);
  final tableMeldsJson = asJsonMap(json['tableMelds']);
  final openingStateJson = asJsonMap(json['openingState']);
  final scoresJson = asJsonMap(json['scores']);
  final activeSeatsJson = asJsonList(json['activeSeats']);
  final removedSeatsJson = asJsonList(json['removedSeats']);
  final starter = PlayerSeat.fromName(asJsonString(json['starter']));
  final currentSeat = PlayerSeat.fromName(asJsonString(json['currentSeat']));
  final turnPhase = TurnPhase.fromName(asJsonString(json['turnPhase']));
  final savedAtRaw = asJsonString(json['savedAt']);
  final savedAt = savedAtRaw == null ? null : DateTime.tryParse(savedAtRaw);
  final fiftyWindowOpenedAtRaw = asJsonString(json['fiftyWindowOpenedAt']);
  final fiftyWindowOpenedAt = fiftyWindowOpenedAtRaw == null
      ? null
      : DateTime.tryParse(fiftyWindowOpenedAtRaw);
  // Open Fifty window provenance, persisted verbatim. Both are v1-additive:
  // absent in older saves, where restore falls back to the legacy geometric
  // discarder guess / `roundNumber == 1` derivation.
  final fiftyWindowDiscarder = PlayerSeat.fromName(
    asJsonString(json['fiftyWindowDiscarder']),
  );
  final fiftyWindowIsFirstDealtRound = asJsonBool(
    json['fiftyWindowIsFirstDealtRound'],
  );
  // roundNumber is hard-required: a missing or unparseable value used to
  // collapse to round 1 (`?? 1`), silently turning a later-round Fifty into
  // the first-dealt-round -1 scoring exception (and persisting the wrong
  // delta into the next round). Fail loud instead of guessing the round.
  final roundNumber = asJsonInt(json['roundNumber']);
  if (roundNumber == null || roundNumber <= 0) {
    throw const FormatException(
      'Saved match is missing a valid roundNumber.',
    );
  }

  if (setupJson == null ||
      handsJson == null ||
      stockJson == null ||
      discardJson == null ||
      starter == null ||
      currentSeat == null ||
      turnPhase == null ||
      savedAt == null) {
    throw const FormatException('Invalid saved match.');
  }

  final hands = <PlayerSeat, List<HareegCard>>{};
  for (final seat in PlayerSeat.values) {
    final cardsJson = asJsonList(handsJson[seat.name]);
    if (cardsJson == null) {
      throw const FormatException('Saved match is missing a hand.');
    }
    hands[seat] = _cardsFromJson(cardsJson);
  }

  final pendingJson = asJsonMap(json['pendingDiscard']);
  // discardHistory is a v1-additive field: older saves without it restore
  // an empty event list, matching the prior behaviour (CPU memory reset on
  // resume). Documented in classic_hareeg_match_snapshot.dart.
  final discardHistoryEvents = _discardHistoryEventsFromJson(
    json['discardHistory'],
  );

  return ClassicHareegMatchSnapshot(
    setup: ClassicHareegSetup.fromJson(setupJson),
    hands: hands,
    stock: _cardsFromJson(stockJson),
    discardPile: _cardsFromJson(discardJson),
    tableMelds: _tableMeldsFromJson(tableMeldsJson),
    starter: starter,
    currentSeat: currentSeat,
    turnPhase: turnPhase,
    pendingDiscard: pendingJson == null
        ? null
        : HareegCard.fromJson(pendingJson),
    openingState: openingStateJson == null
        ? null
        : OpeningState.fromJson(openingStateJson),
    scores: _scoresFromJson(scoresJson),
    activeSeats: _seatListFromJson(
      activeSeatsJson,
      fallback: PlayerSeat.values,
    ),
    roundNumber: roundNumber,
    removedSeats: _seatListFromJson(
      removedSeatsJson,
      fallback: const <PlayerSeat>[],
    ),
    fiftyWindowOpenedAt: fiftyWindowOpenedAt,
    fiftyWindowDiscarder: fiftyWindowDiscarder,
    fiftyWindowIsFirstDealtRound: fiftyWindowIsFirstDealtRound,
    savedAt: savedAt,
    discardHistoryEvents: discardHistoryEvents,
  );
}

/// Encodes [snapshot] into a v1-format saved match JSON object.
Map<String, Object?> encodeMatchSnapshotV1(ClassicHareegMatchSnapshot snapshot) {
  return {
    'version': matchSnapshotV1Version,
    'setup': snapshot.setup.toJson(),
    'hands': {
      for (final entry in snapshot.hands.entries)
        entry.key.name: entry.value.map((card) => card.toJson()).toList(),
    },
    'stock': snapshot.stock.map((card) => card.toJson()).toList(),
    'discardPile': snapshot.discardPile.map((card) => card.toJson()).toList(),
    'tableMelds': {
      for (final entry in snapshot.tableMelds.entries)
        entry.key.name: entry.value.map((meld) => meld.toJson()).toList(),
    },
    'starter': snapshot.starter.name,
    'currentSeat': snapshot.currentSeat.name,
    'turnPhase': snapshot.turnPhase.name,
    'pendingDiscard': snapshot.pendingDiscard?.toJson(),
    'openingState': snapshot.openingState?.toJson(),
    'scores': {
      for (final entry in snapshot.scores.entries) entry.key.name: entry.value,
    },
    'activeSeats': snapshot.activeSeats.map((seat) => seat.name).toList(),
    'roundNumber': snapshot.roundNumber,
    'removedSeats': snapshot.removedSeats.map((seat) => seat.name).toList(),
    'fiftyWindowOpenedAt': snapshot.fiftyWindowOpenedAt?.toIso8601String(),
    'fiftyWindowDiscarder': snapshot.fiftyWindowDiscarder?.name,
    'fiftyWindowIsFirstDealtRound': snapshot.fiftyWindowIsFirstDealtRound,
    'savedAt': snapshot.savedAt.toIso8601String(),
    'discardHistory': {
      'events': [
        for (final event in snapshot.discardHistoryEvents) event.toJson(),
      ],
    },
  };
}

List<DiscardEvent> _discardHistoryEventsFromJson(Object? raw) {
  if (raw == null) {
    return const [];
  }
  final container = asJsonMap(raw);
  if (container == null) {
    throw const FormatException('Invalid discard history container.');
  }
  final events = asJsonList(container['events']);
  if (events == null) {
    return const [];
  }
  return [
    for (final entry in events)
      DiscardEvent.fromJson(
        asJsonMap(entry) ??
            (throw const FormatException('Invalid discard event entry.')),
      ),
  ];
}

List<HareegCard> _cardsFromJson(List<Object?> cardsJson) {
  final cards = <HareegCard>[];
  for (final cardJson in cardsJson) {
    final cardMap = asJsonMap(cardJson);
    if (cardMap == null) {
      throw const FormatException('Invalid saved card.');
    }
    cards.add(HareegCard.fromJson(cardMap));
  }
  return cards;
}

Map<PlayerSeat, List<PlacedMeld>> _tableMeldsFromJson(
  Map<String, Object?>? tableMeldsJson,
) {
  if (tableMeldsJson == null) {
    return const {};
  }

  final tableMelds = <PlayerSeat, List<PlacedMeld>>{};
  for (final seat in PlayerSeat.values) {
    final meldsJson = asJsonList(tableMeldsJson[seat.name]);
    if (meldsJson == null) {
      continue;
    }
    tableMelds[seat] = [
      for (final meldJson in meldsJson)
        PlacedMeld.fromJson(
          asJsonMap(meldJson) ??
              (throw const FormatException('Invalid saved meld.')),
        ),
    ];
  }
  return tableMelds;
}

Map<PlayerSeat, int> _scoresFromJson(Map<String, Object?>? json) {
  if (json == null) {
    return {for (final seat in PlayerSeat.values) seat: 0};
  }

  return {
    for (final seat in PlayerSeat.values) seat: asJsonInt(json[seat.name]) ?? 0,
  };
}

List<PlayerSeat> _seatListFromJson(
  List<Object?>? json, {
  required List<PlayerSeat> fallback,
}) {
  if (json == null) {
    return List.unmodifiable(fallback);
  }

  final seats = <PlayerSeat>[];
  for (final raw in json) {
    final seat = PlayerSeat.fromName(raw is String ? raw : null);
    if (seat != null && !seats.contains(seat)) {
      seats.add(seat);
    }
  }
  return seats.isEmpty
      ? List.unmodifiable(fallback)
      : List.unmodifiable(seats);
}

