import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_session.dart';
import 'package:hareeg_table/ui/features/learning/practice/table_strictness_practice_pack.dart';

import '../../../support/practice_lesson_harness.dart';

void main() {
  // The shared trapped-cover board both demos run on: south holds the 10♥ that
  // completes west's scripted tens.
  final tenHearts = practiceCard(CardRank.ten, CardSuit.hearts);

  String blockedCoverId(HareegCard card) =>
      '${ClassicHareegActionIds.discardBlockedCoverPrefix}${card.id}';

  group('strict-penalty lesson', () {
    test('the throw eats +3, reverts, and completes the lesson', () {
      final session = PracticeSession(
        script: TableStrictnessPracticePack.strictPenalty(),
      );
      runPracticeIntro(session);

      // Draw to start the turn.
      final draw = session.submit(ClassicHareegActionIds.drawStock);
      expect(draw.status, PracticeSubmitStatus.stepCompleted);

      final scoreBefore = session.controller.scores[PlayerSeat.south] ?? 0;
      final handBefore = session.controller.cardCountFor(PlayerSeat.south);

      // Throwing the trapped ten is the taught move: Strict charges +3 and
      // reverts the card, and that penalty completes the lesson.
      final penalty = session.submit(blockedCoverId(tenHearts));
      expect(penalty.status, PracticeSubmitStatus.lessonCompleted);
      expect(
        session.controller.scores[PlayerSeat.south],
        scoreBefore + 3,
        reason: 'Strict charges +3 for the cover throw',
      );
      expect(
        session.controller.cardCountFor(PlayerSeat.south),
        handBefore,
        reason: 'the reverted ten stays in hand',
      );
      expect(
        session.controller.handFor(PlayerSeat.south).map((c) => c.id),
        contains(tenHearts.id),
        reason: 'the card came back but the points stuck',
      );
      // Strict keeps south in the round (only Table removes the seat).
      expect(
        session.controller.removedSeats,
        isNot(contains(PlayerSeat.south)),
      );
    });
  });

  group('table-penalty lesson', () {
    test('the throw lands for +17 and removes the seat from the round', () {
      final session = PracticeSession(
        script: TableStrictnessPracticePack.tablePenalty(),
      );
      runPracticeIntro(session);

      final draw = session.submit(ClassicHareegActionIds.drawStock);
      expect(draw.status, PracticeSubmitStatus.stepCompleted);

      final scoreBefore = session.controller.scores[PlayerSeat.south] ?? 0;

      // On Table the throw goes through: +17, the ten leaves the hand, south is
      // removed from the round, and the lesson completes the instant that
      // round-out lands.
      final out = session.submit(blockedCoverId(tenHearts));
      expect(out.status, PracticeSubmitStatus.lessonCompleted);
      expect(
        session.controller.scores[PlayerSeat.south],
        scoreBefore + 17,
        reason: 'Table charges +17 for the cover throw',
      );
      expect(
        session.controller.removedSeats,
        contains(PlayerSeat.south),
        reason: 'Table removes the offender from the round',
      );
      expect(session.controller.topDiscard?.id, tenHearts.id);
    });
  });
}
