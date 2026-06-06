import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/match_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

import '../../support/test_fixtures.dart';

void main() {
  group('LocalMatchRepository', () {
    test('saves and restores an active match snapshot', () async {
      final store = MemoryKeyValueStore();
      final repository = LocalMatchRepository(store: store);
      final round = ClassicHareegRound.deal(
        setup: ClassicHareegSetup.defaults(),
        seed: 7,
      );
      final snapshot = ClassicHareegMatchSnapshot(
        setup: round.setup,
        hands: round.hands,
        stock: round.stock,
        discardPile: round.discardPile,
        tableMelds: {
          PlayerSeat.south: [
            PlacedMeld.fromCards([
              _card(CardRank.nine, CardSuit.clubs),
              _card(CardRank.nine, CardSuit.diamonds),
              _card(CardRank.nine, CardSuit.hearts),
            ]),
          ],
        },
        starter: round.starter,
        currentSeat: PlayerSeat.east,
        turnPhase: TurnPhase.draw,
        pendingDiscard: round.handFor(PlayerSeat.south).first,
        fiftyWindowOpenedAt: DateTime.utc(2026, 5, 18, 10),
        savedAt: DateTime.utc(2026, 5, 18),
      );

      await repository.saveActiveMatch(snapshot);

      final restored = await repository.loadActiveMatch();
      expect(restored, isNotNull);
      expect(restored!.setup.deckCount, snapshot.setup.deckCount);
      expect(
        restored.hands[PlayerSeat.south]!.first.id,
        snapshot.hands[PlayerSeat.south]!.first.id,
      );
      expect(restored.stock.length, snapshot.stock.length);
      expect(restored.currentSeat, PlayerSeat.east);
      expect(restored.turnPhase, TurnPhase.draw);
      expect(restored.pendingDiscard!.id, snapshot.pendingDiscard!.id);
      expect(restored.removedSeats, isEmpty);
      expect(restored.fiftyWindowOpenedAt, snapshot.fiftyWindowOpenedAt);
      expect(restored.tableMelds[PlayerSeat.south], hasLength(1));
      expect(
        restored.tableMelds[PlayerSeat.south]!.single.cards.map(
          (card) => card.label,
        ),
        ['9D', '9C', '9H'],
      );
    });

    test('abandons an active match snapshot', () async {
      final store = MemoryKeyValueStore();
      final repository = LocalMatchRepository(store: store);
      final round = ClassicHareegRound.deal(
        setup: ClassicHareegSetup.defaults(),
        seed: 2,
      );

      await repository.saveActiveMatch(
        ClassicHareegMatchSnapshot(
          setup: round.setup,
          hands: round.hands,
          stock: round.stock,
          discardPile: round.discardPile,
          starter: round.starter,
          currentSeat: round.currentSeat,
          turnPhase: round.turnPhase,
          savedAt: DateTime.utc(2026, 5, 18),
        ),
      );
      await repository.abandonActiveMatch();

      expect(await repository.loadActiveMatch(), isNull);
    });

    test('invalid saved match is cleared and ignored', () async {
      final store = MemoryKeyValueStore()
        ..values['active_match.v1'] = '{"version":99}';
      final repository = LocalMatchRepository(store: store);

      final restored = await repository.loadActiveMatch();

      expect(restored, isNull);
      expect(store.values.containsKey('active_match.v1'), isFalse);
    });
  });
}

HareegCard _card(CardRank rank, CardSuit suit) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: 50);
}
