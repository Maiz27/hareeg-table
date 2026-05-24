import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_table_play_retraction_planner.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_turn_ledger.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

void main() {
  group('ClassicHareegTablePlayRetractionPlanner', () {
    test('staged opening melds can be returned in hard table mode', () {
      final tenSet = meld([
        card(CardRank.ten, CardSuit.clubs),
        card(CardRank.ten, CardSuit.diamonds),
        card(CardRank.ten, CardSuit.hearts),
      ]);

      final plan = ClassicHareegTablePlayRetractionPlanner.evaluateAll(
        seat: PlayerSeat.south,
        currentSeat: PlayerSeat.south,
        phase: TurnPhase.action,
        strictness: TableStrictness.table,
        openingState: OpeningState.initial(51),
        ledger: ledger(openingMelds: [tenSet]),
      );

      expect(
        plan.scenario,
        ClassicHareegTablePlayRetractionScenario.allOpeningMelds,
      );
      expect(plan.isAllowed, isTrue);
      expect(plan.shouldAdvertise, isTrue);
      expect(plan.openingMelds, [tenSet]);
      expect(plan.message, 'Opening melds returned to your hand.');
    });

    test('hard table blocks current-turn meld and cover retraction', () {
      final turnMeld = meld([
        card(CardRank.five, CardSuit.clubs),
        card(CardRank.six, CardSuit.clubs),
        card(CardRank.seven, CardSuit.clubs),
      ]);
      final original = meld([
        card(CardRank.three, CardSuit.hearts),
        card(CardRank.four, CardSuit.hearts),
        card(CardRank.five, CardSuit.hearts),
      ]);
      final cover = card(CardRank.six, CardSuit.hearts);
      final coverPlay = ClassicHareegTurnCoverPlay(
        targetSeat: PlayerSeat.east,
        meldIndex: 0,
        previousMeld: original,
        coverMeld: PlacedMeld(cards: [cover], valueSnapshot: 6),
        previousOpeningState: opened(PlayerSeat.south),
      );

      final bulkMeldPlan = ClassicHareegTablePlayRetractionPlanner.evaluateAll(
        seat: PlayerSeat.south,
        currentSeat: PlayerSeat.south,
        phase: TurnPhase.action,
        strictness: TableStrictness.table,
        openingState: opened(PlayerSeat.south),
        ledger: ledger(
          meldPlays: [
            ClassicHareegTurnMeldPlay(owner: PlayerSeat.south, meld: turnMeld),
          ],
        ),
      );
      final targetCoverPlan =
          ClassicHareegTablePlayRetractionPlanner.evaluateTarget(
            seat: PlayerSeat.south,
            currentSeat: PlayerSeat.south,
            phase: TurnPhase.action,
            strictness: TableStrictness.table,
            openingState: opened(PlayerSeat.south),
            ledger: ledger(coverPlays: [coverPlay]),
            tableMelds: {
              PlayerSeat.east: [
                original.addCoverCards([cover]),
              ],
            },
            target: const ReturnTablePlayTarget(
              owner: PlayerSeat.east,
              meldIndex: 0,
            ),
          );

      expect(
        bulkMeldPlan.scenario,
        ClassicHareegTablePlayRetractionScenario.blockedByStrictness,
      );
      expect(bulkMeldPlan.isAllowed, isFalse);
      expect(bulkMeldPlan.shouldAdvertise, isFalse);
      expect(
        targetCoverPlan.scenario,
        ClassicHareegTablePlayRetractionScenario.blockedByStrictness,
      );
      expect(targetCoverPlan.isAllowed, isFalse);
      expect(
        targetCoverPlan.message,
        contains('does not allow taking back'),
      );
    });

    test('bulk plan distinguishes mixed current-turn table plays', () {
      final turnMeld = meld([
        card(CardRank.five, CardSuit.clubs),
        card(CardRank.six, CardSuit.clubs),
        card(CardRank.seven, CardSuit.clubs),
      ]);
      final original = meld([
        card(CardRank.three, CardSuit.hearts),
        card(CardRank.four, CardSuit.hearts),
        card(CardRank.five, CardSuit.hearts),
      ]);
      final cover = card(CardRank.six, CardSuit.hearts);

      final plan = ClassicHareegTablePlayRetractionPlanner.evaluateAll(
        seat: PlayerSeat.south,
        currentSeat: PlayerSeat.south,
        phase: TurnPhase.action,
        strictness: TableStrictness.strict,
        openingState: opened(PlayerSeat.south),
        ledger: ledger(
          meldPlays: [
            ClassicHareegTurnMeldPlay(owner: PlayerSeat.south, meld: turnMeld),
          ],
          coverPlays: [
            ClassicHareegTurnCoverPlay(
              targetSeat: PlayerSeat.east,
              meldIndex: 0,
              previousMeld: original,
              coverMeld: PlacedMeld(cards: [cover], valueSnapshot: 6),
              previousOpeningState: opened(PlayerSeat.south),
            ),
          ],
        ),
      );

      expect(
        plan.scenario,
        ClassicHareegTablePlayRetractionScenario.allMixedTablePlays,
      );
      expect(plan.isAllowed, isTrue);
      expect(plan.meldPlays, hasLength(1));
      expect(plan.coverPlays, hasLength(1));
      expect(plan.message, 'Table plays returned to your hand.');
    });

    test('specific cover stack takes priority for a target', () {
      final original = meld([
        card(CardRank.three, CardSuit.clubs),
        card(CardRank.four, CardSuit.clubs),
        card(CardRank.five, CardSuit.clubs),
      ]);
      final firstCover = card(CardRank.six, CardSuit.clubs);
      final secondCover = card(CardRank.seven, CardSuit.clubs);
      final onceCovered = original.addCoverCards([firstCover]);
      final twiceCovered = onceCovered.addCoverCards([secondCover]);

      final plan = ClassicHareegTablePlayRetractionPlanner.evaluateTarget(
        seat: PlayerSeat.south,
        currentSeat: PlayerSeat.south,
        phase: TurnPhase.action,
        strictness: TableStrictness.coaching,
        openingState: opened(PlayerSeat.south),
        ledger: ledger(
          coverPlays: [
            ClassicHareegTurnCoverPlay(
              targetSeat: PlayerSeat.east,
              meldIndex: 0,
              previousMeld: original,
              coverMeld: PlacedMeld(cards: [firstCover], valueSnapshot: 6),
              previousOpeningState: opened(PlayerSeat.south),
            ),
            ClassicHareegTurnCoverPlay(
              targetSeat: PlayerSeat.east,
              meldIndex: 0,
              previousMeld: onceCovered,
              coverMeld: PlacedMeld(cards: [secondCover], valueSnapshot: 7),
              previousOpeningState: opened(PlayerSeat.south),
            ),
          ],
        ),
        tableMelds: {
          PlayerSeat.east: [twiceCovered],
        },
        target: const ReturnTablePlayTarget(
          owner: PlayerSeat.east,
          meldIndex: 0,
        ),
      );

      expect(
        plan.scenario,
        ClassicHareegTablePlayRetractionScenario.specificCoverStack,
      );
      expect(plan.isAllowed, isTrue);
      expect(plan.coverPlays, hasLength(2));
      expect(plan.message, 'Covers returned to your hand.');
    });

    test('specific turn meld matches physical table cards', () {
      final turnMeld = meld([
        card(CardRank.five, CardSuit.diamonds),
        card(CardRank.six, CardSuit.diamonds),
        card(CardRank.seven, CardSuit.diamonds),
      ]);

      final plan = ClassicHareegTablePlayRetractionPlanner.evaluateTarget(
        seat: PlayerSeat.south,
        currentSeat: PlayerSeat.south,
        phase: TurnPhase.action,
        strictness: TableStrictness.coaching,
        openingState: opened(PlayerSeat.south),
        ledger: ledger(
          meldPlays: [
            ClassicHareegTurnMeldPlay(owner: PlayerSeat.south, meld: turnMeld),
          ],
        ),
        tableMelds: {
          PlayerSeat.south: [turnMeld],
        },
        target: const ReturnTablePlayTarget(
          owner: PlayerSeat.south,
          meldIndex: 0,
        ),
      );

      expect(
        plan.scenario,
        ClassicHareegTablePlayRetractionScenario.specificTurnMeld,
      );
      expect(plan.isAllowed, isTrue);
      expect(plan.meldPlays.single.meld, turnMeld);
    });

    test('specific staged opening meld reports staged index', () {
      final tenSet = meld([
        card(CardRank.ten, CardSuit.clubs),
        card(CardRank.ten, CardSuit.diamonds),
        card(CardRank.ten, CardSuit.hearts),
      ]);
      final nineSet = meld([
        card(CardRank.nine, CardSuit.clubs),
        card(CardRank.nine, CardSuit.diamonds),
        card(CardRank.nine, CardSuit.hearts),
      ]);

      final plan = ClassicHareegTablePlayRetractionPlanner.evaluateTarget(
        seat: PlayerSeat.south,
        currentSeat: PlayerSeat.south,
        phase: TurnPhase.action,
        strictness: TableStrictness.table,
        openingState: OpeningState.initial(51),
        ledger: ledger(openingMelds: [tenSet, nineSet]),
        tableMelds: {
          PlayerSeat.south: [tenSet, nineSet],
        },
        target: const ReturnTablePlayTarget(
          owner: PlayerSeat.south,
          meldIndex: 1,
        ),
      );

      expect(
        plan.scenario,
        ClassicHareegTablePlayRetractionScenario.specificOpeningMeld,
      );
      expect(plan.isAllowed, isTrue);
      expect(plan.stagedOpeningIndex, 1);
      expect(plan.openingMelds.single, nineSet);
    });

    test('missing target is reported before any mutation can be attempted', () {
      final plan = ClassicHareegTablePlayRetractionPlanner.evaluateTarget(
        seat: PlayerSeat.south,
        currentSeat: PlayerSeat.south,
        phase: TurnPhase.action,
        strictness: TableStrictness.coaching,
        openingState: opened(PlayerSeat.south),
        ledger: ledger(),
        tableMelds: const {},
        target: const ReturnTablePlayTarget(
          owner: PlayerSeat.east,
          meldIndex: 0,
        ),
      );

      expect(
        plan.scenario,
        ClassicHareegTablePlayRetractionScenario.targetMissing,
      );
      expect(plan.isAllowed, isFalse);
      expect(plan.shouldAdvertise, isFalse);
      expect(plan.message, 'That meld is no longer on table.');
    });
  });
}

ClassicHareegTurnLedger ledger({
  List<PlacedMeld> openingMelds = const [],
  List<ClassicHareegTurnMeldPlay> meldPlays = const [],
  List<ClassicHareegTurnCoverPlay> coverPlays = const [],
}) {
  return ClassicHareegTurnLedger(
    openingMelds: openingMelds,
    meldPlays: meldPlays,
    coverPlays: coverPlays,
  );
}

OpeningState opened(PlayerSeat seat) {
  return OpeningState(
    baseRequirement: 51,
    currentRequirement: 51,
    openedSeats: {seat},
  );
}

PlacedMeld meld(List<HareegCard> cards) {
  return PlacedMeld.fromCards(cards);
}

HareegCard card(CardRank rank, CardSuit suit, [int deckIndex = 800]) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
