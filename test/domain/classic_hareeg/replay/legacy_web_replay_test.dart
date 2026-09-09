import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/match_replay_timeline.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_recorder.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import '../../../scenario/classic_hareeg_scenario.dart';

void main() {
  test(
    'unversioned web recording reconstructs its original round-two deal',
    () async {
      final meld = [
        for (final rank in [
          CardRank.six,
          CardRank.seven,
          CardRank.eight,
          CardRank.nine,
        ])
          ScenarioCards.card(rank, CardSuit.clubs),
      ];
      final discard = ScenarioCards.card(CardRank.ten, CardSuit.hearts);
      final base = ClassicHareegScenario.deal(
        southHand: [...meld, discard],
        currentSeat: PlayerSeat.south,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      ).controller.toSnapshot();
      ClassicHareegGameController create(
        String algorithm, {
        MatchRecorder? recorder,
      }) => ClassicHareegGameController.fromSnapshot(
        ClassicHareegMatchSnapshot.fromJson({
          ...base.toJson(),
          'roundSeedAlgorithm': algorithm,
        }),
        recorder: recorder,
      );
      final recorder = MatchRecorder();
      final oldWeb = create('legacyWeb', recorder: recorder);
      final stable = create('exact32');
      for (final controller in [oldWeb, stable]) {
        final game = ClassicHareegScenario.fromController(controller);
        expect(game.south.playMeld(meld).isSuccess, isTrue);
        expect(game.south.discard(discard).isSuccess, isTrue);
        expect(controller.isRoundOver, isTrue);
      }
      final legacyNext = oldWeb.nextRoundSnapshot()!;
      final stableNext = stable.nextRoundSnapshot()!;
      expect(legacyNext.seed, isNot(stableNext.seed));
      final resumed = ClassicHareegGameController.fromSnapshot(
        legacyNext,
        recorder: recorder,
      );
      final stableIds = stableNext.hands[resumed.currentSeat]!
          .map((card) => card.id)
          .toSet();
      final action = resumed
          .legalActionIdsFor(resumed.currentSeat)
          .firstWhere(
            (id) =>
                id.startsWith('discard:') &&
                !stableIds.contains(id.substring('discard:'.length)),
          );
      expect(resumed.applyAction(action).isSuccess, isTrue);
      final json = recorder.transcript!.toJson();
      final initial = Map<String, Object?>.from(json['initialSnapshot'] as Map)
        ..remove('roundSeedAlgorithm')
        ..remove('turnJournal');
      final oldTranscript = MatchActionTranscript.fromJson({
        ...json,
        'initialSnapshot': initial,
      });
      final result =
          MatchReplayTimeline.build(oldTranscript) as ReplayTimelineBuilt;
      expect(result.timeline.finalSnapshot.seed, legacyNext.seed);
      expect(
        result.timeline.verifyAgainst(resumed.toPositionSnapshot()),
        isEmpty,
      );
      expect(
        await IncrementalTimelineBuild(oldTranscript, chunkSize: 1).run(),
        isA<ReplayTimelineBuilt>(),
      );
      // The compatibility retry is forbidden for a recording that names its
      // algorithm. It cannot become a general escape hatch for invalid actions.
      final wrongVersion = MatchActionTranscript.fromJson({
        ...json,
        'initialSnapshot': {...initial, 'roundSeedAlgorithm': 'exact32'},
      });
      expect(
        MatchReplayTimeline.build(wrongVersion),
        isA<ReplayTimelineFailed>(),
      );
    },
  );
}
