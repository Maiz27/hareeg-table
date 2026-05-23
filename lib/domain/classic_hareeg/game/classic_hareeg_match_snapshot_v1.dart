import '../models/classic_hareeg_setup.dart';
import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../rules/opening_rules.dart';
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
  final version = _asInt(json['version']);
  if (version != matchSnapshotV1Version) {
    throw const FormatException('Unsupported saved match version.');
  }

  final setupJson = _asMap(json['setup']);
  final handsJson = _asMap(json['hands']);
  final stockJson = _asList(json['stock']);
  final discardJson = _asList(json['discardPile']);
  final tableMeldsJson = _asMap(json['tableMelds']);
  final openingStateJson = _asMap(json['openingState']);
  final scoresJson = _asMap(json['scores']);
  final activeSeatsJson = _asList(json['activeSeats']);
  final removedSeatsJson = _asList(json['removedSeats']);
  final starter = PlayerSeat.fromName(_asString(json['starter']));
  final currentSeat = PlayerSeat.fromName(_asString(json['currentSeat']));
  final turnPhase = TurnPhase.fromName(_asString(json['turnPhase']));
  final savedAtRaw = _asString(json['savedAt']);
  final savedAt = savedAtRaw == null ? null : DateTime.tryParse(savedAtRaw);
  final fiftyWindowOpenedAtRaw = _asString(json['fiftyWindowOpenedAt']);
  final fiftyWindowOpenedAt = fiftyWindowOpenedAtRaw == null
      ? null
      : DateTime.tryParse(fiftyWindowOpenedAtRaw);
  final roundNumber = _asInt(json['roundNumber']) ?? 1;

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
    final cardsJson = _asList(handsJson[seat.name]);
    if (cardsJson == null) {
      throw const FormatException('Saved match is missing a hand.');
    }
    hands[seat] = _cardsFromJson(cardsJson);
  }

  final pendingJson = _asMap(json['pendingDiscard']);

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
    roundNumber: roundNumber <= 0 ? 1 : roundNumber,
    removedSeats: _seatListFromJson(
      removedSeatsJson,
      fallback: const <PlayerSeat>[],
    ),
    fiftyWindowOpenedAt: fiftyWindowOpenedAt,
    savedAt: savedAt,
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
    'savedAt': snapshot.savedAt.toIso8601String(),
  };
}

List<HareegCard> _cardsFromJson(List<Object?> cardsJson) {
  final cards = <HareegCard>[];
  for (final cardJson in cardsJson) {
    final cardMap = _asMap(cardJson);
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
    final meldsJson = _asList(tableMeldsJson[seat.name]);
    if (meldsJson == null) {
      continue;
    }
    tableMelds[seat] = [
      for (final meldJson in meldsJson)
        PlacedMeld.fromJson(
          _asMap(meldJson) ??
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
    for (final seat in PlayerSeat.values) seat: _asInt(json[seat.name]) ?? 0,
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

Map<String, Object?>? _asMap(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  return null;
}

List<Object?>? _asList(Object? value) {
  if (value is List) {
    return value;
  }

  return null;
}

int? _asInt(Object? value) {
  return switch (value) {
    int() => value,
    num() when value.isFinite && value % 1 == 0 => value.toInt(),
    String() => int.tryParse(value),
    _ => null,
  };
}

String? _asString(Object? value) {
  return value is String ? value : null;
}
