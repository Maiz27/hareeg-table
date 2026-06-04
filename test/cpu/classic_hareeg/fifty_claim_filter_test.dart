import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_move_planner.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_observation.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_strategy.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_score_ledger.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

/// Regression for the "CPU spam-claims Fifty in a loop" bug.
///
/// The rules engine advertises `claim-fifty` whenever the Fifty window is
/// open and points at the seat — even when the seat has no provable finish,
/// because human players still need the affordance to attempt a wrong claim
/// (penalty + lose-turn under Strict / Table). For a CPU the upside of
/// attempting a wrong claim is zero (it eats a penalty and the next loop tick
/// re-advertises the same claim-fifty), so each planner must filter it back
/// out when the seat lacks a finishing partition.
///
/// The bug surfaced as CPU East racking up huge scores (240 in Round 1) from
/// looping a wrong Fifty claim. This file pins the filter into Skilled,
/// Expert, and Priority planners.
void main() {
  group('CPU Fifty filter — claim-fifty without finishing partition', () {
    test(
      'SkilledCpuMovePlanner.plan does not return claim-fifty without proof',
      () {
        const planner = SkilledCpuMovePlanner();
        final plan = planner.plan(
          _FakeCpuObservation(
            legalActionIds: const [
              ClassicHareegActionIds.claimFifty,
              ClassicHareegActionIds.drawStock,
            ],
            ownIsFiftyClaimant: true,
            topDiscard: _card(CardRank.nine, CardSuit.clubs),
            turnPhase: TurnPhase.draw,
          ),
        );

        expect(
          plan.actionId,
          isNot(ClassicHareegActionIds.claimFifty),
          reason:
              'BUG: Skilled must drop claim-fifty when no finishing '
              'partition exists. Without this filter the CPU loops a wrong '
              'claim and inflates the score.',
        );
      },
    );

    test(
      'ExpertCpuMovePlanner.plan does not return claim-fifty without proof',
      () {
        const planner = ExpertCpuMovePlanner();
        final plan = planner.plan(
          _FakeCpuObservation(
            legalActionIds: const [
              ClassicHareegActionIds.claimFifty,
              ClassicHareegActionIds.drawStock,
            ],
            ownIsFiftyClaimant: true,
            topDiscard: _card(CardRank.nine, CardSuit.clubs),
            turnPhase: TurnPhase.draw,
          ),
        );

        expect(
          plan.actionId,
          isNot(ClassicHareegActionIds.claimFifty),
          reason:
              'BUG: Expert must drop claim-fifty when no finishing '
              'partition exists.',
        );
      },
    );

    test(
      'PriorityCpuMovePlanner.plan does not return claim-fifty without proof',
      () {
        const planner = PriorityCpuMovePlanner();
        final plan = planner.plan(
          _FakeCpuObservation(
            legalActionIds: const [
              ClassicHareegActionIds.claimFifty,
              ClassicHareegActionIds.drawStock,
            ],
            ownIsFiftyClaimant: true,
            topDiscard: _card(CardRank.nine, CardSuit.clubs),
            turnPhase: TurnPhase.draw,
          ),
        );

        expect(
          plan.actionId,
          isNot(ClassicHareegActionIds.claimFifty),
          reason:
              'BUG: Priority.plan must drop claim-fifty when no finishing '
              'partition exists.',
        );
      },
    );

    test(
      'all three planners still return claim-fifty when a finish exists',
      () {
        final discarded = _card(CardRank.nine, CardSuit.clubs);
        final sevenClubs = _card(CardRank.seven, CardSuit.clubs);
        final eightClubs = _card(CardRank.eight, CardSuit.clubs);
        final finalDiscard = _card(CardRank.two, CardSuit.hearts);
        final finish = _partition(
          [
            [sevenClubs, eightClubs, discarded],
          ],
          remaining: [finalDiscard],
        );
        final observation = _FakeCpuObservation(
          legalActionIds: const [
            ClassicHareegActionIds.claimFifty,
            ClassicHareegActionIds.drawStock,
          ],
          ownIsFiftyClaimant: true,
          topDiscard: discarded,
          ownHand: [sevenClubs, eightClubs, finalDiscard],
          turnPhase: TurnPhase.draw,
          finishingPartition: finish,
          difficultyProfile: const CpuDifficultyProfile(
            difficulty: CpuDifficulty.skilled,
            fiftyReactionMillis: 0,
            fiftyMissChance: 0,
          ),
        );

        expect(
          const SkilledCpuMovePlanner().plan(observation).actionId,
          ClassicHareegActionIds.claimFifty,
          reason: 'Skilled keeps Fifty when the finish is provable',
        );
        expect(
          const ExpertCpuMovePlanner().plan(observation).actionId,
          ClassicHareegActionIds.claimFifty,
          reason: 'Expert keeps Fifty when the finish is provable',
        );
        expect(
          const PriorityCpuMovePlanner().plan(observation).actionId,
          ClassicHareegActionIds.claimFifty,
          reason: 'Priority keeps Fifty when the finish is provable',
        );
      },
    );

    test('Skilled chooseMove drops claim-fifty without a finish', () {
      // chooseMove for Skilled routes through plan(), so the same filter
      // must hold at the public boundary.
      const strategy = ClassicHareegCpuStrategy();
      final intent = strategy.chooseMove(
        CpuTurnSnapshot(
          seat: PlayerSeat.east,
          difficulty: CpuDifficulty.skilled,
          legalActionIds: const [
            ClassicHareegActionIds.claimFifty,
            ClassicHareegActionIds.drawStock,
          ],
        ),
        observation: _FakeCpuObservation(
          legalActionIds: const [
            ClassicHareegActionIds.claimFifty,
            ClassicHareegActionIds.drawStock,
          ],
          ownIsFiftyClaimant: true,
          topDiscard: _card(CardRank.nine, CardSuit.clubs),
          turnPhase: TurnPhase.draw,
        ),
      );

      expect(intent.actionId, isNot(ClassicHareegActionIds.claimFifty));
    });

    test('Expert chooseMove drops claim-fifty without a finish', () {
      const strategy = ClassicHareegCpuStrategy();
      final intent = strategy.chooseMove(
        CpuTurnSnapshot(
          seat: PlayerSeat.east,
          difficulty: CpuDifficulty.expert,
          legalActionIds: const [
            ClassicHareegActionIds.claimFifty,
            ClassicHareegActionIds.drawStock,
          ],
        ),
        observation: _FakeCpuObservation(
          legalActionIds: const [
            ClassicHareegActionIds.claimFifty,
            ClassicHareegActionIds.drawStock,
          ],
          ownIsFiftyClaimant: true,
          topDiscard: _card(CardRank.nine, CardSuit.clubs),
          turnPhase: TurnPhase.draw,
        ),
      );

      expect(intent.actionId, isNot(ClassicHareegActionIds.claimFifty));
    });
  });
}

