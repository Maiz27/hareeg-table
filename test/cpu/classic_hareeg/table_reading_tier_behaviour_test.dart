import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/casual_cpu_move_planner.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_move_plan.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_observation.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_table_reading.dart';
import 'package:hareeg_table/cpu/classic_hareeg/expert_cpu_move_planner.dart';
import 'package:hareeg_table/cpu/classic_hareeg/priority_cpu_move_planner.dart';
import 'package:hareeg_table/cpu/classic_hareeg/skilled_cpu_move_planner.dart';
import 'package:hareeg_table/domain/classic_hareeg/analysis/table_reading_analysis.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_discard_history.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

HareegCard _c(CardRank rank, CardSuit suit, {int deckIndex = 0}) =>
    HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);

String _discardAction(HareegCard card) =>
    '${ClassicHareegActionIds.discardPrefix}${card.id}';

const _allSeats = [
  PlayerSeat.south,
  PlayerSeat.east,
  PlayerSeat.north,
  PlayerSeat.west,
];

/// A south-seat action-phase position whose only legal moves are discards, so
/// every tier lands on its discard comparator and the plan names the card the
/// tier chose to shed.
CpuObservationFacts _position({
  required CpuDifficulty difficulty,
  required List<HareegCard> hand,
  List<HareegCard> discardPile = const [],
  int? discardCount,
  Map<PlayerSeat, List<PlacedMeld>> tableMelds = const {},
  DiscardHistoryView discardHistory = const EmptyDiscardHistoryView(),
  Map<PlayerSeat, int> handCounts = const {},
  List<PlayerSeat> activeSeats = _allSeats,
  int stockCount = 22,
  int roundNumber = 1,
  int deckCopyCount = 2,
}) {
  return CpuObservationFacts(
    seat: PlayerSeat.south,
    difficulty: difficulty,
    legalActionIds: [for (final card in hand) _discardAction(card)],
    turnPhase: TurnPhase.action,
    ownHand: hand,
    handCounts: handCounts,
    tableMelds: tableMelds,
    stockCount: stockCount,
    discardCount: discardCount ?? discardPile.length,
    discardPile: discardPile,
    roundNumber: roundNumber,
    deckCopyCount: deckCopyCount,
    activeSeats: activeSeats,
    discardHistory: discardHistory,
    openingState: const OpeningState(
      baseRequirement: 30,
      currentRequirement: 30,
      openedSeats: {PlayerSeat.south, PlayerSeat.east},
    ),
  );
}

ClassicHareegCpuMovePlan _plan(CpuObservation observation) {
  return switch (observation.difficulty) {
    CpuDifficulty.beginner => const PriorityCpuMovePlanner().plan(observation),
    CpuDifficulty.casual => const CasualCpuMovePlanner().plan(observation),
    CpuDifficulty.skilled => const SkilledCpuMovePlanner().plan(observation),
    CpuDifficulty.expert => const ExpertCpuMovePlanner().plan(observation),
  };
}

String _shed(CpuObservation observation) {
  final plan = _plan(observation);
  expect(
    observation.legalActionIds,
    contains(plan.actionId),
    reason: 'a tier must never plan an action the rules did not offer',
  );
  return plan.actionId!;
}

DiscardHistory _pickups(Map<PlayerSeat, List<HareegCard>> bySeat) {
  final history = DiscardHistory();
  for (final entry in bySeat.entries) {
    for (final card in entry.value) {
      history.recordPickup(entry.key, card);
    }
  }
  return history;
}

// --- The material fixture -------------------------------------------------
//
// Queens are starved: both remaining suits are fully accounted for in the
// pile, so the Q-pair can never become a set. Jacks are the equal-pip control
// with live completions.

final _queenHearts = _c(CardRank.queen, CardSuit.hearts);
final _queenSpades = _c(CardRank.queen, CardSuit.spades);
final _jackHearts = _c(CardRank.jack, CardSuit.hearts);
final _jackSpades = _c(CardRank.jack, CardSuit.spades);

final _materialHand = [_jackHearts, _jackSpades, _queenHearts, _queenSpades];

final _queensDeadPile = [
  _c(CardRank.queen, CardSuit.clubs),
  _c(CardRank.queen, CardSuit.clubs, deckIndex: 1),
  _c(CardRank.queen, CardSuit.diamonds),
  _c(CardRank.queen, CardSuit.diamonds, deckIndex: 1),
];

