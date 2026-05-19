import '../models/playing_card.dart';
import 'meld_validator.dart';

/// Result of checking discard legality for a cover card.
class CoverDiscardResult {
  /// Creates a cover discard result.
  const CoverDiscardResult({required this.canDiscard, required this.message});

  /// Whether the card may be discarded in the current context.
  final bool canDiscard;

  /// Player-facing explanation.
  final String message;
}

/// Classic Hareeg cover detection and discard restriction rules.
abstract final class ClassicHareegCoverRules {
  /// Whether a card can legally extend a table meld right now.
  static bool isCover({
    required List<HareegCard> tableMeld,
    required HareegCard candidate,
  }) {
    final candidateIdentity = candidate.effectiveIdentity;
    if (candidateIdentity == null || tableMeld.length < 3) {
      return false;
    }

    final current = ClassicHareegMeldValidator.validate(tableMeld);
    if (!current.isValid) {
      return false;
    }

    return switch (current.type) {
      MeldType.set => _isSetCover(tableMeld, candidateIdentity),
      MeldType.sequence => _isSequenceCover(tableMeld, candidateIdentity),
      null => false,
    };
  }

  /// Returns whether any table meld can receive this card as a cover.
  static bool isAnyCover({
    required Iterable<List<HareegCard>> tableMelds,
    required HareegCard candidate,
  }) {
    return tableMelds.any((meld) {
      return isCover(tableMeld: meld, candidate: candidate);
    });
  }

  /// Opened players may place covers; unopened players are trapped with them.
  static bool canPlayCover({required bool playerOpened}) {
    return playerOpened;
  }

  /// Places a cover and returns the extended meld.
  static List<HareegCard> placeCover({
    required bool playerOpened,
    required List<HareegCard> tableMeld,
    required HareegCard candidate,
  }) {
    if (!playerOpened) {
      throw StateError('Unopened players cannot play covers yet.');
    }
    if (!isCover(tableMeld: tableMeld, candidate: candidate)) {
      throw StateError('Card is not a current cover for this meld.');
    }

    return List.unmodifiable([...tableMeld, candidate]);
  }

  /// Checks normal cover discard restriction.
  static CoverDiscardResult canDiscard({
    required Iterable<List<HareegCard>> tableMelds,
    required HareegCard candidate,
    required bool isFinalDiscard,
  }) {
    if (isFinalDiscard) {
      return const CoverDiscardResult(
        canDiscard: true,
        message: 'Final discard may use a cover.',
      );
    }

    if (isAnyCover(tableMelds: tableMelds, candidate: candidate)) {
      return const CoverDiscardResult(
        canDiscard: false,
        message: 'This card is a cover and cannot be discarded normally.',
      );
    }

    return const CoverDiscardResult(
      canDiscard: true,
      message: 'Card can be discarded.',
    );
  }

  static bool _isSetCover(
    List<HareegCard> tableMeld,
    CardIdentity candidateIdentity,
  ) {
    final identities = tableMeld
        .map((card) => card.effectiveIdentity)
        .whereType<CardIdentity>()
        .toList();
    if (identities.any((identity) => identity.rank != candidateIdentity.rank)) {
      return false;
    }

    final suits = identities.map((identity) => identity.suit).toSet();
    return !suits.contains(candidateIdentity.suit);
  }

  static bool _isSequenceCover(
    List<HareegCard> tableMeld,
    CardIdentity candidateIdentity,
  ) {
    final identities = tableMeld
        .map((card) => card.effectiveIdentity)
        .whereType<CardIdentity>()
        .toList();
    if (identities.any((identity) => identity.suit != candidateIdentity.suit)) {
      return false;
    }

    final lowOrders = identities.map((identity) => identity.rank.order).toList()
      ..sort();
    final highOrders = identities.map((identity) {
      return identity.rank == CardRank.ace ? 14 : identity.rank.order;
    }).toList()..sort();

    final candidateLow = candidateIdentity.rank.order;
    final candidateHigh = candidateIdentity.rank == CardRank.ace
        ? 14
        : candidateIdentity.rank.order;

    if (_isConsecutive(lowOrders)) {
      return candidateLow == lowOrders.first - 1 ||
          candidateLow == lowOrders.last + 1;
    }

    if (_isConsecutive(highOrders)) {
      return candidateHigh == highOrders.first - 1 ||
          candidateHigh == highOrders.last + 1;
    }

    return false;
  }

  static bool _isConsecutive(List<int> orders) {
    for (var index = 1; index < orders.length; index += 1) {
      if (orders[index] != orders[index - 1] + 1) {
        return false;
      }
    }
    return true;
  }
}
