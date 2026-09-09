import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_discard_history.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/snapshot_mismatch.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/match_replay_timeline.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/replay_branch_seed.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

import '../../../support/completed_match_fixture.dart';

/// The branch clock is injected everywhere here. Nothing sleeps, so the Fifty
/// window's behaviour is asserted at exact instants rather than raced against.
void main() {
  final setup = ClassicHareegSetup.defaults();
  final timer = setup.fiftyTimerSeconds;
  final replayNow = replayClockEpoch.add(const Duration(minutes: 5));
  final branchStart = DateTime.utc(2027, 3, 4, 12);

  /// Seconds left on the rebased window, measured [after] the branch instant.
  ///
  /// Read through the production formula on a frame built from the rebased
  /// snapshot, so the test cannot drift from the rule it is checking.
  int? remainingAfter(ReplayBranchSeed seed, Duration after) {
    return _frame(
      seed.snapshot,
      clock: seed.branchStart.add(after),
    ).fiftySecondsRemainingAt(seed.branchStart.add(after));
  }

  ReplayBranchSeed seedWithWindowElapsed(int elapsedSeconds) {
    final snapshot = _snapshot(
      setup: setup,
      fiftyWindowOpenedAt: replayNow.subtract(Duration(seconds: elapsedSeconds)),
    );
    final seed = ReplayBranchSeed.fromFrame(
      _frame(snapshot, clock: replayNow),
      nextFrame: null,
      branchStart: branchStart,
    );
    return seed!;
  }

  group('availability', () {
    test('a match-complete frame refuses to branch', () {
      final frame = _frame(
        _snapshot(setup: setup),
        clock: replayNow,
        matchWinner: PlayerSeat.south,
      );

      expect(
        ReplayBranchSeed.refusalFor(frame, nextFrame: null),
        ReplayBranchRefusal.matchAlreadyComplete,
      );
      expect(
        ReplayBranchSeed.fromFrame(frame, nextFrame: null, branchStart: branchStart),
        isNull,
      );
    });

    test('an ordinary frame branches', () {
      final frame = _frame(_snapshot(setup: setup), clock: replayNow);
      expect(ReplayBranchSeed.refusalFor(frame, nextFrame: null), isNull);
      expect(
        ReplayBranchSeed.fromFrame(frame, nextFrame: null, branchStart: branchStart),
        isNotNull,
      );
    });
  });

  group('real round boundaries on a played match', () {
    // These run against the seed-13 timeline the history fixtures use, not
    // against hand-built frames. The synthetic cases above cannot reach this
    // failure: a round END frame is one where a seat has gone out, and the
    // snapshot has no field that says so, so restoring it reopened a round
    // that had already been scored and left the winner holding nothing.
    late MatchReplayTimeline timeline;
    late List<int> boundaries;

    setUpAll(() {
      final state = buildCompletedMatch(seed: 13).recorderState;
      final outcome = MatchReplayTimeline.build(
        MatchActionTranscript(
          initialSnapshot: state.initialSnapshot!,
          entries: state.entries,
        ),
      );
      timeline = (outcome as ReplayTimelineBuilt).timeline;
      boundaries = [
        for (var i = 1; i < timeline.length; i++)
          if (timeline.frameAt(i).roundNumber >
              timeline.frameAt(i - 1).roundNumber)
            i - 1,
      ];
    });

    ReplayBranchSeed? seedAt(int index) => ReplayBranchSeed.fromFrame(
      timeline.frameAt(index),
      nextFrame: index + 1 < timeline.length
          ? timeline.frameAt(index + 1)
          : null,
      branchStart: branchStart,
    );

    test('the fixture really contains round boundaries to test', () {
      // Without this the whole group could pass over an empty list.
      expect(boundaries, isNotEmpty);
      expect(boundaries.length, greaterThanOrEqualTo(4));
    });

    test('every round-end frame yields a playable next round', () {
      for (final index in boundaries) {
        final branchPoint = timeline.frameAt(index);
        final seed = seedAt(index);
        expect(seed, isNotNull, reason: 'frame $index refused');

        // It advanced exactly one round...
        expect(
          seed!.roundNumber,
          branchPoint.roundNumber + 1,
          reason: 'frame $index did not advance exactly one round',
        );
        expect(seed.advancedPastRoundEnd, isTrue, reason: 'frame $index');

        // ...and the position it hands the table is one somebody can play.
        final controller = ClassicHareegGameController.fromSnapshot(
          seed.snapshot,
          now: () => seed.branchStart,
        );
        expect(
          controller.isRoundOver,
          isFalse,
          reason: 'frame $index reopened a finished round',
        );
        expect(controller.roundResult, isNull, reason: 'frame $index');
        // Every seat still IN the round holds cards. A removed seat holding
        // none is correct and is not a stranded winner.
        for (final seat in controller.roundActiveSeats) {
          expect(
            controller.handFor(seat),
            isNotEmpty,
            reason: 'frame $index left $seat stranded with an empty hand',
          );
        }
      }
    });

    test('the round that just ended is not rescored', () {
      for (final index in boundaries) {
        final seed = seedAt(index)!;
        // The seed adopts the next frame's recorded state, so its scores are
        // the ones the real match reached. Re-running the scoring would be a
        // second penalty for a round that was already paid for.
        expect(
          seed.snapshot.scores,
          timeline.frameAt(index + 1).snapshot.scores,
          reason: 'frame $index rescored the completed round',
        );
      }
    });

    test('exiting returns to the chosen frame, not the one it starts from', () {
      for (final index in boundaries) {
        expect(seedAt(index)!.frameIndex, index, reason: 'frame $index');
      }
    });

    test('a South winner and a CPU winner are both covered', () {
      // The two cases the verdict names. Identified by which seat emptied its
      // hand at the boundary, read off the frame rather than assumed.
      final winners = <PlayerSeat>{};
      for (final index in boundaries) {
        for (final entry in timeline.frameAt(index).snapshot.hands.entries) {
          if (entry.value.isEmpty) winners.add(entry.key);
        }
      }
      expect(
        winners,
        contains(PlayerSeat.south),
        reason: 'the fixture must contain a South-won round',
      );
      expect(
        winners.where((s) => s != PlayerSeat.south),
        isNotEmpty,
        reason: 'the fixture must contain a CPU-won round',
      );
    });

    test('an ordinary mid-round frame does not advance', () {
      // The other half of the guarantee: only a boundary advances. A seed that
      // advanced everywhere would pass every assertion above and be wrong.
      final boundary = boundaries.first;
      final ordinary = boundary - 1;
      expect(
        timeline.frameAt(ordinary).roundNumber,
        timeline.frameAt(boundary).roundNumber,
      );
      final seed = seedAt(ordinary)!;
      expect(seed.advancedPastRoundEnd, isFalse);
      expect(seed.roundNumber, timeline.frameAt(ordinary).roundNumber);
    });

    test('a round end with nothing recorded after it is refused', () {
      // Truncating the recording at a boundary leaves a finished round and no
      // next deal. Inventing one would be a different match, so it refuses.
      final index = boundaries.first;
      expect(
        ReplayBranchSeed.refusalFor(timeline.frameAt(index), nextFrame: null),
        ReplayBranchRefusal.roundEndedWithoutNextRound,
      );
      expect(
        ReplayBranchSeed.fromFrame(
          timeline.frameAt(index),
          nextFrame: null,
          branchStart: branchStart,
        ),
        isNull,
      );
    });
  });

  group('Fifty window rebase', () {
    test('no window stays absent', () {
      final seed = ReplayBranchSeed.fromFrame(
        _frame(_snapshot(setup: setup), clock: replayNow),
        nextFrame: null,
      branchStart: branchStart,
      )!;

      expect(seed.fiftySecondsRemaining, isNull);
      expect(seed.snapshot.fiftyWindowOpenedAt, isNull);
      expect(remainingAfter(seed, Duration.zero), isNull);
    });

    test('remaining seconds are preserved exactly at the branch instant', () {
      final seed = seedWithWindowElapsed(timer - 7);

      expect(seed.fiftySecondsRemaining, 7);
      expect(remainingAfter(seed, Duration.zero), 7);
    });

    test('one second remaining stays one second', () {
      final seed = seedWithWindowElapsed(timer - 1);

      expect(seed.fiftySecondsRemaining, 1);
      expect(remainingAfter(seed, Duration.zero), 1);
      // And it runs down live from there: branching restores real time.
      expect(remainingAfter(seed, const Duration(seconds: 1)), 0);
    });

    test('an already-expired window past grace does not reopen', () {
      final seed = seedWithWindowElapsed(timer + 30);

      expect(seed.fiftySecondsRemaining, isNull);
      expect(remainingAfter(seed, Duration.zero), isNull);
    });

    // The two cases that a remaining-based rebase gets wrong. Every instant
    // inside grace reports `remaining == 0`, so reconstructing the origin from
    // it would restart grace and hand the window time it had already spent.
    test('grace elapsed 1s vanishes at its original boundary, not a fresh one', () {
      final seed = seedWithWindowElapsed(timer + 1);

      expect(seed.fiftySecondsRemaining, 0);
      expect(remainingAfter(seed, Duration.zero), 0);
      // One second of grace was already spent, so one remains.
      expect(remainingAfter(seed, const Duration(seconds: 1)), 0);
      // A restarted grace would still report 0 here. It must be gone.
      expect(remainingAfter(seed, const Duration(seconds: 2)), isNull);
    });

    test('grace elapsed 2s vanishes immediately after, not two seconds later', () {
      final seed = seedWithWindowElapsed(timer + 2);

      expect(seed.fiftySecondsRemaining, 0);
      expect(remainingAfter(seed, Duration.zero), 0);
      // Grace is fully spent: a restarted grace would report 0 for two more
      // seconds.
      expect(remainingAfter(seed, const Duration(seconds: 1)), isNull);
    });

    test('effectivePreActionClock is the reference when present', () {
      // The frame's own clock is past the expiry jump; the pre-action clock is
      // the one that describes the state this frame is showing.
      final preAction = replayNow;
      final snapshot = _snapshot(
        setup: setup,
        fiftyWindowOpenedAt: preAction.subtract(Duration(seconds: timer - 4)),
      );
      final seed = ReplayBranchSeed.fromFrame(
        _frame(
          snapshot,
          clock: preAction.add(const Duration(seconds: 90)),
          effectivePreActionClock: preAction,
        ),
        nextFrame: null,
      branchStart: branchStart,
      )!;

      // Read against the frame clock this would be long gone; against the
      // pre-action clock it has four seconds left.
      expect(seed.fiftySecondsRemaining, 4);
      expect(remainingAfter(seed, Duration.zero), 4);
    });

    test('a retry-advanced clock does not invent a window', () {
      // After a retry pushes the clock past expiry and grace, the frame has no
      // visible window and the branch must not resurrect one.
      final preAction = replayNow;
      final snapshot = _snapshot(
        setup: setup,
        fiftyWindowOpenedAt: preAction.subtract(
          Duration(seconds: timer + 60),
        ),
      );
      final seed = ReplayBranchSeed.fromFrame(
        _frame(
          snapshot,
          clock: preAction.add(const Duration(seconds: 120)),
          effectivePreActionClock: preAction,
        ),
        nextFrame: null,
      branchStart: branchStart,
      )!;

      expect(seed.fiftySecondsRemaining, isNull);
      expect(remainingAfter(seed, Duration.zero), isNull);
    });
  });

  group('whole-state parity', () {
    // Every optional provenance field non-null, discard history non-empty,
    // and — critically — **every setup field non-default**. With defaults, a
    // codec that dropped `cpuDifficulty` or `deckCount` would decode back to
    // the same default on both sides and the comparison would agree falsely.
    ClassicHareegMatchSnapshot richSnapshot() => _snapshot(
      setup: _richSetup,
      fiftyWindowOpenedAt: replayNow.subtract(const Duration(seconds: 3)),
      rich: true,
    );

    test('only the two clock fields change; every other field survives', () {
      final original = richSnapshot();
      final seed = ReplayBranchSeed.fromFrame(
        _frame(original, clock: replayNow),
        nextFrame: null,
      branchStart: branchStart,
      )!;

      // Codec JSON is the whole state, so this catches fields the domain
      // comparator never looks at.
      final before = Map<String, Object?>.of(original.toJson())
        ..remove('savedAt')
        ..remove('fiftyWindowOpenedAt');
      final after = Map<String, Object?>.of(seed.snapshot.toJson())
        ..remove('savedAt')
        ..remove('fiftyWindowOpenedAt');

      expect(after, before);

      // The domain comparator agrees, and states its own limits: it omits the
      // volatile clock fields, which are exactly the two this rebase changes.
      // Kept alongside the JSON comparison rather than instead of it — on its
      // own it would pass while silently ignoring most of the state.
      expect(
        describeSnapshotMismatch(expected: original, actual: seed.snapshot),
        isEmpty,
      );

      // The two that are meant to change, did.
      expect(seed.snapshot.savedAt, branchStart);
      expect(
        seed.snapshot.fiftyWindowOpenedAt,
        isNot(original.fiftyWindowOpenedAt),
      );
    });

    test('fields the snapshot comparator omits are asserted directly', () {
      // `describeSnapshotMismatch` does not compare these. Naming each one
      // means a codec omission cannot hide behind two maps that agree only
      // because both lost the same field.
      final original = richSnapshot();
      final rebased = ReplayBranchSeed.fromFrame(
        _frame(original, clock: replayNow),
        nextFrame: null,
      branchStart: branchStart,
      )!.snapshot;

      // All seven setup fields, each non-default in the fixture.
      expect(rebased.setup.cpuDifficulty, original.setup.cpuDifficulty);
      expect(rebased.setup.cpuDifficulty, isNot(setup.cpuDifficulty));
      expect(rebased.setup.starterMode, original.setup.starterMode);
      expect(rebased.setup.starterMode, isNot(setup.starterMode));
      expect(rebased.setup.openingRequirement, original.setup.openingRequirement);
      expect(rebased.setup.openingRequirement, isNot(setup.openingRequirement));
      expect(rebased.setup.deckCount, original.setup.deckCount);
      expect(rebased.setup.deckCount, isNot(setup.deckCount));
      expect(rebased.setup.jokerCount, original.setup.jokerCount);
      expect(rebased.setup.jokerCount, isNot(setup.jokerCount));
      expect(rebased.setup.fiftyTimerSeconds, original.setup.fiftyTimerSeconds);
      expect(rebased.setup.fiftyTimerSeconds, isNot(setup.fiftyTimerSeconds));
      expect(rebased.setup.tableStrictness, original.setup.tableStrictness);
      expect(rebased.setup.tableStrictness, isNot(setup.tableStrictness));

      expect(rebased.seed, original.seed);
      expect(rebased.starter, original.starter);
      expect(rebased.roundNumber, original.roundNumber);

      // All five opening-state fields, from a non-default state.
      final before = original.openingState!;
      final after = rebased.openingState!;
      expect(after.baseRequirement, before.baseRequirement);
      expect(after.currentRequirement, before.currentRequirement);
      expect(after.benchmarkOwner, before.benchmarkOwner);
      expect(after.isLocked, before.isLocked);
      expect(after.openedSeats, before.openedSeats);
      expect(after.openedSeats, isNotEmpty);

      // Pin the fixture's actual non-default shape, so a later change to the
      // opening rules cannot quietly turn this back into an initial state
      // while every comparison above still agrees.
      expect(after.openedSeats, {PlayerSeat.south, PlayerSeat.north});
      expect(after.benchmarkOwner, PlayerSeat.south);
      expect(after.isLocked, isTrue);
      expect(after.currentRequirement, greaterThan(after.baseRequirement));

      expect(rebased.fiftyWindowDiscarder, original.fiftyWindowDiscarder);
      expect(
        rebased.fiftyWindowIsFirstDealtRound,
        original.fiftyWindowIsFirstDealtRound,
      );
      expect(rebased.activeFiftyClaimCardId, original.activeFiftyClaimCardId);
      expect(
        rebased.activeFiftyClaimDiscarder,
        original.activeFiftyClaimDiscarder,
      );
      expect(
        rebased.activeFiftyClaimIsFirstDealtRound,
        original.activeFiftyClaimIsFirstDealtRound,
      );
      expect(rebased.windowedTakeCardId, original.windowedTakeCardId);
      expect(rebased.windowedTakeDiscarder, original.windowedTakeDiscarder);
      expect(
        rebased.windowedTakeIsFirstDealtRound,
        original.windowedTakeIsFirstDealtRound,
      );

      // Every discard event, in order, field by field — length alone would
      // pass for two events with swapped seats or mangled cards.
      expect(rebased.discardHistoryEvents, isNotEmpty);
      expect(
        rebased.discardHistoryEvents.length,
        original.discardHistoryEvents.length,
      );
      for (var i = 0; i < original.discardHistoryEvents.length; i++) {
        final expected = original.discardHistoryEvents[i];
        final actual = rebased.discardHistoryEvents[i];
        expect(actual.seat, expected.seat, reason: 'event $i seat');
        expect(actual.kind, expected.kind, reason: 'event $i kind');
        expect(actual.sequence, expected.sequence, reason: 'event $i sequence');
        expect(
          actual.card.toJson(),
          expected.card.toJson(),
          reason: 'event $i card',
        );
      }

      expect(rebased.removedSeats, original.removedSeats);
      expect(rebased.activeSeats, original.activeSeats);
      expect(rebased.scores, original.scores);
    });

    test('the branch point is carried for returning to review', () {
      final seed = ReplayBranchSeed.fromFrame(
        _frame(_snapshot(setup: setup), clock: replayNow, index: 42,
            roundNumber: 3),
        nextFrame: null,
      branchStart: branchStart,
      )!;

      expect(seed.frameIndex, 42);
      expect(seed.roundNumber, 3);
      expect(seed.branchStart, branchStart);
    });
  });
}

