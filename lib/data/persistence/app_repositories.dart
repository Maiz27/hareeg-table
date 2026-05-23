import 'key_value_store.dart';
import 'match_repository.dart';
import 'preferences_repository.dart';

/// Default app-wide persistence repositories.
abstract final class AppRepositories {
  static final MethodChannelKeyValueStore _store = MethodChannelKeyValueStore();

  /// Preferences repository backed by local platform storage.
  static final PreferencesRepository preferences = LocalPreferencesRepository(
    store: _store,
  );

  /// Active match repository backed by local platform storage.
  static final MatchRepository matches = LocalMatchRepository(store: _store);
}