CpuObservationFacts _materialPosition(
  CpuDifficulty difficulty, {
  required bool queensDead,
  int stockCount = 22,
}) {
  return _position(
    difficulty: difficulty,
    hand: _materialHand,
    discardPile: queensDead ? _queensDeadPile : const [],
    // Held equal so the attention key — and therefore Casual's gate — cannot
    // shift between the signal and no-signal halves of a pair.
    discardCount: _queensDeadPile.length,
    stockCount: stockCount,
  );
}

// --- The feed fixture -----------------------------------------------------
//
// East is the next active seat. It has opened and is down to three cards, so
// the legacy threat profile has stopped reading its pile pickups entirely —
// which is what lets the new next-seat signal be varied while every legacy
// danger value stays pinned at zero.

final _nineHearts = _c(CardRank.nine, CardSuit.hearts);
final _fourSpades = _c(CardRank.four, CardSuit.spades);
final _feedHand = [_nineHearts, _fourSpades];

List<HareegCard> _fillerPickups(int count) => [
  for (var index = 0; index < count; index += 1)
    _c(CardRank.king, CardSuit.values[index % 4], deckIndex: index ~/ 4),
];

/// East's pickups with the tell about the four at [depthFromNewest].
///
/// Depth 1 is the newest pickup. The relevant tell is a four, which relates to
/// the `4♠` candidate by rank.
DiscardHistory _feedHistory({required int depthFromNewest}) {
  final older = _fillerPickups(8);
  final tell = _c(CardRank.four, CardSuit.hearts);
  final ordered = <HareegCard>[
    ...older.take(8 - depthFromNewest),
    tell,
    ...older.skip(8 - depthFromNewest).take(depthFromNewest - 1),
  ];
  return _pickups({PlayerSeat.east: ordered});
}

