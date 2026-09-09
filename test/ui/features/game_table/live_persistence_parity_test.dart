import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/match_history_repository.dart';
import 'package:hareeg_table/data/persistence/key_value_store.dart';
import 'package:hareeg_table/data/persistence/match_repository.dart';
import 'package:hareeg_table/data/persistence/replay_file_store.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';
import 'package:hareeg_table/ui/features/game_table/table_session_config.dart';
import 'package:hareeg_table/ui/features/game_table/views/game_table_screen.dart';

import '../../../support/test_fixtures.dart';
// Sprint 05 already wrote a dependency-free SHA-256 for its own frozen oracle,
// as a public top-level function. Reusing it keeps one implementation instead
// of a second copy that could drift, and leaves that file unmodified —
// importing a test library does not run its tests.
import '../replay/replay_docked_regression_test.dart' show sha256Hex;

/// Pre-edit oracle for the live table's durable persistence call order.
///
/// Contract B12-B18. This file has two jobs, in a deliberate order: when the
/// fixture is **absent** it captures the call order from the code currently in
/// the tree and writes it; when the fixture is **present** it only reads and
/// compares. The capture therefore happens exactly once, against pre-edit
/// code, and every later run is a parity check.
///
/// "Never regenerated" is not left as a promise. The digest recorded in
/// `sprint-06/pre-edit-oracle/index.md` is recomputed as a blocking gate, so a
/// deleted-and-rebuilt fixture is detectable rather than silent.
///
/// **Only mutations are recorded.** Reads (`loadActiveMatch`, `listSummaries`,
/// `isMatchIdTaken`) vary with widget lifecycle and would make the oracle
/// brittle without saying anything about durable effects. The recorded set is
/// exactly the set a branch sandbox must never reach, which is what makes this
/// oracle and the V11a guard describe the same boundary.
///
/// Each scenario asserts it actually reached the state it is named for. A
/// scenario that silently degraded into an ordinary save would otherwise be
/// recorded under a name that overstates its coverage.
const _oraclePath =
    'test/ui/features/game_table/live_persistence_oracle.json';

/// The digest recorded in `sprint-06/pre-edit-oracle/index.md` at capture
/// time, against pre-edit code at HEAD `6a22bfa1`.
///
/// Checked here rather than only by hand, because "the fixture was never
/// regenerated" is exactly the claim a by-hand step is worst at keeping. A
/// deleted-and-rebuilt oracle would otherwise agree with itself and pass: the
/// scenarios would be re-captured from post-edit code and compared against
/// their own output. This assertion is what makes that fail.
const _oracleDigest =
    'c09834624b6582a950291d65e957ad90a23e17729fce04429656457455c78f69';

/// Filled by the capture cases below, then read by the parity case.
final Map<String, List<String>> _captured = <String, List<String>>{};