HareegCard _card(CardRank rank, CardSuit suit, [int deckIndex = 1]) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}

MeldPartition _partition(
  List<List<HareegCard>> melds, {
  List<HareegCard> remaining = const [],
}) {
  final placed = melds.map(PlacedMeld.fromCards).toList(growable: false);
  return MeldPartition(
    melds: placed,
    cardsUsed: placed.expand((meld) => meld.cards),
    cardsRemaining: remaining,
    jokerAssignments: const [],
  );
}

/// Minimal CpuObservation fake matching the one used in
/// skilled_cpu_move_planner_test.dart. Kept local so the regression test file
/// is self-contained. Only the inputs actually exercised by Fifty filtering
/// are exposed as constructor parameters; the rest are stable defaults.
final class _FakeCpuObservation implements CpuObservation {
  _FakeCpuObservation({
    Iterable<String> legalActionIds = const [],
    this.turnPhase = TurnPhase.action,
    this.topDiscard,
    Iterable<HareegCard> ownHand = const [],
    MeldPartition? finishingPartition,
    CpuDifficultyProfile? difficultyProfile,
    this.ownIsFiftyClaimant = false,
  }) : legalActionIds = List.unmodifiable(legalActionIds),
       ownHand = List.unmodifiable(ownHand),
       _difficultyProfile = difficultyProfile,
       _finishingPartition = finishingPartition;

