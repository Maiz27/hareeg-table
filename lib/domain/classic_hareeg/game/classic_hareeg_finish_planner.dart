import '../models/playing_card.dart';
import '../rules/opening_rules.dart';
import 'classic_hareeg_table_play_planner.dart';

/// Exact-cover helper for proving whether a hand can finish.
///
/// Finish checks are a hot path for blocking-tier Fifty prompts and
/// empty-stock draw decisions. The controller asks the same card set "what if
/// this card is the final discard?" up to fourteen times; this planner builds
/// valid meld candidates once, then reuses subset memoization across those
/// final-discard attempts.
class ClassicHareegFinishPlanner {
  /// Creates a finish planner for one candidate card set.
  ClassicHareegFinishPlanner(List<HareegCard> cards)
    : _cards = List.unmodifiable(cards),
      _fullMask = cards.isEmpty ? 0 : (1 << cards.length) - 1 {
    for (var index = 0; index < _cards.length; index += 1) {
      _bitByCardId[_cards[index].id] = 1 << index;
    }
    _buildMeldCandidates();
  }

  final List<HareegCard> _cards;
  final int _fullMask;
  final Map<String, int> _bitByCardId = {};
  final Map<int, List<_FinishMeldCandidate>> _candidatesByFirstBit = {};
  final Map<int, List<PlacedMeld>?> _partitionMemo = {};
  final Set<int> _candidateMasks = {};

  /// Whether any valid single meld can contain [cardId].
  bool hasValidMeldContaining(String cardId) {
    final bit = _bitByCardId[cardId];
    if (bit == null) {
      return false;
    }
    for (final mask in _candidateMasks) {
      if ((mask & bit) != 0) {
        return true;
      }
    }
    return false;
  }

  /// Partitions every card except [finalDiscard] into legal melds.
  List<PlacedMeld>? partitionWithout(HareegCard finalDiscard) {
    final discardBit = _bitByCardId[finalDiscard.id];
    if (discardBit == null) {
      return null;
    }
    return _partition(_fullMask ^ discardBit);
  }

  void _buildMeldCandidates() {
    if (_cards.length < 3 || _cards.length > 20) {
      return;
    }

    for (var mask = 1; mask <= _fullMask; mask += 1) {
      if (_bitCount(mask) < 3) {
        continue;
      }
      final cards = _cardsForMask(mask);
      if (!_couldBeMeld(cards)) {
        continue;
      }
      final resolved = ClassicHareegTablePlayPlanner.resolveMeldCards(cards);
      if (!resolved.result.isValid) {
        continue;
      }
      final candidate = _FinishMeldCandidate(
        mask: mask,
        meld: PlacedMeld.fromCards(resolved.cards),
        cardCount: _bitCount(mask),
      );
      _candidateMasks.add(mask);
      var bits = mask;
      while (bits != 0) {
        final bit = _lowestBit(bits);
        _candidatesByFirstBit.putIfAbsent(bit, () => []).add(candidate);
        bits ^= bit;
      }
    }

    for (final candidates in _candidatesByFirstBit.values) {
      candidates.sort((left, right) {
        final countCompare = right.cardCount.compareTo(left.cardCount);
        if (countCompare != 0) {
          return countCompare;
        }
        return left.mask.compareTo(right.mask);
      });
    }
  }

  List<PlacedMeld>? _partition(int targetMask) {
    if (targetMask == 0) {
      return const [];
    }
    if (_bitCount(targetMask) < 3) {
      return null;
    }
    if (_partitionMemo.containsKey(targetMask)) {
      return _partitionMemo[targetMask];
    }

    final firstBit = _lowestBit(targetMask);
    final candidates =
        _candidatesByFirstBit[firstBit] ?? const <_FinishMeldCandidate>[];
    for (final candidate in candidates) {
      if ((candidate.mask & targetMask) != candidate.mask) {
        continue;
      }
      final rest = _partition(targetMask ^ candidate.mask);
      if (rest != null) {
        final result = [candidate.meld, ...rest];
        _partitionMemo[targetMask] = result;
        return result;
      }
    }

    _partitionMemo[targetMask] = null;
    return null;
  }

