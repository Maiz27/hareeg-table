import '../models/playing_card.dart';
import 'meld_validator.dart';

/// Returns the canonical display order for the cards of a validated meld.
///
/// The order is presentation-oriented, not rule-affecting: the meld validator
/// accepts the same cards regardless of position. UI surfaces and persisted
/// `PlacedMeld` snapshots both consult this so the same meld renders the same
/// way wherever it appears (hand picker, table lane, suggestion rack, saved
/// match resume).
///
/// Sequences render low-to-high, with aces treated as high when the rest of
/// the run requires it. Sets interleave black and red suits for 3-card and
/// 4-card mixed-colour groups so duplicate suits don't sit next to each
/// other. When a meld doesn't fit either pattern (or fails validation), the
/// original order is preserved.
abstract final class MeldCardOrdering {
  /// Returns [cards] sorted into canonical display order for their meld type.
  static List<HareegCard> forCards(List<HareegCard> cards) {
    final result = ClassicHareegMeldValidator.validate(cards);
    if (!result.isValid || result.type == null) {
      return List<HareegCard>.of(cards);
    }

    return switch (result.type!) {
      MeldType.sequence => _orderedSequenceCards(cards),
      MeldType.set => _orderedSetCards(cards),
    };
  }
}

List<HareegCard> _orderedSequenceCards(List<HareegCard> cards) {
  final copy = List<HareegCard>.of(cards);
  final highAce = _usesHighAceSequence(cards);
  copy.sort((left, right) {
    final leftIdentity = left.effectiveIdentity!;
    final rightIdentity = right.effectiveIdentity!;
    final rankCompare = _sequenceRankOrder(
      leftIdentity.rank,
      highAce: highAce,
    ).compareTo(_sequenceRankOrder(rightIdentity.rank, highAce: highAce));
    if (rankCompare != 0) return rankCompare;
    return left.deckIndex.compareTo(right.deckIndex);
  });
  return copy;
}

int _sequenceRankOrder(CardRank rank, {required bool highAce}) {
  if (highAce && rank == CardRank.ace) {
    return 14;
  }
  return rank.order;
}

bool _usesHighAceSequence(List<HareegCard> cards) {
  final ranks = cards
      .map((card) => card.effectiveIdentity!.rank)
      .toList(growable: false);
  final lowOrders = ranks.map((rank) => rank.order).toList()..sort();
  if (_isConsecutive(lowOrders)) {
    return false;
  }

  final highOrders =
      ranks.map((rank) => rank == CardRank.ace ? 14 : rank.order).toList()
        ..sort();
  return _isConsecutive(highOrders);
}

bool _isConsecutive(List<int> orders) {
  for (var index = 1; index < orders.length; index += 1) {
    if (orders[index] != orders[index - 1] + 1) {
      return false;
    }
  }
  return true;
}

List<HareegCard> _orderedSetCards(List<HareegCard> cards) {
  final black =
      cards.where((card) => !_isRedSuit(card.effectiveIdentity!.suit)).toList()
        ..sort(_compareSetSuitWithinColor);
  final red =
      cards.where((card) => _isRedSuit(card.effectiveIdentity!.suit)).toList()
        ..sort(_compareSetSuitWithinColor);

  if (black.length == 2 && red.length == 2) {
    return [black[0], red[0], black[1], red[1]];
  }
  if (black.length == 1 && red.length == 2) {
    return [red[0], black[0], red[1]];
  }
  if (black.length == 2 && red.length == 1) {
    return [black[0], red[0], black[1]];
  }

  final copy = List<HareegCard>.of(cards);
  copy.sort(_compareSetSuitWithinColor);
  return copy;
}

bool _isRedSuit(CardSuit suit) {
  return suit == CardSuit.diamonds || suit == CardSuit.hearts;
}

int _compareSetSuitWithinColor(HareegCard left, HareegCard right) {
  final leftIdentity = left.effectiveIdentity!;
  final rightIdentity = right.effectiveIdentity!;
  final suitCompare = _setSuitOrder(
    leftIdentity.suit,
  ).compareTo(_setSuitOrder(rightIdentity.suit));
  if (suitCompare != 0) return suitCompare;
  return left.deckIndex.compareTo(right.deckIndex);
}

int _setSuitOrder(CardSuit suit) {
  return switch (suit) {
    CardSuit.clubs => 0,
    CardSuit.diamonds => 1,
    CardSuit.spades => 2,
    CardSuit.hearts => 3,
  };
}