/// Every field deliberately different from [ClassicHareegSetup.defaults].
final _richSetup = const ClassicHareegSetup(
  cpuDifficulty: CpuDifficulty.skilled,
  starterMode: StarterMode.random,
  openingRequirement: 61,
  deckCount: 3,
  jokerCount: 4,
  fiftyTimerSeconds: 9,
  tableStrictness: TableStrictness.table,
);

ReplayFrame _frame(
  ClassicHareegMatchSnapshot snapshot, {
  required DateTime clock,
  int index = 0,
  int roundNumber = 1,
  PlayerSeat? matchWinner,
  DateTime? effectivePreActionClock,
}) {
  return ReplayFrame(
    index: index,
    kind: ReplayFrameKind.actionApplied,
    roundNumber: roundNumber,
    snapshot: snapshot,
    clock: clock,
    matchWinner: matchWinner,
    effectivePreActionClock: effectivePreActionClock,
  );
}

/// Two seats opened, producing a state non-default in all five fields.
///
/// South opens first and becomes the benchmark owner, raising
/// `currentRequirement` above `baseRequirement`. North must then clear that
/// raised value to open at all — but doing so does **not** transfer ownership
/// or raise the requirement again: South stays the owner, South's requirement
/// stands, and North's opening **locks** the state. So the fixture ends with
/// `openedSeats == {south, north}`, `benchmarkOwner == south`,
/// `isLocked == true`, all pinned by assertion below.
OpeningState _richOpeningState(ClassicHareegSetup setup) {
  var state = OpeningState.initial(setup.openingRequirement);
  state = ClassicHareegOpeningRules.applyOpening(
    state: state,
    seat: PlayerSeat.south,
    melds: [
      PlacedMeld(cards: const [], valueSnapshot: setup.openingRequirement + 12),
    ],
  );
  return ClassicHareegOpeningRules.applyOpening(
    state: state,
    seat: PlayerSeat.north,
    melds: [
      // Must clear the requirement south's opening just raised. Clearing it is
      // what makes this opening legal at all; it does not take ownership.
      PlacedMeld(cards: const [], valueSnapshot: setup.openingRequirement + 20),
    ],
  );
}

