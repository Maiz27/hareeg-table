import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/match_replay_timeline.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/replay_reconstruction.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

import '../../../scenario/classic_hareeg_scenario.dart';
import '../../../support/completed_match_fixture.dart';

const _slow = Timeout(Duration(minutes: 5));

MatchActionTranscript _transcript(int seed) {
  final state = buildCompletedMatch(seed: seed).recorderState;
  return MatchActionTranscript(
    initialSnapshot: state.initialSnapshot!,
    entries: state.entries,
  );
}

void main() {
  group('the machine produces one frame at a time', () {
    test('advance emits exactly one frame per call', timeout: _slow, () {
      final machine = ReplayReconstruction(_transcript(13));

      expect(machine.frames, isEmpty);
      expect(machine.advance(), isTrue);
      expect(machine.frames, hasLength(1));
      expect(machine.frames.single.kind, ReplayFrameKind.initial);

      expect(machine.advance(), isTrue);
      expect(machine.frames, hasLength(2));
    });

    test('advance reports false once every entry is consumed', timeout: _slow, () {
      final transcript = _transcript(13);
      final machine = ReplayReconstruction(transcript);
      while (machine.advance()) {
        // Drain.
      }

      expect(machine.isDone, isTrue);
      expect(machine.failure, isNull);
      expect(machine.advance(), isFalse);
      // Draining twice must not append anything.
      final produced = machine.frames.length;
      expect(machine.advance(), isFalse);
      expect(machine.frames, hasLength(produced));
    });

    test('cancelling stops the machine where it stands', timeout: _slow, () {
      final machine = ReplayReconstruction(_transcript(13));
      for (var i = 0; i < 5; i++) {
        machine.advance();
      }
      final atCancel = machine.frames.length;

      machine.cancel();

      expect(machine.isCancelled, isTrue);
      expect(machine.isDone, isTrue);
      expect(machine.advance(), isFalse);
      expect(machine.frames, hasLength(atCancel));
    });

    test('a failure stops the machine and is reported once', timeout: _slow, () {
      final clean = _transcript(13);
      final entries = [...clean.entries];
      final target = entries[30];
      entries[30] = MatchActionTranscriptEntry(
        order: target.order,
        seat: PlayerSeat.values.firstWhere((s) => s != target.seat),
        roundNumber: target.roundNumber,
        phase: target.phase,
        actionId: target.actionId,
      );

      final machine = ReplayReconstruction(
        MatchActionTranscript(
          initialSnapshot: clean.initialSnapshot,
          entries: entries,
        ),
      );
      while (machine.advance()) {
        // Drain until refusal.
      }

      expect(machine.failure, isNotNull);
      expect(machine.failure!.kind, ReplayTimelineFailureKind.seatMismatch);
      expect(machine.isDone, isTrue);
      expect(machine.advance(), isFalse);
    });
  });

  group('a frame is a historical position and stays that way', () {
    late MatchReplayTimeline timeline;

    setUpAll(() {
      timeline =
          (MatchReplayTimeline.build(_transcript(13)) as ReplayTimelineBuilt)
              .timeline;
    });

    test('the archived first frame cannot be rewritten', timeout: _slow, () {
      // Frame 0 carries the snapshot that was stored with the match. If a
      // caller could mutate it, replaying would change the record it came from.
      final snapshot = timeline.frameAt(0).snapshot;

      expect(() => snapshot.discardPile.clear(), throwsUnsupportedError);
      expect(() => snapshot.stock.clear(), throwsUnsupportedError);
      expect(
        () => snapshot.hands[PlayerSeat.south]!.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => snapshot.activeSeats.add(PlayerSeat.south),
        throwsUnsupportedError,
      );
    });

    test('every frame refuses mutation, outer and nested', timeout: _slow, () {
      for (var i = 0; i < timeline.length; i += 37) {
        final snapshot = timeline.frameAt(i).snapshot;

        expect(() => snapshot.discardPile.clear(), throwsUnsupportedError,
            reason: 'frame $i pile');
        expect(() => snapshot.stock.clear(), throwsUnsupportedError,
            reason: 'frame $i stock');
        expect(() => snapshot.scores.clear(), throwsUnsupportedError,
            reason: 'frame $i scores');
        expect(() => snapshot.removedSeats.clear(), throwsUnsupportedError,
            reason: 'frame $i removed');
        expect(
          () => snapshot.discardHistoryEvents.clear(),
          throwsUnsupportedError,
          reason: 'frame $i history',
        );

        for (final hand in snapshot.hands.values) {
          expect(hand.clear, throwsUnsupportedError, reason: 'frame $i hand');
        }
        expect(() => snapshot.hands.clear(), throwsUnsupportedError);

        // Nested one level deeper: the cards inside a placed meld.
        expect(() => snapshot.tableMelds.clear(), throwsUnsupportedError);
        for (final melds in snapshot.tableMelds.values) {
          expect(melds.clear, throwsUnsupportedError, reason: 'frame $i melds');
          for (final meld in melds) {
            expect(
              meld.cards.clear,
              throwsUnsupportedError,
              reason: 'frame $i meld cards',
            );
          }
        }
      }
    });

    test('freezing preserved the state rather than emptying it', timeout: _slow, () {
      // A frozen-but-wrong snapshot would pass every mutation check above, so
      // the content is checked against the transcript's own starting position.
      final first = timeline.frameAt(0).snapshot;
      final source = _transcript(13).initialSnapshot;

      expect(
        first.discardPile.map((c) => c.id).toList(),
        source.discardPile.map((c) => c.id).toList(),
      );
      expect(first.stock.length, source.stock.length);
      for (final seat in PlayerSeat.values) {
        expect(
          (first.hands[seat] ?? const []).map((c) => c.id).toList(),
          (source.hands[seat] ?? const []).map((c) => c.id).toList(),
          reason: seat.name,
        );
      }
      expect(first.currentSeat, source.currentSeat);
      expect(first.savedAt, source.savedAt);
    });
  });

  group('the Fifty window follows the live table', () {
    ClassicHareegMatchSnapshot windowOpenedAt(DateTime openedAt) {
      final base = ClassicHareegScenario.deal(
        currentSeat: PlayerSeat.south,
      ).controller.toSnapshot(savedAt: replayClockEpoch);
      return ClassicHareegMatchSnapshot.fromJson({
        ...base.toJson(),
        'fiftyWindowOpenedAt': openedAt.toIso8601String(),
        'fiftyWindowDiscarder': PlayerSeat.east.name,
      });
    }

    ReplayFrame frameFor(ClassicHareegMatchSnapshot snapshot) => ReplayFrame(
      index: 0,
      kind: ReplayFrameKind.initial,
      roundNumber: snapshot.roundNumber,
      snapshot: snapshot,
      clock: replayClockEpoch,
    );

    test('an open window reports its remaining seconds', () {
      final snapshot = windowOpenedAt(replayClockEpoch);
      final timer = snapshot.setup.fiftyTimerSeconds;

      expect(
        frameFor(snapshot).fiftySecondsRemainingAt(replayClockEpoch),
        timer,
      );
      expect(
        frameFor(snapshot).fiftySecondsRemainingAt(
          replayClockEpoch.add(Duration(seconds: timer - 1)),
        ),
        1,
      );
    });

    test('it holds at zero through the same grace the live table uses', () {
      final snapshot = windowOpenedAt(replayClockEpoch);
      final timer = snapshot.setup.fiftyTimerSeconds;

      for (var extra = 0; extra <= replayFiftyCueExpiryGraceSeconds; extra++) {
        expect(
          frameFor(snapshot).fiftySecondsRemainingAt(
            replayClockEpoch.add(Duration(seconds: timer + extra)),
          ),
          0,
          reason: '$extra second(s) past expiry is still inside the grace',
        );
      }
    });

    test('past the grace there is no window at all', () {
      final snapshot = windowOpenedAt(replayClockEpoch);
      final timer = snapshot.setup.fiftyTimerSeconds;

      // Clamping to zero forever would keep reporting an open window for the
      // rest of the match, and a reviewer would be told about a window the
      // player never saw.
      expect(
        frameFor(snapshot).fiftySecondsRemainingAt(
          replayClockEpoch.add(
            Duration(seconds: timer + replayFiftyCueExpiryGraceSeconds + 1),
          ),
        ),
        isNull,
      );
      expect(
        frameFor(snapshot).fiftySecondsRemainingAt(
          replayClockEpoch.add(const Duration(hours: 1)),
        ),
        isNull,
      );
    });

    test('a retry that jumps past expiry leaves no window behind', timeout: _slow, () {
      // The retry advances the clock by the timer plus thirty seconds, which is
      // well past the grace. Before this was mirrored, that jump manufactured a
      // zero-valued window on the very frame it expired.
      final transcript = _transcript(13);
      final refused = <String>{};

      final outcome = MatchReplayTimeline.build(
        transcript,
        applyHook: (controller, actionId) {
          if (controller.fiftyClaimant != null && refused.add(actionId)) {
            return ApplyActionResult.failure('Fifty window is still open.');
          }
          return controller.applyAction(actionId);
        },
      );

      final timeline = (outcome as ReplayTimelineBuilt).timeline;
      final adjusted = [
        for (final frame in timeline.frames)
          if (frame.effectivePreActionClock != null) frame,
      ];
      expect(adjusted, isNotEmpty, reason: 'the retry must have fired');

      for (final frame in adjusted) {
        final previous = timeline.frameAt(frame.index - 1);
        final jumped = frame.effectivePreActionClock!;
        final timer = previous.snapshot.setup.fiftyTimerSeconds;

        // The jump is timer + 30s, so any window open beforehand is long gone.
        expect(
          jumped.difference(previous.clock).inSeconds,
          greaterThan(timer + replayFiftyCueExpiryGraceSeconds),
        );
        expect(
          previous.fiftySecondsRemainingAt(jumped),
          isNull,
          reason:
              'frame ${frame.index}: a window cannot survive the retry jump',
        );
      }
    });
  });

  group('the opened-seat set is frozen too', () {
    // `OpeningState` keeps the set it is handed. One live collection anywhere
    // in the graph is enough to rewrite history, so it gets the same treatment
    // as every other collection — and is proved on frame 0, the archived
    // snapshot the match was actually stored with.
    late Set<PlayerSeat> sourceOpenedSeats;
    late MatchReplayTimeline timeline;

    setUp(() {
      sourceOpenedSeats = <PlayerSeat>{PlayerSeat.east};

      final dealt = ClassicHareegScenario.deal(
        currentSeat: PlayerSeat.south,
        openingState: OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          // Deliberately mutable: a snapshot built this way is perfectly valid,
          // which is exactly why the freeze cannot assume otherwise.
          openedSeats: sourceOpenedSeats,
        ),
      ).controller.toSnapshot(savedAt: replayClockEpoch);

      timeline =
          (MatchReplayTimeline.build(
                MatchActionTranscript(
                  initialSnapshot: dealt,
                  entries: const [],
                ),
              )
              as ReplayTimelineBuilt)
          .timeline;
    });

    test('the frame starts out carrying what the source had', () {
      final opening = timeline.frameAt(0).snapshot.openingState;
      expect(opening, isNotNull);
      expect(opening!.openedSeats, contains(PlayerSeat.east));
      expect(opening.currentRequirement, 51);
    });

    test('the set the frame carries refuses mutation', () {
      final opening = timeline.frameAt(0).snapshot.openingState!;

      expect(
        () => opening.openedSeats.add(PlayerSeat.north),
        throwsUnsupportedError,
      );
      expect(
        () => opening.openedSeats.remove(PlayerSeat.east),
        throwsUnsupportedError,
      );
      expect(opening.openedSeats.clear, throwsUnsupportedError);
    });

    test('mutating the source afterwards cannot reach the frame', () {
      // The subtler half: even with the frame's own set locked, sharing the
      // caller's set would let a later write to it rewrite the past.
      sourceOpenedSeats
        ..add(PlayerSeat.north)
        ..add(PlayerSeat.west)
        ..remove(PlayerSeat.east);

      final opening = timeline.frameAt(0).snapshot.openingState!;
      expect(opening.openedSeats, {PlayerSeat.east});
      expect(opening.openedSeats, isNot(contains(PlayerSeat.north)));
      expect(opening.hasOpened(PlayerSeat.east), isTrue);
      expect(opening.hasOpened(PlayerSeat.north), isFalse);
    });
  });
}
