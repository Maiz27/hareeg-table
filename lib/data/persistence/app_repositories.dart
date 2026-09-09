import '../../domain/classic_hareeg/history/match_id.dart';
import 'key_value_store.dart';
import 'key_value_store_factory.dart';
import 'learning_progress_repository.dart';
import 'match_history_repository.dart';
import 'match_repository.dart';
import 'preferences_repository.dart';
import 'replay_file_store.dart';
import 'replay_file_store_factory.dart';

/// Default app-wide persistence repositories.
abstract final class AppRepositories {
  // Platform-appropriate store: the native platform channel on mobile/desktop,
  // a localStorage-backed store on web (so prefs/matches/onboarding survive a
  // page refresh instead of living only in memory).
  static final KeyValueStore _store = createDefaultKeyValueStore();

  static final MatchIdMinter _matchIds = MatchIdMinter();

  /// Preferences repository backed by local platform storage.
  static final PreferencesRepository preferences = LocalPreferencesRepository(
    store: _store,
  );

  /// Active match repository backed by local platform storage.
  ///
  /// Migrating a legacy save needs an id, and the id must not collide with a
  /// stored match, so minting consults history before settling on one.
  static final MatchRepository matches = LocalMatchRepository(
    store: _store,
    mintMatchId: reserveMatchId,
  );

  /// Onboarding and guided practice progress backed by local platform storage.
  static final LearningProgressRepository learning =
      LocalLearningProgressRepository(store: _store);

  /// Heavy per-match replay payloads.
  ///
  /// Separate from [_store] because replay records are far too large for the
  /// key/value preferences store: on native they are files under a no-backup
  /// directory, on web they are prefixed browser-storage entries.
  static final ReplayFileStore replayFiles = createDefaultReplayFileStore();

  /// Completed-match history: summaries plus their replay records.
  static final MatchHistoryRepository history = LocalMatchHistoryRepository(
    store: _store,
    replayFiles: replayFiles,
    matches: matches,
  );

  /// Mints a match id, rejecting one already used by history or a replay file.
  ///
  /// The collision check is the point: an id that collides with a stored match
  /// would overwrite that match's replay on the next archive, so a candidate is
  /// rejected and re-minted rather than accepted.
  static Future<String> reserveMatchId() {
    return _matchIds.reserve(isTaken: history.isMatchIdTaken);
  }
}
