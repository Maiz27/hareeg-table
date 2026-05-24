import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';

import 'classic_hareeg_scenario.dart';

/// Regression for the take/return infinite loop guard.
///
/// Before the fix, a seat that took the previous discard and then returned
/// it would immediately see `take-discard` re-advertised on their next
/// action surface, because the discard pile top was the same card and the
/// natural rules said "you are still next anti-clockwise of the previous
/// discarder". A CPU planner could re-take the card forever until the
/// safety cap fired.
///
/// The fix in `_canTakePreviousDiscard` consults a new
/// `_lastReturnedPendingDiscard` guard:
///
/// ```dart
/// final lastReturned = _lastReturnedPendingDiscard;
/// if (lastReturned != null &&
///     lastReturned.seat == _currentSeat &&
///     _discardPile.isNotEmpty &&
///     _discardPile.last.id == lastReturned.cardId) {
///   return false;
/// }
/// ```
///
/// The guard is cleared the moment the discard pile top changes (any new
/// discard, or any mistake-driven pending-discard relocation), so the only
/// effect is breaking the self-loop.
void main() {
  group('Take-return loop guard (non-table strictness)', () {
    test(
      'after take then return, the same seat must not see take-discard '
      'advertised while the pile top is unchanged',
      () {
        // Mid-round state: east just discarded a 7H, north is in draw phase
        // and is the immediate next seat after east. North has a hand that
        // contains the 7H in their candidate range so taking it is at least
        // legal under the surface planner.
        final discarded = ScenarioCards.card(
          CardRank.seven,
          CardSuit.hearts,
          deckIndex: 200,
        );

        final northHand = [
          ScenarioCards.card(CardRank.six, CardSuit.hearts, deckIndex: 200),
          ScenarioCards.card(CardRank.eight, CardSuit.hearts, deckIndex: 200),
          ScenarioCards.card(CardRank.king, CardSuit.spades, deckIndex: 200),
          ScenarioCards.card(CardRank.two, CardSuit.diamonds, deckIndex: 200),
          ScenarioCards.card(CardRank.three, CardSuit.diamonds, deckIndex: 200),
          ScenarioCards.card(CardRank.four, CardSuit.diamonds, deckIndex: 200),
        ];

        final scenario = ClassicHareegScenario.deal(
          setup: ClassicHareegSetup.defaults().copyWith(
            tableStrictness: TableStrictness.standard,
          ),
          seed: 11,
          northHand: northHand,
          // Top of pile is 7H, contributed by east.
          discardPile: [discarded],
          currentSeat: PlayerSeat.north,
          turnPhase: TurnPhase.draw,
        );

        // Sanity: take-discard is initially advertised — that's the whole
        // reason the loop would have triggered.
        expect(
          scenario.north.legalActionIds,
          contains(ClassicHareegActionIds.takeDiscard),
          reason:
              'preconditions: take-discard MUST be advertised before the '
              'take/return loop is exercised',
        );

        // North takes the discard.
        final taken = scenario.north.takeDiscard();
        expect(taken.isSuccess, isTrue, reason: 'take-discard must succeed');
        expect(scenario.controller.pendingDiscard?.id, discarded.id);

        // North returns it.
        final returned = scenario.north.returnPendingDiscard();
        expect(
          returned.isSuccess,
          isTrue,
          reason: 'return-pending-discard must succeed',
        );

        // After the return, north is still the current seat (draw phase),
        // the same 7H is back on top of the discard pile, and the previous
        // discarder is still east — so without the guard the planner would
        // re-advertise take-discard right here, producing an infinite loop.
        expect(
          scenario.controller.currentSeat,
          PlayerSeat.north,
          reason: 'return keeps north in draw phase',
        );
        expect(
          scenario.controller.topDiscard?.id,
          discarded.id,
          reason: 'pile top is the returned card (unchanged)',
        );

        // Core invariant: take-discard MUST NOT be advertised right now —
        // the _lastReturnedPendingDiscard guard suppresses it. The only
        // legal draw-phase action left is drawing from stock.
        expect(
          scenario.north.legalActionIds,
          isNot(contains(ClassicHareegActionIds.takeDiscard)),
          reason:
              'BUG: take-discard MUST be suppressed for the seat that just '
              'returned the pending discard while the pile top is unchanged',
        );
        expect(
          scenario.north.legalActionIds,
          contains(ClassicHareegActionIds.drawStock),
          reason: 'drawing from stock remains the legal exit from draw phase',
        );
      },
    );

    test(
      'guard clears once the pile top changes — a subsequent re-take is '
      'legal again',
      () {
        // Same setup as above, but after north returns and draws from
        // stock, the next discard by north pushes a new card onto the
        // pile. East then takes/returns and the guard should be evaluated
        // freshly for east — never carrying over north's old return.
        final discarded = ScenarioCards.card(
          CardRank.seven,
          CardSuit.hearts,
          deckIndex: 201,
        );

        final scenario = ClassicHareegScenario.deal(
          setup: ClassicHareegSetup.defaults().copyWith(
            tableStrictness: TableStrictness.standard,
          ),
          seed: 11,
          northHand: [
            ScenarioCards.card(CardRank.six, CardSuit.hearts, deckIndex: 201),
            ScenarioCards.card(
              CardRank.eight,
              CardSuit.hearts,
              deckIndex: 201,
            ),
            ScenarioCards.card(CardRank.king, CardSuit.spades, deckIndex: 201),
            ScenarioCards.card(CardRank.two, CardSuit.diamonds, deckIndex: 201),
          ],
          discardPile: [discarded],
          currentSeat: PlayerSeat.north,
          turnPhase: TurnPhase.draw,
        );

        scenario.north.takeDiscard();
        final returned = scenario.north.returnPendingDiscard();
        expect(returned.isSuccess, isTrue);
        expect(
          scenario.north.legalActionIds,
          isNot(contains(ClassicHareegActionIds.takeDiscard)),
          reason: 'guard active immediately after return',
        );

        // North draws from stock, then discards one of their hand cards.
        // That discard pushes a new card on top, clearing the guard.
        expect(scenario.north.drawStock().isSuccess, isTrue);
        final toDiscard = scenario.controller
            .handFor(PlayerSeat.north)
            .firstWhere((c) => !c.isJoker);
        final discard = scenario.north.discard(toDiscard);
        expect(discard.isSuccess, isTrue);

        // It is now west's turn (north -> west anti-clockwise) in draw
        // phase. West is the immediate next seat after north's discard and
        // should be free to take-discard — the guard does not bleed into
        // a different seat.
        expect(scenario.controller.currentSeat, PlayerSeat.west);
        expect(scenario.controller.topDiscard?.id, toDiscard.id);
        expect(
          scenario.west.legalActionIds,
          contains(ClassicHareegActionIds.takeDiscard),
          reason:
              'a different seat facing a new pile top must be free to take '
              'the discard',
        );
      },
    );
  });
}
