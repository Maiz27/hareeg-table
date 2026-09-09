import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_fifty_counters.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';

void main() {
  group('MatchFiftyCounters', () {
    test('starts empty for every seat', () {
      final counters = MatchFiftyCounters.empty();

      for (final seat in PlayerSeat.values) {
        expect(counters.attemptsFor(seat), 0);
        expect(counters.successesFor(seat), 0);
      }
    });

    test('records attempts and successes per seat independently', () {
      final counters = MatchFiftyCounters.empty()
          .withAttempt(PlayerSeat.south)
          .withAttempt(PlayerSeat.south)
          .withSuccess(PlayerSeat.south)
          .withAttempt(PlayerSeat.east);

      expect(counters.attemptsFor(PlayerSeat.south), 2);
      expect(counters.successesFor(PlayerSeat.south), 1);
      expect(counters.attemptsFor(PlayerSeat.east), 1);
      expect(counters.successesFor(PlayerSeat.east), 0);
      expect(counters.attemptsFor(PlayerSeat.north), 0);
    });

    test('refuses a success with no matching attempt', () {
      expect(
        () => MatchFiftyCounters.empty().withSuccess(PlayerSeat.south),
        throwsStateError,
      );
    });

    test('refuses more successes than attempts', () {
      final counters = MatchFiftyCounters.empty()
          .withAttempt(PlayerSeat.south)
          .withSuccess(PlayerSeat.south);

      expect(() => counters.withSuccess(PlayerSeat.south), throwsStateError);
    });

    test('rejects a negative count on construction', () {
      expect(
        () => MatchFiftyCounters(attempts: const {PlayerSeat.south: -1}),
        throwsArgumentError,
      );
    });

    test('rejects successes exceeding attempts on construction', () {
      expect(
        () => MatchFiftyCounters(
          attempts: const {PlayerSeat.south: 1},
          successes: const {PlayerSeat.south: 2},
        ),
        throwsArgumentError,
      );
    });

    test('round-trips through JSON', () {
      final counters = MatchFiftyCounters.empty()
          .withAttempt(PlayerSeat.south)
          .withSuccess(PlayerSeat.south)
          .withAttempt(PlayerSeat.west);

      final restored = MatchFiftyCounters.fromJson(counters.toJson());

      expect(restored.attemptsFor(PlayerSeat.south), 1);
      expect(restored.successesFor(PlayerSeat.south), 1);
      expect(restored.attemptsFor(PlayerSeat.west), 1);
      expect(restored.successesFor(PlayerSeat.west), 0);
    });

    test('rejects invalid stored values rather than clamping them', () {
      // A tally with more successes than attempts was miscounted. Quietly
      // repairing it here would hide the counting bug that produced it.
      expect(
        () => MatchFiftyCounters.fromJson(const {
          'version': 1,
          'attempts': {'south': 1},
          'successes': {'south': 5},
        }),
        throwsFormatException,
      );

      expect(
        () => MatchFiftyCounters.fromJson(const {
          'version': 1,
          'attempts': {'south': -3},
          'successes': <String, Object?>{},
        }),
        throwsFormatException,
      );
    });

    test('rejects an unknown seat name', () {
      expect(
        () => MatchFiftyCounters.fromJson(const {
          'version': 1,
          'attempts': {'northwest': 1},
          'successes': <String, Object?>{},
        }),
        throwsFormatException,
      );
    });

    test('rejects an unsupported schema version', () {
      expect(
        () => MatchFiftyCounters.fromJson(const {
          'version': 99,
          'attempts': <String, Object?>{},
          'successes': <String, Object?>{},
        }),
        throwsFormatException,
      );
    });
  });
}
