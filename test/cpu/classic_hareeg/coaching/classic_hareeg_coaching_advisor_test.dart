import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/classic_hareeg_coaching_advisor.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/coaching_insight.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_discard_history.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

import '../../../scenario/classic_hareeg_scenario.dart';

// Shorthand card builders. deckIndex disambiguates physical copies so two cards
// of the same identity get distinct ids.
HareegCard _c(CardRank rank, CardSuit suit, {int deckIndex = 0}) =>
    ScenarioCards.card(rank, suit, deckIndex: deckIndex);

HareegCard _joker({int jokerIndex = 0, int deckIndex = 90}) =>
    HareegCard.joker(deckIndex: deckIndex, jokerIndex: jokerIndex);

ClassicHareegSetup _coachingSetup() {
  return ClassicHareegSetup.defaults().copyWith(
    tableStrictness: TableStrictness.coaching,
  );
}

PlacedMeld _meld(List<HareegCard> cards) => PlacedMeld.fromCards(cards);

bool _has(List<CoachingInsight> insights, CoachingInsightCategory category) {
  return insights.any((insight) => insight.category == category);
}

CoachingInsight _find(
  List<CoachingInsight> insights,
  CoachingInsightCategory category,
) {
  return insights.firstWhere((insight) => insight.category == category);
}

