import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/mistake_preset_rules.dart';

void main() {
  group('ClassicHareegMistakePresetRules', () {
    test('assisted preset blocks selected illegal actions', () {
      final cover = ClassicHareegMistakePresetRules.resolve(
        preset: RulePreset.assisted,
        mistake: MistakeType.illegalCoverDiscard,
      );
      final jokerReplacement = ClassicHareegMistakePresetRules.resolve(
        preset: RulePreset.assisted,
        mistake: MistakeType.wrongJokerReplacement,
      );

      expect(cover.isAllowed, isFalse);
      expect(jokerReplacement.isAllowed, isFalse);
    });

    test('penalty preset allows selected mistakes with +3', () {
      final result = ClassicHareegMistakePresetRules.resolve(
        preset: RulePreset.tablePenalties,
        mistake: MistakeType.wrongFiftyClaim,
      );

      expect(result.isAllowed, isTrue);
      expect(result.penaltyPoints, 3);
      expect(result.removeFromRound, isFalse);
    });

    test('hard table preset applies +17 and removes player from round', () {
      final result = ClassicHareegMistakePresetRules.resolve(
        preset: RulePreset.hardTable17,
        mistake: MistakeType.insufficientOpening,
      );

      expect(result.isAllowed, isTrue);
      expect(result.penaltyPoints, 17);
      expect(result.removeFromRound, isTrue);
      expect(result.keepExistingMelds, isTrue);
    });

    test('normal joker discard remains hard-blocked in every preset', () {
      for (final preset in RulePreset.values) {
        final result = ClassicHareegMistakePresetRules.resolve(
          preset: preset,
          mistake: MistakeType.normalJokerDiscard,
        );

        expect(result.isAllowed, isFalse);
        expect(result.penaltyPoints, 0);
      }
    });

    test('CPU mistakes are tied to preset and easier difficulties', () {
      expect(
        ClassicHareegMistakePresetRules.cpuMistakesAllowed(
          preset: RulePreset.assisted,
          difficulty: CpuDifficulty.beginner,
        ),
        isFalse,
      );
      expect(
        ClassicHareegMistakePresetRules.cpuMistakesAllowed(
          preset: RulePreset.tablePenalties,
          difficulty: CpuDifficulty.beginner,
        ),
        isTrue,
      );
      expect(
        ClassicHareegMistakePresetRules.cpuMistakesAllowed(
          preset: RulePreset.tablePenalties,
          difficulty: CpuDifficulty.expert,
        ),
        isFalse,
      );
    });
  });
}
