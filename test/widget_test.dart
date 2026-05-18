import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/data/persistence/match_repository.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';

void main() {
  testWidgets('main menu exposes primary navigation', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pump();

    expect(find.text('Hareeg Table'), findsOneWidget);
    expect(find.text('New Game'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Rules / Help'), findsOneWidget);
    expect(find.text('Hareeg 14'), findsOneWidget);
    expect(find.text('Fifties'), findsOneWidget);
  });

  testWidgets('new game opens setup with expected defaults', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pump();

    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();

    expect(find.text('Classic Hareeg setup'), findsOneWidget);
    expect(find.text('Casual'), findsOneWidget);
    expect(find.text('Human starts'), findsOneWidget);
    expect(find.text('51'), findsOneWidget);
    expect(find.text('2 decks'), findsOneWidget);
    expect(find.text('4s'), findsOneWidget);
    expect(find.text('Assisted'), findsOneWidget);
  });

  testWidgets('setup can start the table route', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pump();

    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Start Table'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Start Table'));
    await tester.pumpAndSettle();

    expect(find.text('Classic Hareeg Table'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('CPU East'), findsOneWidget);
    expect(find.text('CPU North'), findsOneWidget);
    expect(find.text('CPU West'), findsOneWidget);
    expect(find.text('Stock'), findsOneWidget);
    expect(find.text('Discard'), findsWidgets);
    expect(
      find.text('Select at least three cards for a meld.'),
      findsOneWidget,
    );
  });

  testWidgets('rules and settings routes are reachable', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pump();

    await tester.tap(find.text('Rules / Help'));
    await tester.pumpAndSettle();

    expect(find.text('Classic Hareeg rules'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Fifty / Khamsin'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Fifty / Khamsin'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Auto-sort hand'), findsOneWidget);
    expect(find.text('Reduced motion'), findsOneWidget);
  });

  testWidgets('saved match can be resumed and abandoned from menu', (
    tester,
  ) async {
    final matchRepository = _MemoryMatchRepository(saved: _snapshot());
    await tester.pumpWidget(_testApp(matchRepository: matchRepository));
    await tester.pump();

    expect(find.text('Resume saved Classic Hareeg table'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Classic Hareeg Table'), findsOneWidget);

    await tester.tap(find.byTooltip('Leave table'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abandon saved match'));
    await tester.pump();

    expect(find.text('No saved match yet'), findsOneWidget);
    expect(matchRepository.saved, isNull);
  });

  testWidgets('resumed CPU turn advances back to human input', (tester) async {
    final matchRepository = _MemoryMatchRepository(
      saved: _snapshot(
        currentSeat: PlayerSeat.east,
        turnPhase: TurnPhase.action,
      ),
    );
    await tester.pumpWidget(_testApp(matchRepository: matchRepository));
    await tester.pump();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(matchRepository.saved!.currentSeat, PlayerSeat.south);
    expect(matchRepository.saved!.turnPhase, TurnPhase.draw);
    expect(find.widgetWithText(FilledButton, 'Draw Stock'), findsOneWidget);
  });

  testWidgets('human discard lets CPU seats complete turns', (tester) async {
    final snapshot = _snapshot();
    final matchRepository = _MemoryMatchRepository(saved: snapshot);
    await tester.pumpWidget(_testApp(matchRepository: matchRepository));
    await tester.pump();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(snapshot.hands[PlayerSeat.south]!.first.label).first,
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();

    expect(matchRepository.saved!.currentSeat, PlayerSeat.south);
    expect(matchRepository.saved!.turnPhase, TurnPhase.draw);
    expect(find.widgetWithText(FilledButton, 'Draw Stock'), findsOneWidget);
  });
}

Widget _testApp({
  PreferencesRepository? preferencesRepository,
  MatchRepository? matchRepository,
}) {
  return HareegTableApp(
    preferencesRepository:
        preferencesRepository ?? _MemoryPreferencesRepository(),
    matchRepository: matchRepository ?? _MemoryMatchRepository(),
  );
}

ClassicHareegMatchSnapshot _snapshot({
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

class _MemoryPreferencesRepository implements PreferencesRepository {
  GamePreferences preferences = GamePreferences.defaults();

  @override
  Future<GamePreferences> loadPreferences() async => preferences;

  @override
  Future<void> savePreferences(GamePreferences preferences) async {
    this.preferences = preferences;
  }
}

class _MemoryMatchRepository implements MatchRepository {
  _MemoryMatchRepository({this.saved});

  ClassicHareegMatchSnapshot? saved;

  @override
  Future<void> abandonActiveMatch() async {
    saved = null;
  }

  @override
  Future<ClassicHareegMatchSnapshot?> loadActiveMatch() async => saved;

  @override
  Future<void> saveActiveMatch(ClassicHareegMatchSnapshot snapshot) async {
    saved = snapshot;
  }
}
