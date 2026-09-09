import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
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

  group('history and statistics copy', () {
    test('CPU difficulty labels are localized, not the enum constant', () {
      // `CpuDifficulty.label` is an English-only constant on the model.
      for (final difficulty in CpuDifficulty.values) {
        expect(
          AppStrings.english.cpuDifficultyLabel(difficulty),
          isNotEmpty,
        );
        expect(
          AppStrings.arabic.cpuDifficultyLabel(difficulty),
          isNot(difficulty.label),
          reason: 'Arabic must not fall through to the English enum label.',
        );
      }
    });

    test('starter mode labels are localized', () {
      for (final mode in StarterMode.values) {
        expect(AppStrings.english.starterModeLabel(mode), isNotEmpty);
        expect(AppStrings.arabic.starterModeLabel(mode), isNot(mode.label));
      }
    });

    test('every new history and statistics string is really translated', () {
      // The catalog falls back to English on a missing key, so an untranslated
      // string ships looking fine. Comparing the two catalogs is what catches
      // a key that was copied rather than translated.
      final english = AppStrings.english;
      final arabic = AppStrings.arabic;

      final pairs = <String, (String, String)>{
        'historyTitle': (english.historyTitle, arabic.historyTitle),
        'historyMenuLabel': (
          english.historyMenuLabel,
          arabic.historyMenuLabel,
        ),
        'historyEmptyTitle': (
          english.historyEmptyTitle,
          arabic.historyEmptyTitle,
        ),
        'historyEmptyBody': (
          english.historyEmptyBody,
          arabic.historyEmptyBody,
        ),
        'historyLoadFailedRetryableTitle': (
          english.historyLoadFailedRetryableTitle,
          arabic.historyLoadFailedRetryableTitle,
        ),
        'historyLoadFailedCorruptTitle': (
          english.historyLoadFailedCorruptTitle,
          arabic.historyLoadFailedCorruptTitle,
        ),
        'historyLoadFailedCorruptBody': (
          english.historyLoadFailedCorruptBody,
          arabic.historyLoadFailedCorruptBody,
        ),
        'historyRetry': (english.historyRetry, arabic.historyRetry),
        'historyDelete': (english.historyDelete, arabic.historyDelete),
        'historyCancel': (english.historyCancel, arabic.historyCancel),
        'historyDeleteConfirmTitle': (
          english.historyDeleteConfirmTitle,
          arabic.historyDeleteConfirmTitle,
        ),
        'historyDeleteFailedCorrupt': (
          english.historyDeleteFailedCorrupt,
          arabic.historyDeleteFailedCorrupt,
        ),
        'historyReplayUnavailable': (
          english.historyReplayUnavailable,
          arabic.historyReplayUnavailable,
        ),
        'historyReplayAvailable': (
          english.historyReplayAvailable,
          arabic.historyReplayAvailable,
        ),
        'historyCoachOn': (english.historyCoachOn, arabic.historyCoachOn),
        'historyCoachOff': (english.historyCoachOff, arabic.historyCoachOff),
        'statisticsTitle': (english.statisticsTitle, arabic.statisticsTitle),
        'statisticsMenuLabel': (
          english.statisticsMenuLabel,
          arabic.statisticsMenuLabel,
        ),
        'statisticsEmptyTitle': (
          english.statisticsEmptyTitle,
          arabic.statisticsEmptyTitle,
        ),
        'statsOverallHeading': (
          english.statsOverallHeading,
          arabic.statsOverallHeading,
        ),
        'statsByCoachHeading': (
          english.statsByCoachHeading,
          arabic.statsByCoachHeading,
        ),
        'statsGamesPlayed': (
          english.statsGamesPlayed,
          arabic.statsGamesPlayed,
        ),
        'statsWinRate': (english.statsWinRate, arabic.statsWinRate),
        'statsFiftySuccessRate': (
          english.statsFiftySuccessRate,
          arabic.statsFiftySuccessRate,
        ),
        'statsAverageMargin': (
          english.statsAverageMargin,
          arabic.statsAverageMargin,
        ),
        'statsMarginDirection': (
          english.statsMarginDirection,
          arabic.statsMarginDirection,
        ),
      };

      for (final entry in pairs.entries) {
        final (en, ar) = entry.value;
        expect(ar, isNotEmpty, reason: '${entry.key} has no Arabic value.');
        expect(
          ar,
          isNot(en),
          reason: '${entry.key} still reads as its English value in Arabic.',
        );
      }
    });

    test('parameterized history copy is localized in both languages', () {
      expect(AppStrings.english.statsLowDataNote(2), contains('2'));
      expect(AppStrings.arabic.statsLowDataNote(2), contains('2'));
      expect(
        AppStrings.arabic.statsLowDataNote(2),
        isNot(AppStrings.english.statsLowDataNote(2)),
      );

      expect(AppStrings.english.statsFiftyMeasuredNote(2, 5), contains('2'));
      expect(AppStrings.english.statsFiftyMeasuredNote(2, 5), contains('5'));
      expect(
        AppStrings.arabic.statsFiftyMeasuredNote(2, 5),
        isNot(AppStrings.english.statsFiftyMeasuredNote(2, 5)),
      );
    });
  });
}
