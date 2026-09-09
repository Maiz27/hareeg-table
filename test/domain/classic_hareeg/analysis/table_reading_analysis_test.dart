import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/analysis/partial_hand_groups.dart';
import 'package:hareeg_table/domain/classic_hareeg/analysis/table_reading_analysis.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

HareegCard _c(CardRank rank, CardSuit suit, {int deckIndex = 0}) =>
    HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);

HareegCard _joker({int index = 0, CardIdentity? represents}) =>
    HareegCard.joker(
      deckIndex: 0,
      jokerIndex: index,
      representedIdentity: represents,
    );

CardIdentity _id(CardRank rank, CardSuit suit) =>
    CardIdentity(rank: rank, suit: suit);

/// The pip ceiling scorer the CPU layer hands in. Reproduced here so the
/// analysis can be exercised without importing `lib/cpu`, which the purity
/// lint forbids in the other direction and which would couple this test to a
/// planner detail it does not care about.
int _solo(HareegCard card, List<HareegCard> hand) {
  if (card.isJoker) {
    return 1 << 20;
  }
  return card.effectiveIdentity?.rank.value ?? 1 << 20;
}

TableReadingAnalysis _analysis({
  List<HareegCard> hand = const [],
  List<HareegCard> discardPile = const [],
  Map<PlayerSeat, List<PlacedMeld>> visibleMelds = const {},
  int deckCopyCount = 2,
}) {
  return TableReadingAnalysis(
    perspectiveHand: hand,
    discardPile: discardPile,
    visibleMelds: visibleMelds,
    deckCopyCount: deckCopyCount,
    soloValue: _solo,
  );
}

PartialHandGroup _pair(HareegCard a, HareegCard b) =>
    PartialHandGroup(kind: PartialGroupKind.pair, cards: [a, b], value: 0);

PartialHandGroup _run(HareegCard a, HareegCard b) =>
    PartialHandGroup(kind: PartialGroupKind.run, cards: [a, b], value: 0);

PlacedMeld _meld(List<HareegCard> cards) => PlacedMeld.fromCards(cards);

