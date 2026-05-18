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

    final options = <CardIdentity>[];
    for (final identity in _allStandardIdentities()) {
      final candidate = List<HareegCard>.of(cards);
      candidate[jokerIndex] = joker.asRepresenting(identity);
      final result = ClassicHareegMeldValidator.validate(candidate);
      if (result.isValid) {
        options.add(identity);
      }
    }

    options.sort(_compareIdentity);
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

  /// Normal joker discard is blocked in every rules preset.
  static bool canDiscard(HareegCard card, {required bool isFinalDiscard}) {
    if (!card.isJoker) {
      return true;
    }
    return isFinalDiscard;
  }

  static Iterable<CardIdentity> _allStandardIdentities() sync* {
    for (final suit in CardSuit.values) {
      for (final rank in CardRank.values) {
        yield CardIdentity(rank: rank, suit: suit);
      }
    }
  }

  static int _compareIdentity(CardIdentity left, CardIdentity right) {
    final suitCompare = left.suit.index.compareTo(right.suit.index);
    if (suitCompare != 0) {
      return suitCompare;
    }
    return left.rank.order.compareTo(right.rank.order);
  }
}
