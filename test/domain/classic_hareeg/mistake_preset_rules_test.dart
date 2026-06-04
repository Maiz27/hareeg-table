import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/table_strictness.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/mistake_preset_rules.dart';

void main() {
  group('ClassicHareegMistakePresetRules', () {
    test('blocking tiers refuse selected illegal actions', () {
      for (final tier in [TableStrictness.coaching, TableStrictness.standard]) {
        final cover = ClassicHareegMistakePresetRules.resolve(
          strictness: tier,
          mistake: MistakeType.illegalCoverDiscard,
        );
        final jokerReplacement = ClassicHareegMistakePresetRules.resolve(
          strictness: tier,
          mistake: MistakeType.wrongJokerReplacement,
        );

        expect(cover.isAllowed, isFalse, reason: 'tier=$tier');
        expect(jokerReplacement.isAllowed, isFalse, reason: 'tier=$tier');
      }
    });

    test('strict tier allows selected mistakes with +3', () {
      final result = ClassicHareegMistakePresetRules.resolve(
        strictness: TableStrictness.strict,
        mistake: MistakeType.wrongFiftyClaim,
      );

      expect(result.isAllowed, isTrue);
      expect(result.penaltyPoints, 3);
      expect(result.removeFromRound, isFalse);
    });

    test('table tier applies +17 and removes player from round', () {
      final result = ClassicHareegMistakePresetRules.resolve(
        strictness: TableStrictness.table,
        mistake: MistakeType.insufficientOpening,
      );

      expect(result.isAllowed, isTrue);
      expect(result.penaltyPoints, 17);
      expect(result.removeFromRound, isTrue);
      expect(result.keepExistingMelds, isTrue);
    });

    test('normal joker discard remains hard-blocked in every tier', () {
      for (final tier in TableStrictness.values) {
        final result = ClassicHareegMistakePresetRules.resolve(
          strictness: tier,
          mistake: MistakeType.normalJokerDiscard,
        );

        expect(result.isAllowed, isFalse, reason: 'tier=$tier');
        expect(result.penaltyPoints, 0, reason: 'tier=$tier');
      }
    });

    test('CPU mistakes are tied to strictness, not difficulty', () {
      expect(
        ClassicHareegMistakePresetRules.cpuMistakesAllowed(
          TableStrictness.coaching,
        ),
        isFalse,
      );
      expect(
        ClassicHareegMistakePresetRules.cpuMistakesAllowed(
          TableStrictness.standard,
        ),
        isFalse,
      );
      // Strict reverts the action so a CPU "mistake" would just waste a turn;
      // only Table tier accepts CPU mistakes (full +17 + round removal).
      expect(
        ClassicHareegMistakePresetRules.cpuMistakesAllowed(
          TableStrictness.strict,
        ),
        isFalse,
      );
      expect(
        ClassicHareegMistakePresetRules.cpuMistakesAllowed(
          TableStrictness.table,
        ),
        isTrue,
      );
    });

    test('player-facing messages use current strictness names', () {
      const blockingMessage = 'This strictness blocks that illegal action.';

      expect(
        ClassicHareegMistakePresetRules.resolve(
          strictness: TableStrictness.coaching,
          mistake: MistakeType.illegalCoverDiscard,
        ).message,
        blockingMessage,
      );
      expect(
        ClassicHareegMistakePresetRules.resolve(
          strictness: TableStrictness.standard,
          mistake: MistakeType.illegalCoverDiscard,
        ).message,
        blockingMessage,
      );
      expect(
        ClassicHareegMistakePresetRules.resolve(
          strictness: TableStrictness.strict,
          mistake: MistakeType.wrongFiftyClaim,
        ).message,
        'Strict penalty: +3.',
      );
      expect(
        ClassicHareegMistakePresetRules.resolve(
          strictness: TableStrictness.table,
          mistake: MistakeType.wrongJokerReplacement,
        ).message,
        'Table mistake: +17 and out of this round.',
      );
    });
  });
}
