import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';

import 'classic_hareeg_scenario.dart';

/// Picking a card up while a Fifty window is open.
///
/// A normal pickup is `take-discard` — the non-committal action a player uses to
/// meld/open. Even while the Fifty window is live it must stay penalty-free:
/// returning the unused taken card never costs points or removes the player.
/// (Claiming Fifty is a separate, deliberate action behind its own control;
/// only that path commits the player to proving the finish.)
void main() {
  final clock = DateTime.utc(2026, 1, 1, 12, 0, 0);
  DateTime now() => clock;

  HareegCard c(CardRank r, CardSuit s, {int d = 0}) =>
      ScenarioCards.card(r, s, deckIndex: d);

  test('take-discard during the window then return carries no penalty', () {
    // South can't finish on the king of spades. They take the windowed discard
    // intending to open, find the meld invalid, and return it. On Table tier
    // this must not penalise or remove them — a pickup is not a Fifty claim.
    final southHand = <HareegCard>[
      c(CardRank.four, CardSuit.hearts, d: 3),
      c(CardRank.seven, CardSuit.clubs, d: 3),
      c(CardRank.nine, CardSuit.diamonds, d: 3),
      c(CardRank.jack, CardSuit.spades, d: 3),
      c(CardRank.queen, CardSuit.hearts, d: 3),
    ];
    final ctrl = ClassicHareegScenario.deal(
      setup: ClassicHareegSetup.defaults().copyWith(
        tableStrictness: TableStrictness.table,
      ),
      southHand: southHand,
      discardPile: [c(CardRank.king, CardSuit.spades, d: 3)],
      currentSeat: PlayerSeat.south,
      turnPhase: TurnPhase.draw,
      openingState: ScenarioCards.openedFor(PlayerSeat.south),
      scores: const {PlayerSeat.south: 0},
      roundNumber: 2,
      fiftyWindowOpenedAt: clock,
      now: now,
    ).controller;

    expect(ctrl.fiftyClaimant, PlayerSeat.south);

    final take = ctrl.applyAction(ClassicHareegActionIds.takeDiscard);
    expect(take.isSuccess, isTrue);
    final ret = ctrl.applyAction(ClassicHareegActionIds.returnPendingDiscard);
    expect(ret.isSuccess, isTrue, reason: ret.message);
    expect(ret.wasReverted, isFalse);
    expect(ctrl.scores[PlayerSeat.south] ?? 0, 0, reason: 'pickup is no penalty');
    expect(ctrl.removedSeats, isEmpty);
  });
}
