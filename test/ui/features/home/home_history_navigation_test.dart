import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';
import 'package:hareeg_table/ui/core/theme/lounge_tokens.dart';
import 'package:hareeg_table/ui/features/history/views/match_history_screen.dart';
import 'package:hareeg_table/ui/features/history/views/match_statistics_screen.dart';

import '../../../support/test_fixtures.dart';

const _viewports = <String, Size>{
  'narrow portrait': Size(320, 568),
  'short landscape': Size(740, 360),
};

Future<void> pumpApp(
  WidgetTester tester, {
  AppStrings strings = AppStrings.english,
  Size size = const Size(400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    HareegTableApp(
      matchRepository: MemoryMatchRepository(),
      historyRepository: MemoryMatchHistoryRepository(),
      preferencesRepository: MemoryPreferencesRepository()
        ..preferences = GamePreferences.defaults().copyWith(
          language: strings.languageCode == 'ar'
              ? AppLanguage.arabic
              : AppLanguage.english,
        ),
      initialRouteOverride: AppRoutes.home,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  ShowcaseCardFan.disableLoopingMotionForTesting = true;

  group('home entry points', () {
    testWidgets('both new controls appear without displacing the old ones', (
      tester,
    ) async {
      await pumpApp(tester);
      final strings = AppStrings.english;

      expect(find.text(strings.historyMenuLabel), findsOneWidget);
      expect(find.text(strings.statisticsMenuLabel), findsOneWidget);

      // Everything the menu offered before must still be here.
      expect(find.text(strings.newGame), findsOneWidget);
      expect(find.text(strings.continueGame), findsOneWidget);
      expect(find.text(strings.practiceTitle), findsOneWidget);
      expect(find.byTooltip(strings.settings), findsOneWidget);
      expect(find.byTooltip(strings.rulesHelp), findsOneWidget);
    });

    testWidgets('History opens the history screen', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text(AppStrings.english.historyMenuLabel));
      await tester.pumpAndSettle();

      expect(find.byType(MatchHistoryScreen), findsOneWidget);
    });

    testWidgets('Statistics opens the statistics screen', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text(AppStrings.english.statisticsMenuLabel));
      await tester.pumpAndSettle();

      expect(find.byType(MatchStatisticsScreen), findsOneWidget);
    });
  });

  group('cross-links are stack-safe', () {
    testWidgets('toggling twice still returns home with one Back', (
      tester,
    ) async {
      await pumpApp(tester);
      final strings = AppStrings.english;

      await tester.tap(find.text(strings.historyMenuLabel));
      await tester.pumpAndSettle();
      expect(find.byType(MatchHistoryScreen), findsOneWidget);

      // History -> Statistics -> History -> Statistics, using the in-screen
      // cross-links rather than going back to the menu each time.
      for (var toggle = 0; toggle < 2; toggle++) {
        await tester.tap(find.byTooltip(strings.statisticsMenuLabel));
        await tester.pumpAndSettle();
        expect(find.byType(MatchStatisticsScreen), findsOneWidget);

        await tester.tap(find.byTooltip(strings.historyMenuLabel));
        await tester.pumpAndSettle();
        expect(find.byType(MatchHistoryScreen), findsOneWidget);
      }

      await tester.tap(find.byTooltip(strings.statisticsMenuLabel));
      await tester.pumpAndSettle();

      // A single Back, after five cross-link taps. Pushing rather than
      // replacing would make the player unwind their own toggling.
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(MatchStatisticsScreen), findsNothing);
      expect(find.byType(MatchHistoryScreen), findsNothing);
      expect(find.text(strings.newGame), findsOneWidget);
    });

    testWidgets('Back from history returns straight home', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text(AppStrings.english.historyMenuLabel));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.english.newGame), findsOneWidget);
    });
  });

  group('home layout gate', () {
    for (final entry in _viewports.entries) {
      for (final strings in [AppStrings.english, AppStrings.arabic]) {
        testWidgets('${entry.key}, ${strings.languageCode}', (tester) async {
          await pumpApp(tester, strings: strings, size: entry.value);

          expect(tester.takeException(), isNull);

          for (final label in [
            strings.historyMenuLabel,
            strings.statisticsMenuLabel,
          ]) {
            final labelFinder = find.text(label);
            expect(labelFinder, findsOneWidget, reason: 'Missing "$label".');

            // `find.text` matches `Text.data` and is untouched by the
            // renderer's ellipsis, so it would pass on a button showing
            // "Histo...". Measure the label under the style, direction, and
            // scaler actually in effect, against the width it was given.
            _expectRendersInFull(tester, labelFinder, label);

            // Secondary controls sit one tier below the 48-pixel primary
            // target but must stay comfortably tappable.
            final button = find.ancestor(
              of: labelFinder,
              matching: find.byType(OutlinedButton),
            );
            expect(button, findsOneWidget);
            expect(
              tester.getSize(button).height,
              greaterThanOrEqualTo(LoungeTokens.tapTargetCardShort),
              reason: '"$label" is below the minimum tap target.',
            );
          }

          // The new row displaces nothing.
          for (final existing in [
            strings.newGame,
            strings.continueGame,
            strings.practiceTitle,
          ]) {
            expect(find.text(existing), findsOneWidget);
          }
          expect(find.byTooltip(strings.settings), findsOneWidget);
          expect(find.byTooltip(strings.rulesHelp), findsOneWidget);
        });
      }
    }
  });
}

/// Fails when [label] is visually truncated at its rendered width.
void _expectRendersInFull(
  WidgetTester tester,
  Finder labelFinder,
  String label,
) {
  final element = tester.element(labelFinder);
  final paragraph = tester.renderObject<RenderParagraph>(labelFinder);
  final available = paragraph.constraints.maxWidth;

  final painter = TextPainter(
    text: TextSpan(text: label, style: paragraph.text.style),
    textDirection: paragraph.textDirection,
    textScaler: MediaQuery.textScalerOf(element),
    maxLines: paragraph.maxLines,
  )..layout(maxWidth: available);

  expect(
    painter.didExceedMaxLines,
    isFalse,
    reason: '"$label" needs more lines than it is allowed at this size.',
  );
  expect(
    painter.width,
    lessThanOrEqualTo(available + 0.5),
    reason:
        '"$label" lays out at ${painter.width.toStringAsFixed(1)} but only '
        '${available.toStringAsFixed(1)} is available, so it renders clipped.',
  );
  painter.dispose();
}
