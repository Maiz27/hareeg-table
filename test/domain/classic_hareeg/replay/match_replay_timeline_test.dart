import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart'
    show TurnPhase;
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/match_replay_timeline.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/snapshot_mismatch.dart';

import '../../../support/completed_match_fixture.dart';

// Driving a real match to a winner costs tens of seconds, so each seed is
// played once for the whole file rather than once per test.
final _fixtures = <int, CompletedMatchFixture>{};
final _transcripts = <int, MatchActionTranscript>{};

CompletedMatchFixture _fixtureFor(int seed) =>
    _fixtures[seed] ??= buildCompletedMatch(seed: seed);

MatchActionTranscript _transcriptFor(int seed) {
  return _transcripts[seed] ??= () {
    final state = _fixtureFor(seed).recorderState;
    return MatchActionTranscript(
      initialSnapshot: state.initialSnapshot!,
      entries: state.entries,
    );
  }();
}

/// Real matches are slow to drive; these budgets are about fixture cost, not
/// about the timeline being slow.
const _slow = Timeout(Duration(minutes: 5));

/// The frame-for-frame comparison walks two full timelines and diffs every
/// snapshot pair. Alone it takes a couple of minutes; sharing a machine with
/// the invariant sweeps it needs real headroom, and a test that passes in
/// isolation but times out in the full suite is not evidence of anything.
const _verySlow = Timeout(Duration(minutes: 12));

MatchReplayTimeline _built(MatchActionTranscript transcript) {
  final outcome = MatchReplayTimeline.build(transcript);
  return (outcome as ReplayTimelineBuilt).timeline;
}

MatchActionTranscriptEntry _copyEntry(
  MatchActionTranscriptEntry entry, {
  PlayerSeat? seat,
  TurnPhase? phase,
  int? roundNumber,
  String? actionId,
}) {
  return MatchActionTranscriptEntry(
    order: entry.order,
    seat: seat ?? entry.seat,
    roundNumber: roundNumber ?? entry.roundNumber,
    phase: phase ?? entry.phase,
    actionId: actionId ?? entry.actionId,
  );
}

MatchActionTranscript _withMutatedEntry(
  MatchActionTranscript source,
  int index,
  MatchActionTranscriptEntry Function(MatchActionTranscriptEntry) mutate,
) {
  final entries = [...source.entries];
  entries[index] = mutate(entries[index]);
  return MatchActionTranscript(
    initialSnapshot: source.initialSnapshot,
    entries: entries,
  );
}

