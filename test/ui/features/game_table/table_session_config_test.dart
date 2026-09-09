import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/replay_branch_seed.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/match_replay_timeline.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/ui/features/game_table/table_mode.dart';
import 'package:hareeg_table/ui/features/game_table/table_session_config.dart';
import 'package:hareeg_table/ui/features/learning/practice/core_turn_practice_pack.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_session.dart';

import '../../../support/completed_match_fixture.dart';
import '../../../support/test_fixtures.dart';

/// Every public route into a table session, with what it must derive.
///
/// The point of this table is that it is **exhaustive over the routes, checked
/// against the type**: the factory set is read off the source, so a fourth
/// factory added without a row here fails rather than shipping unmapped. A
/// test that only walked the rows it happened to know about would agree with
/// any new route, however wrong.
typedef _Route = ({
  String name,
  TableSessionConfig Function() build,
  TableMode mode,
  bool durable,
});

late ReplayBranchSeed _seed;

void main() {
  setUpAll(() {
    final state = buildCompletedMatch(seed: 7).recorderState;
    final outcome = MatchReplayTimeline.build(
      MatchActionTranscript(
        initialSnapshot: state.initialSnapshot!,
        entries: state.entries,
      ),
    );
    final timeline = (outcome as ReplayTimelineBuilt).timeline;
    // Frame 1: an ordinary mid-match position, not the decided end.
    _seed = ReplayBranchSeed.fromFrame(
      timeline.frameAt(1),
      nextFrame: timeline.frameAt(2),
      branchStart: DateTime.utc(2026, 9, 7, 12),
    )!;
  });

  final routes = <_Route>[
    (
      name: 'live',
      build: () => TableSessionConfig.live(
        matchRepository: MemoryMatchRepository(),
        historyRepository: MemoryMatchHistoryRepository(),
      ),
      mode: TableMode.live,
      durable: true,
    ),
    (
      name: 'practice',
      build: () => TableSessionConfig.practice(
        PracticeSession(script: CoreTurnPracticePack.turnRhythm()),
      ),
      mode: TableMode.practice,
      durable: false,
    ),
    (
      name: 'branch blind',
      build: () => TableSessionConfig.branch(
        seed: _seed,
        visibility: BranchVisibility.blind,
        coachEligible: false,
      ),
      mode: TableMode.branchSandboxBlind,
      durable: false,
    ),
    (
      name: 'branch study',
      build: () => TableSessionConfig.branch(
        seed: _seed,
        visibility: BranchVisibility.study,
        coachEligible: true,
      ),
      mode: TableMode.branchSandboxStudy,
      durable: false,
    ),
  ];

  group('every construction route derives its mode and its persistence', () {
    for (final route in routes) {
      test('${route.name} maps to exactly one pairing', () {
        final config = route.build();

        expect(config.mode, route.mode);
        expect(
          config.persistence,
          route.durable
              ? isA<DurableTablePersistence>()
              : isA<EphemeralTablePersistence>(),
        );

        // The agreement that matters: the enum row and the sealed
        // configuration must say the same thing about durability. Two sources
        // of truth for "does this write?" is the drift this closes.
        expect(
          config.mode.capabilities.writesDurableMatchState,
          route.durable,
          reason:
              '${route.name}: the mode row and the persistence variant '
              'disagree about durability',
        );
        expect(config.writesDurableMatchState, route.durable);

        // And progression is read from the mode rather than stored beside it.
        expect(
          config.runsMatchProgression,
          route.mode.capabilities.runsMatchProgression,
        );
      });
    }

    test('the table covers every public route the type offers', () {
      // Read from source, so a fifth factory cannot be added and left
      // unmapped: this count is what turns "we listed the ones we knew" into
      // "we listed all of them".
      final source = File(
        'lib/ui/features/game_table/table_session_config.dart',
      ).readAsStringSync();
      final factories = RegExp(
        r'factory TableSessionConfig\.(\w+)\(',
      ).allMatches(source).map((m) => m.group(1)).toSet();

      expect(factories, {'live', 'practice', 'branch'});
      // Four rows over three factories: `branch` is two rows because
      // visibility selects between two modes.
      expect(routes, hasLength(4));
      expect(
        routes.map((r) => r.mode).toSet(),
        {
          TableMode.live,
          TableMode.practice,
          TableMode.branchSandboxBlind,
          TableMode.branchSandboxStudy,
        },
      );
    });

    test('every mode a session can be is reachable, and review is not', () {
      final reachable = routes.map((r) => r.mode).toSet();
      // Review is the one mode no table session builds: it is a different
      // screen entirely, and a config that could produce it would mean the
      // live table could be asked to run as a passive one.
      expect(
        TableMode.values.toSet().difference(reachable),
        {TableMode.replayReview},
      );
    });
  });

  group('the invalid pairings are unconstructible, not merely unused', () {
    test('no route accepts a mode or a persistence as an argument', () {
      final source = File(
        'lib/ui/features/game_table/table_session_config.dart',
      ).readAsStringSync();

      // The private constructor is the whole guarantee. A public one would let
      // any call site pair a branch with the real repositories.
      expect(source, contains('const TableSessionConfig._('));
      expect(
        RegExp(r'\n\s*const TableSessionConfig\(').hasMatch(source),
        isFalse,
        reason: 'a public generative constructor would reopen the hole',
      );

      // No factory takes either derived fact as a parameter.
      for (final match in RegExp(
        r'factory TableSessionConfig\.\w+\(([\s\S]*?)\n  \) \{',
      ).allMatches(source)) {
        final params = match.group(1)!;
        expect(
          params,
          isNot(contains('TableMode ')),
          reason: 'mode must be derived, never passed in',
        );
        expect(
          params,
          isNot(contains('TableSessionPersistence ')),
          reason: 'persistence must be derived, never passed in',
        );
      }
    });

    test('there is no settable progression field on the config', () {
      final source = File(
        'lib/ui/features/game_table/table_session_config.dart',
      ).readAsStringSync();

      // A second, independently mutable flag is exactly how the enum row and
      // the config would drift apart. Progression must be a getter over the
      // mode and nothing else.
      expect(
        source,
        contains('bool get runsMatchProgression => mode.capabilities'),
      );
      expect(
        RegExp(r'final bool runsMatchProgression').hasMatch(source),
        isFalse,
      );
      expect(
        RegExp(r'set runsMatchProgression').hasMatch(source),
        isFalse,
      );
    });

    test('the ephemeral variant holds no repository at all', () {
      // Fieldless by construction: a caller holding one cannot reach storage,
      // which is what makes a sandbox write impossible rather than skipped.
      const ephemeral = EphemeralTablePersistence();
      expect(ephemeral, isA<TableSessionPersistence>());

      final source = File(
        'lib/ui/features/game_table/table_session_config.dart',
      ).readAsStringSync();
      final body = source.substring(
        source.indexOf('class EphemeralTablePersistence'),
      );
      final classBody = body.substring(0, body.indexOf('\n}'));
      expect(
        RegExp(r'\n\s+final \w').hasMatch(classBody),
        isFalse,
        reason: 'EphemeralTablePersistence must have no fields:\n$classBody',
      );
    });

    test('the branch routes carry the seed and nothing durable', () {
      for (final visibility in BranchVisibility.values) {
        final config = TableSessionConfig.branch(
          seed: _seed,
          visibility: visibility,
          coachEligible: true,
        );
        expect(identical(config.branchSeed, _seed), isTrue);
        expect(config.practiceSession, isNull);
        expect(config.durable, isNull);
      }
    });

    test('coach eligibility is carried through, never invented', () {
      for (final eligible in [true, false]) {
        final config = TableSessionConfig.branch(
          seed: _seed,
          visibility: BranchVisibility.blind,
          coachEligible: eligible,
        );
        expect(config.branchCoachEligible, eligible);
      }
      // The other two routes never claim branch eligibility.
      expect(
        TableSessionConfig.live(
          matchRepository: MemoryMatchRepository(),
          historyRepository: MemoryMatchHistoryRepository(),
        ).branchCoachEligible,
        isFalse,
      );
    });
  });

  group('the boundary is closed to outside libraries, not just to callers', () {
    // A private constructor stops an outside library from EXTENDING the type
    // and stops nothing else. `implements TableSessionConfig` was enough to
    // return `branchSandboxBlind` from `mode` and a `DurableTablePersistence`
    // from `persistence`, and the analyzer accepted it — so the pairing B2
    // calls unconstructible was constructible after all.
    //
    // The proof has to be a COMPILE result, because there is no value to
    // assert on: the point is that the code cannot exist. Each case is written
    // to a temporary directory outside the repository and analyzed against the
    // real package config, so nothing here can affect the repository's own
    // `dart analyze`.
    late Directory scratch;
    late String dartBinary;

    setUpAll(() {
      scratch = Directory.systemTemp.createTempSync('session-boundary');
      // The test process is `flutter_tester`, and `dart` is not on the child
      // process PATH on every machine, so resolve the SDK binary explicitly.
      // Missing it must be a hard failure rather than a skip: a harness that
      // cannot run is not evidence that the boundary is closed.
      final root = Platform.environment['FLUTTER_ROOT'];
      final suffix = Platform.isWindows ? '.exe' : '';
      dartBinary = '$root/bin/cache/dart-sdk/bin/dart$suffix';
      expect(
        File(dartBinary).existsSync(),
        isTrue,
        reason: 'cannot locate the Dart SDK to run the compile-negative proof',
      );
    });
    tearDownAll(() => scratch.deleteSync(recursive: true));

    /// Analyzes [source] as its own library and returns the diagnostics.
    ({int exitCode, String output}) analyze(String name, String source) {
      final file = File('${scratch.path}/$name.dart')..writeAsStringSync(source);
      final result = Process.runSync(dartBinary, [
        'analyze',
        '--packages=${Directory.current.path}/.dart_tool/package_config.json',
        file.path,
      ]);
      return (
        exitCode: result.exitCode,
        output: '${result.stdout}${result.stderr}',
      );
    }

    const importRoot = 'package:hareeg_table/ui/features/game_table';

    test('an outside library cannot implement a session at all', () {
      final probe = analyze('forbidden_pairing', """
import '$importRoot/table_mode.dart';
import '$importRoot/table_session_config.dart';

/// The exact pairing B2 forbids: a branch surface holding real repositories.
class ExternalBranchConfig implements TableSessionConfig {
  ExternalBranchConfig(this.persistence);

  @override
  final DurableTablePersistence persistence;

  @override
  TableMode get mode => TableMode.branchSandboxBlind;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
""");

      expect(
        probe.exitCode,
        isNot(0),
        reason:
            'an outside library compiled a branch session holding durable '
            'storage: ${probe.output}',
      );
      expect(probe.output, contains('final class'));
    });

    test('an outside library cannot extend one either', () {
      final probe = analyze('forbidden_extend', """
import '$importRoot/table_session_config.dart';

class ExternalConfig extends TableSessionConfig {}
""");
      expect(probe.exitCode, isNot(0), reason: probe.output);
    });

    test('and the same closure covers the capability table', () {
      final probe = analyze('forbidden_capabilities', """
import '$importRoot/table_mode.dart';

/// A passive surface that writes to history — the combination the private
/// constructor exists to prevent.
class ExternalCapabilities implements TableModeCapabilities {
  @override
  bool get acceptsHumanInput => false;
  @override
  bool get runsCpuTurns => false;
  @override
  TableCoachSurface get coachSurface => TableCoachSurface.none;
  @override
  bool get writesDurableMatchState => true;
  @override
  bool get revealsAllHands => true;
  @override
  bool get runsMatchProgression => false;
}
""");
      expect(probe.exitCode, isNot(0), reason: probe.output);
    });

    test('the harness can still compile a permitted library', () {
      // Without this, a harness that failed for any reason at all — a bad
      // package config, a typo in the import — would report the two cases
      // above as closed while proving nothing.
      final probe = analyze('permitted_use', """
import '$importRoot/table_session_config.dart';

TableSessionConfig practice(session) => TableSessionConfig.practice(session);
""");
      expect(
        probe.exitCode,
        0,
        reason: 'the compile-negative harness itself is broken: ${probe.output}',
      );
    });
  });

  group('the durable dispatch is exhaustive and one-sided', () {
    test('the screen switches on the sealed variants with no default', () {
      final source = File(
        'lib/ui/features/game_table/views/game_table_screen.dart',
      ).readAsStringSync();

      expect(source, contains('case EphemeralTablePersistence():'));
      expect(source, contains('case DurableTablePersistence('));

      // Progression and durable effect are separate methods, so "this table
      // crosses rounds" and "this table writes" stop being one question.
      expect(source, contains('_advanceProgression()'));
      expect(source, contains('_applyDurableEffect('));

      // The repositories reach the write sites as arguments of the durable
      // arm, never off the widget. That is what makes the write methods
      // inexpressible on the ephemeral side rather than merely skipped.
      expect(source, isNot(contains('widget.matchRepository')));
      expect(source, isNot(contains('widget.historyRepository')));
      expect(source, contains('required this.session'));
    });
  });
}
