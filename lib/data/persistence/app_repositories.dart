import 'key_value_store.dart';
import 'key_value_store_factory.dart';
import 'learning_progress_repository.dart';
import 'match_repository.dart';
import 'preferences_repository.dart';

/// Default app-wide persistence repositories.
abstract final class AppRepositories {
  // Platform-appropriate store: the native platform channel on mobile/desktop,
  // a localStorage-backed store on web (so prefs/matches/onboarding survive a
  // page refresh instead of living only in memory).
  static final KeyValueStore _store = createDefaultKeyValueStore();

  /// Preferences repository backed by local platform storage.
  static final PreferencesRepository preferences = LocalPreferencesRepository(
    store: _store,
  );

  /// Active match repository backed by local platform storage.
  static final MatchRepository matches = LocalMatchRepository(store: _store);

  /// Onboarding and guided practice progress backed by local platform storage.
  static final LearningProgressRepository learning =
      LocalLearningProgressRepository(store: _store);
}
