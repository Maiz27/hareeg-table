import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/coaching_insight.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/ui/features/game_table/coach/coach_insight_flow.dart';

CoachingInsight _insight(
  CoachingInsightCategory category, {
  PlayerSeat? subjectSeat,
  int? subjectValue,
  int? openingRequirement,
}) {
  return CoachingInsight(
    category: category,
    priority: category.priority,
    subjectSeat: subjectSeat,
    subjectValue: subjectValue,
    openingRequirement: openingRequirement,
  );
}

void main() {
  group('CoachInsightFlow', () {
    test('per-turn guidance always surfaces', () {
      final flow = CoachInsightFlow();
      final insights = [
        _insight(CoachingInsightCategory.discardSuggestion),
      ];
      for (var turn = 0; turn < 5; turn += 1) {
        final selected = flow.select(
          insights: insights,
          roundNumber: 1,
          turnKey: '1:$turn',
        );
        expect(selected?.category, CoachingInsightCategory.discardSuggestion);
      }
    });

    test('a stage banner shows for one turn, then yields for the round', () {
      final flow = CoachInsightFlow();
      final insights = [
        _insight(CoachingInsightCategory.endgameStockLow, subjectValue: 6),
        _insight(CoachingInsightCategory.discardSuggestion),
      ];

      // Turn 1: the banner wins, and keeps the callout across rebuilds within
      // the same turn.
      for (var build = 0; build < 3; build += 1) {
        final selected = flow.select(
          insights: insights,
          roundNumber: 1,
          turnKey: '1:1',
        );
        expect(selected?.category, CoachingInsightCategory.endgameStockLow);
      }

      // Turn 2 (same round): the banner is spent; the floor shows. The stock
      // count moving (6 → 4) does NOT re-trigger it — same lesson.
      final nextTurn = flow.select(
        insights: [
          _insight(CoachingInsightCategory.endgameStockLow, subjectValue: 4),
          _insight(CoachingInsightCategory.discardSuggestion),
        ],
        roundNumber: 1,
        turnKey: '1:2',
      );
      expect(nextTurn?.category, CoachingInsightCategory.discardSuggestion);

      // New round: the banner teaches once again.
      final newRound = flow.select(
        insights: insights,
        roundNumber: 2,
        turnKey: '2:1',
      );
      expect(newRound?.category, CoachingInsightCategory.endgameStockLow);
    });

    test('a different subject seat is fresh teaching', () {
      final flow = CoachInsightFlow();
      final east = flow.select(
        insights: [
          _insight(
            CoachingInsightCategory.opponentCloseToFinish,
            subjectSeat: PlayerSeat.east,
            subjectValue: 2,
          ),
        ],
        roundNumber: 1,
        turnKey: '1:1',
      );
      expect(east?.subjectSeat, PlayerSeat.east);

      final west = flow.select(
        insights: [
          _insight(
            CoachingInsightCategory.opponentCloseToFinish,
            subjectSeat: PlayerSeat.west,
            subjectValue: 3,
          ),
        ],
        roundNumber: 1,
        turnKey: '1:2',
      );
      expect(west?.subjectSeat, PlayerSeat.west);
    });

    test('every benchmark raise re-alerts', () {
      final flow = CoachInsightFlow();
      final first = flow.select(
        insights: [
          _insight(
            CoachingInsightCategory.benchmarkAlert,
            subjectSeat: PlayerSeat.west,
            openingRequirement: 60,
          ),
        ],
        roundNumber: 1,
        turnKey: '1:1',
      );
      expect(first?.category, CoachingInsightCategory.benchmarkAlert);

      final raised = flow.select(
        insights: [
          _insight(
            CoachingInsightCategory.benchmarkAlert,
            subjectSeat: PlayerSeat.west,
            openingRequirement: 72,
          ),
        ],
        roundNumber: 1,
        turnKey: '1:2',
      );
      expect(raised?.openingRequirement, 72);

      final repeat = flow.select(
        insights: [
          _insight(
            CoachingInsightCategory.benchmarkAlert,
            subjectSeat: PlayerSeat.west,
            openingRequirement: 72,
          ),
        ],
        roundNumber: 1,
        turnKey: '1:3',
      );
      expect(repeat, isNull);
    });

    test('a spent banner lets the next unseen banner through', () {
      final flow = CoachInsightFlow();
      final insights = [
        _insight(
          CoachingInsightCategory.scorePosture,
          subjectSeat: PlayerSeat.south,
          subjectValue: 27,
        ),
        _insight(CoachingInsightCategory.endgameStockLow, subjectValue: 5),
        _insight(CoachingInsightCategory.discardSuggestion),
      ];

      final turn1 = flow.select(
        insights: insights,
        roundNumber: 1,
        turnKey: '1:1',
      );
      expect(turn1?.category, CoachingInsightCategory.scorePosture);

      final turn2 = flow.select(
        insights: insights,
        roundNumber: 1,
        turnKey: '1:2',
      );
      expect(turn2?.category, CoachingInsightCategory.endgameStockLow);

      final turn3 = flow.select(
        insights: insights,
        roundNumber: 1,
        turnKey: '1:3',
      );
      expect(turn3?.category, CoachingInsightCategory.discardSuggestion);
    });

    test('returns null when only spent banners remain', () {
      final flow = CoachInsightFlow();
      final insights = [
        _insight(CoachingInsightCategory.endgameStockLow, subjectValue: 5),
      ];
      expect(
        flow.select(insights: insights, roundNumber: 1, turnKey: '1:1'),
        isNotNull,
      );
      expect(
        flow.select(insights: insights, roundNumber: 1, turnKey: '1:2'),
        isNull,
      );
    });

    test('returns null for an empty list', () {
      final flow = CoachInsightFlow();
      expect(
        flow.select(insights: const [], roundNumber: 1, turnKey: '1:1'),
        isNull,
      );
    });
  });
}
