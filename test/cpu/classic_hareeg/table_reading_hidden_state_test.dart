import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/casual_cpu_move_planner.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_move_plan.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_observation.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_table_reading.dart';
import 'package:hareeg_table/cpu/classic_hareeg/expert_cpu_move_planner.dart';
import 'package:hareeg_table/cpu/classic_hareeg/priority_cpu_move_planner.dart';
import 'package:hareeg_table/cpu/classic_hareeg/skilled_cpu_move_planner.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

/// Hidden-information invariance, proven where hidden state actually exists.
///
/// The analysis signature having no parameter for an opponent hand is an
/// architectural exclusion, not a proof — an explicit-value API cannot leak
/// what it was never handed. The question that matters is whether a *planner*,
/// standing at a live table that really does hold hidden hands and a hidden
/// stock, can be moved by them. So each case below builds a pair of live
/// controllers whose public face is identical to the last card and whose
/// hidden state is entirely different, and runs the real planners over the
/// real adapter.
HareegCard _c(CardRank rank, CardSuit suit, {int deckIndex = 0}) =>
    HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);

/// East's hand — the perspective seat, and the only hand the CPU may read.
final _eastHand = [
  _c(CardRank.queen, CardSuit.hearts),
  _c(CardRank.queen, CardSuit.spades),
  _c(CardRank.jack, CardSuit.hearts),
  _c(CardRank.jack, CardSuit.spades),
  _c(CardRank.four, CardSuit.diamonds),
];

/// The public pile: every queen of clubs and diamonds is accounted for, so
/// East's queens are a starved pair and the material signal has something to
/// say on this position.
final _discardPile = [
  _c(CardRank.queen, CardSuit.clubs),
  _c(CardRank.queen, CardSuit.clubs, deckIndex: 1),
  _c(CardRank.queen, CardSuit.diamonds),
  _c(CardRank.queen, CardSuit.diamonds, deckIndex: 1),
  _c(CardRank.three, CardSuit.spades),
];

/// North's visible run — public, and identical in both halves of every pair.
final _northMeld = PlacedMeld.fromCards([
  _c(CardRank.six, CardSuit.clubs),
  _c(CardRank.seven, CardSuit.clubs),
  _c(CardRank.eight, CardSuit.clubs),
]);

final _legalActionIds = [
  for (final card in _eastHand)
    '${ClassicHareegActionIds.discardPrefix}${card.id}',
];

ClassicHareegGameController _controller({
  required Map<PlayerSeat, List<HareegCard>> hiddenHands,
  required List<HareegCard> stock,
}) {
  return ClassicHareegGameController.fromSnapshot(
    ClassicHareegMatchSnapshot(
      setup: ClassicHareegSetup.defaults(),
      hands: {PlayerSeat.east: _eastHand, ...hiddenHands},
      stock: stock,
      discardPile: _discardPile,
      tableMelds: {
        PlayerSeat.north: [_northMeld],
      },
      starter: PlayerSeat.east,
      currentSeat: PlayerSeat.east,
      turnPhase: TurnPhase.action,
      openingState: const OpeningState(
        baseRequirement: 30,
        currentRequirement: 30,
        openedSeats: {PlayerSeat.east, PlayerSeat.north},
      ),
      scores: const {
        PlayerSeat.south: 4,
        PlayerSeat.east: 7,
        PlayerSeat.north: 11,
        PlayerSeat.west: 2,
      },
      savedAt: DateTime.utc(2026, 6, 1),
    ),
  );
}

