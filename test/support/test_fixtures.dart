import 'dart:async';
import 'dart:convert';

import 'package:hareeg_table/data/persistence/key_value_store.dart';
import 'package:hareeg_table/data/persistence/learning_progress_repository.dart';
import 'package:hareeg_table/data/persistence/match_history_repository.dart';
import 'package:hareeg_table/data/persistence/match_repository.dart';
import 'package:hareeg_table/data/persistence/replay_file_store.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_fifty_counters.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_summary.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

/// In-memory [KeyValueStore] shared by the persistence repository tests.
class MemoryKeyValueStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> loadString(String key) async => values[key];

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> saveString(String key, String value) async {
    values[key] = value;
  }
}

/// In-memory preferences repository used by widget + integration tests.
class MemoryPreferencesRepository implements PreferencesRepository {
  GamePreferences preferences = GamePreferences.defaults();

  @override
  Future<GamePreferences> loadPreferences() async => preferences;

  @override
  Future<void> savePreferences(GamePreferences preferences) async {
    this.preferences = preferences;
  }
}

/// In-memory learning progress repository.
class MemoryLearningProgressRepository
    with SerializedLearningProgressUpdate
    implements LearningProgressRepository {
  MemoryLearningProgressRepository({LearningProgress? progress})
    : progress = progress ?? LearningProgress.defaults();

  LearningProgress progress;

  @override
  Future<LearningProgress> loadProgress() async => progress;

  @override
  Future<void> saveProgress(LearningProgress progress) async {
    this.progress = progress;
  }
}

/// A valid match id for fixtures that do not care which id they get.
const String testMatchId = 'm-test-aaaaaaaa';

/// In-memory match repository.
///
/// Stores a [MatchCheckpoint], which is what the repository interface deals in
/// now, while keeping a [saved] snapshot view so existing tests read and write
/// the same thing they always did.
class MemoryMatchRepository implements MatchRepository {
  MemoryMatchRepository({
    ClassicHareegMatchSnapshot? saved,
    MatchCheckpoint? checkpoint,
  }) : savedCheckpoint =
           checkpoint ?? (saved == null ? null : checkpointForSnapshot(saved));

  /// The stored checkpoint.
  MatchCheckpoint? savedCheckpoint;

  /// Snapshot held by the stored checkpoint, if any.
  ClassicHareegMatchSnapshot? get saved => savedCheckpoint?.snapshot;

  set saved(ClassicHareegMatchSnapshot? snapshot) {
    savedCheckpoint = snapshot == null ? null : checkpointForSnapshot(snapshot);
  }

  @override
  Future<void> abandonActiveMatch() async {
    savedCheckpoint = null;
  }

  @override
  Future<ActiveMatchLoadOutcome> loadActiveMatch() async {
    final checkpoint = savedCheckpoint;
    return checkpoint == null
        ? const ActiveMatchAbsent()
        : ActiveMatchLoaded(checkpoint);
  }

  @override
  Future<void> saveActiveMatch(MatchCheckpoint checkpoint) async {
    savedCheckpoint = checkpoint;
  }
}

/// In-memory completed-match history.
///
/// Records what it was asked to do so tests can assert that an abandoned match
/// wrote nothing at all, rather than only that history looks empty.
class MemoryMatchHistoryRepository implements MatchHistoryRepository {
  MemoryMatchHistoryRepository({this.matches});

  /// Active-match storage, cleared on a successful archive.
  ///
  /// Clearing the terminal checkpoint is the last step of publication in the
  /// real repository, so the fake does it too — otherwise a completed match
  /// would still look resumable in tests but not in production.
  final MatchRepository? matches;

  /// Published summaries, keyed by match id.
  final Map<String, MatchHistorySummary> summaries = {};

  /// Terminal checkpoints handed over for archiving, in order.
  final List<MatchCheckpoint> archiveCalls = [];

  /// Match ids whose replay was reported unusable, in order.
  final List<String> repairCalls = [];

  @override
  Future<MatchReplayRepairOutcome> repairUnusableReplay({
    required String matchId,
    required String reason,
  }) async {
    repairCalls.add(matchId);
    final summary = summaries[matchId];
    if (summary == null) {
      return MatchReplayRepairFailed(
        MatchHistoryFailure(
          kind: MatchHistoryFailureKind.corrupt,
          matchId: matchId,
          message: 'No history entry exists for this match.',
        ),
      );
    }
    final repaired = summary.withReplayable(false);
    summaries[matchId] = repaired;
    return MatchReplayRepaired(repaired);
  }

