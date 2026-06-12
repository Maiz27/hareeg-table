import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/coaching_insight.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/ui/features/game_table/coach/coach_insight_flow.dart';

CoachingInsight _insight(
  CoachingInsightCategory category, {
  PlayerSeat? subjectSeat,
  bool subjectIsSelf = false,
  int? subjectValue,
  int? openingRequirement,
  List<String> highlightCardIds = const [],
}) {
  return CoachingInsight(
    category: category,
    priority: category.priority,
    subjectSeat: subjectSeat,
    subjectIsSelf: subjectIsSelf,
    subjectValue: subjectValue,
    openingRequirement: openingRequirement,
    highlightCardIds: highlightCardIds,
  );
}

void main() {
  group('CoachInsightFlow', () {
    test('the primary slot always carries the actionable guidance', () {
      // Playtest regression: a stage banner must NEVER occupy the primary
      // slot — the player was left with "the bar was raised" and no idea how
      // to progress the turn.
      final flow = CoachInsightFlow();
      final insights = [
        _insight(
          CoachingInsightCategory.benchmarkAlert,
          subjectSeat: PlayerSeat.west,
          openingRequirement: 60,
        ),
        _insight(CoachingInsightCategory.drawStock),
      ];
      final selection = flow.select(
        insights: insights,
        roundNumber: 1,
        turnKey: '1:1',
      );
      expect(selection.primary?.category, CoachingInsightCategory.drawStock);
      expect(
        selection.stageNote?.category,
        CoachingInsightCategory.benchmarkAlert,
      );
    });

    test('each distinct bait card re-teaches; the same bait stays taught', () {
      // A bait is a live trap on the pile, not round-long posture: deduping
      // by category alone went silent on the round's SECOND bait card. The
      // per-card qualifier re-alerts for a new bait while the same card
      // (still topping the pile turns later) stays taught.
      final flow = CoachInsightFlow();
      CoachSelection selectBait(String cardId, String turnKey) => flow.select(
        insights: [
          _insight(
            CoachingInsightCategory.baitDiscard,
            highlightCardIds: [cardId],
          ),
          _insight(CoachingInsightCategory.drawStock),
        ],
        roundNumber: 1,
        turnKey: turnKey,
      );

      expect(
        selectBait('bait-a', '1:1').stageNote?.category,
        CoachingInsightCategory.baitDiscard,
      );
      // Same bait, later turn: already taught.
      expect(selectBait('bait-a', '1:3').stageNote, isNull);
      // A different bait card is a new trap: teach again.
      expect(
        selectBait('bait-b', '1:5').stageNote?.category,
        CoachingInsightCategory.baitDiscard,
      );
    });

    test('per-turn guidance always surfaces, banners never block it', () {
      final flow = CoachInsightFlow();
      final insights = [
        _insight(CoachingInsightCategory.endgameStockLow, subjectValue: 6),
        _insight(CoachingInsightCategory.discardSuggestion),
      ];
      for (var turn = 0; turn < 5; turn += 1) {
        final selection = flow.select(
          insights: insights,
          roundNumber: 1,
          turnKey: '1:$turn',
        );
        expect(
          selection.primary?.category,
          CoachingInsightCategory.discardSuggestion,
        );
      }
    });

    test('a stage note shows for one turn, then yields for the round', () {
      final flow = CoachInsightFlow();
      final insights = [
        _insight(CoachingInsightCategory.endgameStockLow, subjectValue: 6),
        _insight(CoachingInsightCategory.discardSuggestion),
      ];

      // Turn 1: the note rides along, and stays across rebuilds within the
      // same turn.
      for (var build = 0; build < 3; build += 1) {
        final selection = flow.select(
          insights: insights,
          roundNumber: 1,
          turnKey: '1:1',
        );
        expect(
          selection.stageNote?.category,
          CoachingInsightCategory.endgameStockLow,
        );
      }

      // Turn 2 (same round): the note is spent. The stock count moving
      // (6 → 4) does NOT re-trigger it — same lesson.
      final nextTurn = flow.select(
        insights: [
          _insight(CoachingInsightCategory.endgameStockLow, subjectValue: 4),
          _insight(CoachingInsightCategory.discardSuggestion),
        ],
        roundNumber: 1,
        turnKey: '1:2',
      );
      expect(nextTurn.stageNote, isNull);
      expect(
        nextTurn.primary?.category,
        CoachingInsightCategory.discardSuggestion,
      );

      // New round: the note teaches once again.
      final newRound = flow.select(
        insights: insights,
        roundNumber: 2,
        turnKey: '2:1',
      );
      expect(
        newRound.stageNote?.category,
        CoachingInsightCategory.endgameStockLow,
      );
    });

    test('scorePosture self vs target are distinct teachings at one seat', () {
      // Key hygiene: the self and target scorePosture variants teach
      // materially different lessons. Self is fixed to south today so the seat
      // token differs anyway, but the stage key must carry the self/target
      // dimension itself — otherwise the second of the two at the same seat
      // would be wrongly deduped as already-taught.
      final flow = CoachInsightFlow();
      final selfNote = flow.select(
        insights: [
          _insight(
            CoachingInsightCategory.scorePosture,
            subjectSeat: PlayerSeat.south,
            subjectIsSelf: true,
            subjectValue: 27,
          ),
        ],
        roundNumber: 1,
        turnKey: '1:1',
      );
      expect(
        selfNote.stageNote?.category,
        CoachingInsightCategory.scorePosture,
      );

      // A target posture at the SAME seat token in a later turn is a different
      // lesson and must still surface (not deduped against the self note).
      final targetNote = flow.select(
        insights: [
          _insight(
            CoachingInsightCategory.scorePosture,
            subjectSeat: PlayerSeat.south,
            subjectValue: 29,
          ),
        ],
        roundNumber: 1,
        turnKey: '1:2',
      );
      expect(
        targetNote.stageNote?.category,
        CoachingInsightCategory.scorePosture,
      );
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
      expect(east.stageNote?.subjectSeat, PlayerSeat.east);

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
      expect(west.stageNote?.subjectSeat, PlayerSeat.west);
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
      expect(
        first.stageNote?.category,
        CoachingInsightCategory.benchmarkAlert,
      );

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
      expect(raised.stageNote?.openingRequirement, 72);

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
      expect(repeat.stageNote, isNull);
    });

    test('a spent note lets the next unseen note through', () {
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
      expect(turn1.stageNote?.category, CoachingInsightCategory.scorePosture);
      expect(
        turn1.primary?.category,
        CoachingInsightCategory.discardSuggestion,
      );

      final turn2 = flow.select(
        insights: insights,
        roundNumber: 1,
        turnKey: '1:2',
      );
      expect(
        turn2.stageNote?.category,
        CoachingInsightCategory.endgameStockLow,
      );

      final turn3 = flow.select(
        insights: insights,
        roundNumber: 1,
        turnKey: '1:3',
      );
      expect(turn3.stageNote, isNull);
      expect(
        turn3.primary?.category,
        CoachingInsightCategory.discardSuggestion,
      );
    });

    test('banners alone leave the primary slot empty (caller may promote)',
        () {
      final flow = CoachInsightFlow();
      final insights = [
        _insight(CoachingInsightCategory.endgameStockLow, subjectValue: 5),
      ];
      final first = flow.select(
        insights: insights,
        roundNumber: 1,
        turnKey: '1:1',
      );
      expect(first.primary, isNull);
      expect(
        first.stageNote?.category,
        CoachingInsightCategory.endgameStockLow,
      );

      final second = flow.select(
        insights: insights,
        roundNumber: 1,
        turnKey: '1:2',
      );
      expect(second.primary, isNull);
      expect(second.stageNote, isNull);
    });

    test('empty list selects nothing', () {
      final flow = CoachInsightFlow();
      final selection = flow.select(
        insights: const [],
        roundNumber: 1,
        turnKey: '1:1',
      );
      expect(selection.primary, isNull);
      expect(selection.stageNote, isNull);
    });
  });
}
