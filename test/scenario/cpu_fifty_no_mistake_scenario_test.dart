import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_observation.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_strategy.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';

import 'classic_hareeg_scenario.dart';

/// Regression for the CPU Fifty-claim mistake leak found by the full-match
/// invariant sweep.
///
/// On mistake-allowing tiers (Strict/Table) the rules engine advertises
/// `claim-fifty` even for a hopeless claim, so a human can opt into a paid
/// wrong-claim. `claim-fifty` is not a static mistake-class id, so the CPU
/// mistake filter could not strip it — and the strategic planners' optimistic
/// `finishingPartition()` made the CPU *take* the wrong claim, charging itself a
/// penalty and (on Table tier) removing itself from the round. The priority
/// planner instead returned no choice, crashing the strategy.
///
/// Fix: `cpuActionIdsFor` strips a `claim-fifty` that is not a real finish for
/// the seat, and `_evaluateRoundEnd` draws the round on stock exhaustion when
/// only a hopeless claim remains, so a CPU claimant is never stranded.
void main() {
  final fixedClock = DateTime.utc(2026, 1, 1, 12, 0, 0);
  DateTime now() => fixedClock;

  // South cannot finish with the top discard (2 of spades): no meld uses it and
  // the hand cannot partition into melds + one final discard.
  final unwinnableTopDiscard = ScenarioCards.card(
    CardRank.two,
    CardSuit.spades,
    deckIndex: 3,
  );
  final southStuckHand = <HareegCard>[
    ScenarioCards.card(CardRank.four, CardSuit.hearts, deckIndex: 3),
    ScenarioCards.card(CardRank.seven, CardSuit.clubs, deckIndex: 3),
    ScenarioCards.card(CardRank.nine, CardSuit.diamonds, deckIndex: 3),
    ScenarioCards.card(CardRank.jack, CardSuit.spades, deckIndex: 3),
    ScenarioCards.card(CardRank.queen, CardSuit.hearts, deckIndex: 3),
  ];

  // South finishes with the top discard (AC): {AC,AD,AH}+{2S,2D,2H},
  // final discard 5C. This fixture is also noticed by every configured CPU
  // difficulty's deterministic Fifty miss gate.
  final winningTopDiscard = ScenarioCards.card(
    CardRank.ace,
    CardSuit.clubs,
    deckIndex: 0,
  );
  final southWinningHand = <HareegCard>[
    ScenarioCards.card(CardRank.ace, CardSuit.diamonds),
    ScenarioCards.card(CardRank.ace, CardSuit.hearts),
    ScenarioCards.card(CardRank.two, CardSuit.spades),
    ScenarioCards.card(CardRank.two, CardSuit.diamonds),
    ScenarioCards.card(CardRank.two, CardSuit.hearts),
    ScenarioCards.card(CardRank.five, CardSuit.clubs),
  ];

  ClassicHareegScenario dealClaim({
    required List<HareegCard> southHand,
    required HareegCard topDiscard,
    required TableStrictness strictness,
    CpuDifficulty difficulty = CpuDifficulty.casual,
    List<HareegCard>? stock,
  }) {
    return ClassicHareegScenario.deal(
      setup: ClassicHareegSetup.defaults().copyWith(
        cpuDifficulty: difficulty,
        tableStrictness: strictness,
      ),
      southHand: southHand,
      discardPile: [topDiscard],
      stock: stock,
      currentSeat: PlayerSeat.south,
      turnPhase: TurnPhase.draw,
      openingState: ScenarioCards.openedFor(PlayerSeat.south),
      roundNumber: 2,
      fiftyWindowOpenedAt: fixedClock,
      now: now,
    );
  }

  group('CPU Fifty mistake leak (Table tier)', () {
    test(
      'a hopeless Fifty claim is offered to the human but never to the CPU',
      () {
        final s = dealClaim(
          southHand: southStuckHand,
          topDiscard: unwinnableTopDiscard,
          strictness: TableStrictness.table,
        );
        final c = s.controller;
        expect(c.fiftyClaimant, PlayerSeat.south);

        // Human surface still advertises the claim (opt-in paid mistake).
        expect(
          c.legalActionIdsFor(PlayerSeat.south),
          contains(ClassicHareegActionIds.claimFifty),
          reason: 'the human may still attempt a paid wrong claim',
        );

        // CPU surface must NOT — claiming would be a guaranteed self-penalty
        // (and on Table tier, self-removal).
        final cpuActions = c.cpuActionIdsFor(PlayerSeat.south);
        expect(
          cpuActions,
          isNot(contains(ClassicHareegActionIds.claimFifty)),
          reason: 'the CPU must never be offered a wrong Fifty claim',
        );
        // It still has a real move available (stock is non-empty here).
        expect(cpuActions, contains(ClassicHareegActionIds.drawStock));
      },
    );

    test(
      'a valid Fifty finish IS offered to the CPU (it should claim to win)',
      () {
        final s = dealClaim(
          southHand: southWinningHand,
          topDiscard: winningTopDiscard,
          strictness: TableStrictness.table,
        );
        final c = s.controller;
        expect(c.fiftyClaimant, PlayerSeat.south);
        expect(
          c.cpuActionIdsFor(PlayerSeat.south),
          contains(ClassicHareegActionIds.claimFifty),
          reason: 'a genuine winning Fifty must remain on the CPU surface',
        );
      },
    );

    for (final difficulty in CpuDifficulty.values) {
      test(
        '$difficulty CPU strategy claims and completes a valid Fifty finish',
        () {
          final s = dealClaim(
            southHand: southWinningHand,
            topDiscard: winningTopDiscard,
            strictness: TableStrictness.table,
            difficulty: difficulty,
          );
          final c = s.controller;
          final legal = c.cpuActionIdsFor(PlayerSeat.south);
          const strategy = ClassicHareegCpuStrategy();

          final intent = strategy.chooseMove(
            CpuTurnSnapshot(
              seat: PlayerSeat.south,
              legalActionIds: legal,
              difficulty: c.setup.cpuDifficulty,
            ),
            observation: LiveCpuObservation(
              controller: c,
              seat: PlayerSeat.south,
              legalActionIds: legal,
              difficulty: c.setup.cpuDifficulty,
            ),
          );

          expect(intent.actionId, ClassicHareegActionIds.claimFifty);
          final result = c.applyAction(intent.actionId);
          expect(result.isSuccess, isTrue, reason: result.message);

          // Prove-it flow: the claim takes the card; the CPU then plays the
          // proof out step by step through the same strategy loop.
          expect(c.isFiftyProofTurn, isTrue);
          var safety = 0;
          while (!c.isRoundOver && safety < 24) {
            final proofLegal = c.cpuActionIdsFor(PlayerSeat.south);
            expect(
              proofLegal,
              isNotEmpty,
              reason: 'proof surface must offer the next step',
            );
            final proofIntent = strategy.chooseMove(
              CpuTurnSnapshot(
                seat: PlayerSeat.south,
                legalActionIds: proofLegal,
                difficulty: c.setup.cpuDifficulty,
              ),
              observation: LiveCpuObservation(
                controller: c,
                seat: PlayerSeat.south,
                legalActionIds: proofLegal,
                difficulty: c.setup.cpuDifficulty,
              ),
            );
            final stepResult = c.applyAction(proofIntent.actionId);
            expect(stepResult.isSuccess, isTrue, reason: stepResult.message);
            safety += 1;
          }
          expect(c.isRoundOver, isTrue);
          expect(c.roundOutcome, RoundOutcomeType.fiftyFinish);
        },
      );
    }

    test(
      'stock-exhausted hopeless Fifty draws the round instead of stranding the '
      'CPU',
      () {
        // Stock empty + south cannot finish + no pickup finish: the only thing
        // the engine would otherwise advertise is the hopeless claim. The round
        // must resolve as a draw so the CPU is never left with no legal move.
        final s = dealClaim(
          southHand: southStuckHand,
          topDiscard: unwinnableTopDiscard,
          strictness: TableStrictness.table,
          stock: const [],
        );
        final c = s.controller;

        expect(
          c.isRoundOver,
          isTrue,
          reason: 'stock-exhausted hopeless Fifty state must end the round',
        );
        expect(c.roundOutcome, RoundOutcomeType.draw);
      },
    );
  });
}
