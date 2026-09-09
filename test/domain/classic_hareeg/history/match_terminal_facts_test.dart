import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_terminal_facts.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';

void main() {
  MatchTerminalFacts buildFacts({DateTime? completedAt}) {
    return MatchTerminalFacts(
      completedAt: completedAt ?? DateTime.utc(2026, 8, 22, 9, 30),
      winner: PlayerSeat.south,
      finalScores: const {
        PlayerSeat.south: 12,
        PlayerSeat.east: 31,
        PlayerSeat.north: 28,
        PlayerSeat.west: 33,
      },
      roundCount: 7,
      eliminationRounds: const {
        PlayerSeat.west: 3,
        PlayerSeat.east: 5,
        PlayerSeat.north: 6,
      },
      seats: PlayerSeat.values,
    );
  }

  group('MatchTerminalFacts', () {
    test(
      'legacy eliminated seats stay unknown without blocking real completion',
      () {
        final facts = MatchTerminalFacts(
          completedAt: DateTime.utc(2026),
          winner: PlayerSeat.west,
          finalScores: {
            for (final seat in PlayerSeat.values)
              seat: seat == PlayerSeat.west ? 0 : 100,
          },
          roundCount: 17,
          eliminationRounds: const {PlayerSeat.south: 17},
          unknownEliminationSeats: const {PlayerSeat.north, PlayerSeat.east},
          seats: PlayerSeat.values,
        );
        final restored = MatchTerminalFacts.fromJson(facts.toJson());
        expect(restored.unknownEliminationSeats, {
          PlayerSeat.north,
          PlayerSeat.east,
        });
        expect(restored.eliminationRounds, {PlayerSeat.south: 17});
        expect(restored.standing.placementOf(PlayerSeat.south), 2);
        expect(restored.standing.placementOf(PlayerSeat.north), isNull);
        expect(restored.standing.placementOf(PlayerSeat.east), isNull);
      },
    );
    test('round-trips through JSON', () {
      final restored = MatchTerminalFacts.fromJson(buildFacts().toJson());

      expect(restored.completedAt, DateTime.utc(2026, 8, 22, 9, 30));
      expect(restored.winner, PlayerSeat.south);
      expect(restored.finalScores[PlayerSeat.east], 31);
      expect(restored.roundCount, 7);
      expect(restored.eliminationRounds[PlayerSeat.north], 6);
      expect(restored.seats, PlayerSeat.values);
    });

    test('normalises the completion time to UTC', () {
      final local = DateTime(2026, 8, 22, 9, 30);

      final facts = buildFacts(completedAt: local);

      expect(facts.completedAt.isUtc, isTrue);
      expect(facts.completedAt, local.toUtc());
    });

    test('derives standing from the recorded facts', () {
      final standing = buildFacts().standing;

      expect(standing.winner, PlayerSeat.south);
      expect(standing.placementOf(PlayerSeat.south), 1);
      // north went out last of the eliminated seats, so it places above east.
      expect(standing.placementOf(PlayerSeat.north), 2);
      expect(standing.placementOf(PlayerSeat.east), 3);
      expect(standing.placementOf(PlayerSeat.west), 4);
    });

    test('the recorded facts survive a much later decode unchanged', () {
      // This is the whole point of capturing them at match-over: recovery may
      // run hours later, and it must republish the original completion time
      // and winner rather than anything derived from when it happened to run.
      final original = buildFacts();

      final restored = MatchTerminalFacts.fromJson(original.toJson());

      expect(restored.completedAt, original.completedAt);
      expect(restored.winner, original.winner);
      expect(restored.roundCount, original.roundCount);
    });

    group('terminal truth', () {
      test('rejects a trace that left more than one seat playing', () {
        // The shape a capped or abandoned trace takes: plausible scores, a
        // "winner" that is merely whoever had not been knocked out yet, and a
        // match that never actually finished.
        expect(
          () => MatchTerminalFacts(
            completedAt: DateTime.utc(2026, 8, 22, 10),
            winner: PlayerSeat.south,
            finalScores: const {
              PlayerSeat.south: 4,
              PlayerSeat.east: 9,
              PlayerSeat.north: 12,
              PlayerSeat.west: 31,
            },
            roundCount: 3,
            // Only one seat out; south, east, and north are all still playing.
            eliminationRounds: const {PlayerSeat.west: 3},
            seats: PlayerSeat.values,
          ),
          throwsArgumentError,
        );
      });

      test('rejects a winner who was also eliminated', () {
        expect(
          () => MatchTerminalFacts(
            completedAt: DateTime.utc(2026, 8, 22, 10),
            winner: PlayerSeat.south,
            finalScores: const {
              PlayerSeat.south: 31,
              PlayerSeat.east: 9,
              PlayerSeat.north: 12,
              PlayerSeat.west: 31,
            },
            roundCount: 3,
            eliminationRounds: const {
              PlayerSeat.south: 3,
              PlayerSeat.north: 2,
              PlayerSeat.west: 1,
            },
            seats: PlayerSeat.values,
          ),
          throwsArgumentError,
        );
      });

      test('rejects incomplete final scores', () {
        expect(
          () => MatchTerminalFacts(
            completedAt: DateTime.utc(2026, 8, 22, 10),
            winner: PlayerSeat.south,
            finalScores: const {PlayerSeat.south: 4},
            roundCount: 3,
            eliminationRounds: const {
              PlayerSeat.east: 1,
              PlayerSeat.north: 2,
              PlayerSeat.west: 3,
            },
            seats: PlayerSeat.values,
          ),
          throwsArgumentError,
        );
      });

      test('rejects an elimination round outside the match', () {
        expect(
          () => MatchTerminalFacts(
            completedAt: DateTime.utc(2026, 8, 22, 10),
            winner: PlayerSeat.south,
            finalScores: const {
              PlayerSeat.south: 4,
              PlayerSeat.east: 31,
              PlayerSeat.north: 32,
              PlayerSeat.west: 33,
            },
            roundCount: 3,
            eliminationRounds: const {
              PlayerSeat.east: 1,
              PlayerSeat.north: 2,
              PlayerSeat.west: 9,
            },
            seats: PlayerSeat.values,
          ),
          throwsArgumentError,
        );
      });

      test('rejects a zero round count', () {
        expect(
          () => MatchTerminalFacts(
            completedAt: DateTime.utc(2026, 8, 22, 10),
            winner: PlayerSeat.south,
            finalScores: const {
              PlayerSeat.south: 0,
              PlayerSeat.east: 0,
              PlayerSeat.north: 0,
              PlayerSeat.west: 0,
            },
            roundCount: 0,
            eliminationRounds: const {},
            seats: PlayerSeat.values,
          ),
          throwsArgumentError,
        );
      });

      test('an unfinished trace cannot decode either', () {
        final json = buildFacts().toJson()..['eliminationRounds'] = {'west': 3};

        expect(() => MatchTerminalFacts.fromJson(json), throwsFormatException);
      });
    });

    test('rejects an unsupported schema version', () {
      final json = buildFacts().toJson()..['version'] = 99;

      expect(() => MatchTerminalFacts.fromJson(json), throwsFormatException);
    });

    test('rejects a malformed timestamp', () {
      final json = buildFacts().toJson()..['completedAt'] = 'not-a-date';

      expect(() => MatchTerminalFacts.fromJson(json), throwsFormatException);
    });

    test('rejects an unknown seat name', () {
      final json = buildFacts().toJson()..['winner'] = 'northwest';

      expect(() => MatchTerminalFacts.fromJson(json), throwsFormatException);
    });
  });
}
