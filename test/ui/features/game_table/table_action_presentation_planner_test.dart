import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/ui/core/audio/table_audio.dart';
import 'package:hareeg_table/ui/core/haptics/table_haptics.dart';
import 'package:hareeg_table/ui/features/game_table/table_action_presentation_planner.dart';

void main() {
  group('ClassicHareegActionPresentationPlanner', () {
    test(
      'human draw action plans stock flight, draw sound, and draw haptic',
      () {
        final plan = ClassicHareegActionPresentationPlanner.forHumanAction(
          ClassicHareegActionIds.drawStock,
        );

        expect(plan.sound, TableSoundEvent.drawStock);
        expect(plan.haptic, TableHapticEvent.drawCard);
        expect(plan.flight?.source, TableActionFlightSource.stockBack);
        expect(plan.flight?.destination, TableActionFlightDestination.seatHand);
        expect(plan.flight?.seat, PlayerSeat.south);
      },
    );

    test('human pending return plans hand-to-discard return cues', () {
      final plan = ClassicHareegActionPresentationPlanner.forHumanAction(
        ClassicHareegActionIds.returnPendingDiscard,
      );

      expect(plan.sound, TableSoundEvent.cardReturn);
      expect(plan.haptic, TableHapticEvent.pendingReturn);
      expect(plan.flight?.source, TableActionFlightSource.pendingDiscard);
      expect(
        plan.flight?.destination,
        TableActionFlightDestination.discardPile,
      );
    });

    test('human discard variants share discard presentation', () {
      const cardId = 'deck-1-nine-clubs';

      for (final prefix in [
        ClassicHareegActionIds.discardPrefix,
        ClassicHareegActionIds.discardBlockedCoverPrefix,
        ClassicHareegActionIds.discardJokerPrefix,
      ]) {
        final plan = ClassicHareegActionPresentationPlanner.forHumanAction(
          '$prefix$cardId',
        );

        expect(plan.sound, TableSoundEvent.discardCard);
        expect(plan.haptic, TableHapticEvent.buttonTap);
        expect(plan.flight?.source, TableActionFlightSource.handCard);
        expect(
          plan.flight?.destination,
          TableActionFlightDestination.discardPile,
        );
        expect(plan.flight?.cardId, cardId);
        expect(plan.flight?.allowFaceDownFallback, isFalse);
      }
    });

    test('human table plays target the resolved meld lane', () {
      const firstCardId = 'deck-2-jack-hearts';
      final coverAction = ClassicHareegActionIds.placeCoverActionId(
        targetSeat: PlayerSeat.east,
        meldIndex: 1,
        cardIds: [firstCardId, 'deck-2-jack-spades'],
      );
      final replacementAction = ClassicHareegActionIds.replaceJokerActionId(
        targetSeat: PlayerSeat.west,
        meldIndex: 2,
        cardId: firstCardId,
      );
      final meldAction = ClassicHareegActionIds.playMeldActionId([
        firstCardId,
        'deck-2-queen-hearts',
        'deck-2-king-hearts',
      ]);

      final cover = ClassicHareegActionPresentationPlanner.forHumanAction(
        coverAction,
      );
      final replacement = ClassicHareegActionPresentationPlanner.forHumanAction(
        replacementAction,
      );
      final meld = ClassicHareegActionPresentationPlanner.forHumanAction(
        meldAction,
      );

      expect(cover.sound, TableSoundEvent.meldPlace);
      expect(cover.flight?.destination, TableActionFlightDestination.tableMeld);
      expect(cover.flight?.cardId, firstCardId);
      expect(cover.flight?.targetSeat, PlayerSeat.east);
      expect(cover.flight?.targetMeldIndex, 1);
      expect(replacement.flight?.targetSeat, PlayerSeat.west);
      expect(replacement.flight?.targetMeldIndex, 2);
      expect(meld.flight?.targetSeat, PlayerSeat.south);
      expect(meld.flight?.targetMeldIndex, 0);
    });

    test('cpu discard uses sound and a face-down fallback without haptics', () {
      const cardId = 'hidden-card';

      final plan = ClassicHareegActionPresentationPlanner.forCpuAction(
        seat: PlayerSeat.north,
        actionId: '${ClassicHareegActionIds.discardPrefix}$cardId',
      );

      expect(plan.sound, TableSoundEvent.discardCard);
      expect(plan.haptic, isNull);
      expect(plan.flight?.seat, PlayerSeat.north);
      expect(plan.flight?.source, TableActionFlightSource.handCard);
      expect(
        plan.flight?.destination,
        TableActionFlightDestination.discardPile,
      );
      expect(plan.flight?.cardId, cardId);
      expect(plan.flight?.allowFaceDownFallback, isTrue);
    });

    test('cpu table plays keep sound but do not request card flights', () {
      final actionId = ClassicHareegActionIds.playMeldActionId(['a', 'b', 'c']);

      final plan = ClassicHareegActionPresentationPlanner.forCpuAction(
        seat: PlayerSeat.east,
        actionId: actionId,
      );

      expect(plan.sound, TableSoundEvent.meldPlace);
      expect(plan.haptic, isNull);
      expect(plan.flight, isNull);
    });

    test('cpu cover flies hand card to the target meld with face-down fallback', () {
      const firstCardId = 'deck-3-seven-hearts';
      final coverAction = ClassicHareegActionIds.placeCoverActionId(
        targetSeat: PlayerSeat.south,
        meldIndex: 2,
        cardIds: [firstCardId],
      );

      final plan = ClassicHareegActionPresentationPlanner.forCpuAction(
        seat: PlayerSeat.west,
        actionId: coverAction,
      );

      expect(plan.sound, TableSoundEvent.meldPlace);
      expect(plan.haptic, isNull);
      expect(plan.flight?.seat, PlayerSeat.west);
      expect(plan.flight?.source, TableActionFlightSource.handCard);
      expect(
        plan.flight?.destination,
        TableActionFlightDestination.tableMeld,
      );
      expect(plan.flight?.cardId, firstCardId);
      expect(plan.flight?.targetSeat, PlayerSeat.south);
      expect(plan.flight?.targetMeldIndex, 2);
      expect(plan.flight?.allowFaceDownFallback, isTrue);
    });

    test('non-visual control actions keep only their matching cues', () {
      final returnTablePlay = ClassicHareegActionIds.returnTablePlayActionId(
        owner: PlayerSeat.south,
        meldIndex: 0,
      );

      final usePending = ClassicHareegActionPresentationPlanner.forHumanAction(
        ClassicHareegActionIds.usePendingDiscard,
      );
      final returnPlay = ClassicHareegActionPresentationPlanner.forHumanAction(
        returnTablePlay,
      );

      expect(usePending.sound, isNull);
      expect(usePending.haptic, TableHapticEvent.buttonTap);
      expect(usePending.flight, isNull);
      expect(returnPlay.sound, TableSoundEvent.cardReturn);
      expect(returnPlay.haptic, TableHapticEvent.buttonTap);
      expect(returnPlay.flight, isNull);
    });
  });
}
