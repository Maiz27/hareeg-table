import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/match_repository.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';

void main() {
  group('LocalMatchRepository', () {
    test('saves and restores an active match snapshot', () async {
      final store = _MemoryStore();
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
        starter: round.starter,
        currentSeat: PlayerSeat.east,
        turnPhase: TurnPhase.draw,
        pendingDiscard: round.handFor(PlayerSeat.south).first,
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
    });

    test('abandons an active match snapshot', () async {
      final store = _MemoryStore();
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
      final store = _MemoryStore()
        ..values['active_match.v1'] = '{"version":99}';
      final repository = LocalMatchRepository(store: store);

      final restored = await repository.loadActiveMatch();

      expect(restored, isNull);
      expect(store.values.containsKey('active_match.v1'), isFalse);
    });
  });
}

class _MemoryStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> loadString(String key) async => values[key];

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> saveString(String key, String value) async {
    values[key] = value;
  }
}
