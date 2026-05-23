import '../models/playing_card.dart';

/// Bounded physical-card search for possible Classic Hareeg meld groups.
///
/// This module deliberately returns candidate physical groups, not legality
/// decisions. Joker identity assignment and meld validation stay in the joker
/// and meld rules modules.
abstract final class ClassicHareegMeldCandidateSearch {
  /// Returns candidate physical card groups that could resolve to one meld.
  static List<List<HareegCard>> candidateMeldGroups(
    List<HareegCard> hand, {
    String? preferredCardId,
    int maxPhysicalVariants = 8,
  }) {
    final groups = <List<HareegCard>>[];
    final seen = <String>{};
    final cardsByIdentity = <String, List<HareegCard>>{};
    final unresolvedJokers = <HareegCard>[];

    for (final card in hand) {
      final identity = card.effectiveIdentity;
      if (identity == null) {
        if (card.isJoker) {
          unresolvedJokers.add(card);
        }
        continue;
      }
      cardsByIdentity.putIfAbsent(identity.key, () => <HareegCard>[]).add(card);
    }

    final jokers = _orderedJokers(unresolvedJokers, preferredCardId);

    void addGroup(List<HareegCard> cards) {
      if (cards.length < 3) {
        return;
      }
      final ids = cards.map((card) => card.id).toList();
      if (ids.toSet().length != ids.length) {
        return;
      }
      final key = (ids..sort()).join('|');
      if (seen.add(key)) {
        groups.add(List.unmodifiable(cards));
      }
    }

    for (final rank in CardRank.values) {
      _addSetCandidateGroups(
        addGroup: addGroup,
        cardsByIdentity: cardsByIdentity,
        jokers: jokers,
        rank: rank,
        preferredCardId: preferredCardId,
        maxPhysicalVariants: maxPhysicalVariants,
      );
    }

    for (final suit in CardSuit.values) {
      _addSequenceCandidateGroups(
        addGroup: addGroup,
        cardsByIdentity: cardsByIdentity,
        ranks: CardRank.values,
        suit: suit,
        jokers: jokers,
        preferredCardId: preferredCardId,
        maxPhysicalVariants: maxPhysicalVariants,
      );
      _addHighAceSequenceCandidateGroups(
        addGroup: addGroup,
        cardsByIdentity: cardsByIdentity,
        suit: suit,
        jokers: jokers,
        preferredCardId: preferredCardId,
        maxPhysicalVariants: maxPhysicalVariants,
      );
    }

    return List.unmodifiable(groups);
  }
}

void _addSetCandidateGroups({
  required void Function(List<HareegCard> cards) addGroup,
  required Map<String, List<HareegCard>> cardsByIdentity,
  required List<HareegCard> jokers,
  required CardRank rank,
  required String? preferredCardId,
  required int maxPhysicalVariants,
}) {
  final availableSuits = <CardSuit>[];
  for (final suit in CardSuit.values) {
    final identity = CardIdentity(rank: rank, suit: suit);
    if (_cardForIdentity(cardsByIdentity, identity, preferredCardId) != null) {
      availableSuits.add(suit);
    }
  }

  for (var size = 3; size <= 4; size += 1) {
    final minStandardCount = (size - jokers.length).clamp(0, size);
    final maxStandardCount = availableSuits.length < size
        ? availableSuits.length
        : size;
    for (
      var standardCount = maxStandardCount;
      standardCount >= minStandardCount;
      standardCount -= 1
    ) {
      final jokerCount = size - standardCount;
      for (final suits in _combinations(availableSuits, standardCount)) {
        for (final jokerGroup in _combinations(jokers, jokerCount)) {
          _addMeldGroupVariants(
            addGroup: addGroup,
            choices: [
              for (final suit in suits)
                _cardsForIdentity(
                  cardsByIdentity,
                  CardIdentity(rank: rank, suit: suit),
                  preferredCardId,
                ),
              for (final joker in jokerGroup) [joker],
            ],
            maxPhysicalVariants: maxPhysicalVariants,
          );
        }
      }
    }
  }
}

void _addSequenceCandidateGroups({
  required void Function(List<HareegCard> cards) addGroup,
  required Map<String, List<HareegCard>> cardsByIdentity,
  required List<CardRank> ranks,
  required CardSuit suit,
  required List<HareegCard> jokers,
  required String? preferredCardId,
  required int maxPhysicalVariants,
}) {
  for (var start = 0; start <= ranks.length - 3; start += 1) {
    for (var end = start + 3; end <= ranks.length; end += 1) {
      _addSequenceCandidateGroup(
        addGroup: addGroup,
        cardsByIdentity: cardsByIdentity,
        ranks: ranks.sublist(start, end),
        suit: suit,
        jokers: jokers,
        preferredCardId: preferredCardId,
        maxPhysicalVariants: maxPhysicalVariants,
      );
    }
  }
}

