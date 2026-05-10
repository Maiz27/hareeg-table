import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/classic_hareeg_rules.dart';

void main() {
  test('default Classic Hareeg rules match the documented baseline', () {
    final rules = ClassicHareegRules.defaults();

    expect(rules.seatCount, 4);
    expect(rules.cardsPerPlayer, 14);
    expect(rules.starterCardCount, 15);
    expect(rules.openingRequirement, 51);
    expect(rules.fiftyClaimSeconds, 4);
    expect(rules.eliminationScore, 31);
  });

  test('player seats advance anti-clockwise around a four-seat table', () {
    expect(PlayerSeat.south.nextAntiClockwise, PlayerSeat.east);
    expect(PlayerSeat.east.nextAntiClockwise, PlayerSeat.north);
    expect(PlayerSeat.north.nextAntiClockwise, PlayerSeat.west);
    expect(PlayerSeat.west.nextAntiClockwise, PlayerSeat.south);
  });
}
