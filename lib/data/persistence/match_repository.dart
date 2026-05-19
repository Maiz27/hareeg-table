import 'dart:convert';

import '../../domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'preferences_repository.dart';

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
