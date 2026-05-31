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
      // The claim "succeeds" as an applied mistake (side effects happened).
      expect(result.isSuccess, isTrue, reason: result.message);

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

      // Strict tier penalizes but does NOT remove from the round.
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
