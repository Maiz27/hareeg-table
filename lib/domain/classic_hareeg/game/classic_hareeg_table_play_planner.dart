import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../rules/cover_rules.dart';
import '../rules/joker_rules.dart';
import '../rules/meld_validator.dart';
import '../rules/opening_rules.dart';
import 'classic_hareeg_action.dart';
import 'classic_hareeg_round.dart';

/// Resolved physical cards and validation result for one meld candidate.
class ClassicHareegResolvedMeldCards {
  /// Creates resolved meld cards.
  const ClassicHareegResolvedMeldCards({
    required this.cards,
    required this.result,
    this.jokerAssignments = const [],
  });

  /// Cards after any deterministic joker representation has been applied.
  final List<HareegCard> cards;

  /// Validation result for [cards].
  final MeldValidationResult result;

  /// Explicit represented identities applied to unresolved jokers.
  final List<JokerMeldAssignment> jokerAssignments;
}

/// Resolved melds and validation result for a multi-meld table play.
class ClassicHareegResolvedTablePlay {
  /// Creates a resolved table play.
  const ClassicHareegResolvedTablePlay({
    required this.melds,
    required this.result,
  });

  /// Melds represented by the table play.
  final List<PlacedMeld> melds;

  /// Aggregate validation result for the table play.
  final MeldValidationResult result;
}

/// One playable meld suggestion produced from a hand selection.
class ClassicHareegMeldSuggestion {
  /// Creates a meld suggestion.
  const ClassicHareegMeldSuggestion({
    required this.actionId,
    required this.cards,
  });

  /// Action id that will play this meld through the rules engine.
  final String actionId;

  /// Cards as they should be displayed in the suggestion picker.
  final List<HareegCard> cards;
}

/// Plans legal Classic Hareeg table plays from immutable turn context.
class ClassicHareegTablePlayPlanner {
  /// Creates a planner for the current table-play context.
  const ClassicHareegTablePlayPlanner({
    required this.currentSeat,
    required this.phase,
    required this.hands,
    required this.tableMelds,
    required this.openingState,
    this.pendingDiscard,
  });

  /// Seat whose turn is active.
  final PlayerSeat currentSeat;

  /// Current turn phase.
  final TurnPhase phase;

  /// Current hands by seat.
  final Map<PlayerSeat, List<HareegCard>> hands;

  /// Current table melds by owner.
  final Map<PlayerSeat, List<PlacedMeld>> tableMelds;

  /// Opening benchmark state.
  final OpeningState openingState;

  /// Pending discard awaiting use-or-return, if any.
  final HareegCard? pendingDiscard;

  /// Validates selected hand cards as a full table play.
  MeldValidationResult meldValidationFor(
    PlayerSeat seat,
    List<String> cardIds,
  ) {
    final cards = _cardsFromHand(seat, cardIds);
    if (cards == null) {
      return const MeldValidationResult.invalid(
        'Selected cards are not all in hand.',
      );
    }
    return resolveTablePlay(cards).result;
  }

  /// Validates selected hand cards as one meld.
  MeldValidationResult singleMeldValidationFor(
    PlayerSeat seat,
    List<String> cardIds,
  ) {
    final cards = _cardsFromHand(seat, cardIds);
    if (cards == null) {
      return const MeldValidationResult.invalid(
        'Selected cards are not all in hand.',
      );
    }
    return resolveMeldCards(cards).result;
  }

  /// Returns the exact action id for selected cards as one meld, if legal.
  String? selectedMeldActionIdFor(PlayerSeat seat, List<String> cardIds) {
    if (seat != currentSeat || phase != TurnPhase.action) {
      return null;
    }
    if (cardIds.length < 3 || cardIds.toSet().length != cardIds.length) {
      return null;
    }
    final pending = pendingDiscard;
    if (pending != null && !cardIds.contains(pending.id)) {
      return null;
    }

    final cards = _cardsFromHand(seat, cardIds);
    if (cards == null) {
      return null;
    }
    if ((_handFor(seat).length) - cards.length == 0) {
      return null;
    }

    final resolved = resolveMeldCards(cards);
    if (resolved.result.isValid) {
      return ClassicHareegActionIds.playMeldActionId(cardIds);
    }

    final choices = _jokerMeldChoicesForCards(cards: cards, cardIds: cardIds);
    return choices.isEmpty ? null : choices.first.actionId;
  }

