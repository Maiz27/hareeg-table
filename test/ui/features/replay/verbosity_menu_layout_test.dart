import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/analysis_coach_settings.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_replay_record.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/replay/views/match_replay_screen.dart';
import 'package:hareeg_table/ui/features/replay/widgets/analysis_coach_panel.dart';
import '../../../support/max_content_table_fixture.dart';
import '../../../support/test_fixtures.dart';

class _History extends MemoryMatchHistoryRepository {
  @override
  Future<MatchReplayOpenOutcome> openReplay(String matchId) async =>
      MatchReplayOpened(
        MatchReplayRecord(
          matchId: matchId,
          transcript: MatchActionTranscript(
            initialSnapshot: maximumContentSnapshot(),
            entries: const [],
          ),
        ),
      );
}

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(914, 411),
    const Size(926, 428),
  ]) {
    for (final strings in [AppStrings.english, AppStrings.arabic]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'replay menu labels fit $size ${strings.languageCode} scale $scale',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(
              MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: AppStringsScope(
                    strings: strings,
                    child: Directionality(
                      textDirection: strings.textDirection,
                      child: child!,
                    ),
                  ),
                ),
                home: MatchReplayScreen(
                  summary: historySummary(matchId: 'm-probe-aaaaaaaa'),
                  historyRepository: _History(),
                  analysisCoach: AnalysisCoachSettings.defaults(),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: 'initial screen');
            if (size.width > size.height) {
              await tester.tap(find.byTooltip(strings.replayCoachTitle));
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull, reason: 'expanded panel');
            final dropdown = find.byType(PopupMenuButton<AnalysisVerbosity>);
            expect(dropdown, findsOneWidget);
            final bounds = tester.getRect(dropdown);
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(size.width));
            expect(bounds.height, kMinInteractiveDimension);
            for (final value in AnalysisVerbosity.values) {
              await tester.ensureVisible(dropdown);
              await tester.tap(dropdown);
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: 'open menu for $value',
              );
              final item = find.text(verbosityLabel(strings, value)).last;
              await tester.ensureVisible(item);
              final paragraph = tester.renderObject<RenderParagraph>(item);
              expect(tester.widget<Text>(item).maxLines, isNull);
              final painter = TextPainter(
                text: paragraph.text,
                textDirection: paragraph.textDirection,
                textScaler: paragraph.textScaler,
                locale: paragraph.locale,
              )..layout();
              if (scale == 1.0) {
                expect(
                  paragraph.size.width,
                  greaterThanOrEqualTo(painter.width - 0.5),
                );
              }
              painter.layout(maxWidth: paragraph.size.width);
              expect(
                paragraph.size.height,
                greaterThanOrEqualTo(painter.height - 0.5),
                reason: 'Every wrapped line must fit in the rendered label',
              );
              painter.dispose();
              expect(
                paragraph.didExceedMaxLines,
                isFalse,
                reason: 'Full open-menu label must be readable: $value',
              );
              final itemRect = tester.getRect(item);
              expect(itemRect.left, greaterThanOrEqualTo(0));
              expect(itemRect.right, lessThanOrEqualTo(size.width));
              expect(itemRect.top, greaterThanOrEqualTo(0));
              expect(itemRect.bottom, lessThanOrEqualTo(size.height));
              await tester.tap(item, warnIfMissed: true);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: 'choose $value');
              expect(
                tester
                    .widget<PopupMenuButton<AnalysisVerbosity>>(dropdown)
                    .initialValue,
                value,
              );
            }
            expect(
              tester.getSize(dropdown),
              bounds.size,
              reason: 'Closed control size is unchanged after selection',
            );
            // Pointer selection need not give the anchor keyboard focus.
            // Reach it through traversal before testing keyboard activation.
            final anchorFocus = Focus.of(
              tester.element(
                find.descendant(of: dropdown, matching: find.byType(Row)).first,
              ),
            );
            for (var step = 0; step < 30 && !anchorFocus.hasFocus; step++) {
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
              await tester.pumpAndSettle();
            }
            expect(anchorFocus.hasFocus, isTrue);
            // Dismissing without selection must preserve the chosen setting.
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(
              find.byType(PopupMenuItem<AnalysisVerbosity>),
              findsNWidgets(3),
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(find.byType(PopupMenuItem<AnalysisVerbosity>), findsNothing);
            expect(
              tester
                  .widget<PopupMenuButton<AnalysisVerbosity>>(dropdown)
                  .initialValue,
              AnalysisVerbosity.values.last,
            );
          },
        );
      }
    }
  }
}
