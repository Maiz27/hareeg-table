import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_replay_record.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/replay_branch_seed.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/ui/core/panels/lounge_panel.dart';
import 'package:hareeg_table/ui/features/game_table/table_mode.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/physical_table_playfield.dart';
import 'package:hareeg_table/ui/features/replay/views/branch_sandbox_host.dart';
import 'package:hareeg_table/ui/features/replay/views/match_replay_screen.dart';
import 'package:hareeg_table/ui/features/replay/widgets/analysis_coach_panel.dart';

import '../../../support/branch_sandbox_harness.dart';
import '../../../support/completed_match_fixture.dart';
import '../../../support/test_fixtures.dart';

/// Entering a sandbox: the chooser, the refusal, and what each one produces.
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

  Future<void> pumpReplay(
    WidgetTester tester, {
    AppStrings strings = AppStrings.english,
    Size size = const Size(1688, 780),
    bool highContrast = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppStringsScope(
        strings: strings,
        child: Directionality(
          textDirection: strings.textDirection,
          child: MaterialApp(
            home: MatchReplayScreen(
              summary: historySummary(
                matchId: 'm-entry-aaaaaaaa',
                coachWasEnabled: true,
              ),
              historyRepository: _StaticHistoryRepository(_transcript),
              analysisCoach: AnalysisCoachSettings.defaults(),
              preferences: GamePreferences.defaults().copyWith(
                highContrastCards: highContrast,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 60));
  }

  Finder branchControl() => find.byKey(const ValueKey('replay-branch-control'));

  group('the chooser', () {
    for (final contrast in [false, true]) {
      testWidgets('inherits replay high contrast $contrast', (tester) async {
        await pumpReplay(tester, highContrast: contrast);
        await tester.tap(branchControl());
        await tester.pumpAndSettle();
        expect(
          tester.widget<LoungePanel>(find.byType(LoungePanel)).highContrast,
          contrast,
        );
      });
    }
    for (final strings in [AppStrings.english, AppStrings.arabic]) {
      testWidgets('opens and dismisses in ${strings.languageCode}', (
        tester,
      ) async {
        await pumpReplay(tester, strings: strings);

        await tester.tap(branchControl());
        await tester.pumpAndSettle();

        // Both visibilities are offered, each with the note that says what it
        // means. Neither is buried behind a menu.
        expect(find.text(strings.branchEntryTitle), findsOneWidget);
        expect(find.text(strings.branchEntryBlind), findsOneWidget);
        expect(find.text(strings.branchEntryBlindNote), findsOneWidget);
        expect(find.text(strings.branchEntryStudy), findsOneWidget);
        expect(find.text(strings.branchEntryStudyNote), findsOneWidget);

        // Backing out leaves the review exactly where it was: no sandbox, no
        // cursor move. Scrolled into view first: the chooser is taller than a
        // 390 dp landscape body, so a blind tap would miss and this test would
        // pass for the wrong reason.
        final cancel = find.byKey(const ValueKey('branch-entry-cancel'));
        await tester.ensureVisible(cancel);
        await tester.pumpAndSettle();
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(find.text(strings.branchEntryTitle), findsNothing);
        expect(find.byType(BranchSandboxHost), findsNothing);
        expect(find.byType(MatchReplayScreen), findsOneWidget);
      });

      testWidgets('long ${strings.languageCode} copy renders unclipped', (
        tester,
      ) async {
        // Real copy, measured. The two notes are the longest strings on this
        // surface and the ones a narrow chooser would clip first.
        await pumpReplay(tester, strings: strings);
        await tester.tap(branchControl());
        await tester.pumpAndSettle();

        for (final text in [
          strings.branchEntryBody,
          strings.branchEntryBlindNote,
          strings.branchEntryStudyNote,
        ]) {
          final finder = find.text(text);
          expect(finder, findsOneWidget, reason: text);
          final widget = tester.widget<Text>(finder);
          final rendered = tester.renderObject<RenderBox>(finder);
          final painter = TextPainter(
            text: TextSpan(text: text, style: widget.style),
            textDirection: strings.textDirection,
            maxLines: null,
          )..layout(maxWidth: rendered.size.width);
          expect(painter.didExceedMaxLines, isFalse, reason: 'clipped: $text');
          expect(
            rendered.size.height,
            greaterThanOrEqualTo(painter.height - 0.5),
            reason:
                'the box is shorter than the text it holds, so a glyph is cut '
                'off: $text',
          );
        }
      });
    }

    for (final visibility in const [
      ('branch-entry-blind', TableMode.branchSandboxBlind),
      ('branch-entry-study', TableMode.branchSandboxStudy),
    ]) {
      testWidgets('${visibility.$1} starts a ${visibility.$2.name} sandbox', (
        tester,
      ) async {
        await pumpReplay(tester);
        await tester.tap(branchControl());
        await tester.pumpAndSettle();
        final choice = find.byKey(ValueKey(visibility.$1));
        await tester.ensureVisible(choice);
        await tester.pumpAndSettle();
        await tester.tap(choice);
        await tester.pumpAndSettle(const Duration(seconds: 60));

        expect(find.byType(BranchSandboxHost), findsOneWidget);
        final table = tester.widget<PhysicalTablePlayfield>(
          find.byType(PhysicalTablePlayfield),
        );
        // The chosen visibility is what the table actually renders, not just
        // what was passed along the way.
        expect(
          table.revealedHands.isNotEmpty,
          visibility.$2.capabilities.revealsAllHands,
        );
      });
    }
  });

  group('the branch control stays operable under the analysis card', () {
    // B41. The layout half — the target does not overlap the popover or the
    // scrub overlay — is measured by the Sprint 05 collision map in
    // `replay_hud_overlap_test.dart`. What was missing is the behavioural
    // half the assertion names explicitly: *tapping* it with the card open.
    // A control that the popover covers, or that the card's tap region
    // swallows, would still pass every rect check and be dead to the player.
    testWidgets('branching works with the analysis card expanded', (
      tester,
    ) async {
      await pumpReplay(tester);

      // Step onto a played move first, so the card opens with something in it
      // rather than as an empty rectangle.
      await tester.tap(find.byTooltip(AppStrings.english.replayNext));
      await tester.pumpAndSettle(const Duration(seconds: 30));
      await tester.tap(find.byTooltip(AppStrings.english.replayCoachTitle));
      await tester.pumpAndSettle(const Duration(seconds: 30));
      expect(
        find.byType(ReviewAnalysisCard),
        findsOneWidget,
        reason: 'the card must be open for this to test anything',
      );
      expect(
        tester
            .widget<ReviewAnalysisCard>(find.byType(ReviewAnalysisCard))
            .expanded,
        isTrue,
      );

      // The real control, hit-tested where it renders — not called directly.
      await tester.tap(branchControl());
      await tester.pumpAndSettle();
      expect(
        find.text(AppStrings.english.branchEntryTitle),
        findsOneWidget,
        reason:
            'the branch control did not respond with the analysis card open',
      );

      final choice = find.byKey(const ValueKey('branch-entry-blind'));
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
      await tester.tap(choice);
      await tester.pumpAndSettle(const Duration(seconds: 60));
      expect(
        find.byType(BranchSandboxHost),
        findsOneWidget,
        reason: 'the chooser opened but the sandbox never did',
      );
    });
  });

  group('the docked entry names itself exactly once', () {
    // Found on the real web build, not here: giving `IconButton` a `tooltip`
    // AND wrapping it in a labelled `Semantics` merges two names onto one
    // node, and a screen reader then reads "Play on from here Play on from
    // here". The rendered tree is the only place that shows up.
    for (final strings in [AppStrings.english, AppStrings.arabic]) {
      testWidgets('in ${strings.languageCode}, docked', (tester) async {
        // A portrait body routes to the docked layout, where the branch entry
        // lives in the app bar rather than in the rail.
        await pumpReplay(tester, strings: strings, size: const Size(780, 1688));

        final labelled = find.bySemanticsLabel(strings.branchStart);
        expect(labelled, findsWidgets, reason: 'the control must be named');

        final handle = tester.ensureSemantics();

        // The defect is one node carrying the SAME string as both its label
        // and its tooltip. Flutter's VM semantics tree keeps them as separate
        // properties and reads fine; Flutter **web** renders both as text, and
        // a screen reader then says the name twice. Counting labels therefore
        // proves nothing — asserting the node names itself once, in one
        // property, is what bites.
        final named = <SemanticsData>[];
        void visit(SemanticsNode node) {
          final data = node.getSemanticsData();
          if (data.label == strings.branchStart) named.add(data);
          node.visitChildren((child) {
            visit(child);
            return true;
          });
        }

        visit(tester.semantics.find(find.byType(MaterialApp)));
        expect(named, hasLength(1), reason: 'exactly one node is the control');
        expect(
          named.single.tooltip,
          isEmpty,
          reason:
              'the node carries its name as both label and tooltip, so the '
              'web build announces "${strings.branchStart}" twice. Put the '
              'Tooltip outside the merged Semantics, as ReplayRailButton does.',
        );
        handle.dispose();
      });
    }
  });

  group('a decided frame refuses, and says why', () {
    testWidgets('the last frame of a won match offers no branch', (
      tester,
    ) async {
      await pumpReplay(tester);

      // Jump to the end, where the match has a winner.
      await tester.tap(find.byTooltip(AppStrings.english.replayLast));
      await tester.pumpAndSettle(const Duration(seconds: 60));

      // Disabled, and its label says what changed rather than leaving a dead
      // control the player has to guess about.
      expect(
        find.byTooltip(AppStrings.english.branchUnavailableComplete),
        findsOneWidget,
      );
      expect(find.byTooltip(AppStrings.english.branchStart), findsNothing);

      // Tapping it does nothing: no chooser, no sandbox.
      await tester.tap(branchControl(), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.english.branchEntryTitle), findsNothing);
      expect(find.byType(BranchSandboxHost), findsNothing);
    });

    testWidgets('the refusal is the domain rule, not a screen rule', (
      tester,
    ) async {
      // Same answer, asked of the value the seed builder consults. A screen
      // that decided this for itself could disagree with the seed and offer a
      // branch the seed then refuses to build.
      final decided = branchFrame(branchSnapshot(), matchWinner: null);
      expect(ReplayBranchSeed.refusalFor(decided, nextFrame: null), isNull);

      final won = branchFrame(branchSnapshot(), matchWinner: PlayerSeat.south);
      expect(
        ReplayBranchSeed.refusalFor(won, nextFrame: null),
        ReplayBranchRefusal.matchAlreadyComplete,
      );
      expect(
        ReplayBranchSeed.fromFrame(
          won,
          nextFrame: null,
          branchStart: DateTime.utc(2026),
        ),
        isNull,
      );
    });
  });
}
