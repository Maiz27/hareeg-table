import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';
import 'package:hareeg_table/ui/features/round_summary/views/round_summary_screen.dart';

void main() {
  testWidgets(
    'normal summary shows winner, score deltas, and continue action',
    (tester) async {
      await tester.pumpWidget(
        app(result: normalResult, progress: progressFor(normalResult)),
      );

      expect(find.text('You finished'), findsOneWidget);
      // The new lounge summary splits "before -> after" and the signed delta
      // into separate Text widgets for a calmer scoreboard.
      expect(find.text('0 -> -1'), findsOneWidget);
      expect(find.text('-1'), findsWidgets);
      expect(find.text('Continue next round'), findsOneWidget);
    },
  );

  testWidgets(
    'Fifty summary explains discarder penalty and first-round exception',
    (tester) async {
      final result = const RoundProgressResult(
        type: RoundOutcomeType.fiftyFinish,
        winner: PlayerSeat.east,
        fiftyDiscarder: PlayerSeat.south,
        firstRoundFiftyException: true,
        remainingCardCounts: {
          PlayerSeat.south: 11,
          PlayerSeat.east: 0,
          PlayerSeat.north: 6,
          PlayerSeat.west: 8,
        },
      );

      await tester.pumpWidget(
        app(result: result, progress: progressFor(result)),
      );

      expect(find.text('CPU East hit Fifty'), findsOneWidget);
      expect(
        find.textContaining('First-round Fifty exception'),
        findsOneWidget,
      );
      expect(find.text('0 -> 14'), findsOneWidget);
      expect(find.text('+14'), findsOneWidget);
    },
  );

  testWidgets('drawn summary shows no score changes and same starter message', (
    tester,
  ) async {
    final result = const RoundProgressResult(
      type: RoundOutcomeType.draw,
      remainingCardCounts: {},
    );

    await tester.pumpWidget(
      app(
        result: result,
        progress: ClassicHareegMatchProgressionRules.applyRoundResult(
          scores: baseScores,
          activeSeats: activeSeats,
          currentStarter: PlayerSeat.north,
          result: result,
        ),
      ),
    );

    expect(find.text('Round drawn'), findsOneWidget);
    expect(find.textContaining('No score changes'), findsOneWidget);
    // The lounge summary breaks "Next starter" onto its own line so the
    // seat label can stand on its own typography.
    expect(find.text('Next starter'), findsOneWidget);
    expect(find.text('CPU North'), findsWidgets);
  });

  testWidgets('match end shows eliminated players and return action', (
    tester,
  ) async {
    final result = const RoundProgressResult(
      type: RoundOutcomeType.normalFinish,
      winner: PlayerSeat.east,
      remainingCardCounts: {
        PlayerSeat.south: 2,
        PlayerSeat.east: 0,
        PlayerSeat.north: 2,
        PlayerSeat.west: 2,
      },
    );
    final previous = {
      PlayerSeat.south: 30,
      PlayerSeat.east: 2,
      PlayerSeat.north: 30,
      PlayerSeat.west: 30,
    };
    final progress = ClassicHareegMatchProgressionRules.applyRoundResult(
      scores: previous,
      activeSeats: activeSeats,
      currentStarter: PlayerSeat.south,
      result: result,
    );

    await tester.pumpWidget(
      app(result: result, progress: progress, previousScores: previous),
    );

    expect(find.text('Eliminated'), findsNWidgets(3));
    expect(find.text('Match winner'), findsOneWidget);
    expect(find.text('CPU East'), findsWidgets);
    // The new summary list scrolls; bring the action button on-screen before
    // asserting it is present.
    await tester.scrollUntilVisible(
      find.text('Return to menu'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Return to menu'), findsOneWidget);
  });
}

const activeSeats = [
  PlayerSeat.south,
  PlayerSeat.east,
  PlayerSeat.north,
  PlayerSeat.west,
];

const baseScores = {
  PlayerSeat.south: 0,
  PlayerSeat.east: 0,
  PlayerSeat.north: 0,
  PlayerSeat.west: 0,
};

const normalResult = RoundProgressResult(
  type: RoundOutcomeType.normalFinish,
  winner: PlayerSeat.south,
  remainingCardCounts: {
    PlayerSeat.south: 0,
    PlayerSeat.east: 5,
    PlayerSeat.north: 9,
    PlayerSeat.west: 14,
  },
);

Widget app({
  required RoundProgressResult result,
  required MatchProgressState progress,
  Map<PlayerSeat, int> previousScores = baseScores,
}) {
  return MaterialApp(
    home: RoundSummaryScreen(
      result: result,
      progress: progress,
      previousScores: previousScores,
      onContinue: () {},
      onReturnToMenu: () {},
    ),
  );
}

MatchProgressState progressFor(RoundProgressResult result) {
  return ClassicHareegMatchProgressionRules.applyRoundResult(
    scores: baseScores,
    activeSeats: activeSeats,
    currentStarter: PlayerSeat.south,
    result: result,
  );
}
