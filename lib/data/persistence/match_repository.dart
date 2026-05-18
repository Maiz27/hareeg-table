import 'dart:convert';

import '../../domain/classic_hareeg/game/classic_hareeg_round.dart';
import '../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../domain/classic_hareeg/models/player_seat.dart';
import '../../domain/classic_hareeg/models/playing_card.dart';
import 'preferences_repository.dart';

/// Serializable active Classic Hareeg match state.
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
    this.pendingDiscard,
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
    final starter = PlayerSeat.fromName(_asString(json['starter']));
    final currentSeat = PlayerSeat.fromName(_asString(json['currentSeat']));
    final turnPhase = TurnPhase.fromName(_asString(json['turnPhase']));
    final savedAtRaw = _asString(json['savedAt']);
    final savedAt = savedAtRaw == null ? null : DateTime.tryParse(savedAtRaw);

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
      starter: starter,
      currentSeat: currentSeat,
      turnPhase: turnPhase,
      pendingDiscard: pendingJson == null
          ? null
          : HareegCard.fromJson(pendingJson),
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

  /// Seat that started the current round.
  final PlayerSeat starter;

  /// Seat whose turn is active.
  final PlayerSeat currentSeat;

  /// Current turn phase.
  final TurnPhase turnPhase;

  /// Pending discard card that must be used or returned.
  final HareegCard? pendingDiscard;

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
      'starter': starter.name,
      'currentSeat': currentSeat.name,
      'turnPhase': turnPhase.name,
      'pendingDiscard': pendingDiscard?.toJson(),
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
}

/// Storage boundary for active match resume data.
abstract interface class MatchRepository {
  /// Loads the active saved match, if one exists.
  Future<ClassicHareegMatchSnapshot?> loadActiveMatch();

  /// Saves the active match.
  Future<void> saveActiveMatch(ClassicHareegMatchSnapshot snapshot);

  /// Abandons the active saved match.
  Future<void> abandonActiveMatch();
}

/// JSON-backed active match repository.
class LocalMatchRepository implements MatchRepository {
  /// Creates a match repository from a key/value store.
  const LocalMatchRepository({required KeyValueStore store}) : _store = store;

  static const _key = 'active_match.v1';

  final KeyValueStore _store;

  @override
  Future<void> abandonActiveMatch() {
    return _store.remove(_key);
  }

  @override
  Future<ClassicHareegMatchSnapshot?> loadActiveMatch() async {
    final raw = await _store.loadString(_key);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      final json = _asMap(decoded);
      if (json != null) {
        return ClassicHareegMatchSnapshot.fromJson(json);
      }
      await abandonActiveMatch();
    } on FormatException {
      await abandonActiveMatch();
    }

    return null;
  }

  @override
  Future<void> saveActiveMatch(ClassicHareegMatchSnapshot snapshot) {
    return _store.saveString(_key, jsonEncode(snapshot.toJson()));
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
    num() => value.toInt(),
    String() => int.tryParse(value),
    _ => null,
  };
}

String? _asString(Object? value) {
  return value is String ? value : null;
}
