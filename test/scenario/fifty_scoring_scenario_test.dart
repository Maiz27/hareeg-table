import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';

import 'classic_hareeg_scenario.dart';

/// Deterministic Fifty (Khamsin) scoring scenarios.
///
/// The user reports that Fifty claims "keep missing adding the penalties and
/// bonuses to the score". These tests drive the *real* controller through a
/// genuinely-valid Fifty finish and a wrong Fifty claim, then assert the exact
/// score deltas documented in
/// `match_progression_rules.dart::applyRoundResult` reach the persisted score.
///
/// Scoring contract for a Fifty (Khamsin) finish (lines ~92-118 of
/// match_progression_rules.dart):
///   * winner          -> -3   (or -1 when firstRoundFiftyException, round 1)
///   * fifty discarder -> remainingCardCount + 3
///   * every other     -> remainingCardCount
///
/// Window restoration (classic_hareeg_match_restoration.dart): a Fifty window
/// is reopened when `discardPile.isNotEmpty && turnPhase == TurnPhase.draw`,
/// and the discarder is inferred as `currentSeat.previousAntiClockwise`. For a
/// south claimant the inferred discarder is therefore WEST.
void main() {
  // Fixed clock. `fiftyWindowOpenedAt` is set to the same instant so the 4s
  // window (default fiftyTimerSeconds) is still open (elapsed == 0).
  final fixedClock = DateTime.utc(2026, 1, 1, 12, 0, 0);
  DateTime now() => fixedClock;

  // --- South's winning Fifty hand --------------------------------------
  //
  // Top discard = 3 of clubs (the card WEST "discarded"). South finishes by
  // partitioning hand + top-discard into two melds plus exactly one final
  // discard:
  //   meld A (set of 3s): 3C(top discard) + 3D + 3H
  //   meld B (set of Ks): KS + KD + KH
  //   final discard:      9S
  // The discard (3C) is genuinely used in meld A, satisfying the
  // "Fifty must use the discarded card" rule.
  final topDiscardThreeClubs =
      ScenarioCards.card(CardRank.three, CardSuit.clubs, deckIndex: 1);
  final southWinningHand = <HareegCard>[
    ScenarioCards.card(CardRank.three, CardSuit.diamonds, deckIndex: 1),
    ScenarioCards.card(CardRank.three, CardSuit.hearts, deckIndex: 1),
    ScenarioCards.card(CardRank.king, CardSuit.spades, deckIndex: 1),
    ScenarioCards.card(CardRank.king, CardSuit.diamonds, deckIndex: 1),
    ScenarioCards.card(CardRank.king, CardSuit.hearts, deckIndex: 1),
    ScenarioCards.card(CardRank.nine, CardSuit.spades, deckIndex: 1),
  ];

  // Deterministic small hands for the other seats so remaining-card counts are
  // exactly known: east=2, north=2, west=2.
  final eastHand = <HareegCard>[
    ScenarioCards.card(CardRank.four, CardSuit.clubs, deckIndex: 2),
    ScenarioCards.card(CardRank.five, CardSuit.diamonds, deckIndex: 2),
  ];
  final northHand = <HareegCard>[
    ScenarioCards.card(CardRank.six, CardSuit.clubs, deckIndex: 2),
    ScenarioCards.card(CardRank.seven, CardSuit.diamonds, deckIndex: 2),
  ];
  final westHand = <HareegCard>[
    ScenarioCards.card(CardRank.eight, CardSuit.clubs, deckIndex: 2),
    ScenarioCards.card(CardRank.ten, CardSuit.diamonds, deckIndex: 2),
  ];

  ClassicHareegScenario dealSouthFiftyClaim({required int roundNumber}) {
    return ClassicHareegScenario.deal(
      // Permissive tier is irrelevant to a *valid* finish, but use Table so
      // the same setup shape mirrors the wrong-claim tests; a valid finish
      // never triggers the mistake path.
      setup: ClassicHareegSetup.defaults().copyWith(
        tableStrictness: TableStrictness.table,
      ),
      southHand: southWinningHand,
      eastHand: eastHand,
      northHand: northHand,
      westHand: westHand,
      // A non-empty discard pile whose TOP is the card south finishes with.
      discardPile: [topDiscardThreeClubs],
      // currentSeat=south + draw phase => window reopened, discarder inferred
      // as west (south.previousAntiClockwise).
      currentSeat: PlayerSeat.south,
      turnPhase: TurnPhase.draw,
      // South already opened so opening pressure cannot interfere; the finish
      // also bypasses opening via perfectHandAttempt, but this keeps it clean.
      openingState: ScenarioCards.openedFor(PlayerSeat.south),
      roundNumber: roundNumber,
      fiftyWindowOpenedAt: fixedClock,
      now: now,
    );
  }

  // Drives the prove-it play-out after a successful claim: the engine serves
  // the validated finish plan step by step on the CPU surface.
  void driveProof(ClassicHareegGameController c) {
    var safety = 0;
    while (!c.isRoundOver && c.isFiftyProofTurn && safety < 24) {
      final actions = c.cpuActionIdsFor(PlayerSeat.south);
      expect(actions, isNotEmpty, reason: 'proof step must be offered');
      final result = c.applyAction(actions.first);
      expect(result.isSuccess, isTrue, reason: result.message);
      safety += 1;
    }
  }

  group('Successful Fifty finish scoring', () {
    test(
      'successful Fifty finish applies the documented score deltas to the '
      'live scores',
      () {
        // Round 2 -> NOT the first-round exception, so winner delta is -3.
        final s = dealSouthFiftyClaim(roundNumber: 2);
        final c = s.controller;

        // Sanity: the window opened for south against west's discard.
        expect(
          c.fiftyClaimant,
          PlayerSeat.south,
          reason: 'Fifty window should be open for south',
        );

        // Read remaining counts BEFORE the claim (south is the winner; its
        // count is irrelevant to the winner delta).
        final westCount = c.cardCountFor(PlayerSeat.west);
        final eastCount = c.cardCountFor(PlayerSeat.east);
        final northCount = c.cardCountFor(PlayerSeat.north);
        expect(westCount, 2);
        expect(eastCount, 2);
        expect(northCount, 2);

        final result = s.south.claimFifty();
        expect(
          result.isSuccess,
          isTrue,
          reason: 'claimFifty should succeed for a genuine finish; got: '
              '"${result.message}"',
        );
        driveProof(c);
        expect(c.isRoundOver, isTrue);
        expect(c.roundOutcome, RoundOutcomeType.fiftyFinish);

        final scores = c.scores;
        // Winner south: -3 (round 2, no first-round exception).
        expect(
          scores[PlayerSeat.south],
          -3,
          reason: 'winner delta should be -3',
        );
        // Discarder west: remaining + 3.
        expect(
          scores[PlayerSeat.west],
          westCount + 3,
          reason: 'fifty discarder delta should be remaining(+3)',
        );
        // Other active seats: their remaining counts.
        expect(scores[PlayerSeat.east], eastCount);
        expect(scores[PlayerSeat.north], northCount);
      },
    );

    test(
      'successful Fifty deltas survive a round advance '
      '(nextRoundSnapshot baseline)',
      () {
        final s = dealSouthFiftyClaim(roundNumber: 2);
        final c = s.controller;
        final claim = s.south.claimFifty();
        expect(claim.isSuccess, isTrue, reason: claim.message);
        driveProof(c);

        final displayed = Map<PlayerSeat, int>.from(c.scores);

        final next = c.nextRoundSnapshot(savedAt: fixedClock);
        expect(
          next,
          isNotNull,
          reason: 'a non-match-ending Fifty round should produce a next round',
        );

        final advanced = ClassicHareegGameController.fromSnapshot(
          next!,
          now: now,
        );

        // The Fifty deltas must be folded into the next round's baseline.
        for (final seat in next.activeSeats) {
          expect(
            advanced.scores[seat],
            displayed[seat],
            reason: 'next-round baseline for $seat must equal the displayed '
                'Fifty score',
          );
        }
      },
    );

    test(
      'successful Fifty deltas survive a toSnapshot round-trip at round-over',
      () {
        // SUSPECTED LATENT BUG: toSnapshot persists the stale baseline
        // `_scores`, which does NOT include the just-completed round's Fifty
        // deltas (those live only in the scoreView overlay / roundProgress).
        // A fromSnapshot of that snapshot would then show pre-Fifty scores.
        //
        // We keep the assertion live (not skipped) so a regression here is
        // reported loudly. If this fails, the user's "Fifty score never
        // sticks after save/restore" symptom is reproduced exactly here.
        final s = dealSouthFiftyClaim(roundNumber: 2);
        final c = s.controller;
        final claim = s.south.claimFifty();
        expect(claim.isSuccess, isTrue, reason: claim.message);
        driveProof(c);
        expect(c.isRoundOver, isTrue);

        final displayed = Map<PlayerSeat, int>.from(c.scores);

        final snapshot = c.toSnapshot(savedAt: fixedClock);
        final restored = ClassicHareegGameController.fromSnapshot(
          snapshot,
          now: now,
        );

        for (final seat in PlayerSeat.values) {
          expect(
            restored.scores[seat],
            displayed[seat],
            reason: 'restored score for $seat ('
                '${restored.scores[seat]}) must equal the displayed Fifty '
                'score (${displayed[seat]}). If these differ, toSnapshot '
                'dropped the Fifty delta — the reported bug.',
          );
        }
      },
    );
  });

  group('Windowed take-discard finish scores as a Fifty', () {
    // The user's long-standing "Fifty scored -1 in a real game" bug. During an
    // open Fifty window the player can take the very card they finish with via
    // plain take-discard instead of the claim-fifty button (the natural move:
    // "the card I need is on top — tap it, lay down, go out"). The exit planner
    // used to score that finish as a normal -1 because only the claim path set
    // the Fifty provenance. Every prior Fifty test called claimFifty() directly,
    // so this organic path was never exercised. These tests drive the real
    // take → meld → final-discard sequence through the controller.
    //
    // The winning hand partitions hand + taken 3C into two sets plus one final
    // discard: {3C,3D,3H} + {KS,KD,KH}, discard 9S. The taken 3C is melded, so
    // the finish genuinely uses the windowed card.
    final threeDiamonds =
        ScenarioCards.card(CardRank.three, CardSuit.diamonds, deckIndex: 1);
    final threeHearts =
        ScenarioCards.card(CardRank.three, CardSuit.hearts, deckIndex: 1);
    final kingSpades =
        ScenarioCards.card(CardRank.king, CardSuit.spades, deckIndex: 1);
    final kingDiamonds =
        ScenarioCards.card(CardRank.king, CardSuit.diamonds, deckIndex: 1);
    final kingHearts =
        ScenarioCards.card(CardRank.king, CardSuit.hearts, deckIndex: 1);
    final nineSpades =
        ScenarioCards.card(CardRank.nine, CardSuit.spades, deckIndex: 1);

    void driveTakeAndFinish(ClassicHareegScenario s) {
      expect(s.south.takeDiscard().isSuccess, isTrue);
      expect(
        s.south.playMeld([topDiscardThreeClubs, threeDiamonds, threeHearts])
            .isSuccess,
        isTrue,
      );
      expect(
        s.south.playMeld([kingSpades, kingDiamonds, kingHearts]).isSuccess,
        isTrue,
      );
      expect(s.south.discard(nineSpades).isSuccess, isTrue);
    }

    test(
      'take-discard then finish scores -3 with the documented deltas',
      () {
        final s = dealSouthFiftyClaim(roundNumber: 2);
        final c = s.controller;
        expect(c.fiftyClaimant, PlayerSeat.south);
        final westCount = c.cardCountFor(PlayerSeat.west);

        driveTakeAndFinish(s);

        expect(c.isRoundOver, isTrue);
        expect(
          c.roundOutcome,
          RoundOutcomeType.fiftyFinish,
          reason: 'finishing on the windowed discard is a Fifty even when the '
              'card was taken via take-discard rather than claim-fifty',
        );
        expect(
          c.scores[PlayerSeat.south],
          -3,
          reason: 'winner delta is the -3 Fifty, never a normal -1',
        );
        expect(
          c.scores[PlayerSeat.west],
          westCount + 3,
          reason: 'the windowed discarder (west) still eats remaining + 3',
        );
        expect(c.scores[PlayerSeat.east], c.cardCountFor(PlayerSeat.east));
        expect(c.scores[PlayerSeat.north], c.cardCountFor(PlayerSeat.north));
      },
    );

    test(
      'round 1 take-discard finish uses the first-round -1 exception',
      () {
        // The exception must ride the take path exactly as it does the claim
        // path: a round-1 Fifty scores the winner -1, not -3.
        final s = dealSouthFiftyClaim(roundNumber: 1);
        final c = s.controller;

        driveTakeAndFinish(s);

        expect(c.roundOutcome, RoundOutcomeType.fiftyFinish);
        expect(
          c.scores[PlayerSeat.south],
          -1,
          reason: 'first dealt round Fifty exception applies to the take path',
        );
      },
    );

    test(
      'windowed take provenance survives a mid-turn save/restore',
      () {
        // The user's "Fifty never sticks in a real game" history: the app
        // autosaves after every action, so a take-discard can be persisted
        // mid-turn before the finish. Restore must keep the Fifty provenance or
        // the resumed finish silently reverts to -1.
        final s = dealSouthFiftyClaim(roundNumber: 2);
        final c = s.controller;
        expect(s.south.takeDiscard().isSuccess, isTrue);

        // Save mid-turn (card taken, not yet melded) and restore a fresh engine.
        final restored = ClassicHareegGameController.fromSnapshot(
          c.toSnapshot(savedAt: fixedClock),
          now: now,
        );
        final r = ClassicHareegScenario.fromController(restored);

        // Finish on the restored controller using the taken card.
        expect(
          r.south.playMeld([topDiscardThreeClubs, threeDiamonds, threeHearts])
              .isSuccess,
          isTrue,
        );
        expect(
          r.south.playMeld([kingSpades, kingDiamonds, kingHearts]).isSuccess,
          isTrue,
        );
        expect(r.south.discard(nineSpades).isSuccess, isTrue);

        expect(restored.isRoundOver, isTrue);
        expect(
          restored.roundOutcome,
          RoundOutcomeType.fiftyFinish,
          reason: 'a windowed take resumed from a snapshot still finishes Fifty',
        );
        expect(
          restored.scores[PlayerSeat.south],
          -3,
          reason: 'restored windowed finish scores -3, not a dropped -1',
        );
      },
    );

    test(
      'after the window expires, the same take-discard finish is a normal -1',
      () {
        // Over-broad-fix guard. Reading the clock just past the configured
        // timer means the card was NOT taken within the window, so the finish
        // is an ordinary normalFinish (-1 winner) — Fifty scoring must NOT leak
        // past expiry. Derive the offset from the setup so a changed default
        // timer keeps this test honest.
        final setup = ClassicHareegSetup.defaults().copyWith(
          tableStrictness: TableStrictness.table,
        );
        final expiredClock = fixedClock.add(
          Duration(seconds: setup.fiftyTimerSeconds + 1),
        );
        final s = ClassicHareegScenario.deal(
          setup: setup,
          southHand: southWinningHand,
          eastHand: eastHand,
          northHand: northHand,
          westHand: westHand,
          discardPile: [topDiscardThreeClubs],
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.draw,
          openingState: ScenarioCards.openedFor(PlayerSeat.south),
          roundNumber: 2,
          fiftyWindowOpenedAt: fixedClock,
          now: () => expiredClock,
        );
        final c = s.controller;

        driveTakeAndFinish(s);

        expect(c.isRoundOver, isTrue);
        expect(
          c.roundOutcome,
          RoundOutcomeType.normalFinish,
          reason: 'a pickup after the window closed is a normal finish',
        );
        expect(
          c.scores[PlayerSeat.south],
          -1,
          reason: 'normal finish winner delta is -1, not the -3 Fifty',
        );
      },
    );
  });

  group('Wrong Fifty claim penalties', () {
    // South claims Fifty but holds a hand that cannot finish with the top
    // discard. Top discard = 2 of spades; south's hand has no meld using it
    // and cannot partition into melds + one discard.
    final unwinnableTopDiscard =
        ScenarioCards.card(CardRank.two, CardSuit.spades, deckIndex: 3);
    final southStuckHand = <HareegCard>[
      ScenarioCards.card(CardRank.four, CardSuit.hearts, deckIndex: 3),
      ScenarioCards.card(CardRank.seven, CardSuit.clubs, deckIndex: 3),
      ScenarioCards.card(CardRank.nine, CardSuit.diamonds, deckIndex: 3),
      ScenarioCards.card(CardRank.jack, CardSuit.spades, deckIndex: 3),
      ScenarioCards.card(CardRank.queen, CardSuit.hearts, deckIndex: 3),
    ];

    ClassicHareegScenario dealWrongClaim(TableStrictness strictness) {
      return ClassicHareegScenario.deal(
        setup: ClassicHareegSetup.defaults().copyWith(
          tableStrictness: strictness,
        ),
        southHand: southStuckHand,
        eastHand: eastHand,
        northHand: northHand,
        westHand: westHand,
        discardPile: [unwinnableTopDiscard],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
        roundNumber: 2,
        fiftyWindowOpenedAt: fixedClock,
        now: now,
      );
    }

    test('wrong Fifty claim under Table tier penalizes the claimant by +17',
        () {
      final s = dealWrongClaim(TableStrictness.table);
      final c = s.controller;
      expect(c.fiftyClaimant, PlayerSeat.south);

      final priorSouth = c.scores[PlayerSeat.south] ?? 0;
      final result = s.south.claimFifty();
      // Prove-it flow: the claim is accepted unproven; the consequence fires
      // when the turn ends without a proof.
      expect(result.isSuccess, isTrue, reason: result.message);
      expect(c.isFiftyProofTurn, isTrue);
      expect(
        (c.scores[PlayerSeat.south] ?? 0) - priorSouth,
        0,
        reason: 'no claim-time fee in the prove-it flow',
      );

      final exit = c.applyAction(
        'discard:${southStuckHand.first.id}',
      );
      expect(exit.isSuccess, isTrue, reason: exit.message);

      expect(
        c.removedSeats.contains(PlayerSeat.south),
        isTrue,
        reason: 'Table tier should remove south from the round',
      );
      expect(
        (c.scores[PlayerSeat.south] ?? 0) - priorSouth,
        17,
        reason: 'Table tier wrong Fifty claim should charge +17',
      );
    });

    test('wrong Fifty claim under Strict tier penalizes the claimant by +3',
        () {
      final s = dealWrongClaim(TableStrictness.strict);
      final c = s.controller;
      expect(c.fiftyClaimant, PlayerSeat.south);

      final priorSouth = c.scores[PlayerSeat.south] ?? 0;
      final result = s.south.claimFifty();
      expect(result.isSuccess, isTrue, reason: result.message);
      expect(c.isFiftyProofTurn, isTrue);

      final exit = c.applyAction(
        'discard:${southStuckHand.first.id}',
      );
      expect(exit.isSuccess, isTrue, reason: exit.message);

      // Strict tier penalizes at the unproven exit but does NOT remove from
      // the round — the turn ends normally.
      expect(
        c.removedSeats.contains(PlayerSeat.south),
        isFalse,
        reason: 'Strict tier should not remove south',
      );
      expect(
        (c.scores[PlayerSeat.south] ?? 0) - priorSouth,
        3,
        reason: 'Strict tier wrong Fifty claim should charge +3',
      );
    });
  });
}
