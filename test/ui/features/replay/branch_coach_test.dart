import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/analysis_coach_settings.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_replay_record.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/game_table/table_session_config.dart';
import 'package:hareeg_table/ui/features/replay/views/match_replay_screen.dart';

import '../../../support/branch_sandbox_harness.dart';
import '../../../support/completed_match_fixture.dart';
import '../../../support/test_fixtures.dart';

/// The sandbox coach is inherited, session-only, and reset by a restart.
///
/// Every case here turns on one fact: `coachWasEnabled`, read off the archived
/// summary. Nothing else may raise eligibility, and nothing the player does in
/// a sandbox may reach a stored preference.
late MatchActionTranscript _transcript;

class _StaticHistoryRepository extends MemoryMatchHistoryRepository {
  _StaticHistoryRepository(this._value);

  final MatchActionTranscript _value;

  @override
  Future<MatchReplayOpenOutcome> openReplay(String matchId) async {
    return MatchReplayOpened(
      MatchReplayRecord(matchId: matchId, transcript: _value),
    );
  }
}

void main() {
  setUpAll(() {
    final state = buildCompletedMatch(seed: 13).recorderState;
    _transcript = MatchActionTranscript(
      initialSnapshot: state.initialSnapshot!,
      entries: state.entries,
    );
  });

  Finder toggle() => find.byKey(const ValueKey('branch-coach-toggle'));

  Future<void> openPause(WidgetTester tester) async {
    await tester.tap(find.byTooltip(AppStrings.english.pauseTable));
    await tester.pumpAndSettle();
  }

  Future<void> pumpSandbox(
    WidgetTester tester, {
    required bool coachEligible,
  }) async {
    await pumpBranchSandbox(
      tester,
      branchSandboxApp(
        frame: branchFrame(branchSnapshot()),
        visibility: BranchVisibility.blind,
        coachEligible: coachEligible,
      ),
    );
  }

  group('eligibility comes from the archived match and nowhere else', () {
    testWidgets('an ineligible sandbox has no toggle to switch on', (
      tester,
    ) async {
      await pumpSandbox(tester, coachEligible: false);
      await openPause(tester);

      // Absent, not present-and-off. A player whose archived match had no
      // coaching cannot reach one from a branch of it, and the way that is
      // guaranteed is that the control does not exist.
      expect(toggle(), findsNothing);
      expect(find.text(AppStrings.english.branchCoachToggle), findsNothing);
    });

    testWidgets('an eligible sandbox starts with the coach on', (tester) async {
      await pumpSandbox(tester, coachEligible: true);
      await openPause(tester);

      expect(toggle(), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(toggle()).value,
        isTrue,
        reason: 'the sandbox inherits the archived coach state',
      );
    });

    testWidgets('the toggle is session-only and reaches no preference', (
      tester,
    ) async {
      await pumpSandbox(tester, coachEligible: true);
      await openPause(tester);

      await tester.tap(toggle());
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(toggle()).value,
        isFalse,
        reason: 'the toggle actually moves',
      );

      // Structural, and the reason the behavioural check above is enough: the
      // sandbox surface builds no `onPreferencesChanged` control at all. The
      // live pause panel — every row of which writes a preference — is simply
      // not the panel a sandbox shows.
      expect(find.text(AppStrings.english.motionSpeedLabel), findsNothing);
      expect(find.text(AppStrings.english.soundLabel), findsNothing);
      expect(find.text(AppStrings.english.highContrastCards), findsNothing);
      expect(find.text(AppStrings.english.reportTableIssue), findsNothing);
    });

    testWidgets('restart restores the archived state, not the toggled one', (
      tester,
    ) async {
      await pumpSandbox(tester, coachEligible: true);
      await openPause(tester);
      await tester.tap(toggle());
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle()).value, isFalse);

      await tester.tap(find.text(AppStrings.english.branchRestart));
      await tester.pumpAndSettle(const Duration(seconds: 30));

      await openPause(tester);
      expect(
        tester.widget<SwitchListTile>(toggle()).value,
        isTrue,
        reason:
            'a restart returns to the branch point, which includes the coach '
            'state the archived match had',
      );
    });
  });

  group('the handoff runs from the archived summary to the rendered surface', () {
    for (final eligible in [true, false]) {
      testWidgets(
        'coachWasEnabled=$eligible reaches the sandbox through the real '
        'replay path',
        (tester) async {
          // The thin end-to-end case. Everything above enters the sandbox
          // directly, which cannot show that the summary's flag is the value
          // that arrives; this drives the launch the app actually uses.
          tester.view.physicalSize = const Size(1688, 780);
          tester.view.devicePixelRatio = 2.0;
          addTearDown(tester.view.reset);

          final summary = historySummary(
            matchId: 'm-coach-bbbbbbbb',
            coachWasEnabled: eligible,
          );

          await tester.pumpWidget(
            AppStringsScope(
              strings: AppStrings.english,
              child: const Directionality(
                textDirection: TextDirection.ltr,
                child: SizedBox.shrink(),
              ),
            ),
          );
          await tester.pumpWidget(
            AppStringsScope(
              strings: AppStrings.english,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: MaterialApp(
                  home: MatchReplayScreen(
                    summary: summary,
                    historyRepository: _StaticHistoryRepository(_transcript),
                    analysisCoach: AnalysisCoachSettings.defaults(),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle(const Duration(seconds: 60));

          await tester.tap(
            find.byKey(const ValueKey('replay-branch-control')),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const ValueKey('branch-entry-blind')));
          await tester.pumpAndSettle(const Duration(seconds: 60));

          await tester.tap(find.byTooltip(AppStrings.english.pauseTable));
          await tester.pumpAndSettle();

          expect(
            toggle(),
            eligible ? findsOneWidget : findsNothing,
            reason:
                'the summary flag is what decides, all the way to the rendered '
                'surface',
          );
          if (eligible) {
            expect(tester.widget<SwitchListTile>(toggle()).value, isTrue);
          }
        },
      );
    }
  });
}
