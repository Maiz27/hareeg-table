import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/key_value_store.dart';
import 'package:hareeg_table/data/persistence/match_history_repository.dart';
import 'package:hareeg_table/data/persistence/replay_file_store.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_checkpoint.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_summary.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/match_replay_timeline.dart';

import '../../support/completed_match_fixture.dart';
import '../../support/test_fixtures.dart';

const _matchId = 'm-repair-aaaaaaaa';
const _slow = Timeout(Duration(minutes: 5));

late CompletedMatchFixture _completed;

/// Rewrites the stored replay so one entry names the wrong seat.
///
/// This is deliberately *post-publication drift*: the match is archived
/// normally, through the production repository, with a replay that genuinely
/// verified. Only afterwards is the payload rewritten behind the repository's
/// back — which is the real-world shape of this failure, and the only shape in
/// which the summary is still honestly marked replayable.
///
/// The result still decodes. That is the whole point: a corrupt file is already
/// handled at open, and the gap this closes is the record that decodes and then
/// cannot be rebuilt.
String _driftedPayload(String stored) {
  final json = jsonDecode(stored) as Map<String, Object?>;
  final transcript = (json['transcript']! as Map).cast<String, Object?>();
  final entries = (transcript['entries']! as List)
      .map((e) => (e as Map).cast<String, Object?>())
      .toList();

  final target = entries[40];
  final seat = target['seat'] as String;
  target['seat'] = PlayerSeat.values
      .firstWhere((s) => s.name != seat)
      .name;

  transcript['entries'] = entries;
  json['transcript'] = transcript;
  return jsonEncode(json);
}