  @override
  Future<MatchArchivePublishOutcome> archiveCompletedMatch(
    MatchCheckpoint terminal,
  ) async {
    archiveCalls.add(terminal);
    final facts = terminal.terminalFacts!;
    final summary = MatchHistorySummary(
      matchId: terminal.matchId,
      completedAt: facts.completedAt,
      setup: terminal.snapshot.setup,
      finalScores: facts.finalScores,
      winner: facts.winner,
      southPlacement: facts.standing.placementOf(PlayerSeat.south) ?? 0,
      roundCount: facts.roundCount,
      coachWasEnabled: terminal.coachWasEnabled,
      fiftyCounters: terminal.fiftyCounters,
      fiftyCountersComplete: terminal.fiftyCountersComplete,
      replayable: terminal.recorderState != null && !terminal.replayIneligible,
    );
    summaries[terminal.matchId] = summary;
    await matches?.abandonActiveMatch();
    return MatchArchivePublished(summary);
  }

  @override
  Future<MatchHistoryDeleteOutcome> deleteMatch(String matchId) async {
    summaries.remove(matchId);
    return const MatchHistoryDeleted();
  }

  @override
  Future<bool> isMatchIdTaken(String candidate) async =>
      summaries.containsKey(candidate);

  @override
  Future<MatchHistoryListOutcome> listSummaries() async {
    return MatchHistoryListed(
      summaries: summaries.values.toList(),
      repairedMatchIds: const [],
    );
  }

  @override
  Future<MatchReplayOpenOutcome> openReplay(String matchId) async {
    return MatchReplayOpenFailed(
      const MatchHistoryFailure(
        kind: MatchHistoryFailureKind.corrupt,
        message: 'The in-memory fixture stores no replay payloads.',
      ),
    );
  }

  @override
  Future<MatchArchivePublishOutcome> recoverPendingArchive() async =>
      const MatchArchiveNothingPending();
}

/// Wraps [snapshot] in a minimal checkpoint for fixtures.
MatchCheckpoint checkpointForSnapshot(
  ClassicHareegMatchSnapshot snapshot, {
  String matchId = testMatchId,
}) {
  return MatchCheckpoint(matchId: matchId, snapshot: snapshot);
}

/// Builds a reproducible snapshot for the south seat to drive through the UI.
ClassicHareegMatchSnapshot snapshotWithSouthHand(
  List<HareegCard> southHand, {
  ClassicHareegSetup? setup,
  PlayerSeat currentSeat = PlayerSeat.south,
  TurnPhase turnPhase = TurnPhase.action,
  OpeningState? openingState,
}) {
  final resolvedSetup = setup ?? ClassicHareegSetup.defaults();
  final base = ClassicHareegRound.deal(setup: resolvedSetup, seed: 7);
  return ClassicHareegMatchSnapshot(
    setup: resolvedSetup,
    hands: {
      ...base.hands,
      PlayerSeat.south: [...southHand, ...base.hands[PlayerSeat.south]!],
    },
    stock: base.stock,
    discardPile: base.discardPile,
    starter: base.starter,
    currentSeat: currentSeat,
    turnPhase: turnPhase,
    openingState: openingState,
    savedAt: DateTime.utc(2026, 5, 18),
  );
}

/// Builds an opened state for the named seat (used by tests that need the
/// player to already be opened).
OpeningState openedState(PlayerSeat seat) {
  final setup = ClassicHareegSetup.defaults();
  return ClassicHareegOpeningRules.applyOpening(
    state: OpeningState.initial(setup.openingRequirement),
    seat: seat,
    melds: [
      PlacedMeld(cards: const [], valueSnapshot: setup.openingRequirement),
    ],
  );
}

// --- match history and statistics fixtures -------------------------------

