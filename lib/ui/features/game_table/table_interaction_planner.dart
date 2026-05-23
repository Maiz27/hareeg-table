import '../../../domain/classic_hareeg/game/classic_hareeg_action.dart';
import '../../../domain/classic_hareeg/game/classic_hareeg_table_play_planner.dart';
import '../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../domain/classic_hareeg/rules/opening_rules.dart';

/// Read-only action lookup needed by the table interaction planner.
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

  /// Playable single-meld suggestions for a hand selection.
  List<ClassicHareegMeldSuggestion> meldSuggestionsForSelection(
    PlayerSeat seat,
    List<String> selectedCardIds, {
    int limit,
  });

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

/// Table gesture scenario identified by the interaction planner.
enum TableInteractionScenario {
  /// Input is locked or another seat is active.
  locked,

  /// Dropped card returns a pending discard.
  returnPendingDiscard,

  /// Dropped card is discarded.
  discard,

  /// Broad table drop resolves as a cover.
  tableCover,

  /// Broad table drop resolves as a represented-joker replacement.
  tableJokerReplacement,

  /// Broad table drop resolves as a new meld.
  tableMeld,

  /// Specific meld drop resolves as a cover.
  specificMeldCover,

  /// Specific meld drop resolves as a represented-joker replacement.
  specificMeldJokerReplacement,

  /// Discard drop is blocked.
  blockedDiscard,

  /// Broad table drop is blocked.
  blockedTableDrop,

  /// Specific meld drop is blocked.
  blockedMeldDrop,
}

/// Result of resolving one table interaction.
class TableInteractionResolution {
  const TableInteractionResolution._({
    required this.scenario,
    this.actionId,
    this.failureMessage,
  });

  /// Legal interaction that should apply [actionId].
  const TableInteractionResolution.action(
    String actionId, {
    required TableInteractionScenario scenario,
  }) : this._(scenario: scenario, actionId: actionId);

  /// Blocked interaction with a player-facing [failureMessage].
  const TableInteractionResolution.blocked(
    String failureMessage, {
    required TableInteractionScenario scenario,
  }) : this._(scenario: scenario, failureMessage: failureMessage);

  /// Identified interaction scenario.
  final TableInteractionScenario scenario;

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

/// Resolves table gestures into typed Classic Hareeg interaction scenarios.
class ClassicHareegTableInteractionPlanner {
  /// Creates a table interaction planner.
  ClassicHareegTableInteractionPlanner({
    required this.reader,
    required this.seat,
    required Iterable<String> selectedCardIds,
    required Iterable<HareegCard> handCards,
    this.inputLocked = false,
  }) : selectedCardIds = List.unmodifiable(selectedCardIds),
       handCards = List.unmodifiable(handCards);

  /// Action reader for the current game state.
  final TableInteractionActionReader reader;

