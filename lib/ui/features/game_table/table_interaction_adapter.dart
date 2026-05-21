import '../../../domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import '../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../domain/classic_hareeg/rules/opening_rules.dart';

/// Read-only action lookup needed by the table interaction adapter.
abstract interface class TableInteractionActionReader {
  /// Seat whose turn is currently active.
  PlayerSeat get currentSeat;

  /// Pending discard awaiting use-or-return, if any.
  HareegCard? get pendingDiscard;

  /// Control actions legal for [seat].
  List<String> controlActionIdsFor(PlayerSeat seat);

  /// Exact selected-meld action for [cardIds], if legal.
  String? selectedMeldActionIdFor(PlayerSeat seat, List<String> cardIds);

  /// Explicit represented-card options for an ambiguous joker meld.
  List<CardIdentity> jokerRepresentationOptionsFor(
    PlayerSeat seat,
    List<String> cardIds,
  );

  /// Explicit represented-joker choices for selected meld cards.
  List<JokerMeldActionChoice> jokerMeldChoicesFor(
    PlayerSeat seat,
    List<String> cardIds,
  );

  /// First legal cover action for [cardIds], if any.
  String? coverActionIdFor(PlayerSeat seat, List<String> cardIds);

  /// Legal cover action for a specific target meld, if any.
  String? coverActionIdForMeldTarget({
    required PlayerSeat seat,
    required List<String> cardIds,
    required PlayerSeat targetSeat,
    required int meldIndex,
  });

  /// First legal represented-joker replacement action for [cardIds], if any.
  String? jokerReplacementActionIdFor(PlayerSeat seat, List<String> cardIds);

  /// Legal represented-joker replacement action for a specific target meld.
  String? jokerReplacementActionIdForMeldTarget({
    required PlayerSeat seat,
    required List<String> cardIds,
    required PlayerSeat targetSeat,
    required int meldIndex,
  });
}

/// Adapter from a live controller to the table interaction action reader.
class ClassicHareegControllerTableInteractionReader
    implements TableInteractionActionReader {
  /// Creates a reader backed by [controller].
  const ClassicHareegControllerTableInteractionReader(this.controller);

  /// Live game controller.
  final ClassicHareegGameController controller;

  @override
  PlayerSeat get currentSeat => controller.currentSeat;

  @override
  HareegCard? get pendingDiscard => controller.pendingDiscard;

  @override
  List<String> controlActionIdsFor(PlayerSeat seat) {
    return controller.controlActionIdsFor(seat);
  }

  @override
  String? selectedMeldActionIdFor(PlayerSeat seat, List<String> cardIds) {
    return controller.selectedMeldActionIdFor(seat, cardIds);
  }

  @override
  List<CardIdentity> jokerRepresentationOptionsFor(
    PlayerSeat seat,
    List<String> cardIds,
  ) {
    return controller.jokerRepresentationOptionsFor(seat, cardIds);
  }

  @override
  List<JokerMeldActionChoice> jokerMeldChoicesFor(
    PlayerSeat seat,
    List<String> cardIds,
  ) {
    return controller.jokerMeldChoicesFor(seat, cardIds);
  }

  @override
  String? coverActionIdFor(PlayerSeat seat, List<String> cardIds) {
    return controller.coverActionIdFor(seat, cardIds);
  }

  @override
  String? coverActionIdForMeldTarget({
    required PlayerSeat seat,
    required List<String> cardIds,
    required PlayerSeat targetSeat,
    required int meldIndex,
  }) {
    return controller.coverActionIdForMeldTarget(
      seat: seat,
      cardIds: cardIds,
      targetSeat: targetSeat,
      meldIndex: meldIndex,
    );
  }

  @override
  String? jokerReplacementActionIdFor(PlayerSeat seat, List<String> cardIds) {
    return controller.jokerReplacementActionIdFor(seat, cardIds);
  }

  @override
  String? jokerReplacementActionIdForMeldTarget({
    required PlayerSeat seat,
    required List<String> cardIds,
    required PlayerSeat targetSeat,
    required int meldIndex,
  }) {
    return controller.jokerReplacementActionIdForMeldTarget(
      seat: seat,
      cardIds: cardIds,
      targetSeat: targetSeat,
      meldIndex: meldIndex,
    );
  }
}