void main() {
  late KeyValueStore store;
  late ReplayFileStore replayFiles;
  late MemoryMatchRepository matches;
  late LocalMatchHistoryRepository repository;

  setUpAll(() => _completed = buildCompletedMatch());

  setUp(() {
    store = MemoryKeyValueStore();
    replayFiles = MemoryReplayFileStore();
    matches = MemoryMatchRepository();
    repository = LocalMatchHistoryRepository(
      store: store,
      replayFiles: replayFiles,
      matches: matches,
    );
  });

  /// Publishes a genuine, replayable match through the production path.
  Future<void> archiveGenuineMatch() async {
    final outcome = await repository.archiveCompletedMatch(
      MatchCheckpoint(
        matchId: _matchId,
        snapshot: _completed.finalState,
        recorderState: _completed.recorderState,
      ).terminalize(_completed.facts),
    );
    expect(
      outcome,
      isA<MatchArchivePublished>(),
      reason: 'the fixture must archive as genuinely replayable',
    );
  }

  Future<MatchHistorySummary> onlySummary() async {
    final outcome = await repository.listSummaries();
    expect(outcome, isA<MatchHistoryListed>());
    final summaries = (outcome as MatchHistoryListed).summaries;
    expect(summaries, hasLength(1));
    return summaries.single;
  }

  Future<void> driftTheReplay() async {
    final stored = await replayFiles.readFile(_matchId);
    expect(stored, isNotNull, reason: 'the archive must have written a replay');
    await replayFiles.writeFile(_matchId, _driftedPayload(stored!));
  }

  test('a drifted replay still decodes and still reads as replayable', timeout: _slow, () async {
    await archiveGenuineMatch();
    await driftTheReplay();

    // Decodes: so `openReplay` reports success and the entry keeps advertising
    // a replay. That is precisely the dead link this repair exists to close.
    final opened = await repository.openReplay(_matchId);
    expect(opened, isA<MatchReplayOpened>());
    expect((await onlySummary()).replayable, isTrue);

    // ...and yet it cannot be rebuilt.
    final built = MatchReplayTimeline.build(
      (opened as MatchReplayOpened).record.transcript,
    );
    expect(built, isA<ReplayTimelineFailed>());
    expect(
      (built as ReplayTimelineFailed).failure.kind,
      ReplayTimelineFailureKind.seatMismatch,
    );
  });

  test('repairing marks the entry non-replayable durably', timeout: _slow, () async {
    await archiveGenuineMatch();
    await driftTheReplay();

    final repair = await repository.repairUnusableReplay(
      matchId: _matchId,
      reason: 'entry 40 names the wrong seat',
    );
    expect(repair, isA<MatchReplayRepaired>());
    expect((repair as MatchReplayRepaired).summary.replayable, isFalse);

    // A fresh listing, not the object the repair handed back.
    expect((await onlySummary()).replayable, isFalse);

    // And a fresh repository over the same stores — which is what "durable"
    // has to mean, rather than "this instance remembers".
    final relaunched = LocalMatchHistoryRepository(
      store: store,
      replayFiles: replayFiles,
      matches: matches,
    );
    final afterRelaunch = await relaunched.listSummaries();
    expect(
      ((afterRelaunch as MatchHistoryListed).summaries.single).replayable,
      isFalse,
    );
  });

  test('the match itself is kept, only its replay is withdrawn', timeout: _slow, () async {
    await archiveGenuineMatch();
    final before = await onlySummary();
    await driftTheReplay();
    await repository.repairUnusableReplay(matchId: _matchId, reason: 'drift');

    final after = await onlySummary();
    // Losing a replay must not lose the match: the player's record of having
    // played it is the more important half.
    expect(after.matchId, before.matchId);
    expect(after.completedAt, before.completedAt);
    expect(after.winner, before.winner);
    expect(after.southPlacement, before.southPlacement);
    expect(after.replayable, isFalse);
  });

  test('a repair that cannot be written reports retryable and changes nothing', timeout: _slow, () async {
    await archiveGenuineMatch();
    await driftTheReplay();

    final failing = _WriteFailingKeyValueStore(store);
    final blocked = LocalMatchHistoryRepository(
      store: failing,
      replayFiles: replayFiles,
      matches: matches,
    );

    final outcome = await blocked.repairUnusableReplay(
      matchId: _matchId,
      reason: 'drift',
    );
    expect(outcome, isA<MatchReplayRepairFailed>());
    expect(
      (outcome as MatchReplayRepairFailed).failure.kind,
      MatchHistoryFailureKind.retryable,
    );

    // Still replayable, because nothing was actually repaired. Reporting the
    // entry as fixed here would send the player back to a list that still
    // offers the same dead link, with nothing to retry.
    expect((await onlySummary()).replayable, isTrue);

    // Attempt counting: the first try failed, the second — through a working
    // store — succeeds, so "retry" means a real second attempt.
    expect(failing.writeAttempts, 1);
    final second = await repository.repairUnusableReplay(
      matchId: _matchId,
      reason: 'drift',
    );
    expect(second, isA<MatchReplayRepaired>());
    expect((await onlySummary()).replayable, isFalse);
  });

  test('repairing a match that is not in history is refused, not invented', timeout: _slow, () async {
    await archiveGenuineMatch();

    final outcome = await repository.repairUnusableReplay(
      matchId: 'm-missing-bbbbbbbb',
      reason: 'drift',
    );
    expect(outcome, isA<MatchReplayRepairFailed>());
    expect(
      (outcome as MatchReplayRepairFailed).failure.kind,
      MatchHistoryFailureKind.corrupt,
    );
    expect((await onlySummary()).replayable, isTrue);
  });
}

/// A store that refuses to write, so a repair can fail the way a full disk
/// would.
class _WriteFailingKeyValueStore implements KeyValueStore {
  _WriteFailingKeyValueStore(this._inner);

  final KeyValueStore _inner;
  int writeAttempts = 0;

  @override
  Future<String?> loadString(String key) => _inner.loadString(key);

  @override
  Future<void> saveString(String key, String value) async {
    writeAttempts += 1;
    throw StateError('write refused');
  }

  @override
  Future<void> remove(String key) => _inner.remove(key);
}