void main() {
  group('Beginner ignores both signals', () {
    test('its plan is identical with and without either signal', () {
      final withSignals = _position(
        difficulty: CpuDifficulty.beginner,
        hand: _materialHand,
        discardPile: _queensDeadPile,
        discardCount: _queensDeadPile.length,
        discardHistory: _feedHistory(depthFromNewest: 1),
        handCounts: const {PlayerSeat.east: 3},
      );
      final withoutSignals = _position(
        difficulty: CpuDifficulty.beginner,
        hand: _materialHand,
        discardCount: _queensDeadPile.length,
        handCounts: const {PlayerSeat.east: 3},
      );

      // Both signals would move a table-aware tier on this position.
      expect(
        CpuTableReading.forObservation(
          _materialPosition(CpuDifficulty.skilled, queensDead: true),
        ).availableStarvedCardIds,
        isNotEmpty,
      );
      expect(_shed(withSignals), _shed(withoutSignals));
    });

    test('no pickup memory exists to age, at any depth', () {
      expect(TableReadingPolicy.beginner.pickupMemoryDepth, 0);
      String? plan;
      for (var depth = 1; depth <= 8; depth += 1) {
        final observation = _position(
          difficulty: CpuDifficulty.beginner,
          hand: _feedHand,
          discardHistory: _feedHistory(depthFromNewest: depth),
          handCounts: const {PlayerSeat.east: 3},
        );
        final reading = CpuTableReading.forObservation(observation);
        expect(reading.availableFeedRiskFor(_fourSpades).isRisky, isFalse);
        expect(reading.appliedFeedRiskFor(_fourSpades), isNull);
        plan ??= _shed(observation);
        expect(_shed(observation), plan);
      }
    });
  });

  group('the material signal changes a plan', () {
    test('Skilled sheds a starved card over an equal-pip live one', () {
      // Both candidates are worth ten pips. The queens can never complete;
      // the jacks still can.
      expect(_queenHearts.identity!.rank.value, _jackHearts.identity!.rank.value);

      final blind = _materialPosition(CpuDifficulty.skilled, queensDead: false);
      final seeing = _materialPosition(CpuDifficulty.skilled, queensDead: true);

      expect(_shed(blind), _discardAction(_jackHearts));
      expect(_shed(seeing), _discardAction(_queenHearts));
    });

    test('Expert sheds the starved card too', () {
      expect(
        _shed(_materialPosition(CpuDifficulty.expert, queensDead: true)),
        _discardAction(_queenHearts),
      );
      expect(
        _shed(_materialPosition(CpuDifficulty.expert, queensDead: false)),
        isNot(_discardAction(_queenHearts)),
      );
    });

    test('a card in a finished meld is never called a dead draw', () {
      // The grouping runs over the leftovers of the best complete-meld
      // partition, so a seat holding a finished set of sevens is not told its
      // sevens are starved because the fourth seven is gone.
      final hand = [
        _c(CardRank.seven, CardSuit.hearts),
        _c(CardRank.seven, CardSuit.spades),
        _c(CardRank.seven, CardSuit.clubs),
        _c(CardRank.two, CardSuit.diamonds),
      ];
      final observation = _position(
        difficulty: CpuDifficulty.expert,
        hand: hand,
        discardPile: [
          _c(CardRank.seven, CardSuit.diamonds),
          _c(CardRank.seven, CardSuit.diamonds, deckIndex: 1),
        ],
      );
      final reading = CpuTableReading.forObservation(observation);
      expect(reading.availableStarvedCardIds, isEmpty);
    });
  });

  group('Casual applies material only, on a sampled 40% of positions', () {
    test('its policy attends material at depth one and never feed risk', () {
      expect(TableReadingPolicy.casual.attendsMaterialSignal, isTrue);
      expect(TableReadingPolicy.casual.attendsFeedRisk, isFalse);
      expect(TableReadingPolicy.casual.pickupMemoryDepth, 1);
    });

    test('an attended position sheds the starved card, an ignored one does not', () {
      // Two positions differing only in stock count, one either side of the
      // attention gate. The same starved queens are visible in both.
      final attended = _casualStock(applied: true);
      final ignored = _casualStock(applied: false);

      expect(
        _shed(_materialPosition(CpuDifficulty.casual, queensDead: true,
            stockCount: attended)),
        _discardAction(_queenHearts),
      );
      // Ignored: Casual falls back to its own highest-pip rule, which cannot
      // separate four ten-pip cards and settles on the first action id.
      expect(
        _shed(_materialPosition(CpuDifficulty.casual, queensDead: true,
            stockCount: ignored)),
        _discardAction(_jackHearts),
      );
    });

    test('feed availability moves between depth one and two, Casual does not', () {
      // The tell sits second-newest: inside a two-deep memory, outside a
      // one-deep one. Casual's memory is one.
      final history = _feedHistory(depthFromNewest: 2);
      final observation = _position(
        difficulty: CpuDifficulty.casual,
        hand: _feedHand,
        discardHistory: history,
        handCounts: const {PlayerSeat.east: 3},
      );

      FeedRiskAssessment availableAt(int depth) {
        return FeedRiskAnalysis.assess(
          candidate: _fourSpades,
          perspective: PlayerSeat.south,
          activeSeats: _allSeats,
          recentPickups: history.lastPickupsBy(PlayerSeat.east, depth).toList(),
          targetMelds: const [],
          targetHasOpened: true,
        );
      }

      // Availability differs across the boundary...
      expect(availableAt(1).isRisky, isFalse);
      expect(availableAt(2).isRisky, isTrue);

      // ...while Casual's attention, application, and plan do not move.
      final reading = CpuTableReading.forObservation(observation);
      expect(reading.policy.attendsFeedRisk, isFalse);
      expect(reading.appliedFeedRiskFor(_fourSpades), isNull);
      expect(reading.isFeedRisk(_fourSpades), isFalse);
      expect(
        _shed(observation),
        _shed(
          _position(
            difficulty: CpuDifficulty.casual,
            hand: _feedHand,
            handCounts: const {PlayerSeat.east: 3},
          ),
        ),
      );
    });

    test('Casual still makes a discard Skilled avoids', () {
      // Degradation asserted positively, not as an absence of evidence: East
      // is visibly collecting nines, and Casual throws one anyway because its
      // rule is "shed the biggest pip".
      final history = _pickups({
        PlayerSeat.east: [_c(CardRank.nine, CardSuit.clubs)],
      });
      CpuObservationFacts position(CpuDifficulty difficulty) => _position(
        difficulty: difficulty,
        hand: _feedHand,
        discardHistory: history,
      );

      expect(_shed(position(CpuDifficulty.casual)),
          _discardAction(_nineHearts));
      expect(_shed(position(CpuDifficulty.skilled)),
          _discardAction(_fourSpades));
    });
  });

  group('Skilled applies material and refuses the feed signal', () {
    test('its policy attends material always, feed never, memory three', () {
      expect(TableReadingPolicy.skilled.attendsMaterialSignal, isTrue);
      expect(TableReadingPolicy.skilled.materialAttentionPercent, 100);
      expect(TableReadingPolicy.skilled.attendsFeedRisk, isFalse);
      expect(TableReadingPolicy.skilled.pickupMemoryDepth, 3);
    });

    test('varying only the feed result leaves the plan untouched', () {
      // East's visible meld is the only difference. Under the new rules the
      // jack is a legal cover of East's club run and so a feed risk; Skilled
      // does not consume that value and plans the same move either way.
      final risky = _skilledFeedPosition(coverable: true);
      final safe = _skilledFeedPosition(coverable: false);

      expect(
        CpuTableReading.forObservation(
          _position(
            difficulty: CpuDifficulty.expert,
            hand: risky.ownHand,
            tableMelds: risky.tableMelds,
          ),
        ).isFeedRisk(_c(CardRank.jack, CardSuit.clubs)),
        isTrue,
      );
      expect(
        CpuTableReading.forObservation(risky).appliedFeedRiskFor(
          _c(CardRank.jack, CardSuit.clubs),
        ),
        isNull,
      );
      expect(_shed(risky), _shed(safe));
    });

    test('its own three-pickup hot-rank tiebreak is still alive', () {
      // The legacy read is preserved, not replaced: a nine picked up three
      // turns ago still steers the discard, and one picked up four turns ago
      // no longer does.
      final inWindow = _pickups({
        PlayerSeat.east: [
          _c(CardRank.nine, CardSuit.clubs),
          _c(CardRank.king, CardSuit.hearts),
          _c(CardRank.king, CardSuit.spades),
        ],
      });
      final outOfWindow = _pickups({
        PlayerSeat.east: [
          _c(CardRank.nine, CardSuit.clubs),
          _c(CardRank.king, CardSuit.hearts),
          _c(CardRank.king, CardSuit.spades),
          _c(CardRank.king, CardSuit.diamonds),
        ],
      });

      expect(
        _shed(
          _position(
            difficulty: CpuDifficulty.skilled,
            hand: _feedHand,
            discardHistory: inWindow,
          ),
        ),
        _discardAction(_fourSpades),
        reason: 'the nine is hot at depth three, so it is held back',
      );
      expect(
        _shed(
          _position(
            difficulty: CpuDifficulty.skilled,
            hand: _feedHand,
            discardHistory: outOfWindow,
          ),
        ),
        _discardAction(_nineHearts),
        reason: 'a fourth pickup ages the nine out and the pip rule returns',
      );
    });
  });

  group('Expert applies both, and the feed signal participates on its own', () {
    test('its policy attends both at memory six', () {
      expect(TableReadingPolicy.expert.attendsMaterialSignal, isTrue);
      expect(TableReadingPolicy.expert.attendsFeedRisk, isTrue);
      expect(TableReadingPolicy.expert.pickupMemoryDepth, 6);
    });

    test('the new feed value changes the choice with legacy danger held equal', () {
      // The pair differs only in whether East's visible three-card set is on
      // the table. A set produces no legacy run-end threat and East has no
      // readable pickups, so every legacy danger value is zero on both sides —
      // the old comparator cannot be what moved.
      final withSet = _expertCoverPosition(setOnTable: true);
      final withoutSet = _expertCoverPosition(setOnTable: false);
      final fourDiamonds = _c(CardRank.four, CardSuit.diamonds);

      final dangerWith = OpponentThreatProfile.fromObservation(withSet);
      final dangerWithout = OpponentThreatProfile.fromObservation(withoutSet);
      for (final card in [fourDiamonds, _nineHearts]) {
        expect(dangerWith.dangerScore(card), 0);
        expect(dangerWithout.dangerScore(card), 0);
        expect(dangerWith.avoidFeedingScore(card), 0);
        expect(dangerWithout.avoidFeedingScore(card), 0);
      }

      // Only the new signal moves.
      expect(
        CpuTableReading.forObservation(withSet).isFeedRisk(fourDiamonds),
        isTrue,
      );
      expect(
        CpuTableReading.forObservation(withoutSet).isFeedRisk(fourDiamonds),
        isFalse,
      );

      expect(_shed(withoutSet), _discardAction(fourDiamonds));
      expect(_shed(withSet), _discardAction(_nineHearts));
    });

    test('the feed value and the plan move across the six-deep boundary', () {
      // East has opened and is down to three cards, so the legacy profile has
      // stopped reading its pickups altogether. That pins legacy danger at
      // zero while the new signal's six-deep memory is exercised.
      final inMemory = _expertMemoryPosition(depthFromNewest: 6);
      final outOfMemory = _expertMemoryPosition(depthFromNewest: 7);

      final dangerIn = OpponentThreatProfile.fromObservation(inMemory);
      final dangerOut = OpponentThreatProfile.fromObservation(outOfMemory);
      for (final card in _feedHand) {
        expect(dangerIn.dangerScore(card), dangerOut.dangerScore(card));
        expect(dangerIn.dangerScore(card), 0);
      }

      expect(
        CpuTableReading.forObservation(inMemory).isFeedRisk(_fourSpades),
        isTrue,
      );
      expect(
        CpuTableReading.forObservation(outOfMemory).isFeedRisk(_fourSpades),
        isFalse,
      );

      expect(_shed(outOfMemory), _discardAction(_fourSpades));
      expect(_shed(inMemory), _discardAction(_nineHearts));
    });
  });

  group('the legacy Expert posture is frozen', () {
    PlacedMeld clubRun() => PlacedMeld.fromCards([
      _c(CardRank.eight, CardSuit.clubs),
      _c(CardRank.nine, CardSuit.clubs),
      _c(CardRank.ten, CardSuit.clubs),
    ]);

    OpponentThreatProfile profileWith({
      List<HareegCard> pickups = const [],
      List<PlacedMeld> melds = const [],
      int score = 0,
      int handCount = 9,
    }) {
      return OpponentThreatProfile.fromObservation(
        _position(
          difficulty: CpuDifficulty.expert,
          hand: _feedHand,
          tableMelds: {PlayerSeat.east: melds},
          discardHistory: _pickups({PlayerSeat.east: pickups}),
          handCounts: {PlayerSeat.east: handCount},
        ).copyWithScores({PlayerSeat.east: score}),
      );
    }

    test('the pickup window is still six deep', () {
      final sevenDeep = [
        _c(CardRank.nine, CardSuit.hearts),
        ..._fillerPickups(6),
      ];
      final sixDeep = [
        _c(CardRank.nine, CardSuit.hearts),
        ..._fillerPickups(5),
      ];
      expect(profileWith(pickups: sevenDeep).dangerScore(_nineHearts), 0);
      expect(
        profileWith(pickups: sixDeep).dangerScore(_nineHearts),
        greaterThan(0),
      );
    });

    test('the danger weight ladder is unchanged', () {
      // run-end 120 > near identity 90 > near rank 45 > identity 35 >
      // near suit 20 > rank 15 > suit 5, applied cumulatively.
      expect(
        profileWith(melds: [clubRun()]).dangerScore(
          _c(CardRank.jack, CardSuit.clubs),
        ),
        120,
      );
      expect(
        profileWith(pickups: [_nineHearts]).dangerScore(_nineHearts),
        35 + 15,
      );
      expect(
        profileWith(pickups: [_nineHearts], score: 25).dangerScore(_nineHearts),
        90 + 45 + 35 + 15,
      );
      expect(
        profileWith(pickups: [_c(CardRank.nine, CardSuit.clubs)])
            .dangerScore(_c(CardRank.ten, CardSuit.clubs)),
        5,
      );
      expect(profileWith().dangerScore(_nineHearts), 0);
    });

    test('a joker still reads as flat danger forty', () {
      expect(
        profileWith().dangerScore(
          HareegCard.joker(deckIndex: 0, jokerIndex: 0),
        ),
        40,
      );
    });

    test('a seat that has stopped collecting drops its pickup tells', () {
      expect(
        profileWith(pickups: [_nineHearts], handCount: 3)
            .dangerScore(_nineHearts),
        0,
      );
      expect(
        profileWith(pickups: [_nineHearts], handCount: 4)
            .dangerScore(_nineHearts),
        greaterThan(0),
      );
    });

    test('avoid-feeding still weights an elimination target hardest', () {
      expect(
        profileWith(pickups: [_nineHearts]).avoidFeedingScore(_nineHearts),
        1,
      );
      expect(
        profileWith(pickups: [_nineHearts], score: 25)
            .avoidFeedingScore(_nineHearts),
        2,
      );
      expect(
        profileWith(pickups: [_nineHearts], score: 28)
            .avoidFeedingScore(_nineHearts),
        3,
      );
    });
  });

  group('no tier can plan an illegal action', () {
    test('every tier stays inside the legal set on every fixture', () {
      final fixtures = <CpuObservationFacts Function(CpuDifficulty)>[
        (difficulty) => _materialPosition(difficulty, queensDead: true),
        (difficulty) => _materialPosition(difficulty, queensDead: false),
        (difficulty) => _expertCoverPosition(
          setOnTable: true,
          difficulty: difficulty,
        ),
        (difficulty) => _expertMemoryPosition(
          depthFromNewest: 6,
          difficulty: difficulty,
        ),
        (difficulty) => _position(
          difficulty: difficulty,
          hand: _feedHand,
          activeSeats: const [PlayerSeat.south],
        ),
      ];

      for (final fixture in fixtures) {
        for (final difficulty in CpuDifficulty.values) {
          final observation = fixture(difficulty);
          final plan = _plan(observation);
          expect(plan.actionId, isNotNull);
          expect(observation.legalActionIds, contains(plan.actionId));
        }
      }
    });
  });
}