/// Result of resolving one table interaction.
class TableInteractionResolution {
  const TableInteractionResolution._({this.actionId, this.failureMessage});

  /// Legal interaction that should apply [actionId].
  const TableInteractionResolution.action(String actionId)
    : this._(actionId: actionId);

  /// Blocked interaction with a player-facing [failureMessage].
  const TableInteractionResolution.blocked(String failureMessage)
    : this._(failureMessage: failureMessage);

  /// Legal action id, when one was resolved.
  final String? actionId;

  /// Player-facing explanation when no action was resolved.
  final String? failureMessage;

  /// Whether the interaction can be applied.
  bool get isAction => actionId != null;
}

/// Meld suggestion resolved from selected hand cards.
class TableInteractionMeldSuggestion {
  /// Creates a table interaction meld suggestion.
  const TableInteractionMeldSuggestion({
    required this.actionId,
    required this.cards,
  });

  /// Legal controller action id for this suggestion.
  final String actionId;

  /// Cards to show for the suggestion.
  final List<HareegCard> cards;
}

/// Explicit represented-joker choice for a selected meld.
class TableInteractionJokerChoice {
  /// Creates a table interaction joker choice.
  const TableInteractionJokerChoice({
    required this.identity,
    required this.assignments,
    required this.actionId,
    required this.cards,
  });

  /// Identity to assign to the unresolved joker.
  final CardIdentity identity;

  /// Identities to assign to all unresolved jokers in the meld.
  final List<JokerMeldAssignment> assignments;

  /// Legal controller action id for this represented identity.
  final String actionId;

  /// Cards to preview with the joker identity applied.
  final List<HareegCard> cards;
}

/// Resolves table gestures into Classic Hareeg actions.
class ClassicHareegTableInteractionAdapter {
  /// Creates a table interaction adapter.
  ClassicHareegTableInteractionAdapter({
    required this.reader,
    required this.seat,
    required Iterable<String> selectedCardIds,
    required Iterable<HareegCard> handCards,
    this.inputLocked = false,
  }) : selectedCardIds = List.unmodifiable(selectedCardIds),
       handCards = List.unmodifiable(handCards);

  /// Action reader for the current game state.
  final TableInteractionActionReader reader;

  /// Seat being controlled by this adapter.
  final PlayerSeat seat;

  /// Selected physical card ids.
  final List<String> selectedCardIds;

  /// Current hand cards in display order.
  final List<HareegCard> handCards;

  /// Whether table input is temporarily locked by CPU flow or animation.
  final bool inputLocked;

  bool get _canInteract => !inputLocked && reader.currentSeat == seat;

  /// Whether [card] can be dropped onto the discard pile.
  bool canDropCardToDiscard(HareegCard card) {
    return resolveDiscard(card).isAction;
  }

  /// Resolves a discard-pile drop for [card].
  TableInteractionResolution resolveDiscard(HareegCard card) {
    if (!_canInteract) {
      return const TableInteractionResolution.blocked(
        'That card cannot be discarded now.',
      );
    }

    final legal = reader.controlActionIdsFor(seat);
    final pending = reader.pendingDiscard;
    if (pending?.id == card.id &&
        legal.contains(ClassicHareegActionIds.returnPendingDiscard)) {
      return const TableInteractionResolution.action(
        ClassicHareegActionIds.returnPendingDiscard,
      );
    }

    final discardActionId = _findDiscardActionId(legal, card.id);
    if (discardActionId != null) {
      return TableInteractionResolution.action(discardActionId);
    }

    return const TableInteractionResolution.blocked(
      'That card cannot be discarded now.',
    );
  }

  /// Whether [card] can be dropped onto the broad table target.
  bool canDropCardToTable(HareegCard card) {
    return resolveTableDrop(card).isAction;
  }

  /// Whether [card] can create a new meld on the broad south meld lane.
  bool canPlaceNewMeldOnTable(HareegCard card) {
    if (!_canInteract) {
      return false;
    }
    final ids = _dropCardIds(card);
    if (ids.isEmpty) return false;
    final pending = reader.pendingDiscard;
    if (pending != null && !ids.contains(pending.id)) return false;
    return _legalMeldActionForCardIds(ids) != null;
  }

