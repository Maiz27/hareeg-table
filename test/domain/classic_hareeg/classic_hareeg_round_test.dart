import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';

void main() {
  test('deals four seats with starter counts and stock', () {
    final round = ClassicHareegRound.deal(
      setup: ClassicHareegSetup.defaults(),
      seed: 7,
    );

    expect(round.starter, PlayerSeat.south);
    expect(round.currentSeat, PlayerSeat.south);
    expect(round.turnPhase, TurnPhase.action);
    expect(round.cardCountFor(PlayerSeat.south), 15);
    expect(round.cardCountFor(PlayerSeat.east), 14);
    expect(round.cardCountFor(PlayerSeat.north), 14);
    expect(round.cardCountFor(PlayerSeat.west), 14);
    expect(round.stock.length, 49);
  });

  test('turn order advances anti-clockwise from the starter', () {
    final round = ClassicHareegRound.deal(
      setup: ClassicHareegSetup.defaults(),
      seed: 7,
    );

    expect(round.turnOrder, [
      PlayerSeat.south,
      PlayerSeat.east,
      PlayerSeat.north,
      PlayerSeat.west,
    ]);
  });

  test('random starter is deterministic when seeded', () {
    final round = ClassicHareegRound.deal(
      setup: ClassicHareegSetup.defaults().copyWith(
        starterMode: StarterMode.random,
      ),
      seed: 2,
    );

    expect(round.cardCountFor(round.starter), 15);
    for (final seat in PlayerSeat.values.where(
      (seat) => seat != round.starter,
    )) {
      expect(round.cardCountFor(seat), 14);
    }
  });
}