void main() {
  group('live persistence call order', () {
    for (final scenario in _scenarios) {
      testWidgets('captures ${scenario.name}', (tester) async {
        final entries = await scenario.run(tester);
        final problem = scenario.validate(entries);
        expect(
          problem,
          isNull,
          reason:
              'Scenario "${scenario.name}" did not reach the state it is '
              'named for ($problem). Recording it would overstate the '
              'oracle\'s coverage. Trace: $entries',
        );
        _captured[scenario.name] = entries;
      });
    }

    test('matches the frozen pre-edit oracle', () async {
      final captured = Map<String, List<String>>.of(_captured);
      expect(
        captured.keys.length,
        _scenarios.length,
        reason: 'A capture case did not run; the oracle would be partial.',
      );

      final file = File(_oraclePath);
      const encoder = JsonEncoder.withIndent('  ');
      final rendered = '${encoder.convert(captured)}\n';

      if (!file.existsSync()) {
        file.writeAsStringSync(rendered);
        fail(
          'Pre-edit oracle was absent and has now been captured at '
          '$_oraclePath. This is the one-time B14 capture: record its '
          'SHA-256 and the baseline HEAD in sprint-06/pre-edit-oracle before '
          'any product edit, then re-run. Failing deliberately so a capture '
          'run can never be mistaken for a passing parity run.',
        );
      }

      expect(
        sha256Hex(file.readAsBytesSync()),
        _oracleDigest,
        reason:
            'The frozen pre-edit oracle at $_oraclePath no longer matches the '
            'digest recorded in sprint-06/pre-edit-oracle/index.md. It was '
            'edited or regenerated, so it no longer describes pre-edit code '
            'and any parity it reports is self-agreement.',
      );

      final expected =
          (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>).map(
            (key, value) =>
                MapEntry(key, (value as List<dynamic>).cast<String>()),
          );

      expect(
        captured.keys.toSet(),
        expected.keys.toSet(),
        reason: 'Oracle scenario set drifted.',
      );
      for (final name in expected.keys) {
        expect(
          captured[name],
          expected[name],
          reason: 'Live persistence call order changed for "$name".',
        );
      }
    });
  });
}

/// One named persistence scenario, its driver, and the proof it got there.
class _Scenario {
  const _Scenario(this.name, this.run, this.validate);

  final String name;
  final Future<List<String>> Function(WidgetTester tester) run;

  /// Returns null when the trace genuinely reached the state the scenario is
  /// named for, or a reason when it did not.
  ///
  /// This inspects the **whole ordered trace**, not individual entries. A
  /// per-entry predicate cannot express "round 2 was reached" or "the terminal
  /// save came before a successful publication", and a scenario that degrades
  /// into an ordinary save would satisfy one while overstating its coverage.
  final String? Function(List<String> trace) validate;
}

bool _isSave(String e) => e.startsWith('match.saveActiveMatch');
bool _isTerminalSave(String e) => _isSave(e) && e.contains('terminal=true');
bool _isAbandon(String e) => e.startsWith('match.abandonActiveMatch');
bool _isArchive(String e) => e.startsWith('history.archiveCompletedMatch');
bool _isArchiveFailure(String e) => _isArchive(e) && e.contains('failed');
bool _isArchivePublished(String e) => _isArchive(e) && e.contains('-> published');
bool _isRecoveryPublished(String e) =>
    e.startsWith('history.recoverPendingArchive') && e.contains('-> published');
bool _isSaveAtRound(String e, int round) => _isSave(e) && e.contains('round=$round,');

/// Index of the first entry matching [test], or -1.
int _indexWhere(List<String> trace, bool Function(String) test) {
  for (var i = 0; i < trace.length; i++) {
    if (test(trace[i])) return i;
  }
  return -1;
}

/// Mounting alone must persist the resumed match, and nothing more.
String? _validateOpening(List<String> trace) {
  if (!trace.any((e) => _isSaveAtRound(e, 1))) {
    return 'expected a round-1 active save';
  }
  if (trace.any(_isTerminalSave) || trace.any(_isArchive)) {
    return 'opening must not reach a terminal save or an archive';
  }
  return null;
}

/// An applied action must leave durable evidence **beyond** the mount.
///
/// The initial mount alone produces exactly one round-1 save, which is also
/// all `opening` requires. Sharing one validator between the two therefore let
/// a discard that never applied be frozen under the name `ordinary-action`.
/// Requiring a second save is what distinguishes "an action happened" from
/// "the screen loaded".
String? _validateOrdinaryAction(List<String> trace) {
  final saves = trace.where((e) => _isSaveAtRound(e, 1)).length;
  if (saves < 2) {
    return 'only $saves round-1 save(s): the mount alone produces one, so '
        'this does not show an action was applied';
  }
  if (trace.any(_isTerminalSave) || trace.any(_isArchive)) {
    return 'an ordinary action must not reach a terminal save or an archive';
  }
  return null;
}

