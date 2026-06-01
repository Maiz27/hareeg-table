import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

import '../../scenario/classic_hareeg_scenario.dart';

HareegCard _c(CardRank rank, CardSuit suit) => ScenarioCards.card(rank, suit);

void main() {
  // Regression: a round-over snapshot must reflect the true final committed
  // state, not a revert of the winning turn. A card placed and then REPLACED in
  // the same finishing turn (a joker covered onto a meld, swapped out for the
  // real card, then discarded) used to be re-materialised by the stale turn-
  // journal revert in `toSnapshot`, duplicating it across the winner's hand and
  // the discard pile. `_completeRound` now clears the reversible turn journal,
  // so the round-over snapshot is the committed state. (Surfaced by the full-game
  // invariant sweep at seed=3 expert once the cover-posture change shifted the
  // trajectory through this sequence.)
  test('round-over snapshot conserves cards after cover-joker → replace → '
      'finish', () {
    final joker = HareegCard.joker(deckIndex: 90, jokerIndex: 0);
    // A 5-set missing only hearts: the joker covers it unambiguously as the 5 of
    // hearts (the one absent suit), so replacing it with the real 5♥ is offered.
    final fiveHearts = _c(CardRank.five, CardSuit.hearts);
    final sixHearts = _c(CardRank.six, CardSuit.hearts);
    final scenario = ClassicHareegScenario.deal(
      setup: ClassicHareegSetup.defaults().copyWith(
        tableStrictness: TableStrictness.standard,
      ),
      southHand: [joker, fiveHearts, sixHearts],
      tableMelds: {
        PlayerSeat.south: [
          PlacedMeld.fromCards([
            _c(CardRank.five, CardSuit.diamonds),
            _c(CardRank.five, CardSuit.clubs),
            _c(CardRank.five, CardSuit.spades),
          ]),
          PlacedMeld.fromCards([
            _c(CardRank.seven, CardSuit.hearts),
            _c(CardRank.eight, CardSuit.hearts),
            _c(CardRank.nine, CardSuit.hearts),
          ]),
        ],
      },
      currentSeat: PlayerSeat.south,
      turnPhase: TurnPhase.action,
      openingState: ScenarioCards.openedFor(PlayerSeat.south),
    );
    final controller = scenario.controller;

    String legalCoverWith(String cardId) {
      return controller.legalActionIdsFor(PlayerSeat.south).firstWhere((id) {
        final action = ClassicHareegActionIds.describe(id);
        return action.kind == ClassicHareegActionKind.placeCover &&
            id.contains(cardId);
      });
    }

    String legalOfKind(ClassicHareegActionKind kind) {
      return controller.legalActionIdsFor(PlayerSeat.south).firstWhere(
        (id) => ClassicHareegActionIds.describe(id).kind == kind,
      );
    }

    // Cover the diamond run with the joker (representing the 5 of diamonds).
    expect(controller.applyAction(legalCoverWith(joker.id)).isSuccess, isTrue);

    // Swap the real 5 of diamonds in for the joker, freeing the joker to hand.
    expect(
      controller
          .applyAction(legalOfKind(ClassicHareegActionKind.replaceJoker))
          .isSuccess,
      isTrue,
    );

    // Lay the 6 of hearts off onto the heart run, leaving only the joker.
    expect(controller.applyAction(legalCoverWith(sixHearts.id)).isSuccess, isTrue);

    // Discard the joker as the final card to finish the round.
    final discardId = '${ClassicHareegActionIds.discardPrefix}${joker.id}';
    expect(controller.applyAction(discardId).isSuccess, isTrue);

    final snapshot = controller.toSnapshot(savedAt: DateTime.utc(2026, 6, 1));

    // The injected joker is the bug signature: pre-fix the stale turn-journal
    // revert re-materialised it into the winner's hand, so it appeared in BOTH
    // the hand and the discard pile. (Global conservation is covered by the
    // full-game invariant sweep; this fixture injects melds/hand into a normal
    // deal so the stock still mirrors those cards — only the injected joker id
    // is unique enough to assert on here.)
    final jokerOccurrences = [
      for (final hand in snapshot.hands.values)
        for (final card in hand)
          if (card.id == joker.id) 'hand',
      for (final card in snapshot.stock)
        if (card.id == joker.id) 'stock',
      for (final card in snapshot.discardPile)
        if (card.id == joker.id) 'discard',
      for (final melds in snapshot.tableMelds.values)
        for (final meld in melds)
          for (final card in meld.cards)
            if (card.id == joker.id) 'meld',
    ];

    // Exactly once, on the discard pile — never duplicated into a hand.
    expect(jokerOccurrences, ['discard']);
    expect(snapshot.hands[PlayerSeat.south] ?? const <HareegCard>[], isEmpty);
  });
}
