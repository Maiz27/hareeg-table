import 'dart:convert';

import '../../domain/classic_hareeg/persistence/persistence_codec.dart';
import '../../domain/updates/app_release.dart';
import '../persistence/key_value_store.dart';

/// What the app remembers between update checks.
class UpdateCache {
  /// Creates a cache snapshot.
  const UpdateCache({
    this.lastCheckedAt,
    this.releases = const [],
    this.mayBeTruncated = false,
  });

  /// An empty cache: never checked.
  static const empty = UpdateCache();

  /// When the last successful check finished.
  final DateTime? lastCheckedAt;

  /// Every release that check reported, newest first. The whole listing is
  /// kept so the offer can be worked out again against whatever version is
  /// installed by the next launch.
  final List<AppRelease> releases;

  /// Whether that listing may have left older releases out (the channel
  /// returned a full page).
  final bool mayBeTruncated;
}

/// Key/value-backed store for [UpdateCache].
///
/// Kept under its own key, apart from `preferences.v1`: it is machine state,
/// not a player choice, and a corrupt cache must never cost the player their
/// settings.
class UpdateCacheRepository {
  /// Creates the cache repository over [store].
  const UpdateCacheRepository({required KeyValueStore store}) : _store = store;

  /// Storage key. v1 held a single release; it is simply no longer read, so
  /// the first launch after the upgrade checks again.
  static const key = 'updates.cache.v2';

  final KeyValueStore _store;

  /// Loads the cache; anything unreadable reads as [UpdateCache.empty], and
  /// an unreadable release entry is dropped.
  Future<UpdateCache> load() async {
    final raw = await _store.loadString(key);
    if (raw == null || raw.isEmpty) return UpdateCache.empty;
    try {
      final json = asJsonMap(jsonDecode(raw));
      if (json == null) return UpdateCache.empty;
      final checked = json['lastCheckedAt'];
      final entries = json['releases'];
      final releases = <AppRelease>[
        if (entries is List)
          for (final entry in entries) ?AppRelease.fromJson(asJsonMap(entry)),
      ]..sort((a, b) => b.version.compareTo(a.version));
      return UpdateCache(
        lastCheckedAt: checked is String ? DateTime.tryParse(checked) : null,
        releases: releases,
        mayBeTruncated: json['mayBeTruncated'] == true,
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
        'releases': [for (final release in cache.releases) release.toJson()],
        'mayBeTruncated': cache.mayBeTruncated,
      }),
    );
  }
}
