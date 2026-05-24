import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';

import 'classic_hareeg_scenario.dart';

/// Regression for the Table-tier "cover orphan" bug.
///
/// Before the fix, when a removed seat discarded a card that was actually an
/// illegal cover, [`ClassicHareegGameController._applyDiscard`][] charged the
/// +17 penalty and removed the seat from the round but failed to move the
/// offending card onto the discard pile. The card stayed orphaned in the
/// removed seat's hand and the discard pile top was stale.
///
/// The fix path in `_applyDiscard` is:
///
/// ```dart
/// final removal = _applyMistake(_mistakeConsequencePlan(mistake));
/// if (removal != null) {
///   hand.removeAt(index);   // card leaves the removed seat's hand
///   _discardPile.add(card); // and lands on top of the discard pile
///   _discardHistory.recordDiscard(discardingSeat, card);
///   _previousDiscardSeat = discardingSeat;
///   return removal;
/// }
/// ```
void main() {
  group('Cover orphan regression (Table strictness)', () {
    test(
      'illegal cover discard removes south AND lands on discard pile, '
      'not orphaned in the removed seat hand',
      () {
        // South is already opened and holds the 5C-6C-7C run + the 8C
        // cover candidate + filler so the offending discard is not the
        // final discard. Discarding 8C while it could cover the run is an
        // illegal cover discard.
        final meldCards = [
          ScenarioCards.card(CardRank.five, CardSuit.clubs, deckIndex: 80),
          ScenarioCards.card(CardRank.six, CardSuit.clubs, deckIndex: 80),
          ScenarioCards.card(CardRank.seven, CardSuit.clubs, deckIndex: 80),
        ];
        final cover = ScenarioCards.card(
          CardRank.eight,
          CardSuit.clubs,
          deckIndex: 80,
        );
        final filler = [
          ScenarioCards.card(
            CardRank.queen,
            CardSuit.diamonds,
            deckIndex: 80,
          ),
          ScenarioCards.card(CardRank.king, CardSuit.spades, deckIndex: 80),
        ];

        final scenario = ClassicHareegScenario.deal(
          setup: ClassicHareegSetup.defaults().copyWith(
            tableStrictness: TableStrictness.table,
          ),
          seed: 11,
          southHand: [...meldCards, cover, ...filler],
          openingState: ScenarioCards.openedFor(PlayerSeat.south),
        );

        // South plays the run so the cover candidate is recognised. The DSL
        // returns the raw ApplyActionResult so the assertion stays close to
        // the narrative.
        final played = scenario.south.playMeld(meldCards);
        expect(
          played.isSuccess,
          isTrue,
          reason: 'preconditions: meld must place to land the cover threat',
        );

        final handSizeBeforeDiscard = scenario.south.hand.length;
        final scoreBefore = scenario.controller.scores[PlayerSeat.south] ?? 0;

        final discardResult = scenario.south.discardBlockedCover(cover);

        // The mistake-discard MUST succeed (Table tier accepts the mistake
        // with a +17 penalty).
        expect(
          discardResult.isSuccess,
          isTrue,
          reason:
              'Table tier: cover discard is accepted as a penalised mistake',
        );

        // South is removed from the round...
        expect(
          scenario.controller.removedSeats,
          contains(PlayerSeat.south),
          reason: 'Table tier removes the offender from the round',
        );

        // ...and the +17 penalty was applied.
        expect(
          scenario.controller.scores[PlayerSeat.south],
          scoreBefore + 17,
          reason: 'Table tier: removed seat charged the +17 penalty',
        );

        // Core invariant of this regression: the cover card landed on the
        // discard pile. Before the fix, the discard pile top was still the
        // pre-discard top and the cover stayed in the removed seat's hand.
        expect(
          scenario.controller.topDiscard?.id,
          cover.id,
          reason:
              'Cover card MUST land on top of the discard pile, not be '
              'orphaned in the removed seat hand',
        );

        // And the symmetric assertion: the cover is no longer in south's
        // hand and the hand shrank by exactly one.
        final southHandIds = scenario.controller
            .handFor(PlayerSeat.south)
            .map((c) => c.id);
        expect(
          southHandIds,
          isNot(contains(cover.id)),
          reason: 'Cover card MUST NOT remain in the removed seat hand',
        );
        expect(
          scenario.controller.handFor(PlayerSeat.south),
          hasLength(handSizeBeforeDiscard - 1),
          reason: 'Removed seat hand must shrink by one (the discarded cover)',
        );
      },
    );
  });
}