  /// Returns playable single-meld suggestions for a hand selection.
  ///
  /// Enumerates subsets of [selectedCardIds] (largest first), keeps up to
  /// [limit] legal melds, expands ambiguous-joker subsets into one suggestion
  /// per represented identity, and dedupes by action id. UI pickers consume
  /// the returned list directly so combinatorial enumeration stays inside the
  /// rules engine ([ADR 0001](../../../docs/adr/0001-rules-engine-boundary.md)).
  List<ClassicHareegMeldSuggestion> meldSuggestionsForSelection(
    PlayerSeat seat,
    List<String> selectedCardIds, {
    int limit = 5,
  }) {
    if (limit <= 0 || selectedCardIds.length < 3) {
      return const [];
    }
    final selectedCards = _cardsFromHand(seat, selectedCardIds);
    if (selectedCards == null) {
      return const [];
    }

    final suggestions = <ClassicHareegMeldSuggestion>[];
    final seen = <String>{};

    for (final group in _meldCandidateSubsets(selectedCards)) {
      final groupIds = [for (final card in group) card.id];
      // selectedMeldActionIdFor gates every subset on seat/phase, pending-
      // discard inclusion, hand-must-leave-final-discard, and meld validity.
      // It returns the direct play id when the cards resolve without joker
      // help, otherwise the first joker variant id (or null when illegal).
      // Both branches below need the same gate, so check it once up front.
      final actionId = selectedMeldActionIdFor(seat, groupIds);
      if (actionId == null) {
        continue;
      }
      final jokerChoices = _jokerMeldChoicesForCards(
        cards: group,
        cardIds: groupIds,
      );
      if (jokerChoices.isNotEmpty) {
        for (final choice in jokerChoices) {
          if (!seen.add(choice.actionId)) continue;
          suggestions.add(
            ClassicHareegMeldSuggestion(
              actionId: choice.actionId,
              cards: _displayCardsForChoice(group, choice.assignments),
            ),
          );
          if (suggestions.length >= limit) {
            return suggestions;
          }
        }
        continue;
      }

      final key = (List<String>.of(groupIds)..sort()).join('|');
      if (!seen.add(key)) continue;
      suggestions.add(
        ClassicHareegMeldSuggestion(actionId: actionId, cards: group),
      );
      if (suggestions.length >= limit) {
        return suggestions;
      }
    }
    return suggestions;
  }

  Iterable<List<HareegCard>> _meldCandidateSubsets(
    List<HareegCard> selectedCards,
  ) sync* {
    if (selectedCards.length < 3) return;
    if (selectedCards.length > 10) {
      yield selectedCards;
      return;
    }
    for (var size = selectedCards.length; size >= 3; size -= 1) {
      yield* _subsetsOf(selectedCards, size);
    }
  }

  Iterable<List<HareegCard>> _subsetsOf(
    List<HareegCard> cards,
    int size,
  ) sync* {
    if (size == 0) {
      yield const <HareegCard>[];
      return;
    }
    if (cards.length < size) return;
    for (var index = 0; index <= cards.length - size; index += 1) {
      final head = cards[index];
      final remaining = cards.sublist(index + 1);
      for (final tail in _subsetsOf(remaining, size - 1)) {
        yield [head, ...tail];
      }
    }
  }

  List<HareegCard> _displayCardsForChoice(
    List<HareegCard> cards,
    List<JokerMeldAssignment> assignments,
  ) {
    if (assignments.isEmpty) return cards;
    final assignmentByJokerId = {
      for (final assignment in assignments) assignment.jokerId: assignment,
    };
    final resolved = [
      for (final card in cards)
        if (assignmentByJokerId.containsKey(card.id) && card.isJoker)
          card.asRepresenting(assignmentByJokerId[card.id]!.identity)
        else
          card,
    ];
    return PlacedMeld.fromCards(resolved).cards;
  }

  /// Returns explicit represented-joker choices for selected meld cards.
  List<JokerMeldActionChoice> jokerMeldChoicesFor(
    PlayerSeat seat,
    List<String> cardIds,
  ) {
    if (seat != currentSeat || phase != TurnPhase.action) {
      return const [];
    }
    if (cardIds.length < 3 || cardIds.toSet().length != cardIds.length) {
      return const [];
    }
    final pending = pendingDiscard;
    if (pending != null && !cardIds.contains(pending.id)) {
      return const [];
    }

    final cards = _cardsFromHand(seat, cardIds);
    if (cards == null) {
      return const [];
    }
    if ((_handFor(seat).length) - cards.length == 0) {
      return const [];
    }

    return _jokerMeldChoicesForCards(cards: cards, cardIds: cardIds);
  }

