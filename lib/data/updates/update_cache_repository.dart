import 'dart:convert';

import '../../domain/classic_hareeg/persistence/persistence_codec.dart';
import '../../domain/updates/app_release.dart';
import '../persistence/key_value_store.dart';

/// What the app remembers between update checks.
class UpdateCache {
  /// Creates a cache snapshot.
  const UpdateCache({this.lastCheckedAt, this.lastSeenRelease});

  /// An empty cache: never checked.
  static const empty = UpdateCache();

  /// When the last successful check finished.
  final DateTime? lastCheckedAt;

  /// The newest release that check reported, if any.
  final AppRelease? lastSeenRelease;
}

/// Key/value-backed store for [UpdateCache].
///
/// Kept under its own key, apart from `preferences.v1`: it is machine state,
/// not a player choice, and a corrupt cache must never cost the player their
/// settings.
class UpdateCacheRepository {
  /// Creates the cache repository over [store].
  const UpdateCacheRepository({required KeyValueStore store}) : _store = store;

  /// Storage key.
  static const key = 'updates.cache.v1';

  final KeyValueStore _store;

  /// Loads the cache; anything unreadable reads as [UpdateCache.empty].
  Future<UpdateCache> load() async {
    final raw = await _store.loadString(key);
    if (raw == null || raw.isEmpty) return UpdateCache.empty;
    try {
      final json = asJsonMap(jsonDecode(raw));
      if (json == null) return UpdateCache.empty;
      final checked = json['lastCheckedAt'];
      return UpdateCache(
        lastCheckedAt: checked is String ? DateTime.tryParse(checked) : null,
        lastSeenRelease: AppRelease.fromJson(
          asJsonMap(json['lastSeenRelease']),
        ),
      );
    } on FormatException {
      return UpdateCache.empty;
    }
  }

  /// Saves [cache].
  Future<void> save(UpdateCache cache) {
    return _store.saveString(
      key,
      jsonEncode({
        if (cache.lastCheckedAt != null)
          'lastCheckedAt': cache.lastCheckedAt!.toUtc().toIso8601String(),
        if (cache.lastSeenRelease != null)
          'lastSeenRelease': cache.lastSeenRelease!.toJson(),
      }),
    );
  }
}
