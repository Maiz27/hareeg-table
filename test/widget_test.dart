import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/data/persistence/match_repository.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';

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

    await _pumpCpuTurns(tester);

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
    final discardable = snapshot.hands[PlayerSeat.south]!.firstWhere(
      (card) => !card.isJoker,
    );
    await tester.tap(find.text(discardable.label).first);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await _pumpCpuTurns(tester);

    expect(matchRepository.saved!.currentSeat, PlayerSeat.south);
    expect(matchRepository.saved!.turnPhase, TurnPhase.draw);
    expect(find.widgetWithText(FilledButton, 'Draw Stock'), findsOneWidget);
  });

  testWidgets('CPU turn is visible and locks human input after discard', (
    tester,
  ) async {
    final snapshot = _snapshot();
    final matchRepository = _MemoryMatchRepository(saved: snapshot);
    await tester.pumpWidget(_testApp(matchRepository: matchRepository));
    await tester.pump();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    final discardable = snapshot.hands[PlayerSeat.south]!.firstWhere(
      (card) => !card.isJoker,
    );
    await tester.tap(find.text(discardable.label).first);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pump();

    expect(find.textContaining('CPU East'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Draw Stock'), findsNothing);

    await _pumpCpuTurns(tester);

    final readyDrawButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Draw Stock'),
    );
    expect(readyDrawButton.onPressed, isNotNull);
  });

  testWidgets('selected cards can be played as a persisted meld', (
    tester,
  ) async {
    final meldCards = [
      HareegCard.standard(
        rank: CardRank.five,
        suit: CardSuit.clubs,
        deckIndex: 80,
      ),
      HareegCard.standard(
        rank: CardRank.six,
        suit: CardSuit.clubs,
        deckIndex: 80,
      ),
      HareegCard.standard(
        rank: CardRank.seven,
        suit: CardSuit.clubs,
        deckIndex: 80,
      ),
    ];
    final snapshot = _snapshotWithSouthCards(meldCards);
    final matchRepository = _MemoryMatchRepository(saved: snapshot);
    await tester.pumpWidget(_testApp(matchRepository: matchRepository));
    await tester.pump();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    for (final card in meldCards) {
      await tester.tap(find.text(card.label).first);
      await tester.pump();
    }

    final playMeldButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Play Meld'),
    );
    expect(playMeldButton.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Play Meld'));
    await tester.pumpAndSettle();

    expect(matchRepository.saved!.tableMelds[PlayerSeat.south], hasLength(1));
    expect(
      matchRepository.saved!.tableMelds[PlayerSeat.south]!.single.cards.map(
        (card) => card.label,
      ),
      ['5C', '6C', '7C'],
    );
    expect(find.textContaining('You: 5C 6C 7C'), findsOneWidget);
  });

  testWidgets('joker-assisted sequence can be played as a meld', (
    tester,
  ) async {
    final joker = HareegCard.joker(deckIndex: 82, jokerIndex: 0);
    final meldCards = [
      HareegCard.standard(
        rank: CardRank.nine,
        suit: CardSuit.spades,
        deckIndex: 82,
      ),
      HareegCard.standard(
        rank: CardRank.ten,
        suit: CardSuit.spades,
        deckIndex: 82,
      ),
      joker,
      HareegCard.standard(
        rank: CardRank.queen,
        suit: CardSuit.spades,
        deckIndex: 82,
      ),
    ];
    final snapshot = _snapshotWithSouthCards(meldCards);
    final matchRepository = _MemoryMatchRepository(saved: snapshot);
    await tester.pumpWidget(_testApp(matchRepository: matchRepository));
    await tester.pump();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    for (final card in meldCards) {
      await tester.tap(find.text(card.label).first);
      await tester.pump();
    }

    expect(find.textContaining('Joker as JS'), findsOneWidget);
    final playMeldButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Play Meld'),
    );
    expect(playMeldButton.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Play Meld'));
    await tester.pumpAndSettle();

    expect(
      matchRepository.saved!.tableMelds[PlayerSeat.south]!.single.cards.map(
        (card) => card.label,
      ),
      ['9S', '10S', 'J(JS)', 'QS'],
    );
    expect(find.textContaining('You: 9S 10S J(JS) QS'), findsOneWidget);
  });

  testWidgets('selected cover cards can be added to a table meld', (
    tester,
  ) async {
    final meldCards = [
      HareegCard.standard(
        rank: CardRank.five,
        suit: CardSuit.clubs,
        deckIndex: 81,
      ),
      HareegCard.standard(
        rank: CardRank.six,
        suit: CardSuit.clubs,
        deckIndex: 81,
      ),
      HareegCard.standard(
        rank: CardRank.seven,
        suit: CardSuit.clubs,
        deckIndex: 81,
      ),
      HareegCard.standard(
        rank: CardRank.eight,
        suit: CardSuit.clubs,
        deckIndex: 81,
      ),
    ];
    final covers = [
      HareegCard.standard(
        rank: CardRank.nine,
        suit: CardSuit.clubs,
        deckIndex: 81,
      ),
      HareegCard.standard(
        rank: CardRank.ten,
        suit: CardSuit.clubs,
        deckIndex: 81,
      ),
    ];
    final snapshot = _snapshotWithSouthCards([...meldCards, ...covers]);
    final matchRepository = _MemoryMatchRepository(saved: snapshot);
    await tester.pumpWidget(_testApp(matchRepository: matchRepository));
    await tester.pump();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    for (final card in meldCards) {
      await tester.tap(find.text(card.label).first);
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Play Meld'));
    await tester.pumpAndSettle();

    for (final card in covers) {
      await tester.tap(find.text(card.label).first);
      await tester.pump();
    }
    final coverButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Place Cover'),
    );
    expect(coverButton.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Place Cover'));
    await tester.pumpAndSettle();

    expect(
      matchRepository.saved!.tableMelds[PlayerSeat.south]!.single.cards.map(
        (card) => card.label,
      ),
      ['5C', '6C', '7C', '8C', '9C', '10C'],
    );
    expect(find.textContaining('You: 5C 6C 7C 8C 9C 10C'), findsOneWidget);
  });

  testWidgets('table fits a compact landscape viewport without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final matchRepository = _MemoryMatchRepository(saved: _snapshot());
    await tester.pumpWidget(_testApp(matchRepository: matchRepository));
    await tester.pump();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Classic Hareeg Table'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Auto-sort'), findsOneWidget);
  });

  testWidgets('selecting a joker disables the discard action', (tester) async {
    // Build a snapshot with a known joker in south's hand so we can assert the
    // UI keeps the Discard button disabled when only a joker is selected.
    final base = _snapshot();
    final southHand = List<HareegCard>.of(base.hands[PlayerSeat.south]!);
    final joker = HareegCard.joker(deckIndex: 0, jokerIndex: 0);
    if (!southHand.any((card) => card.isJoker)) {
      southHand.insert(0, joker);
    }
    final patched = ClassicHareegMatchSnapshot(
      setup: base.setup,
      hands: {...base.hands, PlayerSeat.south: southHand},
      stock: base.stock,
      discardPile: base.discardPile,
      starter: base.starter,
      currentSeat: PlayerSeat.south,
      turnPhase: TurnPhase.action,
      savedAt: base.savedAt,
    );
    final matchRepository = _MemoryMatchRepository(saved: patched);
    await tester.pumpWidget(_testApp(matchRepository: matchRepository));
    await tester.pump();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Joker').first);
    await tester.pump();

    final discardButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Discard'),
    );
    expect(
      discardButton.onPressed,
      isNull,
      reason: 'Discarding a joker must be blocked at the UI level.',
    );
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

Future<void> _pumpCpuTurns(WidgetTester tester) async {
  for (var i = 0; i < 16; i += 1) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  await tester.pumpAndSettle();
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

ClassicHareegMatchSnapshot _snapshotWithSouthCards(List<HareegCard> cards) {
  final base = _snapshot();
  return ClassicHareegMatchSnapshot(
    setup: base.setup,
    hands: {
      ...base.hands,
      PlayerSeat.south: [...cards, ...base.hands[PlayerSeat.south]!],
    },
    stock: base.stock,
    discardPile: base.discardPile,
    starter: base.starter,
    currentSeat: PlayerSeat.south,
    turnPhase: TurnPhase.action,
    savedAt: base.savedAt,
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