  List<JokerMeldActionChoice> _jokerMeldChoicesForCards({
    required List<HareegCard> cards,
    required List<String> cardIds,
  }) {
    final variants = resolveMeldCardVariants(cards);
    if (variants.isEmpty) {
      return const [];
    }

    final choices = <JokerMeldActionChoice>[];
    final seen = <String>{};
    for (final variant in variants) {
      if (variant.jokerAssignments.isEmpty) {
        continue;
      }
      final choice = JokerMeldActionChoice.withAssignments(
        assignments: variant.jokerAssignments,
        cardIds: cardIds,
      );
      if (seen.add(choice.actionId)) {
        choices.add(choice);
      }
    }
    return List.unmodifiable(choices);
  }

  /// Returns explicit represented-card choices needed for an ambiguous joker.
  List<CardIdentity> jokerRepresentationOptionsFor(
    PlayerSeat seat,
    List<String> cardIds,
  ) {
    final cards = _cardsFromHand(seat, cardIds);
    if (cards == null) {
      return const [];
    }
    final unresolvedJokers = cards
        .where((card) => card.isJoker && card.representedIdentity == null)
        .toList(growable: false);
    if (unresolvedJokers.length != 1) {
      return const [];
    }

    final options = ClassicHareegJokerRules.representationOptionsForMeld(
      cards: cards,
      joker: unresolvedJokers.single,
    );
    return options.length > 1 ? options : const [];
  }

  /// Returns a legal cover action id for [cardIds], if any.
  String? coverActionIdFor(PlayerSeat seat, List<String> cardIds) {
    if (seat != currentSeat ||
        phase != TurnPhase.action ||
        cardIds.isEmpty ||
        !ClassicHareegCoverRules.canPlayCover(
          playerOpened: openingState.hasOpened(seat),
        )) {
      return null;
    }
    final cards = _cardsFromHand(seat, cardIds);
    if (cards == null) {
      return null;
    }
    if (_handFor(seat).length - cards.length == 0) {
      return null;
    }

    for (final owner in PlayerSeat.values) {
      final melds = tableMelds[owner] ?? const <PlacedMeld>[];
      for (var index = 0; index < melds.length; index += 1) {
        final ordered = orderedCoverCards(
          tableMeld: melds[index].cards,
          candidates: cards,
        );
        if (ordered != null) {
          return ClassicHareegActionIds.placeCoverActionId(
            targetSeat: owner,
            meldIndex: index,
            cardIds: cardIds,
          );
        }
      }
    }
    return null;
  }

  /// Returns a legal cover action id for a specific table meld target.
  String? coverActionIdForMeldTarget({
    required PlayerSeat seat,
    required List<String> cardIds,
    required PlayerSeat targetSeat,
    required int meldIndex,
  }) {
    if (seat != currentSeat ||
        phase != TurnPhase.action ||
        cardIds.isEmpty ||
        !ClassicHareegCoverRules.canPlayCover(
          playerOpened: openingState.hasOpened(seat),
        )) {
      return null;
    }
    final cards = _cardsFromHand(seat, cardIds);
    if (cards == null) {
      return null;
    }
    if (_handFor(seat).length - cards.length == 0) {
      return null;
    }

    final melds = tableMelds[targetSeat] ?? const <PlacedMeld>[];
    if (meldIndex < 0 || meldIndex >= melds.length) {
      return null;
    }
    final ordered = orderedCoverCards(
      tableMeld: melds[meldIndex].cards,
      candidates: cards,
    );
    if (ordered == null) {
      return null;
    }
    return ClassicHareegActionIds.placeCoverActionId(
      targetSeat: targetSeat,
      meldIndex: meldIndex,
      cardIds: cardIds,
    );
  }

  /// Returns a joker replacement action id for one selected real card.
  String? jokerReplacementActionIdFor(PlayerSeat seat, List<String> cardIds) {
    if (seat != currentSeat || cardIds.length != 1) {
      return null;
    }
    return replacementActionIdForCardId(seat, cardIds.single);
  }

