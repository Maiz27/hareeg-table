// Seeds a device or browser with the four history entries the replay viewer
// and the branch sandbox need to be exercised for real, then hands the app
// back to you.
//
// Two ordinary played matches (one replayable, one deliberately unusable), and
// two coached matches whose frame 7 is a stated meld-and-go-out position for
// South — one that crosses a round, one that completes the match.
//
// Run it as an alternate entry point, seed, then install the NORMAL build over
// the top WITHOUT clearing data and open History:
//
//   flutter build apk --debug -t tools/replay_viewer_probe.dart
//   adb install -r -d build/app/outputs/flutter-apk/app-debug.apk
//   # launch, tap Seed, wait for the report
//   flutter build apk --debug
//   adb install -r -d build/app/outputs/flutter-apk/app-debug.apk
//
// `-r` is what preserves the seeded history; an uninstall or a plain install
// would erase it and the whole exercise would measure nothing.
//
// On the web the store is origin-scoped, so seed and inspect on the SAME port:
//
//   flutter run -d web-server --web-port 7357 -t tools/replay_viewer_probe.dart
//   # seed at http://localhost:7357, stop the server
//   flutter run -d web-server --web-port 7357
//
// WARNING: this shares the application id and replaces the normal app on the
// target device until you install the normal build again.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_observation.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_strategy.dart';
import 'package:hareeg_table/data/persistence/app_repositories.dart';
import 'package:hareeg_table/data/persistence/match_history_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_checkpoint.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_replay_record.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_terminal_facts.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/match_replay_timeline.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/replay_branch_seed.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_recorder.dart';

/// A long, genuinely replayable match — the one used for load, seek and round
/// navigation.
const String longMatchId = 'm-rvlong-11111111';

/// A match whose summary is still marked replayable and whose replay JSON
/// still decodes, but which can no longer be rebuilt.
const String driftedMatchId = 'm-rvbad-22222222';

/// A coached match with a branch point that can be played to a **round
/// crossing** by hand on a device.
///
/// The two matches above are ordinary played matches, and that is exactly why
/// the first runtime pass could not reach a meld, a round crossing, a
/// completion or a coach: a branch taken anywhere in them hands South fifteen
/// unremarkable cards. These two start from a *stated* position instead —
/// South already opened, holding one four-card run and nothing else, with the
/// CPUs to move first — so at frame 7 South is on the action phase holding the
/// run plus one drawn card. Melding the run and discarding the spare goes out.
///
/// Here the opponents are on zero, so going out **crosses into a new round**
/// and the match carries on.
const String crossingMatchId = 'm-rvcross-33333333';

/// The same branch point with the opponents one round-penalty from
/// elimination, so the identical play **completes the sandbox** instead.
const String completionMatchId = 'm-rvdone-44444444';

/// The frame the two fixtures above are branched from.
///
/// Non-initial on purpose: the exit and completion routes must be shown to
/// restore *this* cursor, which is indistinguishable from rebuilding at zero
/// if the branch is taken at frame 0.
const int branchFixtureFrame = 7;

void main() => runApp(const _ProbeApp());

class _Line {
  _Line.pass(this.label) : ok = true, detail = null;
  _Line.fail(this.label, this.detail) : ok = false;
  _Line.info(this.label) : ok = null, detail = null;

  final String label;
  final bool? ok;
  final String? detail;

  String get text => switch (ok) {
    true => 'PASS  $label',
    false => 'FAIL  $label${detail == null ? '' : ' :: $detail'}',
    null => 'INFO  $label',
  };
}

class _ProbeApp extends StatefulWidget {
  const _ProbeApp();

  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  static const _strategy = ClassicHareegCpuStrategy();

  final List<_Line> _lines = [];
  bool _running = false;

  void _log(_Line line) => setState(() => _lines.add(line));

  Future<void> _seed() async {
    setState(() {
      _lines.clear();
      _running = true;
    });

    try {
      final history = AppRepositories.history;

      await _seedLongMatch(history);
      await _seedDriftedMatch(history);
      await _seedBranchFixture(
        history,
        matchId: crossingMatchId,
        opponentScore: 0,
        expectation: 'round crossing',
      );
      await _seedBranchFixture(
        history,
        matchId: completionMatchId,
        opponentScore: 30,
        expectation: 'sandbox completion',
      );
      await _report(history);
    } catch (error, stackTrace) {
      _log(_Line.fail('probe threw', '$error'));
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      setState(() => _running = false);
    }
  }

