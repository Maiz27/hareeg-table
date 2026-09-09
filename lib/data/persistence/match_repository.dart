import 'dart:convert';

import '../../domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import '../../domain/classic_hareeg/history/match_checkpoint.dart';
import '../../domain/classic_hareeg/history/match_history_outcomes.dart';
import '../../domain/classic_hareeg/history/match_id.dart';
import '../../domain/classic_hareeg/history/recorded_checkpoint_recovery.dart';
import '../../domain/classic_hareeg/game/round_seed_algorithm.dart';
import 'key_value_store.dart';

export '../../domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
export '../../domain/classic_hareeg/history/match_checkpoint.dart';

/// Result of loading the active match.
sealed class ActiveMatchLoadOutcome {
  const ActiveMatchLoadOutcome();
}

/// No resumable match is stored.
class ActiveMatchAbsent extends ActiveMatchLoadOutcome {
  /// Creates the absent outcome.
  const ActiveMatchAbsent();
}

/// A resumable checkpoint was loaded.
class ActiveMatchLoaded extends ActiveMatchLoadOutcome {
  /// Creates a loaded outcome.
  const ActiveMatchLoaded(this.checkpoint);

  /// The stored checkpoint.
  final MatchCheckpoint checkpoint;
}

/// The stored checkpoint could not be read and was **preserved**.
///
/// Distinct from [ActiveMatchAbsent] on purpose. A checkpoint that parses as
/// this app's format but fails to decode may be recoverable by a future build,
/// so it is kept and reported rather than deleted. Only a recognizably invalid
/// *legacy* payload takes the old clear-and-ignore path, because that shape
/// carries no identity, no recorder, and nothing worth preserving.
class ActiveMatchUnreadable extends ActiveMatchLoadOutcome {
  /// Creates an unreadable outcome.
  const ActiveMatchUnreadable(this.failure);

  /// What went wrong.
  final MatchHistoryFailure failure;
}

/// Storage boundary for active match resume data.
abstract interface class MatchRepository {
  /// Loads the active saved match.
  Future<ActiveMatchLoadOutcome> loadActiveMatch();

  /// Saves the active match checkpoint.
  Future<void> saveActiveMatch(MatchCheckpoint checkpoint);

  /// Abandons the active saved match.
  Future<void> abandonActiveMatch();
}

/// JSON-backed active match repository.
class LocalMatchRepository implements MatchRepository {
  /// Creates a match repository from a key/value store.
  ///
  /// [mintMatchId] supplies an id when migrating a legacy save that has none.
  LocalMatchRepository({
    required KeyValueStore store,
    required Future<String> Function() mintMatchId,
  }) : _store = store,
       _mintMatchId = mintMatchId;

  static const _key = 'active_match.v1';

  final KeyValueStore _store;
  String? _lastWrittenRaw;
  ({String matchId, bool terminal})? _lastWrittenIdentity;

  /// Mints an id that no stored summary or replay file is already using.
  ///
  /// Asynchronous because answering "is this free" means consulting durable
  /// history; a synchronous minter could only ever check nothing.
  final Future<String> Function() _mintMatchId;

  @override
  Future<void> abandonActiveMatch() {
    return _store.remove(_key);
  }

  @override
  Future<ActiveMatchLoadOutcome> loadActiveMatch() async {
    final String? raw;
    try {
      raw = await _store.loadString(_key);
    } catch (error) {
      return ActiveMatchUnreadable(
        MatchHistoryFailure(
          kind: MatchHistoryFailureKind.retryable,
          message: 'Could not read the active match: $error',
          cause: error,
        ),
      );
    }

    if (raw == null || raw.isEmpty) {
      return const ActiveMatchAbsent();
    }

    final Map<String, Object?>? json;
    try {
      json = jsonMapOrNull(jsonDecode(raw));
    } on FormatException {
      // Not even JSON. Nothing here is recoverable.
      await abandonActiveMatch();
      return const ActiveMatchAbsent();
    }

    if (json == null) {
      await abandonActiveMatch();
      return const ActiveMatchAbsent();
    }

    // A checkpoint declares a matchId; a legacy payload is a bare snapshot.
    // The discriminator is the shape, not a guess.
    if (json.containsKey('matchId')) {
      try {
        final checkpoint = MatchCheckpoint.fromJson(json);
        final position = await recoverRecordedPosition(checkpoint);
        if (position == null &&
            (checkpoint.snapshot.roundSeedAlgorithm != null ||
                checkpoint.isTerminal)) {
          return ActiveMatchLoaded(checkpoint);
        }
        // Persist the attempted migration even when the guarded repair refuses
        // to change the board. This pins the legacy platform's deal arithmetic
        // and avoids reconstructing the whole match on every menu visit.
        final repaired = checkpoint.withProgress(
          snapshot:
              position ??
              ClassicHareegMatchSnapshot.fromJson({
                ...checkpoint.snapshot.toJson(),
                'roundSeedAlgorithm': legacyLocalRoundSeedAlgorithm.name,
              }),
        );
        await saveActiveMatch(repaired);
        return ActiveMatchLoaded(repaired);
      } on FormatException catch (error) {
        return ActiveMatchUnreadable(
          MatchHistoryFailure(
            kind: MatchHistoryFailureKind.corrupt,
            message:
                'The saved match checkpoint could not be decoded: '
                '${error.message}',
            cause: error,
          ),
        );
      } catch (error) {
        return ActiveMatchUnreadable(
          MatchHistoryFailure(
            kind: MatchHistoryFailureKind.retryable,
            message: 'Could not recover the recorded checkpoint: $error',
            cause: error,
          ),
        );
      }
    }

    return _migrateLegacySnapshot(json);
  }

