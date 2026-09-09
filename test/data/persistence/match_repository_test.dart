import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/match_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

import '../../support/test_fixtures.dart';

void main() {
  group('LocalMatchRepository', () {
    test(
      'malformed existing match id is rejected without overwriting it',
      () async {
        final raw = jsonEncode({
          'matchId': 42,
          'snapshot': <String, Object?>{},
        });
        final store = MemoryKeyValueStore()..values['active_match.v1'] = raw;
        final repository = LocalMatchRepository(
          store: store,
          mintMatchId: () async => testMatchId,
        );
        await expectLater(
          repository.saveActiveMatch(checkpointForSnapshot(_legacySnapshot())),
          throwsFormatException,
        );
        expect(store.values['active_match.v1'], raw);
      },
    );

    test('legacy missing match id does not block a valid save', () async {
      final store = MemoryKeyValueStore()
        ..values['active_match.v1'] = jsonEncode(_legacySnapshot().toJson());
      final repository = LocalMatchRepository(
        store: store,
        mintMatchId: () async => testMatchId,
      );
      await repository.saveActiveMatch(
        checkpointForSnapshot(_legacySnapshot()),
      );
      expect(await repository.loadActiveMatch(), isA<ActiveMatchLoaded>());
    });
    test('saves and restores an active match snapshot', () async {
      final store = MemoryKeyValueStore();
      final repository = LocalMatchRepository(
        store: store,
        mintMatchId: () async => testMatchId,
      );
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

      await repository.saveActiveMatch(checkpointForSnapshot(snapshot));

      final outcome = await repository.loadActiveMatch();
      expect(outcome, isA<ActiveMatchLoaded>());
      final restored = (outcome as ActiveMatchLoaded).checkpoint.snapshot;
      expect(restored.setup.deckCount, snapshot.setup.deckCount);
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
      final repository = LocalMatchRepository(
        store: store,
        mintMatchId: () async => testMatchId,
      );
      final round = ClassicHareegRound.deal(
        setup: ClassicHareegSetup.defaults(),
        seed: 2,
      );

      await repository.saveActiveMatch(
        checkpointForSnapshot(
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
        ),
      );
      await repository.abandonActiveMatch();

      expect(await repository.loadActiveMatch(), isA<ActiveMatchAbsent>());
    });

    test(
      'a checkpoint with an explicit-null nested record is preserved',
      () async {
        // Present-and-null is damage, not absence, so the repository must report
        // it and keep the bytes rather than clearing a match the player may still
        // be able to resume from a later build.
        final store = MemoryKeyValueStore()
          ..values['active_match.v1'] = jsonEncode({
            'version': 1,
            'matchId': testMatchId,
            'snapshot': _legacySnapshot().toJson(),
            'eliminationRounds': <String, Object?>{},
            'coachWasEnabled': false,
            'fiftyCountersComplete': true,
            'replayIneligible': false,
            'recorderState': null,
          });
        final repository = LocalMatchRepository(
          store: store,
          mintMatchId: () async => testMatchId,
        );

        final outcome = await repository.loadActiveMatch();

        expect(outcome, isA<ActiveMatchUnreadable>());
        expect(
          (outcome as ActiveMatchUnreadable).failure.kind,
          MatchHistoryFailureKind.corrupt,
        );
        // Preserved, not cleared.
        expect(store.values.containsKey('active_match.v1'), isTrue);
      },
    );

    test('invalid saved match is cleared and ignored', () async {
      final store = MemoryKeyValueStore()
        ..values['active_match.v1'] = '{"version":99}';
      final repository = LocalMatchRepository(
        store: store,
        mintMatchId: () async => testMatchId,
      );

      final restored = await repository.loadActiveMatch();

      expect(restored, isA<ActiveMatchAbsent>());
      expect(store.values.containsKey('active_match.v1'), isFalse);
    });
  });
}

HareegCard _card(CardRank rank, CardSuit suit) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: 50);
}

ClassicHareegMatchSnapshot _legacySnapshot() {
  final round = ClassicHareegRound.deal(
    setup: ClassicHareegSetup.defaults(),
    seed: 4,
  );
  return ClassicHareegMatchSnapshot(
    setup: round.setup,
    hands: round.hands,
    stock: round.stock,
    discardPile: round.discardPile,
    starter: round.starter,
    currentSeat: round.currentSeat,
    turnPhase: round.turnPhase,
    savedAt: DateTime.utc(2026, 5, 18),
  );
}