  Future<void> _seedLongMatch(MatchHistoryRepository history) async {
    final played = _playRealMatch();
    if (played.winner == null) {
      _log(_Line.fail('long match', 'no winner reached'));
      return;
    }

    final outcome = await history.archiveCompletedMatch(
      _terminalFor(longMatchId, played),
    );
    if (outcome is! MatchArchivePublished) {
      _log(_Line.fail('long match archive', outcome.runtimeType.toString()));
      return;
    }

    final entries = played.recorder.transcript?.entries.length ?? 0;
    _log(_Line.pass('long match archived as $longMatchId'));
    _log(_Line.info('  transcript actions: $entries'));
    _log(
      _Line.info(
        '  rounds: ${played.recorder.transcript?.entries.last.roundNumber ?? 0}',
      ),
    );
  }

  /// Publishes a genuine match, then rewrites only its replay payload.
  ///
  /// The drift happens *after* publication on purpose. Archiving verifies the
  /// transcript, so a record that was broken up front would simply publish as
  /// non-replayable and never produce the dead link this fixture exists to
  /// create. Rewriting afterwards is also what really happens in the wild.
  Future<void> _seedDriftedMatch(MatchHistoryRepository history) async {
    final played = _playRealMatch();
    if (played.winner == null) {
      _log(_Line.fail('drifted match', 'no winner reached'));
      return;
    }

    final archived = await history.archiveCompletedMatch(
      _terminalFor(driftedMatchId, played),
    );
    if (archived is! MatchArchivePublished) {
      _log(
        _Line.fail('drifted match archive', archived.runtimeType.toString()),
      );
      return;
    }
    _log(_Line.pass('drifted match archived as $driftedMatchId (valid)'));

    final stored = await AppRepositories.replayFiles.readFile(driftedMatchId);
    if (stored == null) {
      _log(_Line.fail('drifted match', 'no replay file was written'));
      return;
    }

    final json = jsonDecode(stored) as Map<String, Object?>;
    final transcript = (json['transcript']! as Map).cast<String, Object?>();
    final entries = (transcript['entries']! as List)
        .map((e) => (e as Map).cast<String, Object?>())
        .toList();
    if (entries.length < 60) {
      _log(_Line.fail('drifted match', 'transcript too short to drift'));
      return;
    }

    final target = entries[40];
    final was = target['seat'] as String;
    target['seat'] = PlayerSeat.values.firstWhere((s) => s.name != was).name;
    transcript['entries'] = entries;
    json['transcript'] = transcript;

    await AppRepositories.replayFiles.writeFile(
      driftedMatchId,
      jsonEncode(json),
    );
    _log(_Line.info('  entry 40 seat rewritten: $was -> ${target['seat']}'));

    // The whole point of the fixture is that it is NOT corrupt. Prove it.
    final reread = await AppRepositories.replayFiles.readFile(driftedMatchId);
    if (reread == null) {
      _log(_Line.fail('drifted match', 'replay file vanished after write'));
      return;
    }
    try {
      final record = MatchReplayRecord.fromJson(
        jsonDecode(reread) as Map<String, Object?>,
      );
      _log(_Line.pass('drifted replay still DECODES'));

      final built = MatchReplayTimeline.build(record.transcript);
      if (built is ReplayTimelineFailed) {
        _log(
          _Line.pass(
            'drifted replay cannot be rebuilt (${built.failure.kind.name})',
          ),
        );
      } else {
        _log(_Line.fail('drifted replay', 'it still rebuilds — not a fixture'));
      }
    } on FormatException catch (error) {
      _log(_Line.fail('drifted replay does not decode', error.message));
    }
  }

