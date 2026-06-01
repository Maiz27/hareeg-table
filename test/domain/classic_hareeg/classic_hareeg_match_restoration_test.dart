import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_restoration.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot_v1.dart';
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

  group('ClassicHareegMatchRestoration JSON round-trip (Issue D)', () {
    test(
      'round >= 2 Fifty window survives encode/decode with -3 scoring '
      'and the true discarder',
      () {
        // A real save: round 5, an OPEN Fifty window (draw phase, non-empty
        // discard). South is claiming; the geometric guess for the discarder
        // is south.previousAntiClockwise == west. We make WEST a removed seat
        // and record the TRUE discarder as east, so the geometric guess is
        // demonstrably wrong.
        final discarded = _card(CardRank.queen, CardSuit.hearts, 71);
        final snapshot = _snapshot(
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.draw,
          discardPile: [discarded],
          roundNumber: 5,
          removedSeats: const [PlayerSeat.west],
          activeSeats: const [
            PlayerSeat.south,
            PlayerSeat.east,
            PlayerSeat.north,
          ],
          fiftyWindowDiscarder: PlayerSeat.east,
          fiftyWindowIsFirstDealtRound: false,
        );

        // Full JSON round-trip — exactly the path a real save takes.
        final json = encodeMatchSnapshotV1(snapshot);
        final decoded = decodeMatchSnapshotV1(json);

        // Round number must survive verbatim, never collapse to 1.
        expect(decoded.roundNumber, 5);

        final restored = ClassicHareegMatchRestoration.fromSnapshot(decoded);

        expect(restored.fiftyWindow, isNotNull);
        // (a) -3 scoring: a round-5 Fifty is NOT the first-dealt-round
        // exception, so the winner delta must be -3, which means
        // isFirstDealtRound must be false.
        expect(
          restored.fiftyWindow!.isFirstDealtRound,
          isFalse,
          reason: 'Round 5 Fifty must use -3, not the first-round -1 exception.',
        );
        // (b) the penalty must land on the TRUE discarder (east), not the
        // geometric guess (west, which is removed anyway).
        expect(
          restored.fiftyWindow!.discarder,
          PlayerSeat.east,
          reason: 'Fifty penalty must charge the recorded discarder, '
              'not the geometric previousAntiClockwise guess.',
        );
      },
    );

    test(
      'roundNumber missing from JSON would silently collapse a round >= 2 '
      'Fifty into the first-round -1 exception',
      () {
        // Reproduces the persisted -1 symptom: a save whose roundNumber is
        // absent/unparseable. With the old `?? 1` fallback this decodes as
        // round 1 and (pre-fix) the restored Fifty window would claim the
        // first-dealt-round -1 exception even though it was really round 5.
        final discarded = _card(CardRank.queen, CardSuit.hearts, 71);
        final snapshot = _snapshot(
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.draw,
          discardPile: [discarded],
          roundNumber: 5,
        );
        final json = encodeMatchSnapshotV1(snapshot);
        json.remove('roundNumber');

        // After the fix this fails loud rather than silently scoring -1.
        expect(
          () => decodeMatchSnapshotV1(json),
          throwsA(isA<FormatException>()),
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
  List<PlayerSeat>? removedSeats,
  DateTime? savedAt,
  DateTime? fiftyWindowOpenedAt,
  PlayerSeat? fiftyWindowDiscarder,
  bool? fiftyWindowIsFirstDealtRound,
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
    removedSeats: removedSeats ?? const [],
    fiftyWindowOpenedAt: fiftyWindowOpenedAt,
    fiftyWindowDiscarder: fiftyWindowDiscarder,
    fiftyWindowIsFirstDealtRound: fiftyWindowIsFirstDealtRound,
    savedAt: savedAt ?? DateTime.utc(2026, 5, 21),
  );
}

HareegCard _card(CardRank rank, CardSuit suit, int deckIndex) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
