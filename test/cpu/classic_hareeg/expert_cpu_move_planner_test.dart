import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_observation.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_strategy.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_discard_history.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

void main() {
  group('Expert CPU routing', () {
    test('holds a plausible Fifty setup even near own elimination', () {
      final firstMeld = [
        card(CardRank.seven, CardSuit.clubs),
        card(CardRank.eight, CardSuit.clubs),
        card(CardRank.nine, CardSuit.clubs),
      ];
      final secondMeld = [
        card(CardRank.ten, CardSuit.hearts),
        card(CardRank.jack, CardSuit.hearts),
        card(CardRank.queen, CardSuit.hearts),
      ];
      final finalDiscard = card(CardRank.king, CardSuit.diamonds);
      final finish = partition(
        [firstMeld, secondMeld],
        remaining: [finalDiscard],
      );
      final finishAction = ClassicHareegActionIds.playMeldActionId(
        [...firstMeld, ...secondMeld].map((card) => card.id),
      );
      final discardFinal = discardAction(finalDiscard);
      final history = DiscardHistory()
        ..recordDiscard(PlayerSeat.south, card(CardRank.four, CardSuit.clubs));
      final observation = _FakeCpuObservation(
        legalActionIds: [finishAction, discardFinal],
        ownHand: [...firstMeld, ...secondMeld, finalDiscard],
        ownScore: 25,
        stockCount: 20,
        openingState: opened(),
        discardHistory: history,
        partitions: _FakeMeldPartitionView([finish]),
        finishingPartition: finish,
      );

      expect(_choose(CpuDifficulty.skilled, observation), finishAction);
      expect(_choose(CpuDifficulty.expert, observation), discardFinal);
    });

    test('extends Fifty hold window for a high-score opponent target', () {
      final firstMeld = [
        card(CardRank.seven, CardSuit.clubs),
        card(CardRank.eight, CardSuit.clubs),
        card(CardRank.nine, CardSuit.clubs),
      ];
      final secondMeld = [
        card(CardRank.ten, CardSuit.hearts),
        card(CardRank.jack, CardSuit.hearts),
        card(CardRank.queen, CardSuit.hearts),
      ];
      final finalDiscard = card(CardRank.king, CardSuit.diamonds);
      final finish = partition(
        [firstMeld, secondMeld],
        remaining: [finalDiscard],
      );
      final finishAction = ClassicHareegActionIds.playMeldActionId(
        [...firstMeld, ...secondMeld].map((card) => card.id),
      );
      final discardFinal = discardAction(finalDiscard);
      final observation = _FakeCpuObservation(
        legalActionIds: [finishAction, discardFinal],
        ownHand: [...firstMeld, ...secondMeld, finalDiscard],
        stockCount: 9,
        openingState: opened(),
        opponentScores: const {PlayerSeat.west: 28},
        partitions: _FakeMeldPartitionView([finish]),
        finishingPartition: finish,
      );

      expect(_choose(CpuDifficulty.skilled, observation), finishAction);
      expect(_choose(CpuDifficulty.expert, observation), discardFinal);
    });

    test('refuses discard adjacent to a high-score opponent run end', () {
      final nineHearts = card(CardRank.nine, CardSuit.hearts);
      final fourClubs = card(CardRank.four, CardSuit.clubs);
      final westRun = [
        card(CardRank.six, CardSuit.hearts),
        card(CardRank.seven, CardSuit.hearts),
        card(CardRank.eight, CardSuit.hearts),
      ];
      final observation = _FakeCpuObservation(
        legalActionIds: [discardAction(nineHearts), discardAction(fourClubs)],
        ownHand: [nineHearts, fourClubs],
        openingState: opened(),
        opponentScores: const {PlayerSeat.west: 26},
        tableMelds: {
          PlayerSeat.west: [PlacedMeld.fromCards(westRun)],
        },
      );

      expect(
        _choose(CpuDifficulty.skilled, observation),
        discardAction(nineHearts),
      );
      expect(
        _choose(CpuDifficulty.expert, observation),
        discardAction(fourClubs),
      );
    });

    test('uses deeper pickup attribution than Skilled hot-list memory', () {
      // The "collecting" signal is what an opponent PICKED UP, not what they
      // discarded. West picked up a 9 several turns back (older than Skilled's
      // 3-deep pickup window but inside Expert's deep memory). Expert still
      // treats rank 9 as hot and refuses to feed it, discarding the 4 instead;
      // Skilled has forgotten the old pickup and falls back to its own posture.
      final nineHearts = card(CardRank.nine, CardSuit.hearts);
      final fourClubs = card(CardRank.four, CardSuit.clubs);
      final history = DiscardHistory()
        // Oldest pickup carries the 9 — beyond Skilled's 3-deep window.
        ..recordPickup(PlayerSeat.west, card(CardRank.nine, CardSuit.diamonds))
        ..recordPickup(PlayerSeat.west, card(CardRank.two, CardSuit.diamonds))
        ..recordPickup(PlayerSeat.west, card(CardRank.three, CardSuit.diamonds))
        ..recordPickup(PlayerSeat.west, card(CardRank.five, CardSuit.spades));
      final observation = _FakeCpuObservation(
        legalActionIds: [discardAction(nineHearts), discardAction(fourClubs)],
        ownHand: [nineHearts, fourClubs],
        openingState: opened(),
        discardHistory: history,
      );

      // Expert keeps the 9 (West is collecting 9s) and sheds the 4.
      expect(
        _choose(CpuDifficulty.expert, observation),
        discardAction(fourClubs),
      );
      // Skilled no longer remembers the old 9 pickup, so it does not avoid the
      // 9 on that basis (its default posture differs from Expert here).
      expect(
        _choose(CpuDifficulty.skilled, observation),
        isNot(discardAction(fourClubs)),
      );
    });

    test(
      'an opponent DISCARDING a suit does not make the seat hoard that suit',
      () {
        // Playtest regression: West discarded a heart and a spade (cards it does
        // NOT want). That must not flip the seat into keeping its dead low cards
        // and shedding a genuinely useful high card. With two dead 3s (one a
        // duplicate) and a developing 8♦, the Expert must discard a low 3, never
        // the 8 — a discard by an opponent is a SAFE signal, not a hot one.
        final threeHeartsA = card(CardRank.three, CardSuit.hearts);
        // Second physical 3♥ (distinct id) — the exact duplicate the seat holds.
        final threeHeartsB = HareegCard.standard(
          rank: CardRank.three,
          suit: CardSuit.hearts,
          deckIndex: 2,
        );
        final threeSpades = card(CardRank.three, CardSuit.spades);
        final eightDiamonds = card(CardRank.eight, CardSuit.diamonds);
        final eightHearts = card(CardRank.eight, CardSuit.hearts);
        final history = DiscardHistory()
          ..recordDiscard(PlayerSeat.west, card(CardRank.king, CardSuit.hearts))
          ..recordDiscard(PlayerSeat.west, card(CardRank.two, CardSuit.spades));
        final observation = _FakeCpuObservation(
          legalActionIds: [
            discardAction(threeHeartsA),
            discardAction(threeHeartsB),
            discardAction(threeSpades),
            discardAction(eightDiamonds),
            discardAction(eightHearts),
          ],
          ownHand: [
            threeHeartsA,
            threeHeartsB,
            threeSpades,
            eightDiamonds,
            eightHearts,
          ],
          openingState: opened(),
          discardHistory: history,
        );

        final chosen = _choose(CpuDifficulty.expert, observation);
        expect(
          chosen,
          isNot(anyOf(
            discardAction(eightDiamonds),
            discardAction(eightHearts),
          )),
        );
        expect(
          chosen,
          anyOf(
            discardAction(threeHeartsA),
            discardAction(threeHeartsB),
            discardAction(threeSpades),
          ),
        );
      },
    );

    test('takes a thin-stock discard defensively even without a meld', () {
      final kingSpades = card(CardRank.king, CardSuit.spades);
      final observation = _FakeCpuObservation(
        legalActionIds: [
          ClassicHareegActionIds.takeDiscard,
          ClassicHareegActionIds.drawStock,
        ],
        turnPhase: TurnPhase.draw,
        topDiscard: kingSpades,
        ownHand: [
          card(CardRank.two, CardSuit.clubs),
          card(CardRank.four, CardSuit.diamonds),
          card(CardRank.six, CardSuit.hearts),
        ],
        stockCount: 7,
        openingState: opened(),
      );

      expect(
        _choose(CpuDifficulty.skilled, observation),
        ClassicHareegActionIds.drawStock,
      );
      expect(
        _choose(CpuDifficulty.expert, observation),
        ClassicHareegActionIds.takeDiscard,
      );
    });

    test('delays joker replacement until a finish is visible', () {
      final discard = card(CardRank.four, CardSuit.clubs);
      final replacement = ClassicHareegActionIds.replaceJokerActionId(
        targetSeat: PlayerSeat.south,
        meldIndex: 0,
        cardId: card(CardRank.jack, CardSuit.clubs).id,
      );
      final observation = _FakeCpuObservation(
        legalActionIds: [replacement, discardAction(discard)],
        ownHand: [discard],
        openingState: opened(),
      );

      expect(_choose(CpuDifficulty.skilled, observation), replacement);
      expect(
        _choose(CpuDifficulty.expert, observation),
        discardAction(discard),
      );
    });

    test('pushes first opening benchmark into the 70-80 band', () {
      final lowOpen = [
        card(CardRank.jack, CardSuit.hearts),
        card(CardRank.queen, CardSuit.hearts),
        card(CardRank.king, CardSuit.hearts),
      ];
      final fatOpen = [
        card(CardRank.seven, CardSuit.clubs),
        card(CardRank.eight, CardSuit.clubs),
        card(CardRank.nine, CardSuit.clubs),
        card(CardRank.ten, CardSuit.clubs),
        card(CardRank.jack, CardSuit.clubs),
        card(CardRank.queen, CardSuit.clubs),
        card(CardRank.king, CardSuit.clubs),
      ];
      final leftovers = [card(CardRank.two, CardSuit.spades)];
      final lowAction = ClassicHareegActionIds.playMeldActionId(
        lowOpen.map((card) => card.id),
      );
      final fatAction = ClassicHareegActionIds.playMeldActionId(
        fatOpen.map((card) => card.id),
      );
      final observation = _FakeCpuObservation(
        legalActionIds: [lowAction, fatAction],
        ownHand: [...lowOpen, ...fatOpen, ...leftovers],
        stockCount: 40,
        openingState: OpeningState.initial(30),
        partitions: _FakeMeldPartitionView([
          partition([lowOpen], remaining: [...fatOpen, ...leftovers]),
          partition([fatOpen], remaining: [...lowOpen, ...leftovers]),
        ]),
      );

      expect(_choose(CpuDifficulty.skilled, observation), lowAction);
      expect(_choose(CpuDifficulty.expert, observation), fatAction);
    });

    test('prefers interior joker sequence identities', () {
      const joker = HareegCard.joker(deckIndex: 9, jokerIndex: 0);
      final queenHearts = card(CardRank.queen, CardSuit.hearts);
      final kingHearts = card(CardRank.king, CardSuit.hearts);
      final aceHearts = card(CardRank.ace, CardSuit.hearts);
      final leftover = card(CardRank.two, CardSuit.spades);
      const edgeIdentity = CardIdentity(
        rank: CardRank.jack,
        suit: CardSuit.hearts,
      );
      const interiorIdentity = CardIdentity(
        rank: CardRank.king,
        suit: CardSuit.hearts,
      );
      final edgeAssignment = JokerMeldAssignment(
        jokerId: joker.id,
        identity: edgeIdentity,
      );
      final interiorAssignment = JokerMeldAssignment(
        jokerId: joker.id,
        identity: interiorIdentity,
      );
      final edgeAction =
          ClassicHareegActionIds.playMeldWithJokerIdentitiesActionId(
            cardIds: [joker.id, queenHearts.id, kingHearts.id],
            assignments: [edgeAssignment],
          );
      final interiorAction =
          ClassicHareegActionIds.playMeldWithJokerIdentitiesActionId(
            cardIds: [joker.id, queenHearts.id, aceHearts.id],
            assignments: [interiorAssignment],
          );
      final observation = _FakeCpuObservation(
        legalActionIds: [edgeAction, interiorAction],
        ownHand: [joker, queenHearts, kingHearts, aceHearts, leftover],
        openingState: opened(),
        partitions: _FakeMeldPartitionView([
          partitionFromPlaced(
            [
              [joker.asRepresenting(edgeIdentity), queenHearts, kingHearts],
            ],
            remaining: [aceHearts, leftover],
            assignments: [edgeAssignment],
          ),
          partitionFromPlaced(
            [
              [joker.asRepresenting(interiorIdentity), queenHearts, aceHearts],
            ],
            remaining: [kingHearts, leftover],
            assignments: [interiorAssignment],
          ),
        ]),
        discardHistory: DiscardHistory()
          ..recordDiscard(
            PlayerSeat.south,
            card(CardRank.jack, CardSuit.hearts),
          ),
      );

      expect(_choose(CpuDifficulty.skilled, observation), edgeAction);
      expect(_choose(CpuDifficulty.expert, observation), interiorAction);
    });
  });

  group('Expert cover posture (endgame Fifty-hold)', () {
    final westRun = [
      card(CardRank.seven, CardSuit.spades),
      card(CardRank.eight, CardSuit.spades),
      card(CardRank.nine, CardSuit.spades),
    ];

    test('never burns a joker on a non-finishing cover', () {
      // A held joker is the strongest finish/Fifty asset, so Expert holds it
      // rather than laying it onto a cover. Skilled (no Fifty-hold posture)
      // still burns it — the tier difference the playtest exposed.
      final joker = HareegCard.joker(deckIndex: 90, jokerIndex: 0);
      final fiveClubs = card(CardRank.five, CardSuit.clubs);
      final nineDiamonds = card(CardRank.nine, CardSuit.diamonds);
      final coverAction = ClassicHareegActionIds.placeCoverActionId(
        targetSeat: PlayerSeat.west,
        meldIndex: 0,
        cardIds: [joker.id],
      );
      final observation = _FakeCpuObservation(
        legalActionIds: [
          coverAction,
          discardAction(fiveClubs),
          discardAction(nineDiamonds),
        ],
        ownHand: [joker, fiveClubs, nineDiamonds],
        stockCount: 20,
        openingState: opened(),
        tableMelds: {
          PlayerSeat.west: [PlacedMeld.fromCards(westRun)],
        },
      );

      expect(_choose(CpuDifficulty.skilled, observation), coverAction);
      final expert = _choose(CpuDifficulty.expert, observation);
      expect(expert, isNot(coverAction));
      expect(expert.startsWith(ClassicHareegActionIds.discardPrefix), isTrue);
    });

    test('always plays a cover that empties the hand (a win)', () {
      // A finishing cover wins outright; the Fifty-hold posture must never
      // suppress it even with a tiny hand and deep stock.
      final fiveSpades = card(CardRank.five, CardSuit.spades);
      final coverAction = ClassicHareegActionIds.placeCoverActionId(
        targetSeat: PlayerSeat.east,
        meldIndex: 0,
        cardIds: [fiveSpades.id],
      );
      final observation = _FakeCpuObservation(
        legalActionIds: [coverAction, discardAction(fiveSpades)],
        ownHand: [fiveSpades],
        stockCount: 20,
        openingState: opened(),
        tableMelds: {
          PlayerSeat.east: [
            PlacedMeld.fromCards([
              card(CardRank.two, CardSuit.spades),
              card(CardRank.three, CardSuit.spades),
              card(CardRank.four, CardSuit.spades),
            ]),
          ],
        },
      );

      expect(_choose(CpuDifficulty.expert, observation), coverAction);
    });

    test('holds a non-finishing cover for a Fifty while the hand develops', () {
      // Issue C: opened, few cards, deep stock, a developing pair. The cover
      // extends the seat's OWN set (not a run end, so only the new Fifty-hold
      // posture — never the legacy own-run-end hold — can cause the hold).
      // Covering sheds an extra card and kills the Fifty; Expert instead holds
      // the cover and discards the loose 5, keeping the 9-pair to draw a Fifty.
      final fiveSpades = card(CardRank.five, CardSuit.spades);
      final nineHearts = card(CardRank.nine, CardSuit.hearts);
      final nineDiamonds = card(CardRank.nine, CardSuit.diamonds);
      final ownFiveSet = [
        card(CardRank.five, CardSuit.hearts),
        card(CardRank.five, CardSuit.clubs),
        card(CardRank.five, CardSuit.diamonds),
      ];
      final coverAction = ClassicHareegActionIds.placeCoverActionId(
        targetSeat: PlayerSeat.east,
        meldIndex: 0,
        cardIds: [fiveSpades.id],
      );
      final observation = _FakeCpuObservation(
        legalActionIds: [
          coverAction,
          discardAction(fiveSpades),
          discardAction(nineHearts),
          discardAction(nineDiamonds),
        ],
        ownHand: [fiveSpades, nineHearts, nineDiamonds],
        stockCount: 40,
        openingState: opened(),
        tableMelds: {
          PlayerSeat.east: [PlacedMeld.fromCards(ownFiveSet)],
        },
      );

      // Holds the cover (does not play it) and sheds the loose 5, not a 9.
      expect(
        _choose(CpuDifficulty.expert, observation),
        discardAction(fiveSpades),
      );
    });

    test('plays a non-finishing cover when the hand is not developing', () {
      // The Fifty-hold gate is real: with no developing pair/run left, holding
      // buys nothing, so Expert lays the loose card off as a cover.
      final tenSpades = card(CardRank.ten, CardSuit.spades);
      final fourHearts = card(CardRank.four, CardSuit.hearts);
      final coverAction = ClassicHareegActionIds.placeCoverActionId(
        targetSeat: PlayerSeat.west,
        meldIndex: 0,
        cardIds: [tenSpades.id],
      );
      final observation = _FakeCpuObservation(
        legalActionIds: [
          coverAction,
          discardAction(tenSpades),
          discardAction(fourHearts),
        ],
        ownHand: [tenSpades, fourHearts],
        stockCount: 40,
        openingState: opened(),
        tableMelds: {
          PlayerSeat.west: [PlacedMeld.fromCards(westRun)],
        },
      );

      expect(_choose(CpuDifficulty.expert, observation), coverAction);
    });
  });
}

