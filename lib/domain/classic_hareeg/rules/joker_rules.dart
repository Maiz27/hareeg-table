import '../models/playing_card.dart';
import 'meld_validator.dart';

/// Result of replacing a represented joker on the table.
class JokerReplacementResult {
  /// Creates a replacement result.
  const JokerReplacementResult({
    required this.tableCards,
    required this.freedJoker,
  });

  /// Updated table meld cards after replacement.
  final List<HareegCard> tableCards;

  /// Joker returned to the replacing player's hand.
  final HareegCard freedJoker;
}

/// One legal way to assign represented identities to unresolved meld jokers.
class JokerMeldResolution {
  /// Creates a resolved joker meld.
  const JokerMeldResolution({
    required this.cards,
    required this.result,
    this.assignments = const {},
  });

  /// Cards after represented identities have been applied.
  final List<HareegCard> cards;

  /// Meld validation result for [cards].
  final MeldValidationResult result;

  /// Represented identities by physical joker id.
  final Map<String, CardIdentity> assignments;
}

/// Classic Hareeg joker placement, replacement, and discard rules.
abstract final class ClassicHareegJokerRules {
  /// Returns all represented identities that make the meld legal.
  static List<CardIdentity> representationOptionsForMeld({
    required List<HareegCard> cards,
    required HareegCard joker,
  }) {
    if (!joker.isJoker) {
      throw ArgumentError('representation options require a joker card.');
    }

    final jokerIndex = cards.indexWhere((card) => card.id == joker.id);
    if (jokerIndex == -1) {
      throw ArgumentError('joker must be present in the candidate meld.');
    }

    final options =
        resolveMeldVariants(cards, limit: 52)
            .map((resolution) => resolution.assignments[joker.id])
            .whereType<CardIdentity>()
            .toSet()
            .toList()
          ..sort(_compareIdentity);
    return List.unmodifiable(options);
  }

  /// CPU deterministic represented identity choice for a joker placement.
  static CardIdentity? deterministicCpuIdentity({
    required List<HareegCard> cards,
    required HareegCard joker,
  }) {
    final options = representationOptionsForMeld(cards: cards, joker: joker);
    if (options.isEmpty) {
      return null;
    }
    return options.first;
  }

  /// Returns legal represented-joker variants for a single meld candidate.
  static List<JokerMeldResolution> resolveMeldVariants(
    List<HareegCard> cards, {
    Map<String, CardIdentity>? jokerIdentities,
    int limit = 5,
  }) {
    if (limit <= 0) {
      return const [];
    }

    final direct = ClassicHareegMeldValidator.validate(cards);
    if (direct.isValid &&
        (jokerIdentities == null || jokerIdentities.isEmpty)) {
      return [
        JokerMeldResolution(cards: List.unmodifiable(cards), result: direct),
      ];
    }

    final unresolvedJokers = cards
        .where((card) => card.isJoker && card.representedIdentity == null)
        .toList(growable: false);
    if (unresolvedJokers.isEmpty) {
      return const [];
    }

    final explicitIdentities =
        jokerIdentities ?? const <String, CardIdentity>{};
    if (explicitIdentities.isNotEmpty) {
      final unresolvedIds = unresolvedJokers.map((joker) => joker.id).toSet();
      if (explicitIdentities.keys
              .toSet()
              .difference(unresolvedIds)
              .isNotEmpty ||
          unresolvedIds
              .difference(explicitIdentities.keys.toSet())
              .isNotEmpty) {
        return const [];
      }
      final explicit = _resolveWithAssignments(cards, explicitIdentities);
      return explicit.result.isValid ? [explicit] : const [];
    }

    final variants = <JokerMeldResolution>[];
    final seen = <String>{};
    void addVariant(Map<String, CardIdentity> assignments) {
      if (variants.length >= limit) {
        return;
      }
      final resolved = _resolveWithAssignments(cards, assignments);
      if (!resolved.result.isValid) {
        return;
      }
      final key = _visualMeldKey(resolved.cards);
      if (seen.add(key)) {
        variants.add(resolved);
      }
    }

    _addSetVariants(
      cards: cards,
      jokers: unresolvedJokers,
      addVariant: addVariant,
      canAddMore: () => variants.length < limit,
    );
    _addSequenceVariants(
      cards: cards,
      jokers: unresolvedJokers,
      addVariant: addVariant,
      canAddMore: () => variants.length < limit,
    );
    return List.unmodifiable(variants);
  }

  /// Whether an opened player may replace a represented table joker.
  static bool canReplaceJoker({
    required bool playerOpened,
    required List<HareegCard> tableCards,
    required HareegCard replacementCard,
  }) {
    if (!playerOpened) {
      return false;
    }

    final replacementIdentity = replacementCard.identity;
    if (replacementIdentity == null) {
      return false;
    }

    return tableCards.any((card) {
      return card.isJoker && card.representedIdentity == replacementIdentity;
    });
  }

  /// Replaces a represented table joker and returns the freed joker.
  static JokerReplacementResult replaceJoker({
    required bool playerOpened,
    required List<HareegCard> tableCards,
    required HareegCard replacementCard,
  }) {
    if (!canReplaceJoker(
      playerOpened: playerOpened,
      tableCards: tableCards,
      replacementCard: replacementCard,
    )) {
      throw StateError('That joker cannot be replaced by this player/card.');
    }

    final replacementIdentity = replacementCard.identity;
    final updated = <HareegCard>[];
    HareegCard? freedJoker;

    for (final card in tableCards) {
      if (freedJoker == null &&
          card.isJoker &&
          card.representedIdentity == replacementIdentity) {
        freedJoker = card.withoutRepresentation();
        updated.add(replacementCard);
      } else {
        updated.add(card);
      }
    }

    return JokerReplacementResult(
      tableCards: List.unmodifiable(updated),
      freedJoker: freedJoker!,
    );
  }

