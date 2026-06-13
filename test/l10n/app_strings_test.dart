import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/l10n/app_strings.dart';

void main() {
  group('AppStrings strictness copy', () {
    test('English rules help uses current strictness names', () {
      final strings = AppStrings.english;

      expect(strings.helpFiftyBody, contains('Coaching and Standard'));
      expect(strings.helpFiftyBody, contains('Strict'));
      expect(strings.helpFiftyBody, contains('Table'));
      expect(strings.helpFiftyBody, isNot(contains('Assisted')));
      expect(strings.helpMistakePresetsTitle, 'Mistake handling');
      expect(strings.helpMistakePresetsBody, contains('Coaching and Standard'));
      expect(strings.helpMistakePresetsBody, contains('Strict'));
      expect(strings.helpMistakePresetsBody, contains('Table'));
      expect(strings.helpMistakePresetsBody, isNot(contains('preset')));
    });

    test('Arabic rules help does not fall back to legacy English terms', () {
      final strings = AppStrings.arabic;

      expect(strings.helpFiftyBody, isNot(contains('Assisted')));
      expect(strings.helpMistakePresetsTitle, isNot('Mistake presets'));
      expect(strings.helpMistakePresetsBody, isNot(contains('Hard table')));
    });

    test('Arabic fast CPU turn settings are localized', () {
      final strings = AppStrings.arabic;

      expect(strings.fastCpuTurns, isNot('Fast CPU turns'));
      expect(strings.fastCpuTurnsDescription, isNot(contains('CPU')));
      expect(strings.fastCpuTurnsDescription, contains('الكمبيوتر'));
    });

    test('strictness feedback messages are localized in Arabic', () {
      final strings = AppStrings.arabic;

      expect(
        strings.gameMessage('This strictness blocks that illegal action.'),
        'مستوى الصرامة هذا يمنع هذه الحركة غير القانونية.',
      );
      expect(
        strings.gameMessage('Strict penalty: +3.'),
        'عقوبة الوضع الصارم: +3.',
      );
      expect(
        strings.gameMessage('Table mistake: +17 and out of this round.'),
        'خطأ وضع الطاولة: +17 وخروج من هذه الجولة.',
      );
    });
  });
}