/// The crossing is only proven by a save at the **next** round number.
String? _validateRoundCrossing(List<String> trace) {
  if (!trace.any((e) => _isSaveAtRound(e, 1))) {
    return 'expected a round-1 save before the crossing';
  }
  if (!trace.any((e) => _isSaveAtRound(e, 2))) {
    return 'no round-2 save: the round never actually crossed';
  }
  if (trace.any(_isArchive)) {
    return 'a continuing match must not archive';
  }
  return null;
}

String? _validateAbandon(List<String> trace) {
  if (!trace.any(_isAbandon)) return 'expected abandonActiveMatch';
  if (trace.any(_isArchive)) {
    return 'an abandoned match must never be archived';
  }
  return null;
}

/// Ordering is the whole point: the terminal checkpoint must be durable
/// **before** publication starts.
String? _validateTerminal(List<String> trace) {
  final terminal = _indexWhere(trace, _isTerminalSave);
  final published = _indexWhere(trace, _isArchivePublished);
  if (terminal < 0) return 'no terminal save';
  if (published < 0) return 'no successful publication';
  if (terminal > published) {
    return 'terminal save must precede publication (save=$terminal, '
        'publish=$published)';
  }
  return null;
}

/// A failure alone is not a retry. The trace must show the failure and then a
/// later successful publication.
String? _validateArchiveRetry(List<String> trace) {
  final terminal = _indexWhere(trace, _isTerminalSave);
  final failed = _indexWhere(trace, _isArchiveFailure);
  final recovered = _indexWhere(trace, _isRecoveryPublished);
  if (terminal < 0) return 'no terminal save';
  if (failed < 0) return 'no injected archive failure';
  if (recovered < 0) {
    return 'the failure was never retried to a successful recovery';
  }
  // Publication must come from recovery, not a second direct archive call:
  // the app retries by relaunching, never by calling archive twice.
  if (trace.any(_isArchivePublished)) {
    return 'publication came from a direct archiveCompletedMatch call, which '
        'is not the production retry path';
  }
  if (!(terminal < failed && failed < recovered)) {
    return 'expected terminal save -> failure -> recovery, got '
        'save=$terminal, fail=$failed, recover=$recovered';
  }
  return null;
}

final _scenarios = <_Scenario>[
  _Scenario('opening', _openingScenario, _validateOpening),
  _Scenario('ordinary-action', _ordinaryActionScenario, _validateOrdinaryAction),
  _Scenario('round-crossing', _roundCrossingScenario, _validateRoundCrossing),
  _Scenario('leave-abandon', _leaveAbandonScenario, _validateAbandon),
  _Scenario('terminal-save-before-archive', _terminalScenario, _validateTerminal),
  _Scenario('archive-failure-retry', _archiveFailureScenario, _validateArchiveRetry),
];

// --- recording wrappers ---------------------------------------------------

/// Ordered log of durable mutations, shared by both recording wrappers.
class _PersistenceLog {
  final List<String> entries = <String>[];

  void add(String entry) => entries.add(entry);
}

/// Wraps a real repository and records every mutation in order.
///
/// It delegates rather than stubbing, so the table under test sees the same
/// behaviour it would in production and the recorded order is the order that
/// actually happened.
class _RecordingMatchRepository implements MatchRepository {
  _RecordingMatchRepository(this._log, this._inner);

  final _PersistenceLog _log;
  final MatchRepository _inner;

  @override
  Future<ActiveMatchLoadOutcome> loadActiveMatch() => _inner.loadActiveMatch();

  @override
  Future<void> saveActiveMatch(MatchCheckpoint checkpoint) {
    _log.add(
      'match.saveActiveMatch(round=${checkpoint.snapshot.roundNumber}, '
      'terminal=${checkpoint.terminalFacts != null})',
    );
    return _inner.saveActiveMatch(checkpoint);
  }

