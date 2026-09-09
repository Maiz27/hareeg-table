import 'dart:async';
import 'dart:convert';

import '../../domain/classic_hareeg/history/match_history_outcomes.dart';
import '../../domain/classic_hareeg/history/match_history_summary.dart';
import '../../domain/classic_hareeg/history/match_replay_record.dart';
import '../../domain/classic_hareeg/history/match_replay_verification.dart';
import '../../domain/classic_hareeg/history/match_terminal_facts.dart';
import '../../domain/classic_hareeg/models/player_seat.dart';
import '../../domain/classic_hareeg/persistence/persistence_codec.dart';
import '../../domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'key_value_store.dart';
import 'match_repository.dart';
import 'replay_file_store.dart';

/// Schema version implemented by the history index wire format.
const int matchHistoryIndexVersion = 1;

/// Storage boundary for completed-match history.
///
/// Completed matches live as two records — a light summary in the key-value
/// store and a heavy replay file — and keeping those two consistent is the
/// whole job of this module. Callers never touch either store directly, so no
/// call site has to remember the ordering rules, and there is exactly one place
/// where "summary says replayable but the file is gone" can be created or
/// repaired.
abstract interface class MatchHistoryRepository {
  /// Lists completed matches, newest first, repairing drift as it goes.
  Future<MatchHistoryListOutcome> listSummaries();

  /// Loads one match's replay record.
  Future<MatchReplayOpenOutcome> openReplay(String matchId);

  /// Removes both records for one match.
  Future<MatchHistoryDeleteOutcome> deleteMatch(String matchId);

  /// Marks a match non-replayable because its replay cannot be used.
  ///
  /// [openReplay] answers success as soon as the stored bytes decode, so a
  /// record that decodes but cannot be *reconstructed* would otherwise stay
  /// advertised as replayable forever and the player could open the same dead
  /// link indefinitely. The caller reports what it found; deciding what that
  /// means for the two stores stays here.
  Future<MatchReplayRepairOutcome> repairUnusableReplay({
    required String matchId,
    required String reason,
  });

  /// Marks a completed match for publication and publishes it.
  Future<MatchArchivePublishOutcome> archiveCompletedMatch(
    MatchCheckpoint terminal,
  );

  /// Finishes any publication interrupted by a crash or a kill.
  Future<MatchArchivePublishOutcome> recoverPendingArchive();

  /// Whether [candidate] is already used by a summary or a replay file.
  Future<bool> isMatchIdTaken(String candidate);
}

/// Two-record match history over the key-value store and the replay file store.
class LocalMatchHistoryRepository implements MatchHistoryRepository {
  /// Creates a history repository.
  LocalMatchHistoryRepository({
    required KeyValueStore store,
    required ReplayFileStore replayFiles,
    required MatchRepository matches,
  }) : _store = store,
       _replayFiles = replayFiles,
       _matches = matches;

  static const String indexKey = 'match_history_index.v1';
  static const String pendingKey = 'match_archive_pending.v1';
  static const String pendingDeleteKey = 'match_history_delete_pending.v1';

  final KeyValueStore _store;
  final ReplayFileStore _replayFiles;
  final MatchRepository _matches;

  /// Serializes every operation.
  ///
  /// Two publications of the same match racing each other would both read the
  /// index, both add their summary, and the second write would erase the
  /// first's — a lost update that is invisible until someone notices a missing
  /// match. Chaining the work removes the interleaving rather than trying to
  /// detect it.
  Future<void> _tail = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  MatchHistoryFailure _retryable(
    String message,
    Object error, {
    String? matchId,
  }) {
    return MatchHistoryFailure(
      kind: MatchHistoryFailureKind.retryable,
      message: '$message: $error',
      matchId: matchId,
      cause: error,
    );
  }

  MatchHistoryFailure _corrupt(
    String message,
    Object error, {
    String? matchId,
  }) {
    return MatchHistoryFailure(
      kind: MatchHistoryFailureKind.corrupt,
      message: '$message: $error',
      matchId: matchId,
      cause: error,
    );
  }

  // --- index -------------------------------------------------------------

