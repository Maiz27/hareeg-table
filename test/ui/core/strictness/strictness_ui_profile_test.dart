import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/table_strictness.dart';
import 'package:hareeg_table/ui/core/cards/card_theme.dart';
import 'package:hareeg_table/ui/core/strictness/strictness_ui_profile.dart';

void main() {
  group('StrictnessUiProfile', () {
    group('showsProactiveHints', () {
      test('is true only for coaching', () {
        expect(TableStrictness.coaching.showsProactiveHints, isTrue);
        expect(TableStrictness.standard.showsProactiveHints, isFalse);
        expect(TableStrictness.strict.showsProactiveHints, isFalse);
        expect(TableStrictness.table.showsProactiveHints, isFalse);
      });
    });

    group('showsMeldPicker', () {
      test('is true only for coaching', () {
        expect(TableStrictness.coaching.showsMeldPicker, isTrue);
        expect(TableStrictness.standard.showsMeldPicker, isFalse);
        expect(TableStrictness.strict.showsMeldPicker, isFalse);
        expect(TableStrictness.table.showsMeldPicker, isFalse);
      });
    });

    group('showsCardValueInInspect', () {
      test('is true for every tier', () {
        for (final tier in TableStrictness.values) {
          expect(tier.showsCardValueInInspect, isTrue, reason: 'tier=$tier');
        }
      });
    });

    group('inspectVerbosity', () {
      test('is coaching for the coaching tier', () {
        expect(
          TableStrictness.coaching.inspectVerbosity,
          InspectVerbosity.coaching,
        );
      });

      test('is terse for every other tier', () {
        expect(
          TableStrictness.standard.inspectVerbosity,
          InspectVerbosity.terse,
        );
        expect(
          TableStrictness.strict.inspectVerbosity,
          InspectVerbosity.terse,
        );
        expect(TableStrictness.table.inspectVerbosity, InspectVerbosity.terse);
      });
    });

    group('jokerDisplay', () {
      test('is assisted for coaching and standard', () {
        expect(TableStrictness.coaching.jokerDisplay, JokerDisplay.assisted);
        expect(TableStrictness.standard.jokerDisplay, JokerDisplay.assisted);
      });

      test('is memoryReveal for strict and table', () {
        expect(
          TableStrictness.strict.jokerDisplay,
          JokerDisplay.memoryReveal,
        );
        expect(TableStrictness.table.jokerDisplay, JokerDisplay.memoryReveal);
      });
    });

    group('jokerCueDuration', () {
      test('is null (persistent) for coaching and standard', () {
        expect(TableStrictness.coaching.jokerCueDuration, isNull);
        expect(TableStrictness.standard.jokerCueDuration, isNull);
      });

      test('is 3 seconds for strict and table', () {
        const expected = Duration(seconds: 3);
        expect(TableStrictness.strict.jokerCueDuration, expected);
        expect(TableStrictness.table.jokerCueDuration, expected);
      });
    });

    group('longPressRevealsRepresented', () {
      test('is true for coaching and standard', () {
        expect(TableStrictness.coaching.longPressRevealsRepresented, isTrue);
        expect(TableStrictness.standard.longPressRevealsRepresented, isTrue);
      });

      test('is false for strict and table', () {
        expect(TableStrictness.strict.longPressRevealsRepresented, isFalse);
        expect(TableStrictness.table.longPressRevealsRepresented, isFalse);
      });
    });
  });
}
