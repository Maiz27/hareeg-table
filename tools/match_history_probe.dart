/// Runtime probe for completed-match archiving.
///
/// An alternate entrypoint, not part of the shipped app. It exists because the
/// properties that matter here cannot be observed from a unit test: that a
/// summary and a replay file really land in the app's no-backup storage through
/// the platform channel, that an abandoned match writes nothing, and that
/// publishing the same pending record twice leaves exactly one pair.
///
/// Nothing runs on launch. Each phase is a button so the records a phase leaves
/// behind are still there for `adb` to inspect before the next phase runs.
///
/// ```
/// flutter run -d <emulator-id> --target=tools/match_history_probe.dart --no-pub
/// ```
///
/// `docs/testing/replay-file-store-verification.md` carries the full sequence.
library;

import 'package:flutter/material.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_observation.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_strategy.dart';
import 'package:hareeg_table/data/persistence/app_repositories.dart';
import 'package:hareeg_table/data/persistence/match_history_repository.dart';
import 'package:hareeg_table/data/persistence/match_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_terminal_facts.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_recorder.dart';

/// An unrelated match seeded before the abandonment test, to prove abandoning
/// does not disturb records that are already stored.
const String sentinelMatchId = 'm-sentinel-aaaaaaaa';

/// The match the probe archives.
const String probeMatchId = 'm-probe-bbbbbbbb';

/// The match the probe abandons; it must never reach history.
const String abandonedMatchId = 'm-abandon-cccccccc';

/// The match played across a force-stop in phases F and G.
const String resumeMatchId = 'm-resume-eeeeeeee';

void main() {
  runApp(const _ProbeApp());
}

class _Step {
  _Step.pass(this.label) : passed = true, detail = null;

  _Step.fail(this.label, this.detail) : passed = false;

  _Step.info(this.label) : passed = null, detail = null;

  final String label;
  final bool? passed;
  final String? detail;

  String get prefix => switch (passed) {
    true => 'PASS',
    false => 'FAIL',
    null => 'INFO',
  };
}

class _ProbeApp extends StatefulWidget {
  const _ProbeApp();

  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  final CpuStrategy _strategy = const ClassicHareegCpuStrategy();
  final MatchHistoryRepository _history = AppRepositories.history;
  final MatchRepository _matches = AppRepositories.matches;
  final List<_Step> _steps = <_Step>[];

  String _phase = 'none';
  bool _running = false;

  void _emit(_Step step) {
    debugPrint(
      '[history-probe] ${step.prefix} ${step.label}'
      '${step.detail == null ? '' : ' — ${step.detail}'}',
    );
    setState(() => _steps.add(step));
  }

  void _check(String label, bool condition, [String? detail]) {
    _emit(condition ? _Step.pass(label) : _Step.fail(label, detail ?? 'failed'));
  }

  Future<void> _run(String phase, Future<void> Function() body) async {
    setState(() {
      _phase = phase;
      _steps.clear();
      _running = true;
    });
    try {
      await body();
    } catch (error) {
      _emit(_Step.fail('phase $phase aborted', '$error'));
    } finally {
      setState(() => _running = false);
    }
  }

  ClassicHareegMatchSnapshot _snapshot({ClassicHareegSetup? setup}) {
    final round = ClassicHareegRound.deal(
      setup: setup ?? ClassicHareegSetup.defaults(),
      seed: 7,
    );
    return ClassicHareegMatchSnapshot(
      setup: round.setup,
      hands: round.hands,
      stock: round.stock,
      discardPile: round.discardPile,
      starter: round.starter,
      currentSeat: round.currentSeat,
      turnPhase: round.turnPhase,
      savedAt: DateTime.now().toUtc(),
    );
  }

