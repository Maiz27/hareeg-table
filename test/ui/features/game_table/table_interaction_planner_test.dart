import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_table_play_planner.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/cover_rules.dart';
import 'package:hareeg_table/ui/features/game_table/table_interaction_planner.dart';

void main() {
  group('ClassicHareegTableInteractionPlanner', () {
    test('locked input blocks hover and drop resolution with one scenario', () {
      final card = _card(CardRank.two, CardSuit.clubs, 1);
      final planner = _planner(
        reader: _FakeTableInteractionActionReader(
          controlActions: ['discard:${card.id}'],
        ),
        handCards: [card],
        inputLocked: true,
      );

      final discard = planner.resolveDiscard(card);
      final table = planner.resolveTableDrop(card);
      final meld = planner.resolveMeldDrop(card, PlayerSeat.east, 0);

      expect(discard.scenario, TableInteractionScenario.locked);
      expect(table.scenario, TableInteractionScenario.locked);
      expect(meld.scenario, TableInteractionScenario.locked);
      expect(planner.canDropCardToDiscard(card), isFalse);
      expect(planner.canDropCardToTable(card), isFalse);
      expect(planner.canDropCardToMeld(card, PlayerSeat.east, 0), isFalse);
    });

    test('inactive seat blocks interaction with the locked scenario', () {
      final card = _card(CardRank.two, CardSuit.hearts, 10);
      final actionId = '${ClassicHareegActionIds.discardPrefix}${card.id}';
      final planner = _planner(
        reader: _FakeTableInteractionActionReader(
          currentSeat: PlayerSeat.east,
          controlActions: [actionId],
        ),
        handCards: [card],
      );

      final result = planner.resolveDiscard(card);

      expect(result.scenario, TableInteractionScenario.locked);
      expect(result.isAction, isFalse);
    });

    test('pending discard drop resolves as return pending discard', () {
      final pending = _card(CardRank.nine, CardSuit.clubs, 2);
      final planner = _planner(
        reader: _FakeTableInteractionActionReader(
          pendingDiscard: pending,
          controlActions: [ClassicHareegActionIds.returnPendingDiscard],
        ),
        handCards: [pending],
      );

      final result = planner.resolveDiscard(pending);

      expect(result.scenario, TableInteractionScenario.returnPendingDiscard);
      expect(result.actionId, ClassicHareegActionIds.returnPendingDiscard);
      expect(planner.canDropCardToDiscard(pending), isTrue);
    });

    test('plain discard action resolves from the control action surface', () {
      final card = _card(CardRank.three, CardSuit.diamonds, 3);
      final actionId = '${ClassicHareegActionIds.discardPrefix}${card.id}';
      final planner = _planner(
        reader: _FakeTableInteractionActionReader(controlActions: [actionId]),
        handCards: [card],
      );

      final result = planner.resolveDiscard(card);

      expect(result.scenario, TableInteractionScenario.discard);
      expect(result.actionId, actionId);
    });

    test(
      'broad table drop priority keeps cover glow distinct from meld glow',
      () {
        final first = _card(CardRank.seven, CardSuit.clubs, 4);
        final second = _card(CardRank.eight, CardSuit.clubs, 4);
        final third = _card(CardRank.nine, CardSuit.clubs, 4);
        final ids = [first.id, second.id, third.id];
        final meldAction = ClassicHareegActionIds.playMeldActionId(ids);
        final coverAction = ClassicHareegActionIds.placeCoverActionId(
          targetSeat: PlayerSeat.east,
          meldIndex: 0,
          cardIds: ids,
        );
        final reader = _FakeTableInteractionActionReader(
          selectedMeldActions: {_key(ids): meldAction},
          coverActions: {_key(ids): coverAction},
        );
        final planner = _planner(
          reader: reader,
          selectedCardIds: ids,
          handCards: [first, second, third],
        );

        final result = planner.resolveTableDrop(second);

        expect(result.scenario, TableInteractionScenario.tableCover);
        expect(result.actionId, coverAction);
        expect(planner.canDropCardToTable(second), isTrue);
        expect(planner.canPlaceNewMeldOnTable(second), isFalse);
      },
    );

    test('broad table drop prefers joker replacement before new meld', () {
      final first = _card(CardRank.king, CardSuit.clubs, 11);
      final second = _card(CardRank.king, CardSuit.hearts, 11);
      final third = _card(CardRank.king, CardSuit.spades, 11);
      final ids = [first.id, second.id, third.id];
      final meldAction = ClassicHareegActionIds.playMeldActionId(ids);
      final replacementAction = ClassicHareegActionIds.replaceJokerActionId(
        targetSeat: PlayerSeat.west,
        meldIndex: 1,
        cardId: first.id,
      );
      final planner = _planner(
        reader: _FakeTableInteractionActionReader(
          selectedMeldActions: {_key(ids): meldAction},
          replacementActions: {_key(ids): replacementAction},
        ),
        selectedCardIds: ids,
        handCards: [first, second, third],
      );

      final result = planner.resolveTableDrop(third);

      expect(result.scenario, TableInteractionScenario.tableJokerReplacement);
      expect(result.actionId, replacementAction);
      expect(planner.canPlaceNewMeldOnTable(third), isFalse);
    });

    test(
      'new meld glow is true only when the broad drop resolves as a meld',
      () {
        final first = _card(CardRank.seven, CardSuit.hearts, 5);
        final second = _card(CardRank.eight, CardSuit.hearts, 5);
        final third = _card(CardRank.nine, CardSuit.hearts, 5);
        final ids = [first.id, second.id, third.id];
        final meldAction = ClassicHareegActionIds.playMeldActionId(ids);
        final planner = _planner(
          reader: _FakeTableInteractionActionReader(
            selectedMeldActions: {_key(ids): meldAction},
          ),
          selectedCardIds: ids,
          handCards: [first, second, third],
        );

        final result = planner.resolveTableDrop(first);

        expect(result.scenario, TableInteractionScenario.tableMeld);
        expect(result.actionId, meldAction);
        expect(planner.canPlaceNewMeldOnTable(first), isTrue);
      },
    );

    test('selected group is tried before dragged single card', () {
      final first = _card(CardRank.five, CardSuit.spades, 6);
      final second = _card(CardRank.six, CardSuit.spades, 6);
      final third = _card(CardRank.seven, CardSuit.spades, 6);
      final ids = [first.id, second.id, third.id];
      final groupAction = ClassicHareegActionIds.playMeldActionId(ids);
      final planner = _planner(
        reader: _FakeTableInteractionActionReader(
          selectedMeldActions: {_key(ids): groupAction},
        ),
        selectedCardIds: ids,
        handCards: [first, second, third],
      );

      final result = planner.resolveTableDrop(second);

      expect(result.scenario, TableInteractionScenario.tableMeld);
      expect(result.actionId, groupAction);
    });

    test('table drops without the pending discard stay legal (relaxed)', () {
      // Relaxed taken-discard rule: a meld that does not include the pending
      // card is a legal play; only ending the turn is gated on its use.
      final pending = _card(CardRank.queen, CardSuit.clubs, 7);
      final first = _card(CardRank.five, CardSuit.hearts, 7);
      final second = _card(CardRank.six, CardSuit.hearts, 7);
      final third = _card(CardRank.seven, CardSuit.hearts, 7);
      final ids = [first.id, second.id, third.id];
      final meldAction = ClassicHareegActionIds.playMeldActionId(ids);
      final planner = _planner(
        reader: _FakeTableInteractionActionReader(
          pendingDiscard: pending,
          selectedMeldActions: {_key(ids): meldAction},
        ),
        selectedCardIds: ids,
        handCards: [pending, first, second, third],
      );

      final result = planner.resolveTableDrop(first);

      expect(result.scenario, TableInteractionScenario.tableMeld);
      expect(result.actionId, meldAction);
      expect(planner.canDropCardToTable(first), isTrue);
    });

    test('specific meld drops prioritize cover before joker replacement', () {
      final card = _card(CardRank.eight, CardSuit.clubs, 8);
      final coverAction = ClassicHareegActionIds.placeCoverActionId(
        targetSeat: PlayerSeat.east,
        meldIndex: 0,
        cardIds: [card.id],
      );
      final replacementAction = ClassicHareegActionIds.replaceJokerActionId(
        targetSeat: PlayerSeat.east,
        meldIndex: 0,
        cardId: card.id,
      );
      final planner = _planner(
        reader: _FakeTableInteractionActionReader(
          targetCoverActions: {
            _targetKey(PlayerSeat.east, 0, [card.id]): coverAction,
          },
          targetReplacementActions: {
            _targetKey(PlayerSeat.east, 0, [card.id]): replacementAction,
          },
        ),
        handCards: [card],
      );

      final result = planner.resolveMeldDrop(card, PlayerSeat.east, 0);

      expect(result.scenario, TableInteractionScenario.specificMeldCover);
      expect(result.actionId, coverAction);
    });

    test('specific meld drop can resolve as joker replacement', () {
      final card = _card(CardRank.ace, CardSuit.diamonds, 9);
      final replacementAction = ClassicHareegActionIds.replaceJokerActionId(
        targetSeat: PlayerSeat.west,
        meldIndex: 2,
        cardId: card.id,
      );
      final planner = _planner(
        reader: _FakeTableInteractionActionReader(
          targetReplacementActions: {
            _targetKey(PlayerSeat.west, 2, [card.id]): replacementAction,
          },
        ),
        handCards: [card],
      );

      final result = planner.resolveMeldDrop(card, PlayerSeat.west, 2);

      expect(
        result.scenario,
        TableInteractionScenario.specificMeldJokerReplacement,
      );
      expect(result.actionId, replacementAction);
    });

    test('action gate filters every table offer shape', () {
      final first = _card(CardRank.four, CardSuit.clubs, 12);
      final second = _card(CardRank.five, CardSuit.clubs, 12);
      final third = _card(CardRank.six, CardSuit.clubs, 12);
      final ids = [first.id, second.id, third.id];
      final discardAction =
          '${ClassicHareegActionIds.discardPrefix}${first.id}';
      final meldAction = ClassicHareegActionIds.playMeldActionId(ids);
      final coverAction = ClassicHareegActionIds.placeCoverActionId(
        targetSeat: PlayerSeat.east,
        meldIndex: 0,
        cardIds: ids,
      );
      final replacementAction = ClassicHareegActionIds.replaceJokerActionId(
        targetSeat: PlayerSeat.west,
        meldIndex: 1,
        cardId: first.id,
      );
      final targetCoverAction = ClassicHareegActionIds.placeCoverActionId(
        targetSeat: PlayerSeat.north,
        meldIndex: 2,
        cardIds: [first.id],
      );
      final jokerChoiceA = JokerMeldActionChoice(
        jokerId: third.id,
        identity: const CardIdentity(rank: CardRank.six, suit: CardSuit.clubs),
        cardIds: ids,
      );
      final jokerChoiceB = JokerMeldActionChoice(
        jokerId: third.id,
        identity: const CardIdentity(
          rank: CardRank.seven,
          suit: CardSuit.clubs,
        ),
        cardIds: ids,
      );
      final blocked = {
        discardAction,
        meldAction,
        coverAction,
        replacementAction,
        targetCoverAction,
        jokerChoiceA.actionId,
        jokerChoiceB.actionId,
      };
      final planner = _planner(
        reader: _FakeTableInteractionActionReader(
          controlActions: [discardAction],
          selectedMeldActions: {_key(ids): meldAction},
          coverActions: {_key(ids): coverAction},
          replacementActions: {_key(ids): replacementAction},
          targetCoverActions: {
            _targetKey(PlayerSeat.north, 2, [first.id]): targetCoverAction,
          },
          meldSuggestions: [
            ClassicHareegMeldSuggestion(
              actionId: meldAction,
              cards: [first, second, third],
            ),
          ],
          jokerChoices: [jokerChoiceA, jokerChoiceB],
        ),
        selectedCardIds: ids,
        handCards: [first, second, third],
        actionGate: PredicateTableInteractionActionGate(
          (actionId) => !blocked.contains(actionId),
        ),
      );

      expect(planner.resolveDiscard(first).isAction, isFalse);
      expect(planner.selectedMeldActionId(), isNull);
      expect(planner.resolveTableDrop(second).isAction, isFalse);
      expect(
        planner.resolveMeldDrop(first, PlayerSeat.north, 2).isAction,
        isFalse,
      );
      expect(planner.meldSuggestions(), isEmpty);
      expect(planner.jokerChoicesForCardIds(ids), isEmpty);
    });
  });
}

