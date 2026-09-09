import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/key_value_store.dart';
import 'package:hareeg_table/data/persistence/match_history_repository.dart';
import 'package:hareeg_table/data/persistence/match_repository.dart';
import 'package:hareeg_table/data/persistence/replay_file_store.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_summary.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_id.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_terminal_facts.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';

import '../../support/completed_match_fixture.dart';
import '../../support/test_fixtures.dart';

late CompletedMatchFixture _completed;

void main() {
  late _CountingKeyValueStore store;
  late _CountingReplayFileStore replayFiles;
  late MemoryMatchRepository matches;
  late LocalMatchHistoryRepository repository;

  // One real match, played once and reused, so every replayable fixture has a
  // transcript that genuinely reconstructs its final state without paying for a
  // driven match per test.
  setUpAll(() {
    _completed = buildCompletedMatch();
  });

  setUp(() {
    store = _CountingKeyValueStore();
    replayFiles = _CountingReplayFileStore()..order = store;
    matches = MemoryMatchRepository();
    repository = LocalMatchHistoryRepository(
      store: store,
      replayFiles: replayFiles,
      matches: matches,
    );
  });

  ClassicHareegMatchSnapshot snapshot({int seed = 7}) {
    final round = ClassicHareegRound.deal(
      setup: ClassicHareegSetup.defaults(),
      seed: seed,
    );
    return ClassicHareegMatchSnapshot(
      setup: round.setup,
      hands: round.hands,
      stock: round.stock,
      discardPile: round.discardPile,
      starter: round.starter,
      currentSeat: round.currentSeat,
      turnPhase: round.turnPhase,
      savedAt: DateTime.utc(2026, 8, 22),
    );
  }

  /// Terminal facts from a real completed match.
  ///
  /// Hand-written facts no longer construct: a completed match must end with
  /// exactly one survivor, and inventing one would describe a match that never
  /// finished.
  MatchTerminalFacts facts({DateTime? completedAt}) {
    final base = _completed.facts;
    return MatchTerminalFacts(
      completedAt: completedAt ?? base.completedAt,
      winner: base.winner,
      finalScores: base.finalScores,
      roundCount: base.roundCount,
      eliminationRounds: base.eliminationRounds,
      seats: base.seats,
    );
  }

  /// A terminal checkpoint with no recorder, so it publishes non-replayable.
  /// Nothing here is trying to test replay verification — that has its own
  /// tests — so keeping the payload out of the way keeps these focused on
  /// two-record consistency.
  MatchCheckpoint terminal({
    String matchId = testMatchId,
    DateTime? completedAt,
  }) {
    return MatchCheckpoint(
      matchId: matchId,
      snapshot: snapshot(),
    ).terminalize(facts(completedAt: completedAt));
  }

  /// A terminal checkpoint whose transcript genuinely reconstructs its terminal
  /// facts, so replay verification accepts it and a replay file is written.
  ///
  /// The facts describe the state an empty-progress replay actually reaches —
  /// round 1, nobody eliminated, no scores — because verification runs the
  /// transcript for real and compares where it lands.
  MatchCheckpoint terminalWithRecorder({String matchId = testMatchId}) {
    // A real match driven to an actual winner. Verification replays the
    // transcript for real, so a hand-written action would be rejected as
    // illegal and the match would publish non-replayable.
    return MatchCheckpoint(
      matchId: matchId,
      snapshot: _completed.finalState,
      recorderState: _completed.recorderState,
    ).terminalize(_completed.facts);
  }

  Future<List<MatchHistorySummary>> listed() async {
    final outcome = await repository.listSummaries();
    expect(outcome, isA<MatchHistoryListed>());
    return (outcome as MatchHistoryListed).summaries;
  }

  group('publication', () {
    test('writes a summary and clears both markers', () async {
      matches.savedCheckpoint = terminal();

      final outcome = await repository.archiveCompletedMatch(terminal());

      expect(outcome, isA<MatchArchivePublishedNonReplayable>());
      expect(await listed(), hasLength(1));
      expect(store.values.containsKey(LocalMatchHistoryRepository.pendingKey),
          isFalse);
      expect(matches.savedCheckpoint, isNull);
    });

    test('writes the replay before the summary', () async {
      await repository.archiveCompletedMatch(terminalWithRecorder());

      final replayWrite = store.writeOrder.indexOf('replay');
      final summaryWrite = store.writeOrder.indexOf(
        LocalMatchHistoryRepository.indexKey,
      );
      expect(replayWrite, isNonNegative);
      expect(replayWrite, lessThan(summaryWrite));
    });

    test('never puts transcript data in the key-value store', () async {
      await repository.archiveCompletedMatch(terminalWithRecorder());

      for (final entry in store.values.entries) {
        expect(
          entry.value.contains('"entries"'),
          isFalse,
          reason: 'KV key ${entry.key} contains transcript data',
        );
      }
    });

    test('refuses to archive a live checkpoint', () async {
      final live = MatchCheckpoint(matchId: testMatchId, snapshot: snapshot());

      final outcome = await repository.archiveCompletedMatch(live);

      expect(outcome, isA<MatchArchivePublishFailed>());
      expect(await listed(), isEmpty);
    });

    test('a replay write failure writes no summary and keeps the pending record',
        () async {
      replayFiles.failWrites = true;
      matches.savedCheckpoint = terminalWithRecorder();

      final outcome = await repository.archiveCompletedMatch(
        terminalWithRecorder(),
      );

      expect(outcome, isA<MatchArchivePublishFailed>());
      expect(
        (outcome as MatchArchivePublishFailed).failure.kind,
        MatchHistoryFailureKind.retryable,
      );
      expect(await listed(), isEmpty);
      expect(
        store.values.containsKey(LocalMatchHistoryRepository.pendingKey),
        isTrue,
      );
      expect(matches.savedCheckpoint, isNotNull);
    });

    test('republishing sequentially yields one summary and one replay',
        () async {
      final record = terminalWithRecorder();

      await repository.archiveCompletedMatch(record);
      final before = replayFiles.files[testMatchId];
      await repository.archiveCompletedMatch(record);

      expect(await listed(), hasLength(1));
      expect(replayFiles.files.keys, [testMatchId]);
      // Byte-identical: a rewrite must not produce a different payload.
      expect(replayFiles.files[testMatchId], before);
    });

    test('overlapping republication converges without losing an index update',
        () async {
      final record = terminalWithRecorder();

      await Future.wait([
        repository.archiveCompletedMatch(record),
        repository.archiveCompletedMatch(record),
        repository.archiveCompletedMatch(record),
      ]);

      expect(await listed(), hasLength(1));
      expect(replayFiles.files.keys, [testMatchId]);
    });

    test('a second match does not displace the first', () async {
      await repository.archiveCompletedMatch(terminalWithRecorder());
      await repository.archiveCompletedMatch(
        terminalWithRecorder(matchId: 'm-two-bbbbbbbb'),
      );

      expect(await listed(), hasLength(2));
    });
  });

  group('crash recovery', () {
    test('nothing pending is a no-op that writes nothing', () async {
      final outcome = await repository.recoverPendingArchive();

      expect(outcome, isA<MatchArchiveNothingPending>());
      expect(store.writeOrder, isEmpty);
    });

    test('death after the terminal save, before the pending write, publishes',
        () async {
      // Step 1 landed and step 2 never did: a terminal checkpoint nobody is
      // coming back for.
      matches.savedCheckpoint = terminal();

      final outcome = await repository.recoverPendingArchive();

      expect(outcome, isA<MatchArchivePublishedNonReplayable>());
      expect(await listed(), hasLength(1));
      expect(matches.savedCheckpoint, isNull);
    });

    test('step-1 recovery keeps the original completion time and winner',
        () async {
      // Recovery may run much later. It must republish what was recorded at
      // match-over, not stamp its own clock or infer a winner from the board.
      final completed = DateTime.utc(2026, 8, 22, 10);
      matches.savedCheckpoint = terminal(completedAt: completed);

      await repository.recoverPendingArchive();

      final summary = (await listed()).single;
      expect(summary.completedAt, completed);
      expect(summary.winner, _completed.facts.winner);
    });

    test('death after the pending write, before the replay, publishes',
        () async {
      matches.savedCheckpoint = terminalWithRecorder();
      store.values[LocalMatchHistoryRepository.pendingKey] = jsonEncode(
        PendingMatchArchive(matchId: testMatchId).toJson(),
      );

      final outcome = await repository.recoverPendingArchive();

      expect(outcome, isA<MatchArchivePublished>());
      expect(await listed(), hasLength(1));
      expect(replayFiles.files.keys, [testMatchId]);
    });

    test('death after the replay write, before the summary, yields one pair',
        () async {
      matches.savedCheckpoint = terminalWithRecorder();
      store.values[LocalMatchHistoryRepository.pendingKey] = jsonEncode(
        PendingMatchArchive(matchId: testMatchId).toJson(),
      );
      // The replay is already on disk from the interrupted attempt.
      await replayFiles.writeFile(testMatchId, 'stale');

      await repository.recoverPendingArchive();

      expect(await listed(), hasLength(1));
      expect(replayFiles.files.keys, [testMatchId]);
      expect(replayFiles.files[testMatchId], isNot('stale'));
    });

    test('death after the summary write, before the pending clear, converges',
        () async {
      await repository.archiveCompletedMatch(terminal());
      // Re-create the marker as though the clear never landed.
      store.values[LocalMatchHistoryRepository.pendingKey] = jsonEncode(
        PendingMatchArchive(matchId: testMatchId).toJson(),
      );

      final outcome = await repository.recoverPendingArchive();

      expect(outcome, isA<MatchArchiveAlreadyPublished>());
      expect(await listed(), hasLength(1));
      expect(
        store.values.containsKey(LocalMatchHistoryRepository.pendingKey),
        isFalse,
      );
    });

    test('death after the pending clear, before the checkpoint clear, converges',
        () async {
      await repository.archiveCompletedMatch(terminal());
      // The summary is published but the terminal checkpoint survived.
      matches.savedCheckpoint = terminal();

      final outcome = await repository.recoverPendingArchive();

      expect(outcome, isA<MatchArchiveAlreadyPublished>());
      expect(await listed(), hasLength(1));
      expect(matches.savedCheckpoint, isNull);
    });

    test('a corrupt pending record is a typed failure, not a silent clear',
        () async {
      store.values[LocalMatchHistoryRepository.pendingKey] = '{not json';

      final outcome = await repository.recoverPendingArchive();

      expect(outcome, isA<MatchArchivePublishFailed>());
      expect(
        store.values.containsKey(LocalMatchHistoryRepository.pendingKey),
        isTrue,
      );
    });
  });

  group('listing', () {
    test('is newest first with an ascending match-id tiebreak', () async {
      await repository.archiveCompletedMatch(
        terminal(matchId: 'm-old-aaaaaaaa', completedAt: DateTime.utc(2026, 1)),
      );
      await repository.archiveCompletedMatch(
        terminal(matchId: 'm-tieb-bbbbbbbb', completedAt: DateTime.utc(2026, 6)),
      );
      await repository.archiveCompletedMatch(
        terminal(matchId: 'm-tiea-cccccccc', completedAt: DateTime.utc(2026, 6)),
      );

      final summaries = await listed();

      expect(
        [for (final summary in summaries) summary.matchId],
        // Equal timestamps resolve by id ascending, so the order is pinned
        // rather than incidental.
        ['m-tiea-cccccccc', 'm-tieb-bbbbbbbb', 'm-old-aaaaaaaa'],
      );
    });

    test('reads no replay payloads, however many matches there are', () async {
      for (final id in ['m-a-aaaaaaaa', 'm-b-bbbbbbbb', 'm-c-cccccccc']) {
        await repository.archiveCompletedMatch(
          terminalWithRecorder(matchId: id),
        );
      }
      replayFiles.resetCounts();

      await repository.listSummaries();

      expect(replayFiles.listKeysCalls, 1);
      expect(replayFiles.readCalls, 0);
    });

    test('repairs a summary whose replay file vanished', () async {
      await repository.archiveCompletedMatch(terminalWithRecorder());
      replayFiles.files.remove(testMatchId);

      final outcome = await repository.listSummaries();

      expect(outcome, isA<MatchHistoryListed>());
      final listing = outcome as MatchHistoryListed;
      expect(listing.repairedMatchIds, [testMatchId]);
      expect(listing.summaries.single.replayable, isFalse);
    });

    test('persists the repair and batches multiple into one write', () async {
      for (final id in ['m-a-aaaaaaaa', 'm-b-bbbbbbbb']) {
        await repository.archiveCompletedMatch(
          terminalWithRecorder(matchId: id),
        );
      }
      replayFiles.files.clear();
      store.resetCounts();

      await repository.listSummaries();

      expect(store.writesTo(LocalMatchHistoryRepository.indexKey), 1);

      // The repair is durable: a second listing does not need to redo it.
      store.resetCounts();
      final second = await repository.listSummaries();
      expect(
        (second as MatchHistoryListed).repairedMatchIds,
        isEmpty,
      );
      expect(second.summaries.every((s) => !s.replayable), isTrue);
    });

    test('a replay-store failure mutates nothing and is not an empty list',
        () async {
      await repository.archiveCompletedMatch(terminalWithRecorder());
      replayFiles.failListKeys = true;

      final outcome = await repository.listSummaries();

      expect(outcome, isA<MatchHistoryListFailed>());
      expect(
        (outcome as MatchHistoryListFailed).failure.kind,
        MatchHistoryFailureKind.retryable,
      );

      // Nothing was downgraded on the way past.
      replayFiles.failListKeys = false;
      expect((await listed()).single.replayable, isTrue);
    });

    test('a false winner publishes non-replayable with no replay file', () async {
      // End-to-end counterpart to the verification unit test: a real transcript
      // paired with self-consistent facts naming the wrong winner must not
      // produce a replayable summary, and must leave no replay behind.
      final trueWinner = _completed.facts.winner;
      final impostor = PlayerSeat.values.firstWhere(
        (seat) => seat != trueWinner,
      );
      final forged = MatchCheckpoint(
        matchId: testMatchId,
        snapshot: _completed.finalState,
        recorderState: _completed.recorderState,
      ).terminalize(
        MatchTerminalFacts(
          completedAt: _completed.facts.completedAt,
          winner: impostor,
          finalScores: _completed.facts.finalScores,
          roundCount: _completed.facts.roundCount,
          eliminationRounds: {
            for (final seat in PlayerSeat.values)
              if (seat != impostor) seat: _completed.facts.roundCount,
          },
          seats: PlayerSeat.values,
        ),
      );

      final outcome = await repository.archiveCompletedMatch(forged);

      expect(outcome, isA<MatchArchivePublishedNonReplayable>());
      expect((await listed()).single.replayable, isFalse);
      expect(replayFiles.files, isEmpty);
    });

    test('a corrupt index is a typed corrupt failure', () async {
      store.values[LocalMatchHistoryRepository.indexKey] = '{not json';

      final outcome = await repository.listSummaries();

      expect(outcome, isA<MatchHistoryListFailed>());
      expect(
        (outcome as MatchHistoryListFailed).failure.kind,
        MatchHistoryFailureKind.corrupt,
      );
    });
  });

  group('opening a replay', () {
    test('loads a stored replay record', () async {
      await repository.archiveCompletedMatch(terminalWithRecorder());

      final outcome = await repository.openReplay(testMatchId);

      expect(outcome, isA<MatchReplayOpened>());
      expect((outcome as MatchReplayOpened).record.matchId, testMatchId);
    });

    test('a transient read failure keeps the summary replayable', () async {
      // A backend failure says nothing about whether the replay exists.
      // Downgrading here would discard a working replay over a blip.
      await repository.archiveCompletedMatch(terminalWithRecorder());
      replayFiles.failReads = true;

      final outcome = await repository.openReplay(testMatchId);

      expect(outcome, isA<MatchReplayOpenFailed>());
      expect(
        (outcome as MatchReplayOpenFailed).failure.kind,
        MatchHistoryFailureKind.retryable,
      );

      replayFiles.failReads = false;
      expect((await listed()).single.replayable, isTrue);
    });

    test('a missing file repairs the summary to non-replayable', () async {
      await repository.archiveCompletedMatch(terminalWithRecorder());
      replayFiles.files.remove(testMatchId);

      final outcome = await repository.openReplay(testMatchId);

      expect(outcome, isA<MatchReplayUnavailable>());
      expect((outcome as MatchReplayUnavailable).summary.replayable, isFalse);
      expect((await listed()).single.replayable, isFalse);
    });

    test('unreadable bytes repair the summary to non-replayable', () async {
      await repository.archiveCompletedMatch(terminalWithRecorder());
      replayFiles.files[testMatchId] = 'not json at all';

      final outcome = await repository.openReplay(testMatchId);

      expect(outcome, isA<MatchReplayUnavailable>());
      expect((await listed()).single.replayable, isFalse);
    });

    test('a record carrying another match id is treated as corrupt', () async {
      // The bytes decode cleanly — they are simply somebody else's match.
      // Trusting the file name alone would open the wrong game as this one.
      await repository.archiveCompletedMatch(terminalWithRecorder());
      final foreign = await replayFiles.readFile(testMatchId);
      replayFiles.files[testMatchId] = foreign!.replaceFirst(
        '"matchId":"$testMatchId"',
        '"matchId":"m-other-dddddddd"',
      );

      final outcome = await repository.openReplay(testMatchId);

      expect(outcome, isA<MatchReplayUnavailable>());
      expect((await listed()).single.replayable, isFalse);
    });

    test('an unknown match is a typed failure', () async {
      final outcome = await repository.openReplay('m-none-aaaaaaaa');

      expect(outcome, isA<MatchReplayOpenFailed>());
    });
  });

  group('deletion', () {
    test('removes both records', () async {
      await repository.archiveCompletedMatch(terminalWithRecorder());

      final outcome = await repository.deleteMatch(testMatchId);

      expect(outcome, isA<MatchHistoryDeleted>());
      expect(await listed(), isEmpty);
      expect(replayFiles.files, isEmpty);
    });

    test('an already-absent replay does not block summary deletion', () async {
      await repository.archiveCompletedMatch(terminal());
      expect(replayFiles.files, isEmpty);

      final outcome = await repository.deleteMatch(testMatchId);

      expect(outcome, isA<MatchHistoryDeleted>());
      expect(await listed(), isEmpty);
    });

    test('a thrown replay-delete error keeps the summary visible', () async {
      await repository.archiveCompletedMatch(terminalWithRecorder());
      replayFiles.failDeletes = true;

      final outcome = await repository.deleteMatch(testMatchId);

      expect(outcome, isA<MatchHistoryDeleteFailed>());
      replayFiles.failDeletes = false;
      expect(await listed(), hasLength(1));
    });

    test('a failed index write leaves an entry that self-heals on next list',
        () async {
      await repository.archiveCompletedMatch(terminalWithRecorder());
      store.failWritesTo.add(LocalMatchHistoryRepository.indexKey);

      final outcome = await repository.deleteMatch(testMatchId);

      expect(outcome, isA<MatchHistoryDeleteFailed>());
      store.failWritesTo.clear();

      // The replay is gone, so the surviving summary repairs rather than
      // offering a replay that cannot open.
      final summaries = await listed();
      expect(summaries.single.replayable, isFalse);
    });
  });

  group('a duplicated summary id is corruption on every path', () {
    /// Writes an index holding the same match twice.
    Future<void> seedDuplicate() async {
      await repository.archiveCompletedMatch(terminalWithRecorder());
      final raw = store.values[LocalMatchHistoryRepository.indexKey]!;
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      final entries = decoded['summaries']! as List<Object?>;
      decoded['summaries'] = [entries.single, entries.single];
      store.values[LocalMatchHistoryRepository.indexKey] = jsonEncode(decoded);
    }

    test('listing reports corrupt rather than returning duplicates', () async {
      await seedDuplicate();

      final outcome = await repository.listSummaries();

      expect(outcome, isA<MatchHistoryListFailed>());
      expect(
        (outcome as MatchHistoryListFailed).failure.kind,
        MatchHistoryFailureKind.corrupt,
      );
    });

    test('opening reports corrupt', () async {
      await seedDuplicate();

      final outcome = await repository.openReplay(testMatchId);

      expect(outcome, isA<MatchReplayOpenFailed>());
      expect(
        (outcome as MatchReplayOpenFailed).failure.kind,
        MatchHistoryFailureKind.corrupt,
      );
    });

    test('deleting reports corrupt', () async {
      await seedDuplicate();

      final outcome = await repository.deleteMatch(testMatchId);

      expect(outcome, isA<MatchHistoryDeleteFailed>());
      expect(
        (outcome as MatchHistoryDeleteFailed).failure.kind,
        MatchHistoryFailureKind.corrupt,
      );
    });

    test('publication reports corrupt instead of throwing', () async {
      // This is the path that used to leak: publication asks the index for
      // *the* summary of a match, and two of them made `.single` throw a raw
      // StateError straight out of the repository.
      await seedDuplicate();

      final outcome = await repository.archiveCompletedMatch(
        terminalWithRecorder(),
      );

      expect(outcome, isA<MatchArchivePublishFailed>());
      expect(
        (outcome as MatchArchivePublishFailed).failure.kind,
        MatchHistoryFailureKind.corrupt,
      );
    });

    test('recovery reports corrupt instead of throwing', () async {
      await seedDuplicate();
      store.values[LocalMatchHistoryRepository.pendingKey] = jsonEncode(
        PendingMatchArchive(matchId: testMatchId).toJson(),
      );
      matches.savedCheckpoint = null;

      final outcome = await repository.recoverPendingArchive();

      expect(outcome, isA<MatchArchivePublishFailed>());
      expect(
        (outcome as MatchArchivePublishFailed).failure.kind,
        MatchHistoryFailureKind.corrupt,
      );
    });
  });

  group('id collision', () {
    test('reports an id already used by a summary', () async {
      await repository.archiveCompletedMatch(terminal());

      expect(await repository.isMatchIdTaken(testMatchId), isTrue);
      expect(await repository.isMatchIdTaken('m-free-aaaaaaaa'), isFalse);
    });

    test('reports an id already used by a replay file', () async {
      await replayFiles.writeFile('m-orphan-aaaaaaa', 'payload');

      expect(await repository.isMatchIdTaken('m-orphan-aaaaaaa'), isTrue);
    });

    test('reserve mints again rather than returning a colliding id', () async {
      // The production path: minting consults durable history, so an id that
      // would overwrite a stored match is rejected and re-minted.
      await repository.archiveCompletedMatch(terminalWithRecorder());
      final stored = (await listed()).single.matchId;

      var handedOut = 0;
      final reserved = await _StubMinter(
        candidates: [stored, 'm-fresh-eeeeeeee'],
        onMint: () => handedOut++,
      ).reserve(isTaken: repository.isMatchIdTaken);

      expect(reserved, 'm-fresh-eeeeeeee');
      expect(handedOut, 2, reason: 'the colliding candidate must be rejected');
    });

    test('an unreadable index is treated as taken rather than free', () async {
      // Accepting an id we cannot prove is free could overwrite a stored match.
      store.values[LocalMatchHistoryRepository.indexKey] = '{not json';

      expect(await repository.isMatchIdTaken('m-any-aaaaaaaa'), isTrue);
    });
  });
}