  Future<List<MatchHistorySummary>> _readIndex() async {
    final raw = await _store.loadString(indexKey);
    if (raw == null || raw.isEmpty) {
      return <MatchHistorySummary>[];
    }

    final json = asJsonMap(jsonDecode(raw));
    if (json == null) {
      throw const FormatException('History index is not an object.');
    }

    final version = asJsonInt(json['version']);
    if (version != matchHistoryIndexVersion) {
      throw FormatException(
        'Unsupported history index version $version; '
        'expected $matchHistoryIndexVersion.',
      );
    }

    final rawSummaries = asJsonList(json['summaries']);
    if (rawSummaries == null) {
      throw const FormatException('History index has no summaries list.');
    }

    final summaries = <MatchHistorySummary>[];
    final seen = <String>{};
    for (final entry in rawSummaries) {
      final summary = MatchHistorySummary.fromJson(
        asJsonMap(entry) ??
            (throw const FormatException('Invalid history summary entry.')),
      );
      // Two entries for one match is corruption, and it is not harmless: the
      // publication and recovery paths ask the index for *the* summary of a
      // match, and a duplicate would throw a raw StateError straight out of the
      // repository instead of a typed outcome. Caught here so every caller
      // reports the same corrupt result.
      if (!seen.add(summary.matchId)) {
        throw FormatException(
          'History index holds more than one summary for '
          '"${summary.matchId}".',
        );
      }
      summaries.add(summary);
    }

    return summaries;
  }

  Future<void> _writeIndex(List<MatchHistorySummary> summaries) {
    return _store.saveString(
      indexKey,
      jsonEncode({
        'version': matchHistoryIndexVersion,
        'summaries': [for (final summary in summaries) summary.toJson()],
      }),
    );
  }

  /// Newest first, with an explicit ascending match-id tiebreak so two matches
  /// completing in the same millisecond still list in one stable order.
  List<MatchHistorySummary> _sorted(List<MatchHistorySummary> summaries) {
    final sorted = [...summaries]
      ..sort((a, b) {
        final byTime = b.completedAt.compareTo(a.completedAt);
        if (byTime != 0) {
          return byTime;
        }
        return a.matchId.compareTo(b.matchId);
      });
    return List.unmodifiable(sorted);
  }

  // --- listing -----------------------------------------------------------

  @override
  Future<MatchHistoryListOutcome> listSummaries() {
    return _serialized(() async {
      final List<MatchHistorySummary> summaries;
      try {
        summaries = await _readIndex();
      } on FormatException catch (error) {
        return MatchHistoryListFailed(_corrupt('History index', error));
      } catch (error) {
        return MatchHistoryListFailed(_retryable('History index', error));
      }

      // One listKeys call and no readFile calls: a missing replay is found by
      // set difference against the stored keys, so listing a hundred matches
      // never touches a replay payload.
      final Set<String> replayKeys;
      try {
        replayKeys = (await _replayFiles.listKeys()).toSet();
      } catch (error) {
        // Nothing is mutated on a listing failure. Treating an unreadable
        // store as "no replays exist" would repair every entry to
        // non-replayable and permanently discard working replays.
        return MatchHistoryListFailed(_retryable('Replay listing', error));
      }

      final repaired = <String>[];
      final updated = <MatchHistorySummary>[];
      for (final summary in summaries) {
        if (summary.replayable && !replayKeys.contains(summary.matchId)) {
          repaired.add(summary.matchId);
          updated.add(_markNonReplayable(summary));
        } else {
          updated.add(summary);
        }
      }

      if (repaired.isNotEmpty) {
        try {
          // One write for every repair in this pass.
          await _writeIndex(updated);
        } catch (error) {
          return MatchHistoryListFailed(
            _retryable('History index repair', error),
          );
        }
      }

      return MatchHistoryListed(
        summaries: _sorted(updated),
        repairedMatchIds: List.unmodifiable(repaired),
      );
    });
  }

  // --- opening -----------------------------------------------------------