  @override
  Future<void> abandonActiveMatch() {
    _log.add('match.abandonActiveMatch()');
    return _inner.abandonActiveMatch();
  }
}

/// Fails the first history-index write, then behaves normally.
///
/// A real storage failure injected at the storage layer, which is what makes
/// the retry genuine: `_publish` catches it and returns
/// `MatchArchivePublishFailed(retryable)` while the pending record written
/// earlier survives, so the next launch has something to recover.
class _FailOnceIndexStore implements KeyValueStore {
  _FailOnceIndexStore(this._inner, {required this.enabled});

  final KeyValueStore _inner;
  final bool enabled;
  bool _failed = false;

  @override
  Future<String?> loadString(String key) => _inner.loadString(key);

  @override
  Future<void> remove(String key) => _inner.remove(key);

  @override
  Future<void> saveString(String key, String value) async {
    if (enabled && !_failed && key == LocalMatchHistoryRepository.indexKey) {
      _failed = true;
      throw StateError('Injected history-index write failure.');
    }
    return _inner.saveString(key, value);
  }
}

String _outcomeLabel(MatchArchivePublishOutcome outcome) => switch (outcome) {
  MatchArchivePublished() => 'published',
  MatchArchivePublishedNonReplayable() => 'publishedNonReplayable',
  MatchArchiveNothingPending() => 'nothingPending',
  MatchArchiveAlreadyPublished() => 'alreadyPublished',
  MatchArchivePublishFailed(:final failure) => 'failed(${failure.kind.name})',
};

/// Records the **public** history calls the app actually makes, and their
/// outcomes, delegating to a real [LocalMatchHistoryRepository].
///
/// Only outer methods are recorded. Production recovery publishes through the
/// private `_archiveLocked` (`match_history_repository.dart:513-537`), so the
/// app makes exactly one public call to retry — `recoverPendingArchive` — and
/// its *result* is the publication. Logging a second public
/// `archiveCompletedMatch` would put a call in the oracle that no caller makes.
///
/// Archive and recovery entries are written after the call completes, because
/// the outcome is part of the record; saves are written at invocation. The two
/// conventions cannot disagree here, since the terminal save is awaited before
/// publication is invoked.
class _RecordingHistoryRepository implements MatchHistoryRepository {
  _RecordingHistoryRepository(this._log, this._inner);

  final _PersistenceLog _log;
  final MatchHistoryRepository _inner;

  @override
  Future<MatchHistoryListOutcome> listSummaries() => _inner.listSummaries();

  @override
  Future<MatchReplayOpenOutcome> openReplay(String matchId) =>
      _inner.openReplay(matchId);

  @override
  Future<bool> isMatchIdTaken(String candidate) =>
      _inner.isMatchIdTaken(candidate);

  @override
  Future<MatchHistoryDeleteOutcome> deleteMatch(String matchId) {
    _log.add('history.deleteMatch()');
    return _inner.deleteMatch(matchId);
  }

  @override
  Future<MatchReplayRepairOutcome> repairUnusableReplay({
    required String matchId,
    required String reason,
  }) {
    _log.add('history.repairUnusableReplay()');
    return _inner.repairUnusableReplay(matchId: matchId, reason: reason);
  }

  @override
  Future<MatchArchivePublishOutcome> archiveCompletedMatch(
    MatchCheckpoint terminal,
  ) async {
    final outcome = await _inner.archiveCompletedMatch(terminal);
    _log.add('history.archiveCompletedMatch() -> ${_outcomeLabel(outcome)}');
    return outcome;
  }

  @override
  Future<MatchArchivePublishOutcome> recoverPendingArchive() async {
    final outcome = await _inner.recoverPendingArchive();
    _log.add('history.recoverPendingArchive() -> ${_outcomeLabel(outcome)}');
    return outcome;
  }
}

// --- scenario drivers -----------------------------------------------------

