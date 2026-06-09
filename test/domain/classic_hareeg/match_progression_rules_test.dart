import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';

void main() {
  group('ClassicHareegMatchProgressionRules', () {
    test('normal finish gives winner -1 and others remaining counts', () {
      final state = apply(
        result: const RoundProgressResult(
          type: RoundOutcomeType.normalFinish,
          winner: PlayerSeat.south,
          remainingCardCounts: {
            PlayerSeat.south: 0,
            PlayerSeat.east: 5,
            PlayerSeat.north: 9,
            PlayerSeat.west: 14,
          },
        ),
      );

      expect(state.scores[PlayerSeat.south], -1);
      expect(state.scores[PlayerSeat.east], 5);
      expect(state.scores[PlayerSeat.north], 9);
      expect(state.scores[PlayerSeat.west], 14);
      expect(state.nextStarter, PlayerSeat.south);
    });

    test('Fifty finish applies winner benefit and discarder penalty', () {
      final state = apply(
        result: const RoundProgressResult(
          type: RoundOutcomeType.fiftyFinish,
          winner: PlayerSeat.east,
          fiftyDiscarder: PlayerSeat.south,
          remainingCardCounts: {
            PlayerSeat.south: 11,
            PlayerSeat.east: 0,
            PlayerSeat.north: 6,
            PlayerSeat.west: 8,
          },
        ),
      );

      expect(state.scores[PlayerSeat.east], -3);
      expect(state.scores[PlayerSeat.south], 14);
      expect(state.scores[PlayerSeat.north], 6);
      expect(state.scores[PlayerSeat.west], 8);
      expect(state.nextStarter, PlayerSeat.east);
    });

    test('first-round Fifty exception gives winner -1', () {
      final state = apply(
        result: const RoundProgressResult(
          type: RoundOutcomeType.fiftyFinish,
          winner: PlayerSeat.east,
          fiftyDiscarder: PlayerSeat.south,
          firstRoundFiftyException: true,
          remainingCardCounts: {
            PlayerSeat.south: 11,
            PlayerSeat.east: 0,
            PlayerSeat.north: 6,
            PlayerSeat.west: 8,
          },
        ),
      );

      expect(state.scores[PlayerSeat.east], -1);
    });

    test('drawn rounds make no score changes and repeat starter', () {
      final state = apply(
        currentStarter: PlayerSeat.north,
        scores: {
          PlayerSeat.south: 4,
          PlayerSeat.east: 5,
          PlayerSeat.north: 6,
          PlayerSeat.west: 7,
        },
        result: const RoundProgressResult(
          type: RoundOutcomeType.draw,
          remainingCardCounts: {},
        ),
      );

      expect(state.scores[PlayerSeat.south], 4);
      expect(state.scores[PlayerSeat.east], 5);
      expect(state.scores[PlayerSeat.north], 6);
      expect(state.scores[PlayerSeat.west], 7);
      expect(state.nextStarter, PlayerSeat.north);
    });

    test('a draw whose starter is eliminated hands the deal to a survivor', () {
      // The starter (south) is already at the elimination threshold when the
      // round is concluded as a draw (e.g. a mid-round penalty crossed 31
      // before the round ended). A draw repeats the starter, but an eliminated
      // seat cannot deal — the next surviving seat anti-clockwise must, so that
      // dealing the next round never trips "Starter must be an active seat".
      final state = apply(
        currentStarter: PlayerSeat.south,
        scores: {
          PlayerSeat.south: 34,
          PlayerSeat.east: 0,
          PlayerSeat.north: 0,
          PlayerSeat.west: 0,
        },
        result: const RoundProgressResult(
          type: RoundOutcomeType.draw,
          remainingCardCounts: {},
        ),
      );

      expect(state.activeSeats, isNot(contains(PlayerSeat.south)));
      expect(state.activeSeats, contains(state.nextStarter));
      expect(state.nextStarter, PlayerSeat.east);
      expect(state.matchWinner, isNull);
    });

    test('normal finish rejects a winner outside active seats', () {
      expect(
        () => ClassicHareegMatchProgressionRules.applyRoundResult(
          scores: {PlayerSeat.south: 0, PlayerSeat.east: 0},
          activeSeats: const [PlayerSeat.south, PlayerSeat.east],
          currentStarter: PlayerSeat.south,
          result: const RoundProgressResult(
            type: RoundOutcomeType.normalFinish,
            winner: PlayerSeat.north,
            remainingCardCounts: {},
          ),
        ),
        throwsArgumentError,
      );
    });

    test('Fifty finish rejects invalid discarders', () {
      expect(
        () => ClassicHareegMatchProgressionRules.applyRoundResult(
          scores: {PlayerSeat.south: 0, PlayerSeat.east: 0},
          activeSeats: const [PlayerSeat.south, PlayerSeat.east],
          currentStarter: PlayerSeat.south,
          result: const RoundProgressResult(
            type: RoundOutcomeType.fiftyFinish,
            winner: PlayerSeat.south,
            fiftyDiscarder: PlayerSeat.south,
            remainingCardCounts: {},
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => ClassicHareegMatchProgressionRules.applyRoundResult(
          scores: {PlayerSeat.south: 0, PlayerSeat.east: 0},
          activeSeats: const [PlayerSeat.south, PlayerSeat.east],
          currentStarter: PlayerSeat.south,
          result: const RoundProgressResult(
            type: RoundOutcomeType.fiftyFinish,
            winner: PlayerSeat.south,
            fiftyDiscarder: PlayerSeat.north,
            remainingCardCounts: {},
          ),
        ),
        throwsArgumentError,
      );
    });

    test('eliminates players at 31 and preserves relative order', () {
      final state = apply(
        scores: {
          PlayerSeat.south: 30,
          PlayerSeat.east: 2,
          PlayerSeat.north: 3,
          PlayerSeat.west: 4,
        },
        result: const RoundProgressResult(
          type: RoundOutcomeType.normalFinish,
          winner: PlayerSeat.east,
          remainingCardCounts: {
            PlayerSeat.south: 2,
            PlayerSeat.east: 0,
            PlayerSeat.north: 5,
            PlayerSeat.west: 6,
          },
        ),
      );

      expect(state.scores[PlayerSeat.south], 32);
      expect(state.activeSeats, [
        PlayerSeat.east,
        PlayerSeat.north,
        PlayerSeat.west,
      ]);
    });

    test('last remaining player wins match', () {
      final state = apply(
        scores: {
          PlayerSeat.south: 30,
          PlayerSeat.east: 2,
          PlayerSeat.north: 30,
          PlayerSeat.west: 30,
        },
        result: const RoundProgressResult(
          type: RoundOutcomeType.normalFinish,
          winner: PlayerSeat.east,
          remainingCardCounts: {
            PlayerSeat.south: 2,
            PlayerSeat.east: 0,
            PlayerSeat.north: 2,
            PlayerSeat.west: 2,
          },
        ),
      );

      expect(state.activeSeats, [PlayerSeat.east]);
      expect(state.matchWinner, PlayerSeat.east);
    });
  });
}

MatchProgressState apply({
  Map<PlayerSeat, int>? scores,
  PlayerSeat currentStarter = PlayerSeat.south,
  required RoundProgressResult result,
}) {
  return ClassicHareegMatchProgressionRules.applyRoundResult(
    scores:
        scores ??
        {
          PlayerSeat.south: 0,
          PlayerSeat.east: 0,
          PlayerSeat.north: 0,
          PlayerSeat.west: 0,
        },
    activeSeats: const [
      PlayerSeat.south,
      PlayerSeat.east,
      PlayerSeat.north,
      PlayerSeat.west,
    ],
    currentStarter: currentStarter,
    result: result,
  );
}
