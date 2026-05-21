import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/data/persistence/match_repository.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/ui/core/brand/app_brand_mark.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';

import 'support/test_fixtures.dart';

void main() {
  testWidgets('main menu shows primary navigation entries', (tester) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    expect(find.text('New Game'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Rules / Help'), findsOneWidget);
  });

  testWidgets('high contrast cues keep the selected card theme', (
    tester,
  ) async {
    final preferences = MemoryPreferencesRepository()
      ..preferences = GamePreferences.defaults().copyWith(
        cardThemeId: 'minimal_symbols',
        highContrastCards: true,
      );

    await tester.pumpWidget(testApp(preferencesRepository: preferences));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Minimal Symbols card theme preview'),
      findsOneWidget,
    );
  });

  testWidgets('splash uses the themed showcase card fan', (tester) async {
    await tester.pumpWidget(testApp(initialRoute: AppRoutes.splash));
    await tester.pump();

    expect(find.byType(ShowcaseCardFan), findsOneWidget);
  });

  testWidgets('new game opens the setup form with defaults', (tester) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();

    expect(find.text('Classic Hareeg setup'), findsWidgets);
    expect(find.text('CPU difficulty'), findsOneWidget);
    expect(find.text('Casual'), findsOneWidget);
    expect(find.text('First starter'), findsOneWidget);
    expect(find.text('You start'), findsOneWidget);
    expect(find.text('House rules'), findsOneWidget);
  });

  testWidgets('leaving a newly started table returns to the main menu', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Start Table'), 300);
    await tester.tap(find.text('Start Table'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Pause'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave table'));
    await tester.pumpAndSettle();

    expect(find.text('New Game'), findsOneWidget);
    expect(find.text('Classic Hareeg setup'), findsNothing);
  });

  testWidgets('rules-help and settings routes are reachable', (tester) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Rules / Help'));
    await tester.pumpAndSettle();
    expect(find.text('Classic Hareeg rules'), findsWidgets);
    expect(find.byType(AppBrandMark), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Table rules'), findsOneWidget);
    expect(find.text('Assistance'), findsOneWidget);
    expect(find.text('Look'), findsOneWidget);
    expect(find.text('Feel'), findsOneWidget);
  });

  testWidgets('settings → About & Licenses opens the attribution screen', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('About & Licenses'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('About & Licenses'));
    await tester.pumpAndSettle();

    expect(find.text('Card themes'), findsOneWidget);
    expect(find.text('Sandline Lounge'), findsWidgets);
    expect(find.byType(AppBrandMark), findsOneWidget);
  });

  testWidgets('saved match resumes onto the table and can be abandoned', (
    tester,
  ) async {
    final repository = MemoryMatchRepository(saved: defaultSnapshot());
    await tester.pumpWidget(testApp(matchRepository: repository));
    await tester.pumpAndSettle();

    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Abandon saved match'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Pause'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave table'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abandon saved match'));
    await tester.pumpAndSettle();

    expect(find.text('No saved match yet'), findsOneWidget);
    expect(repository.saved, isNull);
  });
}

Widget testApp({
  PreferencesRepository? preferencesRepository,
  MatchRepository? matchRepository,
  String initialRoute = AppRoutes.home,
}) {
  return HareegTableApp(
    preferencesRepository:
        preferencesRepository ?? MemoryPreferencesRepository(),
    matchRepository: matchRepository ?? MemoryMatchRepository(),
    initialRouteOverride: initialRoute,
  );
}

ClassicHareegMatchSnapshot defaultSnapshot({
  PlayerSeat currentSeat = PlayerSeat.south,
  TurnPhase turnPhase = TurnPhase.action,
}) {
  final round = ClassicHareegRound.deal(
    setup: ClassicHareegSetup.defaults(),
    seed: 3,
  );
  return ClassicHareegMatchSnapshot(
    setup: round.setup,
    hands: round.hands,
    stock: round.stock,
    discardPile: round.discardPile,
    starter: round.starter,
    currentSeat: currentSeat,
    turnPhase: turnPhase,
    savedAt: DateTime.utc(2026, 5, 18),
  );
}
