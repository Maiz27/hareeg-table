import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_strategy.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';

void main() {
  test('CPU turn snapshots expose an immutable copy of legal actions', () {
    final actionIds = ['draw-stock'];
    final snapshot = CpuTurnSnapshot(
      seat: PlayerSeat.east,
      legalActionIds: actionIds,
    );

    actionIds.add('discard-7-hearts');

    expect(snapshot.legalActionIds, ['draw-stock']);
    expect(
      () => snapshot.legalActionIds.add('discard-7-hearts'),
      throwsUnsupportedError,
    );
  });
}
