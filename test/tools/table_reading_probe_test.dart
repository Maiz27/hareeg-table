import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_observation.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_discard_history.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

import '../../tools/table_reading_probe.dart';

/// Regressions for the probe's attribution machinery.
///
/// The probe reports device evidence, so a defect in how it *counts* is a
/// defect in the evidence. Each test here corresponds to a way the round-one
/// numbers were wrong: a counterfactual that was never proven surgical, a
/// blinding that never proved it removed anything, and evidence-class counters
/// that were fed the combined availability.
///
/// Deliberately built on tiny synthetic positions rather than a real run —
/// these assert the bookkeeping, not the corpus.
HareegCard _c(CardRank rank, CardSuit suit, {int deckIndex = 0}) =>
    HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);

const _allSeats = [
  PlayerSeat.south,
  PlayerSeat.east,
  PlayerSeat.north,
  PlayerSeat.west,
];

CpuObservationFacts _position({
  List<HareegCard> hand = const [],
  List<HareegCard> discardPile = const [],
  Map<PlayerSeat, List<PlacedMeld>> tableMelds = const {},
  DiscardHistoryView discardHistory = const EmptyDiscardHistoryView(),
  Map<PlayerSeat, int> handCounts = const {},
  int discardCount = 0,
}) {
  return CpuObservationFacts(
    seat: PlayerSeat.south,
    difficulty: CpuDifficulty.expert,
    legalActionIds: [for (final card in hand) 'discard:${card.id}'],
    turnPhase: TurnPhase.action,
    ownHand: hand,
    handCounts: handCounts,
    tableMelds: tableMelds,
    discardPile: discardPile,
    discardCount: discardCount,
    activeSeats: _allSeats,
    discardHistory: discardHistory,
    openingState: const OpeningState(
      baseRequirement: 30,
      currentRequirement: 30,
      openedSeats: {PlayerSeat.south, PlayerSeat.east},
    ),
  );
}

