import 'dart:convert';

import '../../domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'key_value_store.dart';

export '../../domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';

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
      final json = jsonMapOrNull(decoded);
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
