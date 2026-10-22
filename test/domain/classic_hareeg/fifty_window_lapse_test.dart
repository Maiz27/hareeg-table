import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/replay_reconstruction.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_recorder.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

/// Regression coverage for the release-build hang: the stock is empty, the
/// previous seat's discard opens a Fifty window for the human, the human lets
/// it run out, and the table sits there. The round stayed open only because a
/// valid Fifty finish existed on the thrown card, and expiry is a clock event
/// with no action behind it, so nothing re-ran the stock-exhaustion decision
/// once the claim was gone. The player had to take and return the discard by
/// hand to end the round.
void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12);
  final setup = ClassicHareegSetup.defaults();
  final live = t0.add(const Duration(seconds: 1));
  final lapsed = t0.add(Duration(seconds: setup.fiftyTimerSeconds + 5));

  group('settleLapsedFiftyWindow', () {
    test(
      'a stock-exhausted draw phase held open only by a Fifty claim draws the '
      'round when the window lapses',
      () {
        var now = live;
        // South (unopened) holds 4C 5C 6C 2D; the thrown 7H only extends
        // North's 8H 9H 10H. The Fifty *claim* path can realise that cover
        // finish (its proof opens first), so the round stays open while the
        // window is live — but the plain pickup path cannot, so once the
        // window lapses nothing is left: no stock, no claim, no finishing take.
        final controller = _southClaimantController(
          setup: setup,
          now: () => now,
          southHand: _coverOnlyHand,
          discardTop: _c(CardRank.seven, CardSuit.hearts),
        );

        expect(controller.isRoundOver, isFalse);
        expect(
          controller.legalActionIdsFor(PlayerSeat.south),
          contains(ClassicHareegActionIds.claimFifty),
        );
        expect(
          controller.settleLapsedFiftyWindow(),
          isFalse,
          reason: 'a live window must not be settled early',
        );
        expect(controller.isRoundOver, isFalse);

        now = lapsed;
        expect(
          controller.legalActionIdsFor(PlayerSeat.south),
          isEmpty,
          reason: 'the stranded state: nothing legal, round still open',
        );

        expect(controller.settleLapsedFiftyWindow(), isTrue);

        expect(controller.isRoundOver, isTrue);
        expect(controller.roundResult?.type, RoundOutcomeType.draw);
        expect(controller.fiftyClaimant, isNull);
        expect(
          controller.roundEndedByLivelockBackstop,
          isFalse,
          reason:
              'the lapse settles through the normal stock-exhaustion '
              'planner, not the liveness backstop',
        );
        expect(
          controller.settleLapsedFiftyWindow(),
          isFalse,
          reason: 'each window settles at most once',
        );
      },
    );

    test('a lapsed window with a realizable pickup finish keeps the round open '
        'on that finish alone', () {
      var now = live;
      // Same shape, but the thrown 6C melds with South's 4C 5C: a finish the
      // pickup path can actually play out.
      final controller = _southClaimantController(
        setup: setup,
        now: () => now,
        southHand: [
          _c(CardRank.four, CardSuit.clubs),
          _c(CardRank.five, CardSuit.clubs),
          _c(CardRank.two, CardSuit.diamonds),
        ],
        discardTop: _c(CardRank.six, CardSuit.clubs),
      );
      expect(controller.isRoundOver, isFalse);

      now = lapsed;
      expect(controller.settleLapsedFiftyWindow(), isTrue);

      expect(controller.isRoundOver, isFalse);
      expect(controller.fiftyClaimant, isNull);
      expect(
        controller.legalActionIdsFor(PlayerSeat.south),
        [ClassicHareegActionIds.takeDiscard],
        reason: 'only the finishing take continues after empty stock',
      );
    });

    test('is a no-op without a window', () {
      final controller = ClassicHareegGameController.fromRound(
        ClassicHareegRound.deal(setup: setup, seed: 7),
      );
      expect(controller.fiftyClaimant, isNull);
      expect(controller.settleLapsedFiftyWindow(), isFalse);
      expect(controller.isRoundOver, isFalse);
    });
  });

  group('replay reconstruction', () {
    test('crosses a round that ended because the Fifty window lapsed with the '
        'stock empty', () {
      // The recorded match starts (a resumed save) with the window already
      // open for South, stamped at the replay epoch so the synthetic clock
      // reads it the way the live clock did: live at first, then lapsed.
      final opened = replayClockEpoch;
      var now = opened.add(const Duration(seconds: 1));
      final recorder = MatchRecorder();
      final first = _southClaimantController(
        setup: setup,
        now: () => now,
        southHand: _coverOnlyHand,
        discardTop: _c(CardRank.seven, CardSuit.hearts),
        openedAt: opened,
        roundNumber: 1,
        recorder: recorder,
      );
      expect(first.fiftyClaimant, PlayerSeat.south);
      expect(first.isRoundOver, isFalse);

      // The human lets the window run out; the live table settles it. No
      // action is recorded for round 1 at all.
      now = opened.add(Duration(seconds: setup.fiftyTimerSeconds + 5));
      expect(first.settleLapsedFiftyWindow(), isTrue);
      expect(first.roundResult?.type, RoundOutcomeType.draw);

      final next = first.nextRoundSnapshot(savedAt: now);
      expect(next, isNotNull);
      final second = ClassicHareegGameController.fromSnapshot(
        next!,
        recorder: recorder,
        now: () => now,
      );
      final opening = second.legalActionIdsFor(second.currentSeat).first;
      final applied = second.applyAction(opening);
      expect(applied.isSuccess, isTrue, reason: applied.message);

      final state = recorder.toState();
      final transcript = MatchActionTranscript(
        initialSnapshot: state.initialSnapshot!,
        entries: state.entries,
      );
      expect(transcript.entries.map((e) => e.roundNumber), [2]);
      expect(transcript.initialSnapshot.fiftyWindowOpenedAt, opened);

      final machine = ReplayReconstruction(transcript);
      while (machine.advance()) {
        // Drain.
      }

      expect(machine.failure, isNull, reason: machine.failure?.message);
      expect(machine.frames.map((f) => f.kind), [
        ReplayFrameKind.initial,
        ReplayFrameKind.roundStart,
        ReplayFrameKind.actionApplied,
      ]);
      expect(machine.frames[1].roundNumber, 2);
      expect(
        machine.frames[1].snapshot.hands,
        next.hands,
        reason: 'replay must deal the same round 2 the live match did',
      );
      expect(machine.frames.last.appliedEntry, transcript.entries.single);
    });
  });
}