  /// Seat being controlled by this planner.
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
        scenario: TableInteractionScenario.locked,
      );
    }

    final legal = reader.controlActionIdsFor(seat);
    final pending = reader.pendingDiscard;
    if (pending?.id == card.id &&
        legal.contains(ClassicHareegActionIds.returnPendingDiscard)) {
      return const TableInteractionResolution.action(
        ClassicHareegActionIds.returnPendingDiscard,
        scenario: TableInteractionScenario.returnPendingDiscard,
      );
    }

    final discardActionId = _findDiscardActionId(legal, card.id);
    if (discardActionId != null) {
      return TableInteractionResolution.action(
        discardActionId,
        scenario: TableInteractionScenario.discard,
      );
    }

    return const TableInteractionResolution.blocked(
      'That card cannot be discarded now.',
      scenario: TableInteractionScenario.blockedDiscard,
    );
  }

  /// Whether [card] can be dropped onto the broad table target.
  bool canDropCardToTable(HareegCard card) {
    return resolveTableDrop(card).isAction;
  }

  /// Whether [card] can create a new meld on the broad south meld lane.
  bool canPlaceNewMeldOnTable(HareegCard card) {
    return resolveTableDrop(card).scenario ==
        TableInteractionScenario.tableMeld;
  }

  /// Resolves a broad table drop for [card].
  TableInteractionResolution resolveTableDrop(HareegCard card) {
    if (!_canInteract) {
      return const TableInteractionResolution.blocked(
        'Drop a valid meld, cover, or joker replacement.',
        scenario: TableInteractionScenario.locked,
      );
    }

    final action = _tableActionForCardIds(_dropCardIds(card));
    if (action == null) {
      return const TableInteractionResolution.blocked(
        'Drop a valid meld, cover, or joker replacement.',
        scenario: TableInteractionScenario.blockedTableDrop,
      );
    }
    return TableInteractionResolution.action(
      action.actionId,
      scenario: action.scenario,
    );
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
        scenario: TableInteractionScenario.locked,
      );
    }

    for (final cardIds in _dropCardIdCandidatesForMeld(card)) {
      final action = _tableActionForMeldTarget(cardIds, owner, meldIndex);
      if (action != null) {
        return TableInteractionResolution.action(
          action.actionId,
          scenario: action.scenario,
        );
      }
    }

    return const TableInteractionResolution.blocked(
      'That card does not fit this meld.',
      scenario: TableInteractionScenario.blockedMeldDrop,
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
  ///
  /// The combinatorial enumeration lives in the rules engine. The UI just
  /// forwards the current selection and re-shapes the domain suggestion type.
  List<TableInteractionMeldSuggestion> meldSuggestions() {
    final domainSuggestions = reader.meldSuggestionsForSelection(
      seat,
      selectedCardIds,
    );
    return [
      for (final suggestion in domainSuggestions)
        TableInteractionMeldSuggestion(
          actionId: suggestion.actionId,
          cards: suggestion.cards,
        ),
    ];
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

  _ResolvedTableInteractionAction? _tableActionForCardIds(
    List<String> cardIds,
  ) {
    if (cardIds.isEmpty) return null;
    final pending = reader.pendingDiscard;
    if (pending != null && !cardIds.contains(pending.id)) {
      return null;
    }

    final coverActionId = reader.coverActionIdFor(seat, cardIds);
    if (coverActionId != null) {
      return _ResolvedTableInteractionAction(
        actionId: coverActionId,
        scenario: TableInteractionScenario.tableCover,
      );
    }

    final replaceActionId = reader.jokerReplacementActionIdFor(seat, cardIds);
    if (replaceActionId != null) {
      return _ResolvedTableInteractionAction(
        actionId: replaceActionId,
        scenario: TableInteractionScenario.tableJokerReplacement,
      );
    }

    final meldActionId = _legalMeldActionForCardIds(cardIds);
    if (meldActionId == null) {
      return null;
    }
    return _ResolvedTableInteractionAction(
      actionId: meldActionId,
      scenario: TableInteractionScenario.tableMeld,
    );
  }

  _ResolvedTableInteractionAction? _tableActionForMeldTarget(
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
      return _ResolvedTableInteractionAction(
        actionId: coverActionId,
        scenario: TableInteractionScenario.specificMeldCover,
      );
    }

    final replacementActionId = reader.jokerReplacementActionIdForMeldTarget(
      seat: seat,
      cardIds: cardIds,
      targetSeat: owner,
      meldIndex: meldIndex,
    );
    if (replacementActionId == null) {
      return null;
    }
    return _ResolvedTableInteractionAction(
      actionId: replacementActionId,
      scenario: TableInteractionScenario.specificMeldJokerReplacement,
    );
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

}

class _ResolvedTableInteractionAction {
  const _ResolvedTableInteractionAction({
    required this.actionId,
    required this.scenario,
  });

  final String actionId;
  final TableInteractionScenario scenario;
}
