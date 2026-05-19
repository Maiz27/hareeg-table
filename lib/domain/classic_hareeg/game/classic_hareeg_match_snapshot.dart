import '../models/classic_hareeg_setup.dart';
import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../rules/opening_rules.dart';
import 'classic_hareeg_round.dart';

/// Serializable active Classic Hareeg match state.
///
/// Lives in the domain layer so the rules-engine seam can describe full game
/// state in a JSON-friendly form without depending on the data/persistence
/// layer. The persistence repository encodes and decodes this type.
class ClassicHareegMatchSnapshot {
  /// Creates a saved match snapshot.
  const ClassicHareegMatchSnapshot({
    required this.setup,
    required this.hands,
    required this.stock,
    required this.discardPile,
    required this.starter,
    required this.currentSeat,
    required this.turnPhase,
    required this.savedAt,
    this.tableMelds = const {},
    this.pendingDiscard,
    this.openingState,
    this.scores = const {},
    this.activeSeats = const [
      PlayerSeat.south,
      PlayerSeat.east,
      PlayerSeat.north,
      PlayerSeat.west,
    ],
    this.roundNumber = 1,
    this.removedSeats = const [],
  });

  /// Restores a saved match from JSON-compatible data.
  factory ClassicHareegMatchSnapshot.fromJson(Map<String, Object?> json) {
    final version = _asInt(json['version']);
    if (version != 1) {
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
      activeSeats: _seatListFromJson(activeSeatsJson),
      roundNumber: roundNumber <= 0 ? 1 : roundNumber,
      removedSeats: _seatListFromJson(removedSeatsJson),
      savedAt: savedAt,
    );
  }

  /// Setup values active for the saved match.
  final ClassicHareegSetup setup;

  /// Cards held by each seat.
  final Map<PlayerSeat, List<HareegCard>> hands;

  /// Face-down stock cards.
  final List<HareegCard> stock;

  /// Face-up discard pile.
  final List<HareegCard> discardPile;

  /// Melds already played onto the table by each seat.
  final Map<PlayerSeat, List<PlacedMeld>> tableMelds;

  /// Seat that started the current round.
  final PlayerSeat starter;

  /// Seat whose turn is active.
  final PlayerSeat currentSeat;

  /// Current turn phase.
  final TurnPhase turnPhase;

  /// Pending discard card that must be used or returned.
  final HareegCard? pendingDiscard;

  /// Opening benchmark state for the active round.
  final OpeningState? openingState;

  /// Match scores before the active round result is applied.
  final Map<PlayerSeat, int> scores;

  /// Seats still active in the match.
  final List<PlayerSeat> activeSeats;

  /// One-based dealt round number for first-round Fifty rules.
  final int roundNumber;

  /// Seats removed from the current round by hard-table mistakes.
  final List<PlayerSeat> removedSeats;

  /// Time the snapshot was saved.
  final DateTime savedAt;

  /// Converts the snapshot to JSON-compatible data.
  Map<String, Object?> toJson() {
    return {
      'version': 1,
      'setup': setup.toJson(),
      'hands': {
        for (final entry in hands.entries)
          entry.key.name: entry.value.map((card) => card.toJson()).toList(),
      },
      'stock': stock.map((card) => card.toJson()).toList(),
      'discardPile': discardPile.map((card) => card.toJson()).toList(),
      'tableMelds': {
        for (final entry in tableMelds.entries)
          entry.key.name: entry.value.map((meld) => meld.toJson()).toList(),
      },
      'starter': starter.name,
      'currentSeat': currentSeat.name,
      'turnPhase': turnPhase.name,
      'pendingDiscard': pendingDiscard?.toJson(),
      'openingState': openingState?.toJson(),
      'scores': {
        for (final entry in scores.entries) entry.key.name: entry.value,
      },
      'activeSeats': activeSeats.map((seat) => seat.name).toList(),
      'roundNumber': roundNumber,
      'removedSeats': removedSeats.map((seat) => seat.name).toList(),
      'savedAt': savedAt.toIso8601String(),
    };
  }

  static List<HareegCard> _cardsFromJson(List<Object?> cardsJson) {
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

  static Map<PlayerSeat, List<PlacedMeld>> _tableMeldsFromJson(
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

  static Map<PlayerSeat, int> _scoresFromJson(Map<String, Object?>? json) {
    if (json == null) {
      return {for (final seat in PlayerSeat.values) seat: 0};
    }

    return {
      for (final seat in PlayerSeat.values) seat: _asInt(json[seat.name]) ?? 0,
    };
  }

  static List<PlayerSeat> _seatListFromJson(List<Object?>? json) {
    if (json == null) {
      return PlayerSeat.values;
    }

    final seats = <PlayerSeat>[];
    for (final raw in json) {
      final seat = PlayerSeat.fromName(raw is String ? raw : null);
      if (seat != null && !seats.contains(seat)) {
        seats.add(seat);
      }
    }
    return seats.isEmpty ? PlayerSeat.values : List.unmodifiable(seats);
  }
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