  /// Plays a real match far enough to produce a legal, replayable transcript.
  ///
  /// Every action goes through the controller's own legal-action surface, so
  /// the transcript replays. A hand-written action would be rejected during
  /// replay verification and the match would publish non-replayable — which is
  /// exactly the hole that made an earlier version of this probe unable to
  /// prove anything about replay files.
  ({MatchRecorder recorder, ClassicHareegMatchSnapshot finalState, PlayerSeat? winner})
  _playRealMatch({int actionLimit = 3000, ClassicHareegSetup? setup}) {
    var clock = DateTime.utc(2026, 1, 1);
    DateTime now() => clock;

    final recorder = MatchRecorder();
    var controller = ClassicHareegGameController.fromSnapshot(
      _snapshot(setup: setup),
      now: now,
      recorder: recorder,
    );

    PlayerSeat? winner;
    var applied = 0;
    while (applied < actionLimit) {
      if (controller.isRoundOver) {
        winner = controller.scoreView.progress?.matchWinner;
        if (winner != null) {
          break;
        }
        // Rounds keep dealing until a seat actually wins. Stopping at the first
        // round over would leave three seats still playing, and terminalizing
        // that would manufacture a match that never finished.
        final next = controller.nextRoundSnapshot(savedAt: now());
        if (next == null) {
          break;
        }
        controller = ClassicHareegGameController.fromSnapshot(
          next,
          now: now,
          recorder: recorder,
        );
        continue;
      }

      final actionId = _chooseAction(controller);
      if (actionId == null || !controller.applyAction(actionId).isSuccess) {
        break;
      }
      applied++;
      clock = clock.add(const Duration(seconds: 1));
    }

    return (
      recorder: recorder,
      finalState: controller.toSnapshot(savedAt: now()),
      winner: winner,
    );
  }

  /// Picks the seat's move with the shipped CPU strategy.
  ///
  /// Taking the first legal action instead looks simpler but never finishes a
  /// match — it draws and returns forever, so the run only ever ends on a cap,
  /// which is precisely the outcome that must not be publishable.
  String? _chooseAction(ClassicHareegGameController controller) {
    final seat = controller.currentSeat;
    final legal = controller.cpuActionIdsFor(seat);
    if (legal.isEmpty) {
      return null;
    }

    try {
      return _strategy
          .chooseMove(
            CpuTurnSnapshot(
              seat: seat,
              legalActionIds: legal,
              difficulty: controller.setup.cpuDifficulty,
            ),
            observation: LiveCpuObservation(
              controller: controller,
              seat: seat,
              legalActionIds: legal,
              difficulty: controller.setup.cpuDifficulty,
            ),
          )
          .actionId;
    } on StateError {
      return null;
    }
  }

  /// Builds a terminal checkpoint from a match that actually finished.
  ///
  /// Throws when the trace stopped without a winner. That refusal is the point:
  /// terminalizing a capped run would publish a completed match that never
  /// completed, and every downstream assertion would then be measuring fiction.
  MatchCheckpoint _terminalFor(String matchId, {ClassicHareegSetup? setup}) {
    final played = _playRealMatch(setup: setup);
    final winner = played.winner;
    if (winner == null) {
      throw StateError(
        'The probe match stopped without a winner; it must not be '
        'terminalized.',
      );
    }

    final finalState = played.finalState;
    final scores = finalState.scores;
    // Everyone except the winner is out by definition once a match is won.
    final eliminationRounds = <PlayerSeat, int>{
      for (final seat in PlayerSeat.values)
        if (seat != winner) seat: finalState.roundNumber,
    };

    return MatchCheckpoint(
      matchId: matchId,
      snapshot: finalState,
      recorderState: played.recorder.toState(),
    ).terminalize(
      MatchTerminalFacts(
        completedAt: DateTime.now().toUtc(),
        winner: winner,
        finalScores: {
          for (final seat in PlayerSeat.values) seat: scores[seat] ?? 0,
        },
        roundCount: finalState.roundNumber,
        eliminationRounds: eliminationRounds,
        seats: PlayerSeat.values,
      ),
    );
  }