void _addHighAceSequenceCandidateGroups({
  required void Function(List<HareegCard> cards) addGroup,
  required Map<String, List<HareegCard>> cardsByIdentity,
  required CardSuit suit,
  required List<HareegCard> jokers,
  required String? preferredCardId,
  required int maxPhysicalVariants,
}) {
  final ranks = [
    for (final rank in CardRank.values)
      if (rank != CardRank.ace) rank,
    CardRank.ace,
  ];
  for (var start = 0; start <= ranks.length - 3; start += 1) {
    _addSequenceCandidateGroup(
      addGroup: addGroup,
      cardsByIdentity: cardsByIdentity,
      ranks: ranks.sublist(start),
      suit: suit,
      jokers: jokers,
      preferredCardId: preferredCardId,
      maxPhysicalVariants: maxPhysicalVariants,
    );
  }
}

void _addSequenceCandidateGroup({
  required void Function(List<HareegCard> cards) addGroup,
  required Map<String, List<HareegCard>> cardsByIdentity,
  required List<CardRank> ranks,
  required CardSuit suit,
  required List<HareegCard> jokers,
  required String? preferredCardId,
  required int maxPhysicalVariants,
}) {
  var missing = 0;
  final presentChoices = <List<HareegCard>>[];
  for (final rank in ranks) {
    final cards = _cardsForIdentity(
      cardsByIdentity,
      CardIdentity(rank: rank, suit: suit),
      preferredCardId,
    );
    if (cards.isEmpty) {
      missing += 1;
      presentChoices.add(const []);
    } else {
      presentChoices.add(cards);
    }
  }

  if (missing > jokers.length) {
    return;
  }

  for (final jokerGroup in _combinations(jokers, missing)) {
    var jokerIndex = 0;
    final choices = <List<HareegCard>>[];
    for (final cards in presentChoices) {
      if (cards.isEmpty) {
        choices.add([jokerGroup[jokerIndex]]);
        jokerIndex += 1;
      } else {
        choices.add(cards);
      }
    }
    _addMeldGroupVariants(
      addGroup: addGroup,
      choices: choices,
      maxPhysicalVariants: maxPhysicalVariants,
    );
  }
}

void _addMeldGroupVariants({
  required void Function(List<HareegCard> cards) addGroup,
  required List<List<HareegCard>> choices,
  required int maxPhysicalVariants,
}) {
  if (choices.any((cards) => cards.isEmpty)) {
    return;
  }

  var emitted = 0;
  void build(int index, List<HareegCard> selected) {
    if (emitted >= maxPhysicalVariants) {
      return;
    }
    if (index == choices.length) {
      emitted += 1;
      addGroup(List.unmodifiable(selected));
      return;
    }
    for (final card in choices[index]) {
      build(index + 1, [...selected, card]);
    }
  }

  build(0, const <HareegCard>[]);
}

List<HareegCard> _orderedJokers(
  List<HareegCard> jokers,
  String? preferredCardId,
) {
  if (preferredCardId == null || jokers.length < 2) {
    return List.unmodifiable(jokers);
  }
  final ordered = List<HareegCard>.of(jokers);
  final preferredIndex = ordered.indexWhere(
    (joker) => joker.id == preferredCardId,
  );
  if (preferredIndex > 0) {
    final preferred = ordered.removeAt(preferredIndex);
    ordered.insert(0, preferred);
  }
  return List.unmodifiable(ordered);
}

List<HareegCard> _cardsForIdentity(
  Map<String, List<HareegCard>> cardsByIdentity,
  CardIdentity identity,
  String? preferredCardId,
) {
  final cards = cardsByIdentity[identity.key];
  if (cards == null || cards.isEmpty) {
    return const [];
  }
  final ordered = List<HareegCard>.of(cards);
  if (preferredCardId != null) {
    final preferredIndex = ordered.indexWhere(
      (card) => card.id == preferredCardId,
    );
    if (preferredIndex > 0) {
      final preferred = ordered.removeAt(preferredIndex);
      ordered.insert(0, preferred);
    }
  }
  return List.unmodifiable(ordered);
}

HareegCard? _cardForIdentity(
  Map<String, List<HareegCard>> cardsByIdentity,
  CardIdentity identity,
  String? preferredCardId,
) {
  final cards = cardsByIdentity[identity.key];
  if (cards == null || cards.isEmpty) {
    return null;
  }
  if (preferredCardId != null) {
    for (final card in cards) {
      if (card.id == preferredCardId) {
        return card;
      }
    }
  }
  return cards.first;
}

Iterable<List<T>> _combinations<T>(List<T> items, int size) sync* {
  if (size < 0 || size > items.length) {
    return;
  }
  if (size == 0) {
    yield <T>[];
    return;
  }

  Iterable<List<T>> build(int start, int remaining) sync* {
    if (remaining == 0) {
      yield <T>[];
      return;
    }
    for (var index = start; index <= items.length - remaining; index += 1) {
      for (final suffix in build(index + 1, remaining - 1)) {
        yield [items[index], ...suffix];
      }
    }
  }

  yield* build(0, size);
}