  /// Returns a legal joker replacement action id for a specific table meld.
  String? jokerReplacementActionIdForMeldTarget({
    required PlayerSeat seat,
    required List<String> cardIds,
    required PlayerSeat targetSeat,
    required int meldIndex,
  }) {
    if (seat != currentSeat ||
        phase != TurnPhase.action ||
        cardIds.length != 1 ||
        !openingState.hasOpened(seat)) {
      return null;
    }
    final hand = _handFor(seat);
    final cardIndex = hand.indexWhere(
      (candidate) => candidate.id == cardIds.single,
    );
    if (cardIndex == -1) {
      return null;
    }

    final melds = tableMelds[targetSeat] ?? const <PlacedMeld>[];
    if (meldIndex < 0 || meldIndex >= melds.length) {
      return null;
    }
    if (!ClassicHareegJokerRules.canReplaceJoker(
      playerOpened: true,
      tableCards: melds[meldIndex].cards,
      replacementCard: hand[cardIndex],
    )) {
      return null;
    }
    return ClassicHareegActionIds.replaceJokerActionId(
      targetSeat: targetSeat,
      meldIndex: meldIndex,
      cardId: hand[cardIndex].id,
    );
  }

  /// Returns the first joker replacement action id matching [cardId]. Only
  /// surfaces an action when the seat has opened — replacing a joker is a
  /// play action that requires an open. Use [cardBlockedByTableJoker] for
  /// the discard-eligibility check, which must apply regardless of opening
  /// (the rule "you can't discard a card that could replace a joker on the
  /// table" doesn't relax pre-opening).
  String? replacementActionIdForCardId(PlayerSeat seat, String cardId) {
    if (!openingState.hasOpened(seat)) {
      return null;
    }
    final hand = _handFor(seat);
    final cardIndex = hand.indexWhere((candidate) => candidate.id == cardId);
    if (cardIndex == -1) {
      return null;
    }
    final card = hand[cardIndex];

    for (final owner in PlayerSeat.values) {
      final melds = tableMelds[owner] ?? const <PlacedMeld>[];
      for (var index = 0; index < melds.length; index += 1) {
        if (ClassicHareegJokerRules.canReplaceJoker(
          playerOpened: true,
          tableCards: melds[index].cards,
          replacementCard: card,
        )) {
          return ClassicHareegActionIds.replaceJokerActionId(
            targetSeat: owner,
            meldIndex: index,
            cardId: card.id,
          );
        }
      }
    }
    return null;
  }

