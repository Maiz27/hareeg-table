import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/classic_hareeg_cpu_turn_runner.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_strategy.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/strictness_rule_profile.dart';

/// Regression suite for the CPU "mistake loop" bug.
///
/// The original bug: a CPU seat in an action-phase state where their only
/// discard candidates were cover cards (e.g. all-cover hand after picking up
/// a discard) would loop on a `discard-blocked-cover:<card>` action under
/// Strict tier. The action surface advertised the id (because
/// `MistakeResolution.isAllowed` is true on Strict/Table), the Priority planner
/// picked it via the fallback branch, the controller applied a Strict-tier
/// mistake (penalty +3, action reverted, card stayed in hand, turn did NOT
/// advance), and the runner re-polled the same surface — burning the safety
/// cap on consecutive penalties (~64 attempts × 3 = ~192 points).
///
/// The contract: `StrictnessRuleProfile.cpuMistakesAllowed` is true ONLY for
/// `TableStrictness.table`. On Coaching, Standard, and Strict, the CPU action
/// surface must never expose a mistake-class action id — even if the human
/// `legalActionIdsFor` surface still does (Strict's coaching loop relies on
/// the human being able to attempt the penalised discard).
void main() {
  group('CPU action surface refuses mistakes off-Table', () {
    for (final tier in TableStrictness.values) {
      test(
        '${tier.name}: cpuActionIdsFor never exposes discard-blocked-cover '
        'when cpuMistakesAllowed is false',
        () {
          final fixture = _coverTrapFixture(tier);
          final controller = ClassicHareegGameController.fromSnapshot(
            fixture.snapshot,
          );

          final cpuActions = controller.cpuActionIdsFor(fixture.cpuSeat);
          final humanActions = controller.legalActionIdsFor(fixture.cpuSeat);
          final blockedCoverIds = cpuActions
              .where(
                (id) => id.startsWith(
                  ClassicHareegActionIds.discardBlockedCoverPrefix,
                ),
              )
              .toList();

          if (tier.cpuMistakesAllowed) {
            // Table tier: CPU may attempt cover discards as paid mistakes.
            expect(
              blockedCoverIds,
              isNotEmpty,
              reason:
                  '${tier.name} permits CPU mistakes, so the cpu surface '
                  'should still expose discard-blocked-cover ids.',
            );
          } else {
            expect(
              blockedCoverIds,
              isEmpty,
              reason:
                  '${tier.name}: cpuMistakesAllowed=false so the CPU action '
                  'surface must filter out discard-blocked-cover:* ids. '
                  'Without this filter the Priority planner picks one as a '
                  'fallback, the controller applies a reverted Strict-tier '
                  'penalty, and the runner loops on it.',
            );
          }

          if (tier == TableStrictness.strict) {
            // Strict tier still advertises the same id to humans (the
            // coaching loop relies on it). The filter is CPU-surface-only.
            expect(
              humanActions.any(
                (id) => id.startsWith(
                  ClassicHareegActionIds.discardBlockedCoverPrefix,
                ),
              ),
              isTrue,
              reason:
                  'Strict must still advertise the cover discard to humans '
                  'so the +3 coaching toast can fire.',
            );
          }
        },
      );
    }

    test(
      'strict: CPU one-turn run picks the plain discard, no penalty applied',
      () async {
        final fixture = _coverTrapFixture(TableStrictness.strict);
        final controller = ClassicHareegGameController.fromSnapshot(
          fixture.snapshot,
        );
        final scoreBefore = controller.scores[fixture.cpuSeat] ?? 0;
        final handBefore = controller.cardCountFor(fixture.cpuSeat);

        final result = await ClassicHareegCpuTurnRunner(
          controller: controller,
          strategy: const _PriorityStrategy(),
          // East is the acting CPU; the runner stops as soon as the turn
          // returns to the human seat (south).
          humanSeat: PlayerSeat.south,
          actionLimit: 8,
        ).run();

        final scoreAfter = controller.scores[fixture.cpuSeat] ?? 0;
        // Lower score is better in Hareeg — a mistake penalty ADDS +3 to
        // the seat's score. A successful finish, by contrast, hands the
        // winner -1. The mistake-loop signature is the score going UP.
        expect(
          scoreAfter,
          lessThanOrEqualTo(scoreBefore),
          reason:
              'BUG: CPU score went up under cpuMistakesAllowed=false — '
              'the Strict mistake penalty (+3) must never fire for a CPU. '
              'Before=$scoreBefore after=$scoreAfter delta='
              '${scoreAfter - scoreBefore}.',
        );
        expect(
          result.appliedDecisions.any(
            (decision) => decision.actionId.startsWith(
              ClassicHareegActionIds.discardBlockedCoverPrefix,
            ),
          ),
          isFalse,
          reason:
              'BUG: CPU runner must not apply any discard-blocked-cover '
              'action when cpuMistakesAllowed=false.',
        );
        // The CPU's hand must have shrunk by at least one (they discarded
        // something legally). Don't pin the exact value — a meld play or
        // a normal finish might have removed more cards.
        expect(
          controller.cardCountFor(fixture.cpuSeat),
          lessThan(handBefore),
          reason: 'CPU hand must have shrunk after a legal action.',
        );
      },
    );

    test(
      'watchdog: 20 randomized CPU runs under strict never apply a '
      'mistake-class action and never hit the safety cap',
      () async {
        // Walk 20 fresh deals, run the CPU loop, and assert two invariants
        // per pass:
        //   1. No applied decision starts with a mistake-class prefix
        //      (`discard-blocked-cover:` or `discard-joker:`).
        //   2. The runner does not exit via the safety cap — that is the
        //      direct signature of the planner advertising a leaky id and
        //      the controller looping on the reverted result.
        // The runner's own invariant guard (it throws StateError on a
        // reverted CPU result) also catches a leak earlier than these
        // assertions, but the explicit check documents the intent.
        for (var seed = 0; seed < 20; seed += 1) {
          final setup = ClassicHareegSetup.defaults().copyWith(
            tableStrictness: TableStrictness.strict,
          );
          final controller = ClassicHareegGameController.fromRound(
            ClassicHareegRound.deal(setup: setup, seed: seed),
          );

          final result = await ClassicHareegCpuTurnRunner(
            controller: controller,
            strategy: const _PriorityStrategy(),
            humanSeat: PlayerSeat.south,
            actionLimit: 32,
          ).run();

          for (final decision in result.appliedDecisions) {
            expect(
              decision.actionId.startsWith(
                ClassicHareegActionIds.discardBlockedCoverPrefix,
              ),
              isFalse,
              reason:
                  'seed=$seed: CPU ${decision.seat.name} applied a '
                  'mistake-class action ${decision.actionId} under strict '
                  'tier — that is the planner leak signature.',
            );
            expect(
              decision.actionId.startsWith(
                ClassicHareegActionIds.discardJokerPrefix,
              ),
              isFalse,
              reason:
                  'seed=$seed: CPU ${decision.seat.name} applied a '
                  'mistake-class joker-discard action ${decision.actionId} '
                  'under strict tier.',
            );
          }
          expect(
            result.reachedSafetyLimit,
            isFalse,
            reason:
                'seed=$seed: runner hit the safety cap under strict — that '
                'is the loop signature.',
          );
        }
      },
    );
  });
}