ClassicHareegMatchSnapshot _snapshot({
  required ClassicHareegSetup setup,
  DateTime? fiftyWindowOpenedAt,
  bool rich = false,
}) {
  final dealt = ClassicHareegRound.deal(setup: setup, seed: 5);
  final discard = dealt.discardPile.isNotEmpty
      ? dealt.discardPile.last
      : HareegCard.standard(
          rank: CardRank.four,
          suit: CardSuit.hearts,
          deckIndex: 0,
        );

  return ClassicHareegMatchSnapshot(
    setup: setup,
    hands: dealt.hands,
    stock: dealt.stock,
    discardPile: dealt.discardPile,
    starter: dealt.starter,
    currentSeat: PlayerSeat.east,
    turnPhase: TurnPhase.action,
    savedAt: DateTime.utc(2026, 1, 2),
    seed: rich ? 4242 : null,
    roundNumber: rich ? 3 : 1,
    scores: rich
        ? const {
            PlayerSeat.south: 5,
            PlayerSeat.east: 9,
            PlayerSeat.north: 12,
            PlayerSeat.west: 2,
          }
        : const {},
    removedSeats: rich ? const [PlayerSeat.west] : const [],
    openingState: rich ? _richOpeningState(setup) : null,
    fiftyWindowOpenedAt: fiftyWindowOpenedAt,
    fiftyWindowDiscarder: rich ? PlayerSeat.north : null,
    fiftyWindowIsFirstDealtRound: rich ? true : null,
    activeFiftyClaimCardId: rich ? discard.id : null,
    activeFiftyClaimDiscarder: rich ? PlayerSeat.east : null,
    activeFiftyClaimIsFirstDealtRound: rich ? false : null,
    windowedTakeCardId: rich ? discard.id : null,
    windowedTakeDiscarder: rich ? PlayerSeat.west : null,
    windowedTakeIsFirstDealtRound: rich ? true : null,
    discardHistoryEvents: rich
        ? [
            DiscardEvent(
              seat: PlayerSeat.east,
              card: discard,
              kind: DiscardEventKind.discard,
              sequence: 1,
            ),
            DiscardEvent(
              seat: PlayerSeat.north,
              card: discard,
              kind: DiscardEventKind.pickup,
              sequence: 2,
            ),
          ]
        : const [],
  );
}
