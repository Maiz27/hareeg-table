import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_restoration.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/finish_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

void main() {
  group('ClassicHareegMatchRestoration', () {
    test('restores detached mutable live state from snapshot', () {
      final southCard = _card(CardRank.five, CardSuit.clubs, 70);
      final stockCard = _card(CardRank.king, CardSuit.spades, 70);
      final tableMeld = const PlacedMeld(cards: [], valueSnapshot: 51);
      final snapshot = _snapshot(
        hands: {
          for (final seat in PlayerSeat.values) seat: <HareegCard>[],
          PlayerSeat.south: [southCard],
        },
        stock: [stockCard],
        tableMelds: {
          PlayerSeat.south: [tableMeld],
        },
        scores: const {PlayerSeat.south: 7},
        activeSeats: const [PlayerSeat.south, PlayerSeat.east],
      );

      final restored = ClassicHareegMatchRestoration.fromSnapshot(snapshot);
      restored.hands[PlayerSeat.south]!.clear();
      restored.stock.clear();
      restored.tableMelds[PlayerSeat.south]!.clear();
      restored.scores[PlayerSeat.south] = 99;
      restored.activeSeats.clear();
      restored.removedSeats.add(PlayerSeat.west);

      expect(snapshot.hands[PlayerSeat.south]!.single.id, southCard.id);
      expect(snapshot.stock.single.id, stockCard.id);
      expect(snapshot.tableMelds[PlayerSeat.south], [tableMeld]);
      expect(snapshot.scores[PlayerSeat.south], 7);
      expect(snapshot.activeSeats, [PlayerSeat.south, PlayerSeat.east]);
      expect(snapshot.removedSeats, isEmpty);
    });

    test('restores draw-phase discard metadata and Fifty window', () {
      final discarded = _card(CardRank.queen, CardSuit.hearts, 71);
      final savedAt = DateTime.utc(2026, 5, 21, 9);
      final openedAt = DateTime.utc(2026, 5, 21, 9, 0, 2);
      final snapshot = _snapshot(
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        discardPile: [discarded],
        roundNumber: 1,
        savedAt: savedAt,
        fiftyWindowOpenedAt: openedAt,
      );

      final restored = ClassicHareegMatchRestoration.fromSnapshot(snapshot);

      expect(restored.previousDiscardSeat, PlayerSeat.west);
      expect(restored.fiftyWindow, isNotNull);
      expect(restored.fiftyWindow!.discarder, PlayerSeat.west);
      expect(restored.fiftyWindow!.claimant, PlayerSeat.south);
      expect(restored.fiftyWindow!.discardedCard.id, discarded.id);
      expect(
        restored.fiftyWindow!.durationSeconds,
        snapshot.setup.fiftyTimerSeconds,
      );
      expect(restored.fiftyWindow!.isFirstDealtRound, isTrue);
      expect(restored.fiftyWindowOpenedAt, openedAt);
      expect(restored.turnSource, FinishCardSource.stock);
    });

    test(
      'restores pending-discard source without reopening Fifty in action',
      () {
        final discarded = _card(CardRank.three, CardSuit.diamonds, 72);
        final pending = _card(CardRank.four, CardSuit.diamonds, 72);
        final snapshot = _snapshot(
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          discardPile: [discarded],
          pendingDiscard: pending,
        );

        final restored = ClassicHareegMatchRestoration.fromSnapshot(snapshot);

        expect(restored.previousDiscardSeat, PlayerSeat.west);
        expect(restored.fiftyWindow, isNull);
        expect(restored.fiftyWindowOpenedAt, isNull);
        expect(restored.pendingDiscard?.id, pending.id);
        expect(restored.turnSource, FinishCardSource.previousDiscard);
        expect(
          restored.openingState.currentRequirement,
          snapshot.setup.openingRequirement,
        );
      },
    );
  });
}

ClassicHareegMatchSnapshot _snapshot({
  Map<PlayerSeat, List<HareegCard>>? hands,
  List<HareegCard>? stock,
  List<HareegCard>? discardPile,
  Map<PlayerSeat, List<PlacedMeld>>? tableMelds,
  Map<PlayerSeat, int>? scores,
  List<PlayerSeat>? activeSeats,
  PlayerSeat currentSeat = PlayerSeat.south,
  TurnPhase turnPhase = TurnPhase.action,
  HareegCard? pendingDiscard,
  int roundNumber = 2,
  DateTime? savedAt,
  DateTime? fiftyWindowOpenedAt,
}) {
  return ClassicHareegMatchSnapshot(
    setup: ClassicHareegSetup.defaults(),
    hands:
        hands ?? {for (final seat in PlayerSeat.values) seat: <HareegCard>[]},
    stock: stock ?? const [],
    discardPile: discardPile ?? const [],
    tableMelds: tableMelds ?? const {},
    starter: PlayerSeat.south,
    currentSeat: currentSeat,
    turnPhase: turnPhase,
    pendingDiscard: pendingDiscard,
    scores: scores ?? const {},
    activeSeats: activeSeats ?? PlayerSeat.values,
    roundNumber: roundNumber,
    fiftyWindowOpenedAt: fiftyWindowOpenedAt,
    savedAt: savedAt ?? DateTime.utc(2026, 5, 21),
  );
}

HareegCard _card(CardRank rank, CardSuit suit, int deckIndex) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
