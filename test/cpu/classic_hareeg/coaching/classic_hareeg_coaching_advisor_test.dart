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

  group('coverKeep', () {
    test('hand card extends one of the seat own table melds', () {
      final tableRun = [
        _c(CardRank.eight, CardSuit.diamonds),
        _c(CardRank.nine, CardSuit.diamonds),
        _c(CardRank.ten, CardSuit.diamonds),
      ];
      final coverCard = _c(CardRank.jack, CardSuit.diamonds);
      final hand = [
        coverCard,
        _c(CardRank.two, CardSuit.spades),
        _c(CardRank.five, CardSuit.hearts),
        _c(CardRank.king, CardSuit.clubs),
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

      expect(_has(insights, CoachingInsightCategory.coverKeep), isTrue);
      final insight = _find(insights, CoachingInsightCategory.coverKeep);
      expect(insight.coverCardId, coverCard.id);
      expect(insight.coverMeldOwner, PlayerSeat.south);
      expect(insight.coverMeldIndex, 0);
    });

    test('absent when no hand card covers an own meld', () {
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

      expect(_has(insights, CoachingInsightCategory.coverKeep), isFalse);
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