  Future<List<String>> _historyIds() async {
    final outcome = await _history.listSummaries();
    if (outcome is! MatchHistoryListed) {
      _emit(_Step.fail('listSummaries failed', '$outcome'));
      return const [];
    }
    return [for (final summary in outcome.summaries) summary.matchId];
  }

  /// Seeds browsable history for the history and statistics screens.
  ///
  /// Separate from the correctness phases: this one exists so the normal app
  /// build has something real to render when the two screens are inspected on
  /// device. It deliberately produces the awkward cases rather than four
  /// identical wins — two difficulties, both coach states, one entry whose
  /// replay file is gone, and one whose Fifty counters were never measured.
  ///
  /// Everything is published through the production repository. After running
  /// this, install the normal debug build with `adb install -r -d` so the data
  /// survives, then browse.
  Future<void> _phaseH() async {
    for (final id in await _historyIds()) {
      await _history.deleteMatch(id);
    }
    await _matches.abandonActiveMatch();
    _check('H1 history starts empty', (await _historyIds()).isEmpty);

    const seeds = <({
      String id,
      CpuDifficulty difficulty,
      TableStrictness strictness,
      bool coach,
      bool countersMeasured,
      bool keepReplay,
    })>[
      (
        id: 'm-browse1-aaaaaaaa',
        difficulty: CpuDifficulty.casual,
        strictness: TableStrictness.coaching,
        coach: true,
        countersMeasured: true,
        keepReplay: true,
      ),
      (
        id: 'm-browse2-bbbbbbbb',
        difficulty: CpuDifficulty.casual,
        strictness: TableStrictness.standard,
        coach: false,
        // The unmeasured entry: its zeros mean unknown, and the statistics
        // screen must disclose the smaller Fifty denominator because of it.
        countersMeasured: false,
        keepReplay: true,
      ),
      (
        id: 'm-browse3-cccccccc',
        difficulty: CpuDifficulty.expert,
        strictness: TableStrictness.strict,
        coach: false,
        countersMeasured: true,
        // Its replay file is removed below, so listing repairs it to
        // non-replayable and the entry must still be shown.
        keepReplay: false,
      ),
      (
        id: 'm-browse4-dddddddd',
        difficulty: CpuDifficulty.expert,
        strictness: TableStrictness.table,
        coach: true,
        countersMeasured: true,
        keepReplay: true,
      ),
    ];

    for (final seed in seeds) {
      // Played under the seed's own setup, so the entry the screen renders
      // describes a match that was really played that way.
      final base = _terminalFor(
        seed.id,
        setup: ClassicHareegSetup.defaults().copyWith(
          cpuDifficulty: seed.difficulty,
          tableStrictness: seed.strictness,
        ),
      );
      final terminal = MatchCheckpoint(
        matchId: base.matchId,
        snapshot: base.snapshot,
        recorderState: base.recorderState,
        coachWasEnabled: seed.coach,
        fiftyCountersComplete: seed.countersMeasured,
      ).terminalize(base.terminalFacts!);

      await _matches.saveActiveMatch(terminal);
      final outcome = await _history.archiveCompletedMatch(terminal);
      _check(
        'H2 archived ${seed.id}',
        outcome is MatchArchivePublished ||
            outcome is MatchArchivePublishedNonReplayable,
        '$outcome',
      );

      if (!seed.keepReplay) {
        // Drop the payload behind the repository's back, which is exactly the
        // drift the listing repair is meant to notice.
        await AppRepositories.replayFiles.deleteFile(seed.id);
        _emit(_Step.info('H3 removed the replay file for ${seed.id}'));
      }
    }

    final ids = await _historyIds();
    _check('H4 four matches are listed', ids.length == 4, '$ids');
    _emit(
      _Step.info(
        'H5 install the normal build with `adb install -r -d` and browse '
        'History and Statistics',
      ),
    );
  }

