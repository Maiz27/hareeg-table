import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_standing.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';

void main() {
  test('standing JSON requires at least one entry', () {
    expect(
      () => MatchStanding.fromJson({
        'version': matchStandingVersion,
        'entries': <Object>[],
      }),
      throwsFormatException,
    );
  });
  group('MatchStanding.fromMatchFacts', () {
    test('ranks a four-seat clean finish by survival, not by score', () {
      final standing = MatchStanding.fromMatchFacts(
        winner: PlayerSeat.south,
        finalScores: const {
          PlayerSeat.south: 12,
          PlayerSeat.east: 31,
          PlayerSeat.north: 33,
          PlayerSeat.west: 35,
        },
        eliminationRounds: const {
          PlayerSeat.west: 2,
          PlayerSeat.north: 4,
          PlayerSeat.east: 6,
        },
        seats: PlayerSeat.values,
      );

      expect(
        [for (final entry in standing.entries) entry.seat],
        [PlayerSeat.south, PlayerSeat.east, PlayerSeat.north, PlayerSeat.west],
      );
      expect([for (final entry in standing.entries) entry.rank], [1, 2, 3, 4]);
      expect(standing.placementOf(PlayerSeat.south), 1);
      expect(standing.entries.first.eliminatedInRound, isNull);
    });

    test('a same-round double elimination breaks on lower final score', () {
      final standing = MatchStanding.fromMatchFacts(
        winner: PlayerSeat.north,
        finalScores: const {
          PlayerSeat.north: 8,
          PlayerSeat.south: 31,
          PlayerSeat.east: 40,
          PlayerSeat.west: 33,
        },
        eliminationRounds: const {
          PlayerSeat.west: 3,
          // Both go out in round 5; south's lower score places it above east.
          PlayerSeat.south: 5,
          PlayerSeat.east: 5,
        },
        seats: PlayerSeat.values,
      );

      expect(
        [for (final entry in standing.entries) entry.seat],
        [PlayerSeat.north, PlayerSeat.south, PlayerSeat.east, PlayerSeat.west],
      );
    });

    test('equal round and equal score fall back to stable seat order', () {
      final standing = MatchStanding.fromMatchFacts(
        winner: PlayerSeat.west,
        finalScores: const {
          PlayerSeat.west: 5,
          PlayerSeat.south: 31,
          PlayerSeat.east: 31,
          PlayerSeat.north: 31,
        },
        eliminationRounds: const {
          PlayerSeat.south: 4,
          PlayerSeat.east: 4,
          PlayerSeat.north: 4,
        },
        seats: PlayerSeat.values,
      );

      // south, east, north is declared enum order — the tie must resolve the
      // same way every run rather than however the map iterated.
      expect(
        [for (final entry in standing.entries) entry.seat],
        [PlayerSeat.west, PlayerSeat.south, PlayerSeat.east, PlayerSeat.north],
      );
    });

    test('handles a two-seat match', () {
      final standing = MatchStanding.fromMatchFacts(
        winner: PlayerSeat.east,
        finalScores: const {PlayerSeat.east: 10, PlayerSeat.south: 31},
        eliminationRounds: const {PlayerSeat.south: 3},
        seats: const [PlayerSeat.south, PlayerSeat.east],
      );

      expect(standing.entries, hasLength(2));
      expect(standing.placementOf(PlayerSeat.east), 1);
      expect(standing.placementOf(PlayerSeat.south), 2);
      expect(standing.placementOf(PlayerSeat.north), isNull);
    });

    test('every seat is ranked exactly once with no gaps', () {
      final standing = MatchStanding.fromMatchFacts(
        winner: PlayerSeat.south,
        finalScores: const {},
        eliminationRounds: const {PlayerSeat.east: 2},
        seats: PlayerSeat.values,
      );

      final ranks = [for (final entry in standing.entries) entry.rank];
      expect(ranks, [1, 2, 3, 4]);
      expect({
        for (final entry in standing.entries) entry.seat,
      }, PlayerSeat.values.toSet());
    });

    test('rejects a winner that did not play', () {
      expect(
        () => MatchStanding.fromMatchFacts(
          winner: PlayerSeat.north,
          finalScores: const {},
          eliminationRounds: const {},
          seats: const [PlayerSeat.south, PlayerSeat.east],
        ),
        throwsArgumentError,
      );
    });

    test('round-trips through JSON', () {
      final standing = MatchStanding.fromMatchFacts(
        winner: PlayerSeat.south,
        finalScores: const {PlayerSeat.south: 4, PlayerSeat.east: 31},
        eliminationRounds: const {PlayerSeat.east: 2},
        seats: const [PlayerSeat.south, PlayerSeat.east],
      );

      final restored = MatchStanding.fromJson(standing.toJson());

      expect(restored.winner, PlayerSeat.south);
      expect(restored.placementOf(PlayerSeat.east), 2);
      expect(restored.entries.last.eliminatedInRound, 2);
    });

    test('rejects an unsupported schema version', () {
      expect(
        () => MatchStanding.fromJson(const {'version': 99, 'entries': []}),
        throwsFormatException,
      );
    });
  });
}