void main() {
  group('a counterfactual never launders a confounded position', () {
    test('a confounded outcome is recorded but never counted', () {
      final counterfactual = Counterfactual();
      final tally = SignalTally();

      scoreCounterfactual(
        counterfactual,
        removed: true,
        surgical: false,
        changed: true,
        into: tally,
      );

      expect(counterfactual.blindable, 1);
      expect(counterfactual.confounded, 1);
      expect(counterfactual.countable, 0);
      expect(counterfactual.changed, 0);
      expect(
        tally.choiceChanged,
        0,
        reason: 'a change that cannot be attributed is not evidence',
      );
    });

    test('a blinding that removed nothing is not evidence either', () {
      final counterfactual = Counterfactual();
      final tally = SignalTally();

      scoreCounterfactual(
        counterfactual,
        removed: false,
        surgical: true,
        changed: true,
        into: tally,
      );

      expect(counterfactual.confounded, 1);
      expect(counterfactual.changed, 0);
      expect(tally.choiceChanged, 0);
    });

    test('a surgical removal that moves the plan does count', () {
      final counterfactual = Counterfactual();
      final tally = SignalTally();

      scoreCounterfactual(
        counterfactual,
        removed: true,
        surgical: true,
        changed: true,
        into: tally,
      );

      expect(counterfactual.countable, 1);
      expect(counterfactual.changed, 1);
      expect(tally.choiceChanged, 1);
    });

    test('blindable always splits into countable plus confounded', () {
      final counterfactual = Counterfactual();
      final tally = SignalTally();
      for (final outcome in [
        (removed: true, surgical: true, changed: true),
        (removed: true, surgical: true, changed: false),
        (removed: true, surgical: false, changed: true),
        (removed: false, surgical: true, changed: true),
      ]) {
        scoreCounterfactual(
          counterfactual,
          removed: outcome.removed,
          surgical: outcome.surgical,
          changed: outcome.changed,
          into: tally,
        );
      }

      expect(counterfactual.blindable, 4);
      expect(
        counterfactual.countable + counterfactual.confounded,
        counterfactual.blindable,
      );
      expect(counterfactual.changed, 1);
      expect(tally.choiceChanged, 1);
    });
  });

  group('availability is never mistaken for consumption', () {
    test('a tier that is allowed to look but never acts proves nothing', () {
      // `applied` is policy × availability: the tier attends the signal class
      // and the signal had something to say. Both stay exactly as high if the
      // production comparator stops reading the feed result altogether, so a
      // large `applied` is not evidence that anything was consumed.
      final tier = TierReport(CpuDifficulty.expert)
        ..feed.attended = 300
        ..feed.available = 300
        ..feed.applied = 300;

      expect(tier.feed.applied, 300);
      expect(
        provesFeedConsumption(tier),
        isFalse,
        reason:
            'consumption is a planner result, not a policy flag; only a '
            'surgical counterfactual that moved a real decision counts',
      );
    });

    test('one surgical counterfactual change is what proves it', () {
      final viaPickup = TierReport(CpuDifficulty.expert)
        ..feedPickupBlind.changed = 1;
      final viaMeld = TierReport(CpuDifficulty.expert)
        ..feedMeldBlind.changed = 1;

      expect(provesFeedConsumption(viaPickup), isTrue);
      expect(provesFeedConsumption(viaMeld), isTrue);
    });

    test('a tier with no counterfactual movement never proves consumption', () {
      final tier = TierReport(CpuDifficulty.skilled)
        ..feed.attended = 300
        ..feed.available = 22
        ..feed.applied = 22
        ..feedPickupBlind.blindable = 22
        ..feedPickupBlind.confounded = 22;

      expect(provesFeedConsumption(tier), isFalse);
    });
  });

  group('the material blinding proves it removed the signal', () {
    test('emptying the pile does not always silence card death', () {
      // The reason the round-one blind was not load-bearing: card death counts
      // the perspective hand and the visible melds as well as the pile. Here
      // both missing sevens are accounted for WITHOUT the pile, so the pair
      // stays starved however empty the pile is.
      final hand = [
        _c(CardRank.seven, CardSuit.hearts),
        _c(CardRank.seven, CardSuit.spades),
      ];
      final blinded = _position(
        hand: hand,
        tableMelds: {
          PlayerSeat.north: [
            PlacedMeld.fromCards([
              _c(CardRank.seven, CardSuit.clubs),
              _c(CardRank.eight, CardSuit.clubs),
              _c(CardRank.nine, CardSuit.clubs),
            ]),
            PlacedMeld.fromCards([
              _c(CardRank.seven, CardSuit.clubs, deckIndex: 1),
              _c(CardRank.seven, CardSuit.diamonds),
              _c(CardRank.seven, CardSuit.hearts, deckIndex: 1),
            ]),
            PlacedMeld.fromCards([
              _c(CardRank.seven, CardSuit.diamonds, deckIndex: 1),
              _c(CardRank.eight, CardSuit.diamonds),
              _c(CardRank.nine, CardSuit.diamonds),
            ]),
          ],
        },
      );

      expect(
        materialSignalPresent(blinded, hand),
        isTrue,
        reason:
            'an empty pile is not the same as a removed signal, which is why '
            'the probe asserts removal instead of assuming it',
      );
    });

    test('a genuinely blind position reports no starved candidate', () {
      final hand = [
        _c(CardRank.seven, CardSuit.hearts),
        _c(CardRank.seven, CardSuit.spades),
      ];
      expect(materialSignalPresent(_position(hand: hand), hand), isFalse);
    });
  });

  group('the feed blinding proves it removed the signal', () {
    test('a position with a live cover still reports feed evidence', () {
      final hand = [_c(CardRank.jack, CardSuit.clubs)];
      final position = _position(
        hand: hand,
        tableMelds: {
          PlayerSeat.east: [
            PlacedMeld.fromCards([
              _c(CardRank.eight, CardSuit.clubs),
              _c(CardRank.nine, CardSuit.clubs),
              _c(CardRank.ten, CardSuit.clubs),
            ]),
          ],
        },
      );
      expect(feedEvidencePresent(position, hand), isTrue);
    });

    test('replacing the target meld with a maximal set silences it', () {
      final hand = [_c(CardRank.jack, CardSuit.clubs)];
      final position = _position(
        hand: hand,
        tableMelds: {
          PlayerSeat.east: [
            PlacedMeld.fromCards([
              _c(CardRank.four, CardSuit.hearts),
              _c(CardRank.four, CardSuit.clubs),
              _c(CardRank.four, CardSuit.spades),
              _c(CardRank.four, CardSuit.diamonds),
            ]),
          ],
        },
      );
      expect(feedEvidencePresent(position, hand), isFalse);
    });
  });

  group('the legacy posture guard notices when it has been disturbed', () {
    final hand = [
      _c(CardRank.nine, CardSuit.hearts),
      _c(CardRank.four, CardSuit.spades),
    ];

    PlacedMeld clubRun() => PlacedMeld.fromCards([
      _c(CardRank.eight, CardSuit.clubs),
      _c(CardRank.nine, CardSuit.clubs),
      _c(CardRank.ten, CardSuit.clubs),
    ]);

    test('removing a run the legacy profile reads is caught', () {
      // This is the confound that made the round-one Expert number
      // unattributable: neutralising the target's melds also removes the
      // run-end threats `OpponentThreatProfile` scores.
      final live = _position(
        hand: [_c(CardRank.jack, CardSuit.clubs), ...hand],
        tableMelds: {
          PlayerSeat.east: [clubRun()],
        },
      );
      final blind = _position(
        hand: [_c(CardRank.jack, CardSuit.clubs), ...hand],
        tableMelds: {
          PlayerSeat.east: [
            PlacedMeld.fromCards([
              _c(CardRank.four, CardSuit.hearts),
              _c(CardRank.four, CardSuit.clubs),
              _c(CardRank.four, CardSuit.spades),
              _c(CardRank.four, CardSuit.diamonds),
            ]),
          ],
        },
      );

      expect(
        legacyProfileUnchanged(
          live: live,
          blind: blind,
          candidates: [_c(CardRank.jack, CardSuit.clubs)],
        ),
        isFalse,
      );
    });

    test('removing pickups the legacy profile reads is caught', () {
      final history = DiscardHistory()
        ..recordPickup(PlayerSeat.east, _c(CardRank.nine, CardSuit.clubs));
      // East must still be reading the pile: the legacy profile drops the
      // pickups of an opened seat that is down to fewer than four cards.
      final live = _position(
        hand: hand,
        discardHistory: history,
        handCounts: const {PlayerSeat.east: 9},
      );
      final blind = _position(
        hand: hand,
        handCounts: const {PlayerSeat.east: 9},
      );

      expect(
        legacyProfileUnchanged(live: live, blind: blind, candidates: hand),
        isFalse,
      );
    });

    test('a change the legacy profile cannot see passes the guard', () {
      // A set produces no run-end threat and East has no readable pickups, so
      // every legacy value is zero on both sides even though the new signal
      // sees a legal cover appear.
      final candidates = [_c(CardRank.four, CardSuit.diamonds), ...hand];
      final live = _position(
        hand: candidates,
        tableMelds: {
          PlayerSeat.east: [
            PlacedMeld.fromCards([
              _c(CardRank.four, CardSuit.hearts),
              _c(CardRank.four, CardSuit.clubs),
              _c(CardRank.four, CardSuit.spades),
            ]),
          ],
        },
      );
      final blind = _position(hand: candidates);

      expect(feedEvidencePresent(live, candidates), isTrue);
      expect(feedEvidencePresent(blind, candidates), isFalse);
      expect(
        legacyProfileUnchanged(live: live, blind: blind, candidates: candidates),
        isTrue,
        reason: 'nothing the legacy profile scores moved between these two',
      );
    });
  });
}
