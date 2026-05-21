import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';
import 'package:hareeg_table/ui/features/game_table/table_interaction_adapter.dart';

void main() {
  group('ClassicHareegTableInteractionAdapter', () {
    test('resolves a pending discard drop as return-pending-discard', () {
      final pending = _card(CardRank.nine, CardSuit.clubs, 91);
      final controller = _controller(
        southHand: [
          pending,
          _card(CardRank.three, CardSuit.hearts, 91),
          _card(CardRank.four, CardSuit.hearts, 91),
          _card(CardRank.five, CardSuit.hearts, 91),
        ],
        discardPile: [_card(CardRank.ace, CardSuit.spades, 91)],
        pendingDiscard: pending,
      );
      final adapter = _controllerAdapter(controller);

      final result = adapter.resolveDiscard(pending);

      expect(result.actionId, ClassicHareegActionIds.returnPendingDiscard);
      expect(adapter.canDropCardToDiscard(pending), isTrue);
    });

    test('uses selected cards as a group before the dragged single card', () {
      final first = _card(CardRank.seven, CardSuit.clubs, 41);
      final second = _card(CardRank.eight, CardSuit.clubs, 41);
      final third = _card(CardRank.nine, CardSuit.clubs, 41);
      final groupAction = ClassicHareegActionIds.playMeldActionId([
        first.id,
        second.id,
        third.id,
      ]);
      final reader = _FakeTableInteractionActionReader(
        selectedMeldActions: {
          _key([first.id, second.id, third.id]): groupAction,
        },
      );
      final adapter = ClassicHareegTableInteractionAdapter(
        reader: reader,
        seat: PlayerSeat.south,
        selectedCardIds: [first.id, second.id, third.id],
        handCards: [first, second, third],
      );

      final result = adapter.resolveTableDrop(second);

      expect(result.actionId, groupAction);
    });

    test('meld suggestions are limited to selected cards', () {
      final diamondRun = [
        _card(CardRank.eight, CardSuit.diamonds, 80),
        _card(CardRank.nine, CardSuit.diamonds, 80),
        _card(CardRank.ten, CardSuit.diamonds, 80),
      ];
      final jackSet = [
        _card(CardRank.jack, CardSuit.diamonds, 80),
        _card(CardRank.jack, CardSuit.hearts, 80),
        _card(CardRank.jack, CardSuit.clubs, 80),
      ];
      final controller = _controller(
        southHand: [
          ...diamondRun,
          ...jackSet,
          _card(CardRank.two, CardSuit.clubs, 80),
        ],
      );
      final selectedAction = ClassicHareegActionIds.playMeldActionId(
        diamondRun.map((card) => card.id),
      );
      final bundledAction = ClassicHareegActionIds.playMeldActionId(
        [...diamondRun, ...jackSet].map((card) => card.id),
      );

      final suggestions = _controllerAdapter(
        controller,
        selectedCardIds: diamondRun.map((card) => card.id),
      ).meldSuggestions();

      expect(suggestions.map((suggestion) => suggestion.actionId), [
        selectedAction,
      ]);
      expect(
        suggestions.map((suggestion) => suggestion.actionId),
        isNot(contains(bundledAction)),
      );
    });

    test('joker choices preview the represented card identities', () {
      const joker = HareegCard.joker(deckIndex: 83, jokerIndex: 0);
      final aceHearts = _card(CardRank.ace, CardSuit.hearts, 83);
      final aceSpades = _card(CardRank.ace, CardSuit.spades, 83);
      final controller = _controller(
        southHand: [
          aceHearts,
          aceSpades,
          joker,
          _card(CardRank.four, CardSuit.clubs, 83),
        ],
        openingState: _opened(PlayerSeat.south),
      );
      final cardIds = [aceHearts.id, aceSpades.id, joker.id];

      final choices = _controllerAdapter(
        controller,
        selectedCardIds: cardIds,
      ).jokerChoicesForCardIds(cardIds);

      expect(choices.map((choice) => choice.identity).toSet(), {
        const CardIdentity(rank: CardRank.ace, suit: CardSuit.clubs),
        const CardIdentity(rank: CardRank.ace, suit: CardSuit.diamonds),
      });
      expect(
        choices.every(
          (choice) => choice.cards.any(
            (card) =>
                card.id == joker.id &&
                card.representedIdentity == choice.identity,
          ),
        ),
        isTrue,
      );
    });

    test('joker meld suggestions preview distinct ordered melds', () {
      const joker = HareegCard.joker(deckIndex: 84, jokerIndex: 0);
      final jackClubs = _card(CardRank.jack, CardSuit.clubs, 84);
      final tenClubs = _card(CardRank.ten, CardSuit.clubs, 84);
      final controller = _controller(
        southHand: [
          jackClubs,
          tenClubs,
          joker,
          _card(CardRank.four, CardSuit.clubs, 84),
        ],
        openingState: _opened(PlayerSeat.south),
      );

      final suggestions = _controllerAdapter(
        controller,
        selectedCardIds: [jackClubs.id, tenClubs.id, joker.id],
      ).meldSuggestions();

      expect(suggestions, hasLength(2));
      expect(suggestions.map((suggestion) => _identityKeys(suggestion.cards)), [
        'nine-clubs|ten-clubs|jack-clubs',
        'ten-clubs|jack-clubs|queen-clubs',
      ]);
      expect(suggestions.map((suggestion) => suggestion.actionId).toSet(), {
        ClassicHareegActionIds.playMeldWithJokerIdentityActionId(
          cardIds: [jackClubs.id, tenClubs.id, joker.id],
          jokerId: joker.id,
          identity: const CardIdentity(
            rank: CardRank.nine,
            suit: CardSuit.clubs,
          ),
        ),
        ClassicHareegActionIds.playMeldWithJokerIdentityActionId(
          cardIds: [jackClubs.id, tenClubs.id, joker.id],
          jokerId: joker.id,
          identity: const CardIdentity(
            rank: CardRank.queen,
            suit: CardSuit.clubs,
          ),
        ),
      });
    });

    test('two-joker meld suggestions preview both represented jokers', () {
      const firstJoker = HareegCard.joker(deckIndex: 85, jokerIndex: 0);
      const secondJoker = HareegCard.joker(deckIndex: 85, jokerIndex: 1);
      final twoClubs = _card(CardRank.two, CardSuit.clubs, 85);
      final threeClubs = _card(CardRank.three, CardSuit.clubs, 85);
      final controller = _controller(
        southHand: [
          twoClubs,
          threeClubs,
          firstJoker,
          secondJoker,
          _card(CardRank.king, CardSuit.hearts, 85),
        ],
        openingState: _opened(PlayerSeat.south),
      );

      final suggestions = _controllerAdapter(
        controller,
        selectedCardIds: [
          twoClubs.id,
          threeClubs.id,
          firstJoker.id,
          secondJoker.id,
        ],
      ).meldSuggestions();

      expect(suggestions, isNotEmpty);
      expect(
        suggestions
            .take(2)
            .map((suggestion) => _identityKeys(suggestion.cards)),
        [
          'ace-clubs|two-clubs|three-clubs|four-clubs',
          'two-clubs|three-clubs|four-clubs|five-clubs',
        ],
      );
      expect(
        suggestions.take(2).map((suggestion) {
          return suggestion.cards.where((card) => card.isJoker).length;
        }),
        everyElement(2),
      );
      expect(
        suggestions.take(2).map((suggestion) => suggestion.actionId),
        everyElement(
          startsWith(ClassicHareegActionIds.playMeldWithJokersPrefix),
        ),
      );
    });

    test('blocked table drops carry the table-drop explanation', () {
      final card = _card(CardRank.two, CardSuit.clubs, 80);
      final controller = _controller(southHand: [card]);

      final result = _controllerAdapter(controller).resolveTableDrop(card);

      expect(result.isAction, isFalse);
      expect(
        result.failureMessage,
        'Drop a valid meld, cover, or joker replacement.',
      );
    });
  });
}