  /// Normal joker discard is blocked in every strictness tier.
  static bool canDiscard(HareegCard card, {required bool isFinalDiscard}) {
    if (!card.isJoker) {
      return true;
    }
    return isFinalDiscard;
  }

  static int _compareIdentity(CardIdentity left, CardIdentity right) {
    final suitCompare = left.suit.index.compareTo(right.suit.index);
    if (suitCompare != 0) {
      return suitCompare;
    }
    return left.rank.order.compareTo(right.rank.order);
  }

  static JokerMeldResolution _resolveWithAssignments(
    List<HareegCard> cards,
    Map<String, CardIdentity> assignments,
  ) {
    final resolvedCards = cards
        .map((card) {
          final identity = assignments[card.id];
          if (identity == null) {
            return card;
          }
          if (!card.isJoker || card.representedIdentity != null) {
            return card;
          }
          return card.asRepresenting(identity);
        })
        .toList(growable: false);
    final result = ClassicHareegMeldValidator.validate(resolvedCards);
    return JokerMeldResolution(
      cards: List.unmodifiable(resolvedCards),
      result: result,
      assignments: Map.unmodifiable(assignments),
    );
  }

  static void _addSetVariants({
    required List<HareegCard> cards,
    required List<HareegCard> jokers,
    required void Function(Map<String, CardIdentity> assignments) addVariant,
    required bool Function() canAddMore,
  }) {
    if (cards.length > CardSuit.values.length) {
      return;
    }

    final known = _knownIdentities(cards);
    final knownRanks = known.map((identity) => identity.rank).toSet();
    final candidateRanks = knownRanks.isEmpty
        ? CardRank.values
        : knownRanks.length == 1
        ? [knownRanks.single]
        : const <CardRank>[];

    for (final rank in candidateRanks) {
      if (!canAddMore()) {
        return;
      }
      final usedSuits = <CardSuit>{};
      var invalid = false;
      for (final identity in known) {
        if (identity.rank != rank || !usedSuits.add(identity.suit)) {
          invalid = true;
          break;
        }
      }
      if (invalid) {
        continue;
      }

      final availableSuits = CardSuit.values
          .where((suit) => !usedSuits.contains(suit))
          .toList(growable: false);
      if (availableSuits.length < jokers.length) {
        continue;
      }
      for (final suits in _combinations(availableSuits, jokers.length)) {
        if (!canAddMore()) {
          return;
        }
        addVariant({
          for (var index = 0; index < jokers.length; index += 1)
            jokers[index].id: CardIdentity(rank: rank, suit: suits[index]),
        });
      }
    }
  }

  static void _addSequenceVariants({
    required List<HareegCard> cards,
    required List<HareegCard> jokers,
    required void Function(Map<String, CardIdentity> assignments) addVariant,
    required bool Function() canAddMore,
  }) {
    final known = _knownIdentities(cards);
    final knownSuits = known.map((identity) => identity.suit).toSet();
    final candidateSuits = knownSuits.isEmpty
        ? CardSuit.values
        : knownSuits.length == 1
        ? [knownSuits.single]
        : const <CardSuit>[];

    for (final suit in candidateSuits) {
      for (final ranks in _sequenceRankWindows(cards.length)) {
        if (!canAddMore()) {
          return;
        }
        final available = ranks.toList();
        var invalid = false;
        for (final identity in known) {
          if (identity.suit != suit || !available.remove(identity.rank)) {
            invalid = true;
            break;
          }
        }
        if (invalid || available.length != jokers.length) {
          continue;
        }
        addVariant({
          for (var index = 0; index < jokers.length; index += 1)
            jokers[index].id: CardIdentity(rank: available[index], suit: suit),
        });
      }
    }
  }

  static List<CardIdentity> _knownIdentities(List<HareegCard> cards) {
    return cards
        .map((card) => card.effectiveIdentity)
        .whereType<CardIdentity>()
        .toList(growable: false);
  }

  static Iterable<List<CardRank>> _sequenceRankWindows(int length) sync* {
    if (length < 3 || length > CardRank.values.length) {
      return;
    }

    for (var start = 0; start <= CardRank.values.length - length; start += 1) {
      yield CardRank.values.skip(start).take(length).toList(growable: false);
    }

    final highAceRanks = [
      CardRank.two,
      CardRank.three,
      CardRank.four,
      CardRank.five,
      CardRank.six,
      CardRank.seven,
      CardRank.eight,
      CardRank.nine,
      CardRank.ten,
      CardRank.jack,
      CardRank.queen,
      CardRank.king,
      CardRank.ace,
    ];
    final highAceStart = highAceRanks.length - length;
    if (highAceStart >= 0) {
      yield highAceRanks.skip(highAceStart).toList(growable: false);
    }
  }

  static Iterable<List<T>> _combinations<T>(List<T> values, int size) sync* {
    if (size < 0 || size > values.length) {
      return;
    }
    if (size == 0) {
      yield <T>[];
      return;
    }

    Iterable<List<T>> choose(int start, int remaining) sync* {
      if (remaining == 0) {
        yield <T>[];
        return;
      }
      for (var index = start; index <= values.length - remaining; index += 1) {
        for (final tail in choose(index + 1, remaining - 1)) {
          yield [values[index], ...tail];
        }
      }
    }

    yield* choose(0, size);
  }

  static String _visualMeldKey(List<HareegCard> cards) {
    final identities =
        cards
            .map((card) => card.effectiveIdentity)
            .whereType<CardIdentity>()
            .toList()
          ..sort(_compareIdentity);
    return identities.map((identity) => identity.key).join('|');
  }
}
