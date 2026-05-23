import '../../../domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import '../../../domain/classic_hareeg/game/classic_hareeg_table_play_planner.dart';
import '../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../domain/classic_hareeg/models/playing_card.dart';
import 'table_interaction_planner.dart';

export 'table_interaction_planner.dart';

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
  List<ClassicHareegMeldSuggestion> meldSuggestionsForSelection(
    PlayerSeat seat,
    List<String> selectedCardIds, {
    int limit = 5,
  }) {
    return controller.meldSuggestionsForSelection(
      seat,
      selectedCardIds,
      limit: limit,
    );
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

/// UI adapter that exposes table interaction plans through widget-friendly
/// booleans and action resolutions.
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

  ClassicHareegTableInteractionPlanner get _planner {
    return ClassicHareegTableInteractionPlanner(
      reader: reader,
      seat: seat,
      selectedCardIds: selectedCardIds,
      handCards: handCards,
      inputLocked: inputLocked,
    );
  }

  /// Whether [card] can be dropped onto the discard pile.
  bool canDropCardToDiscard(HareegCard card) {
    return _planner.canDropCardToDiscard(card);
  }

  /// Resolves a discard-pile drop for [card].
  TableInteractionResolution resolveDiscard(HareegCard card) {
    return _planner.resolveDiscard(card);
  }

  /// Whether [card] can be dropped onto the broad table target.
  bool canDropCardToTable(HareegCard card) {
    return _planner.canDropCardToTable(card);
  }

  /// Whether [card] can create a new meld on the broad south meld lane.
  bool canPlaceNewMeldOnTable(HareegCard card) {
    return _planner.canPlaceNewMeldOnTable(card);
  }

  /// Resolves a broad table drop for [card].
  TableInteractionResolution resolveTableDrop(HareegCard card) {
    return _planner.resolveTableDrop(card);
  }

  /// Whether [card] can be dropped onto a specific table meld.
  bool canDropCardToMeld(HareegCard card, PlayerSeat owner, int meldIndex) {
    return _planner.canDropCardToMeld(card, owner, meldIndex);
  }

  /// Resolves a drop onto a specific table meld.
  TableInteractionResolution resolveMeldDrop(
    HareegCard card,
    PlayerSeat owner,
    int meldIndex,
  ) {
    return _planner.resolveMeldDrop(card, owner, meldIndex);
  }

  /// Returns a play action for the exact selected single meld.
  String? selectedMeldActionId() {
    return _planner.selectedMeldActionId();
  }

  /// Returns selected-card-only meld suggestions for the table.
  List<TableInteractionMeldSuggestion> meldSuggestions() {
    return _planner.meldSuggestions();
  }

  /// Returns explicit represented-joker choices for [cardIds].
  List<TableInteractionJokerChoice> jokerChoicesForCardIds(
    List<String> cardIds,
  ) {
    return _planner.jokerChoicesForCardIds(cardIds);
  }
}
