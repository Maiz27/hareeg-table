import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/data/persistence/match_repository.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';

import 'support/test_fixtures.dart';

void main() {
  testWidgets('main menu shows primary navigation entries', (tester) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    expect(find.text('Hareeg Table'), findsWidgets);
    expect(find.text('New Game'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Rules / Help'), findsOneWidget);
  });

  testWidgets('new game opens the setup form with defaults', (tester) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();

    expect(find.text('Classic Hareeg setup'), findsWidgets);
    expect(find.text('Casual'), findsOneWidget);
    expect(find.text('Human starts'), findsOneWidget);
  });

  testWidgets('rules-help and settings routes are reachable', (tester) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rules / Help'));
    await tester.pumpAndSettle();
    expect(find.text('Classic Hareeg rules'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Match defaults'), findsOneWidget);
    expect(find.text('CPU difficulty'), findsOneWidget);
  });

  testWidgets('settings → About & Licenses opens the attribution screen', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('About & Licenses'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('About & Licenses'));
    await tester.pumpAndSettle();

    expect(find.text('Card themes'), findsOneWidget);
    expect(find.text('Hareeg Original'), findsWidgets);
  });

  testWidgets('saved match resumes onto the table and can be abandoned', (
    tester,
  ) async {
    final repository = MemoryMatchRepository(saved: defaultSnapshot());
    await tester.pumpWidget(testApp(matchRepository: repository));
    await tester.pumpAndSettle();

    expect(find.text('Resume saved Classic Hareeg table'), findsOneWidget);

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