/// Mounts the live table over recording repositories and settles it.
Future<List<String>> _drive(
  WidgetTester tester,
  ClassicHareegMatchSnapshot snapshot, {
  bool failArchiveOnce = false,
  bool relaunchHome = false,
  Future<void> Function(WidgetTester tester)? act,
}) async {
  tester.view.physicalSize = const Size(1688, 780);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  final log = _PersistenceLog();
  final inner = MemoryMatchRepository();
  final matches = _RecordingMatchRepository(log, inner);
  // A real repository over memory stores, so the recorded trace is the real
  // public call sequence rather than a fake's approximation of one.
  final history = _RecordingHistoryRepository(
    log,
    LocalMatchHistoryRepository(
      store: _FailOnceIndexStore(
        MemoryKeyValueStore(),
        enabled: failArchiveOnce,
      ),
      replayFiles: MemoryReplayFileStore(),
      matches: inner,
    ),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: GameTableScreen(
        setup: snapshot.setup,
        session: TableSessionConfig.live(
          matchRepository: matches,
          historyRepository: history,
        ),
        preferences: GamePreferences.defaults(),
        onPreferencesChanged: (_) {},
        initialSnapshot: snapshot,
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 30));
  if (act != null) {
    await act(tester);
    await tester.pumpAndSettle(const Duration(seconds: 30));
  }
  if (relaunchHome) {
    // The next launch is where a failed archive is retried: Home calls
    // `recoverPendingArchive` on load (`home_screen.dart:144`). Mounting the
    // real app shell over the same stores is that launch.
    final priorMotion = ShowcaseCardFan.disableLoopingMotionForTesting;
    ShowcaseCardFan.disableLoopingMotionForTesting = true;
    addTearDown(
      () => ShowcaseCardFan.disableLoopingMotionForTesting = priorMotion,
    );
    await tester.pumpWidget(
      HareegTableApp(
        matchRepository: matches,
        historyRepository: history,
        preferencesRepository: MemoryPreferencesRepository(),
        learningProgressRepository: MemoryLearningProgressRepository(),
        initialRouteOverride: AppRoutes.home,
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 30));
  }
  return List<String>.of(log.entries);
}

ClassicHareegSetup get _setup => ClassicHareegSetup.defaults();

HareegCard _card(CardRank rank, CardSuit suit) =>
    HareegCard.standard(rank: rank, suit: suit, deckIndex: 100);

/// An already-opened state, so south may finish without meeting the opening
/// requirement first.
OpeningState _opened(PlayerSeat seat) {
  return ClassicHareegOpeningRules.applyOpening(
    state: OpeningState.initial(51),
    seat: seat,
    melds: [const PlacedMeld(cards: [], valueSnapshot: 51)],
  );
}

/// Builds a resumable snapshot, optionally replacing south's whole hand.
ClassicHareegMatchSnapshot _snapshot({
  List<HareegCard>? southHand,
  PlayerSeat currentSeat = PlayerSeat.south,
  TurnPhase turnPhase = TurnPhase.action,
  OpeningState? openingState,
  Map<PlayerSeat, int> scores = const {},
  List<PlayerSeat> removedSeats = const [],
  int roundNumber = 1,
}) {
  final dealt = ClassicHareegRound.deal(setup: _setup, seed: 3);
  return ClassicHareegMatchSnapshot(
    setup: _setup,
    hands: southHand == null
        ? dealt.hands
        : {...dealt.hands, PlayerSeat.south: southHand},
    stock: dealt.stock,
    discardPile: dealt.discardPile,
    starter: dealt.starter,
    currentSeat: currentSeat,
    turnPhase: turnPhase,
    openingState: openingState,
    scores: scores,
    activeSeats: const [
      PlayerSeat.south,
      PlayerSeat.east,
      PlayerSeat.north,
      PlayerSeat.west,
    ],
    removedSeats: removedSeats,
    roundNumber: roundNumber,
    savedAt: DateTime.utc(2026, 6, 1),
  );
}