/// A stock count whose attention bucket puts the material fixture on the
/// wanted side of Casual's gate.
int _casualStock({required bool applied}) {
  for (var stock = 1; stock < 200; stock += 1) {
    final observation = _materialPosition(
      CpuDifficulty.casual,
      queensDead: true,
      stockCount: stock,
    );
    if (TableReadingPolicy.casual.appliesMaterialSignalAt(observation) ==
        applied) {
      return stock;
    }
  }
  fail('no stock count produced an ${applied ? 'attended' : 'ignored'} gate');
}

/// A Skilled position whose only variable is whether East's visible meld can
/// accept the jack of clubs.
CpuObservationFacts _skilledFeedPosition({required bool coverable}) {
  return _position(
    difficulty: CpuDifficulty.skilled,
    hand: [_c(CardRank.jack, CardSuit.clubs), _c(CardRank.three, CardSuit.hearts)],
    tableMelds: {
      PlayerSeat.east: [
        coverable
            ? PlacedMeld.fromCards([
                _c(CardRank.eight, CardSuit.clubs),
                _c(CardRank.nine, CardSuit.clubs),
                _c(CardRank.ten, CardSuit.clubs),
              ])
            : PlacedMeld.fromCards([
                _c(CardRank.five, CardSuit.hearts),
                _c(CardRank.five, CardSuit.clubs),
                _c(CardRank.five, CardSuit.spades),
              ]),
      ],
    },
  );
}

