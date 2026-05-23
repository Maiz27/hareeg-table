import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_discard_eligibility.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/mistake_preset_rules.dart';

void main() {
  group('ClassicHareegDiscardEligibilityPlanner', () {
    test('normal cards advertise plain discard actions', () {
      final discard = card(CardRank.nine, CardSuit.hearts);

      final result = ClassicHareegDiscardEligibilityPlanner.evaluate(
        preset: RulePreset.assisted,
        tableMelds: const [],
        card: discard,
        isFinalDiscard: false,
        blocksJokerReplacement: false,
      );

      expect(result.scenario, ClassicHareegDiscardScenario.normal);
      expect(result.isAllowed, isTrue);
      expect(result.shouldAdvertise, isTrue);
      expect(
        result.actionId,
        '${ClassicHareegActionIds.discardPrefix}${discard.id}',
      );
      expect(result.appliesMistake, isFalse);
    });

    test('normal joker discards stay hard-blocked and hidden', () {
      const joker = HareegCard.joker(deckIndex: 10, jokerIndex: 0);

      for (final preset in RulePreset.values) {
        final result = ClassicHareegDiscardEligibilityPlanner.evaluate(
          preset: preset,
          tableMelds: const [],
          card: joker,
          isFinalDiscard: false,
          blocksJokerReplacement: false,
        );

        expect(result.scenario, ClassicHareegDiscardScenario.normalJoker);
        expect(result.isAllowed, isFalse);
        expect(result.shouldAdvertise, isFalse);
        expect(
          result.actionId,
          '${ClassicHareegActionIds.discardJokerPrefix}${joker.id}',
        );
        expect(result.mistakeType, MistakeType.normalJokerDiscard);
      }
    });

    test('assisted cover discards are blocked and hidden', () {
      final cover = card(CardRank.eight, CardSuit.clubs, 2);

      final result = ClassicHareegDiscardEligibilityPlanner.evaluate(
        preset: RulePreset.assisted,
        tableMelds: [
          [
            card(CardRank.five, CardSuit.clubs, 2),
            card(CardRank.six, CardSuit.clubs, 2),
            card(CardRank.seven, CardSuit.clubs, 2),
          ],
        ],
        card: cover,
        isFinalDiscard: false,
        blocksJokerReplacement: false,
      );

      expect(result.scenario, ClassicHareegDiscardScenario.cover);
      expect(result.isAllowed, isFalse);
      expect(result.shouldAdvertise, isFalse);
      expect(
        result.actionId,
        '${ClassicHareegActionIds.discardBlockedCoverPrefix}${cover.id}',
      );
      expect(result.message, contains('cover'));
    });

    test('table penalties allow joker-replacement discards as mistakes', () {
      final replacement = card(CardRank.queen, CardSuit.diamonds, 3);

      final result = ClassicHareegDiscardEligibilityPlanner.evaluate(
        preset: RulePreset.tablePenalties,
        tableMelds: const [],
        card: replacement,
        isFinalDiscard: false,
        blocksJokerReplacement: true,
      );

      expect(result.scenario, ClassicHareegDiscardScenario.jokerReplacement);
      expect(result.isAllowed, isTrue);
      expect(result.shouldAdvertise, isTrue);
      expect(
        result.actionId,
        '${ClassicHareegActionIds.discardBlockedCoverPrefix}${replacement.id}',
      );
      expect(result.mistakeType, MistakeType.illegalCoverDiscard);
      expect(result.appliesMistake, isTrue);
      expect(result.mistakeResolution?.penaltyPoints, 3);
      expect(result.mistakeResolution?.removeFromRound, isFalse);
    });

    test(
      'hard table identifies cards that are both covers and replacements',
      () {
        final blocked = card(CardRank.eight, CardSuit.clubs, 4);

        final result = ClassicHareegDiscardEligibilityPlanner.evaluate(
          preset: RulePreset.hardTable17,
          tableMelds: [
            [
              card(CardRank.five, CardSuit.clubs, 4),
              card(CardRank.six, CardSuit.clubs, 4),
              card(CardRank.seven, CardSuit.clubs, 4),
            ],
          ],
          card: blocked,
          isFinalDiscard: false,
          blocksJokerReplacement: true,
        );

        expect(
          result.scenario,
          ClassicHareegDiscardScenario.coverAndJokerReplacement,
        );
        expect(result.isAllowed, isTrue);
        expect(result.shouldAdvertise, isTrue);
        expect(result.appliesMistake, isTrue);
        expect(result.mistakeResolution?.penaltyPoints, 17);
        expect(result.mistakeResolution?.removeFromRound, isTrue);
      },
    );

    test(
      'final discards bypass joker, cover, and replacement restrictions',
      () {
        final cover = card(CardRank.eight, CardSuit.clubs, 5);
        const joker = HareegCard.joker(deckIndex: 5, jokerIndex: 0);

        final coverResult = ClassicHareegDiscardEligibilityPlanner.evaluate(
          preset: RulePreset.assisted,
          tableMelds: [
            [
              card(CardRank.five, CardSuit.clubs, 5),
              card(CardRank.six, CardSuit.clubs, 5),
              card(CardRank.seven, CardSuit.clubs, 5),
            ],
          ],
          card: cover,
          isFinalDiscard: true,
          blocksJokerReplacement: true,
        );
        final jokerResult = ClassicHareegDiscardEligibilityPlanner.evaluate(
          preset: RulePreset.assisted,
          tableMelds: const [],
          card: joker,
          isFinalDiscard: true,
          blocksJokerReplacement: false,
        );

        for (final result in [coverResult, jokerResult]) {
          expect(result.scenario, ClassicHareegDiscardScenario.finalDiscard);
          expect(result.isAllowed, isTrue);
          expect(result.shouldAdvertise, isTrue);
          expect(result.actionPrefix, ClassicHareegActionIds.discardPrefix);
          expect(result.appliesMistake, isFalse);
        }
      },
    );
  });
}

HareegCard card(CardRank rank, CardSuit suit, [int deckIndex = 1]) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
