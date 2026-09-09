// D12: the coach callout must not overflow at a docked sandbox width.
//
// Found by driving a real browser, not by a widget test: the docked 390x844
// branch sandbox raised
//
//   EXCEPTION CAUGHT BY RENDERING LIBRARY
//   A RenderFlex overflowed by 37 pixels on the right.
//   creator: Row <- Column <- Expanded <- Row <- Padding <- DecoratedBox
//          <- Semantics <- _CoachCallout <- ...
//   constraints: BoxConstraints(0.0<=w<=6.7, 0.0<=h<=Infinity)
//
// The arithmetic behind it: the web build lays the table out in a canvas of
// fixed height 430 and scales it to fill the viewport, so a 390x844 viewport
// is only ~199 logical pixels across. Side insets of a fixed 54 left the
// callout's text column 6.7 pixels.
//
// These tests pin the width that failed, in both locales, and pin that the
// wide table's spacing is unchanged -- a fix that quietly re-spaced the
// desktop table would pass an overflow check and still be wrong.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/coaching_insight.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/game_table/coach/coach_hint.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/coach_overlay.dart';

/// The failing state: the `finishAvailable` hint, which is the one the docked
/// sandbox was showing when the exception was raised.
CoachHint _finishHint(AppStrings strings) {
  final hint = CoachHintPresenter.present(
    insight: const CoachingInsight(
      category: CoachingInsightCategory.finishAvailable,
      priority: 1000,
      highlightCardIds: ['deck-200-six-clubs', 'deck-201-seven-clubs'],
    ),
    strings: strings,
    identityForCardId: (_) => null,
    topDiscardIdentity: null,
  );
  return hint!;
}

Future<void> _pumpAt(
  WidgetTester tester,
  Size size, {
  required AppStrings strings,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(strings.isRtl ? 'ar' : 'en'),
      home: Directionality(
        textDirection: strings.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: Stack(
          children: [
            const SizedBox.expand(),
            CoachOverlay(hint: _finishHint(strings), highContrast: false),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // The exact canvas the web build produces for a 390x844 viewport: the table
  // is laid out at a fixed design height of 430 and scaled to fill, so the
  // width is 390 * 430 / 844.
  const dockedDesign = Size(198.7, 430);

  group('CoachOverlay does not overflow', () {
    testWidgets('at the docked sandbox width, English', (tester) async {
      await _pumpAt(tester, dockedDesign, strings: AppStrings.english);
      expect(tester.takeException(), isNull);
    });

    testWidgets('at the docked sandbox width, Arabic', (tester) async {
      await _pumpAt(tester, dockedDesign, strings: AppStrings.arabic);
      expect(tester.takeException(), isNull);
    });

    testWidgets('at a narrower width still', (tester) async {
      // Deliberately past anything the product ships, so the fix is a rule
      // rather than a value tuned to one number.
      await _pumpAt(tester, const Size(150, 430), strings: AppStrings.english);
      expect(tester.takeException(), isNull);
    });

    testWidgets('and still renders the hint it was given', (tester) async {
      // A callout that overflowed less because it stopped drawing would pass
      // every check above.
      await _pumpAt(tester, dockedDesign, strings: AppStrings.english);
      expect(tester.takeException(), isNull);
      expect(find.byType(CoachOverlay), findsOneWidget);
      expect(
        find.textContaining(AppStrings.english.coachLabel.toUpperCase()),
        findsOneWidget,
      );
    });
  });

  group('CoachOverlay spacing on the sizes that already worked', () {
    testWidgets('a wide table keeps its fixed inset', (tester) async {
      // 0.14 of 930 is 130, well past the 66 the wide table uses, so the
      // fraction must not be what applies here.
      await _pumpAt(tester, const Size(930, 430), strings: AppStrings.english);
      expect(tester.takeException(), isNull);
      final overlay = tester.widget<Padding>(
        find.byKey(const ValueKey('coach-overlay-insets')),
      );
      final inset = overlay.padding.resolve(TextDirection.ltr);
      expect(inset.left, 66);
      expect(inset.right, 66);
    });

    testWidgets('the docked width uses the fraction instead', (tester) async {
      await _pumpAt(tester, dockedDesign, strings: AppStrings.english);
      final overlay = tester.widget<Padding>(
        find.byKey(const ValueKey('coach-overlay-insets')),
      );
      final inset = overlay.padding.resolve(TextDirection.ltr);
      expect(inset.left, lessThan(54));
      expect(inset.left, greaterThan(0));
    });
  });
}