String _choose(CpuDifficulty difficulty, _FakeCpuObservation observation) {
  const strategy = ClassicHareegCpuStrategy();
  return strategy
      .chooseMove(
        CpuTurnSnapshot(
          seat: PlayerSeat.east,
          difficulty: difficulty,
          legalActionIds: observation.legalActionIds,
        ),
        observation: observation,
      )
      .actionId;
}

HareegCard card(CardRank rank, CardSuit suit) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: 1);
}

String discardAction(HareegCard card) {
  return '${ClassicHareegActionIds.discardPrefix}${card.id}';
}

OpeningState opened() {
  return OpeningState(
    baseRequirement: 30,
    currentRequirement: 30,
    openedSeats: const {PlayerSeat.east},
  );
}

MeldPartition partition(
  List<List<HareegCard>> melds, {
  List<HareegCard> remaining = const [],
}) {
  return partitionFromPlaced(melds, remaining: remaining);
}

MeldPartition partitionFromPlaced(
  List<List<HareegCard>> melds, {
  List<HareegCard> remaining = const [],
  List<JokerMeldAssignment> assignments = const [],
}) {
  final placed = melds.map(PlacedMeld.fromCards).toList(growable: false);
  return MeldPartition(
    melds: placed,
    cardsUsed: placed.expand((meld) => meld.cards),
    cardsRemaining: remaining,
    jokerAssignments: assignments,
  );
}

final class _FakeMeldPartitionView implements MeldPartitionView {
  const _FakeMeldPartitionView(this.partitions);

  final List<MeldPartition> partitions;

  @override
  Iterable<MeldPartition> enumerate({
    bool includePendingDiscard = true,
    int maxPartitions = 32,
    int minMelds = 1,
    int maxMelds = 5,
    String? mustUseCardId,
    int? minTotalValue,
  }) {
    return partitions
        .where((partition) => partition.meldCount >= minMelds)
        .where((partition) => partition.meldCount <= maxMelds)
        .where(
          (partition) =>
              mustUseCardId == null || partition.usesCardId(mustUseCardId),
        )
        .where(
          (partition) =>
              minTotalValue == null || partition.totalValue >= minTotalValue,
        )
        .take(maxPartitions);
  }
}

typedef _FakeCpuObservation = CpuObservationFacts;