void main() {
  group('finishAvailable', () {
    test('opened seat that can empty its hand this turn', () {
      // Opened seat, action phase, hand is two complete runs of 3 + one extra
      // card to act as the final discard.
      final hand = [
        _c(CardRank.eight, CardSuit.diamonds),
        _c(CardRank.nine, CardSuit.diamonds),
        _c(CardRank.ten, CardSuit.diamonds),
        _c(CardRank.five, CardSuit.clubs),
        _c(CardRank.six, CardSuit.clubs),
        _c(CardRank.seven, CardSuit.clubs),
        _c(CardRank.two, CardSuit.spades),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.finishAvailable), isTrue);
      expect(insights.first.category, CoachingInsightCategory.finishAvailable);
    });

    test('a single remaining card is a winning finish, not a discard hint', () {
      // Playtest regression: down to one card after covering out, the coach
      // must say "you can win" (finish) and ring the last card, not "discard
      // your least useful card".
      final last = _c(CardRank.jack, CardSuit.clubs);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: [last],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(insights.first.category, CoachingInsightCategory.finishAvailable);
      expect(insights.first.highlightCardIds, contains(last.id));
    });

    test('one card in the DRAW phase says draw first, not "you can win"', () {
      // Playtest: down to a single card at the start of your turn, you must draw
      // before you can discard it — so the finish hint must NOT fire in the draw
      // phase; the actionable hint is to draw from the stock.
      final last = _c(CardRank.jack, CardSuit.clubs);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: [last],
        discardPile: [_c(CardRank.two, CardSuit.spades)],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.finishAvailable), isFalse);
      expect(insights.first.category, CoachingInsightCategory.drawStock);
    });

    test('absent when the hand cannot finish this turn', () {
      final hand = [
        _c(CardRank.eight, CardSuit.diamonds),
        _c(CardRank.nine, CardSuit.diamonds),
        _c(CardRank.ten, CardSuit.diamonds),
        _c(CardRank.two, CardSuit.spades),
        _c(CardRank.five, CardSuit.hearts),
        _c(CardRank.nine, CardSuit.spades),
        _c(CardRank.king, CardSuit.clubs),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.finishAvailable), isFalse);
    });

    test('names the final discard of the winning plan', () {
      // The plan-aware finish walks the player all the way through: lay the
      // ringed melds, then throw the named junk card.
      final junk = _c(CardRank.two, CardSuit.spades);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: [
          _c(CardRank.eight, CardSuit.diamonds),
          _c(CardRank.nine, CardSuit.diamonds),
          _c(CardRank.ten, CardSuit.diamonds),
          junk,
        ],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      final finish = _find(insights, CoachingInsightCategory.finishAvailable);
      expect(finish.discardCardId, junk.id);
      expect(finish.bypassesOpening, isFalse);
    });

    test('cover-routed full finish: set + cover + final discard', () {
      // Playtest regression: a 3-card set, a J♠ that covers North's table run,
      // and a junk final discard is a COMPLETE win — the coach said "you can
      // lay down a meld" because its melds-only scan could not see the cover
      // route. The finish hint must own this state and name the closing throw
      // (legal even though the J♠ itself could never leave as a plain discard).
      final tableRun = [
        _c(CardRank.eight, CardSuit.spades),
        _c(CardRank.nine, CardSuit.spades),
        _c(CardRank.ten, CardSuit.spades),
      ];
      final coverJack = _c(CardRank.jack, CardSuit.spades);
      final junk = _c(CardRank.two, CardSuit.hearts);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: [
          _c(CardRank.nine, CardSuit.diamonds),
          _c(CardRank.nine, CardSuit.clubs),
          _c(CardRank.nine, CardSuit.hearts),
          coverJack,
          junk,
        ],
        tableMelds: {
          PlayerSeat.north: [_meld(tableRun)],
        },
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          openedSeats: {PlayerSeat.south, PlayerSeat.north},
        ),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(insights.first.category, CoachingInsightCategory.finishAvailable);
      final finish = insights.first;
      expect(finish.coverFinishes, isTrue);
      expect(finish.discardCardId, junk.id);
      // Both ends of the lay-off ring: the cover card and the table meld.
      expect(finish.highlightCardIds, contains(coverJack.id));
      expect(finish.highlightCardIds, containsAll(tableRun.map((c) => c.id)));
    });

    test('unopened seat: the opening finish through a cover', () {
      // The exact playtest hand shape: an UNOPENED seat whose 3-card set
      // clears the requirement, plus a cover and the final discard — a full
      // win that doubles as the opening. The old unopened early-return
      // suppressed it entirely and the coach fixated on the meld lay.
      final tableRun = [
        _c(CardRank.eight, CardSuit.spades),
        _c(CardRank.nine, CardSuit.spades),
        _c(CardRank.ten, CardSuit.spades),
      ];
      final coverJack = _c(CardRank.jack, CardSuit.spades);
      final junk = _c(CardRank.two, CardSuit.hearts);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: [
          _c(CardRank.nine, CardSuit.diamonds),
          _c(CardRank.nine, CardSuit.clubs),
          _c(CardRank.nine, CardSuit.hearts),
          coverJack,
          junk,
        ],
        tableMelds: {
          PlayerSeat.north: [_meld(tableRun)],
        },
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        // The fresh 9-9-9 set (27) clears the requirement, so the cover-routed
        // plan is engine-valid for an unopened seat.
        openingState: const OpeningState(
          baseRequirement: 25,
          currentRequirement: 25,
          openedSeats: {PlayerSeat.north},
        ),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(insights.first.category, CoachingInsightCategory.finishAvailable);
      final finish = insights.first;
      expect(finish.coverFinishes, isTrue);
      expect(finish.bypassesOpening, isTrue);
      expect(finish.discardCardId, junk.id);
    });

    test('two-joker cover-routed finish outranks the meld hint (playtest)', () {
      // Screenshot hand: 3♠ 5♠ 7♠ Q♠ K♠ + two jokers + a drawn 5♥ covering
      // West's heart run. The full win is 5♥ cover + the 5-joker-7♠ and
      // Q-K-joker runs + 3♠ as the final discard — but the coach only said
      // "you can lay down a meld": the ambiguous Q-K-joker (J or A) made the
      // engine's finish proof reject the candidate, hiding the finish.
      final threeSpades = _c(CardRank.three, CardSuit.spades);
      final fiveHearts = _c(CardRank.five, CardSuit.hearts);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: [
          threeSpades,
          _c(CardRank.five, CardSuit.spades),
          _c(CardRank.seven, CardSuit.spades),
          _c(CardRank.queen, CardSuit.spades),
          _c(CardRank.king, CardSuit.spades),
          _joker(jokerIndex: 0, deckIndex: 90),
          _joker(jokerIndex: 1, deckIndex: 91),
          fiveHearts,
        ],
        tableMelds: {
          PlayerSeat.west: [
            _meld([
              _c(CardRank.six, CardSuit.hearts),
              _c(CardRank.seven, CardSuit.hearts),
              _c(CardRank.eight, CardSuit.hearts),
              _c(CardRank.nine, CardSuit.hearts),
            ]),
          ],
        },
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          openedSeats: {PlayerSeat.south, PlayerSeat.west},
        ),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(insights.first.category, CoachingInsightCategory.finishAvailable);
      final finish = insights.first;
      expect(finish.coverFinishes, isTrue);
      expect(finish.discardCardId, threeSpades.id);
      expect(finish.highlightCardIds, contains(fiveHearts.id));
    });

    test('unopened seat: the perfect-hand bypass', () {
      // A melds-only full hand finishes BELOW the requirement — the rules'
      // perfect-hand exemption. Previously invisible to the coach (unopened
      // seats were gated out of the finish hint wholesale).
      final junk = _c(CardRank.two, CardSuit.spades);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: [
          _c(CardRank.eight, CardSuit.diamonds),
          _c(CardRank.nine, CardSuit.diamonds),
          _c(CardRank.ten, CardSuit.diamonds),
          _c(CardRank.five, CardSuit.clubs),
          _c(CardRank.six, CardSuit.clubs),
          _c(CardRank.seven, CardSuit.clubs),
          junk,
        ],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        // 45 total meld value < 51: only the full-hand finish makes these
        // melds playable.
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          openedSeats: {},
        ),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(insights.first.category, CoachingInsightCategory.finishAvailable);
      final finish = insights.first;
      expect(finish.coverFinishes, isFalse);
      expect(finish.bypassesOpening, isTrue);
      expect(finish.discardCardId, junk.id);
    });
  });

  group('fiftyAvailable', () {
    test('seat owns the window and a finish uses the top discard', () {
      // South holds a complete run, a run missing one card, and a junk 2♠ for
      // the final discard; the top discard completes the finish. (A valid
      // finish must END with a discard — a hand that melds everything with
      // nothing left to throw is not claimable, which the engine's claim
      // advertisement enforces.)
      final hand = [
        _c(CardRank.eight, CardSuit.diamonds),
        _c(CardRank.nine, CardSuit.diamonds),
        _c(CardRank.ten, CardSuit.diamonds),
        _c(CardRank.five, CardSuit.clubs),
        _c(CardRank.six, CardSuit.clubs),
        _c(CardRank.two, CardSuit.spades),
      ];
      final topDiscard = _c(CardRank.seven, CardSuit.clubs);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        discardPile: [topDiscard],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
        fiftyWindowOpenedAt: DateTime.utc(2026, 5, 24),
        // Pin the clock inside the claim window: the hint requires the claim
        // to be LIVE on the legal surface, not merely a restored window.
        now: () => DateTime.utc(2026, 5, 24, 0, 0, 1),
      );

      // The restoration opens a Fifty window for the current seat whenever the
      // restored phase is draw with a non-empty discard pile.
      expect(scenario.controller.fiftyClaimant, PlayerSeat.south);

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.fiftyAvailable), isTrue);
      expect(insights.first.category, CoachingInsightCategory.fiftyAvailable);
    });

    test('absent when there is no open Fifty window', () {
      // Action phase (not draw) means no Fifty window is restored, so the seat
      // is not the claimant even though a finish-completing discard sits on top.
      final hand = [
        _c(CardRank.eight, CardSuit.diamonds),
        _c(CardRank.nine, CardSuit.diamonds),
        _c(CardRank.ten, CardSuit.diamonds),
        _c(CardRank.five, CardSuit.clubs),
        _c(CardRank.six, CardSuit.clubs),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        discardPile: [_c(CardRank.seven, CardSuit.clubs)],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      expect(scenario.controller.fiftyClaimant, isNull);

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.fiftyAvailable), isFalse);
    });
  });

  group('openNow vs openingProgress', () {
    test('openNow when best partition meets the requirement', () {
      // Three face cards of one suit -> value 30; plus a run worth 30. With a
      // 30 requirement the best partition clears it.
      final hand = [
        _c(CardRank.king, CardSuit.spades),
        _c(CardRank.queen, CardSuit.spades),
        _c(CardRank.jack, CardSuit.spades),
        _c(CardRank.two, CardSuit.hearts),
        _c(CardRank.three, CardSuit.clubs),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: const OpeningState(
          baseRequirement: 30,
          currentRequirement: 30,
          openedSeats: {},
        ),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.openNow), isTrue);
      expect(_has(insights, CoachingInsightCategory.openingProgress), isFalse);
      final insight = _find(insights, CoachingInsightCategory.openNow);
      expect(insight.openingBestValue, greaterThanOrEqualTo(30));
      expect(insight.meldActionId, isNotNull);
    });

    test('openingProgress carries the shortfall when below requirement', () {
      // A single low run worth 9 against a 51 requirement -> shortfall 42.
      final hand = [
        _c(CardRank.two, CardSuit.clubs),
        _c(CardRank.three, CardSuit.clubs),
        _c(CardRank.four, CardSuit.clubs),
        _c(CardRank.nine, CardSuit.spades),
        _c(CardRank.king, CardSuit.hearts),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          openedSeats: {},
        ),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.openingProgress), isTrue);
      expect(_has(insights, CoachingInsightCategory.openNow), isFalse);
      final insight = _find(insights, CoachingInsightCategory.openingProgress);
      expect(insight.openingRequirement, 51);
      expect(insight.openingBestValue, lessThan(51));
      expect(insight.openingShortfall, 51 - insight.openingBestValue!);
    });

    test('unopened seat is guided to open with a combined keep + discard hint', () {
      // Playtest screenshot: a fresh, unopened hand where the 4♣ anchors BOTH a
      // 4-5-6-7 club run and a set of 4s, plus a complete set of 8s. Best
      // opening partition is 46 vs a 51 requirement. The coach must surface ONE
      // opening hint that rings the cards worth keeping AND names a deadwood
      // card to discard (potential-weighted) — never the meld-anchoring 4♣.
      final fourClubs = _c(CardRank.four, CardSuit.clubs);
      final kingDiamonds = _c(CardRank.king, CardSuit.diamonds);
      final twoDiamonds = _c(CardRank.two, CardSuit.diamonds);
      final twoClubs = _c(CardRank.two, CardSuit.clubs);
      final hand = [
        fourClubs,
        _c(CardRank.four, CardSuit.hearts),
        _c(CardRank.four, CardSuit.spades),
        _c(CardRank.five, CardSuit.clubs),
        _c(CardRank.six, CardSuit.clubs),
        _c(CardRank.seven, CardSuit.clubs),
        _c(CardRank.eight, CardSuit.hearts),
        _c(CardRank.eight, CardSuit.diamonds),
        _c(CardRank.eight, CardSuit.spades),
        twoDiamonds,
        twoClubs,
        kingDiamonds,
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: const OpeningState(
          baseRequirement: 81,
          currentRequirement: 81,
          openedSeats: {},
        ),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(insights.first.category, CoachingInsightCategory.openingProgress);
      expect(
        _has(insights, CoachingInsightCategory.discardSuggestion),
        isFalse,
      );
      final opening = _find(insights, CoachingInsightCategory.openingProgress);
      // The combined hint names a low deadwood discard (a 2), never the 4♣ that
      // anchors a meld, and never the lone King it should keep for its ceiling.
      expect(opening.discardCardId, anyOf(twoDiamonds.id, twoClubs.id));
      expect(opening.discardCardId, isNot(fourClubs.id));
      expect(opening.discardCardId, isNot(kingDiamonds.id));
      expect(opening.highlightCardIds, isNot(contains(opening.discardCardId)));
    });

    test('mid-opening with a joker guides to finish opening, not a cover', () {
      // Playtest joker bug: after staging the 10-set, the seat (not yet fully
      // opened) still holds a 5-set + two aces + a joker that finish the
      // opening. The coach must say "lay these to open" (openNow) — NOT suggest
      // covering the staged 10-set with the joker (cover-keep is premature until
      // fully opened). The staged 10-set's value counts toward the requirement.
      final joker = _joker();
      final tenSet = [
        _c(CardRank.ten, CardSuit.hearts),
        _c(CardRank.ten, CardSuit.clubs),
        _c(CardRank.ten, CardSuit.diamonds),
      ];
      final hand = [
        _c(CardRank.five, CardSuit.hearts),
        _c(CardRank.five, CardSuit.clubs),
        _c(CardRank.five, CardSuit.diamonds),
        _c(CardRank.ace, CardSuit.spades),
        _c(CardRank.ace, CardSuit.clubs),
        joker,
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        tableMelds: {
          PlayerSeat.south: [_meld(tenSet)],
        },
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          openedSeats: {},
        ),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(insights.first.category, CoachingInsightCategory.openNow);
      // The joker is framed as part of a meld to lay, not as a cover hint.
      expect(_has(insights, CoachingInsightCategory.playCover), isFalse);
      expect(insights.first.highlightCardIds, contains(joker.id));
    });

    test('a committed meld card does not inflate a deadwood neighbour', () {
      // Playtest: unopened with a 3-ace set (the keep partition) + a loose 2♥/3♥
      // + an isolated K♣. The A♥ is locked in the ace SET, so it must NOT count
      // as a heart-run partner (A-2-3) for the low hearts — otherwise they'd
      // out-score the King and the coach would wrongly shed the King. The
      // suggested discard must be a low heart, never the King.
      final kingClubs = _c(CardRank.king, CardSuit.clubs);
      final twoHearts = _c(CardRank.two, CardSuit.hearts);
      final threeHearts = _c(CardRank.three, CardSuit.hearts);
      final hand = [
        _c(CardRank.ace, CardSuit.spades),
        _c(CardRank.ace, CardSuit.hearts),
        _c(CardRank.ace, CardSuit.clubs),
        twoHearts,
        threeHearts,
        kingClubs,
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          openedSeats: {},
        ),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      final opening = _find(insights, CoachingInsightCategory.openingProgress);
      expect(opening.discardCardId, isNot(kingClubs.id));
      expect(opening.discardCardId, anyOf(twoHearts.id, threeHearts.id));
    });

    test('opening insights absent for an already-opened seat', () {
      final hand = [
        _c(CardRank.king, CardSuit.spades),
        _c(CardRank.queen, CardSuit.spades),
        _c(CardRank.jack, CardSuit.spades),
        _c(CardRank.two, CardSuit.hearts),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.openNow), isFalse);
      expect(_has(insights, CoachingInsightCategory.openingProgress), isFalse);
    });
  });

  group('playMeld', () {
    test('opened seat with a legal meld on the surface', () {
      final run = [
        _c(CardRank.eight, CardSuit.diamonds),
        _c(CardRank.nine, CardSuit.diamonds),
        _c(CardRank.ten, CardSuit.diamonds),
      ];
      final hand = [
        ...run,
        _c(CardRank.two, CardSuit.spades),
        _c(CardRank.four, CardSuit.hearts),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.playMeld), isTrue);
      final insight = _find(insights, CoachingInsightCategory.playMeld);
      expect(insight.meldActionId, isNotNull);
      expect(insight.highlightCardIds, isNotEmpty);
    });

    test('a complete in-hand meld outranks using a card for a cover', () {
      // Playtest regression: with three queens (a settable set) AND a J that
      // would cover the seat's own heart run, the coach must say "play the
      // queens" (playMeld, 700), never "use the queen/J for a cover" (cover,
      // <=550). A full meld is always better than breaking a card off.
      final queenHearts = _c(CardRank.queen, CardSuit.hearts);
      final queenSpades = _c(CardRank.queen, CardSuit.spades);
      final queenDiamonds = _c(CardRank.queen, CardSuit.diamonds);
      final jackHearts = _c(CardRank.jack, CardSuit.hearts);
      final tableRun = [
        _c(CardRank.ten, CardSuit.hearts),
        _c(CardRank.nine, CardSuit.hearts),
        _c(CardRank.eight, CardSuit.hearts),
      ];
      final hand = [
        queenHearts,
        queenSpades,
        queenDiamonds,
        jackHearts,
        _c(CardRank.two, CardSuit.spades),
        // Second loose card: queens + J-cover + ONE junk card would be a full
        // finish (set, cover, final discard), which correctly outranks the
        // meld hint; this test is about the non-finishing state.
        _c(CardRank.seven, CardSuit.diamonds),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        tableMelds: {
          PlayerSeat.south: [_meld(tableRun)],
        },
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(insights.first.category, CoachingInsightCategory.playMeld);
      final insight = _find(insights, CoachingInsightCategory.playMeld);
      expect(
        insight.highlightCardIds,
        containsAll([queenHearts.id, queenSpades.id, queenDiamonds.id]),
      );
    });

    test('combines a playable meld with an available lay-off cover', () {
      // Playtest: opened, holding a 5-6-7 club run to play AND a loose J♥ that
      // lays off onto NORTH's 8-9-10 heart run. The lay-off is on the legal
      // cover surface and the brain is not holding it (it extends an opponent's
      // run, not the seat's own — no own-run hold — and a 6-card hand is too far
      // from a finish for the Fifty-development hold). The coach surfaces BOTH
      // in one hint — the meld to play plus the cover — not the meld alone.
      final coverJack = _c(CardRank.jack, CardSuit.hearts);
      final hand = [
        _c(CardRank.five, CardSuit.clubs),
        _c(CardRank.six, CardSuit.clubs),
        _c(CardRank.seven, CardSuit.clubs),
        coverJack,
        _c(CardRank.two, CardSuit.spades),
        // Second loose card: run + cover + ONE junk card would be a full
        // finish, which correctly outranks the combined meld hint.
        _c(CardRank.nine, CardSuit.diamonds),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        tableMelds: {
          PlayerSeat.north: [
            _meld([
              _c(CardRank.eight, CardSuit.hearts),
              _c(CardRank.nine, CardSuit.hearts),
              _c(CardRank.ten, CardSuit.hearts),
            ]),
          ],
        },
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          openedSeats: {PlayerSeat.south, PlayerSeat.north},
        ),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(insights.first.category, CoachingInsightCategory.playMeld);
      final insight = _find(insights, CoachingInsightCategory.playMeld);
      expect(insight.coverCardId, coverJack.id);
      expect(insight.highlightCardIds, contains(coverJack.id));
      expect(
        insight.highlightCardIds,
        containsAll([hand[0].id, hand[1].id, hand[2].id]),
      );
    });

    test(
      'does NOT ride a cover the Expert posture holds (own-run extension)',
      () {
        // GAP 1 regression: opened, holding a 5-6-7 club run to play AND a J♥
        // that lays off onto the seat's OWN 8-9-10 heart run. That lay-off is a
        // legal cover, but the Expert brain HOLDS it as an own-run extension
        // (keep developing the run, do not burn the card early) — a NON-Fifty
        // hold reason. The play-meld rider narrates only a lay-off the brain
        // would lead with, so it must present the meld ALONE and never name the
        // held J♥. (Before honoring all hold reasons, the bespoke combine still
        // rang this own-run cover, narrating a play the brain declined.)
        final ownRunJack = _c(CardRank.jack, CardSuit.hearts);
        final hand = [
          _c(CardRank.five, CardSuit.clubs),
          _c(CardRank.six, CardSuit.clubs),
          _c(CardRank.seven, CardSuit.clubs),
          ownRunJack,
          _c(CardRank.two, CardSuit.spades),
          _c(CardRank.nine, CardSuit.diamonds),
        ];
        final scenario = ClassicHareegScenario.deal(
          setup: _coachingSetup(),
          southHand: hand,
          tableMelds: {
            PlayerSeat.south: [
              _meld([
                _c(CardRank.eight, CardSuit.hearts),
                _c(CardRank.nine, CardSuit.hearts),
                _c(CardRank.ten, CardSuit.hearts),
              ]),
            ],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: ScenarioCards.openedFor(PlayerSeat.south),
        );

        final insights = ClassicHareegCoachingAdvisor.adviseFor(
          scenario.controller,
          PlayerSeat.south,
        );

        final insight = _find(insights, CoachingInsightCategory.playMeld);
        expect(insight.coverCardId, isNull);
        expect(insight.highlightCardIds, isNot(contains(ownRunJack.id)));
        // The meld it leads with is still the club run.
        expect(
          insight.highlightCardIds,
          containsAll([hand[0].id, hand[1].id, hand[2].id]),
        );
      },
    );

    test('absent when the opened seat has no playable meld', () {
      final hand = [
        _c(CardRank.two, CardSuit.spades),
        _c(CardRank.five, CardSuit.hearts),
        _c(CardRank.nine, CardSuit.clubs),
        _c(CardRank.king, CardSuit.diamonds),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.playMeld), isFalse);
    });
  });

  group('pickupCompletesMeld', () {
    test('taking the discard pulls hand cards into a meld', () {
      final hand = [
        _c(CardRank.eight, CardSuit.diamonds),
        _c(CardRank.nine, CardSuit.diamonds),
        _c(CardRank.two, CardSuit.spades),
        _c(CardRank.five, CardSuit.hearts),
        _c(CardRank.king, CardSuit.clubs),
      ];
      final topDiscard = _c(CardRank.ten, CardSuit.diamonds);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        discardPile: [topDiscard],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(
        _has(insights, CoachingInsightCategory.pickupCompletesMeld),
        isTrue,
      );
      final insight = _find(
        insights,
        CoachingInsightCategory.pickupCompletesMeld,
      );
      expect(insight.highlightCardIds, contains(topDiscard.id));
    });

    test('absent when the discard does not help any meld', () {
      final hand = [
        _c(CardRank.eight, CardSuit.diamonds),
        _c(CardRank.nine, CardSuit.diamonds),
        _c(CardRank.two, CardSuit.spades),
        _c(CardRank.five, CardSuit.hearts),
        _c(CardRank.king, CardSuit.clubs),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        discardPile: [_c(CardRank.four, CardSuit.hearts)],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(
        _has(insights, CoachingInsightCategory.pickupCompletesMeld),
        isFalse,
      );
    });
  });

  group('cover (Expert-plan driven)', () {
    // Cover advice mirrors the Expert plan's chosen move (CPU-first). The coach
    // never re-derives its own cover decision, so it inherits the brain's
    // Fifty-hold / never-burn-a-joker posture instead of diverging from it.
    test('surfaces the lay-off when the brain covers a loose card', () {
      // 8♣ is loose (no partner in a 6-card hand, so no Fifty-hold) and the
      // brain lays it off onto north's 5-6-7 club run. The coach presents it.
      final cover = _c(CardRank.eight, CardSuit.clubs);
      final hand = [
        cover,
        _c(CardRank.king, CardSuit.diamonds),
        _c(CardRank.queen, CardSuit.hearts),
        _c(CardRank.two, CardSuit.spades),
        _c(CardRank.nine, CardSuit.hearts),
        _c(CardRank.four, CardSuit.diamonds),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        tableMelds: {
          PlayerSeat.north: [
            _meld([
              _c(CardRank.five, CardSuit.clubs),
              _c(CardRank.six, CardSuit.clubs),
              _c(CardRank.seven, CardSuit.clubs),
            ]),
          ],
        },
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(insights.first.category, CoachingInsightCategory.playCover);
      final insight = _find(insights, CoachingInsightCategory.playCover);
      expect(insight.coverCardId, cover.id);
      expect(insight.highlightCardIds, contains(cover.id));
      expect(insight.coverFinishes, isFalse);
      expect(insight.coverIsChoice, isFalse);
    });

    test(
      'finish-by-cover in a cover-only endgame never blacks out (Issue A)',
      () {
        // Cover-only endgame: the seat's two cards each lay off onto an opponent
        // meld and there is no plain safe discard. The old bespoke detector
        // blacked out here (covers on opponent melds, no own-meld cover, the
        // lay-off hint bailed on the empty safe-discard set). The engine-plan
        // path now surfaces the SIMPLEST win: cover the 5♠ onto East's run, then
        // close with the 10♥ — legal as the FINAL discard even though it is
        // cover-blocked as a plain throw.
        final tenHearts = _c(CardRank.ten, CardSuit.hearts);
        final fiveSpades = _c(CardRank.five, CardSuit.spades);
        final scenario = ClassicHareegScenario.deal(
          setup: _coachingSetup(),
          southHand: [tenHearts, fiveSpades],
          tableMelds: {
            PlayerSeat.north: [
              _meld([
                _c(CardRank.seven, CardSuit.hearts),
                _c(CardRank.eight, CardSuit.hearts),
                _c(CardRank.nine, CardSuit.hearts),
              ]),
            ],
            PlayerSeat.east: [
              _meld([
                _c(CardRank.two, CardSuit.spades),
                _c(CardRank.three, CardSuit.spades),
                _c(CardRank.four, CardSuit.spades),
              ]),
            ],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: ScenarioCards.openedFor(PlayerSeat.south),
        );

        final insights = ClassicHareegCoachingAdvisor.adviseFor(
          scenario.controller,
          PlayerSeat.south,
        );

        expect(insights, isNotEmpty); // regression: never black out
        expect(
          insights.first.category,
          CoachingInsightCategory.finishAvailable,
        );
        expect(insights.first.coverFinishes, isTrue);
        // The 5♠ lay-off rings as the play; the 10♥ is the named closing throw.
        expect(insights.first.highlightCardIds, contains(fiveSpades.id));
        expect(insights.first.discardCardId, tenHearts.id);
      },
    );

    test('holds for a Fifty rather than covering away a card (Issue C)', () {
      // Opened, 3 cards, deep stock, a developing diamond run (8♦-10♦). 10♠
      // could cover north's spade run, but covering sheds a card and kills the
      // Fifty, so the brain holds. The coach must NOT push the cover; it shows
      // the brain's actual move (a discard) instead.
      final eightDiamonds = _c(CardRank.eight, CardSuit.diamonds);
      final tenDiamonds = _c(CardRank.ten, CardSuit.diamonds);
      final tenSpades = _c(CardRank.ten, CardSuit.spades);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: [eightDiamonds, tenDiamonds, tenSpades],
        tableMelds: {
          PlayerSeat.north: [
            _meld([
              _c(CardRank.seven, CardSuit.spades),
              _c(CardRank.eight, CardSuit.spades),
              _c(CardRank.nine, CardSuit.spades),
            ]),
          ],
        },
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.playCover), isFalse);
      expect(insights.where((insight) => insight.coverFinishes), isEmpty);
      expect(
        insights.first.category,
        CoachingInsightCategory.discardSuggestion,
      );
      // Playtest regression: the hold must be NARRATED, not silent — a
      // freshly drawn cover the coach says nothing about reads as blindness.
      // The discard hint names the held 10♠, why it stays (Fifty
      // development), and never recommends throwing the held card itself.
      final discard = insights.first;
      expect(discard.coverCardId, tenSpades.id);
      expect(discard.holdCoverReason, CoachCoverHoldReason.fiftyDevelopment);
      expect(discard.discardCardId, isNot(tenSpades.id));
      // The held cover and its target meld ring as a keep group.
      expect(discard.meldGroups, hasLength(1));
      expect(discard.meldGroups.single, contains(tenSpades.id));
    });

    test('never pushes a held joker onto a cover (Issue B)', () {
      // A joker could extend the club run, but the brain never burns a joker on
      // a cover — it holds it for a finish/Fifty. The coach must not ring the
      // joker. (The CPU-level posture is covered in expert_cpu_move_planner_test.)
      final joker = _joker();
      final hand = [
        joker,
        _c(CardRank.king, CardSuit.diamonds),
        _c(CardRank.queen, CardSuit.hearts),
        _c(CardRank.three, CardSuit.spades),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        tableMelds: {
          PlayerSeat.north: [
            _meld([
              _c(CardRank.five, CardSuit.clubs),
              _c(CardRank.six, CardSuit.clubs),
              _c(CardRank.seven, CardSuit.clubs),
            ]),
          ],
        },
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      for (final cover in insights.where(
        (insight) => insight.category == CoachingInsightCategory.playCover,
      )) {
        expect(cover.coverCardId, isNot(joker.id));
        expect(cover.highlightCardIds, isNot(contains(joker.id)));
      }
      for (final finish in insights.where((insight) => insight.coverFinishes)) {
        expect(finish.highlightCardIds, isNot(contains(joker.id)));
      }
    });
  });

  group('jokerAdvice', () {
    test('joker swap outranks melding away the swap card (playtest)', () {
      // Table: 7♣–joker(8♣)–9♣. Hand: 8♥ 8♦ + a drawn 8♣ (+ junk so the meld
      // is not a finish). The coach said "you can lay down a meld" for the
      // natural 8s — but melding burns the 8♣ that could reclaim the joker.
      // The swap is free and must lead, with the 8s combo folded in as a
      // ring group instead of shadowed.
      final jokerEight = _joker().asRepresenting(
        const CardIdentity(rank: CardRank.eight, suit: CardSuit.clubs),
      );
      final tableRun = [
        _c(CardRank.seven, CardSuit.clubs),
        jokerEight,
        _c(CardRank.nine, CardSuit.clubs),
      ];
      final eightHearts = _c(CardRank.eight, CardSuit.hearts);
      final eightDiamonds = _c(CardRank.eight, CardSuit.diamonds);
      final eightClubs = _c(CardRank.eight, CardSuit.clubs, deckIndex: 3);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: [
          eightHearts,
          eightDiamonds,
          eightClubs,
          _c(CardRank.two, CardSuit.spades),
          _c(CardRank.king, CardSuit.diamonds),
        ],
        tableMelds: {
          PlayerSeat.north: [_meld(tableRun)],
        },
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          openedSeats: {PlayerSeat.south, PlayerSeat.north},
        ),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(insights.first.category, CoachingInsightCategory.jokerAdvice);
      final advice = insights.first;
      expect(advice.jokerCardId, eightClubs.id);
      // The 8s combo rides along as a ring group (the presenter teaches
      // "swap first — the meld still works with the freed joker").
      expect(advice.meldGroups, hasLength(1));
      expect(
        advice.meldGroups.single,
        containsAll([eightHearts.id, eightDiamonds.id, eightClubs.id]),
      );
      // The meld hint still exists below the swap, never above it.
      expect(_has(insights, CoachingInsightCategory.playMeld), isTrue);
    });

    test('seat can replace a represented joker on the table', () {
      // North owns a run where the middle card is a represented joker; South
      // holds the real nine of diamonds and can swap it in.
      final jokerNine = _joker().asRepresenting(
        const CardIdentity(rank: CardRank.nine, suit: CardSuit.diamonds),
      );
      final tableRun = [
        _c(CardRank.eight, CardSuit.diamonds),
        jokerNine,
        _c(CardRank.ten, CardSuit.diamonds),
      ];
      final realNine = _c(CardRank.nine, CardSuit.diamonds, deckIndex: 3);
      final hand = [
        realNine,
        _c(CardRank.two, CardSuit.spades),
        _c(CardRank.five, CardSuit.hearts),
        _c(CardRank.king, CardSuit.clubs),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        tableMelds: {
          PlayerSeat.north: [_meld(tableRun)],
        },
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.jokerAdvice), isTrue);
      final insight = _find(insights, CoachingInsightCategory.jokerAdvice);
      expect(insight.jokerReplacementActionId, isNotNull);
      expect(insight.jokerCardId, realNine.id);
      // Regression: rings the hand card AND the table meld holding the joker, so
      // the player sees where the swap happens (not just which card to use).
      expect(insight.highlightCardIds, contains(realNine.id));
      expect(
        insight.highlightCardIds,
        containsAll([tableRun[0].id, jokerNine.id, tableRun[2].id]),
      );
    });

    test('absent when no table joker can be replaced', () {
      final tableRun = [
        _c(CardRank.eight, CardSuit.diamonds),
        _c(CardRank.nine, CardSuit.diamonds),
        _c(CardRank.ten, CardSuit.diamonds),
      ];
      final hand = [
        _c(CardRank.two, CardSuit.spades),
        _c(CardRank.five, CardSuit.hearts),
        _c(CardRank.king, CardSuit.clubs),
        _c(CardRank.four, CardSuit.hearts),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        tableMelds: {
          PlayerSeat.north: [_meld(tableRun)],
        },
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.jokerAdvice), isFalse);
    });
  });

  group('hold-back warning (threat fold-in)', () {
    // South's hand for most cases: the NAIVE throw (lowest keep-score) is the
    // lone 9♥; the K♦ is the safe alternative; Q♠+J♠ are run partners worth
    // keeping. The warning must fire ONLY when the naive throw is materially
    // threatened AND the recommendation dodges it.
    final southNine = _c(CardRank.nine, CardSuit.hearts, deckIndex: 4);
    final kingDiamonds = _c(CardRank.king, CardSuit.diamonds);
    List<HareegCard> warnableHand() => [
      southNine,
      kingDiamonds,
      _c(CardRank.queen, CardSuit.spades),
      _c(CardRank.jack, CardSuit.spades),
    ];

    test('warns when the natural throw feeds a collector, naming a safer '
        'card', () {
      // East picked up a nine: the rank tell. South's cheapest throw is its
      // own nine — the coach must steer to the King and explain the hold-back.
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: warnableHand(),
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
        discardHistoryEvents: [
          DiscardEvent(
            seat: PlayerSeat.east,
            card: _c(CardRank.nine, CardSuit.clubs),
            kind: DiscardEventKind.pickup,
            sequence: 0,
          ),
        ],
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      final suggestion = _find(
        insights,
        CoachingInsightCategory.discardSuggestion,
      );
      expect(suggestion.avoidCardId, southNine.id);
      expect(suggestion.avoidOpponent, PlayerSeat.east);
      expect(suggestion.avoidReason, CoachAvoidReason.collecting);
      expect(suggestion.avoidRank, CardRank.nine);
      expect(suggestion.discardCardId, isNot(southNine.id));
    });

    test('silent when the natural throw is already safe', () {
      // Same nine pickup, but South's cheapest throw is a harmless 2♠ — the
      // warning would not change the decision, so it must not fire (the
      // playtest fixation: warning on every turn regardless of relevance).
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: [
          southNine,
          _c(CardRank.two, CardSuit.spades),
          _c(CardRank.five, CardSuit.diamonds),
          _c(CardRank.king, CardSuit.hearts),
        ],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
        discardHistoryEvents: [
          DiscardEvent(
            seat: PlayerSeat.east,
            card: _c(CardRank.nine, CardSuit.clubs),
            kind: DiscardEventKind.pickup,
            sequence: 0,
          ),
        ],
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      final suggestion = _find(
        insights,
        CoachingInsightCategory.discardSuggestion,
      );
      expect(suggestion.avoidCardId, isNull);
      expect(suggestion.discardCardId, isNot(southNine.id));
    });

    test('an opponent merely DISCARDING a card is not "collecting" it', () {
      // East discarded a nine (threw it away). A discard means the opponent
      // did NOT want it, so it must not flag South's nine as risky — only
      // deliberate pickups count. The turn-one false-positive the playtest
      // surfaced.
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: warnableHand(),
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
        discardHistoryEvents: [
          DiscardEvent(
            seat: PlayerSeat.east,
            card: _c(CardRank.nine, CardSuit.clubs),
            kind: DiscardEventKind.discard,
            sequence: 0,
          ),
        ],
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      final suggestion = _find(
        insights,
        CoachingInsightCategory.discardSuggestion,
      );
      expect(suggestion.avoidCardId, isNull);
    });

    test('tells from an opponent down to a few cards are stale', () {
      // The owner's playtest complaint: East picked up a nine early, then
      // melded down to two cards. It has stopped collecting from the pile —
      // the warning must not keep firing on its stale tell.
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: warnableHand(),
        eastHand: [
          _c(CardRank.two, CardSuit.diamonds, deckIndex: 7),
          _c(CardRank.six, CardSuit.spades, deckIndex: 7),
        ],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          openedSeats: {PlayerSeat.south, PlayerSeat.east},
        ),
        discardHistoryEvents: [
          DiscardEvent(
            seat: PlayerSeat.east,
            card: _c(CardRank.nine, CardSuit.clubs),
            kind: DiscardEventKind.pickup,
            sequence: 0,
          ),
        ],
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      final suggestion = _find(
        insights,
        CoachingInsightCategory.discardSuggestion,
      );
      expect(suggestion.avoidCardId, isNull);
      // The right teaching for that opponent is the close-to-finish banner.
      expect(
        _has(insights, CoachingInsightCategory.opponentCloseToFinish),
        isTrue,
      );
    });

    test('a pickup the opponent has since melded onto the table is spent', () {
      // East picked up the 9♣ and later laid it in a visible set: the tell is
      // consumed — South's nine is no longer evidence of collecting.
      final pickedUp = _c(CardRank.nine, CardSuit.clubs);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: warnableHand(),
        tableMelds: {
          PlayerSeat.east: [
            _meld([
              pickedUp,
              _c(CardRank.nine, CardSuit.spades, deckIndex: 7),
              _c(CardRank.nine, CardSuit.diamonds, deckIndex: 7),
            ]),
          ],
        },
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          openedSeats: {PlayerSeat.south, PlayerSeat.east},
        ),
        discardHistoryEvents: [
          DiscardEvent(
            seat: PlayerSeat.east,
            card: pickedUp,
            kind: DiscardEventKind.pickup,
            sequence: 0,
          ),
        ],
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      final suggestion = _find(
        insights,
        CoachingInsightCategory.discardSuggestion,
      );
      expect(suggestion.avoidCardId, isNull);
    });

    test('a suit pickup only marks adjacent ranks, not the whole suit', () {
      // East picked up the 2♣. South's cheapest throw is a 9♣ — same suit but
      // seven ranks away, no plausible run neighbour. The old suit-wide match
      // (one clubs pickup poisons every club) was the fixation bug.
      final nineClubs = _c(CardRank.nine, CardSuit.clubs, deckIndex: 4);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: [
          nineClubs,
          kingDiamonds,
          _c(CardRank.queen, CardSuit.spades),
          _c(CardRank.jack, CardSuit.spades),
        ],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
        discardHistoryEvents: [
          DiscardEvent(
            seat: PlayerSeat.east,
            card: _c(CardRank.two, CardSuit.clubs),
            kind: DiscardEventKind.pickup,
            sequence: 0,
          ),
        ],
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      final suggestion = _find(
        insights,
        CoachingInsightCategory.discardSuggestion,
      );
      expect(suggestion.avoidCardId, isNull);
      expect(suggestion.discardCardId, nineClubs.id);
    });

    test('a suit pickup at adjacent rank IS a run tell', () {
      // East picked up the 8♣; South's cheapest throw is the 9♣ — a direct
      // run neighbour. Warn and steer to the King.
      final nineClubs = _c(CardRank.nine, CardSuit.clubs, deckIndex: 4);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: [
          nineClubs,
          kingDiamonds,
          _c(CardRank.queen, CardSuit.spades),
          _c(CardRank.jack, CardSuit.spades),
        ],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
        discardHistoryEvents: [
          DiscardEvent(
            seat: PlayerSeat.east,
            card: _c(CardRank.eight, CardSuit.clubs),
            kind: DiscardEventKind.pickup,
            sequence: 0,
          ),
        ],
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      final suggestion = _find(
        insights,
        CoachingInsightCategory.discardSuggestion,
      );
      expect(suggestion.avoidCardId, nineClubs.id);
      expect(suggestion.avoidReason, CoachAvoidReason.collecting);
      expect(suggestion.avoidSuit, CardSuit.clubs);
      expect(suggestion.discardCardId, isNot(nineClubs.id));
    });

    // NOTE: there is deliberately no run-end fold-in case here. A card that
    // extends a visible table meld is cover-blocked from plain discard by the
    // rules, so it never appears on the legal safe-discard surface the
    // guidance picks from. The runEnd threat branch stays for parity with the
    // Expert danger model (and any future tier where cover-discards are
    // legal), but it cannot fire on the Coaching tier's legal surface.

    test('silent when every legal throw is threatened', () {
      // East collects both ranks South holds. A warning with no safer
      // alternative is noise the player cannot act on.
      final nineHearts = _c(CardRank.nine, CardSuit.hearts, deckIndex: 4);
      final queenHearts = _c(CardRank.queen, CardSuit.hearts, deckIndex: 4);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: [nineHearts, queenHearts],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
        discardHistoryEvents: [
          DiscardEvent(
            seat: PlayerSeat.east,
            card: _c(CardRank.nine, CardSuit.clubs),
            kind: DiscardEventKind.pickup,
            sequence: 0,
          ),
          DiscardEvent(
            seat: PlayerSeat.east,
            card: _c(CardRank.queen, CardSuit.clubs),
            kind: DiscardEventKind.pickup,
            sequence: 1,
          ),
        ],
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      final suggestion = _find(
        insights,
        CoachingInsightCategory.discardSuggestion,
      );
      expect(suggestion.avoidCardId, isNull);
    });

    test('rides the opening-progress hint for an unopened seat', () {
      // The fixation's worst case was pre-opening: the standalone warning
      // permanently shadowed opening guidance. Now it rides ON the opening
      // hint instead — keep cards ringed, a safe build-discard named, and the
      // hot card held back.
      final nineHearts = _c(CardRank.nine, CardSuit.hearts, deckIndex: 4);
      final kingClubs = _c(CardRank.king, CardSuit.clubs);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: [
          _c(CardRank.eight, CardSuit.diamonds),
          _c(CardRank.nine, CardSuit.diamonds),
          _c(CardRank.ten, CardSuit.diamonds),
          nineHearts,
          kingClubs,
        ],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          openedSeats: {},
        ),
        discardHistoryEvents: [
          DiscardEvent(
            seat: PlayerSeat.east,
            card: _c(CardRank.nine, CardSuit.clubs),
            kind: DiscardEventKind.pickup,
            sequence: 0,
          ),
        ],
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      final opening = _find(insights, CoachingInsightCategory.openingProgress);
      expect(opening.avoidCardId, nineHearts.id);
      expect(opening.avoidOpponent, PlayerSeat.east);
      expect(opening.discardCardId, kingClubs.id);
      // No standalone warning category exists to shadow the opening guidance.
      expect(insights.first.category, CoachingInsightCategory.openingProgress);
    });
  });

  group('fiftyHold', () {
    final finishingHand = [
      _c(CardRank.eight, CardSuit.diamonds),
      _c(CardRank.nine, CardSuit.diamonds),
      _c(CardRank.ten, CardSuit.diamonds),
      _c(CardRank.five, CardSuit.clubs),
      _c(CardRank.six, CardSuit.clubs),
      _c(CardRank.seven, CardSuit.clubs),
      _c(CardRank.two, CardSuit.spades),
    ];

    test('replaces the finish hint when Expert would hold for a Fifty', () {
      // Finishing hand, deep stock, heavy pips, and WEST — the seat that
      // discards immediately before South, the only seat a Fifty claimed by
      // South can punish — at high-risk score: Expert holds the finish, so
      // the coach explains the hold instead of contradicting the brain with
      // "you can win".
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: finishingHand,
        scores: const {PlayerSeat.west: 27},
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.finishAvailable), isFalse);
      final hold = _find(insights, CoachingInsightCategory.fiftyHold);
      expect(insights.first.category, CoachingInsightCategory.fiftyHold);
      expect(hold.subjectSeat, PlayerSeat.west);
      expect(hold.subjectIsSelf, isFalse);
      expect(hold.subjectValue, 27);
      // The finish partition still rings so the player sees the choice.
      expect(hold.highlightCardIds, isNotEmpty);
      // The hold names the throw that keeps it alive (playtest: the hint
      // said "hold" but never said how to end the turn) — here the junk 2♠.
      expect(hold.discardCardId, finishingHand.last.id);
    });

    test(
      'plain finish when only an unpunishable opponent is at high score',
      () {
        // East acts AFTER South, so a Fifty claimed by South can never hit East
        // — its high score does not justify the gamble. (Playtest: the hint
        // implied the high scorer across the table would pay the +3, but only
        // the seat discarding right before you ever does.)
        final scenario = ClassicHareegScenario.deal(
          setup: _coachingSetup(),
          southHand: finishingHand,
          scores: const {PlayerSeat.east: 27},
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: ScenarioCards.openedFor(PlayerSeat.south),
        );

        final insights = ClassicHareegCoachingAdvisor.adviseFor(
          scenario.controller,
          PlayerSeat.south,
        );

        expect(
          insights.first.category,
          CoachingInsightCategory.finishAvailable,
        );
        expect(_has(insights, CoachingInsightCategory.fiftyHold), isFalse);
      },
    );

    test('names the player when their own score motivates the hold', () {
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: finishingHand,
        scores: const {PlayerSeat.south: 26},
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      final hold = _find(insights, CoachingInsightCategory.fiftyHold);
      expect(hold.subjectIsSelf, isTrue);
      expect(hold.subjectValue, 26);
    });

    test('hold-discard is cover-aware: never recommends a blocked throw', () {
      // Playtest hand: A♥ K♥ joker + J♠, where the J♠ covers North's spade
      // run. The finish is "meld the hearts run (joker as Q♥), throw the J♠"
      // — legal because the FINAL discard is exempt from the cover block. But
      // to HOLD for a Fifty the player must end the turn with a plain throw,
      // and the J♠ cannot leave that way. The hold guidance must come off the
      // legal surface: break the hearts pair, never name the blocked J♠.
      final tableRun = [
        _c(CardRank.eight, CardSuit.spades),
        _c(CardRank.nine, CardSuit.spades),
        _c(CardRank.ten, CardSuit.spades),
      ];
      final coverJack = _c(CardRank.jack, CardSuit.spades);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: [
          _c(CardRank.ace, CardSuit.hearts),
          _c(CardRank.king, CardSuit.hearts),
          _joker(),
          coverJack,
        ],
        tableMelds: {
          PlayerSeat.north: [_meld(tableRun)],
        },
        scores: const {PlayerSeat.west: 27},
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          openedSeats: {PlayerSeat.south, PlayerSeat.north},
        ),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      final hold = _find(insights, CoachingInsightCategory.fiftyHold);
      expect(hold.discardCardId, isNotNull);
      expect(hold.discardCardId, isNot(coverJack.id));
    });

    test('hold-discard falls back to the safe surface when the plan is a cover', () {
      // GAP 2 regression: a fiftyHold where the Expert plan's chosen move this
      // turn is NOT a safe discard. The hand is two complete runs (9-10-J♦,
      // 5-6-7♣) plus a J♠ that lays off onto NORTH's 8-9-10♠ run. The whole
      // hand finishes (both runs + the J♠ as the final discard), and the brain
      // HOLDS that finish for a Fifty (deep stock, heavy pips, West at risk).
      // With seven cards the Fifty-development cover hold (≤5 cards) does not
      // apply, so the brain's actual move this turn is the COVER, not a discard
      // — meaning [expertDiscardId] is null. The hold hint must still carry a
      // non-null throw off the legal-safe-discard surface, or the presenter
      // silently drops the "throw this to keep the hold alive" suffix (the gap).
      // The named throw must never be the cover-blocked J♠.
      final coverJack = _c(CardRank.jack, CardSuit.spades);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: [
          _c(CardRank.nine, CardSuit.diamonds),
          _c(CardRank.ten, CardSuit.diamonds),
          _c(CardRank.jack, CardSuit.diamonds),
          _c(CardRank.five, CardSuit.clubs),
          _c(CardRank.six, CardSuit.clubs),
          _c(CardRank.seven, CardSuit.clubs),
          coverJack,
        ],
        tableMelds: {
          PlayerSeat.north: [
            _meld([
              _c(CardRank.eight, CardSuit.spades),
              _c(CardRank.nine, CardSuit.spades),
              _c(CardRank.ten, CardSuit.spades),
            ]),
          ],
        },
        scores: const {PlayerSeat.west: 27},
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          openedSeats: {PlayerSeat.south, PlayerSeat.north},
        ),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      final hold = _find(insights, CoachingInsightCategory.fiftyHold);
      expect(insights.first.category, CoachingInsightCategory.fiftyHold);
      // The fallback names a real throw off the legal-safe-discard surface —
      // never the cover-blocked J♠.
      expect(hold.discardCardId, isNotNull);
      expect(hold.discardCardId, isNot(coverJack.id));
    });

    test('plain finish when no one is at high-risk score', () {
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: finishingHand,
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(insights.first.category, CoachingInsightCategory.finishAvailable);
      expect(_has(insights, CoachingInsightCategory.fiftyHold), isFalse);
    });
  });

  group('takeAndFinish', () {
    final nearFinishHand = [
      _c(CardRank.eight, CardSuit.diamonds),
      _c(CardRank.nine, CardSuit.diamonds),
      _c(CardRank.five, CardSuit.clubs),
      _c(CardRank.six, CardSuit.clubs),
      _c(CardRank.seven, CardSuit.clubs),
      _c(CardRank.two, CardSuit.spades),
    ];

    test('takes over when the Fifty claim window has lapsed', () {
      // The 10♦ tops the pile and completes 8-9-10♦; the rest of the hand is
      // a complete run + the final discard. The restored window's timer has
      // long expired (real clock vs the 2026-05-24 save), so the claim is no
      // longer on the legal surface — but the finish is still there for −1.
      // The claim-vs-take lesson, live.
      final ten = _c(CardRank.ten, CardSuit.diamonds);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: nearFinishHand,
        discardPile: [ten],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(insights.first.category, CoachingInsightCategory.takeAndFinish);
      final take = _find(insights, CoachingInsightCategory.takeAndFinish);
      expect(take.highlightCardIds, contains(ten.id));
    });

    test('yields to the Fifty claim while the window is the seat\'s', () {
      final ten = _c(CardRank.ten, CardSuit.diamonds);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: nearFinishHand,
        discardPile: [ten],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
        fiftyWindowOpenedAt: DateTime.utc(2026, 5, 24),
        now: () => DateTime.utc(2026, 5, 24, 0, 0, 1),
      );

      expect(scenario.controller.fiftyClaimant, PlayerSeat.south);

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.takeAndFinish), isFalse);
      expect(insights.first.category, CoachingInsightCategory.fiftyAvailable);
    });

    test('absent when the discard does not finish the hand', () {
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: nearFinishHand,
        discardPile: [_c(CardRank.king, CardSuit.hearts)],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.takeAndFinish), isFalse);
    });

    test('detects a cover-routed take-and-finish', () {
      // Taking the 7♣ completes 5-6-7♣, the J♠ lays off onto North's spade
      // run, and the 2♥ closes — a finish the old melds-only proof missed
      // (it under-promised on every cover-routed take).
      final seven = _c(CardRank.seven, CardSuit.clubs);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: [
          _c(CardRank.five, CardSuit.clubs),
          _c(CardRank.six, CardSuit.clubs),
          _c(CardRank.jack, CardSuit.spades),
          _c(CardRank.two, CardSuit.hearts),
        ],
        discardPile: [seven],
        tableMelds: {
          PlayerSeat.north: [
            _meld([
              _c(CardRank.eight, CardSuit.spades),
              _c(CardRank.nine, CardSuit.spades),
              _c(CardRank.ten, CardSuit.spades),
            ]),
          ],
        },
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          openedSeats: {PlayerSeat.south, PlayerSeat.north},
        ),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(insights.first.category, CoachingInsightCategory.takeAndFinish);
      expect(insights.first.highlightCardIds, contains(seven.id));
    });
  });

  group('baitDiscard', () {
    test('flags a pickup that fits the hand but cannot open', () {
      // Unopened South with a low pair; the third 2 completes a set worth far
      // below the 51 requirement. Taking it only reveals the plan — the bait
      // lesson, surfaced instead of silence.
      final bait = _c(CardRank.two, CardSuit.diamonds);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: [
          _c(CardRank.two, CardSuit.spades),
          _c(CardRank.two, CardSuit.hearts),
          _c(CardRank.nine, CardSuit.clubs),
          _c(CardRank.king, CardSuit.diamonds),
        ],
        discardPile: [bait],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          openedSeats: {},
        ),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(
        _has(insights, CoachingInsightCategory.pickupCompletesMeld),
        isFalse,
      );
      final baitInsight = _find(insights, CoachingInsightCategory.baitDiscard);
      expect(baitInsight.highlightCardIds, contains(bait.id));
    });

    test('absent for an opened seat — any completing pickup is fine', () {
      final bait = _c(CardRank.two, CardSuit.diamonds);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: [
          _c(CardRank.two, CardSuit.spades),
          _c(CardRank.two, CardSuit.hearts),
          _c(CardRank.nine, CardSuit.clubs),
          _c(CardRank.king, CardSuit.diamonds),
        ],
        discardPile: [bait],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.baitDiscard), isFalse);
      expect(
        _has(insights, CoachingInsightCategory.pickupCompletesMeld),
        isTrue,
      );
    });
  });

  group('stage banners', () {
    test('scorePosture: own high-risk score', () {
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        scores: const {PlayerSeat.south: 27},
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      final posture = _find(insights, CoachingInsightCategory.scorePosture);
      expect(posture.subjectIsSelf, isTrue);
      expect(posture.subjectValue, 27);
      expect(posture.subjectThreshold, isNotNull);
    });

    test('scorePosture: opponent at elimination-target score', () {
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        scores: const {PlayerSeat.west: 29},
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      final posture = _find(insights, CoachingInsightCategory.scorePosture);
      expect(posture.subjectIsSelf, isFalse);
      expect(posture.subjectSeat, PlayerSeat.west);
      expect(posture.subjectValue, 29);
    });

    test('scorePosture: absent at calm scores', () {
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        scores: const {PlayerSeat.south: 10, PlayerSeat.east: 24},
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.scorePosture), isFalse);
    });

    test('endgameStockLow fires at the Expert thin-stock threshold', () {
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        stock: [
          _c(CardRank.three, CardSuit.spades, deckIndex: 7),
          _c(CardRank.four, CardSuit.diamonds, deckIndex: 7),
          _c(CardRank.five, CardSuit.spades, deckIndex: 7),
        ],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      final banner = _find(insights, CoachingInsightCategory.endgameStockLow);
      expect(banner.subjectValue, 3);
    });

    test('opponentCloseToFinish names the shortest opened opponent hand', () {
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        eastHand: [
          _c(CardRank.two, CardSuit.diamonds, deckIndex: 7),
          _c(CardRank.six, CardSuit.spades, deckIndex: 7),
        ],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          openedSeats: {PlayerSeat.east},
        ),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      final banner = _find(
        insights,
        CoachingInsightCategory.opponentCloseToFinish,
      );
      expect(banner.subjectSeat, PlayerSeat.east);
      expect(banner.subjectValue, 2);
    });

    test('benchmarkAlert fires only on a raised, foreign benchmark', () {
      final raised = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 68,
          openedSeats: {PlayerSeat.west},
          benchmarkOwner: PlayerSeat.west,
        ),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        raised.controller,
        PlayerSeat.south,
      );

      final banner = _find(insights, CoachingInsightCategory.benchmarkAlert);
      expect(banner.subjectSeat, PlayerSeat.west);
      expect(banner.openingRequirement, 68);

      final unraised = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          openedSeats: {PlayerSeat.west},
        ),
      );

      expect(
        _has(
          ClassicHareegCoachingAdvisor.adviseFor(
            unraised.controller,
            PlayerSeat.south,
          ),
          CoachingInsightCategory.benchmarkAlert,
        ),
        isFalse,
      );
    });

    test('benchmarkAlert goes quiet once the benchmark locks', () {
      // Playtest regression: a second player opening LOCKS the benchmark —
      // it can never rise again, so "can keep raising until a second player
      // opens" was stale and factually wrong on the table.
      final locked = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 60,
          openedSeats: {PlayerSeat.west, PlayerSeat.north},
          benchmarkOwner: PlayerSeat.west,
          isLocked: true,
        ),
      );

      expect(
        _has(
          ClassicHareegCoachingAdvisor.adviseFor(
            locked.controller,
            PlayerSeat.south,
          ),
          CoachingInsightCategory.benchmarkAlert,
        ),
        isFalse,
      );
    });
  });

  group('draw-phase gating (playtest joker-set fixation)', () {
    test('a meldable hand must not hijack the draw phase', () {
      // Playtest regression: an opened seat holding a ready set (joker
      // included) was told "lay this meld / hold it for a Fifty" all through
      // the DRAW phase — while the actual decision was draw-vs-take. A meld
      // can only be laid after drawing, so playMeld is action-phase only.
      final hand = [
        _c(CardRank.five, CardSuit.hearts),
        _c(CardRank.five, CardSuit.clubs),
        _joker(),
        _c(CardRank.two, CardSuit.spades),
        _c(CardRank.king, CardSuit.diamonds),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        discardPile: [_c(CardRank.nine, CardSuit.spades, deckIndex: 7)],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.playMeld), isFalse);
      expect(insights.first.category, CoachingInsightCategory.drawStock);

      // After actually drawing, the meld guidance takes over.
      final drawResult = scenario.south.drawStock();
      expect(drawResult.isSuccess, isTrue);
      final actionInsights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );
      expect(_has(actionInsights, CoachingInsightCategory.playMeld), isTrue);
    });

    test('a requirement-meeting unopened hand defers openNow until after the '
        'draw', () {
      final hand = [
        _c(CardRank.king, CardSuit.spades),
        _c(CardRank.king, CardSuit.hearts),
        _c(CardRank.king, CardSuit.diamonds),
        _c(CardRank.queen, CardSuit.spades),
        _c(CardRank.queen, CardSuit.hearts),
        _c(CardRank.queen, CardSuit.diamonds),
        // Two loose cards so the post-draw hand can OPEN but never fully
        // finish (two leftovers beyond the final discard can't be consumed)
        // — with the sets alone, drawing any card made the hand a complete
        // win and finishAvailable correctly outranked the openNow this test
        // pins.
        _c(CardRank.two, CardSuit.clubs),
        _c(CardRank.eight, CardSuit.hearts),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        discardPile: [_c(CardRank.two, CardSuit.spades, deckIndex: 7)],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          openedSeats: {},
        ),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.openNow), isFalse);
      expect(insights.first.category, CoachingInsightCategory.drawStock);
      // The draw hint carries the "you can already open" signal: progress
      // folded in with a zero shortfall.
      final draw = _find(insights, CoachingInsightCategory.drawStock);
      expect(draw.openingShortfall, 0);
      expect(draw.openingBestValue, greaterThanOrEqualTo(51));

      // After the draw, openNow surfaces.
      final drawResult = scenario.south.drawStock();
      expect(drawResult.isSuccess, isTrue);
      final actionInsights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );
      expect(actionInsights.first.category, CoachingInsightCategory.openNow);
    });
  });

  group('discardSuggestion', () {
    test('recommends a discard when the seat owes one and cannot play', () {
      // Opened seat, action phase, a disconnected hand with no meld to play:
      // the coach should name a card to discard to end the turn.
      final hand = [
        _c(CardRank.two, CardSuit.spades),
        _c(CardRank.five, CardSuit.hearts),
        _c(CardRank.nine, CardSuit.clubs),
        _c(CardRank.king, CardSuit.diamonds),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.discardSuggestion), isTrue);
      expect(
        insights.first.category,
        CoachingInsightCategory.discardSuggestion,
      );
      final insight = _find(
        insights,
        CoachingInsightCategory.discardSuggestion,
      );
      expect(insight.discardCardId, isNotNull);
      expect(hand.map((c) => c.id), contains(insight.discardCardId));
    });

    test('keeps a pair that could become a set rather than breaking it', () {
      // The reported playtest bug: a Q-Q pair (a third Queen makes a 30 set)
      // must NOT be the suggested discard when lone low deadwood is present.
      // Reusing the Expert brain's discard ranking keeps the pair.
      final queenHearts = _c(CardRank.queen, CardSuit.hearts);
      final queenClubs = _c(CardRank.queen, CardSuit.clubs);
      final hand = [
        queenHearts,
        queenClubs,
        _c(CardRank.two, CardSuit.spades),
        _c(CardRank.five, CardSuit.diamonds, deckIndex: 5),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      final insight = _find(
        insights,
        CoachingInsightCategory.discardSuggestion,
      );
      expect(insight.discardCardId, isNot(queenHearts.id));
      expect(insight.discardCardId, isNot(queenClubs.id));
    });
  });

  group('drawStock', () {
    test('is the floor hint when nothing better applies in the draw phase', () {
      // Opened seat, draw phase, disconnected hand, and a top discard that
      // helps nothing: no finish / meld / pickup / cover / joker / defensive,
      // so the coach falls back to "draw a card".
      final hand = [
        _c(CardRank.two, CardSuit.spades),
        _c(CardRank.five, CardSuit.diamonds),
        _c(CardRank.nine, CardSuit.hearts),
        _c(CardRank.king, CardSuit.clubs),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        discardPile: [_c(CardRank.four, CardSuit.hearts)],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(_has(insights, CoachingInsightCategory.drawStock), isTrue);
      expect(insights.first.category, CoachingInsightCategory.drawStock);
    });

    test('unopened draw phase surfaces draw and folds in opening progress', () {
      // Playtest issue A: an unopened seat in the draw phase that cannot pick up
      // or open should be told to DRAW (the actionable move), with the opening
      // shortfall folded into the draw insight rather than lost behind it.
      final hand = [
        _c(CardRank.two, CardSuit.clubs),
        _c(CardRank.three, CardSuit.clubs),
        _c(CardRank.four, CardSuit.clubs),
        _c(CardRank.nine, CardSuit.spades),
        _c(CardRank.king, CardSuit.hearts),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        discardPile: [_c(CardRank.seven, CardSuit.hearts)],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        openingState: const OpeningState(
          baseRequirement: 51,
          currentRequirement: 51,
          openedSeats: {},
        ),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(insights.first.category, CoachingInsightCategory.drawStock);
      final draw = _find(insights, CoachingInsightCategory.drawStock);
      expect(draw.openingRequirement, 51);
      expect(draw.openingBestValue, isNotNull);
      expect(draw.openingBestValue, lessThan(51));
      expect(draw.openingShortfall, 51 - draw.openingBestValue!);
      // Regression: the draw hint must still ring the in-hand cards that make
      // up the best meld-in-progress (the 2-3-4 club run), not just the stock.
      expect(draw.highlightCardIds, isNotEmpty);
    });

    test('is outranked whenever a real insight applies', () {
      // Same draw phase, but the top discard now completes a meld: pickup
      // (600) must outrank the draw floor (100).
      final hand = [
        _c(CardRank.eight, CardSuit.diamonds),
        _c(CardRank.nine, CardSuit.diamonds),
        _c(CardRank.two, CardSuit.spades),
        _c(CardRank.king, CardSuit.clubs),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        discardPile: [_c(CardRank.ten, CardSuit.diamonds)],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(
        insights.first.category,
        CoachingInsightCategory.pickupCompletesMeld,
      );
    });
  });

  group('recompute after a real draw (controller↔advisor regression)', () {
    test('drawing the card that completes a set keeps the set, never sheds it', () {
      // Playtest issue B: South (unopened, draw phase) holds 8♦ 8♥ + deadwood.
      // The stock's top card is the 8♣ that completes the 8-set. After actually
      // DRAWING it through the controller, the advisor must treat the freshly
      // completed set as a KEEPER and never tell the seat to throw one of the
      // 8s. The set is only worth 24 against a 72 requirement, so an unopened
      // seat is guided by opening progress (which rings the set as the cards to
      // hold) rather than a discard floor. This drives the draw through the live
      // controller so it guards the engine side of the stale-discard bug
      // regardless of the UI's caching.
      final eightDiamonds = _c(CardRank.eight, CardSuit.diamonds);
      final eightHearts = _c(CardRank.eight, CardSuit.hearts);
      final eightClubs = _c(CardRank.eight, CardSuit.clubs);
      final twoSpades = _c(CardRank.two, CardSuit.spades);
      final fiveHearts = _c(CardRank.five, CardSuit.hearts);
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: [eightDiamonds, eightHearts, twoSpades, fiveHearts],
        // drawStock removes the LAST stock card, so 8♣ sits on top. Leading
        // filler keeps the stock non-empty after the draw.
        stock: [
          _c(CardRank.three, CardSuit.spades, deckIndex: 7),
          _c(CardRank.four, CardSuit.diamonds, deckIndex: 7),
          eightClubs,
        ],
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        openingState: const OpeningState(
          baseRequirement: 72,
          currentRequirement: 72,
          openedSeats: {},
        ),
      );

      final drawResult = scenario.south.drawStock();
      expect(drawResult.isSuccess, isTrue);
      // Sanity: the 8♣ is now in hand and we are owing a discard.
      expect(scenario.south.hand.map((c) => c.id), contains(eightClubs.id));

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      // The surfaced hint is opening guidance that rings the completed 8-set as
      // the cards to keep — proving the advisor recomputed on the post-draw hand.
      final opening = _find(insights, CoachingInsightCategory.openingProgress);
      expect(
        opening.highlightCardIds,
        containsAll([eightDiamonds.id, eightHearts.id, eightClubs.id]),
      );
      // No insight may tell the seat to discard one of the 8s.
      for (final insight in insights) {
        expect(
          insight.discardCardId,
          isNot(anyOf(eightDiamonds.id, eightHearts.id, eightClubs.id)),
        );
      }
      // An unopened seat gets opening guidance, not a discard floor.
      expect(
        _has(insights, CoachingInsightCategory.discardSuggestion),
        isFalse,
      );
    });
  });

  group('priority ordering', () {
    test('insights are sorted highest priority first', () {
      final hand = [
        _c(CardRank.eight, CardSuit.diamonds),
        _c(CardRank.nine, CardSuit.diamonds),
        _c(CardRank.ten, CardSuit.diamonds),
        _c(CardRank.five, CardSuit.clubs),
        _c(CardRank.six, CardSuit.clubs),
        _c(CardRank.seven, CardSuit.clubs),
        _c(CardRank.two, CardSuit.spades),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      for (var i = 1; i < insights.length; i += 1) {
        expect(
          insights[i - 1].priority,
          greaterThanOrEqualTo(insights[i].priority),
        );
      }
    });

    test('the category priority ladder is strictly descending', () {
      // CoachingInsightCategory declares its values in descending priority order
      // — the single source of truth the advisor sorts by. Many playtest fixes
      // were "category X must outrank category Y" (drawStock over openingProgress,
      // takeAndFinish over pickupCompletesMeld, stage banners over the floors),
      // so pin that the ladder never silently inverts or collides.
      final categories = CoachingInsightCategory.values;
      for (var i = 1; i < categories.length; i += 1) {
        expect(
          categories[i - 1].priority,
          greaterThan(categories[i].priority),
          reason:
              '${categories[i - 1].name} must outrank ${categories[i].name}',
        );
      }
    });

    test('returns an empty list when it is not the seat turn', () {
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        currentSeat: PlayerSeat.east,
        turnPhase: TurnPhase.action,
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      // Off-turn: no legal-surface insights, and South is unopened in a fresh
      // deal so an openingProgress teaching insight may still appear. Assert
      // that no turn-gated categories leak.
      expect(_has(insights, CoachingInsightCategory.playMeld), isFalse);
      expect(
        _has(insights, CoachingInsightCategory.pickupCompletesMeld),
        isFalse,
      );
    });
  });
}
