import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';
import 'package:hareeg_table/ui/core/motion/motion_speed.dart';

void main() {
  group('ShowcaseCardFan motion seam', () {
    testWidgets('rest pose is unchanged when motion is none', (tester) async {
      await _pump(tester, motion: ShowcaseFanMotion.none);
      final fanFinder = find.byType(ShowcaseCardFan);
      expect(fanFinder, findsOneWidget);
      // All slot Opacity wrappers are absent at rest (opacity == 1.0 short
      // circuit in _FannedCardSlot.build), so probing for them confirms the
      // rest pose path is hit.
      expect(
        find.descendant(of: fanFinder, matching: find.byType(Opacity)),
        findsNothing,
      );
    });

    testWidgets('reduced motion collapses any choreography to rest', (
      tester,
    ) async {
      await _pump(
        tester,
        motion: ShowcaseFanMotion.intro,
        speed: MotionSpeed.reduced,
      );
      // Pump enough to let any controller start would have produced opacity
      // wrappers; rest pose has none.
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        find.descendant(
          of: find.byType(ShowcaseCardFan),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
    });

    testWidgets('intro starts off-rest and resolves to rest pose', (
      tester,
    ) async {
      await _pump(tester, motion: ShowcaseFanMotion.intro);
      // First frame: at least one slot is mid-tween with opacity < 1.
      await tester.pump();
      final introOpacities = tester
          .widgetList<Opacity>(
            find.descendant(
              of: find.byType(ShowcaseCardFan),
              matching: find.byType(Opacity),
            ),
          )
          .map((o) => o.opacity)
          .toList();
      expect(
        introOpacities,
        isNotEmpty,
        reason: 'intro should add opacity wrappers while tweening',
      );
      expect(introOpacities.any((o) => o < 0.99), isTrue);

      // Let the controller finish.
      await tester.pump(const Duration(seconds: 2));
      final settledOpacities = tester
          .widgetList<Opacity>(
            find.descendant(
              of: find.byType(ShowcaseCardFan),
              matching: find.byType(Opacity),
            ),
          )
          .toList();
      expect(
        settledOpacities,
        isEmpty,
        reason: 'after intro settles, slots collapse back to the rest path',
      );
    });

    testWidgets('idle motion keeps the controller running', (tester) async {
      await _pump(tester, motion: ShowcaseFanMotion.idle);
      await tester.pump(const Duration(milliseconds: 100));
      // The idle loop never settles, so subsequent frames keep rebuilding.
      expect(tester.hasRunningAnimations, isTrue);
    });
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required ShowcaseFanMotion motion,
  MotionSpeed speed = MotionSpeed.normal,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MotionScope(
        settings: MotionSettings(speed: speed, osReducedMotion: false),
        child: AppStringsScope(
          strings: AppStrings.forLanguageCode('en'),
          child: Scaffold(
            body: Center(
              child: ShowcaseCardFan(width: 232, height: 134, motion: motion),
            ),
          ),
        ),
      ),
    ),
  );
}
