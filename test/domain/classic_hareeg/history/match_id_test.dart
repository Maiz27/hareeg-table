import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/replay_file_store.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_id.dart';

void main() {
  group('match ids', () {
    test('a minted id is usable as a replay file key', () {
      // The domain does not import the storage layer to state this rule, so
      // this test is what stops the two drifting apart.
      final minter = MatchIdMinter(
        now: () => DateTime.utc(2026, 8, 22, 12),
        random: Random(7),
      );

      for (var i = 0; i < 50; i++) {
        final id = minter.mint(isTaken: (_) => false);
        expect(isValidMatchId(id), isTrue, reason: id);
        expect(isValidReplayFileKey(id), isTrue, reason: id);
      }
    });

    test('rejects malformed ids', () {
      for (final bad in const [
        '',
        'match-1',
        'm--aaaaaaaa',
        'm-abc-AAAAAAAA',
        'm-abc-aaaaaaa',
        'm-abc-aaaaaaaaa',
        'm-abc',
        '../escape',
      ]) {
        expect(isValidMatchId(bad), isFalse, reason: bad);
      }
    });

    test('two ids minted in the same millisecond still differ', () {
      // A clock reading alone cannot separate them: the random suffix is what
      // does the work.
      final minter = MatchIdMinter(
        now: () => DateTime.utc(2026, 8, 22, 12),
        random: Random(11),
      );

      final ids = {
        for (var i = 0; i < 200; i++) minter.mint(isTaken: (_) => false),
      };

      expect(ids, hasLength(200));
    });

    test('mints again rather than reusing a taken id', () {
      final minter = MatchIdMinter(
        now: () => DateTime.utc(2026, 8, 22, 12),
        random: Random(3),
      );
      final first = MatchIdMinter(
        now: () => DateTime.utc(2026, 8, 22, 12),
        random: Random(3),
      ).mint(isTaken: (_) => false);

      final second = minter.mint(isTaken: (candidate) => candidate == first);

      expect(second, isNot(first));
      expect(isValidMatchId(second), isTrue);
    });

    test('gives up rather than looping forever when everything is taken', () {
      final minter = MatchIdMinter(
        now: () => DateTime.utc(2026, 8, 22, 12),
        random: Random(5),
      );

      expect(
        () => minter.mint(isTaken: (_) => true),
        throwsStateError,
      );
    });
  });
}