  /// Setup: clear anything left over, then seed the sentinel pair.
  Future<void> _phaseA() async {
    for (final id in await _historyIds()) {
      await _history.deleteMatch(id);
    }
    await _matches.abandonActiveMatch();
    _check('A1 history starts empty', (await _historyIds()).isEmpty);

    final sentinel = _terminalFor(sentinelMatchId);
    await _matches.saveActiveMatch(sentinel);
    final outcome = await _history.archiveCompletedMatch(sentinel);
    _check(
      'A2 sentinel match archived',
      outcome is MatchArchivePublished,
      '$outcome',
    );
    _check(
      'A3 sentinel is listed',
      (await _historyIds()).contains(sentinelMatchId),
    );
    _emit(_Step.info('A4 sentinel left in place for adb inspection'));
  }

  /// Abandonment must write nothing and must not disturb the sentinel.
  Future<void> _phaseB() async {
    final before = await _historyIds();

    await _matches.saveActiveMatch(
      MatchCheckpoint(matchId: abandonedMatchId, snapshot: _snapshot()),
    );
    await _matches.abandonActiveMatch();

    final after = await _historyIds();
    _check(
      'B1 abandoning wrote no history entry',
      !after.contains(abandonedMatchId),
      '$after',
    );
    _check(
      'B2 history is unchanged by the abandonment',
      after.length == before.length,
      'before=$before after=$after',
    );
    _check(
      'B3 the sentinel pair survived untouched',
      after.contains(sentinelMatchId),
    );
    _check(
      'B4 no active match remains',
      await _matches.loadActiveMatch() is ActiveMatchAbsent,
    );
  }

  /// Publishing the same pending record twice must leave exactly one pair.
  Future<void> _phaseC() async {
    final terminal = _terminalFor(probeMatchId);

    await _matches.saveActiveMatch(terminal);
    final first = await _history.archiveCompletedMatch(terminal);
    _emit(_Step.info('C1 first publication: ${first.runtimeType}'));

    await _matches.saveActiveMatch(terminal);
    final second = await _history.archiveCompletedMatch(terminal);
    _emit(_Step.info('C2 second publication: ${second.runtimeType}'));

    final ids = await _historyIds();
    _check(
      'C3 exactly one summary for the republished match',
      ids.where((id) => id == probeMatchId).length == 1,
      '$ids',
    );
    _check(
      'C4 the sentinel is still listed alongside it',
      ids.contains(sentinelMatchId),
      '$ids',
    );
    _emit(
      _Step.info(
        'C5 inspect no_backup/replays with adb: exactly one '
        '$probeMatchId.json must be present',
      ),
    );
  }

  /// Recovery after a kill: publish from a terminal checkpoint with no pending
  /// record, which is what a death between steps 1 and 2 leaves behind.
  Future<void> _phaseD() async {
    await _matches.saveActiveMatch(_terminalFor(probeMatchId));
    final outcome = await _history.recoverPendingArchive();
    _emit(_Step.info('D1 recovery outcome: ${outcome.runtimeType}'));

    _check(
      'D2 recovery left no resumable match',
      await _matches.loadActiveMatch() is ActiveMatchAbsent,
    );
    final ids = await _historyIds();
    _check(
      'D3 still exactly one summary for the match',
      ids.where((id) => id == probeMatchId).length == 1,
      '$ids',
    );
  }