ClassicHareegGameController _controller({
  List<HareegCard>? southHand,
  List<HareegCard>? discardPile,
  HareegCard? pendingDiscard,
  OpeningState? openingState,
}) {
  return ClassicHareegGameController.fromSnapshot(
    _savedSnapshot(
      southHand: southHand,
      discardPile: discardPile,
      pendingDiscard: pendingDiscard,
      openingState: openingState,
    ),
  );
}

ClassicHareegTableInteractionAdapter _controllerAdapter(
  ClassicHareegGameController controller, {
  Iterable<String> selectedCardIds = const [],
}) {
  return ClassicHareegTableInteractionAdapter(
    reader: ClassicHareegControllerTableInteractionReader(controller),
    seat: PlayerSeat.south,
    selectedCardIds: selectedCardIds,
    handCards: controller.handFor(PlayerSeat.south),
  );
}

ClassicHareegMatchSnapshot _savedSnapshot({
  List<HareegCard>? southHand,
  List<HareegCard>? discardPile,
  HareegCard? pendingDiscard,
  OpeningState? openingState,
}) {
  final setup = ClassicHareegSetup.defaults();
  final round = ClassicHareegRound.deal(setup: setup, seed: 3);
  final hands = southHand == null
      ? round.hands
      : {...round.hands, PlayerSeat.south: southHand};
  return ClassicHareegMatchSnapshot(
    setup: setup,
    hands: hands,
    stock: round.stock,
    discardPile: discardPile ?? round.discardPile,
    starter: round.starter,
    currentSeat: PlayerSeat.south,
    turnPhase: TurnPhase.action,
    pendingDiscard: pendingDiscard,
    openingState: openingState,
    savedAt: DateTime.utc(2026, 5, 21),
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

String _key(Iterable<String> cardIds) => cardIds.join('|');

String _identityKeys(List<HareegCard> cards) {
  return cards.map((card) => card.effectiveIdentity!.key).join('|');
}

class _FakeTableInteractionActionReader
    implements TableInteractionActionReader {
  const _FakeTableInteractionActionReader({
    this.selectedMeldActions = const {},
  });

  @override
  PlayerSeat get currentSeat => PlayerSeat.south;

  @override
  HareegCard? get pendingDiscard => null;

  final Map<String, String> selectedMeldActions;

  @override
  List<String> controlActionIdsFor(PlayerSeat seat) => const [];

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
    return const [];
  }

  @override
  String? coverActionIdFor(PlayerSeat seat, List<String> cardIds) => null;

  @override
  String? coverActionIdForMeldTarget({
    required PlayerSeat seat,
    required List<String> cardIds,
    required PlayerSeat targetSeat,
    required int meldIndex,
  }) {
    return null;
  }

  @override
  String? jokerReplacementActionIdFor(PlayerSeat seat, List<String> cardIds) {
    return null;
  }

  @override
  String? jokerReplacementActionIdForMeldTarget({
    required PlayerSeat seat,
    required List<String> cardIds,
    required PlayerSeat targetSeat,
    required int meldIndex,
  }) {
    return null;
  }
}
