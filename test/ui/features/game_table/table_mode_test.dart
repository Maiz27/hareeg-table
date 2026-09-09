import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/ui/features/game_table/table_mode.dart';

/// The mode table is policy, so it is asserted against literal expectations
/// rather than against anything derived from the table itself. A test that read
/// its answers out of the value under test would agree with any mistake.
void main() {
  test('every mode declares its capabilities', () {
    // A mode added later without a decision fails here rather than silently
    // inheriting whatever the first branch of some switch happens to do.
    for (final mode in TableMode.values) {
      expect(mode.capabilities, isNotNull, reason: mode.name);
    }
    expect(TableMode.values, hasLength(5));
  });

  test('live play accepts input, runs CPUs, coaches live, and saves', () {
    final live = TableMode.live.capabilities;
    expect(live.acceptsHumanInput, isTrue);
    expect(live.runsCpuTurns, isTrue);
    expect(live.coachSurface, TableCoachSurface.live);
    expect(live.writesDurableMatchState, isTrue);
    expect(live.revealsAllHands, isFalse);
    expect(live.runsMatchProgression, isTrue);
  });

  test('practice accepts input but drives itself, coaches not at all, and saves nothing', () {
    final practice = TableMode.practice.capabilities;
    expect(practice.acceptsHumanInput, isTrue);
    expect(practice.runsCpuTurns, isFalse);
    expect(practice.coachSurface, TableCoachSurface.none);
    expect(practice.writesDurableMatchState, isFalse);
    expect(practice.revealsAllHands, isFalse);
    // Practice drives the table from a lesson script and owns its own
    // completion overlay, so the round-result pipeline must stay out of it.
    expect(practice.runsMatchProgression, isFalse);
  });

  test('replay review is passive, inert, analysis-only, and writes nothing', () {
    final review = TableMode.replayReview.capabilities;
    expect(review.acceptsHumanInput, isFalse);
    expect(review.runsCpuTurns, isFalse);
    expect(review.coachSurface, TableCoachSurface.analysis);
    expect(review.writesDurableMatchState, isFalse);
    expect(review.revealsAllHands, isFalse);
    expect(review.runsMatchProgression, isFalse);
  });

  test('both branch sandboxes play live but write nothing', () {
    for (final mode in [
      TableMode.branchSandboxBlind,
      TableMode.branchSandboxStudy,
    ]) {
      final branch = mode.capabilities;
      expect(branch.acceptsHumanInput, isTrue, reason: mode.name);
      expect(branch.runsCpuTurns, isTrue, reason: mode.name);
      expect(branch.coachSurface, TableCoachSurface.live, reason: mode.name);
      // The whole point: it progresses like a real match and persists nothing.
      expect(branch.runsMatchProgression, isTrue, reason: mode.name);
      expect(branch.writesDurableMatchState, isFalse, reason: mode.name);
      expect(mode.isBranch, isTrue, reason: mode.name);
    }
  });

  test('the two branch modes differ in visibility and nothing else', () {
    final blind = TableMode.branchSandboxBlind.capabilities;
    final study = TableMode.branchSandboxStudy.capabilities;

    // Visibility is the only permitted difference. If a later edit diverges
    // them on any other axis, study mode would stop being "blind plus face-up
    // hands" and the rendering-only guarantee would quietly weaken.
    expect(blind.revealsAllHands, isFalse);
    expect(study.revealsAllHands, isTrue);

    expect(study.acceptsHumanInput, blind.acceptsHumanInput);
    expect(study.runsCpuTurns, blind.runsCpuTurns);
    expect(study.coachSurface, blind.coachSurface);
    expect(study.writesDurableMatchState, blind.writesDurableMatchState);
    expect(study.runsMatchProgression, blind.runsMatchProgression);
  });

  test('only live play writes durable match state', () {
    expect(
      TableMode.values
          .where((m) => m.capabilities.writesDurableMatchState)
          .toList(),
      [TableMode.live],
    );
  });

  test('the two coaches cannot both be on screen', () {
    // Structural, not a rule to remember: one enum field means "live coach and
    // analysis coach at the same time" is not a value anyone can build.
    for (final mode in TableMode.values) {
      expect(TableCoachSurface.values, contains(mode.capabilities.coachSurface));
    }
    expect(
      TableMode.values
          .where((m) => m.capabilities.coachSurface == TableCoachSurface.live)
          .toList(),
      [
        TableMode.live,
        TableMode.branchSandboxBlind,
        TableMode.branchSandboxStudy,
      ],
    );
    // The exclusion that matters for Sprint 06: the analysis coach belongs to
    // review alone, so a branch can never show it and review can never show
    // the live one. Neither is a check someone has to remember to perform.
    expect(
      TableMode.values
          .where(
            (m) => m.capabilities.coachSurface == TableCoachSurface.analysis,
          )
          .toList(),
      [TableMode.replayReview],
    );
    for (final mode in TableMode.values.where((m) => m.isBranch)) {
      expect(
        mode.capabilities.coachSurface,
        isNot(TableCoachSurface.analysis),
        reason: mode.name,
      );
    }
    expect(
      TableMode.replayReview.capabilities.coachSurface,
      isNot(TableCoachSurface.live),
    );
  });

  test('a fourth capability combination is not constructible', () {
    // The guarantee is that only the declared combinations exist. A public
    // constructor would let any call site invent, say, a passive surface that
    // still writes to history.
    final source = File(
      'lib/ui/features/game_table/table_mode.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('const TableModeCapabilities._('),
      reason: 'the capability constructor must be private',
    );
    expect(
      RegExp(r'\n\s*const TableModeCapabilities\(').hasMatch(source),
      isFalse,
      reason: 'no public generative constructor may exist',
    );
  });

  test('the live table never runs as a review surface', () {
    final source = File(
      'lib/ui/features/game_table/views/game_table_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('TableMode.replayReview')));
    // The implicit practice flag is gone: what a surface may do is read from
    // the mode, in one place, rather than re-decided per call site.
    expect(source, isNot(contains('_isPractice')));
    expect(source, contains('_mode.capabilities'));
  });
}