  /// Resolves a broad table drop for [card].
  TableInteractionResolution resolveTableDrop(HareegCard card) {
    if (!_canInteract) {
      return const TableInteractionResolution.blocked(
        'Drop a valid meld, cover, or joker replacement.',
      );
    }

    final actionId = _tableActionIdForCardIds(_dropCardIds(card));
    if (actionId == null) {
      return const TableInteractionResolution.blocked(
        'Drop a valid meld, cover, or joker replacement.',
      );
    }
    return TableInteractionResolution.action(actionId);
  }

  /// Whether [card] can be dropped onto a specific table meld.
  bool canDropCardToMeld(HareegCard card, PlayerSeat owner, int meldIndex) {
    return resolveMeldDrop(card, owner, meldIndex).isAction;
  }

  /// Resolves a drop onto a specific table meld.
  TableInteractionResolution resolveMeldDrop(
    HareegCard card,
    PlayerSeat owner,
    int meldIndex,
  ) {
    if (!_canInteract) {
      return const TableInteractionResolution.blocked(
        'That card does not fit this meld.',
      );
    }

    for (final cardIds in _dropCardIdCandidatesForMeld(card)) {
      final actionId = _tableActionIdForMeldTarget(cardIds, owner, meldIndex);
      if (actionId != null) {
        return TableInteractionResolution.action(actionId);
      }
    }

    return const TableInteractionResolution.blocked(
      'That card does not fit this meld.',
    );
  }

  /// Returns a play action for the exact selected single meld.
  String? selectedMeldActionId() {
    if (selectedCardIds.length < 3) {
      return null;
    }
    return _legalMeldActionForCardIds(selectedCardIds);
  }

  /// Returns selected-card-only meld suggestions for the table.
  List<TableInteractionMeldSuggestion> meldSuggestions() {
    // The GitHub PRD is explicit: the picker reflects selected cards only.
    // Opening bundles from the rest of the hand are deliberately excluded.
    if (selectedCardIds.length < 3) return const [];
    final seen = <String>{};
    final suggestions = <TableInteractionMeldSuggestion>[];
    final selectedCards = [
      for (final card in handCards)
        if (selectedCardIds.contains(card.id)) card,
    ];

    for (final group in _selectedMeldCandidateGroups(selectedCards)) {
      final ids = group.map((card) => card.id).toList(growable: false);
      final jokerChoices = _jokerChoicesForCardIds(
        ids,
        includeDeterministic: true,
      );
      if (jokerChoices.isNotEmpty) {
        for (final choice in jokerChoices) {
          if (!seen.add(choice.actionId)) continue;
          suggestions.add(
            TableInteractionMeldSuggestion(
              actionId: choice.actionId,
              cards: choice.cards,
            ),
          );
          if (suggestions.length == 5) {
            break;
          }
        }
        if (suggestions.length == 5) {
          break;
        }
        continue;
      }

      final actionId = _legalMeldActionForCardIds(ids);
      if (actionId == null) continue;
      final key = (List<String>.of(ids)..sort()).join('|');
      if (!seen.add(key)) continue;
      suggestions.add(
        TableInteractionMeldSuggestion(actionId: actionId, cards: group),
      );
      if (suggestions.length == 5) {
        break;
      }
    }
    return suggestions;
  }

  /// Returns explicit represented-joker choices for [cardIds].
  List<TableInteractionJokerChoice> jokerChoicesForCardIds(
    List<String> cardIds,
  ) {
    return _jokerChoicesForCardIds(cardIds, includeDeterministic: false);
  }

  List<TableInteractionJokerChoice> _jokerChoicesForCardIds(
    List<String> cardIds, {
    required bool includeDeterministic,
  }) {
    final choices = reader.jokerMeldChoicesFor(seat, cardIds);
    if (!includeDeterministic && choices.length <= 1) {
      return const [];
    }
    final cards = _cardsForIds(cardIds);
    if (cards == null) {
      return const [];
    }

    return [
      for (final choice in choices)
        TableInteractionJokerChoice(
          identity: choice.identity,
          assignments: choice.assignments,
          actionId: choice.actionId,
          cards: _cardsWithJokerAssignments(cards, choice.assignments),
        ),
    ];
  }