  /// Resume, part one: play some of a match and save a LIVE checkpoint.
  ///
  /// Force-stop the app after this phase, relaunch, and run phase G. The point
  /// is that the transcript must span the kill.
  Future<void> _phaseF() async {
    var clock = DateTime.utc(2026, 1, 1);
    final recorder = MatchRecorder();
    final controller = ClassicHareegGameController.fromSnapshot(
      _snapshot(),
      now: () => clock,
      recorder: recorder,
    );

    String? lastBefore;
    for (var applied = 0; applied < 12; applied++) {
      if (controller.isRoundOver) {
        break;
      }
      final options = controller.cpuActionIdsFor(controller.currentSeat);
      if (options.isEmpty) {
        break;
      }
      if (!controller.applyAction(options.first).isSuccess) {
        break;
      }
      lastBefore = recorder.transcript?.entries.last.actionId;
      clock = clock.add(const Duration(seconds: 1));
    }

    _check('F1 played actions before the kill', lastBefore != null);
    _emit(_Step.info('F2 last pre-stop action: $lastBefore'));

    await _matches.saveActiveMatch(
      MatchCheckpoint(
        matchId: resumeMatchId,
        snapshot: controller.toSnapshot(savedAt: clock),
        recorderState: recorder.toState(),
      ),
    );
    _check(
      'F3 live checkpoint saved with ${recorder.transcript?.entries.length} '
      'recorded actions',
      recorder.transcript != null,
    );
    _emit(_Step.info('F4 now force-stop the app, relaunch, and run phase G'));
  }

  /// Resume, part two: restore from the saved checkpoint, finish, archive.
  ///
  /// Run this only after a force-stop and relaunch.
  Future<void> _phaseG() async {
    final loaded = await _matches.loadActiveMatch();
    if (loaded is! ActiveMatchLoaded) {
      _emit(_Step.fail('G1 no saved checkpoint to resume', '$loaded'));
      return;
    }

    final checkpoint = loaded.checkpoint;
    final state = checkpoint.recorderState;
    if (state == null) {
      _emit(_Step.fail('G1 checkpoint carried no recorder state', 'null'));
      return;
    }

    final before = [for (final entry in state.entries) entry.actionId];
    _check('G1 resumed transcript is non-empty', before.isNotEmpty);
    _emit(_Step.info('G2 pre-stop actions restored: ${before.length}'));

    var clock = DateTime.utc(2026, 1, 1, 1);
    final recorder = MatchRecorder.restore(state);
    var controller = ClassicHareegGameController.fromSnapshot(
      checkpoint.snapshot,
      now: () => clock,
      recorder: recorder,
    );

    PlayerSeat? winner;
    var applied = 0;
    while (applied < 3000) {
      if (controller.isRoundOver) {
        winner = controller.scoreView.progress?.matchWinner;
        if (winner != null) {
          break;
        }
        final next = controller.nextRoundSnapshot(savedAt: clock);
        if (next == null) {
          break;
        }
        controller = ClassicHareegGameController.fromSnapshot(
          next,
          now: () => clock,
          recorder: recorder,
        );
        continue;
      }
      final actionId = _chooseAction(controller);
      if (actionId == null || !controller.applyAction(actionId).isSuccess) {
        break;
      }
      applied++;
      clock = clock.add(const Duration(seconds: 1));
    }

    if (winner == null) {
      _emit(
        _Step.fail(
          'G5 the resumed match did not reach a winner',
          'a capped trace must not be terminalized',
        ),
      );
      return;
    }

    final all = [for (final entry in recorder.transcript!.entries) entry.actionId];
    final namedPre = before.last;
    final namedPost = all.length > before.length ? all[before.length] : null;
    _emit(
      _Step.info(
        'G3a named pre-stop action [${before.length - 1}]: $namedPre; '
        'named post-resume action [${before.length}]: $namedPost',
      ),
    );

    _check(
      'G3 transcript spans the kill: ${before.length} pre + '
      '${all.length - before.length} post',
      all.length > before.length,
      '$all',
    );
    _check(
      'G4 the named pre-stop action sits at index ${before.length - 1}',
      all.length > before.length - 1 && all[before.length - 1] == namedPre,
      'found ${all.length > before.length - 1 ? all[before.length - 1] : null}',
    );
    _check(
      'G4a the named post-resume action sits at index ${before.length}',
      namedPost != null && all[before.length] == namedPost,
      '$namedPost',
    );

    final finalState = controller.toSnapshot(savedAt: clock);
    final terminal =
        MatchCheckpoint(
          matchId: resumeMatchId,
          snapshot: finalState,
          recorderState: recorder.toState(),
        ).terminalize(
          MatchTerminalFacts(
            completedAt: DateTime.now().toUtc(),
            winner: winner,
            finalScores: {
              for (final seat in PlayerSeat.values)
                seat: finalState.scores[seat] ?? 0,
            },
            roundCount: finalState.roundNumber,
            eliminationRounds: {
              for (final seat in PlayerSeat.values)
                if (seat != winner) seat: finalState.roundNumber,
            },
            seats: PlayerSeat.values,
          ),
        );

    await _matches.saveActiveMatch(terminal);
    final published = await _history.archiveCompletedMatch(terminal);
    // Published, not PublishedNonReplayable: publication only promises a replay
    // after replaying the transcript against the completed state, so this is
    // the assertion that the resumed transcript actually reconstructs.
    _check(
      'G5 resumed match published WITH a replay',
      published is MatchArchivePublished,
      '$published',
    );

    final opened = await _history.openReplay(resumeMatchId);
    if (opened is MatchReplayOpened) {
      final ids = [
        for (final entry in opened.record.transcript.entries) entry.actionId,
      ];
      // The whole sequence, not a length and a first element: a replay that
      // agreed on both ends and differed in the middle would pass that.
      _check(
        'G6 the stored replay matches the full action sequence',
        ids.join(',') == all.join(','),
        '${ids.length} entries vs ${all.length}',
      );
      _check(
        'G6a the stored replay holds the named pre-stop action at '
        '${before.length - 1}',
        ids.length > before.length - 1 && ids[before.length - 1] == namedPre,
      );
      _check(
        'G6b the stored replay holds the named post-resume action at '
        '${before.length}',
        namedPost != null &&
            ids.length > before.length &&
            ids[before.length] == namedPost,
      );
    } else {
      _emit(_Step.fail('G6 could not open the stored replay', '$opened'));
    }
  }