  @override
  Future<MatchReplayOpenOutcome> openReplay(String matchId) {
    return _serialized(() async {
      final List<MatchHistorySummary> summaries;
      try {
        summaries = await _readIndex();
      } on FormatException catch (error) {
        return MatchReplayOpenFailed(
          _corrupt('History index', error, matchId: matchId),
        );
      } catch (error) {
        return MatchReplayOpenFailed(
          _retryable('History index', error, matchId: matchId),
        );
      }

      final index = summaries.indexWhere((s) => s.matchId == matchId);
      if (index < 0) {
        return MatchReplayOpenFailed(
          MatchHistoryFailure(
            kind: MatchHistoryFailureKind.corrupt,
            matchId: matchId,
            message: 'No history entry exists for this match.',
          ),
        );
      }

      final String? raw;
      try {
        raw = await _replayFiles.readFile(matchId);
      } catch (error) {
        // A backend failure says nothing about whether the replay exists, so
        // the summary keeps its replayable flag and the caller retries.
        return MatchReplayOpenFailed(
          _retryable('Replay read', error, matchId: matchId),
        );
      }

      if (raw == null) {
        return _repairToNonReplayable(
          summaries,
          index,
          'The replay file is missing.',
        );
      }

      try {
        final json = asJsonMap(jsonDecode(raw));
        if (json == null) {
          throw const FormatException('Replay record is not an object.');
        }
        final record = MatchReplayRecord.fromJson(json);
        // The bytes decode, but they must also be *this* match's bytes. A
        // record carrying a different id would otherwise open as the requested
        // match and replay somebody else's game.
        if (record.matchId != matchId) {
          throw FormatException(
            'Replay record belongs to "${record.matchId}", not "$matchId".',
          );
        }
        return MatchReplayOpened(record);
      } on FormatException catch (error) {
        // Bytes were read successfully and do not decode: retrying reads the
        // same bad bytes, so this is real evidence about the data.
        return _repairToNonReplayable(
          summaries,
          index,
          'The replay file could not be decoded: ${error.message}',
        );
      }
    });
  }

  /// The single definition of "this match's replay can no longer be used".
  ///
  /// Both repair paths — the drift sweep during listing, and the open-time
  /// repair — go through here, so the two can never come to disagree about
  /// what marking an entry non-replayable involves.
  static MatchHistorySummary _markNonReplayable(MatchHistorySummary summary) =>
      summary.withReplayable(false);

  Future<MatchReplayOpenOutcome> _repairToNonReplayable(
    List<MatchHistorySummary> summaries,
    int index,
    String reason,
  ) async {
    final repaired = _markNonReplayable(summaries[index]);
    final updated = [...summaries]..[index] = repaired;
    try {
      await _writeIndex(updated);
    } catch (error) {
      return MatchReplayOpenFailed(
        _retryable('History index repair', error, matchId: repaired.matchId),
      );
    }
    return MatchReplayUnavailable(repaired, reason);
  }

  @override
  Future<MatchReplayRepairOutcome> repairUnusableReplay({
    required String matchId,
    required String reason,
  }) {
    return _serialized(() async {
      final List<MatchHistorySummary> summaries;
      try {
        summaries = await _readIndex();
      } on FormatException catch (error) {
        return MatchReplayRepairFailed(
          _corrupt('History index', error, matchId: matchId),
        );
      } catch (error) {
        return MatchReplayRepairFailed(
          _retryable('History index', error, matchId: matchId),
        );
      }

      final index = summaries.indexWhere((s) => s.matchId == matchId);
      if (index < 0) {
        // Nothing to repair. Not an error: a concurrent delete is a perfectly
        // good reason for the entry to be gone.
        return MatchReplayRepairFailed(
          MatchHistoryFailure(
            kind: MatchHistoryFailureKind.corrupt,
            matchId: matchId,
            message: 'No history entry exists for this match.',
          ),
        );
      }

      final outcome = await _repairToNonReplayable(summaries, index, reason);
      return switch (outcome) {
        MatchReplayUnavailable(:final summary) => MatchReplayRepaired(summary),
        MatchReplayOpenFailed(:final failure) => MatchReplayRepairFailed(
          failure,
        ),
        // `_repairToNonReplayable` only ever answers unavailable-or-failed.
        MatchReplayOpened() => MatchReplayRepairFailed(
          MatchHistoryFailure(
            kind: MatchHistoryFailureKind.retryable,
            matchId: matchId,
            message: 'Replay repair returned an unexpected outcome.',
          ),
        ),
      };
    });
  }

  // --- deletion ----------------------------------------------------------

  @override
  Future<MatchHistoryDeleteOutcome> deleteMatch(String matchId) {
    return _serialized(() async {
      try {
        final unfinished = await _store.loadString(pendingDeleteKey);
        if (unfinished != null) {
          final previous = await _finishDelete(unfinished);
          if (previous is MatchHistoryDeleteFailed) return previous;
        }
        await _store.saveString(pendingDeleteKey, matchId);
      } catch (error) {
        return MatchHistoryDeleteFailed(
          _retryable('Delete marker', error, matchId: matchId),
        );
      }
      return _finishDelete(matchId);
    });
  }