/// Builds a completed-match summary for history and statistics fixtures.
///
/// Defaults describe an ordinary south win with measured Fifty counters, so a
/// test only states the facts it is actually about.
MatchHistorySummary historySummary({
  required String matchId,
  DateTime? completedAt,
  ClassicHareegSetup? setup,
  Map<PlayerSeat, int>? finalScores,
  PlayerSeat winner = PlayerSeat.south,
  int southPlacement = 1,
  int roundCount = 3,
  bool coachWasEnabled = false,
  int southFiftyAttempts = 0,
  int southFiftySuccesses = 0,
  bool fiftyCountersComplete = true,
  bool replayable = true,
}) {
  return MatchHistorySummary(
    matchId: matchId,
    completedAt: completedAt ?? DateTime.utc(2026, 8, 22, 10),
    setup: setup ?? ClassicHareegSetup.defaults(),
    finalScores:
        finalScores ??
        const {
          PlayerSeat.south: 10,
          PlayerSeat.east: 30,
          PlayerSeat.north: 40,
          PlayerSeat.west: 50,
        },
    winner: winner,
    southPlacement: southPlacement,
    roundCount: roundCount,
    coachWasEnabled: coachWasEnabled,
    fiftyCounters: MatchFiftyCounters(
      attempts: {PlayerSeat.south: southFiftyAttempts},
      successes: {PlayerSeat.south: southFiftySuccesses},
    ),
    fiftyCountersComplete: fiftyCountersComplete,
    replayable: replayable,
  );
}

/// Counts what a surface asks of the replay store.
///
/// Exists so "history is summary-only" can be asserted as a fact about calls
/// rather than inferred from the absence of a visible payload.
class CountingReplayFileStore implements ReplayFileStore {
  /// Wraps [inner], counting every call that reaches it.
  CountingReplayFileStore(this.inner);

  /// The store doing the actual work.
  final ReplayFileStore inner;

  /// Calls to [readFile]. Must stay zero for listing and statistics.
  int readFileCalls = 0;

  /// Calls to [listKeys].
  int listKeysCalls = 0;

  @override
  Future<bool> deleteFile(String key) => inner.deleteFile(key);

  @override
  Future<List<String>> listKeys() {
    listKeysCalls++;
    return inner.listKeys();
  }

  @override
  Future<String?> readFile(String key) {
    readFileCalls++;
    return inner.readFile(key);
  }

  @override
  Future<void> writeFile(String key, String contents) =>
      inner.writeFile(key, contents);
}

/// A real [LocalMatchHistoryRepository] over in-memory stores.
///
/// Widget tests use this rather than [MemoryMatchHistoryRepository] wherever
/// the behaviour under test belongs to production code — ordering, drift
/// repair, and two-record deletion all live in the real repository, and a fake
/// that returned a pre-sorted list would prove none of them.
typedef HistoryHarness = ({
  LocalMatchHistoryRepository repository,
  MemoryKeyValueStore store,
  CountingReplayFileStore replayFiles,
});

/// Builds a real history repository over memory stores, seeded with
/// [summaries] and a replay file for each summary marked replayable.
HistoryHarness historyHarness({
  List<MatchHistorySummary> summaries = const [],
  Set<String> withoutReplayFiles = const {},
}) {
  final store = MemoryKeyValueStore();
  final replayFiles = CountingReplayFileStore(MemoryReplayFileStore());

  if (summaries.isNotEmpty) {
    store.values[LocalMatchHistoryRepository.indexKey] = jsonEncode({
      'version': matchHistoryIndexVersion,
      'summaries': [for (final summary in summaries) summary.toJson()],
    });
  }

  for (final summary in summaries) {
    if (!summary.replayable || withoutReplayFiles.contains(summary.matchId)) {
      continue;
    }
    // Written straight through the inner store so seeding does not inflate the
    // call counters the tests assert on. MemoryReplayFileStore writes its map
    // before returning its Future (no await); this is not asynchronous I/O.
    unawaited(replayFiles.inner.writeFile(summary.matchId, '{"seeded":true}'));
  }

  return (
    repository: LocalMatchHistoryRepository(
      store: store,
      replayFiles: replayFiles,
      matches: MemoryMatchRepository(),
    ),
    store: store,
    replayFiles: replayFiles,
  );
}

/// Writes bytes that decode as neither a valid index nor valid JSON.
///
/// Drives the repository's genuine corrupt path — a `FormatException` out of
/// its index read — rather than hand-building a corrupt outcome, so the copy
/// and affordances under test are the ones a real damaged store produces.
void corruptHistoryIndex(MemoryKeyValueStore store) {
  store.values[LocalMatchHistoryRepository.indexKey] = '{"version":';
}
