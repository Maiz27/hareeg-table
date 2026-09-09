import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/match_replay_timeline.dart';
import 'package:hareeg_table/ui/core/cards/card_theme_registry.dart';
import 'package:hareeg_table/ui/features/game_table/table_mode.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/physical_table_playfield.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/analysis_coach_settings.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/replay/review_insight_presenter.dart';
import 'package:hareeg_table/ui/features/replay/widgets/analysis_coach_panel.dart';
import 'package:hareeg_table/ui/features/replay/widgets/review_table_playfield.dart';

import '../../../scenario/classic_hareeg_scenario.dart';

ClassicHareegMatchSnapshot _snapshot() => ClassicHareegScenario.deal(
  currentSeat: PlayerSeat.south,
).controller.toSnapshot(savedAt: replayClockEpoch);

Widget _wrap(Widget child) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.ltr,
    child: Material(child: child),
  ),
);

/// The expectations here are stated as literal product behaviour, deliberately
/// not read out of `TableMode.replayReview.capabilities`. If they were derived
/// from the same value the wrapper reads, a wrong capability table and a wrong
/// wrapper would agree with each other and both tests would pass.
void main() {
  testWidgets('review renders the real table with nothing playable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ReviewTablePlayfield(
          mode: TableMode.replayReview,
          snapshot: _snapshot(),
          theme: CardThemeRegistry.byId(null),
          fiftySecondsRemaining: null,
        ),
      ),
    );

    final playfield = tester.widget<PhysicalTablePlayfield>(
      find.byType(PhysicalTablePlayfield),
    );

    // It really is the live table widget, not a review-shaped imitation.
    expect(playfield.isHumanTurn, isFalse);
    expect(playfield.isCpuRunning, isFalse);
    expect(playfield.canDrawStock, isFalse);
    expect(playfield.canTakeDiscard, isFalse);
    expect(playfield.canReturnDiscard, isFalse);
    expect(playfield.canClaimFifty, isFalse);
    expect(playfield.canReturnOpeningMelds, isFalse);
    expect(playfield.showMeldSuggestions, isFalse);
    expect(playfield.onPlaySelectedMeld, isNull);
    expect(playfield.selectedIds, isEmpty);
  });

  testWidgets('every card-level affordance refuses', (tester) async {
    final snapshot = _snapshot();
    await tester.pumpWidget(
      _wrap(
        ReviewTablePlayfield(
          mode: TableMode.replayReview,
          snapshot: snapshot,
          theme: CardThemeRegistry.byId(null),
          fiftySecondsRemaining: null,
        ),
      ),
    );

    final playfield = tester.widget<PhysicalTablePlayfield>(
      find.byType(PhysicalTablePlayfield),
    );
    final card = (snapshot.hands[PlayerSeat.south] ?? const []).first;

    expect(playfield.canDiscardCard(card), isFalse);
    expect(playfield.canPlayCardOnTable(card), isFalse);
    expect(playfield.canPlaceMeldOnTable(card), isFalse);
    expect(playfield.canRetractMeld(PlayerSeat.south, 0), isFalse);
  });

  testWidgets('a mode that would allow play is refused outright', (
    tester,
  ) async {
    // Not "rendered as if passive": constructing a review table from a playable
    // mode is a programming error, and failing loudly is what keeps the mode
    // table load-bearing rather than decorative.
    expect(
      () => ReviewTablePlayfield(
        mode: TableMode.live,
        snapshot: _snapshot(),
        theme: CardThemeRegistry.byId(null),
        fiftySecondsRemaining: null,
      ),
      throwsArgumentError,
    );

    expect(
      () => ReviewTablePlayfield(
        mode: TableMode.practice,
        snapshot: _snapshot(),
        theme: CardThemeRegistry.byId(null),
        fiftySecondsRemaining: null,
      ),
      throwsArgumentError,
    );
  });

  test('the wrapper reads the capability table rather than restating it', () {
    // If the wrapper hard-coded passivity, changing the mode table would leave
    // it happily passive and this whole file would prove nothing about the
    // modes. These references are what tie the two together.
    final source = File(
      'lib/ui/features/replay/widgets/review_table_playfield.dart',
    ).readAsStringSync();

    expect(source, contains('mode.capabilities'));
    expect(source, contains('capabilities.acceptsHumanInput'));
    expect(source, contains('capabilities.runsCpuTurns'));

    // And it must not build its own table: review happens on the real one.
    for (final forbidden in const [
      'CardView(',
      'SeatMeldLane(',
      'TableCenterArea(',
      'SouthHandFan(',
    ]) {
      expect(source, isNot(contains(forbidden)));
    }
  });

  test('no interaction is wired inline, so a new affordance cannot slip in', () {
    final source = File(
      'lib/ui/features/replay/widgets/review_table_playfield.dart',
    ).readAsStringSync();

    // Every hook comes from the one disabled bundle. An inline closure here
    // would be the first step back towards a playable review.
    final inlineClosures = RegExp(
      r'\n\s+(on|can)[A-Z]\w*:\s*\(',
    ).allMatches(source);
    expect(
      inlineClosures.map((m) => m.group(0)!.trim()).toList(),
      isEmpty,
      reason: 'interaction must come from PassiveTableInteraction',
    );
    expect(source, contains('PassiveTableInteraction()'));
  });

  group('the analysis region is chosen by the mode, not by the screen', () {
    Widget region(TableMode mode) => _wrap(
      ReviewAnalysisRegion(
        mode: mode,
        insights: const [],
        presenter: ReviewInsightPresenter(
          strings: AppStrings.english,
          cards: const {},
        ),
        settings: AnalysisCoachSettings.defaults(),
        isOverridden: false,
        onSettingsChanged: (_) {},
        reviewable: true,
      ),
    );

    testWidgets('review shows the analysis coach', (tester) async {
      await tester.pumpWidget(region(TableMode.replayReview));
      await tester.pumpAndSettle();

      expect(find.byType(AnalysisCoachPanel), findsOneWidget);
      expect(find.text(AppStrings.english.replayCoachTitle), findsOneWidget);
    });

    testWidgets('practice shows no coach here at all', (tester) async {
      // Practice has its own teaching surface; the analysis coach belongs to
      // review. The region asks the mode rather than assuming.
      await tester.pumpWidget(region(TableMode.practice));
      await tester.pumpAndSettle();

      expect(find.byType(AnalysisCoachPanel), findsNothing);
      expect(find.text(AppStrings.english.replayCoachTitle), findsNothing);
    });

    testWidgets('the live coach surface shows nothing here either', (
      tester,
    ) async {
      await tester.pumpWidget(region(TableMode.live));
      await tester.pumpAndSettle();

      expect(find.byType(AnalysisCoachPanel), findsNothing);
    });

    test('the region reads the coach surface rather than restating it', () {
      final source = File(
        'lib/ui/features/replay/widgets/analysis_coach_panel.dart',
      ).readAsStringSync();

      expect(source, contains('capabilities.coachSurface'));
      expect(source, contains('TableCoachSurface.analysis'));
    });
  });
}