HareegCard _c(CardRank rank, CardSuit suit, [int deckIndex = 0]) =>
    HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);

final _coverOnlyHand = [
  _c(CardRank.four, CardSuit.clubs),
  _c(CardRank.five, CardSuit.clubs),
  _c(CardRank.six, CardSuit.clubs),
  _c(CardRank.two, CardSuit.diamonds),
];

final _northRun = [
  _c(CardRank.eight, CardSuit.hearts),
  _c(CardRank.nine, CardSuit.hearts),
  _c(CardRank.ten, CardSuit.hearts),
];

/// A stock-empty round with South (unopened, the human) in draw phase as the
/// claimant of a window West opened at [t0], and a lowered opening requirement
/// so a single low club run opens.
ClassicHareegGameController _southClaimantController({
  required ClassicHareegSetup setup,
  required DateTime Function() now,
  required List<HareegCard> southHand,
  required HareegCard discardTop,
  DateTime? openedAt,
  int roundNumber = 2,
  MatchRecorder? recorder,
}) {
  final t0 = openedAt ?? DateTime.utc(2026, 1, 1, 12);
  return ClassicHareegGameController.fromSnapshot(
    ClassicHareegMatchSnapshot(
      setup: setup,
      hands: {
        PlayerSeat.south: southHand,
        PlayerSeat.east: [_c(CardRank.king, CardSuit.spades)],
        PlayerSeat.north: [_c(CardRank.queen, CardSuit.spades)],
        PlayerSeat.west: [_c(CardRank.nine, CardSuit.spades)],
      },
      stock: const [],
      discardPile: [discardTop],
      tableMelds: {
        PlayerSeat.north: [PlacedMeld.fromCards(_northRun)],
      },
      starter: PlayerSeat.south,
      currentSeat: PlayerSeat.south,
      turnPhase: TurnPhase.draw,
      openingState: OpeningState.initial(15),
      roundNumber: roundNumber,
      savedAt: t0,
      fiftyWindowOpenedAt: t0,
      fiftyWindowDiscarder: PlayerSeat.south.previousAntiClockwise,
      previousDiscardSeat: PlayerSeat.south.previousAntiClockwise,
    ),
    now: now,
    recorder: recorder,
  );
}
