import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

import 'classic_hareeg_match_driver.dart';
import 'classic_hareeg_scenario.dart';

/// "Family C" narrative scenario tests — each test tells a single, deterministic
/// start-to-finish game story that exercises ONE documented rule area end to end
/// and asserts the exact outcome. They complement the unit-level rules tests by
/// driving the *real* controller through the scenario DSL, the same seam the UI
/// uses.
///
/// Rule references:
///   * Opening benchmark (default 51): a seat opens only when the melds it plays
///     in one turn total at least the current requirement
///     (`opening_rules.dart::validateOpening` + `applyOpening`). Card meld value
///     is `CardRank.value`: ace/J/Q/K = 10, others = pip
///     (`playing_card.dart::CardRank.value`); a same-rank set sums those values
///     (`meld_validator.dart::_validateSet`).
///   * Normal finish + scoring: a finish is played melds + exactly one final
///     discard (`finish_rules.dart::validateFinish`); the discarder wins. On a
///     normal finish the winner gets -1 and every other active seat gets its
///     remaining card count (`match_progression_rules.dart::applyRoundResult`,
///     `RoundOutcomeType.normalFinish`).
///   * Match progression: each round's resulting scores become the next round's
///     baseline; a seat is eliminated at score >= 31 (default eliminationScore)
///     and the match ends when one active seat remains
///     (`match_progression_rules.dart::applyRoundResult`).
void main() {
  // Fixed clock keeps Fifty windows and any time-sensitive surface deterministic.
  DateTime fixedNow() => DateTime.utc(2026, 1, 1);

  group('Opening benchmark gate (requirement 51)', () {
    // Card values (CardRank.value): K/Q/J/ace = 10, pips = face value.
    // A same-rank set sums those values, so:
    //   set of three kings  = 10 + 10 + 10 = 30  (< 51, cannot open alone)
    //   set of three queens = 10 + 10 + 10 = 30
    //   30 + 30 = 60 (>= 51) opens the seat in one turn.
    List<HareegCard> threeKings() => [
          ScenarioCards.card(CardRank.king, CardSuit.clubs, deckIndex: 60),
          ScenarioCards.card(CardRank.king, CardSuit.diamonds, deckIndex: 60),
          ScenarioCards.card(CardRank.king, CardSuit.hearts, deckIndex: 60),
        ];
    List<HareegCard> threeQueens() => [
          ScenarioCards.card(CardRank.queen, CardSuit.clubs, deckIndex: 60),
          ScenarioCards.card(CardRank.queen, CardSuit.diamonds, deckIndex: 60),
          ScenarioCards.card(CardRank.queen, CardSuit.hearts, deckIndex: 60),
        ];

    test(
      'a single sub-51 meld (three kings = 30) does NOT open the seat: it '
      'stages without opening',
      () {
        // South is UNOPENED (initial 51 benchmark, not in openedSeats) and acts
        // in the action phase. It holds two sets plus a filler discard.
        final filler =
            ScenarioCards.card(CardRank.two, CardSuit.spades, deckIndex: 60);
        final s = ClassicHareegScenario.deal(
          southHand: [...threeKings(), ...threeQueens(), filler],
          openingState: OpeningState.initial(51),
          currentSeat: PlayerSeat.south,
          now: fixedNow,
        );
        final c = s.controller;

        expect(
          c.openingState.hasOpened(PlayerSeat.south),
          isFalse,
          reason: 'precondition: south starts unopened',
        );

        // Playing ONLY the kings (value 30 < 51) is accepted as a *staged*
        // opening meld but MUST NOT open the seat. This is the staging subtlety:
        // sub-requirement opening melds are allowed onto the table but
        // `opensPlayer` stays false (meld_play_eligibility openingPartial).
        final played = s.south.playMeld(threeKings());
        expect(
          played.isSuccess,
          isTrue,
          reason: 'sub-51 opening meld stages rather than being rejected',
        );
        expect(
          c.openingState.hasOpened(PlayerSeat.south),
          isFalse,
          reason: 'a 30-point meld is below the 51 benchmark: seat stays '
              'UNOPENED',
        );

        // The staged meld can be taken back via returnOpeningMelds, proving it
        // was never a committed opening.
        final returned = s.south.returnOpeningMelds();
        expect(
          returned.isSuccess,
          isTrue,
          reason: 'a staged (uncommitted) sub-51 opening meld is returnable',
        );
        expect(
          c.openingState.hasOpened(PlayerSeat.south),
          isFalse,
          reason: 'still unopened after returning the staged meld',
        );
        expect(
          c.tableMeldsFor(PlayerSeat.south),
          isEmpty,
          reason: 'returned staged meld left the table',
        );
      },
    );

    test(
      'playing melds totalling >= 51 in one turn (kings + queens = 60) opens '
      'the seat and lands both melds on the table',
      () {
        final filler =
            ScenarioCards.card(CardRank.two, CardSuit.spades, deckIndex: 61);
        final s = ClassicHareegScenario.deal(
          southHand: [...threeKings(), ...threeQueens(), filler],
          openingState: OpeningState.initial(51),
          currentSeat: PlayerSeat.south,
          now: fixedNow,
        );
        final c = s.controller;
        expect(c.openingState.hasOpened(PlayerSeat.south), isFalse);

        // First meld stages (30 < 51) without opening.
        final first = s.south.playMeld(threeKings());
        expect(first.isSuccess, isTrue);
        expect(
          c.openingState.hasOpened(PlayerSeat.south),
          isFalse,
          reason: 'after the first 30-point meld the running total is still '
              'below 51',
        );

        // Second meld pushes the staged total to 60 (>= 51) and OPENS the seat.
        final second = s.south.playMeld(threeQueens());
        expect(second.isSuccess, isTrue);
        expect(
          c.openingState.hasOpened(PlayerSeat.south),
          isTrue,
          reason: 'staged total 30 + 30 = 60 >= 51 opens the seat in one turn',
        );

        // Both melds are committed to the table.
        expect(
          c.tableMeldsFor(PlayerSeat.south),
          hasLength(2),
          reason: 'both opening melds are placed once the benchmark is met',
        );
        final placedValue = c
            .tableMeldsFor(PlayerSeat.south)
            .fold<int>(0, (total, meld) => total + meld.valueSnapshot);
        expect(
          placedValue,
          60,
          reason: 'placed opening melds total 60 points',
        );
      },
    );
  });

  group('Normal finish + round-end scoring', () {
    test(
      'an opened seat empties its hand (melds + final discard) -> normalFinish; '
      'winner delta -1, each loser delta = remaining card count',
      () {
        // South is already opened so it may keep placing melds and finish.
        // Hand: set of three fives (5C 5D 5H) + set of three sixes (6C 6D 6H)
        // + one final discard (9S) = 7 cards. After both melds, exactly one
        // card (9S) remains -> discarding it is the final discard.
        final southFinishHand = <HareegCard>[
          ScenarioCards.card(CardRank.five, CardSuit.clubs, deckIndex: 70),
          ScenarioCards.card(CardRank.five, CardSuit.diamonds, deckIndex: 70),
          ScenarioCards.card(CardRank.five, CardSuit.hearts, deckIndex: 70),
          ScenarioCards.card(CardRank.six, CardSuit.clubs, deckIndex: 70),
          ScenarioCards.card(CardRank.six, CardSuit.diamonds, deckIndex: 70),
          ScenarioCards.card(CardRank.six, CardSuit.hearts, deckIndex: 70),
          ScenarioCards.card(CardRank.nine, CardSuit.spades, deckIndex: 70),
        ];
        // Deterministic small loser hands so remaining counts are exact:
        // east = 3, north = 2, west = 4.
        final eastHand = <HareegCard>[
          ScenarioCards.card(CardRank.two, CardSuit.clubs, deckIndex: 71),
          ScenarioCards.card(CardRank.three, CardSuit.clubs, deckIndex: 71),
          ScenarioCards.card(CardRank.four, CardSuit.clubs, deckIndex: 71),
        ];
        final northHand = <HareegCard>[
          ScenarioCards.card(CardRank.seven, CardSuit.diamonds, deckIndex: 71),
          ScenarioCards.card(CardRank.eight, CardSuit.diamonds, deckIndex: 71),
        ];
        final westHand = <HareegCard>[
          ScenarioCards.card(CardRank.nine, CardSuit.hearts, deckIndex: 71),
          ScenarioCards.card(CardRank.ten, CardSuit.hearts, deckIndex: 71),
          ScenarioCards.card(CardRank.jack, CardSuit.hearts, deckIndex: 71),
          ScenarioCards.card(CardRank.queen, CardSuit.hearts, deckIndex: 71),
        ];

        final s = ClassicHareegScenario.deal(
          southHand: southFinishHand,
          eastHand: eastHand,
          northHand: northHand,
          westHand: westHand,
          openingState: ScenarioCards.openedFor(PlayerSeat.south),
          currentSeat: PlayerSeat.south,
          now: fixedNow,
        );
        final c = s.controller;

        // Loser counts captured before the finish (the round result snapshots
        // these exact counts).
        final eastCount = c.cardCountFor(PlayerSeat.east);
        final northCount = c.cardCountFor(PlayerSeat.north);
        final westCount = c.cardCountFor(PlayerSeat.west);
        expect(eastCount, 3);
        expect(northCount, 2);
        expect(westCount, 4);

        // Play both melds, then discard the last card to finish.
        expect(
          s.south.playMeld([
            southFinishHand[0],
            southFinishHand[1],
            southFinishHand[2],
          ]).isSuccess,
          isTrue,
        );
        expect(
          s.south.playMeld([
            southFinishHand[3],
            southFinishHand[4],
            southFinishHand[5],
          ]).isSuccess,
          isTrue,
        );
        expect(
          c.cardCountFor(PlayerSeat.south),
          1,
          reason: 'exactly one card left -> the next discard is the final '
              'discard',
        );

        final finish = s.south.discard(southFinishHand[6]);
        expect(
          finish.isSuccess,
          isTrue,
          reason: 'final discard completes the finish',
        );

        // Round is over as a NORMAL finish with south as winner.
        expect(c.isRoundOver, isTrue);
        expect(
          c.roundOutcome,
          RoundOutcomeType.normalFinish,
          reason: 'emptying the hand via melds + final discard is a normal '
              'finish',
        );

        // Scoring deltas (scores start at the default empty baseline, so the
        // displayed score IS the delta):
        //   winner south -> -1
        //   each loser   -> its remaining card count
        final scores = c.scores;
        expect(
          scores[PlayerSeat.south],
          -1,
          reason: 'normal-finish winner delta is -1',
        );
        expect(
          scores[PlayerSeat.east],
          eastCount,
          reason: 'losing seat gains its remaining card count',
        );
        expect(scores[PlayerSeat.north], northCount);
        expect(scores[PlayerSeat.west], westCount);
      },
    );
  });

  group('Multi-round match progression', () {
    test(
      'a skilled-CPU match converges to a single winner; scores carry round to '
      'round and eliminations happen at >= 31',
      () {
        final setup = ClassicHareegSetup.defaults().copyWith(
          cpuDifficulty: CpuDifficulty.skilled,
        );

        // Find a seed that converges to a match winner within budget. The
        // driver is fully deterministic per (setup, seed), so the chosen seed
        // is reproducible.
        MatchRunReport? converged;
        for (final seed in [1, 2, 3, 4, 5, 6, 7, 8, 11, 13, 17, 23]) {
          final report = ClassicHareegMatchDriver(
            actionLimit: 8000,
            roundLimit: 60,
          ).run(setup: setup, seed: seed);
          if (report.stopReason == MatchStopReason.matchWinner) {
            converged = report;
            break;
          }
        }

        expect(
          converged,
          isNotNull,
          reason: 'at least one seed must drive the skilled-CPU match to a '
              'natural winner within the action/round budget',
        );
        final report = converged!;

        // The winner is a single seat.
        expect(report.winner, isNotNull);
        // A real multi-round match: more than one round must have been played
        // so the carry-over assertion below is non-vacuous.
        expect(
          report.rounds.length,
          greaterThan(1),
          reason: 'a converging match plays several rounds before a winner',
        );

        // Score carry-over: each round's scoresAfter becomes the next round's
        // scoresBefore baseline (applyRoundResult folds deltas into the running
        // total carried by nextRoundSnapshot).
        for (var i = 1; i < report.rounds.length; i += 1) {
          final prev = report.rounds[i - 1];
          final curr = report.rounds[i];
          for (final seat in curr.scoresBefore.keys) {
            expect(
              curr.scoresBefore[seat],
              prev.scoresAfter[seat],
              reason: 'round ${curr.roundNumber} baseline for $seat must equal '
                  'round ${prev.roundNumber} result',
            );
          }
        }

        // Final-round result drives elimination: the winner is the single
        // surviving active seat with score < 31; everyone else ended >= 31.
        final finalRound = report.rounds.last;
        final finalScores = finalRound.scoresAfter;
        expect(
          finalScores[report.winner],
          lessThan(31),
          reason: 'match winner is below the 31 elimination threshold',
        );
        for (final seat in PlayerSeat.values) {
          if (seat == report.winner) {
            continue;
          }
          expect(
            finalScores[seat],
            greaterThanOrEqualTo(31),
            reason: '$seat was eliminated, so it ended at or above 31',
          );
        }
      },
    );
  });
}
