import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/core/cards/card_theme_registry.dart';
import 'package:hareeg_table/ui/core/theme/lounge_tokens.dart';
import 'package:hareeg_table/ui/features/settings/models/settings_section.dart';
import 'package:hareeg_table/ui/features/settings/views/settings_screen.dart';

/// Layout regressions from the 1.0.0-alpha.12 release build, reproduced on a
/// phone-sized surface with a larger text scale and the real UI font (the
/// test font's square glyphs would wrap every label and prove nothing).
void main() {
  setUpAll(() async {
    final loader = FontLoader(LoungeTokens.uiFamily);
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(
        File(
          'assets/fonts/IBMPlexSansArabic-$weight.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
  });

  /// Opens the settings on [section] and scrolls until [anchor], a widget
  /// inside that section's body, is built: the list is lazy, so a section
  /// below the first screen does not exist until it is scrolled to.
  Future<void> pumpSettings(
    WidgetTester tester, {
    required SettingsSection section,
    required Finder anchor,
  }) async {
    // A 1080×2340 phone at its native density, with "Large" text.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        // A fresh screen per section: the same State would otherwise be
        // reused and keep the section it first opened.
        key: UniqueKey(),
        home: SettingsScreen(
          preferences: GamePreferences.defaults(),
          onUpdate: (_) {},
          cardThemes: CardThemeRegistry.all(),
          isMatchActive: false,
          initialSection: section,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(anchor, 160);
    await tester.pumpAndSettle();
  }

  /// The floating label of an outlined field straddles the field's top border,
  /// so half of it sits above the field. The section body is clipped for its
  /// expand animation; the label must start inside that clip or it is cut.
  void expectLabelInsideSectionClip(WidgetTester tester, String label) {
    final labelFinder = find.descendant(
      of: find.byType(InputDecorator),
      matching: find.text(label),
    );
    expect(labelFinder, findsOneWidget);
    final clipFinder = find
        .ancestor(of: labelFinder, matching: find.byType(ClipRect))
        .first;
    final labelRect = tester.getRect(labelFinder);
    final clipRect = tester.getRect(clipFinder);
    expect(
      labelRect.top,
      greaterThanOrEqualTo(clipRect.top),
      reason: '"$label" is clipped at the top of its section',
    );
  }

  /// A segment label may wrap between words, never inside one.
  void expectNoMidWordBreak(WidgetTester tester, String label) {
    final finder = find.text(label);
    expect(finder, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    var start = 0;
    for (final word in label.split(' ')) {
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + word.length),
      );
      final lineTops = boxes.map((box) => box.top.round()).toSet();
      expect(
        lineTops,
        hasLength(1),
        reason: '"$word" in "$label" is broken across lines',
      );
      start += word.length + 1;
    }
  }

  testWidgets('dropdown labels are not clipped by the section body', (
    tester,
  ) async {
    final strings = AppStrings.english;

    await pumpSettings(
      tester,
      section: SettingsSection.language,
      anchor: find.byType(InputDecorator),
    );
    expectLabelInsideSectionClip(tester, strings.language);

    await pumpSettings(
      tester,
      section: SettingsSection.tableRules,
      anchor: find.text(strings.deckCount),
    );
    expectLabelInsideSectionClip(tester, strings.deckCount);
    expectLabelInsideSectionClip(tester, strings.fiftyTimer);
  });

  testWidgets('segmented picker labels never break inside a word', (
    tester,
  ) async {
    final strings = AppStrings.english;

    await pumpSettings(
      tester,
      section: SettingsSection.review,
      anchor: find.text(strings.replayVerbosityKeyMoments),
    );
    expectNoMidWordBreak(tester, strings.replayVerbosityNarrateAll);
    expectNoMidWordBreak(tester, strings.replayVerbosityKeyMoments);
    expectNoMidWordBreak(tester, strings.replayVerbosityClearMistakes);

    await pumpSettings(
      tester,
      section: SettingsSection.feel,
      anchor: find.text(strings.normal),
    );
    expectNoMidWordBreak(tester, strings.normal);
    expectNoMidWordBreak(tester, strings.fast);
    expectNoMidWordBreak(tester, strings.reduced);
  });
}