void main() {
  group('frame model over a real completed match', () {
    late MatchActionTranscript transcript;
    late MatchReplayTimeline timeline;

    setUpAll(() {
      transcript = _transcriptFor(7);
      timeline = _built(transcript);
    });

    test('frame count is one initial, one per round crossing, one per action', () {
      // Hand-computed rather than read off the timeline: K is the number of
      // times the transcript's round number steps up.
      var crossings = 0;
      var round = transcript.initialSnapshot.roundNumber;
      for (final entry in transcript.entries) {
        while (round < entry.roundNumber) {
          crossings += 1;
          round += 1;
        }
      }
      expect(
        timeline.length,
        1 + crossings + transcript.entries.length,
        reason: '1 initial + $crossings round starts + '
            '${transcript.entries.length} actions',
      );
    });

    test('indexes are dense and gap-free', () {
      for (var i = 0; i < timeline.length; i++) {
        expect(timeline.frameAt(i).index, i);
      }
    });

    test('an applied entry is carried exactly by action-applied frames', () {
      for (final frame in timeline.frames) {
        expect(
          frame.appliedEntry != null,
          frame.kind == ReplayFrameKind.actionApplied,
          reason: 'frame ${frame.index} (${frame.kind.name})',
        );
      }
    });

    test('applied actions appear in transcript order', () {
      final orders = [
        for (final frame in timeline.frames)
          if (frame.appliedEntry case final entry?) entry.order,
      ];
      expect(orders, [for (final entry in transcript.entries) entry.order]);
    });

    test('round numbers never go backwards', () {
      var previous = timeline.frameAt(0).roundNumber;
      for (final frame in timeline.frames) {
        expect(frame.roundNumber, greaterThanOrEqualTo(previous));
        previous = frame.roundNumber;
      }
    });

    test('a round start precedes that round\'s first applied action', () {
      for (final round in timeline.roundNumbers.skip(1)) {
        final start = timeline.startIndexOfRound(round)!;
        expect(timeline.frameAt(start).kind, ReplayFrameKind.roundStart);
        expect(timeline.frameAt(start).roundNumber, round);
        expect(timeline.frameAt(start - 1).roundNumber, lessThan(round));
      }
    });

    test('the first round opens at the initial frame', () {
      final first = timeline.roundNumbers.first;
      expect(timeline.startIndexOfRound(first), 0);
      expect(timeline.frameAt(0).kind, ReplayFrameKind.initial);
      expect(timeline.startIndexOfRound(9999), isNull);
    });

    test('a round start is never after a frame belonging to it', () {
      for (var i = 0; i < timeline.length; i++) {
        final start = timeline.startIndexOfRound(timeline.roundOfFrame(i))!;
        expect(start, lessThanOrEqualTo(i));
      }
    });

    test('the winner appears only on the final frame', () {
      // Compared against the fixture's independently derived winner, not
      // against the timeline's own answer.
      final expected = _fixtureFor(7).facts.winner;
      expect(timeline.matchWinner, expected);
      for (var i = 0; i < timeline.length - 1; i++) {
        expect(timeline.frameAt(i).matchWinner, isNull, reason: 'frame $i');
      }
    });

    test('the frame list rejects mutation and frames never alias each other', () {
      expect(
        () => timeline.frames.add(timeline.frameAt(0)),
        throwsUnsupportedError,
      );

      // `ClassicHareegMatchSnapshot` stores its collections as handed to it and
      // does not wrap them, so the timeline cannot promise an immutable
      // snapshot without changing that shared type. What it can promise, and
      // what actually protects a reviewer stepping around, is that no two
      // frames share state: mutating one position can never silently rewrite
      // another.
      final seen = <ClassicHareegMatchSnapshot>[];
      for (final frame in timeline.frames) {
        expect(
          seen.any((other) => identical(other, frame.snapshot)),
          isFalse,
          reason: 'frame ${frame.index} reuses a snapshot from another frame',
        );
        seen.add(frame.snapshot);
      }
    });

    test('the clock advances one second per applied action', () {
      final applied = [
        for (final frame in timeline.frames)
          if (frame.kind == ReplayFrameKind.actionApplied) frame,
      ];
      for (var i = 1; i < applied.length; i++) {
        expect(
          applied[i].clock.difference(applied[i - 1].clock).inSeconds,
          1,
          reason: 'between applied frames ${i - 1} and $i',
        );
      }
      expect(applied.first.clock, replayClockEpoch.add(const Duration(seconds: 1)));
    });

    test('reconstructed frames are stamped with their own clock', () {
      for (final frame in timeline.frames.skip(1)) {
        expect(frame.snapshot.savedAt, frame.clock, reason: 'frame ${frame.index}');
      }
    });
  });

  test('frame 0 keeps the archived snapshot while the clock starts at the epoch', timeout: _slow, () {
    // The archived snapshot carries whenever the match was actually saved.
    // Deliberately set to an instant far from the replay epoch so a
    // implementation that re-stamped it, or that read the clock off the
    // snapshot, cannot pass.
    final source = _transcriptFor(13);
    final archivedAt = DateTime.utc(2019, 3, 14, 15, 9, 26);
    final rebased = ClassicHareegMatchSnapshot.fromJson({
      ...source.initialSnapshot.toJson(),
      'savedAt': archivedAt.toIso8601String(),
    });
    final transcript = MatchActionTranscript(
      initialSnapshot: rebased,
      entries: source.entries,
    );

    final timeline = _built(transcript);
    final first = timeline.frameAt(0);

    expect(first.kind, ReplayFrameKind.initial);
    expect(first.snapshot.savedAt, archivedAt);
    expect(first.clock, replayClockEpoch);
    expect(first.snapshot.savedAt, isNot(first.clock));
    expect(first.roundNumber, rebased.roundNumber);
  });

  group('entry metadata must describe the state it is applied to', () {
    late MatchActionTranscript clean;

    setUpAll(() => clean = _transcriptFor(13));


    test('a valid transcript passes validation', timeout: _slow, () {
      expect(MatchReplayTimeline.build(clean), isA<ReplayTimelineBuilt>());
    });

    test('a rewritten seat is refused', timeout: _slow, () {
      final entry = clean.entries[40];
      final wrongSeat = PlayerSeat.values.firstWhere((s) => s != entry.seat);
      final outcome = MatchReplayTimeline.build(
        _withMutatedEntry(clean, 40, (e) => _copyEntry(e, seat: wrongSeat)),
      );

      final failure = (outcome as ReplayTimelineFailed).failure;
      expect(failure.kind, ReplayTimelineFailureKind.seatMismatch);
      expect(failure.entry?.order, entry.order);
      expect(failure.message, contains(wrongSeat.name));
      expect(failure.message, contains(entry.seat.name));
    });

    test('a rewritten phase is refused', timeout: _slow, () {
      final entry = clean.entries[40];
      final wrongPhase = TurnPhase.values.firstWhere((p) => p != entry.phase);
      final outcome = MatchReplayTimeline.build(
        _withMutatedEntry(clean, 40, (e) => _copyEntry(e, phase: wrongPhase)),
      );

      final failure = (outcome as ReplayTimelineFailed).failure;
      expect(failure.kind, ReplayTimelineFailureKind.phaseMismatch);
      expect(failure.message, contains(wrongPhase.name));
    });

    test('a round number below the reconstructed round is refused', timeout: _slow, () {
      // Must be an entry the machine reaches AFTER it has already crossed into
      // that round. Rewriting the FIRST entry of round 2 down to round 1 does
      // not regress anything — the crossing simply never happens and the entry
      // is judged against round 1, which is a different failure.
      final firstOfRoundTwo = clean.entries.indexWhere((e) => e.roundNumber >= 2);
      expect(firstOfRoundTwo, greaterThan(0), reason: 'fixture must cross a round');
      final index = clean.entries.indexWhere(
        (e) => e.roundNumber == clean.entries[firstOfRoundTwo].roundNumber,
        firstOfRoundTwo + 1,
      );
      expect(index, greaterThan(firstOfRoundTwo));

      final outcome = MatchReplayTimeline.build(
        _withMutatedEntry(
          clean,
          index,
          (e) => _copyEntry(e, roundNumber: e.roundNumber - 1),
        ),
      );

      final failure = (outcome as ReplayTimelineFailed).failure;
      expect(failure.kind, ReplayTimelineFailureKind.roundRegression);
    });

    test('an unapplicable action is refused with the engine\'s own wording', () {
      final outcome = MatchReplayTimeline.build(
        _withMutatedEntry(
          clean,
          40,
          (e) => _copyEntry(e, actionId: 'draw-stock'),
        ),
      );

      final failure = (outcome as ReplayTimelineFailed).failure;
      expect(failure.kind, ReplayTimelineFailureKind.actionRejected);
      expect(failure.message, contains('was rejected during replay'));
    });

    test('a refusal produces no timeline at all', timeout: _slow, () {
      final outcome = MatchReplayTimeline.build(
        _withMutatedEntry(
          clean,
          40,
          (e) => _copyEntry(e, actionId: 'draw-stock'),
        ),
      );
      // A partial snapshot exists for diagnostics, but nothing hands back a
      // half-reconstructed timeline that could be rendered as the match.
      expect(outcome, isA<ReplayTimelineFailed>());
      expect((outcome as ReplayTimelineFailed).failure.partialSnapshot, isNotNull);
    });
  });

  test('an empty transcript builds to a single initial frame', timeout: _slow, () {
    final source = _transcriptFor(13);
    final timeline = _built(
      MatchActionTranscript(
        initialSnapshot: source.initialSnapshot,
        entries: const [],
      ),
    );
    expect(timeline.length, 1);
    expect(timeline.frameAt(0).kind, ReplayFrameKind.initial);
  });

  group('the incremental drain is the same machine', () {
    test('sync and chunked drains agree frame for frame', timeout: _verySlow, () async {
      // Seeds this file already drives, so no extra match is played for this
      // test alone. Seed 7 is the long one (~1700 actions) and is the case
      // that actually stresses a chunked drain, which matters more than a
      // third medium-length match.
      for (final seed in [7, 13]) {
        final transcript = _transcriptFor(seed);
        final sync = _built(transcript);

        final build = IncrementalTimelineBuild(transcript, chunkSize: 16);
        final async = ((await build.run())! as ReplayTimelineBuilt).timeline;

        expect(async.length, sync.length, reason: 'seed $seed length');
        for (var i = 0; i < sync.length; i++) {
          final a = sync.frameAt(i);
          final b = async.frameAt(i);
          expect(b.kind, a.kind, reason: 'seed $seed frame $i kind');
          expect(b.roundNumber, a.roundNumber, reason: 'seed $seed frame $i round');
          expect(b.clock, a.clock, reason: 'seed $seed frame $i clock');
          expect(b.appliedEntry?.order, a.appliedEntry?.order);
          expect(
            describeSnapshotMismatch(expected: a.snapshot, actual: b.snapshot),
            isEmpty,
            reason: 'seed $seed frame $i state',
          );
        }
      }
    });

    test('the drain really yields, rather than doing it all in one chunk', timeout: _slow, () async {
      final transcript = _transcriptFor(13);
      var yields = 0;
      final build = IncrementalTimelineBuild(
        transcript,
        chunkSize: 16,
        yieldTo: () async {
          yields += 1;
          await Future<void>.delayed(Duration.zero);
        },
      );
      final timeline = ((await build.run())! as ReplayTimelineBuilt).timeline;

      // A single-chunk implementation would report one yield or none.
      expect(yields, greaterThanOrEqualTo((timeline.length / 16).floor() - 1));
      expect(yields, build.yieldCount);
      expect(yields, greaterThan(4));
    });

    test('cancelling mid-build stops the work and yields no result', timeout: _slow, () async {
      final transcript = _transcriptFor(7);
      late IncrementalTimelineBuild build;
      var yields = 0;
      build = IncrementalTimelineBuild(
        transcript,
        chunkSize: 8,
        yieldTo: () async {
          yields += 1;
          if (yields == 3) {
            build.cancel();
          }
          await Future<void>.delayed(Duration.zero);
        },
      );

      expect(await build.run(), isNull);
      final producedAtCancel = build.producedFrames;
      expect(producedAtCancel, lessThan(transcript.entries.length));

      // Nothing keeps running after the caller walked away.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(build.producedFrames, producedAtCancel);
    });
  });

  test('the Fifty expire-and-retry branch is preserved', timeout: _slow, () {
    // This branch exists for matches recorded against a wall clock: an action
    // the player applied after the window closed can read as illegal while the
    // synthetic window is still open. It is unreachable from driver-generated
    // transcripts — a probe over 8229 entries across 8 seeds hit it zero times
    // — so the only honest way to cover it is to make the engine answer "not
    // yet" once. The controller and the rules stay genuine; only the first
    // answer is withheld.
    final transcript = _transcriptFor(13);
    final refusedOnce = <String>{};
    var refusals = 0;

    final outcome = MatchReplayTimeline.build(
      transcript,
      applyHook: (controller, actionId) {
        if (controller.fiftyClaimant != null && refusedOnce.add(actionId)) {
          refusals += 1;
          return ApplyActionResult.failure('Fifty window is still open.');
        }
        return controller.applyAction(actionId);
      },
    );

    expect(outcome, isA<ReplayTimelineBuilt>());
    final timeline = (outcome as ReplayTimelineBuilt).timeline;
    expect(refusals, greaterThan(0), reason: 'the hook must actually fire');

    final adjusted = [
      for (final frame in timeline.frames)
        if (frame.effectivePreActionClock != null) frame,
    ];
    expect(adjusted, isNotEmpty);

    for (final frame in adjusted) {
      final previous = timeline.frameAt(frame.index - 1);
      final jump =
          frame.effectivePreActionClock!.difference(previous.clock).inSeconds;
      expect(
        jump,
        frame.snapshot.setup.fiftyTimerSeconds +
            replayFiftyExpiryPaddingSeconds,
        reason: 'frame ${frame.index} clock jump',
      );
      // The action still landed, and the frame is stamped one second past the
      // adjusted instant like every other applied frame.
      expect(
        frame.clock,
        frame.effectivePreActionClock!.add(const Duration(seconds: 1)),
      );
    }
  });

  test('a replay with no retry carries no clock adjustment at all', () {
    final timeline = _built(_transcriptFor(13));
    expect(
      timeline.frames.where((f) => f.effectivePreActionClock != null),
      isEmpty,
    );
  });
}