LiveCpuObservation _observe(
  ClassicHareegGameController controller,
  CpuDifficulty difficulty,
) {
  return LiveCpuObservation(
    controller: controller,
    seat: PlayerSeat.east,
    legalActionIds: _legalActionIds,
    difficulty: difficulty,
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

/// Everything the CPU is allowed to see, rendered as a comparable string.
String _publicFace(CpuObservation observation) {
  return [
    observation.seat.name,
    observation.turnPhase.name,
    observation.roundNumber,
    observation.stockCount,
    observation.discardCount,
    observation.deckCopyCount,
    observation.currentOpeningRequirement,
    observation.ownHand.map((card) => card.id).join(','),
    observation.discardPile.map((card) => card.id).join(','),
    observation.legalActionIds.join(','),
    for (final seat in PlayerSeat.values)
      '${seat.name}:${observation.handCountFor(seat)}'
      ':${observation.scoreFor(seat)}'
      ':${observation.hasOpened(seat)}'
      ':${observation.tableMeldsFor(seat).map((meld) => meld.cards.map((card) => card.id).join('+')).join('/')}',
  ].join('|');
}

/// The signals themselves, rendered as a comparable string.
String _signals(CpuObservation observation) {
  final reading = CpuTableReading.forObservation(observation);
  final starved = reading.availableStarvedCardIds.toList()..sort();
  final feed = [
    for (final card in observation.ownHand)
      '${card.id}='
      '${(reading.availableFeedRiskFor(card).evidence.map((kind) => kind.name).toList()..sort()).join('+')}',
  ];
  final dead = reading.analysis.deadNeededIdentities
      .map((identity) => identity.key)
      .toList()
    ..sort();
  return [
    'target=${reading.feedTarget?.name}',
    'starved=${starved.join(',')}',
    'dead=${dead.join(',')}',
    'feed=${feed.join(',')}',
  ].join('|');
}

void _expectIndistinguishable(
  ClassicHareegGameController left,
  ClassicHareegGameController right, {
  required String because,
}) {
  for (final difficulty in CpuDifficulty.values) {
    final a = _observe(left, difficulty);
    final b = _observe(right, difficulty);

    expect(
      _publicFace(a),
      _publicFace(b),
      reason: 'the pair must be publicly identical ($because)',
    );
    expect(
      _signals(a),
      _signals(b),
      reason: 'the computed signals moved with hidden state ($because)',
    );
    expect(
      _plan(a).actionId,
      _plan(b).actionId,
      reason: '${difficulty.name} changed its plan with hidden state ($because)',
    );
    expect(
      _plan(a).scenario,
      _plan(b).scenario,
      reason: '${difficulty.name} changed its branch ($because)',
    );
  }
}

void main() {
  group('a planner cannot be moved by what it cannot see', () {
    test('different opponent hand contents at identical counts', () {
      // Both hidden hands hold four cards. One is a near-finished club run
      // sitting right on top of the cards East is holding; the other is
      // scattered low junk. A planner that peeked would not play these two
      // positions the same way.
      final left = _controller(
        hiddenHands: {
          PlayerSeat.south: [
            _c(CardRank.nine, CardSuit.clubs),
            _c(CardRank.ten, CardSuit.clubs),
            _c(CardRank.jack, CardSuit.clubs),
            _c(CardRank.jack, CardSuit.diamonds),
          ],
          PlayerSeat.north: [
            _c(CardRank.queen, CardSuit.hearts, deckIndex: 1),
            _c(CardRank.queen, CardSuit.spades, deckIndex: 1),
            _c(CardRank.two, CardSuit.hearts),
            _c(CardRank.two, CardSuit.spades),
          ],
          PlayerSeat.west: [
            _c(CardRank.ace, CardSuit.clubs),
            _c(CardRank.ace, CardSuit.diamonds),
            _c(CardRank.ace, CardSuit.hearts),
            _c(CardRank.king, CardSuit.clubs),
          ],
        },
        stock: _stockA(),
      );
      final right = _controller(
        hiddenHands: {
          PlayerSeat.south: [
            _c(CardRank.two, CardSuit.diamonds),
            _c(CardRank.five, CardSuit.hearts),
            _c(CardRank.eight, CardSuit.diamonds),
            _c(CardRank.king, CardSuit.diamonds),
          ],
          PlayerSeat.north: [
            _c(CardRank.three, CardSuit.hearts),
            _c(CardRank.six, CardSuit.diamonds),
            _c(CardRank.nine, CardSuit.diamonds),
            _c(CardRank.ten, CardSuit.hearts),
          ],
          PlayerSeat.west: [
            _c(CardRank.four, CardSuit.hearts),
            _c(CardRank.seven, CardSuit.hearts),
            _c(CardRank.ten, CardSuit.diamonds),
            _c(CardRank.king, CardSuit.hearts),
          ],
        },
        stock: _stockA(),
      );

      _expectIndistinguishable(
        left,
        right,
        because: 'opponent hand contents differ',
      );
    });

    test('different hidden stock identities and order at a fixed count', () {
      // The visible stock count is the same; what is in it, and the order it
      // will come out in, is entirely different. That is also the future
      // transcript: these two tables will play out as different games.
      final hidden = {
        PlayerSeat.south: [
          _c(CardRank.two, CardSuit.diamonds),
          _c(CardRank.five, CardSuit.hearts),
          _c(CardRank.eight, CardSuit.diamonds),
          _c(CardRank.king, CardSuit.diamonds),
        ],
        PlayerSeat.north: [
          _c(CardRank.three, CardSuit.hearts),
          _c(CardRank.six, CardSuit.diamonds),
          _c(CardRank.nine, CardSuit.diamonds),
          _c(CardRank.ten, CardSuit.hearts),
        ],
        PlayerSeat.west: [
          _c(CardRank.four, CardSuit.hearts),
          _c(CardRank.seven, CardSuit.hearts),
          _c(CardRank.ten, CardSuit.diamonds),
          _c(CardRank.king, CardSuit.hearts),
        ],
      };

      final left = _controller(hiddenHands: hidden, stock: _stockA());
      final right = _controller(hiddenHands: hidden, stock: _stockB());

      expect(_stockA().length, _stockB().length);
      expect(
        _stockA().map((card) => card.id).toSet(),
        isNot(_stockB().map((card) => card.id).toSet()),
      );
      _expectIndistinguishable(
        left,
        right,
        because: 'stock identities and order differ',
      );
    });

    test('a different future cannot reach back into the present plan', () {
      // The same visible position, then the two tables actually diverge: one
      // is advanced by a real action, the other is not. The plan computed for
      // the original position is unchanged, because nothing downstream of it
      // is an input.
      final hidden = {
        PlayerSeat.south: [
          _c(CardRank.two, CardSuit.diamonds),
          _c(CardRank.five, CardSuit.hearts),
          _c(CardRank.eight, CardSuit.diamonds),
          _c(CardRank.king, CardSuit.diamonds),
        ],
        PlayerSeat.north: [
          _c(CardRank.three, CardSuit.hearts),
          _c(CardRank.six, CardSuit.diamonds),
          _c(CardRank.nine, CardSuit.diamonds),
          _c(CardRank.ten, CardSuit.hearts),
        ],
        PlayerSeat.west: [
          _c(CardRank.four, CardSuit.hearts),
          _c(CardRank.seven, CardSuit.hearts),
          _c(CardRank.ten, CardSuit.diamonds),
          _c(CardRank.king, CardSuit.hearts),
        ],
      };

      for (final difficulty in CpuDifficulty.values) {
        final controller = _controller(hiddenHands: hidden, stock: _stockA());
        final before = _plan(_observe(controller, difficulty));
        final signalsBefore = _signals(_observe(controller, difficulty));

        final rerun = _controller(hiddenHands: hidden, stock: _stockA());
        final replayed = _plan(_observe(rerun, difficulty));

        expect(replayed.actionId, before.actionId);
        expect(_signals(_observe(rerun, difficulty)), signalsBefore);

        // Advance one table by the very action the tier chose, then recompute
        // the original position from a fresh controller. The answer is the
        // same, so no future entry has fed backwards.
        final advanced = _controller(hiddenHands: hidden, stock: _stockA());
        advanced.applyAction(before.actionId!);
        expect(advanced.turnPhase, isNot(TurnPhase.action));

        final fresh = _controller(hiddenHands: hidden, stock: _stockA());
        expect(_plan(_observe(fresh, difficulty)).actionId, before.actionId);
      }
    });
  });

  group('the pair really is a pair', () {
    test('the fixture positions differ only below the public surface', () {
      // A guard against the invariance claim passing because the two halves
      // were accidentally identical.
      final left = _controller(
        hiddenHands: {
          PlayerSeat.south: [
            _c(CardRank.nine, CardSuit.clubs),
            _c(CardRank.ten, CardSuit.clubs),
            _c(CardRank.jack, CardSuit.clubs),
            _c(CardRank.jack, CardSuit.diamonds),
          ],
          PlayerSeat.north: [
            _c(CardRank.queen, CardSuit.hearts, deckIndex: 1),
            _c(CardRank.queen, CardSuit.spades, deckIndex: 1),
            _c(CardRank.two, CardSuit.hearts),
            _c(CardRank.two, CardSuit.spades),
          ],
          PlayerSeat.west: [
            _c(CardRank.ace, CardSuit.clubs),
            _c(CardRank.ace, CardSuit.diamonds),
            _c(CardRank.ace, CardSuit.hearts),
            _c(CardRank.king, CardSuit.clubs),
          ],
        },
        stock: _stockA(),
      );
      final right = _controller(
        hiddenHands: {
          PlayerSeat.south: [
            _c(CardRank.two, CardSuit.diamonds),
            _c(CardRank.five, CardSuit.hearts),
            _c(CardRank.eight, CardSuit.diamonds),
            _c(CardRank.king, CardSuit.diamonds),
          ],
          PlayerSeat.north: [
            _c(CardRank.three, CardSuit.hearts),
            _c(CardRank.six, CardSuit.diamonds),
            _c(CardRank.nine, CardSuit.diamonds),
            _c(CardRank.ten, CardSuit.hearts),
          ],
          PlayerSeat.west: [
            _c(CardRank.four, CardSuit.hearts),
            _c(CardRank.seven, CardSuit.hearts),
            _c(CardRank.ten, CardSuit.diamonds),
            _c(CardRank.king, CardSuit.hearts),
          ],
        },
        stock: _stockB(),
      );

      for (final seat in [PlayerSeat.south, PlayerSeat.north, PlayerSeat.west]) {
        expect(
          left.handFor(seat).map((card) => card.id),
          isNot(right.handFor(seat).map((card) => card.id)),
        );
        expect(left.cardCountFor(seat), right.cardCountFor(seat));
      }
      expect(left.stockCount, right.stockCount);
    });

    test('the signals on this position are not vacuously empty', () {
      final controller = _controller(
        hiddenHands: {
          PlayerSeat.south: [
            _c(CardRank.two, CardSuit.diamonds),
            _c(CardRank.five, CardSuit.hearts),
            _c(CardRank.eight, CardSuit.diamonds),
            _c(CardRank.king, CardSuit.diamonds),
          ],
          PlayerSeat.north: [
            _c(CardRank.three, CardSuit.hearts),
            _c(CardRank.six, CardSuit.diamonds),
            _c(CardRank.nine, CardSuit.diamonds),
            _c(CardRank.ten, CardSuit.hearts),
          ],
          PlayerSeat.west: [
            _c(CardRank.four, CardSuit.hearts),
            _c(CardRank.seven, CardSuit.hearts),
            _c(CardRank.ten, CardSuit.diamonds),
            _c(CardRank.king, CardSuit.hearts),
          ],
        },
        stock: _stockA(),
      );
      final reading = CpuTableReading.forObservation(
        _observe(controller, CpuDifficulty.expert),
      );

      expect(reading.feedTarget, PlayerSeat.north);
      expect(
        reading.availableStarvedCardIds,
        containsAll([_eastHand[0].id, _eastHand[1].id]),
        reason: 'the queens are starved on this position',
      );
    });
  });
}

List<HareegCard> _stockA() => [
  _c(CardRank.two, CardSuit.clubs),
  _c(CardRank.three, CardSuit.diamonds),
  _c(CardRank.five, CardSuit.spades),
  _c(CardRank.seven, CardSuit.diamonds),
  _c(CardRank.nine, CardSuit.spades),
  _c(CardRank.jack, CardSuit.clubs, deckIndex: 1),
];

List<HareegCard> _stockB() => [
  _c(CardRank.king, CardSuit.spades),
  _c(CardRank.ten, CardSuit.spades),
  _c(CardRank.eight, CardSuit.spades),
  _c(CardRank.six, CardSuit.spades),
  _c(CardRank.four, CardSuit.spades),
  _c(CardRank.two, CardSuit.spades),
];
