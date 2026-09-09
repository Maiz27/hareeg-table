import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/analysis_coach_settings.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_replay_record.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/replay/replay_hud_layout.dart';
import 'package:hareeg_table/ui/features/replay/views/match_replay_screen.dart';
import 'package:hareeg_table/ui/features/replay/widgets/review_table_playfield.dart';

import '../../../support/max_content_table_fixture.dart';
import '../../../support/test_fixtures.dart';

const _matchId = 'm-screen-aaaaaaaa';
const _slow = Timeout(Duration(minutes: 5));

const _shortSizes = <Size>[Size(844, 390), Size(914, 411), Size(926, 428)];
const _dockedSizes = <Size>[Size(320, 568), Size(390, 844)];

late MatchActionTranscript _transcript;

class _StaticHistoryRepository extends MemoryMatchHistoryRepository {
  _StaticHistoryRepository(this._value);

  final MatchActionTranscript _value;

  @override
  Future<MatchReplayOpenOutcome> openReplay(String matchId) async {
    return MatchReplayOpened(
      MatchReplayRecord(matchId: _matchId, transcript: _value),
    );
  }
}

Finder _byTypeName(String name) => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == name,
);

Future<void> _pump(
  WidgetTester tester,
  Size size, [
  AppStrings strings = AppStrings.english,
]) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();

  await tester.pumpWidget(
    MaterialApp(
      home: AppStringsScope(
        strings: strings,
        child: Directionality(
          textDirection: strings.textDirection,
          child: MatchReplayScreen(
            summary: historySummary(matchId: _matchId),
            historyRepository: _StaticHistoryRepository(_transcript),
            analysisCoach: const AnalysisCoachSettings(
              verbosity: AnalysisVerbosity.narrateAll,
              cardDeathWarnings: true,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

void main() {
  setUpAll(() {
    _transcript = MatchActionTranscript(
      initialSnapshot: maximumContentSnapshot(),
      entries: const [],
    );
  });

  group('the short layout gives the whole body to the table', () {
    for (final size in _shortSizes) {
      testWidgets('$size is full-bleed with no app bar', timeout: _slow, (
        tester,
      ) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pump(tester, size);

        // A7: the app bar is what made the naive breakpoint circular, and in
        // the short layout Back lives in the rail instead.
        expect(find.byType(AppBar), findsNothing, reason: 'app bar at $size');

        final table = tester.getRect(find.byType(ReviewTablePlayfield));
        // A9: nothing permanently subtracts height from the table. The rails
        // are overlays in the same stack, so this is the whole body, not 85%
        // of it — but 85% is the contracted floor, so that is what is asserted
        // as the requirement and the rest is headroom.
        expect(table.height, greaterThanOrEqualTo(size.height * 0.85));
        expect(table.width, size.width);

        // A10: above the playfield's compact thresholds, so regular card sizes
        // render. Asserted through the projection the HUD routes on, which the
        // parity suite ties to the rendered tree.
        expect(table.height, greaterThan(360));
        expect(
          ReplayTableGeometry.project(table.size).compact,
          isFalse,
          reason: 'compact cards at $size',
        );
      });
    }
  });

  group('the permanent inventory is nine affordances plus one scrub', () {
    for (final size in _shortSizes) {
      for (final strings in [AppStrings.english, AppStrings.arabic]) {
        testWidgets(
          '$size in ${strings.languageCode}',
          timeout: _slow,
          (tester) async {
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await _pump(tester, size, strings);

            // A13: every one is visible. None is behind a long-press, a menu,
            // or a disclosure.
            expect(_byTypeName('ReplayRailButton'), findsNWidgets(9));
            expect(_byTypeName('ReplayScrubTarget'), findsOneWidget);

            // The withdrawn surfaces must actually be gone, not merely unused.
            expect(_byTypeName('ReplayLeadingCluster'), findsNothing);
            expect(_byTypeName('ReplayTrailingCluster'), findsNothing);
            expect(_byTypeName('_AnalysisChip'), findsNothing);
            expect(_byTypeName('ReplayScrubBar'), findsNothing);

            // A42: measured, not assumed, and at the rendered rect rather than
            // at the constraint that produced it.
            for (final name in const [
              'ReplayRailButton',
              'ReplayScrubTarget',
            ]) {
              for (final element in _byTypeName(name).evaluate()) {
                final box = element.renderObject! as RenderBox;
                expect(box.size.width, greaterThanOrEqualTo(44));
                expect(box.size.height, greaterThanOrEqualTo(44));
              }
            }
          },
        );
      }
    }
  });

  group('the six navigation actions all reach the timeline', () {
    testWidgets('each transport control is present and labelled', timeout:
        _slow, (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(tester, const Size(844, 390));

      final strings = AppStrings.english;
      for (final tooltip in [
        strings.replayBack,
        strings.replayFirst,
        strings.replayCoachTitle,
        strings.replayPreviousRound,
        strings.replayPrevious,
        strings.replayNext,
        strings.replayNextRound,
        strings.replayLast,
      ]) {
        expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
      }
    });
  });

  group('the docked branch is unchanged where it applies', () {
    for (final size in _dockedSizes) {
      testWidgets('$size renders the docked bands', timeout: _slow, (
        tester,
      ) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pump(tester, size);

        expect(find.byType(AppBar), findsOneWidget, reason: 'at $size');
        expect(_byTypeName('ReplayRailButton'), findsNothing);
        expect(_byTypeName('ReplayScrubTarget'), findsNothing);
        expect(_byTypeName('ReplayReviewControls'), findsOneWidget);
      });
    }
  });

  group('replay never renders the live meld chip', () {
    for (final size in [..._shortSizes, ..._dockedSizes]) {
      testWidgets('no SouthSideControls at $size', timeout: _slow, (
        tester,
      ) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pump(tester, size);
        expect(_byTypeName('SouthSideControls'), findsNothing);
      });
    }
  });
}
