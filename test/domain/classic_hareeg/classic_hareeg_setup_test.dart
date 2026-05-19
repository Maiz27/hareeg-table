import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';

void main() {
  group('ClassicHareegSetup', () {
    test('fromJson falls back for invalid numeric fields', () {
      final setup = ClassicHareegSetup.fromJson({
        'openingRequirement': 0,
        'deckCount': -1,
        'jokerCount': -2,
        'fiftyTimerSeconds': 0,
      });
      final defaults = ClassicHareegSetup.defaults();

      expect(setup.openingRequirement, defaults.openingRequirement);
      expect(setup.deckCount, defaults.deckCount);
      expect(setup.jokerCount, defaults.jokerCount);
      expect(setup.fiftyTimerSeconds, defaults.fiftyTimerSeconds);
    });

    test('fromJson rejects fractional numeric fields', () {
      final setup = ClassicHareegSetup.fromJson({
        'openingRequirement': 75.5,
        'deckCount': 3.25,
        'jokerCount': 1.5,
        'fiftyTimerSeconds': 6.75,
      });
      final defaults = ClassicHareegSetup.defaults();

      expect(setup.openingRequirement, defaults.openingRequirement);
      expect(setup.deckCount, defaults.deckCount);
      expect(setup.jokerCount, defaults.jokerCount);
      expect(setup.fiftyTimerSeconds, defaults.fiftyTimerSeconds);
    });

    test('fromJson allows zero jokers', () {
      final setup = ClassicHareegSetup.fromJson({
        'openingRequirement': 75,
        'deckCount': 3,
        'jokerCount': 0,
        'fiftyTimerSeconds': 6,
      });

      expect(setup.openingRequirement, 75);
      expect(setup.deckCount, 3);
      expect(setup.jokerCount, 0);
      expect(setup.fiftyTimerSeconds, 6);
    });
  });
}