  Future<MatchHistoryDeleteOutcome> _finishDelete(String matchId) async {
    try {
      // Remove only this match's recovery inputs. The durable deletion marker
      // makes interruption here resumable without resurrecting the summary.
      final active = await _matches.loadActiveMatch();
      if (active is ActiveMatchUnreadable) {
        return MatchHistoryDeleteFailed(active.failure);
      }
      if (active is ActiveMatchLoaded &&
          active.checkpoint.isTerminal &&
          active.checkpoint.matchId == matchId) {
        await _matches.abandonActiveMatch();
      }
      final rawPending = await _store.loadString(pendingKey);
      if (rawPending != null) {
        final pending = PendingMatchArchive.fromJson(
          asJsonMap(jsonDecode(rawPending)) ??
              (throw const FormatException('Invalid pending archive.')),
        );
        if (pending.matchId == matchId) await _store.remove(pendingKey);
      }
    } catch (error) {
      return MatchHistoryDeleteFailed(
        _retryable('Delete recovery data', error, matchId: matchId),
      );
    }
    try {
      // A false answer means the file was already absent, which is a fine
      // starting point for deletion — only a thrown error means we do not
      // know whether the replay is gone.
      await _replayFiles.deleteFile(matchId);
    } catch (error) {
      return MatchHistoryDeleteFailed(
        _retryable('Replay delete', error, matchId: matchId),
      );
    }

    final List<MatchHistorySummary> summaries;
    try {
      summaries = await _readIndex();
    } on FormatException catch (error) {
      return MatchHistoryDeleteFailed(
        _corrupt('History index', error, matchId: matchId),
      );
    } catch (error) {
      return MatchHistoryDeleteFailed(
        _retryable('History index', error, matchId: matchId),
      );
    }

    final remaining = [
      for (final summary in summaries)
        if (summary.matchId != matchId) summary,
    ];

    try {
      await _writeIndex(remaining);
    } catch (error) {
      // The replay is gone but the summary survives. It stays visible, and
      // the next listing repairs it to non-replayable rather than leaving a
      // button that opens nothing.
      return MatchHistoryDeleteFailed(
        _retryable('History index write', error, matchId: matchId),
      );
    }

    try {
      await _store.remove(pendingDeleteKey);
    } catch (error) {
      return MatchHistoryDeleteFailed(
        _retryable('Delete marker clear', error, matchId: matchId),
      );
    }
    return const MatchHistoryDeleted();
  }

  // --- publication -------------------------------------------------------

  @override
  Future<bool> isMatchIdTaken(String candidate) async {
    try {
      final summaries = await _readIndex();
      if (summaries.any((summary) => summary.matchId == candidate)) {
        return true;
      }
    } catch (_) {
      // An unreadable index cannot prove the id is free, so treat it as taken
      // and mint another. Rejecting a usable id is harmless; accepting one that
      // collides would overwrite a stored match.
      return true;
    }

    try {
      return (await _replayFiles.listKeys()).contains(candidate);
    } catch (_) {
      return true;
    }
  }

  @override
  Future<MatchArchivePublishOutcome> archiveCompletedMatch(
    MatchCheckpoint terminal,
  ) {
    return _serialized(() => _archiveLocked(terminal));
  }

  /// The archive body, already holding the lock.
  ///
  /// Separate from [archiveCompletedMatch] because recovery needs to archive
  /// from inside its own critical section; going through the public entry point
  /// would queue behind the lock the caller is already holding and deadlock.
  Future<MatchArchivePublishOutcome> _archiveLocked(
    MatchCheckpoint terminal,
  ) async {
    {
      if (!terminal.isTerminal) {
        return MatchArchivePublishFailed(
          MatchHistoryFailure(
            kind: MatchHistoryFailureKind.corrupt,
            matchId: terminal.matchId,
            message: 'Only a completed match can be archived.',
          ),
        );
      }

      try {
        await _store.saveString(
          pendingKey,
          jsonEncode(PendingMatchArchive(matchId: terminal.matchId).toJson()),
        );
      } catch (error) {
        return MatchArchivePublishFailed(
          _retryable('Pending archive write', error, matchId: terminal.matchId),
        );
      }

      return _publish(terminal);
    }
  }