  /// True when [card]'s identity matches a represented joker sitting on any
  /// table meld. Used by discard eligibility to block "throw a card that
  /// could replace a joker" attempts even before the seat has opened (the
  /// rule applies to the card, not to the seat's open state). The actual
  /// replace-joker *action* still requires the seat to have opened.
  bool cardBlockedByTableJoker(HareegCard card) {
    final identity = card.identity;
    if (identity == null) return false;
    for (final owner in PlayerSeat.values) {
      final melds = tableMelds[owner] ?? const <PlacedMeld>[];
      for (final meld in melds) {
        for (final tableCard in meld.cards) {
          if (tableCard.isJoker &&
              tableCard.representedIdentity == identity) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Returns legal cover action ids from [seat]'s hand.
  List<String> coverActionIds(PlayerSeat seat, {String? mustUseCardId}) {
    if (phase != TurnPhase.action ||
        !ClassicHareegCoverRules.canPlayCover(
          playerOpened: openingState.hasOpened(seat),
        )) {
      return const [];
    }

    final hand = _handFor(seat);
    final ids = <String>{};
    for (final group in candidateGroups(hand, minSize: 1, maxSize: 3)) {
      if (hand.length - group.length == 0) {
        continue;
      }
      if (mustUseCardId != null &&
          !group.any((card) => card.id == mustUseCardId)) {
        continue;
      }
      for (final owner in PlayerSeat.values) {
        final melds = tableMelds[owner] ?? const <PlacedMeld>[];
        for (var index = 0; index < melds.length; index += 1) {
          final ordered = orderedCoverCards(
            tableMeld: melds[index].cards,
            candidates: group,
          );
          if (ordered != null) {
            ids.add(
              ClassicHareegActionIds.placeCoverActionId(
                targetSeat: owner,
                meldIndex: index,
                cardIds: group.map((card) => card.id),
              ),
            );
            return List.unmodifiable(ids);
          }
        }
      }
    }
    return List.unmodifiable(ids);
  }

  /// Returns legal represented-joker replacement action ids from [seat]'s hand.
  List<String> replaceJokerActionIds(PlayerSeat seat, {String? mustUseCardId}) {
    if (phase != TurnPhase.action ||
        !ClassicHareegCoverRules.canPlayCover(
          playerOpened: openingState.hasOpened(seat),
        )) {
      return const [];
    }

    final hand = _handFor(seat);
    for (final card in hand) {
      if (mustUseCardId != null && card.id != mustUseCardId) {
        continue;
      }
      final actionId = replacementActionIdForCardId(seat, card.id);
      if (actionId != null) {
        return [actionId];
      }
    }
    return const [];
  }

  List<HareegCard> _handFor(PlayerSeat seat) {
    return hands[seat] ?? const <HareegCard>[];
  }

  List<HareegCard>? _cardsFromHand(PlayerSeat seat, List<String> cardIds) {
    final uniqueIds = <String>{};
    for (final id in cardIds) {
      if (!uniqueIds.add(id)) {
        return null;
      }
    }

    final hand = _handFor(seat);
    final cards = <HareegCard>[];
    for (final id in cardIds) {
      final index = hand.indexWhere((card) => card.id == id);
      if (index == -1) {
        return null;
      }
      cards.add(hand[index]);
    }
    return cards;
  }

  /// Resolves [cards] as a single meld.
  static ClassicHareegResolvedMeldCards resolveMeldCards(
    List<HareegCard> cards, {
    String? jokerId,
    CardIdentity? jokerIdentity,
    Map<String, CardIdentity>? jokerIdentities,
  }) {
    final direct = ClassicHareegMeldValidator.validate(cards);
    if (direct.isValid) {
      return ClassicHareegResolvedMeldCards(cards: cards, result: direct);
    }

    final unresolvedJokers = cards
        .where((card) => card.isJoker && card.representedIdentity == null)
        .toList(growable: false);
    final explicitIdentities = <String, CardIdentity>{};
    if (jokerIdentities != null) {
      explicitIdentities.addAll(jokerIdentities);
    }
    if (jokerId != null || jokerIdentity != null) {
      if (jokerId == null || jokerIdentity == null) {
        return ClassicHareegResolvedMeldCards(
          cards: cards,
          result: const MeldValidationResult.invalid(
            'Selected joker identity does not match this meld.',
          ),
        );
      }
      explicitIdentities[jokerId] = jokerIdentity;
    }

    if (explicitIdentities.isNotEmpty) {
      final unresolvedIds = unresolvedJokers.map((joker) => joker.id).toSet();
      if (explicitIdentities.keys
              .toSet()
              .difference(unresolvedIds)
              .isNotEmpty ||
          unresolvedIds
              .difference(explicitIdentities.keys.toSet())
              .isNotEmpty) {
        return ClassicHareegResolvedMeldCards(
          cards: cards,
          result: const MeldValidationResult.invalid(
            'Selected joker identity does not match this meld.',
          ),
        );
      }
      return _resolveMeldCardsWithAssignments(cards, [
        for (final joker in unresolvedJokers)
          JokerMeldAssignment(
            jokerId: joker.id,
            identity: explicitIdentities[joker.id]!,
          ),
      ]);
    }

    if (unresolvedJokers.isEmpty) {
      return ClassicHareegResolvedMeldCards(cards: cards, result: direct);
    }

    final variants = resolveMeldCardVariants(cards);
    if (variants.isEmpty) {
      return ClassicHareegResolvedMeldCards(cards: cards, result: direct);
    }
    if (variants.length == 1) {
      return variants.single;
    }
    return ClassicHareegResolvedMeldCards(
      cards: cards,
      result: const MeldValidationResult.invalid(
        'Choose what each joker represents.',
      ),
    );
  }

  /// Returns legal represented-joker variants for a single meld candidate.
  static List<ClassicHareegResolvedMeldCards> resolveMeldCardVariants(
    List<HareegCard> cards, {
    int limit = 5,
  }) {
    final variants = ClassicHareegJokerRules.resolveMeldVariants(
      cards,
      limit: limit,
    );
    return List.unmodifiable(variants.map(_fromJokerResolution));
  }

  static ClassicHareegResolvedMeldCards _resolveMeldCardsWithAssignments(
    List<HareegCard> cards,
    List<JokerMeldAssignment> assignments,
  ) {
    final assignmentByJokerId = <String, CardIdentity>{};
    for (final assignment in assignments) {
      if (assignmentByJokerId.containsKey(assignment.jokerId)) {
        return ClassicHareegResolvedMeldCards(
          cards: cards,
          result: const MeldValidationResult.invalid(
            'A joker can only have one represented identity.',
          ),
        );
      }
      assignmentByJokerId[assignment.jokerId] = assignment.identity;
    }

    final variants = ClassicHareegJokerRules.resolveMeldVariants(
      cards,
      jokerIdentities: assignmentByJokerId,
      limit: 1,
    );
    if (variants.isEmpty) {
      return ClassicHareegResolvedMeldCards(
        cards: cards,
        result: const MeldValidationResult.invalid(
          'Selected joker identity does not match this meld.',
        ),
      );
    }
    return _fromJokerResolution(variants.single);
  }

  static ClassicHareegResolvedMeldCards _fromJokerResolution(
    JokerMeldResolution resolution,
  ) {
    final assignments = [
      for (final entry in resolution.assignments.entries)
        JokerMeldAssignment(jokerId: entry.key, identity: entry.value),
    ];
    if (!resolution.result.isValid) {
      return ClassicHareegResolvedMeldCards(
        cards: resolution.cards,
        result: resolution.result,
        jokerAssignments: List.unmodifiable(assignments),
      );
    }

    final orderedCards = PlacedMeld.fromCards(resolution.cards).cards;
    return ClassicHareegResolvedMeldCards(
      cards: orderedCards,
      result: MeldValidationResult.valid(
        type: resolution.result.type!,
        value: resolution.result.value,
        message: assignments.isEmpty
            ? resolution.result.message
            : '${resolution.result.message} '
                  '${_jokerAssignmentMessage(assignments)}.',
      ),
      jokerAssignments: List.unmodifiable(assignments),
    );
  }

  /// Resolves [cards] as one or more melds.
  static ClassicHareegResolvedTablePlay resolveTablePlay(
    List<HareegCard> cards, {
    String? jokerId,
    CardIdentity? jokerIdentity,
    Map<String, CardIdentity>? jokerIdentities,
  }) {
    final single = resolveMeldCards(
      cards,
      jokerId: jokerId,
      jokerIdentity: jokerIdentity,
      jokerIdentities: jokerIdentities,
    );
    if (single.result.isValid) {
      return ClassicHareegResolvedTablePlay(
        melds: [PlacedMeld.fromCards(single.cards)],
        result: single.result,
      );
    }

    final explicitJokerIdentities = <String, CardIdentity>{};
    if (jokerIdentities != null) {
      explicitJokerIdentities.addAll(jokerIdentities);
    }
    if (jokerId != null || jokerIdentity != null) {
      if (jokerId == null || jokerIdentity == null) {
        return const ClassicHareegResolvedTablePlay(
          melds: [],
          result: MeldValidationResult.invalid(
            'Selected joker identity does not match this table play.',
          ),
        );
      }
      explicitJokerIdentities[jokerId] = jokerIdentity;
    }
    if (!_explicitJokerIdentitiesMatch(cards, explicitJokerIdentities)) {
      return const ClassicHareegResolvedTablePlay(
        melds: [],
        result: MeldValidationResult.invalid(
          'Selected joker identity does not match this table play.',
        ),
      );
    }

    final melds = _partitionIntoMelds(
      cards,
      <String, List<PlacedMeld>?>{},
      jokerIdentities: explicitJokerIdentities.isEmpty
          ? null
          : explicitJokerIdentities,
    );
    if (melds == null) {
      return ClassicHareegResolvedTablePlay(
        melds: const [],
        result: single.result,
      );
    }

    final value = melds.fold<int>(
      0,
      (total, meld) => total + meld.valueSnapshot,
    );
    return ClassicHareegResolvedTablePlay(
      melds: melds,
      result: MeldValidationResult.valid(
        type: MeldType.set,
        value: value,
        message: 'Valid table play.',
      ),
    );
  }

  /// Returns cover cards in legal application order, if possible.
  static List<HareegCard>? orderedCoverCards({
    required List<HareegCard> tableMeld,
    required List<HareegCard> candidates,
  }) {
    return ClassicHareegCoverRules.orderedCoverCards(
      tableMeld: tableMeld,
      candidates: candidates,
    );
  }

  /// Resolves one cover candidate, including joker cover identity if needed.
  static HareegCard? resolveCoverCandidate({
    required List<HareegCard> tableMeld,
    required HareegCard candidate,
  }) {
    return ClassicHareegCoverRules.resolveCoverCandidate(
      tableMeld: tableMeld,
      candidate: candidate,
    );
  }

  static String _jokerAssignmentMessage(List<JokerMeldAssignment> assignments) {
    if (assignments.length == 1) {
      return 'Joker as ${assignments.single.identity.label}';
    }
    final labels = assignments
        .map((assignment) => assignment.identity.label)
        .join(', ');
    return 'Jokers as $labels';
  }

  /// Enumerates candidate groups from [cards].
  static Iterable<List<HareegCard>> candidateGroups(
    List<HareegCard> cards, {
    required int minSize,
    int? maxSize,
  }) sync* {
    final count = cards.length;
    if (count == 0 || count > 20) {
      return;
    }
    final effectiveMaxSize = maxSize ?? count;

    final maxMask = 1 << count;
    for (var mask = 1; mask < maxMask; mask += 1) {
      final group = <HareegCard>[];
      for (var index = 0; index < count; index += 1) {
        if ((mask & (1 << index)) != 0) {
          group.add(cards[index]);
        }
      }
      if (group.length >= minSize && group.length <= effectiveMaxSize) {
        yield group;
      }
    }
  }

  static List<PlacedMeld>? _partitionIntoMelds(
    List<HareegCard> cards,
    Map<String, List<PlacedMeld>?> memo, {
    Map<String, CardIdentity>? jokerIdentities,
  }) {
    if (cards.isEmpty) {
      return const [];
    }
    if (cards.length < 3) {
      return null;
    }

    final key = (cards.map((card) => card.id).toList()..sort()).join('|');
    if (memo.containsKey(key)) {
      return memo[key];
    }

    final first = cards.first;
    for (final group in _candidateGroupsContainingFirst(cards, first)) {
      final resolved = resolveMeldCards(
        group,
        jokerIdentities: _jokerIdentitiesForGroup(group, jokerIdentities),
      );
      if (!resolved.result.isValid) {
        continue;
      }
      final groupIds = group.map((card) => card.id).toSet();
      final remaining = cards
          .where((card) => !groupIds.contains(card.id))
          .toList(growable: false);
      final rest = _partitionIntoMelds(
        remaining,
        memo,
        jokerIdentities: jokerIdentities,
      );
      if (rest != null) {
        final result = [PlacedMeld.fromCards(resolved.cards), ...rest];
        memo[key] = result;
        return result;
      }
    }
    memo[key] = null;
    return null;
  }

  static bool _explicitJokerIdentitiesMatch(
    List<HareegCard> cards,
    Map<String, CardIdentity> identities,
  ) {
    if (identities.isEmpty) {
      return true;
    }
    final unresolvedJokerIds = cards
        .where((card) => card.isJoker && card.representedIdentity == null)
        .map((card) => card.id)
        .toSet();
    return identities.keys.toSet().difference(unresolvedJokerIds).isEmpty;
  }

  static Map<String, CardIdentity>? _jokerIdentitiesForGroup(
    List<HareegCard> group,
    Map<String, CardIdentity>? identities,
  ) {
    if (identities == null || identities.isEmpty) {
      return null;
    }
    final groupCardIds = group.map((card) => card.id).toSet();
    final groupIdentities = <String, CardIdentity>{};
    for (final entry in identities.entries) {
      if (groupCardIds.contains(entry.key)) {
        groupIdentities[entry.key] = entry.value;
      }
    }
    return groupIdentities.isEmpty ? null : groupIdentities;
  }

  static Iterable<List<HareegCard>> _candidateGroupsContainingFirst(
    List<HareegCard> cards,
    HareegCard first,
  ) sync* {
    final rest = cards.where((card) => card.id != first.id).toList();
    final maxMask = 1 << rest.length;
    for (var mask = 0; mask < maxMask; mask += 1) {
      final group = <HareegCard>[first];
      for (var index = 0; index < rest.length; index += 1) {
        if ((mask & (1 << index)) != 0) {
          group.add(rest[index]);
        }
      }
      if (group.length >= 3) {
        yield group;
      }
    }
  }
}