  /// Cleanup.
  Future<void> _phaseE() async {
    for (final id in await _historyIds()) {
      final outcome = await _history.deleteMatch(id);
      _emit(_Step.info('E: deleted $id -> ${outcome.runtimeType}'));
    }
    await _matches.abandonActiveMatch();
    _check('E1 history is empty', (await _historyIds()).isEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final failures = _steps.where((step) => step.passed == false).length;

    return MaterialApp(
      title: 'Match history probe',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: Text('History probe — phase $_phase'),
          backgroundColor: failures > 0 ? Colors.red.shade900 : null,
        ),
        body: Column(
          children: <Widget>[
            Wrap(
              spacing: 8,
              children: <Widget>[
                _button('A setup', () => _run('A', _phaseA)),
                _button('B abandon', () => _run('B', _phaseB)),
                _button('C double publish', () => _run('C', _phaseC)),
                _button('D recovery', () => _run('D', _phaseD)),
                _button('F resume setup', () => _run('F', _phaseF)),
                _button('G resume finish', () => _run('G', _phaseG)),
                _button('E cleanup', () => _run('E', _phaseE)),
                _button('H seed browse data', () => _run('H', _phaseH)),
              ],
            ),
            const Divider(),
            Text(
              _steps.isEmpty
                  ? 'No phase has run yet.'
                  : '$failures failure(s) in ${_steps.length} step(s)',
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _steps.length,
                itemBuilder: (context, index) {
                  final step = _steps[index];
                  return ListTile(
                    dense: true,
                    leading: Text(step.prefix),
                    title: Text(step.label),
                    subtitle: step.detail == null ? null : Text(step.detail!),
                    textColor: switch (step.passed) {
                      true => Colors.green,
                      false => Colors.red,
                      null => null,
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _button(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: _running ? null : onPressed,
      child: Text(label),
    );
  }
}