  List<HareegCard> _cardsForMask(int mask) {
    final cards = <HareegCard>[];
    for (var index = 0; index < _cards.length; index += 1) {
      if ((mask & (1 << index)) != 0) {
        cards.add(_cards[index]);
      }
    }
    return cards;
  }

  static int _lowestBit(int value) => value & -value;

  static int _bitCount(int value) {
    var count = 0;
    var bits = value;
    while (bits != 0) {
      bits &= bits - 1;
      count += 1;
    }
    return count;
  }

  static bool _couldBeMeld(List<HareegCard> cards) {
    if (cards.length < 3) {
      return false;
    }

    var unresolvedJokerCount = 0;
    final identities = <CardIdentity>[];
    for (final card in cards) {
      final identity = card.effectiveIdentity;
      if (identity != null) {
        identities.add(identity);
        continue;
      }
      if (!card.isJoker) {
        return false;
      }
      unresolvedJokerCount += 1;
    }

    if (unresolvedJokerCount > 2 || identities.isEmpty) {
      return false;
    }
    return _couldBeSameRankSet(
          cardCount: cards.length,
          unresolvedJokerCount: unresolvedJokerCount,
          identities: identities,
        ) ||
        _couldBeSameSuitSequence(
          cardCount: cards.length,
          unresolvedJokerCount: unresolvedJokerCount,
          identities: identities,
        );
  }

  static bool _couldBeSameRankSet({
    required int cardCount,
    required int unresolvedJokerCount,
    required List<CardIdentity> identities,
  }) {
    if (cardCount > CardSuit.values.length) {
      return false;
    }

    final rank = identities.first.rank;
    if (identities.any((identity) => identity.rank != rank)) {
      return false;
    }

    final suits = identities.map((identity) => identity.suit).toSet();
    if (suits.length != identities.length) {
      return false;
    }
    return CardSuit.values.length - suits.length >= unresolvedJokerCount;
  }

  static bool _couldBeSameSuitSequence({
    required int cardCount,
    required int unresolvedJokerCount,
    required List<CardIdentity> identities,
  }) {
    if (cardCount > CardRank.values.length) {
      return false;
    }

    final suit = identities.first.suit;
    if (identities.any((identity) => identity.suit != suit)) {
      return false;
    }

    final ranks = identities.map((identity) => identity.rank).toSet();
    if (ranks.length != identities.length) {
      return false;
    }

    return _hasSequenceWindow(
          ranks: ranks,
          cardCount: cardCount,
          unresolvedJokerCount: unresolvedJokerCount,
          rankOrder: CardRank.values,
        ) ||
        _hasSequenceWindow(
          ranks: ranks,
          cardCount: cardCount,
          unresolvedJokerCount: unresolvedJokerCount,
          rankOrder: [
            for (final rank in CardRank.values)
              if (rank != CardRank.ace) rank,
            CardRank.ace,
          ],
        );
  }

  static bool _hasSequenceWindow({
    required Set<CardRank> ranks,
    required int cardCount,
    required int unresolvedJokerCount,
    required List<CardRank> rankOrder,
  }) {
    if (cardCount > rankOrder.length) {
      return false;
    }

    for (var start = 0; start <= rankOrder.length - cardCount; start += 1) {
      final window = rankOrder.skip(start).take(cardCount).toSet();
      if (!window.containsAll(ranks)) {
        continue;
      }
      if (window.length - ranks.length <= unresolvedJokerCount) {
        return true;
      }
    }
    return false;
  }
}

class _FinishMeldCandidate {
  const _FinishMeldCandidate({
    required this.mask,
    required this.meld,
    required this.cardCount,
  });

  final int mask;
  final PlacedMeld meld;
  final int cardCount;
}
