import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_table_play_planner.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/cover_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

void main() {
  group('ClassicHareegTablePlayPlanner', () {
    test('returns exact selected meld action ids', () {
      final run = [
        _card(CardRank.seven, CardSuit.clubs, 10),
        _card(CardRank.eight, CardSuit.clubs, 10),
        _card(CardRank.nine, CardSuit.clubs, 10),
      ];
      final discard = _card(CardRank.two, CardSuit.spades, 10);
      final planner = _planner(southHand: [...run, discard]);

      final actionId = planner.selectedMeldActionIdFor(
        PlayerSeat.south,
        run.map((card) => card.id).toList(growable: false),
      );

      expect(
        actionId,
        ClassicHareegActionIds.playMeldActionId(run.map((card) => card.id)),
      );
    });

    test('does not plan melds that leave no final discard', () {
      final run = [
        _card(CardRank.seven, CardSuit.clubs, 11),
        _card(CardRank.eight, CardSuit.clubs, 11),
        _card(CardRank.nine, CardSuit.clubs, 11),
      ];
      final planner = _planner(southHand: run);

      expect(
        planner.selectedMeldActionIdFor(
          PlayerSeat.south,
          run.map((card) => card.id).toList(growable: false),
        ),
        isNull,
      );
    });

    test('requires pending discard to be part of selected melds', () {
      final pending = _card(CardRank.seven, CardSuit.clubs, 12);
      final eight = _card(CardRank.eight, CardSuit.clubs, 12);
      final nine = _card(CardRank.nine, CardSuit.clubs, 12);
      final unrelated = _card(CardRank.two, CardSuit.spades, 12);
      final planner = _planner(
        southHand: [pending, eight, nine, unrelated],
        pendingDiscard: pending,
      );

      expect(
        planner.selectedMeldActionIdFor(PlayerSeat.south, [
          eight.id,
          nine.id,
          unrelated.id,
        ]),
        isNull,
      );
      expect(
        planner.selectedMeldActionIdFor(PlayerSeat.south, [
          pending.id,
          eight.id,
          nine.id,
        ]),
        isNotNull,
      );
    });

    test('suggestion cards render in canonical meld order regardless of '
        'selection order', () {
      // A high-ace run selected ace-first (hand display order) must still
      // read 9..A on the suggestion rack.
      final run = [
        _card(CardRank.ace, CardSuit.hearts, 14),
        _card(CardRank.nine, CardSuit.hearts, 14),
        _card(CardRank.ten, CardSuit.hearts, 14),
        _card(CardRank.jack, CardSuit.hearts, 14),
        _card(CardRank.queen, CardSuit.hearts, 14),
        _card(CardRank.king, CardSuit.hearts, 14),
      ];
      final discard = _card(CardRank.two, CardSuit.spades, 14);
      final planner = _planner(southHand: [...run, discard]);

      final suggestions = planner.meldSuggestionsForSelection(
        PlayerSeat.south,
        run.map((card) => card.id).toList(growable: false),
        limit: 1,
      );

      expect(suggestions, hasLength(1));
      expect(
        [
          for (final card in suggestions.single.cards)
            card.effectiveIdentity!.rank,
        ],
        [
          CardRank.nine,
          CardRank.ten,
          CardRank.jack,
          CardRank.queen,
          CardRank.king,
          CardRank.ace,
        ],
        reason: 'the ace belongs at the high end, not where it was tapped',
      );
    });

    test('exposes ambiguous joker representation options', () {
      const joker = HareegCard.joker(deckIndex: 13, jokerIndex: 0);
      final aceHearts = _card(CardRank.ace, CardSuit.hearts, 13);
      final aceSpades = _card(CardRank.ace, CardSuit.spades, 13);
      final planner = _planner(
        southHand: [
          aceHearts,
          aceSpades,
          joker,
          _card(CardRank.two, CardSuit.clubs, 13),
        ],
      );

      final options = planner.jokerRepresentationOptionsFor(PlayerSeat.south, [
        aceHearts.id,
        aceSpades.id,
        joker.id,
      ]);

      expect(options.toSet(), {
        const CardIdentity(rank: CardRank.ace, suit: CardSuit.clubs),
        const CardIdentity(rank: CardRank.ace, suit: CardSuit.diamonds),
      });
    });

    test('exposes two-joker selected meld choices', () {
      const firstJoker = HareegCard.joker(deckIndex: 16, jokerIndex: 0);
      const secondJoker = HareegCard.joker(deckIndex: 16, jokerIndex: 1);
      final twoClubs = _card(CardRank.two, CardSuit.clubs, 16);
      final threeClubs = _card(CardRank.three, CardSuit.clubs, 16);
      final planner = _planner(
        southHand: [
          twoClubs,
          threeClubs,
          firstJoker,
          secondJoker,
          _card(CardRank.king, CardSuit.hearts, 16),
        ],
        openingState: _opened(PlayerSeat.south),
      );
      final selectedIds = [
        twoClubs.id,
        threeClubs.id,
        firstJoker.id,
        secondJoker.id,
      ];

      final choices = planner.jokerMeldChoicesFor(
        PlayerSeat.south,
        selectedIds,
      );
      final actionId = planner.selectedMeldActionIdFor(
        PlayerSeat.south,
        selectedIds,
      );

      expect(choices, hasLength(2));
      expect(
        choices.map((choice) => choice.assignments.length),
        everyElement(2),
      );
      expect(
        choices.map((choice) => choice.actionId),
        everyElement(
          startsWith(ClassicHareegActionIds.playMeldWithJokersPrefix),
        ),
      );
      expect(actionId, choices.first.actionId);
    });

    test('finds cover and joker replacement actions for table targets', () {
      final cover = _card(CardRank.eight, CardSuit.clubs, 14);
      final replacement = _card(CardRank.seven, CardSuit.clubs, 15);
      final representedJoker = const HareegCard.joker(
        deckIndex: 15,
        jokerIndex: 0,
        representedIdentity: CardIdentity(
          rank: CardRank.seven,
          suit: CardSuit.clubs,
        ),
      );
      final planner = _planner(
        southHand: [
          cover,
          replacement,
          _card(CardRank.two, CardSuit.spades, 14),
        ],
        openingState: _opened(PlayerSeat.south),
        tableMelds: {
          PlayerSeat.south: [
            PlacedMeld.fromCards([
              _card(CardRank.five, CardSuit.clubs, 14),
              _card(CardRank.six, CardSuit.clubs, 14),
              _card(CardRank.seven, CardSuit.clubs, 16),
            ]),
          ],
          PlayerSeat.north: [
            PlacedMeld.fromCards([
              _card(CardRank.six, CardSuit.clubs, 15),
              representedJoker,
              _card(CardRank.eight, CardSuit.clubs, 15),
            ]),
          ],
        },
      );

      expect(
        planner.coverActionIdForMeldTarget(
          seat: PlayerSeat.south,
          cardIds: [cover.id],
          targetSeat: PlayerSeat.south,
          meldIndex: 0,
        ),
        ClassicHareegActionIds.placeCoverActionId(
          targetSeat: PlayerSeat.south,
          meldIndex: 0,
          cardIds: [cover.id],
        ),
      );
      expect(
        planner.jokerReplacementActionIdForMeldTarget(
          seat: PlayerSeat.south,
          cardIds: [replacement.id],
          targetSeat: PlayerSeat.north,
          meldIndex: 0,
        ),
        ClassicHareegActionIds.replaceJokerActionId(
          targetSeat: PlayerSeat.north,
          meldIndex: 0,
          cardId: replacement.id,
        ),
      );
    });

    test('targeted joker cover can choose the high sequence end', () {
      const joker = HareegCard.joker(deckIndex: 17, jokerIndex: 0);
      final planner = _planner(
        southHand: [joker, _card(CardRank.two, CardSuit.spades, 17)],
        openingState: _opened(PlayerSeat.south),
        tableMelds: {
          PlayerSeat.east: [
            PlacedMeld.fromCards([
              _card(CardRank.six, CardSuit.clubs, 17),
              _card(CardRank.seven, CardSuit.clubs, 17),
              _card(CardRank.eight, CardSuit.clubs, 17),
            ]),
          ],
        },
      );

      final actionId = planner.coverActionIdForMeldTarget(
        seat: PlayerSeat.south,
        cardIds: [joker.id],
        targetSeat: PlayerSeat.east,
        meldIndex: 0,
        coverPlacement: CoverPlacement.highEnd,
      );
      final target = ClassicHareegActionIds.coverActionTarget(actionId!);

      expect(
        target?.jokerIdentities[joker.id],
        const CardIdentity(rank: CardRank.nine, suit: CardSuit.clubs),
      );
    });

    test('unambiguous single-end cover accepts regardless of hovered end', () {
      // Playtest regression: an 8 of clubs only extends the high end of a
      // 5-6-7 club run, but the pointer hovered the low-end zone. The cover
      // must still be accepted (drop anywhere on an unambiguous cover) instead
      // of being rejected for a placement mismatch.
      final cover = _card(CardRank.eight, CardSuit.clubs, 20);
      final planner = _planner(
        southHand: [cover, _card(CardRank.two, CardSuit.spades, 20)],
        openingState: _opened(PlayerSeat.south),
        tableMelds: {
          PlayerSeat.south: [
            PlacedMeld.fromCards([
              _card(CardRank.five, CardSuit.clubs, 20),
              _card(CardRank.six, CardSuit.clubs, 20),
              _card(CardRank.seven, CardSuit.clubs, 20),
            ]),
          ],
        },
      );

      final actionId = planner.coverActionIdForMeldTarget(
        seat: PlayerSeat.south,
        cardIds: [cover.id],
        targetSeat: PlayerSeat.south,
        meldIndex: 0,
        coverPlacement: CoverPlacement.lowEnd,
      );

      expect(actionId, isNotNull);
    });
  });
}

ClassicHareegTablePlayPlanner _planner({
  required List<HareegCard> southHand,
  HareegCard? pendingDiscard,
  OpeningState? openingState,
  Map<PlayerSeat, List<PlacedMeld>> tableMelds = const {},
}) {
  return ClassicHareegTablePlayPlanner(
    currentSeat: PlayerSeat.south,
    phase: TurnPhase.action,
    pendingDiscard: pendingDiscard,
    hands: {PlayerSeat.south: southHand},
    tableMelds: tableMelds,
    openingState: openingState ?? OpeningState.initial(51),
  );
}

OpeningState _opened(PlayerSeat seat) {
  return ClassicHareegOpeningRules.applyOpening(
    state: OpeningState.initial(51),
    seat: seat,
    melds: [const PlacedMeld(cards: [], valueSnapshot: 51)],
  );
}

HareegCard _card(CardRank rank, CardSuit suit, int deckIndex) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