  /// Upgrades a pre-checkpoint save in place.
  ///
  /// The migrated checkpoint is written back **immediately**, before returning.
  /// Deferring it would mint a fresh id on every load until the first save, and
  /// two loads of the same match would disagree about its identity — which is
  /// exactly the thing the id exists to prevent.
  Future<ActiveMatchLoadOutcome> _migrateLegacySnapshot(
    Map<String, Object?> json,
  ) async {
    final ClassicHareegMatchSnapshot snapshot;
    try {
      snapshot = ClassicHareegMatchSnapshot.fromJson(json);
    } on FormatException {
      // A recognizably invalid legacy payload keeps the historical
      // clear-and-ignore behaviour: it holds no identity and no transcript, so
      // there is nothing to preserve.
      await abandonActiveMatch();
      return const ActiveMatchAbsent();
    }

    final String matchId;
    try {
      matchId = await _mintMatchId();
    } catch (error) {
      // Preserve the legacy bytes: a match we cannot name is still a match the
      // player can resume once minting works again.
      return ActiveMatchUnreadable(
        MatchHistoryFailure(
          kind: MatchHistoryFailureKind.retryable,
          message: 'Could not mint a match id for the legacy save: $error',
          cause: error,
        ),
      );
    }

    final migrated = MatchCheckpoint(
      matchId: matchId,
      snapshot: snapshot,
      // A legacy save predates recorder persistence, so its earlier actions are
      // gone for good: it can never produce a faithful replay, and its Fifty
      // counters were never measured.
      recorderState: null,
      replayIneligible: true,
      fiftyCountersComplete: false,
    );

    try {
      await saveActiveMatch(migrated);
    } catch (error) {
      // Preserve the legacy bytes rather than destroying a resumable match.
      return ActiveMatchUnreadable(
        MatchHistoryFailure(
          kind: MatchHistoryFailureKind.retryable,
          matchId: migrated.matchId,
          message: 'Could not persist the migrated match checkpoint: $error',
          cause: error,
        ),
      );
    }

    return ActiveMatchLoaded(migrated);
  }

  @override
  Future<void> saveActiveMatch(MatchCheckpoint checkpoint) async {
    assert(
      isValidMatchId(checkpoint.matchId),
      'A checkpoint must carry a valid match id.',
    );
    // A completed-but-unpublished checkpoint is the sole recovery source.
    // Refuse replacement even when a caller bypasses Home (e.g. a rematch).
    final raw = await _store.loadString(_key);
    if (raw != null && raw.isNotEmpty) {
      final ({String matchId, bool terminal}) identity;
      if (raw == _lastWrittenRaw && _lastWrittenIdentity != null) {
        identity = _lastWrittenIdentity!;
      } else {
        final existing = jsonMapOrNull(jsonDecode(raw));
        if (existing == null) {
          throw const FormatException('Unreadable active match.');
        }
        final rawMatchId = existing['matchId'];
        if (rawMatchId != null && rawMatchId is! String) {
          throw const FormatException('Unreadable active match id.');
        }
        identity = (
          matchId: rawMatchId as String? ?? '',
          terminal: existing['terminalFacts'] != null,
        );
      }
      if (identity.terminal &&
          (identity.matchId != checkpoint.matchId || !checkpoint.isTerminal)) {
        throw StateError(
          'Recover the completed match before starting another.',
        );
      }
    }
    final pending = await _store.loadString('match_archive_pending.v1');
    if (pending != null && pending.isNotEmpty) {
      final marker = jsonMapOrNull(jsonDecode(pending));
      if (marker == null ||
          marker['matchId'] != checkpoint.matchId ||
          !checkpoint.isTerminal) {
        throw StateError('A match archive still needs recovery.');
      }
    }
    final encoded = jsonEncode(checkpoint.toJson());
    await _store.saveString(_key, encoded);
    // Avoid decoding our own 200 KB transcript again at the next action.
    // Always read and compare the actual store first: another writer or failed
    // read must not be hidden by this optimization.
    _lastWrittenRaw = encoded;
    _lastWrittenIdentity = (
      matchId: checkpoint.matchId,
      terminal: checkpoint.isTerminal,
    );
  }
}
