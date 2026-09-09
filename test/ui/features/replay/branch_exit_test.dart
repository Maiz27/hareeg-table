import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_orientation.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_replay_record.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/replay_branch_session.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/game_table/table_session_config.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/ui/features/game_table/views/game_table_screen.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/physical_table_playfield.dart';
import 'package:hareeg_table/ui/features/replay/views/branch_sandbox_host.dart';
import 'package:hareeg_table/ui/features/replay/views/match_replay_screen.dart';
import 'package:hareeg_table/ui/features/replay/widgets/replay_hud_clusters.dart';
import 'package:hareeg_table/ui/features/replay/widgets/replay_scrub_bar.dart';

import '../../../support/branch_sandbox_harness.dart';
import '../../../support/completed_match_fixture.dart';
import '../../../support/test_fixtures.dart';

/// Leaving a sandbox: one policy, four routes, and nothing left behind.
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

/// The four ways a player leaves, and how each one is driven.
///
/// Android system Back and browser Back are one channel in a widget test:
/// both arrive as the platform's pop route message, which is exactly what
/// `PopScope` intercepts. Driving that message covers the code path for both;
/// the two runtime substrates each execute the one they can, and neither is
/// asked to prove the other.
typedef _ExitRoute = ({
  String name,
  Future<void> Function(WidgetTester tester) drive,
});

/// Records what a screen asked the device to do, in order.
class _RecordingOrientationPolicy implements OrientationPolicy {
  final List<String> requests = [];

  @override
  Future<void> usePortrait() async => requests.add('portrait');

  @override
  Future<void> useLandscape() async => requests.add('landscape');
}

