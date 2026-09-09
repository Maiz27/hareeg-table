import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/analysis_coach_settings.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/core/cards/card_theme_registry.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/opponent_seat_rails.dart';
import 'package:hareeg_table/ui/features/history/widgets/match_history_entry_card.dart';
import 'package:hareeg_table/ui/features/replay/review_insight_presenter.dart';
import 'package:hareeg_table/ui/features/replay/widgets/analysis_coach_panel.dart';
import 'package:hareeg_table/ui/features/replay/widgets/branch_entry_sheet.dart';

import '../../../support/test_fixtures.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child,
  AppStrings strings,
) async {
  await tester.pumpWidget(
    AppStringsScope(
      strings: strings,
      child: MaterialApp(
        builder: (context, child) =>
            Directionality(textDirection: strings.textDirection, child: child!),
        home: Scaffold(
          body: Center(child: SizedBox(width: 500, child: child)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<SemanticsNode> _nodes(WidgetTester tester) {
  // ignore: deprecated_member_use
  final root = tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    if (!node.isMergedIntoParent) nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return nodes;
}

String _label(SemanticsNode node) =>
    node.getSemanticsData().label.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  for (final strings in [AppStrings.english, AppStrings.arabic]) {
    testWidgets(
      'Replay has one named actionable node ${strings.languageCode}',
      (tester) async {
        var tapped = 0;
        await _pump(
          tester,
          MatchHistoryEntryCard(
            summary: historySummary(matchId: 'm-a11y-aaaaaaaa'),
            onDelete: () {},
            onReplay: () => tapped++,
          ),
          strings,
        );
        final nodes = _nodes(tester)
            .where(
              (node) =>
                  node.getSemanticsData().flagsCollection.isButton &&
                  _label(node).contains(strings.replayTitle),
            )
            .toList();
        expect(
          nodes,
          hasLength(1),
          reason: 'No duplicate parent or repeated label',
        );
        expect(_label(nodes.single), strings.replayTitle);
        expect(
          nodes.single.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        await tester.tap(find.text(strings.replayTitle));
        expect(tapped, 1);
      },
    );

    testWidgets(
      'branch choices have one named action ${strings.languageCode}',
      (tester) async {
        await _pump(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showBranchEntrySheet(context),
              child: const Text('open'),
            ),
          ),
          strings,
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        for (final (title, note) in [
          (strings.branchEntryBlind, strings.branchEntryBlindNote),
          (strings.branchEntryStudy, strings.branchEntryStudyNote),
        ]) {
          final nodes = _nodes(
            tester,
          ).where((node) => _label(node).contains('$title. $note')).toList();
          expect(nodes, hasLength(1));
          expect(_label(nodes.single), '$title. $note');
          expect(
            nodes.single.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
        }
      },
    );

    testWidgets(
      'coach toggle has one name and dropdown names its purpose ${strings.languageCode}',
      (tester) async {
        var settings = AnalysisCoachSettings.defaults();
        await _pump(
          tester,
          StatefulBuilder(
            builder: (context, setState) => AnalysisCoachPanel(
              insights: const [],
              presenter: ReviewInsightPresenter(
                strings: strings,
                cards: const {},
              ),
              settings: settings,
              isOverridden: false,
              reviewable: true,
              onSettingsChanged: (value) => setState(() => settings = value),
            ),
          ),
          strings,
        );
        final nodes = _nodes(tester)
            .where(
              (node) =>
                  node.getSemanticsData().flagsCollection.isToggled !=
                  ui.Tristate.none,
            )
            .toList();
        expect(nodes, hasLength(1));
        expect(_label(nodes.single), strings.replayCardDeathWarnings);
        expect(
          nodes.single.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        final before = settings.cardDeathWarnings;
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(settings.cardDeathWarnings, !before);
        // Invoke the published switch action, not just its pointer handler.
        // ignore: deprecated_member_use
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          nodes.single.id,
          SemanticsAction.tap,
        );
        await tester.pumpAndSettle();
        expect(settings.cardDeathWarnings, before);
        final expected = strings.languageCode == 'ar'
            ? 'مستوى تفصيل الشرح'
            : 'Explanation detail';
        final dropdown = _nodes(
          tester,
        ).where((node) => _label(node).contains(expected)).toList();
        expect(dropdown, hasLength(1));
        expect(
          dropdown.single.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(
          _label(dropdown.single),
          contains(verbosityLabel(strings, settings.verbosity)),
        );
        // ignore: deprecated_member_use
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          dropdown.single.id,
          SemanticsAction.tap,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .text(verbosityLabel(strings, AnalysisVerbosity.clearMistakes))
              .last,
        );
        await tester.pumpAndSettle();
        expect(settings.verbosity, AnalysisVerbosity.clearMistakes);
      },
    );

    testWidgets(
      'study expansion supports Tab Enter Space and tap ${strings.languageCode}',
      (tester) async {
        var expanded = 0;
        final label = strings.languageCode == 'ar'
            ? 'عرض يد الشمال'
            : 'Show North hand';
        await _pump(
          tester,
          OpponentHandRail(
            theme: CardThemeRegistry.byId(null),
            count: 1,
            cardSize: const Size(32, 44),
            active: false,
            thinking: false,
            eliminated: false,
            compact: true,
            onExpand: () => expanded++,
            expandLabel: label,
          ),
          strings,
        );
        final beforeRect = tester.getRect(find.byType(OpponentHandRail));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(expanded, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(expanded, 2);
        final nodes = _nodes(
          tester,
        ).where((node) => _label(node) == label).toList();
        expect(nodes, hasLength(1));
        expect(
          nodes.single.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(tester.getRect(find.byType(OpponentHandRail)), beforeRect);
        await tester.tap(find.bySemanticsLabel(label));
        await tester.pumpAndSettle();
        expect(expanded, 3);
      },
    );
  }

  testWidgets('hidden hand stays inert to keyboard', (tester) async {
    await _pump(
      tester,
      OpponentHandRail(
        theme: CardThemeRegistry.byId(null),
        count: 1,
        cardSize: const Size(32, 44),
        active: false,
        thinking: false,
        eliminated: false,
        compact: true,
      ),
      AppStrings.english,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(
      _nodes(
        tester,
      ).where((node) => node.getSemanticsData().hasAction(SemanticsAction.tap)),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}