/// An Expert position where East's visible three-card set makes the four of
/// diamonds a legal public benefit, while producing no legacy run-end threat.
CpuObservationFacts _expertCoverPosition({
  required bool setOnTable,
  CpuDifficulty difficulty = CpuDifficulty.expert,
}) {
  return _position(
    difficulty: difficulty,
    hand: [_nineHearts, _c(CardRank.four, CardSuit.diamonds)],
    tableMelds: {
      PlayerSeat.east: [
        if (setOnTable)
          PlacedMeld.fromCards([
            _c(CardRank.four, CardSuit.hearts),
            _c(CardRank.four, CardSuit.clubs),
            _c(CardRank.four, CardSuit.spades),
          ]),
      ],
    },
  );
}

/// An Expert position whose only variable is how deep East's four-tell sits.
CpuObservationFacts _expertMemoryPosition({
  required int depthFromNewest,
  CpuDifficulty difficulty = CpuDifficulty.expert,
}) {
  return _position(
    difficulty: difficulty,
    hand: _feedHand,
    discardHistory: _feedHistory(depthFromNewest: depthFromNewest),
    handCounts: const {PlayerSeat.east: 3},
  );
}

extension on CpuObservationFacts {
  /// The same position with visible scores applied.
  CpuObservationFacts copyWithScores(Map<PlayerSeat, int> scores) {
    return CpuObservationFacts(
      seat: seat,
      difficulty: difficulty,
      legalActionIds: legalActionIds,
      turnPhase: turnPhase,
      ownHand: ownHand,
      handCounts: {
        for (final entry in _allSeats)
          if (entry != seat) entry: handCountFor(entry),
      },
      tableMelds: tableMelds,
      stockCount: stockCount,
      discardCount: discardCount,
      discardPile: discardPile,
      roundNumber: roundNumber,
      deckCopyCount: deckCopyCount,
      activeSeats: activeSeats,
      discardHistory: discardHistory,
      openingState: openingState,
      opponentScores: scores,
    );
  }
}