void main() {
  setUpAll(() {
    final state = buildCompletedMatch(seed: 13).recorderState;
    _transcript = MatchActionTranscript(
      initialSnapshot: state.initialSnapshot!,
      entries: state.entries,
    );
  });

  final strings = AppStrings.english;

  Future<void> pauseLeave(WidgetTester tester) async {
    await tester.tap(find.byTooltip(strings.pauseTable));
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.branchExitSandbox));
    await tester.pumpAndSettle();
  }

  Future<void> inAppBack(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('branch-exit')));
    await tester.pumpAndSettle();
  }

  Future<void> platformBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  final routes = <_ExitRoute>[
    (name: 'pause leave', drive: pauseLeave),
    (name: 'in-app Back', drive: inAppBack),
    (name: 'Android system Back / browser Back', drive: platformBack),
  ];

  /// Opens the replay, records the HUD inventory, then enters a sandbox.
  ///
  /// The count is taken **before** branching: the sandbox is an opaque route,
  /// so the review's rails are not in the tree while it is up. Reading it
  /// after would compare zero against zero and prove nothing about the HUD the
  /// player comes back to.
  Future<int> pumpReplayAndBranch(
    WidgetTester tester, {
    BranchVisibility visibility = BranchVisibility.blind,
  }) async {
    tester.view.physicalSize = const Size(1688, 780);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppStringsScope(
        strings: strings,
        child: Directionality(
          textDirection: strings.textDirection,
          child: MaterialApp(
            home: MatchReplayScreen(
              summary: historySummary(matchId: 'm-exit-aaaaaaaa'),
              historyRepository: _StaticHistoryRepository(_transcript),
              analysisCoach: AnalysisCoachSettings.defaults(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 60));
    final railCountBefore = find.byType(ReplayRailButton).evaluate().length;
    expect(railCountBefore, greaterThan(0), reason: 'no HUD to preserve');

    await tester.tap(find.byKey(const ValueKey('replay-branch-control')));
    await tester.pumpAndSettle();
    final choice = find.byKey(
      ValueKey(
        visibility == BranchVisibility.blind
            ? 'branch-entry-blind'
            : 'branch-entry-study',
      ),
    );
    await tester.ensureVisible(choice);
    await tester.pumpAndSettle();
    await tester.tap(choice);
    await tester.pumpAndSettle(const Duration(seconds: 60));
    expect(find.byType(BranchSandboxHost), findsOneWidget);
    return railCountBefore;
  }

  group('divergence is armed by applied actions, not by pointers', () {
    test('a fresh session has not diverged, and one action arms it', () {
      final session = ReplayBranchSession.start(
        frame: branchFrame(branchSnapshot()),
        nextFrame: null,
        coachEligible: false,
        branchStart: DateTime.utc(2026, 9, 7),
      )!;
      expect(session.hasDiverged, isFalse);
      session.recordAppliedAction();
      expect(session.hasDiverged, isTrue);
      // Idempotent: a second action does not "un-diverge" it.
      session.recordAppliedAction();
      expect(session.hasDiverged, isTrue);
    });

    testWidgets('tapping around without applying anything leaves it clean', (
      tester,
    ) async {
      // Branch at a South-turn frame and touch the surface without ever
      // completing a move. If divergence tracked pointer activity instead of
      // applied actions, this would confirm on the way out.
      await pumpBranchSandbox(
        tester,
        branchSandboxApp(
          frame: branchFrame(
            branchSnapshot(
              southHand: branchFinishingHand,
              openingState: branchOpened(PlayerSeat.south),
            ),
          ),
          visibility: BranchVisibility.blind,
          coachEligible: false,
        ),
      );

      // Select and deselect a card, open and close the score sheet: pointer
      // activity, no applied action.
      final rect = tester.getRect(branchSouthCard(branchFinishingHand.first));
      await tester.tapAt(Offset(rect.left + 6, rect.center.dy));
      await tester.pump();
      await tester.tapAt(Offset(rect.left + 6, rect.center.dy));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(strings.scores));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(strings.close));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('branch-exit')));
      await tester.pumpAndSettle();

      // No confirmation: nothing happened, so there is nothing to discard.
      expect(find.text(strings.branchExitTitle), findsNothing);
    });

    testWidgets('a CPU action arms it just as a South action does', (
      tester,
    ) async {
      // The seed hands the turn to a CPU. By the time the sandbox settles, a
      // CPU has moved and nothing the player did caused it — but the sandbox
      // has still left its historical line.
      await pumpBranchSandbox(
        tester,
        branchSandboxApp(
          frame: branchFrame(
            branchSnapshot(
              currentSeat: PlayerSeat.east,
              turnPhase: TurnPhase.draw,
            ),
          ),
          visibility: BranchVisibility.blind,
          coachEligible: false,
        ),
      );
      expect(
        tester
            .widget<PhysicalTablePlayfield>(find.byType(PhysicalTablePlayfield))
            .currentSeat,
        PlayerSeat.south,
        reason: 'the CPUs really did take their turns',
      );

      await tester.tap(find.byKey(const ValueKey('branch-exit')));
      await tester.pumpAndSettle();
      expect(find.text(strings.branchExitTitle), findsOneWidget);
    });

    testWidgets('leaving mid-run, between two CPU actions, still confirms', (
      tester,
    ) async {
      // The window this closes: a CPU action has applied, the loop is dwelling
      // before its next decision, and the player leaves. Settling the loop
      // first — which every other test here does — hides the defect entirely,
      // because by then the run has returned and reported itself.
      tester.view.physicalSize = const Size(1688, 780);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        branchSandboxApp(
          frame: branchFrame(
            branchSnapshot(
              currentSeat: PlayerSeat.east,
              turnPhase: TurnPhase.draw,
            ),
          ),
          visibility: BranchVisibility.blind,
          coachEligible: false,
        ),
      );

      PhysicalTablePlayfield table() => tester.widget<PhysicalTablePlayfield>(
        find.byType(PhysicalTablePlayfield),
      );

      // Step forward frame by frame instead of settling, and stop the instant
      // the board shows one applied action.
      await tester.pump();
      final openingStock = table().stockCount;
      var stepsToFirstAction = 0;
      while (table().stockCount == openingStock && stepsToFirstAction < 400) {
        await tester.pump(const Duration(milliseconds: 25));
        stepsToFirstAction += 1;
      }
      expect(
        table().stockCount,
        lessThan(openingStock),
        reason: 'no CPU action applied within the step budget',
      );
      final stockAtExit = table().stockCount;

      // Leave right now, without letting the loop finish.
      await tester.tap(find.byKey(const ValueKey('branch-exit')));
      await tester.pump();
      expect(
        find.text(strings.branchExitTitle),
        findsOneWidget,
        reason:
            'the sandbox had already diverged, but leaving mid-run asked '
            'nothing before discarding it',
      );

      // And this is what proves the tap really landed inside the run rather
      // than after it: the loop went on applying actions underneath the
      // confirmation.
      await tester.tap(find.text(strings.branchExitCancel));
      await tester.pumpAndSettle(const Duration(seconds: 30));
      expect(
        table().stockCount,
        lessThan(stockAtExit),
        reason:
            'the CPU loop had already finished when the exit was tapped, '
            'so this proves nothing about the mid-run window',
      );
    });
  });

  group('one exit policy, whichever route the player takes', () {
    for (final route in routes) {
      testWidgets('${route.name} returns to the branch-point frame', (
        tester,
      ) async {
        final railCountBefore = await pumpReplayAndBranch(tester);

        await route.drive(tester);
        await tester.pumpAndSettle(const Duration(seconds: 30));

        // A branch taken at the opening frame has applied nothing yet — the
        // seat on turn is south — so this leaves immediately and lands back on
        // the review it came from.
        expect(
          find.byType(BranchSandboxHost),
          findsNothing,
          reason: route.name,
        );
        expect(find.byType(MatchReplayScreen), findsOneWidget);
        // Sprint 05's HUD is intact: the rails are the same inventory they
        // were before the sandbox opened, not a rebuilt or degraded surface.
        expect(
          find.byType(ReplayRailButton).evaluate().length,
          railCountBefore,
          reason: route.name,
        );
      });

      testWidgets('${route.name} confirms once the sandbox has diverged', (
        tester,
      ) async {
        await pumpBranchSandbox(
          tester,
          branchSandboxApp(
            frame: branchFrame(
              branchSnapshot(
                southHand: branchFinishingHand,
                openingState: branchOpened(PlayerSeat.south),
              ),
            ),
            visibility: BranchVisibility.blind,
            coachEligible: false,
          ),
        );

        // One applied action: a real discard.
        await branchDiscard(tester, branchFinishingHand.last);

        await route.drive(tester);
        await tester.pumpAndSettle();

        // Localized, and it says what leaving costs.
        expect(
          find.text(strings.branchExitTitle),
          findsOneWidget,
          reason: route.name,
        );
        expect(find.text(strings.branchExitBody), findsOneWidget);
        expect(find.text(strings.branchExitConfirm), findsOneWidget);
        expect(find.text(strings.branchExitCancel), findsOneWidget);

        // Keeping the sandbox leaves it exactly where it was.
        await tester.tap(find.text(strings.branchExitCancel));
        await tester.pumpAndSettle();
        expect(find.byType(BranchSandboxHost), findsOneWidget);
        expect(find.text(strings.branchExitTitle), findsNothing);
      });
    }
  });

  group('a sandbox exposes no durable affordance, at any point', () {
    testWidgets('mid-play and at completion, the escape hatches are absent', (
      tester,
    ) async {
      Future<void> assertNoDurableAffordance(String where) async {
        for (final absent in [
          strings.reportTableIssue,
          strings.shareReport,
          strings.newMatchSameSetup,
          strings.returnToMenu,
          strings.motionSpeedLabel,
          strings.highContrastCards,
        ]) {
          expect(find.text(absent), findsNothing, reason: '$where: $absent');
        }
      }

      await pumpBranchSandbox(
        tester,
        branchSandboxApp(
          frame: branchFrame(
            branchSnapshot(
              southHand: branchFinishingHand,
              openingState: branchOpened(PlayerSeat.south),
              scores: const {
                PlayerSeat.south: 0,
                PlayerSeat.east: 30,
                PlayerSeat.north: 30,
                PlayerSeat.west: 30,
              },
              roundNumber: 3,
            ),
          ),
          visibility: BranchVisibility.blind,
          coachEligible: false,
        ),
      );

      await assertNoDurableAffordance('mid-play');
      await tester.tap(find.byTooltip(strings.pauseTable));
      await tester.pumpAndSettle();
      await assertNoDurableAffordance('paused');
      await tester.tap(find.text(strings.branchResume));
      await tester.pumpAndSettle();

      // Every opponent is one round-penalty from elimination, so south's
      // finish wins the sandbox outright.
      await branchFinishRound(tester);
      await tester.pumpAndSettle(const Duration(seconds: 30));

      // Exactly two exits, and nothing else.
      expect(find.text(strings.branchReturnToReplay), findsOneWidget);
      expect(find.text(strings.branchRestart), findsOneWidget);
      await assertNoDurableAffordance('completed');
    });
  });

  group('leaving a sandbox does not rearrange the reviewer', () {
    // Found on the Pixel_8a, not in a test: leaving a sandbox dropped the
    // replay viewer from its short landscape HUD into the docked portrait one.
    // The table restores portrait on dispose because every *other* table is
    // pushed from a portrait surface — but a sandbox is pushed from the
    // reviewer, which is landscape too, and the restore landed after the
    // reviewer had already asked for landscape again.
    testWidgets('the sandbox never asks for portrait on its way out', (
      tester,
    ) async {
      final policy = _RecordingOrientationPolicy();
      final previous = AppOrientation.installPolicy(policy);
      addTearDown(() => AppOrientation.installPolicy(previous));

      await pumpBranchSandbox(
        tester,
        branchSandboxApp(
          frame: branchFrame(branchSnapshot()),
          visibility: BranchVisibility.blind,
          coachEligible: false,
        ),
      );
      expect(
        policy.requests,
        contains('landscape'),
        reason: 'the sandbox is a landscape surface',
      );

      // Tear the sandbox down the way a pop does.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(
        policy.requests,
        isNot(contains('portrait')),
        reason:
            'a sandbox that restores portrait leaves the replay viewer it was '
            'pushed from in the wrong layout',
      );
    });

    testWidgets('a live table still restores portrait', (tester) async {
      // The guard is narrow, and this is what keeps it narrow: the fix must
      // not stop an ordinary match from putting the menus back upright.
      final policy = _RecordingOrientationPolicy();
      final previous = AppOrientation.installPolicy(policy);
      addTearDown(() => AppOrientation.installPolicy(previous));

      tester.view.physicalSize = const Size(1688, 780);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: GameTableScreen(
            setup: branchSnapshot().setup,
            session: TableSessionConfig.live(
              matchRepository: MemoryMatchRepository(),
              historyRepository: MemoryMatchHistoryRepository(),
            ),
            preferences: GamePreferences.defaults(),
            onPreferencesChanged: (_) {},
            initialSnapshot: branchSnapshot(),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 30));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(policy.requests, contains('portrait'));
    });
  });

  group('restart returns to the branch point', () {
    testWidgets('the board, the divergence and the clock all reset', (
      tester,
    ) async {
      final clock = BranchTestClock(DateTime.utc(2026, 9, 7, 9));
      await pumpBranchSandbox(
        tester,
        branchSandboxApp(
          frame: branchFrame(
            branchSnapshot(
              southHand: branchFinishingHand,
              openingState: branchOpened(PlayerSeat.south),
            ),
          ),
          visibility: BranchVisibility.study,
          coachEligible: false,
          clock: clock.call,
        ),
      );

      PhysicalTablePlayfield table() => tester.widget<PhysicalTablePlayfield>(
        find.byType(PhysicalTablePlayfield),
      );

      final startingHand = table().southCards.map((c) => c.id).toList();
      expect(startingHand, hasLength(branchFinishingHand.length));

      await branchDiscard(tester, branchFinishingHand.last);
      expect(
        table().southCards.map((c) => c.id).toList(),
        isNot(startingHand),
        reason: 'the sandbox really moved before the restart',
      );

      clock.advance(const Duration(minutes: 5));
      await tester.tap(find.byTooltip(strings.pauseTable));
      await tester.pumpAndSettle();
      await tester.tap(find.text(strings.branchRestart));
      await tester.pumpAndSettle(const Duration(seconds: 30));

      // 1. The board is the seed again.
      expect(table().southCards.map((c) => c.id).toList(), startingHand);
      // 2. The chosen visibility survived.
      expect(table().revealedHands, isNotEmpty);
      // 3. Divergence reset: leaving now asks nothing.
      await tester.tap(find.byKey(const ValueKey('branch-exit')));
      await tester.pumpAndSettle();
      expect(find.text(strings.branchExitTitle), findsNothing);
    });
  });

  group('the exit confirmation holds its real copy at every width', () {
    // B65's other half. The entry chooser is measured in
    // `branch_entry_test.dart`; the confirmation was not measured at all, and
    // it is the surface with the longest Arabic sentence in the feature.
    //
    // The dialog is opened once over a genuinely diverged sandbox and then
    // re-measured as the viewport is resized across every contracted size.
    // Driving a discard at 320 dp is not possible — the sandbox is a
    // landscape surface — but the panel it puts up must still survive that
    // width, and resizing under it is the honest way to ask.
    const sizes = <(String, Size)>[
      ('844x390 short', Size(844, 390)),
      ('914x411 short', Size(914, 411)),
      ('926x428 short', Size(926, 428)),
      ('390x844 docked', Size(390, 844)),
      ('320x568 docked', Size(320, 568)),
    ];

    for (final locale in [AppStrings.english, AppStrings.arabic]) {
      testWidgets('${locale.languageCode} copy is never clipped', (
        tester,
      ) async {
        await pumpBranchSandbox(
          tester,
          branchSandboxApp(
            frame: branchFrame(
              branchSnapshot(
                southHand: branchFinishingHand,
                openingState: branchOpened(PlayerSeat.south),
              ),
            ),
            visibility: BranchVisibility.blind,
            coachEligible: false,
            strings: locale,
          ),
        );
        await branchDiscard(tester, branchFinishingHand.last);
        await tester.tap(find.byKey(const ValueKey('branch-exit')));
        await tester.pumpAndSettle();
        expect(find.text(locale.branchExitTitle), findsOneWidget);

        for (final (name, size) in sizes) {
          tester.view.physicalSize = size * 2;
          tester.view.devicePixelRatio = 2.0;
          await tester.pumpAndSettle();

          for (final copy in [
            locale.branchExitTitle,
            locale.branchSandboxBadge,
            locale.branchExitBody,
            locale.branchExitConfirm,
            locale.branchExitCancel,
          ]) {
            final finder = find.text(copy);
            expect(finder, findsOneWidget, reason: '$name: $copy');
            final widget = tester.widget<Text>(finder);
            final box = tester.renderObject<RenderBox>(finder);
            final painter = TextPainter(
              text: TextSpan(text: copy, style: widget.style),
              textDirection: locale.textDirection,
              // Measured against the limit the widget actually declares. A
              // one-line header that ellipsizes is a clip, not a layout that
              // merely wrapped.
              maxLines: widget.maxLines,
            )..layout(maxWidth: box.size.width);
            expect(
              painter.didExceedMaxLines,
              isFalse,
              reason: '$name clipped: $copy',
            );
            expect(
              box.size.height,
              greaterThanOrEqualTo(painter.height - 0.5),
              reason: '$name cut a glyph off: $copy',
            );
          }

          expect(
            tester.takeException(),
            isNull,
            reason: '$name overflowed while the confirmation was up',
          );
        }
      });
    }
  });

  group('the review comes back to the exact frame it was left at', () {
    // B46 and B51's restoration clause. The group above proves the *screen*
    // comes back; it branches from the opening frame, where "restored the
    // cursor" and "rebuilt at zero" are the same observation and neither can
    // fail. Everything here starts from a non-initial cursor, so the two are
    // finally distinguishable.
    String cursorLabel(WidgetTester tester) =>
        tester.widget<ReplayScrubTarget>(find.byType(ReplayScrubTarget)).label;

    Future<void> pumpReplay(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1688, 780);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        AppStringsScope(
          strings: strings,
          child: Directionality(
            textDirection: strings.textDirection,
            child: MaterialApp(
              home: MatchReplayScreen(
                summary: historySummary(matchId: 'm-cursor-aaaaaaaa'),
                historyRepository: _StaticHistoryRepository(_transcript),
                analysisCoach: AnalysisCoachSettings.defaults(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 60));
    }

    Future<void> step(WidgetTester tester, String tooltip, int times) async {
      for (var i = 0; i < times; i++) {
        await tester.tap(find.byTooltip(tooltip));
        await tester.pumpAndSettle(const Duration(seconds: 30));
      }
    }

    Future<void> enterBranch(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('replay-branch-control')));
      await tester.pumpAndSettle();
      final choice = find.byKey(const ValueKey('branch-entry-blind'));
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
      await tester.tap(choice);
      await tester.pumpAndSettle(const Duration(seconds: 60));
      expect(find.byType(BranchSandboxHost), findsOneWidget);
    }

    for (final route in routes) {
      testWidgets('${route.name} restores a non-initial cursor', (
        tester,
      ) async {
        await pumpReplay(tester);
        final atStart = cursorLabel(tester);

        await step(tester, strings.replayNext, 7);
        final chosen = cursorLabel(tester);
        expect(
          chosen,
          isNot(atStart),
          reason:
              'the cursor never moved, so "restored" would be indistinguishable '
              'from "rebuilt at the opening frame"',
        );
        final railsBefore = find.byType(ReplayRailButton).evaluate().length;

        await enterBranch(tester);
        // A sandbox that applied nothing could be popped by any mechanism and
        // still land somewhere plausible. Diverge first.
        await branchSettleToSouthTurn(tester);
        expect(await branchPlayOneSouthAction(tester), isTrue);

        await route.drive(tester);
        await tester.pumpAndSettle();
        expect(find.text(strings.branchExitTitle), findsOneWidget);
        await tester.tap(find.text(strings.branchExitConfirm));
        await tester.pumpAndSettle(const Duration(seconds: 60));

        expect(
          find.byType(BranchSandboxHost),
          findsNothing,
          reason: route.name,
        );
        expect(find.byType(MatchReplayScreen), findsOneWidget);
        expect(
          cursorLabel(tester),
          chosen,
          reason: '${route.name} did not restore the branch-point frame',
        );
        expect(find.byType(ReplayRailButton).evaluate().length, railsBefore);
      });
    }

    testWidgets(
      'completion restores it too, after the sandbox is played out',
      (tester) async {
        // B51's other half. Reaching completion needs a late branch point, so
        // this jumps to the end and steps back to the nearest branchable frame
        // — which is also, conveniently, as non-initial as a cursor gets.
        await pumpReplay(tester);
        final control = find.byKey(const ValueKey('replay-branch-control'));
        await step(tester, strings.replayLast, 1);
        var back = 0;
        while (tester.widget<ReplayRailButton>(control).onPressed == null) {
          expect(
            back,
            lessThan(12),
            reason: 'no branchable frame near the end',
          );
          await step(tester, strings.replayPrevious, 1);
          back += 1;
        }
        expect(back, greaterThan(0), reason: 'the terminal frame must refuse');
        // Far enough back that south has real turns before the round decides.
        await step(tester, strings.replayPrevious, 12);

        final chosen = cursorLabel(tester);
        final railsBefore = find.byType(ReplayRailButton).evaluate().length;
        await enterBranch(tester);

        final completion = find.text(strings.branchCompletionTitle);
        var applied = 0;
        var idle = 0;
        while (completion.evaluate().isEmpty) {
          if (await branchPlayOneSouthAction(tester)) {
            applied += 1;
            idle = 0;
          } else {
            idle += 1;
            expect(idle, lessThan(12), reason: 'the turn stopped coming back');
            await tester.pumpAndSettle(const Duration(seconds: 30));
          }
          expect(applied, lessThan(400), reason: 'never reached completion');
        }
        expect(
          applied,
          greaterThan(0),
          reason: 'completion must be reached by playing, not on arrival',
        );

        // Exactly two ways out, and nothing else (B51).
        expect(find.text(strings.branchReturnToReplay), findsOneWidget);
        expect(find.text(strings.branchRestart), findsOneWidget);

        await tester.tap(find.text(strings.branchReturnToReplay));
        await tester.pumpAndSettle();
        expect(find.text(strings.branchExitTitle), findsOneWidget);
        await tester.tap(find.text(strings.branchExitConfirm));
        await tester.pumpAndSettle(const Duration(seconds: 60));

        expect(find.byType(MatchReplayScreen), findsOneWidget);
        expect(
          cursorLabel(tester),
          chosen,
          reason: 'completion returned to a different frame',
        );
        expect(find.byType(ReplayRailButton).evaluate().length, railsBefore);
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  });
}