ClassicHareegTableInteractionPlanner _planner({
  required _FakeTableInteractionActionReader reader,
  Iterable<String> selectedCardIds = const [],
  Iterable<HareegCard> handCards = const [],
  bool inputLocked = false,
  TableInteractionActionGate actionGate =
      const AllowAllTableInteractionActionGate(),
}) {
  return ClassicHareegTableInteractionPlanner(
    reader: reader,
    seat: PlayerSeat.south,
    selectedCardIds: selectedCardIds,
    handCards: handCards,
    inputLocked: inputLocked,
    actionGate: actionGate,
  );
}

HareegCard _card(CardRank rank, CardSuit suit, int deckIndex) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}

String _key(Iterable<String> cardIds) => cardIds.join('|');

String _targetKey(PlayerSeat owner, int meldIndex, Iterable<String> cardIds) {
  return '${owner.name}:$meldIndex:${_key(cardIds)}';
}

class _FakeTableInteractionActionReader
    implements TableInteractionActionReader {
  const _FakeTableInteractionActionReader({
    this.currentSeat = PlayerSeat.south,
    this.pendingDiscard,
    this.controlActions = const [],
    this.selectedMeldActions = const {},
    this.coverActions = const {},
    this.replacementActions = const {},
    this.targetCoverActions = const {},
    this.targetReplacementActions = const {},
    this.meldSuggestions = const [],
    this.jokerChoices = const [],
  });

  @override
  final PlayerSeat currentSeat;

  @override
  final HareegCard? pendingDiscard;

  final List<String> controlActions;
  final Map<String, String> selectedMeldActions;
  final Map<String, String> coverActions;
  final Map<String, String> replacementActions;
  final Map<String, String> targetCoverActions;
  final Map<String, String> targetReplacementActions;
  final List<ClassicHareegMeldSuggestion> meldSuggestions;
  final List<JokerMeldActionChoice> jokerChoices;

  @override
  List<String> controlActionIdsFor(PlayerSeat seat) => controlActions;

  @override
  String? selectedMeldActionIdFor(PlayerSeat seat, List<String> cardIds) {
    return selectedMeldActions[_key(cardIds)];
  }

  @override
  List<CardIdentity> jokerRepresentationOptionsFor(
    PlayerSeat seat,
    List<String> cardIds,
  ) {
    return const [];
  }

  @override
  List<JokerMeldActionChoice> jokerMeldChoicesFor(
    PlayerSeat seat,
    List<String> cardIds,
  ) {
    return jokerChoices;
  }

  @override
  List<ClassicHareegMeldSuggestion> meldSuggestionsForSelection(
    PlayerSeat seat,
    List<String> selectedCardIds, {
    int limit = 5,
  }) {
    return meldSuggestions;
  }

  @override
  String? coverActionIdFor(PlayerSeat seat, List<String> cardIds) {
    return coverActions[_key(cardIds)];
  }

  @override
  String? coverActionIdForMeldTarget({
    required PlayerSeat seat,
    required List<String> cardIds,
    required PlayerSeat targetSeat,
    required int meldIndex,
    CoverPlacement? coverPlacement,
  }) {
    return targetCoverActions[_targetKey(targetSeat, meldIndex, cardIds)];
  }

  @override
  String? jokerReplacementActionIdFor(PlayerSeat seat, List<String> cardIds) {
    return replacementActions[_key(cardIds)];
  }

  @override
  String? jokerReplacementActionIdForMeldTarget({
    required PlayerSeat seat,
    required List<String> cardIds,
    required PlayerSeat targetSeat,
    required int meldIndex,
  }) {
    return targetReplacementActions[_targetKey(targetSeat, meldIndex, cardIds)];
  }
}
