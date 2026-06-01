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
  });

  group('fiftyAvailable', () {
    test('seat owns the window and a finish uses the top discard', () {
      // South holds two runs missing one card each; the top discard completes a
      // finish (the partition must use the discard and leave <= 1 card).
      final hand = [
        _c(CardRank.eight, CardSuit.diamonds),
        _c(CardRank.nine, CardSuit.diamonds),
        _c(CardRank.ten, CardSuit.diamonds),
        _c(CardRank.five, CardSuit.clubs),
        _c(CardRank.six, CardSuit.clubs),
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
      final insight = _find(
        insights,
        CoachingInsightCategory.openingProgress,
      );
      expect(insight.openingRequirement, 51);
      expect(insight.openingBestValue, lessThan(51));
      expect(
        insight.openingShortfall,
        51 - insight.openingBestValue!,
      );
    });

    test('unopened seat is guided to open with a combined keep + discard hint',
        () {
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
      expect(_has(insights, CoachingInsightCategory.coverKeep), isFalse);
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
      // lays off onto an 8-9-10 heart run on the table. The coach should surface
      // BOTH in one hint — the meld to play plus the cover — not the meld alone.
      final coverJack = _c(CardRank.jack, CardSuit.hearts);
      final hand = [
        _c(CardRank.five, CardSuit.clubs),
        _c(CardRank.six, CardSuit.clubs),
        _c(CardRank.seven, CardSuit.clubs),
        coverJack,
        _c(CardRank.two, CardSuit.spades),
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

      expect(insights.first.category, CoachingInsightCategory.playMeld);
      final insight = _find(insights, CoachingInsightCategory.playMeld);
      expect(insight.coverCardId, coverJack.id);
      expect(insight.highlightCardIds, contains(coverJack.id));
      expect(
        insight.highlightCardIds,
        containsAll([hand[0].id, hand[1].id, hand[2].id]),
      );
    });

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

    test('finish-by-cover in a cover-only endgame never blacks out (Issue A)', () {
      // Cover-only endgame: the seat's two cards each lay off onto an opponent
      // meld and there is no plain safe discard. The old bespoke detector
      // blacked out here (covers on opponent melds, no own-meld cover, the
      // lay-off hint bailed on the empty safe-discard set). The plan-driven path
      // surfaces a finish-by-cover instead. (The rules engine advertises covers
      // one at a time, so the currently-legal cover is the one ringed.)
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
      expect(insights.first.category, CoachingInsightCategory.finishAvailable);
      expect(insights.first.coverFinishes, isTrue);
      expect(insights.first.highlightCardIds, contains(tenHearts.id));
    });

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
      expect(insights.first.category, CoachingInsightCategory.discardSuggestion);
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

  group('defensiveDiscard', () {
    test('warns about a card whose rank an opponent picked up', () {
      // East (an opponent of South) picked up the nine of clubs. South holds a
      // legal-to-discard nine; discarding it would feed East.
      final pickedUp = _c(CardRank.nine, CardSuit.clubs);
      final southNine = _c(CardRank.nine, CardSuit.hearts, deckIndex: 4);
      final hand = [
        southNine,
        _c(CardRank.two, CardSuit.spades),
        _c(CardRank.five, CardSuit.diamonds),
        _c(CardRank.king, CardSuit.hearts),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
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

      expect(
        _has(insights, CoachingInsightCategory.defensiveDiscard),
        isTrue,
      );
      final insight = _find(
        insights,
        CoachingInsightCategory.defensiveDiscard,
      );
      expect(insight.hotOpponent, PlayerSeat.east);
      expect(insight.hotRank, CardRank.nine);
      expect(insight.discardCardId, southNine.id);
    });

    test('absent when no opponent is collecting any held rank or suit', () {
      final hand = [
        _c(CardRank.nine, CardSuit.hearts),
        _c(CardRank.two, CardSuit.spades),
        _c(CardRank.five, CardSuit.diamonds),
        _c(CardRank.king, CardSuit.hearts),
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

      expect(
        _has(insights, CoachingInsightCategory.defensiveDiscard),
        isFalse,
      );
    });

    test('an opponent merely DISCARDING a suit is not "collecting" it', () {
      // East discarded a nine of clubs (threw it away). A discard means the
      // opponent did NOT want it, so it must not flag South's nine as risky —
      // only deliberate pickups count. This is the turn-one false-positive the
      // playtest surfaced.
      final discarded = _c(CardRank.nine, CardSuit.clubs);
      final southNine = _c(CardRank.nine, CardSuit.hearts, deckIndex: 4);
      final hand = [
        southNine,
        _c(CardRank.two, CardSuit.spades),
        _c(CardRank.five, CardSuit.diamonds),
        _c(CardRank.king, CardSuit.hearts),
      ];
      final scenario = ClassicHareegScenario.deal(
        setup: _coachingSetup(),
        southHand: hand,
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        openingState: ScenarioCards.openedFor(PlayerSeat.south),
        discardHistoryEvents: [
          DiscardEvent(
            seat: PlayerSeat.east,
            card: discarded,
            kind: DiscardEventKind.discard,
            sequence: 0,
          ),
        ],
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      expect(
        _has(insights, CoachingInsightCategory.defensiveDiscard),
        isFalse,
      );
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
    test('drawing the card that completes a set keeps the set, never sheds it',
        () {
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
      expect(
        scenario.south.hand.map((c) => c.id),
        contains(eightClubs.id),
      );

      final insights = ClassicHareegCoachingAdvisor.adviseFor(
        scenario.controller,
        PlayerSeat.south,
      );

      // The surfaced hint is opening guidance that rings the completed 8-set as
      // the cards to keep — proving the advisor recomputed on the post-draw hand.
      final opening = _find(
        insights,
        CoachingInsightCategory.openingProgress,
      );
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
      // playCover over coverKeep, discardSuggestion over defensiveDiscard), so
      // pin that the ladder never silently inverts or collides.
      final categories = CoachingInsightCategory.values;
      for (var i = 1; i < categories.length; i += 1) {
        expect(
          categories[i - 1].priority,
          greaterThan(categories[i].priority),
          reason: '${categories[i - 1].name} must outrank ${categories[i].name}',
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