  String? _findDiscardActionId(List<String> legal, String selectedId) {
    for (final id in legal) {
      if (ClassicHareegActionIds.discardCardId(id) == selectedId) {
        return id;
      }
    }
    return null;
  }

  List<String> _dropCardIds(HareegCard card) {
    if (selectedCardIds.contains(card.id) && selectedCardIds.length > 1) {
      return selectedCardIds;
    }
    return [card.id];
  }

  String? _tableActionIdForCardIds(List<String> cardIds) {
    if (cardIds.isEmpty) return null;
    final pending = reader.pendingDiscard;
    if (pending != null && !cardIds.contains(pending.id)) {
      return null;
    }

    final coverActionId = reader.coverActionIdFor(seat, cardIds);
    if (coverActionId != null) return coverActionId;

    final replaceActionId = reader.jokerReplacementActionIdFor(seat, cardIds);
    if (replaceActionId != null) return replaceActionId;

    return _legalMeldActionForCardIds(cardIds);
  }

  String? _tableActionIdForMeldTarget(
    List<String> cardIds,
    PlayerSeat owner,
    int meldIndex,
  ) {
    if (cardIds.isEmpty) return null;
    final pending = reader.pendingDiscard;
    if (pending != null && !cardIds.contains(pending.id)) {
      return null;
    }

    final coverActionId = reader.coverActionIdForMeldTarget(
      seat: seat,
      cardIds: cardIds,
      targetSeat: owner,
      meldIndex: meldIndex,
    );
    if (coverActionId != null) {
      return coverActionId;
    }

    final replacementActionId = reader.jokerReplacementActionIdForMeldTarget(
      seat: seat,
      cardIds: cardIds,
      targetSeat: owner,
      meldIndex: meldIndex,
    );
    if (replacementActionId != null) return replacementActionId;

    return null;
  }

  String? _legalMeldActionForCardIds(Iterable<String> cardIds) {
    return reader.selectedMeldActionIdFor(
      seat,
      cardIds.toList(growable: false),
    );
  }

  Iterable<List<String>> _dropCardIdCandidatesForMeld(HareegCard card) sync* {
    if (selectedCardIds.contains(card.id) && selectedCardIds.length > 1) {
      yield selectedCardIds;
    }
    yield [card.id];
  }

  List<HareegCard>? _cardsForIds(List<String> cardIds) {
    final cards = <HareegCard>[];
    for (final id in cardIds) {
      final index = handCards.indexWhere((card) => card.id == id);
      if (index == -1) {
        return null;
      }
      cards.add(handCards[index]);
    }
    return cards;
  }

  List<HareegCard> _cardsWithJokerAssignments(
    List<HareegCard> cards,
    List<JokerMeldAssignment> assignments,
  ) {
    final assignmentByJokerId = {
      for (final assignment in assignments) assignment.jokerId: assignment,
    };
    final resolvedCards = [
      for (final card in cards)
        if (assignmentByJokerId.containsKey(card.id) && card.isJoker)
          card.asRepresenting(assignmentByJokerId[card.id]!.identity)
        else
          card,
    ];
    return PlacedMeld.fromCards(resolvedCards).cards;
  }

  Iterable<List<HareegCard>> _selectedMeldCandidateGroups(
    List<HareegCard> selectedCards,
  ) sync* {
    if (selectedCards.length < 3) {
      return;
    }
    if (selectedCards.length > 10) {
      yield selectedCards;
      return;
    }
    for (var size = selectedCards.length; size >= 3; size -= 1) {
      yield* _cardCombinations(selectedCards, size);
    }
  }

  Iterable<List<HareegCard>> _cardCombinations(
    List<HareegCard> cards,
    int size,
  ) sync* {
    if (size == 0) {
      yield const <HareegCard>[];
      return;
    }
    if (cards.length < size) {
      return;
    }
    for (var index = 0; index <= cards.length - size; index += 1) {
      final head = cards[index];
      final remaining = cards.sublist(index + 1);
      for (final tail in _cardCombinations(remaining, size - 1)) {
        yield [head, ...tail];
      }
    }
  }
}
