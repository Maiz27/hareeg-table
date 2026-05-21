import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_flow.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/classic_hareeg_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';

void main() {
  group('ClassicHareegMatchFlow', () {
    test('returns null before a round result is available', () {
      final flow = _flow();

      expect(flow.progressFor(null), isNull);
      expect(flow.nextRoundSnapshotFor(roundResult: null), isNull);
    });

    test('creates next round snapshot from completed round progress', () {
      final savedAt = DateTime.utc(2026, 5, 21, 8, 30);
      final flow = _flow(
        scores: const {
          PlayerSeat.south: 4,
          PlayerSeat.east: 5,
          PlayerSeat.north: 6,
          PlayerSeat.west: 7,
        },
        activeSeats: const [
          PlayerSeat.south,
          PlayerSeat.east,
          PlayerSeat.north,
        ],
        currentStarter: PlayerSeat.east,
        roundNumber: 4,
      );
      const result = RoundProgressResult(
        type: RoundOutcomeType.normalFinish,
        winner: PlayerSeat.south,
        remainingCardCounts: {
          PlayerSeat.south: 0,
          PlayerSeat.east: 3,
          PlayerSeat.north: 4,
        },
      );

      final progress = flow.progressFor(result);
      final next = flow.nextRoundSnapshotFor(
        roundResult: result,
        savedAt: savedAt,
      );

      expect(progress, isNotNull);
      expect(progress!.scores, {
        PlayerSeat.south: 3,
        PlayerSeat.east: 8,
        PlayerSeat.north: 10,
        PlayerSeat.west: 7,
      });
      expect(progress.activeSeats, [
        PlayerSeat.south,
        PlayerSeat.east,
        PlayerSeat.north,
      ]);
      expect(progress.nextStarter, PlayerSeat.south);

      expect(next, isNotNull);
      expect(next!.scores, progress.scores);
      expect(next.activeSeats, progress.activeSeats);
      expect(next.starter, progress.nextStarter);
      expect(next.currentSeat, progress.nextStarter);
      expect(next.roundNumber, 5);
      expect(next.savedAt, savedAt);
      expect(next.discardPile, isEmpty);
      expect(next.pendingDiscard, isNull);
      expect(next.removedSeats, isEmpty);
      expect(
        next.openingState!.currentRequirement,
        flow.setup.openingRequirement,
      );
      expect(next.tableMelds.values.every((melds) => melds.isEmpty), isTrue);
    });

    test('does not deal another round after a match winner is produced', () {
      final flow = _flow(
        scores: const {
          PlayerSeat.south: 0,
          PlayerSeat.east: 30,
          PlayerSeat.north: 30,
          PlayerSeat.west: 30,
        },
      );
      const result = RoundProgressResult(
        type: RoundOutcomeType.normalFinish,
        winner: PlayerSeat.south,
        remainingCardCounts: {
          PlayerSeat.south: 0,
          PlayerSeat.east: 1,
          PlayerSeat.north: 1,
          PlayerSeat.west: 1,
        },
      );

      final progress = flow.progressFor(result);

      expect(progress!.matchWinner, PlayerSeat.south);
      expect(flow.nextRoundSnapshotFor(roundResult: result), isNull);
    });
  });
}

ClassicHareegMatchFlow _flow({
  Map<PlayerSeat, int>? scores,
  List<PlayerSeat>? activeSeats,
  PlayerSeat currentStarter = PlayerSeat.south,
  int roundNumber = 1,
}) {
  return ClassicHareegMatchFlow(
    setup: ClassicHareegSetup.defaults(),
    rules: ClassicHareegRules.defaults(),
    scores: scores ?? {for (final seat in PlayerSeat.values) seat: 0},
    activeSeats: activeSeats ?? PlayerSeat.values,
    currentStarter: currentStarter,
    roundNumber: roundNumber,
  );
}