  @override
  CpuDifficulty get difficulty => CpuDifficulty.skilled;

  @override
  final List<String> legalActionIds;

  @override
  final TurnPhase turnPhase;

  @override
  HareegCard? get pendingDiscard => null;

  @override
  final List<HareegCard> ownHand;

  @override
  int get stockCount => 20;

  @override
  final HareegCard? topDiscard;

  @override
  OpeningState get openingState => const OpeningState(
    baseRequirement: 30,
    currentRequirement: 30,
    openedSeats: {PlayerSeat.east},
  );

  @override
  DiscardHistoryView get discardHistory => const EmptyDiscardHistoryView();

  @override
  MeldPartitionView get partitions => const EmptyMeldPartitionView();

  final MeldPartition? _finishingPartition;
  final CpuDifficultyProfile? _difficultyProfile;

  @override
  int get ownScore => 0;

  @override
  final bool ownIsFiftyClaimant;

  @override
  int get eliminationThreshold => 31;

  @override
  PlayerSeat get seat => PlayerSeat.east;

  @override
  int handCountFor(PlayerSeat seat) => seat == this.seat ? ownHand.length : 0;

  @override
  List<PlacedMeld> tableMeldsFor(PlayerSeat seat) => const [];

  @override
  Map<PlayerSeat, List<PlacedMeld>> get tableMelds => const {};

  @override
  int get tableMeldCount => 0;

  @override
  int get discardCount => 0;

  @override
  bool hasOpened(PlayerSeat seat) => openingState.hasOpened(seat);

  @override
  bool ownHasOpened() => hasOpened(seat);

  @override
  PlayerSeat? get benchmarkOwner => openingState.benchmarkOwner;

  @override
  int get currentOpeningRequirement => openingState.currentRequirement;

  @override
  ClassicHareegScoreView get scoreView {
    return ClassicHareegScoreView(
      previousScores: {seat: ownScore},
      currentScores: {seat: ownScore},
    );
  }

  @override
  int scoreFor(PlayerSeat seat) => scoreView.currentScores[seat] ?? 0;

  @override
  List<PlayerSeat> get activeSeats => const [
    PlayerSeat.south,
    PlayerSeat.east,
    PlayerSeat.north,
    PlayerSeat.west,
  ];

  @override
  PlayerSeat get currentSeat => seat;

  @override
  List<PlayerSeat> get opponents => const [
    PlayerSeat.north,
    PlayerSeat.west,
    PlayerSeat.south,
  ];

  @override
  PlayerSeat? get fiftyClaimant => ownIsFiftyClaimant ? seat : null;

  @override
  int? get fiftySecondsRemaining => ownIsFiftyClaimant ? 3 : null;

  @override
  MeldPartition? shortestSingleMeld() {
    for (final partition in partitions.enumerate(maxMelds: 1)) {
      return partition;
    }
    return null;
  }

  @override
  MeldPartition? finishingPartition() {
    if (_finishingPartition != null) {
      return _finishingPartition;
    }
    for (final partition in partitions.enumerate()) {
      if (partition.cardsRemaining.length == 1) {
        return partition;
      }
    }
    return null;
  }

  @override
  CpuDifficultyProfile get difficultyProfile {
    return _difficultyProfile ?? CpuDifficultyProfile.forDifficulty(difficulty);
  }
}