  /// Publishes a coached match whose frame [branchFixtureFrame] is a stated
  /// meld-and-go-out position for South.
  ///
  /// Played through the same real controller and the same shipped strategy as
  /// the other two — only the starting position is chosen rather than dealt,
  /// which is what makes the position reachable on a device at all. Archive
  /// verification still replays the transcript, so a fixture that did not
  /// genuinely play would publish as non-replayable and fail here.
  Future<void> _seedBranchFixture(
    MatchHistoryRepository history, {
    required String matchId,
    required int opponentScore,
    required String expectation,
  }) async {
    final played = _playRealMatch(from: _branchFixtureSnapshot(opponentScore));
    if (played.winner == null) {
      _log(_Line.fail(matchId, 'no winner reached'));
      return;
    }

    final outcome = await history.archiveCompletedMatch(
      // Coached, which is the only source of sandbox coach eligibility: the
      // two matches above are not, so without this the device can never show
      // a coach toggle at all.
      _terminalFor(matchId, played, coachWasEnabled: true),
    );
    if (outcome is! MatchArchivePublished) {
      _log(_Line.fail('$matchId archive', outcome.runtimeType.toString()));
      return;
    }
    _log(_Line.pass('$matchId archived (coached, for $expectation)'));

    // The branch point is evidence, not a hope: prove the frame this fixture
    // exists for is really the position it claims to be.
    final stored = await AppRepositories.replayFiles.readFile(matchId);
    if (stored == null) {
      _log(_Line.fail(matchId, 'no replay file'));
      return;
    }
    final record = MatchReplayRecord.fromJson(
      jsonDecode(stored) as Map<String, Object?>,
    );
    final built = MatchReplayTimeline.build(record.transcript);
    if (built is! ReplayTimelineBuilt) {
      _log(_Line.fail('$matchId timeline', built.runtimeType.toString()));
      return;
    }
    final frame = built.timeline.frameAt(branchFixtureFrame);
    final south = frame.snapshot.hands[PlayerSeat.south] ?? const [];
    _log(
      _Line.info(
        '  frame $branchFixtureFrame: ${frame.snapshot.currentSeat.name} '
        '${frame.snapshot.turnPhase.name}, south holds '
        '${south.map((c) => c.label).join(' ')}',
      ),
    );
    final branchable =
        ReplayBranchSeed.refusalFor(
          frame,
          nextFrame: branchFixtureFrame + 1 < built.timeline.length
              ? built.timeline.frameAt(branchFixtureFrame + 1)
              : null,
        ) ==
        null;
    if (frame.snapshot.currentSeat == PlayerSeat.south &&
        frame.snapshot.turnPhase == TurnPhase.action &&
        south.length == 5 &&
        branchable) {
      _log(_Line.pass('  branch point is the stated meld position'));
    } else {
      _log(_Line.fail('  branch point', 'not the stated meld position'));
    }
  }

  /// The stated position both branch fixtures start from.
  ClassicHareegMatchSnapshot _branchFixtureSnapshot(int opponentScore) {
    final setup = ClassicHareegSetup.defaults();
    final dealt = ClassicHareegRound.deal(setup: setup, seed: 3);
    // Deck indices outside the dealt range, so these four are unambiguously
    // South's own cards rather than duplicates of dealt ones.
    HareegCard club(CardRank rank, int index) =>
        HareegCard.standard(rank: rank, suit: CardSuit.clubs, deckIndex: index);

    return ClassicHareegMatchSnapshot(
      setup: setup,
      hands: {
        ...dealt.hands,
        PlayerSeat.south: [
          club(CardRank.six, 200),
          club(CardRank.seven, 201),
          club(CardRank.eight, 202),
          club(CardRank.nine, 203),
        ],
      },
      stock: dealt.stock,
      discardPile: const [],
      starter: dealt.starter,
      // The CPUs move first, so South's own turn — and therefore the branch
      // point — lands at a frame the reviewer has to be stepped to.
      currentSeat: PlayerSeat.east,
      turnPhase: TurnPhase.draw,
      // Already opened, so the run can be melded without meeting the opening
      // requirement first.
      openingState: ClassicHareegOpeningRules.applyOpening(
        state: OpeningState.initial(setup.openingRequirement),
        seat: PlayerSeat.south,
        melds: [
          PlacedMeld(cards: const [], valueSnapshot: setup.openingRequirement),
        ],
      ),
      scores: {
        PlayerSeat.south: 0,
        for (final seat in PlayerSeat.values)
          if (seat != PlayerSeat.south) seat: opponentScore,
      },
      roundNumber: 3,
      savedAt: DateTime.now().toUtc(),
    );
  }