/// Hands out a fixed candidate sequence so a collision can be forced.
class _StubMinter implements MatchIdMinter {
  _StubMinter({required this.candidates, required this.onMint});

  final List<String> candidates;
  final void Function() onMint;
  int _index = 0;

  @override
  String mint({required bool Function(String candidate) isTaken}) {
    onMint();
    return candidates[_index++];
  }

  @override
  Future<String> reserve({
    required Future<bool> Function(String candidate) isTaken,
  }) async {
    for (var attempt = 0; attempt < candidates.length; attempt++) {
      final candidate = mint(isTaken: (_) => false);
      if (!await isTaken(candidate)) {
        return candidate;
      }
    }
    throw StateError('No free candidate.');
  }
}

class _CountingKeyValueStore implements KeyValueStore {
  final Map<String, String> values = {};
  final List<String> writeOrder = [];
  final Set<String> failWritesTo = {};

  void resetCounts() => writeOrder.clear();

  int writesTo(String key) => writeOrder.where((k) => k == key).length;

  @override
  Future<String?> loadString(String key) async => values[key];

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> saveString(String key, String value) async {
    if (failWritesTo.contains(key)) {
      throw StateError('Simulated key-value write failure for $key.');
    }
    writeOrder.add(key);
    values[key] = value;
  }
}