/// South holds exactly one meld plus one final discard.
///
/// Playing the meld and discarding the last card finishes the round outright.
/// That is the only route to a genuine round crossing or match completion:
/// nothing concludes a round on load except human elimination.
List<HareegCard> get _finishingHand => [
  _card(CardRank.seven, CardSuit.clubs),
  _card(CardRank.eight, CardSuit.clubs),
  _card(CardRank.nine, CardSuit.clubs),
  _card(CardRank.two, CardSuit.spades),
];

/// Plays south's meld and discards the last card.
Future<void> _finishRound(WidgetTester tester) async {
  for (final label in ['Seven of Clubs', 'Eight of Clubs', 'Nine of Clubs']) {
    await tester.tap(find.bySemanticsLabel(label).first, warnIfMissed: false);
  }
  await tester.pumpAndSettle();
  await tester.tap(find.text('Play meld'));
  await tester.pumpAndSettle();

  final discard = find.bySemanticsLabel('Two of Spades').first;
  final dropTarget = find.byKey(const ValueKey('discard-pile-drop-target'));
  await tester.dragFrom(
    tester.getCenter(discard),
    tester.getCenter(dropTarget) - tester.getCenter(discard),
  );
  await tester.pumpAndSettle();
}

Future<List<String>> _openingScenario(WidgetTester t) => _drive(t, _snapshot());

Future<List<String>> _ordinaryActionScenario(WidgetTester t) {
  return _drive(
    t,
    _snapshot(southHand: _finishingHand, openingState: _opened(PlayerSeat.south)),
    act: (tester) async {
      // One ordinary discard, without finishing: drop a single card on the
      // pile while three others remain in hand.
      final discard = find.bySemanticsLabel('Two of Spades').first;
      final dropTarget = find.byKey(const ValueKey('discard-pile-drop-target'));
      await tester.dragFrom(
        tester.getCenter(discard),
        tester.getCenter(dropTarget) - tester.getCenter(discard),
      );
    },
  );
}

/// South finishes with every seat well below the elimination score, so the
/// match continues and the next round is dealt and saved.
Future<List<String>> _roundCrossingScenario(WidgetTester t) => _drive(
  t,
  _snapshot(southHand: _finishingHand, openingState: _opened(PlayerSeat.south)),
  act: _finishRound,
);

/// South is score-eliminated mid-round with CPUs still active: play stops and
/// nothing is archived.
Future<List<String>> _leaveAbandonScenario(WidgetTester t) => _drive(
  t,
  _snapshot(
    currentSeat: PlayerSeat.north,
    turnPhase: TurnPhase.draw,
    scores: const {
      PlayerSeat.south: 34,
      PlayerSeat.east: 0,
      PlayerSeat.north: 0,
      PlayerSeat.west: 0,
    },
    removedSeats: const [PlayerSeat.south],
    roundNumber: 2,
  ),
);

/// Every opponent sits one round-penalty below the elimination score, so
/// south's finish eliminates all three at once and south wins the match.
Map<PlayerSeat, int> get _terminalScores => const {
  PlayerSeat.south: 0,
  PlayerSeat.east: 30,
  PlayerSeat.north: 30,
  PlayerSeat.west: 30,
};

Future<List<String>> _terminalScenario(WidgetTester t) => _drive(
  t,
  _snapshot(
    southHand: _finishingHand,
    openingState: _opened(PlayerSeat.south),
    scores: _terminalScores,
    roundNumber: 3,
  ),
  act: _finishRound,
);

Future<List<String>> _archiveFailureScenario(WidgetTester t) => _drive(
  t,
  _snapshot(
    southHand: _finishingHand,
    openingState: _opened(PlayerSeat.south),
    scores: _terminalScores,
    roundNumber: 3,
  ),
  failArchiveOnce: true,
  relaunchHome: true,
  act: _finishRound,
);
