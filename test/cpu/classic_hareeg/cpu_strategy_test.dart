import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_strategy.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';

void main() {
  test('CPU turn snapshots expose an immutable copy of legal actions', () {
    final actionIds = ['draw-stock'];
    final snapshot = CpuTurnSnapshot(
      seat: PlayerSeat.east,
      legalActionIds: actionIds,
    );

    actionIds.add('discard:7-hearts');

    expect(snapshot.legalActionIds, ['draw-stock']);
    expect(
      () => snapshot.legalActionIds.add('discard:7-hearts'),
      throwsUnsupportedError,
    );
  });

  test('CPU chooses only legal move intents from the snapshot', () {
    const strategy = ClassicHareegCpuStrategy();
    final intent = strategy.chooseMove(
      CpuTurnSnapshot(
        seat: PlayerSeat.east,
        legalActionIds: ['draw-stock', 'take-discard'],
      ),
    );

    expect(['draw-stock', 'take-discard'], contains(intent.actionId));
  });

  test('CPU prioritizes finish, opening, covers, draw, then pickup', () {
    const strategy = ClassicHareegCpuStrategy();

    expect(
      strategy
          .chooseMove(
            CpuTurnSnapshot(
              seat: PlayerSeat.east,
              legalActionIds: ['draw-stock', 'finish-round'],
            ),
          )
          .actionId,
      'finish-round',
    );
    expect(
      strategy
          .chooseMove(
            CpuTurnSnapshot(
              seat: PlayerSeat.east,
              legalActionIds: ['draw-stock', 'open'],
            ),
          )
          .actionId,
      'open',
    );
    expect(
      strategy
          .chooseMove(
            CpuTurnSnapshot(
              seat: PlayerSeat.east,
              legalActionIds: ['draw-stock', 'place-cover'],
            ),
          )
          .actionId,
      'place-cover',
    );
    expect(
      strategy
          .chooseMove(
            CpuTurnSnapshot(
              seat: PlayerSeat.east,
              legalActionIds: ['draw-stock', 'take-discard'],
            ),
          )
          .actionId,
      'draw-stock',
    );
  });

  test('CPU returns pending discard until table play is implemented', () {
    const strategy = ClassicHareegCpuStrategy();

    final intent = strategy.chooseMove(
      CpuTurnSnapshot(
        seat: PlayerSeat.east,
        legalActionIds: ['use-pending-discard', 'return-pending-discard'],
      ),
    );

    expect(intent.actionId, 'return-pending-discard');
  });

  test(
    'CPU avoids blocked cover and joker discards when alternatives exist',
    () {
      const strategy = ClassicHareegCpuStrategy();
      final intent = strategy.chooseMove(
        CpuTurnSnapshot(
          seat: PlayerSeat.east,
          legalActionIds: [
            'discard-blocked-cover:9-clubs',
            'discard-joker:0',
            'discard:7-hearts',
          ],
        ),
      );

      expect(intent.actionId, 'discard:7-hearts');
    },
  );

  test(
    'CPU difficulty profiles vary Fifty reaction timing and miss chance',
    () {
      final beginner = CpuDifficultyProfile.forDifficulty(
        CpuDifficulty.beginner,
      );
      final expert = CpuDifficultyProfile.forDifficulty(CpuDifficulty.expert);

      expect(
        beginner.fiftyReactionMillis,
        greaterThan(expert.fiftyReactionMillis),
      );
      expect(beginner.fiftyMissChance, greaterThan(expert.fiftyMissChance));
    },
  );
}