  @override
  Future<MatchArchivePublishOutcome> recoverPendingArchive() {
    return _serialized(() async {
      try {
        final deleting = await _store.loadString(pendingDeleteKey);
        if (deleting != null) {
          final result = await _finishDelete(deleting);
          if (result is MatchHistoryDeleteFailed) {
            return MatchArchivePublishFailed(result.failure);
          }
        }
      } catch (error) {
        return MatchArchivePublishFailed(_retryable('Delete recovery', error));
      }
      final String? rawPending;
      try {
        rawPending = await _store.loadString(pendingKey);
      } catch (error) {
        return MatchArchivePublishFailed(_retryable('Pending archive', error));
      }

      final checkpointOutcome = await _matches.loadActiveMatch();
      if (checkpointOutcome is ActiveMatchUnreadable) {
        return MatchArchivePublishFailed(checkpointOutcome.failure);
      }
      final terminal = switch (checkpointOutcome) {
        ActiveMatchLoaded(:final checkpoint) when checkpoint.isTerminal =>
          checkpoint,
        _ => null,
      };

      if (rawPending == null || rawPending.isEmpty) {
        // A crash between marking the match terminal and writing the pending
        // record leaves exactly this: a terminal checkpoint nobody is coming
        // back for. Recreate the pending record and publish.
        if (terminal == null) {
          return const MatchArchiveNothingPending();
        }
        return _archiveLocked(terminal);
      }

      final PendingMatchArchive pending;
      try {
        final json = asJsonMap(jsonDecode(rawPending));
        if (json == null) {
          throw const FormatException('Pending archive is not an object.');
        }
        pending = PendingMatchArchive.fromJson(json);
      } on FormatException catch (error) {
        return MatchArchivePublishFailed(_corrupt('Pending archive', error));
      }

      if (terminal != null && terminal.matchId == pending.matchId) {
        return _publish(terminal);
      }

      // The checkpoint is gone but the pending record survives: publication got
      // as far as clearing one and not the other. If the summary is already
      // there, the work is done and only the marker needs clearing.
      return _clearPendingIfPublished(pending.matchId);
    });
  }

  Future<MatchArchivePublishOutcome> _clearPendingIfPublished(
    String matchId,
  ) async {
    final List<MatchHistorySummary> summaries;
    try {
      summaries = await _readIndex();
    } on FormatException catch (error) {
      return MatchArchivePublishFailed(
        _corrupt('History index', error, matchId: matchId),
      );
    } catch (error) {
      return MatchArchivePublishFailed(
        _retryable('History index', error, matchId: matchId),
      );
    }

    final existing = summaries.where((s) => s.matchId == matchId).toList();
    if (existing.isEmpty) {
      // The active checkpoint was positively read above and cannot publish
      // this id; the index was also read successfully. This id-only marker has
      // no recoverable match data. Clear it, report the loss once, then allow
      // subsequent recovery/new games. Never infer absence from a read error.
      try {
        await _store.remove(pendingKey);
      } catch (error) {
        return MatchArchivePublishFailed(_retryable('Orphan marker clear', error, matchId: matchId));
      }
      return MatchArchivePublishFailed(
        MatchHistoryFailure(
          kind: MatchHistoryFailureKind.corrupt,
          matchId: matchId,
          message:
              'A publication is pending but its match data is gone; it cannot '
              'be completed.',
        ),
      );
    }

    try {
      await _store.remove(pendingKey);
    } catch (error) {
      return MatchArchivePublishFailed(
        _retryable('Pending archive clear', error, matchId: matchId),
      );
    }

    return MatchArchiveAlreadyPublished(existing.single);
  }

