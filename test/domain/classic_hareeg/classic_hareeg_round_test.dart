import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/classic_hareeg_rules.dart';

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

  test('records explicit and generated seeds for replay', () {
    final setup = ClassicHareegSetup.defaults();
    final explicit = ClassicHareegRound.deal(setup: setup, seed: 7);
    final generated = ClassicHareegRound.deal(setup: setup);
    final replay = ClassicHareegRound.deal(setup: setup, seed: generated.seed);

    expect(explicit.seed, 7);
    expect(generated.seed, inInclusiveRange(0, 0x7FFFFFFE));
    expect(replay.handFor(PlayerSeat.south).map((card) => card.id), [
      for (final card in generated.handFor(PlayerSeat.south)) card.id,
    ]);
    expect(replay.stock.map((card) => card.id), [
      for (final card in generated.stock) card.id,
    ]);
  });

  test('single deck with no jokers cannot deal four seats', () {
    // The setup picker only exposes 2-4 decks, but the round factory must
    // still refuse to deal an under-sized deck. 52 cards is one short of the
    // 57 required (14 * 4 + 1).
    expect(
      () => ClassicHareegRound.deal(
        setup: ClassicHareegSetup.defaults().copyWith(
          deckCount: 1,
          jokerCount: 0,
        ),
      ),
      throwsStateError,
    );
  });

  test('zero decks cannot deal four seats', () {
    expect(
      () => ClassicHareegRound.deal(
        setup: ClassicHareegSetup.defaults().copyWith(
          deckCount: 0,
          jokerCount: 0,
        ),
      ),
      throwsStateError,
    );
  });

  test('deck-size validation uses the active rules', () {
    const largerDealRules = ClassicHareegRules(
      seatCount: 4,
      cardsPerPlayer: 30,
      starterCardCount: 31,
      openingRequirement: 51,
      fiftyClaimSeconds: 4,
      eliminationScore: 31,
    );

    expect(
      () => ClassicHareegRound.deal(
        setup: ClassicHareegSetup.defaults(),
        rules: largerDealRules,
      ),
      throwsStateError,
    );
  });
}