class _CountingReplayFileStore implements ReplayFileStore {
  final Map<String, String> files = {};
  int listKeysCalls = 0;
  int readCalls = 0;
  bool failWrites = false;
  bool failReads = false;
  bool failDeletes = false;
  bool failListKeys = false;

  /// The shared store, so replay writes are visible in one ordering with the
  /// key-value writes.
  _CountingKeyValueStore? order;

  void resetCounts() {
    listKeysCalls = 0;
    readCalls = 0;
  }

  ReplayFileStoreException _failure(String? key) {
    return ReplayFileStoreException(
      code: ReplayFileStoreErrorCode.ioError,
      message: 'Simulated replay store failure.',
      key: key,
    );
  }

  @override
  Future<bool> deleteFile(String key) async {
    if (failDeletes) {
      throw _failure(key);
    }
    return files.remove(key) != null;
  }

  @override
  Future<List<String>> listKeys() async {
    listKeysCalls++;
    if (failListKeys) {
      throw _failure(null);
    }
    return files.keys.toList()..sort();
  }

  @override
  Future<String?> readFile(String key) async {
    readCalls++;
    if (failReads) {
      throw _failure(key);
    }
    return files[key];
  }

  @override
  Future<void> writeFile(String key, String contents) async {
    if (failWrites) {
      throw _failure(key);
    }
    // Recorded in the same list as the key-value writes so ordering between
    // the two stores is assertable.
    order?.writeOrder.add('replay');
    files[key] = contents;
  }
}
