import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_checkpoint.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/match_replay_timeline.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/replay_branch_seed.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_recorder.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/recorded_checkpoint_recovery.dart';
import '../../../scenario/classic_hareeg_scenario.dart';

void main() {
  test(
    'returning a discard keeps retake forbidden and memory numbering exact after resume',
    () {
      final clock = DateTime.utc(2026, 9, 9);
      final game = ClassicHareegScenario.deal(
        setup: ClassicHareegSetup.defaults(),
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        now: () => clock,
        discardPile: [
          ScenarioCards.card(CardRank.five, CardSuit.clubs, deckIndex: 200),
        ],
      );
      expect(game.south.takeDiscard().isSuccess, isTrue);
      expect(game.south.returnPendingDiscard().isSuccess, isTrue);
      final exact = game.controller.toPositionSnapshot(savedAt: clock);
      final restored = ClassicHareegGameController.fromSnapshot(
        ClassicHareegMatchSnapshot.fromJson(exact.toJson()),
        now: () => clock,
      );
      expect(
        restored.legalActionIdsFor(PlayerSeat.south),
        game.controller.legalActionIdsFor(PlayerSeat.south),
      );
      expect(
        restored.legalActionIdsFor(PlayerSeat.south),
        isNot(contains('take-discard')),
      );
      expect(restored.fiftyClaimant, isNull);
      expect(
        restored.toPositionSnapshot(savedAt: clock).toJson(),
        exact.toJson(),
      );
      expect(game.south.drawStock().isSuccess, isTrue);
      expect(restored.applyAction('draw-stock').isSuccess, isTrue);
      final discard = game.controller
          .legalActionIdsFor(PlayerSeat.south)
          .firstWhere((id) => id.startsWith('discard:'));
      expect(game.controller.applyAction(discard).isSuccess, isTrue);
      expect(restored.applyAction(discard).isSuccess, isTrue);
      expect(
        restored.toPositionSnapshot(savedAt: clock).toJson(),
        game.controller.toPositionSnapshot(savedAt: clock).toJson(),
      );
    },
  );
  final meld = [
    for (final rank in [CardRank.eight, CardRank.nine, CardRank.ten])
      ScenarioCards.card(rank, CardSuit.diamonds),
  ];
  ClassicHareegScenario scenario(MatchRecorder recorder) =>
      ClassicHareegScenario.deal(
        setup: ClassicHareegSetup.defaults(),
        currentSeat: PlayerSeat.south,
        southHand: [
          ...meld,
          for (final rank in CardRank.values.where(
            (rank) => rank != CardRank.ace,
          ))
            ScenarioCards.card(rank, CardSuit.spades),
        ],
        recorder: recorder,
      );

  test(
    'applied frame and branch preserve the real staged opening and undo state',
    () {
      final recorder = MatchRecorder();
      final game = scenario(recorder);
      expect(game.south.playMeld(meld).isSuccess, isTrue);
      final frame =
          (MatchReplayTimeline.build(recorder.transcript!)
                  as ReplayTimelineBuilt)
              .timeline
              .frameAt(1);
      expect(frame.snapshot.tableMelds[PlayerSeat.south], hasLength(1));
      expect(
        frame.snapshot.hands[PlayerSeat.south]!.map((card) => card.id),
        game.south.hand.map((card) => card.id),
      );
      final seed = ReplayBranchSeed.fromFrame(
        frame,
        nextFrame: null,
        branchStart: DateTime.utc(2026, 9, 9),
      )!;
      final branch = ClassicHareegGameController.fromSnapshot(seed.snapshot);
      expect(branch.tableMeldsFor(PlayerSeat.south), hasLength(1));
      expect(
        branch.legalActionIdsFor(PlayerSeat.south),
        game.controller.legalActionIdsFor(PlayerSeat.south),
      );
    },
  );

  test(
    'exact checkpoint and recorder survive resume without resurrecting played cards',
    () {
      final recorder = MatchRecorder();
      final game = scenario(recorder);
      expect(game.south.playMeld(meld).isSuccess, isTrue);
      final checkpoint = MatchCheckpoint.fromJson(
        MatchCheckpoint(
          matchId: 'm-position-cccccccc',
          snapshot: game.controller.toPositionSnapshot(),
          recorderState: recorder.toState(),
        ).toJson(),
      );
      final resumedRecorder = MatchRecorder.restore(checkpoint.recorderState!);
      final restored = ClassicHareegGameController.fromSnapshot(
        checkpoint.snapshot,
        recorder: resumedRecorder,
      );
      expect(
        restored.handFor(PlayerSeat.south).map((card) => card.id),
        game.south.hand.map((card) => card.id),
      );
      expect(restored.tableMeldsFor(PlayerSeat.south), hasLength(1));
      expect(restored.applyAction('return-opening-melds').isSuccess, isTrue);
      final resumed = ClassicHareegScenario.fromController(restored);
      expect(resumed.south.playMeld(meld).isSuccess, isTrue);
      expect(resumedRecorder.transcript!.entries, hasLength(3));
      expect(
        MatchReplayTimeline.build(resumedRecorder.transcript!),
        isA<ReplayTimelineBuilt>(),
      );
    },
  );

  test(
    'old rollback checkpoint is recovered only when it agrees with the transcript',
    () async {
      final recorder = MatchRecorder();
      final game = scenario(recorder);
      expect(game.south.playMeld(meld).isSuccess, isTrue);
      final legacyJson = game.controller.toSnapshot().toJson()
        ..remove('roundSeedAlgorithm');
      final old = MatchCheckpoint(
        matchId: 'm-position-cccccccc',
        snapshot: ClassicHareegMatchSnapshot.fromJson(legacyJson),
        recorderState: recorder.toState(),
      );
      final recovered = await recoverRecordedPosition(old);
      expect(recovered, isNotNull);
      expect(recovered!.tableMelds[PlayerSeat.south], hasLength(1));
      expect(recovered.savedAt, old.snapshot.savedAt);
      final mismatching = ClassicHareegMatchSnapshot.fromJson({
        ...legacyJson,
        'roundNumber': 99,
      });
      expect(
        await recoverRecordedPosition(old.withProgress(snapshot: mismatching)),
        isNull,
      );
    },
  );
}