class _CoverTrapFixture {
  const _CoverTrapFixture({
    required this.snapshot,
    required this.cpuSeat,
    required this.coverCards,
    required this.safeCard,
  });

  final ClassicHareegMatchSnapshot snapshot;
  final PlayerSeat cpuSeat;
  final List<HareegCard> coverCards;
  final HareegCard safeCard;
}

/// Builds a snapshot where [PlayerSeat.east] is on turn (action phase),
/// already opened, and holds several cards that are covers for a 5C-6C-7C
/// table meld owned by south plus exactly one safe (non-cover) card. Under
/// Strict / Table tiers `discard-blocked-cover:*` is advertised for every
/// cover card; under Coaching / Standard those ids are suppressed.
_CoverTrapFixture _coverTrapFixture(TableStrictness tier) {
  final setup = ClassicHareegSetup.defaults().copyWith(tableStrictness: tier);
  final round = ClassicHareegRound.deal(setup: setup, seed: 5);

  // 5C-6C-7C: south's already-placed meld. 4C, 8C, 9C, 10C in east's hand
  // are all covers of that run.
  final southMeld = [
    _card(CardRank.five, CardSuit.clubs, 80),
    _card(CardRank.six, CardSuit.clubs, 80),
    _card(CardRank.seven, CardSuit.clubs, 80),
  ];
  final coverCards = [
    _card(CardRank.four, CardSuit.clubs, 81),
    _card(CardRank.eight, CardSuit.clubs, 81),
    _card(CardRank.nine, CardSuit.clubs, 81),
    _card(CardRank.ten, CardSuit.clubs, 81),
  ];
  // One plain, non-cover card so the seat has at least one legal discard
  // even after filtering mistake-class ids. The 2 of hearts cannot extend
  // the clubs sequence on the table.
  final safeCard = _card(CardRank.two, CardSuit.hearts, 82);

  final eastHand = [...coverCards, safeCard];

  return _CoverTrapFixture(
    snapshot: ClassicHareegMatchSnapshot(
      setup: setup,
      hands: {
        ...{
          for (final seat in PlayerSeat.values)
            seat: List<HareegCard>.of(round.hands[seat] ?? const []),
        },
        PlayerSeat.east: eastHand,
      },
      stock: round.stock,
      discardPile: round.discardPile,
      tableMelds: {
        PlayerSeat.south: [
          PlacedMeld(
            cards: List<HareegCard>.unmodifiable(southMeld),
            valueSnapshot: 51,
          ),
        ],
      },
      starter: round.starter,
      currentSeat: PlayerSeat.east,
      turnPhase: TurnPhase.action,
      openingState: _openedFor([PlayerSeat.south, PlayerSeat.east]),
      savedAt: DateTime.utc(2026, 5, 24),
    ),
    cpuSeat: PlayerSeat.east,
    coverCards: coverCards,
    safeCard: safeCard,
  );
}

OpeningState _openedFor(Iterable<PlayerSeat> seats) {
  var state = OpeningState.initial(51);
  for (final seat in seats) {
    state = ClassicHareegOpeningRules.applyOpening(
      state: state,
      seat: seat,
      melds: [const PlacedMeld(cards: [], valueSnapshot: 51)],
    );
  }
  return state;
}

HareegCard _card(CardRank rank, CardSuit suit, int deckIndex) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}

/// Mirrors the production planner's priority-order behavior closely enough
/// to reproduce the bug: when no high-value action is available, it falls
/// back to the first non-claim-fifty legal action — which is exactly the
/// path that picks `discard-blocked-cover:*` if the surface leaks it.
class _PriorityStrategy implements CpuStrategy {
  const _PriorityStrategy();

  @override
  CpuMoveIntent chooseMove(
    CpuTurnSnapshot snapshot, {
    CpuObservation? observation,
  }) {
    final ids = snapshot.legalActionIds;
    // Pick the first id that is not a claim-fifty (matches Priority planner
    // claim filtering when no finishing partition is available).
    for (final id in ids) {
      if (id == ClassicHareegActionIds.claimFifty) continue;
      return CpuMoveIntent(actionId: id);
    }
    return CpuMoveIntent(actionId: ids.first);
  }
}