  Future<void> _report(MatchHistoryRepository history) async {
    final listed = await history.listSummaries();
    if (listed is! MatchHistoryListed) {
      _log(_Line.fail('listing', listed.runtimeType.toString()));
      return;
    }

    for (final summary in listed.summaries) {
      _log(
        _Line.info(
          '  ${summary.matchId}  replayable=${summary.replayable}  '
          'rounds=${summary.roundCount}',
        ),
      );
    }

    final drifted = listed.summaries
        .where((s) => s.matchId == driftedMatchId)
        .toList();
    if (drifted.length == 1 && drifted.single.replayable) {
      _log(
        _Line.pass(
          'drifted entry is still advertised as replayable — open it in the '
          'normal app and it must repair itself',
        ),
      );
    } else {
      _log(
        _Line.fail(
          'drifted entry',
          'expected one entry still marked replayable',
        ),
      );
    }
  }

  Future<void> _clear() async {
    setState(() {
      _lines.clear();
      _running = true;
    });
    try {
      for (final id in [
        longMatchId,
        driftedMatchId,
        crossingMatchId,
        completionMatchId,
      ]) {
        final outcome = await AppRepositories.history.deleteMatch(id);
        _log(
          outcome is MatchHistoryDeleted
              ? _Line.pass('deleted $id')
              : _Line.fail('delete $id', outcome.runtimeType.toString()),
        );
      }
    } finally {
      setState(() => _running = false);
    }
  }

  MatchCheckpoint _terminalFor(
    String matchId,
    _Played played, {
    bool coachWasEnabled = false,
  }) {
    final winner = played.winner!;
    final finalState = played.finalState;

    // Everyone except the winner is out by definition once a match is won.
    // Leaving this empty makes the terminal facts describe four seats still
    // playing alongside a winner, and the engine rightly refuses to call that
    // a completed match.
    final eliminationRounds = <PlayerSeat, int>{
      for (final seat in PlayerSeat.values)
        if (seat != winner) seat: finalState.roundNumber,
    };

    return MatchCheckpoint(
          matchId: matchId,
          snapshot: finalState,
          recorderState: played.recorder.toState(),
        )
        .withCoachEnabled(coachWasEnabled)
        .terminalize(
          MatchTerminalFacts(
            completedAt: DateTime.now().toUtc(),
            winner: winner,
            finalScores: {
              for (final seat in PlayerSeat.values)
                seat: finalState.scores[seat] ?? 0,
            },
            roundCount: finalState.roundNumber,
            eliminationRounds: eliminationRounds,
            seats: PlayerSeat.values,
          ),
        );
  }

  /// Plays a whole match with the shipped CPU strategy.
  ///
  /// Every action goes through the controller's own legal-action surface, so
  /// the transcript genuinely replays; a hand-written action would be rejected
  /// during archive verification and publish as non-replayable.
  _Played _playRealMatch({
    int actionLimit = 4000,
    ClassicHareegMatchSnapshot? from,
  }) {
    var clock = DateTime.utc(2026, 1, 1);
    DateTime now() => clock;

    final recorder = MatchRecorder();
    var controller = ClassicHareegGameController.fromSnapshot(
      from ?? _dealSnapshot(),
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

    return _Played(
      recorder: recorder,
      finalState: controller.toSnapshot(savedAt: now()),
      winner: winner,
    );
  }

  ClassicHareegMatchSnapshot _dealSnapshot() {
    final round = ClassicHareegRound.deal(
      setup: ClassicHareegSetup.defaults(),
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('Replay viewer probe')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  FilledButton(
                    onPressed: _running ? null : _seed,
                    child: const Text('Seed'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _running ? null : _clear,
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
            if (_running) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _lines.length,
                itemBuilder: (context, index) => Text(
                  _lines[index].text,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Played {
  const _Played({
    required this.recorder,
    required this.finalState,
    required this.winner,
  });

  final MatchRecorder recorder;
  final ClassicHareegMatchSnapshot finalState;
  final PlayerSeat? winner;
}