  Future<MatchArchivePublishOutcome> _publish(MatchCheckpoint terminal) async {
    final facts = terminal.terminalFacts!;
    final matchId = terminal.matchId;

    final List<MatchHistorySummary> summaries;
    try {
      summaries = await _readIndex();
    } on FormatException catch (error) {
      return MatchArchivePublishFailed(
        _corrupt('History index', error, matchId: matchId),
      );
    } catch (error) {
      return MatchArchivePublishFailed(
        _retryable('History index', error, matchId: matchId),
      );
    }

    final alreadyPublished = summaries
        .where((summary) => summary.matchId == matchId)
        .toList();
    if (alreadyPublished.isNotEmpty) {
      final cleared = await _clearArchiveMarkers(matchId);
      if (cleared != null) {
        return cleared;
      }
      return MatchArchiveAlreadyPublished(alreadyPublished.single);
    }

    final replay = _candidateReplay(terminal, facts);
    final replayable = replay.record != null;

    if (replayable) {
      try {
        // The replay lands before the summary, so a summary is never durable
        // pointing at a file that does not exist.
        await _replayFiles.writeFile(
          matchId,
          jsonEncode(replay.record!.toJson()),
        );
      } catch (error) {
        // No summary is written and the pending record survives for a retry.
        return MatchArchivePublishFailed(
          _retryable('Replay write', error, matchId: matchId),
        );
      }
    }

    final summary = MatchHistorySummary(
      matchId: matchId,
      completedAt: facts.completedAt,
      setup: terminal.snapshot.setup,
      finalScores: facts.finalScores,
      winner: facts.winner,
      southPlacement: facts.standing.placementOf(PlayerSeat.south) ?? 0,
      roundCount: facts.roundCount,
      coachWasEnabled: terminal.coachWasEnabled,
      fiftyCounters: terminal.fiftyCounters,
      fiftyCountersComplete: terminal.fiftyCountersComplete,
      replayable: replayable,
    );

    try {
      await _writeIndex([...summaries, summary]);
    } catch (error) {
      return MatchArchivePublishFailed(
        _retryable('History index write', error, matchId: matchId),
      );
    }

    final cleared = await _clearArchiveMarkers(matchId);
    if (cleared != null) {
      return cleared;
    }

    return replayable
        ? MatchArchivePublished(summary)
        : MatchArchivePublishedNonReplayable(summary, replay.reason!);
  }

  /// Clears the pending marker and then the terminal checkpoint.
  ///
  /// Returns a failure outcome when either clear fails, or null on success.
  Future<MatchArchivePublishOutcome?> _clearArchiveMarkers(
    String matchId,
  ) async {
    try {
      await _store.remove(pendingKey);
    } catch (error) {
      return MatchArchivePublishFailed(
        _retryable('Pending archive clear', error, matchId: matchId),
      );
    }

    try {
      final active = await _matches.loadActiveMatch();
      if (active is ActiveMatchUnreadable) {
        return MatchArchivePublishFailed(active.failure);
      }
      if (active is ActiveMatchLoaded &&
          active.checkpoint.isTerminal &&
          active.checkpoint.matchId == matchId) {
        await _matches.abandonActiveMatch();
      }
    } catch (error) {
      return MatchArchivePublishFailed(
        _retryable('Checkpoint clear', error, matchId: matchId),
      );
    }

    return null;
  }

  _ReplayCandidate _candidateReplay(
    MatchCheckpoint terminal,
    MatchTerminalFacts facts,
  ) {
    if (terminal.replayIneligible) {
      return const _ReplayCandidate.rejected(
        'This match was marked ineligible for replay.',
      );
    }

    final state = terminal.recorderState;
    if (state == null) {
      return const _ReplayCandidate.rejected(
        'No recorder state was captured for this match.',
      );
    }

    final initial = state.initialSnapshot;
    if (initial == null || state.entries.isEmpty) {
      return const _ReplayCandidate.rejected(
        'The match recorded no replayable actions.',
      );
    }

    final transcript = MatchActionTranscript(
      initialSnapshot: initial,
      entries: state.entries,
    );

    // A well-formed transcript is not necessarily a complete one. Run it and
    // check where it lands before promising a replay.
    final mismatch = verifyReplayReconstructsTerminalFacts(
      transcript: transcript,
      facts: facts,
      finalSnapshot: terminal.snapshot,
    );
    if (mismatch != null) {
      return _ReplayCandidate.rejected(mismatch);
    }

    return _ReplayCandidate.accepted(
      MatchReplayRecord(matchId: terminal.matchId, transcript: transcript),
    );
  }
}

class _ReplayCandidate {
  const _ReplayCandidate.accepted(this.record) : reason = null;

  const _ReplayCandidate.rejected(String this.reason) : record = null;

  final MatchReplayRecord? record;
  final String? reason;
}