void main() {
  group('card death — three counting places, physical copies only', () {
    test('an identity with every copy accounted for is dead', () {
      final analysis = _analysis(
        hand: [_c(CardRank.seven, CardSuit.hearts)],
        discardPile: [_c(CardRank.seven, CardSuit.hearts, deckIndex: 1)],
      );
      expect(analysis.accountedCopies(_id(CardRank.seven, CardSuit.hearts)), 2);
      expect(analysis.isDead(_id(CardRank.seven, CardSuit.hearts)), isTrue);
    });

    test('copies are counted in hand, pile, and visible melds alike', () {
      final analysis = _analysis(
        hand: [_c(CardRank.four, CardSuit.clubs)],
        discardPile: const [],
        visibleMelds: {
          PlayerSeat.north: [
            _meld([
              _c(CardRank.four, CardSuit.clubs, deckIndex: 1),
              _c(CardRank.four, CardSuit.hearts),
              _c(CardRank.four, CardSuit.spades),
            ]),
          ],
        },
      );
      expect(analysis.accountedCopies(_id(CardRank.four, CardSuit.clubs)), 2);
      expect(analysis.isDead(_id(CardRank.four, CardSuit.clubs)), isTrue);
      // The other members of that meld are one copy each, not dead.
      expect(analysis.isDead(_id(CardRank.four, CardSuit.hearts)), isFalse);
    });

    test('a joker standing in for the identity does not count as a copy', () {
      // The physical card is still somewhere in play — in a hand, in the stock
      // — so the identity is alive however the meld reads on the table.
      final analysis = _analysis(
        hand: [_c(CardRank.nine, CardSuit.spades)],
        visibleMelds: {
          PlayerSeat.east: [
            PlacedMeld(
              cards: [
                _c(CardRank.eight, CardSuit.spades),
                _joker(represents: _id(CardRank.nine, CardSuit.spades)),
                _c(CardRank.ten, CardSuit.spades),
              ],
              valueSnapshot: 27,
            ),
          ],
        },
      );
      expect(analysis.accountedCopies(_id(CardRank.nine, CardSuit.spades)), 1);
      expect(analysis.isDead(_id(CardRank.nine, CardSuit.spades)), isFalse);
    });

    test('a merely unseen card is not dead', () {
      final analysis = _analysis(
        hand: [_c(CardRank.queen, CardSuit.diamonds)],
        deckCopyCount: 2,
      );
      expect(analysis.isDead(_id(CardRank.queen, CardSuit.diamonds)), isFalse);
    });

    test('deckCopyCount below one is rejected rather than tolerated', () {
      // A zero denominator would report every identity dead, which is
      // indistinguishable from the signal being switched off.
      expect(
        () => _analysis(hand: [_c(CardRank.two, CardSuit.clubs)], deckCopyCount: 0),
        throwsArgumentError,
      );
      expect(
        () =>
            _analysis(hand: [_c(CardRank.two, CardSuit.clubs)], deckCopyCount: -3),
        throwsArgumentError,
      );
    });

    test('jokers have no identity and are never reported dead or alive', () {
      final analysis = _analysis(
        hand: [_joker(), _joker(index: 1)],
        discardPile: [_joker(index: 2)],
      );
      // Every identity query is about a standard face; a joker contributes to
      // none of them.
      for (final rank in CardRank.values) {
        for (final suit in CardSuit.values) {
          expect(analysis.accountedCopies(_id(rank, suit)), 0);
        }
      }
    });

    test('card death is pure: repeated and permuted inputs agree', () {
      final hand = [
        _c(CardRank.five, CardSuit.hearts),
        _c(CardRank.five, CardSuit.hearts, deckIndex: 1),
        _c(CardRank.king, CardSuit.clubs),
      ];
      final pile = [
        _c(CardRank.three, CardSuit.spades),
        _c(CardRank.king, CardSuit.clubs, deckIndex: 1),
      ];
      final straight = _analysis(hand: hand, discardPile: pile);
      final permuted = _analysis(
        hand: hand.reversed.toList(),
        discardPile: pile.reversed.toList(),
      );

      for (final identity in [
        _id(CardRank.five, CardSuit.hearts),
        _id(CardRank.king, CardSuit.clubs),
        _id(CardRank.three, CardSuit.spades),
      ]) {
        expect(straight.isDead(identity), permuted.isDead(identity));
        expect(
          straight.accountedCopies(identity),
          permuted.accountedCopies(identity),
        );
        // And stable across repeat evaluation of the same instance.
        expect(straight.isDead(identity), straight.isDead(identity));
      }
    });

    test('the signature has no place for hidden state', () {
      // An architectural exclusion, asserted as documentation: everything the
      // constructor accepts is the seat's own hand or public table state.
      // Opponent hands, stock identities, pickup history, and future actions
      // have no parameter to arrive through. The behavioural proof that the
      // planners cannot leak them lives in the hidden-state test.
      final analysis = _analysis(hand: [_c(CardRank.ace, CardSuit.hearts)]);
      expect(analysis.perspectiveHand, hasLength(1));
      expect(analysis.discardPile, isEmpty);
      expect(analysis.visibleMelds, isEmpty);
      expect(() => analysis.perspectiveHand.add(_joker()), throwsUnsupportedError);
      expect(() => analysis.discardPile.add(_joker()), throwsUnsupportedError);
    });
  });

  group('development liveness — one-card completions', () {
    test('a pair completes with its rank in the suits it does not hold', () {
      final completions = TableReadingAnalysis.completionsFor(
        _pair(
          _c(CardRank.seven, CardSuit.hearts),
          _c(CardRank.seven, CardSuit.spades),
        ),
      );
      expect(completions, {
        _id(CardRank.seven, CardSuit.clubs),
        _id(CardRank.seven, CardSuit.diamonds),
      });
      // Held suits are excluded — a set needs distinct suits.
      expect(completions, isNot(contains(_id(CardRank.seven, CardSuit.hearts))));
      expect(completions, isNot(contains(_id(CardRank.seven, CardSuit.spades))));
    });

    test('an adjacent run completes at both ends', () {
      final completions = TableReadingAnalysis.completionsFor(
        _run(
          _c(CardRank.eight, CardSuit.clubs),
          _c(CardRank.nine, CardSuit.clubs),
        ),
      );
      expect(completions, {
        _id(CardRank.seven, CardSuit.clubs),
        _id(CardRank.ten, CardSuit.clubs),
      });
    });

    test('a gapped run completes only in the gap', () {
      final completions = TableReadingAnalysis.completionsFor(
        _run(
          _c(CardRank.eight, CardSuit.clubs),
          _c(CardRank.ten, CardSuit.clubs),
        ),
      );
      expect(completions, {_id(CardRank.nine, CardSuit.clubs)});
      // The outer extensions are NOT completions: 7-8-10 and 8-10-J are not
      // legal sequences, only the filled 8-9-10 is.
      expect(completions, isNot(contains(_id(CardRank.seven, CardSuit.clubs))));
      expect(completions, isNot(contains(_id(CardRank.jack, CardSuit.clubs))));
    });

    test('a solo group has no completions', () {
      expect(
        TableReadingAnalysis.completionsFor(
          PartialHandGroup(
            kind: PartialGroupKind.solo,
            cards: [_c(CardRank.king, CardSuit.hearts)],
            value: 10,
          ),
        ),
        isEmpty,
      );
    });

    test('completions come from the perspective hand alone', () {
      // Two analyses with identical hands but wildly different table state
      // report the same completions: the enumeration reads the group only.
      final pair = _pair(
        _c(CardRank.six, CardSuit.hearts),
        _c(CardRank.six, CardSuit.clubs),
      );
      expect(
        TableReadingAnalysis.completionsFor(pair),
        TableReadingAnalysis.completionsFor(pair),
      );
      expect(TableReadingAnalysis.completionsFor(pair), {
        _id(CardRank.six, CardSuit.spades),
        _id(CardRank.six, CardSuit.diamonds),
      });
    });
  });

  group('development liveness — the Ace sits at both ends', () {
    test('Queen-King completes with Jack OR Ace', () {
      // The meld validator accepts Q-K-A. A liveness walk that only stepped
      // through the low ordering, where Ace is 1, would silently drop the Ace
      // and call a live draw dead.
      final completions = TableReadingAnalysis.completionsFor(
        _run(
          _c(CardRank.queen, CardSuit.diamonds),
          _c(CardRank.king, CardSuit.diamonds),
        ),
      );
      expect(completions, {
        _id(CardRank.jack, CardSuit.diamonds),
        _id(CardRank.ace, CardSuit.diamonds),
      });
    });

    test('Ace-Two completes with Three', () {
      final completions = TableReadingAnalysis.completionsFor(
        _run(
          _c(CardRank.ace, CardSuit.spades),
          _c(CardRank.two, CardSuit.spades),
        ),
      );
      expect(completions, {_id(CardRank.three, CardSuit.spades)});
    });

    test('no off-deck rank is emitted at either boundary', () {
      final low = TableReadingAnalysis.completionsFor(
        _run(
          _c(CardRank.ace, CardSuit.spades),
          _c(CardRank.two, CardSuit.spades),
        ),
      );
      final high = TableReadingAnalysis.completionsFor(
        _run(
          _c(CardRank.queen, CardSuit.diamonds),
          _c(CardRank.king, CardSuit.diamonds),
        ),
      );
      final ranks = CardRank.values.toSet();
      for (final identity in {...low, ...high}) {
        expect(ranks, contains(identity.rank));
      }
      // Nothing "below Ace" and nothing "above King in the low ordering"
      // other than the deliberate high Ace.
      expect(low.length, 1);
      expect(high, {
        _id(CardRank.jack, CardSuit.diamonds),
        _id(CardRank.ace, CardSuit.diamonds),
      });
    });

    test(
      'a same-suit King-Ace pair still forms no group — the accepted v1 gap',
      () {
        // The grouping predicate measures distance in the low ordering where
        // Ace is 1, so King and Ace are 12 apart and never pair. Changing that
        // would move every keep score in the game, so Sprint 04 fixes only the
        // completion enumeration for groups the predicate already forms. This
        // test records the limitation rather than leaving it to be discovered.
        expect(
          cardsCanMeldTogether(
            _id(CardRank.king, CardSuit.hearts),
            _id(CardRank.ace, CardSuit.hearts),
          ),
          isFalse,
        );
      },
    );
  });

  group('group starvation', () {
    test('a developing pair whose every completion is dead is starved', () {
      final pairA = _c(CardRank.seven, CardSuit.hearts);
      final pairB = _c(CardRank.seven, CardSuit.spades);
      final analysis = _analysis(
        hand: [pairA, pairB],
        // Both remaining suits fully accounted for in the pile.
        discardPile: [
          _c(CardRank.seven, CardSuit.clubs),
          _c(CardRank.seven, CardSuit.clubs, deckIndex: 1),
          _c(CardRank.seven, CardSuit.diamonds),
          _c(CardRank.seven, CardSuit.diamonds, deckIndex: 1),
        ],
      );
      final group = analysis.partialGroups.single;
      expect(group.kind, PartialGroupKind.pair);
      expect(analysis.isGroupStarved(group), isTrue);
      expect(analysis.deadNeededIdentities, {
        _id(CardRank.seven, CardSuit.clubs),
        _id(CardRank.seven, CardSuit.diamonds),
      });
    });

    test('one live completion is enough to keep a group alive', () {
      final analysis = _analysis(
        hand: [
          _c(CardRank.seven, CardSuit.hearts),
          _c(CardRank.seven, CardSuit.spades),
        ],
        discardPile: [
          _c(CardRank.seven, CardSuit.clubs),
          _c(CardRank.seven, CardSuit.clubs, deckIndex: 1),
          _c(CardRank.seven, CardSuit.diamonds),
        ],
      );
      final group = analysis.partialGroups.single;
      expect(analysis.isGroupStarved(group), isFalse);
      expect(analysis.neededIdentities, contains(
        _id(CardRank.seven, CardSuit.diamonds),
      ));
      expect(analysis.deadNeededIdentities, {
        _id(CardRank.seven, CardSuit.clubs),
      });
    });

    test('a solo group is never starved — it has nothing to starve', () {
      final analysis = _analysis(
        hand: [
          _c(CardRank.king, CardSuit.hearts),
          _c(CardRank.four, CardSuit.spades),
        ],
      );
      for (final group in analysis.partialGroups) {
        expect(group.kind, PartialGroupKind.solo);
        expect(analysis.isGroupStarved(group), isFalse);
      }
      expect(analysis.neededIdentities, isEmpty);
    });

    test('a joker-only hand starves nothing', () {
      final analysis = _analysis(hand: [_joker(), _joker(index: 1)]);
      expect(analysis.neededIdentities, isEmpty);
      expect(analysis.deadNeededIdentities, isEmpty);
    });
  });

  group('feed risk — the next active anti-clockwise seat', () {
    test('an eliminated seat in between is skipped', () {
      expect(
        FeedRiskAnalysis.nextActiveSeat(
          from: PlayerSeat.south,
          activeSeats: const [
            PlayerSeat.south,
            PlayerSeat.north,
            PlayerSeat.west,
          ],
        ),
        PlayerSeat.north,
      );
    });

    test('the walk wraps around from the last seat', () {
      expect(
        FeedRiskAnalysis.nextActiveSeat(
          from: PlayerSeat.west,
          activeSeats: const [PlayerSeat.south, PlayerSeat.west],
        ),
        PlayerSeat.south,
      );
    });

    test('with nobody else active there is no target, and never itself', () {
      expect(
        FeedRiskAnalysis.nextActiveSeat(
          from: PlayerSeat.east,
          activeSeats: const [PlayerSeat.east],
        ),
        isNull,
      );
      final assessment = FeedRiskAnalysis.assess(
        candidate: _c(CardRank.nine, CardSuit.hearts),
        perspective: PlayerSeat.east,
        activeSeats: const [PlayerSeat.east],
        recentPickups: [_c(CardRank.nine, CardSuit.clubs)],
        targetMelds: const [],
        targetHasOpened: true,
      );
      expect(assessment.target, isNull);
      expect(assessment.isRisky, isFalse);
      expect(assessment.evidence, isEmpty);
    });
  });

  group('feed risk — class A, recent public pickup', () {
    FeedRiskAssessment assess(
      HareegCard candidate, {
      List<HareegCard> pickups = const [],
      List<PlacedMeld> melds = const [],
      bool opened = true,
    }) {
      return FeedRiskAnalysis.assess(
        candidate: candidate,
        perspective: PlayerSeat.south,
        activeSeats: const [
          PlayerSeat.south,
          PlayerSeat.east,
          PlayerSeat.north,
          PlayerSeat.west,
        ],
        recentPickups: pickups,
        targetMelds: melds,
        targetHasOpened: opened,
      );
    }

    test('the target is the next active seat', () {
      final result = assess(
        _c(CardRank.nine, CardSuit.hearts),
        pickups: [_c(CardRank.nine, CardSuit.clubs)],
      );
      expect(result.target, PlayerSeat.east);
    });

    test('same rank as a remembered pickup is evidence', () {
      final result = assess(
        _c(CardRank.nine, CardSuit.hearts),
        pickups: [_c(CardRank.nine, CardSuit.clubs)],
      );
      expect(result.evidence, contains(FeedEvidenceKind.recentPickup));
      expect(result.isRisky, isTrue);
    });

    test('same suit within a run distance of two is evidence', () {
      final result = assess(
        _c(CardRank.seven, CardSuit.clubs),
        pickups: [_c(CardRank.nine, CardSuit.clubs)],
      );
      expect(result.evidence, contains(FeedEvidenceKind.recentPickup));
    });

    test('the high-Ace seam counts: a King pickup relates to an Ace', () {
      final result = assess(
        _c(CardRank.ace, CardSuit.spades),
        pickups: [_c(CardRank.king, CardSuit.spades)],
      );
      expect(result.evidence, contains(FeedEvidenceKind.recentPickup));
    });

    test('the low-Ace seam counts: a Three pickup relates to an Ace', () {
      final result = assess(
        _c(CardRank.ace, CardSuit.spades),
        pickups: [_c(CardRank.three, CardSuit.spades)],
      );
      expect(result.evidence, contains(FeedEvidenceKind.recentPickup));
    });

    test('ranks do not wrap: a King pickup does not relate to a Two', () {
      final result = assess(
        _c(CardRank.two, CardSuit.spades),
        pickups: [_c(CardRank.king, CardSuit.spades)],
      );
      expect(result.isRisky, isFalse);
    });

    test('wrong rank in a different suit is not evidence', () {
      final result = assess(
        _c(CardRank.four, CardSuit.hearts),
        pickups: [_c(CardRank.nine, CardSuit.clubs)],
      );
      expect(result.isRisky, isFalse);
    });

    test('same suit beyond run distance is not evidence', () {
      final result = assess(
        _c(CardRank.five, CardSuit.clubs),
        pickups: [_c(CardRank.nine, CardSuit.clubs)],
      );
      expect(result.isRisky, isFalse);
    });

    test('an empty memory produces no class A evidence', () {
      // Aging is applied by the caller before this point: a pickup outside the
      // tier's memory depth simply is not in the list.
      final result = assess(_c(CardRank.nine, CardSuit.hearts));
      expect(result.isRisky, isFalse);
    });
  });

  group('feed risk — class B, a legal public benefit', () {
    FeedRiskAssessment assess(
      HareegCard candidate, {
      List<PlacedMeld> melds = const [],
      bool opened = true,
    }) {
      return FeedRiskAnalysis.assess(
        candidate: candidate,
        perspective: PlayerSeat.south,
        activeSeats: const [
          PlayerSeat.south,
          PlayerSeat.east,
          PlayerSeat.north,
          PlayerSeat.west,
        ],
        recentPickups: const [],
        targetMelds: melds,
        targetHasOpened: opened,
      );
    }

    test('a legal cover extension is evidence', () {
      final result = assess(
        _c(CardRank.jack, CardSuit.clubs),
        melds: [
          _meld([
            _c(CardRank.eight, CardSuit.clubs),
            _c(CardRank.nine, CardSuit.clubs),
            _c(CardRank.ten, CardSuit.clubs),
          ]),
        ],
      );
      expect(result.evidence, contains(FeedEvidenceKind.coverExtension));
    });

    test('a full four-card set cannot accept another card', () {
      // Sets require distinct suits, so a natural four-card set is maximal.
      // "The target has a visible set of this rank" would have fired here.
      final result = assess(
        _c(CardRank.six, CardSuit.hearts, deckIndex: 1),
        melds: [
          _meld([
            _c(CardRank.six, CardSuit.hearts),
            _c(CardRank.six, CardSuit.clubs),
            _c(CardRank.six, CardSuit.spades),
            _c(CardRank.six, CardSuit.diamonds),
          ]),
        ],
      );
      expect(result.isRisky, isFalse);
    });

    test('a duplicate suit cannot extend a three-card set', () {
      final result = assess(
        _c(CardRank.six, CardSuit.hearts, deckIndex: 1),
        melds: [
          _meld([
            _c(CardRank.six, CardSuit.hearts),
            _c(CardRank.six, CardSuit.clubs),
            _c(CardRank.six, CardSuit.spades),
          ]),
        ],
      );
      expect(result.isRisky, isFalse);
    });

    test('a duplicate identity does not extend a run', () {
      final result = assess(
        _c(CardRank.nine, CardSuit.clubs, deckIndex: 1),
        melds: [
          _meld([
            _c(CardRank.eight, CardSuit.clubs),
            _c(CardRank.nine, CardSuit.clubs),
            _c(CardRank.ten, CardSuit.clubs),
          ]),
        ],
      );
      expect(result.isRisky, isFalse);
    });

    test('a card that extends nothing is not evidence', () {
      final result = assess(
        _c(CardRank.two, CardSuit.diamonds),
        melds: [
          _meld([
            _c(CardRank.eight, CardSuit.clubs),
            _c(CardRank.nine, CardSuit.clubs),
            _c(CardRank.ten, CardSuit.clubs),
          ]),
        ],
      );
      expect(result.isRisky, isFalse);
    });
  });

  group('feed risk — class C, freeing a represented joker', () {
    FeedRiskAssessment assess(
      HareegCard candidate, {
      List<PlacedMeld> melds = const [],
      bool opened = true,
    }) {
      return FeedRiskAnalysis.assess(
        candidate: candidate,
        perspective: PlayerSeat.south,
        activeSeats: const [
          PlayerSeat.south,
          PlayerSeat.east,
          PlayerSeat.north,
          PlayerSeat.west,
        ],
        recentPickups: const [],
        targetMelds: melds,
        targetHasOpened: opened,
      );
    }

    PlacedMeld jokerRun() => PlacedMeld(
      cards: [
        _c(CardRank.eight, CardSuit.spades),
        _joker(represents: _id(CardRank.nine, CardSuit.spades)),
        _c(CardRank.ten, CardSuit.spades),
      ],
      valueSnapshot: 27,
    );

    test('replacing a represented joker is its own evidence class', () {
      final result = assess(
        _c(CardRank.nine, CardSuit.spades),
        melds: [jokerRun()],
      );
      expect(result.evidence, contains(FeedEvidenceKind.jokerReplacement));
      // Asserted separately from cover extension so one cannot stand in for
      // the other: this candidate is not a cover of that run.
      expect(
        result.evidence,
        isNot(contains(FeedEvidenceKind.coverExtension)),
      );
    });

    test('an unopened target cannot legally replace a joker', () {
      final result = assess(
        _c(CardRank.nine, CardSuit.spades),
        melds: [jokerRun()],
        opened: false,
      );
      expect(result.isRisky, isFalse);
    });

    test('a different identity does not free that joker', () {
      final result = assess(
        _c(CardRank.nine, CardSuit.hearts),
        melds: [jokerRun()],
      );
      expect(
        result.evidence,
        isNot(contains(FeedEvidenceKind.jokerReplacement)),
      );
    });

    test(
      'a represented identity feeds the target but does not count as dead',
      () {
        // The two treatments run deliberately opposite. For feed risk the
        // meld shape is public and the benefit real, so the represented
        // identity counts. For card death the physical card is still in play,
        // so it does not.
        final identity = _id(CardRank.nine, CardSuit.spades);
        final melds = {
          PlayerSeat.east: [jokerRun()],
        };

        final feed = assess(
          _c(CardRank.nine, CardSuit.spades),
          melds: melds[PlayerSeat.east]!,
        );
        expect(feed.evidence, contains(FeedEvidenceKind.jokerReplacement));

        final death = _analysis(
          hand: [_c(CardRank.nine, CardSuit.spades)],
          visibleMelds: melds,
        );
        expect(death.accountedCopies(identity), 1);
        expect(death.isDead(identity), isFalse);
      },
    );
  });

  group('feed risk — aging applies to pickups only', () {
    test('a stale pickup dies but a visible meld benefit still fires', () {
      // The caller has already aged the pickup out of memory; the meld is
      // current table state and is never aged.
      final result = FeedRiskAnalysis.assess(
        candidate: _c(CardRank.jack, CardSuit.clubs),
        perspective: PlayerSeat.south,
        activeSeats: const [
          PlayerSeat.south,
          PlayerSeat.east,
          PlayerSeat.north,
          PlayerSeat.west,
        ],
        recentPickups: const [],
        targetMelds: [
          _meld([
            _c(CardRank.eight, CardSuit.clubs),
            _c(CardRank.nine, CardSuit.clubs),
            _c(CardRank.ten, CardSuit.clubs),
          ]),
        ],
        targetHasOpened: true,
      );
      expect(result.evidence, {FeedEvidenceKind.coverExtension});
    });

    test('evidence belonging to another opponent is not the target seat', () {
      // The caller passes the TARGET's pickups and melds. North's tells never
      // reach an assessment aimed at East, because they are not in the input.
      final result = FeedRiskAnalysis.assess(
        candidate: _c(CardRank.nine, CardSuit.hearts),
        perspective: PlayerSeat.south,
        activeSeats: const [
          PlayerSeat.south,
          PlayerSeat.east,
          PlayerSeat.north,
          PlayerSeat.west,
        ],
        recentPickups: const [],
        targetMelds: const [],
        targetHasOpened: true,
      );
      expect(result.target, PlayerSeat.east);
      expect(result.isRisky, isFalse);
    });

    test('the assessment names which evidence fired, per candidate', () {
      final melds = [
        _meld([
          _c(CardRank.eight, CardSuit.clubs),
          _c(CardRank.nine, CardSuit.clubs),
          _c(CardRank.ten, CardSuit.clubs),
        ]),
      ];
      FeedRiskAssessment assess(HareegCard candidate) {
        return FeedRiskAnalysis.assess(
          candidate: candidate,
          perspective: PlayerSeat.south,
          activeSeats: const [
            PlayerSeat.south,
            PlayerSeat.east,
            PlayerSeat.north,
            PlayerSeat.west,
          ],
          recentPickups: [_c(CardRank.four, CardSuit.hearts)],
          targetMelds: melds,
          targetHasOpened: true,
        );
      }

      final cover = assess(_c(CardRank.jack, CardSuit.clubs));
      final pickup = assess(_c(CardRank.four, CardSuit.spades));
      final neither = assess(_c(CardRank.two, CardSuit.diamonds));

      expect(cover.evidence, {FeedEvidenceKind.coverExtension});
      expect(pickup.evidence, {FeedEvidenceKind.recentPickup});
      expect(neither.evidence, isEmpty);
      // Per candidate, so a planner can rank them against each other.
      expect(cover.candidate.effectiveIdentity, _id(CardRank.jack, CardSuit.clubs));
      expect(() => cover.evidence.add(FeedEvidenceKind.recentPickup),
          throwsUnsupportedError);
    });
  });
}
