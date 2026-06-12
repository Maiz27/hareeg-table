import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../rules/cover_rules.dart';
import '../rules/opening_rules.dart';
import 'classic_hareeg_table_play_planner.dart';

/// One table meld a finish plan may extend with covers.
class ClassicHareegFinishCoverTarget {
  /// Creates a cover target for an existing table meld.
  const ClassicHareegFinishCoverTarget({
    required this.owner,
    required this.meldIndex,
    required this.meldCards,
  });

  /// Every meld in [tableMelds] as a cover target — the single way cover
  /// targets are derived, shared by the controller and the CPU layer.
  static List<ClassicHareegFinishCoverTarget> allFrom(
    Map<PlayerSeat, List<PlacedMeld>> tableMelds,
  ) {
    return [
      for (final entry in tableMelds.entries)
        for (var index = 0; index < entry.value.length; index += 1)
          ClassicHareegFinishCoverTarget(
            owner: entry.key,
            meldIndex: index,
            meldCards: entry.value[index].cards,
          ),
    ];
  }

  /// Seat that owns the table meld.
  final PlayerSeat owner;

  /// Index of the meld in the owner's table lane.
  final int meldIndex;

  /// Cards currently forming the table meld.
  final List<HareegCard> meldCards;
}

/// One planned cover placement inside a finish plan.
class ClassicHareegFinishPlanCover {
  /// Creates a planned cover placement.
  const ClassicHareegFinishPlanCover({
    required this.targetSeat,
    required this.meldIndex,
    required this.cards,
  });

  /// Seat that owns the meld being extended.
  final PlayerSeat targetSeat;

  /// Index of the meld in the owner's table lane at plan time.
  final int meldIndex;

  /// Cover cards in legal application order, jokers resolved.
  final List<HareegCard> cards;
}

/// Melds plus cover placements proving one final-discard choice.
typedef ClassicHareegFinishPlanParts = ({
  List<PlacedMeld> melds,
  List<ClassicHareegFinishPlanCover> covers,
});

/// Exact-cover helper for proving whether a hand can finish.
///
/// Finish checks are a hot path for blocking-tier Fifty prompts and
/// empty-stock draw decisions. The controller asks the same card set "what if
/// this card is the final discard?" up to fourteen times; this planner builds
/// valid meld candidates once, then reuses subset memoization across those
/// final-discard attempts.
///
/// When [coverTargets] are supplied the planner also routes finishes through
/// covers: cards that legally extend existing table melds (including
/// cover-after-cover chains on the same meld) count as used. Cover-routed
/// plans for an unopened seat are only valid when the plan's fresh melds
/// independently reach [coverPlanMinimumMeldValue] (the table's current
/// opening requirement) — a melds-only perfect hand stays exempt.
class ClassicHareegFinishPlanner {
  /// Creates a finish planner for one candidate card set.
  ///
  /// [coverDisallowedCardIds] bars specific cards from being used as cover
  /// extensions, forcing them into fresh melds for any complete plan. The
  /// controller uses this to check *pickup* realizability: a taken discard that
  /// an unopened seat can only place via a cover is unplayable (covers need a
  /// prior opening, but the taken card must be used immediately), so barring it
  /// from covers reports a finish only when the discard genuinely melds.
  ClassicHareegFinishPlanner(
    List<HareegCard> cards, {
    List<ClassicHareegFinishCoverTarget> coverTargets = const [],
    int? coverPlanMinimumMeldValue,
    Set<String> coverDisallowedCardIds = const {},
  }) : _cards = List.unmodifiable(cards),
       _fullMask = cards.isEmpty ? 0 : (1 << cards.length) - 1,
       _coverPlanMinimumMeldValue = coverPlanMinimumMeldValue,
       _coverDisallowedCardIds = coverDisallowedCardIds {
    for (var index = 0; index < _cards.length; index += 1) {
      _bitByCardId[_cards[index].id] = 1 << index;
    }
    _buildMeldCandidates();
    _buildCoverExtensions(coverTargets);
  }

  final List<HareegCard> _cards;
  final int _fullMask;
  final int? _coverPlanMinimumMeldValue;
  final Set<String> _coverDisallowedCardIds;
  final Map<String, int> _bitByCardId = {};
  final Map<int, List<_FinishMeldCandidate>> _candidatesByFirstBit = {};
  final Map<int, List<PlacedMeld>?> _partitionMemo = {};
  final Set<int> _candidateMasks = {};
  final List<_CoverTargetExtensions> _extensionsByTarget = [];
  int _extensionUnionMask = 0;

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

  /// Whether [cardId] can be used by any finish route — a fresh meld or a
  /// cover extension of a table meld.
  bool hasFinishUseContaining(String cardId) {
    if (hasValidMeldContaining(cardId)) {
      return true;
    }
    final bit = _bitByCardId[cardId];
    return bit != null && (_extensionUnionMask & bit) != 0;
  }

  /// Partitions every card except [finalDiscard] into legal melds.
  List<PlacedMeld>? partitionWithout(HareegCard finalDiscard) {
    final discardBit = _bitByCardId[finalDiscard.id];
    if (discardBit == null) {
      return null;
    }
    return _partition(_fullMask ^ discardBit);
  }

  /// Plans melds plus covers using every card except [finalDiscard].
  ///
  /// Prefers a melds-only partition (the perfect-hand shape, exempt from the
  /// opening constraint); otherwise searches cover-routed plans where each
  /// cover target receives at most one extension chain.
  ClassicHareegFinishPlanParts? planWithout(HareegCard finalDiscard) {
    final discardBit = _bitByCardId[finalDiscard.id];
    if (discardBit == null) {
      return null;
    }
    final targetMask = _fullMask ^ discardBit;
    final meldsOnly = _partition(targetMask);
    if (meldsOnly != null) {
      return (melds: meldsOnly, covers: const []);
    }
    if (_extensionsByTarget.isEmpty) {
      return null;
    }
    return _searchCoverPlan(targetMask);
  }

  ClassicHareegFinishPlanParts? _searchCoverPlan(int targetMask) {
    final chosen = <ClassicHareegFinishPlanCover>[];
    final visitedFailures = <int>{};
    ClassicHareegFinishPlanParts? found;

    bool dfs(int targetIndex, int remainingMask) {
      if (found != null) {
        return true;
      }
      if (targetIndex == _extensionsByTarget.length) {
        if (chosen.isEmpty) {
          // Melds-only was already attempted by the caller.
          return false;
        }
        final melds = _partition(remainingMask);
        if (melds == null) {
          return false;
        }
        if (_coverPlanMinimumMeldValue != null) {
          final meldValue = melds.fold<int>(
            0,
            (total, meld) => total + meld.totalValue,
          );
          if (meldValue < _coverPlanMinimumMeldValue) {
            return false;
          }
        }
        found = (
          melds: melds,
          covers: List<ClassicHareegFinishPlanCover>.unmodifiable(chosen),
        );
        return true;
      }

      final failureKey = (targetIndex << _cards.length) | remainingMask;
      if (visitedFailures.contains(failureKey)) {
        return false;
      }

      // Option 1: leave this target uncovered.
      if (dfs(targetIndex + 1, remainingMask)) {
        return true;
      }

      final target = _extensionsByTarget[targetIndex];
      for (final extension in target.extensions) {
        if ((extension.mask & remainingMask) != extension.mask) {
          continue;
        }
        chosen.add(
          ClassicHareegFinishPlanCover(
            targetSeat: target.owner,
            meldIndex: target.meldIndex,
            cards: extension.orderedCards,
          ),
        );
        if (dfs(targetIndex + 1, remainingMask ^ extension.mask)) {
          return true;
        }
        chosen.removeLast();
      }

      visitedFailures.add(failureKey);
      return false;
    }

    dfs(0, targetMask);
    return found;
  }

  void _buildCoverExtensions(List<ClassicHareegFinishCoverTarget> targets) {
    for (final target in targets) {
      final extensions = <int, List<HareegCard>>{};

      void grow(List<HareegCard> meld, int usedMask, List<HareegCard> ordered) {
        if (extensions.length >= _maxExtensionsPerTarget) {
          return;
        }
        for (var index = 0; index < _cards.length; index += 1) {
          final bit = 1 << index;
          if ((usedMask & bit) != 0) {
            continue;
          }
          if (_coverDisallowedCardIds.contains(_cards[index].id)) {
            // Barred from cover use (e.g. a taken discard an unopened seat must
            // meld), so it can never extend a table meld in this plan.
            continue;
          }
          final extension = ClassicHareegCoverRules.resolveCoverExtension(
            tableMeld: meld,
            candidate: _cards[index],
          );
          if (extension == null) {
            continue;
          }
          final nextMask = usedMask | bit;
          if (extensions.containsKey(nextMask)) {
            continue;
          }
          final nextOrdered = [...ordered, extension.card];
          extensions[nextMask] = nextOrdered;
          grow(extension.extendedMeld, nextMask, nextOrdered);
        }
      }

      grow(target.meldCards, 0, const []);
      if (extensions.isEmpty) {
        continue;
      }
      _extensionsByTarget.add(
        _CoverTargetExtensions(
          owner: target.owner,
          meldIndex: target.meldIndex,
          extensions: [
            for (final entry in extensions.entries)
              _CoverExtensionCandidate(
                mask: entry.key,
                orderedCards: List.unmodifiable(entry.value),
              ),
          ],
        ),
      );
      for (final mask in extensions.keys) {
        _extensionUnionMask |= mask;
      }
    }
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
      var resolved = ClassicHareegTablePlayPlanner.resolveMeldCards(cards);
      if (!resolved.result.isValid) {
        // An AMBIGUOUS joker (several legal identities, e.g. Q-K-joker as J
        // or A) makes resolveMeldCards demand a choice — right for the human
        // action surface, fatal for a finish PROOF: any legal identity
        // proves the meld placeable, so rejecting the candidate hid whole
        // finishes (and their Fifty claims) whenever a joker meld had more
        // than one reading. Resolve to the highest-value variant so an
        // unopened seat's fresh-meld value check sees its best proof.
        ClassicHareegResolvedMeldCards? best;
        for (final variant
            in ClassicHareegTablePlayPlanner.resolveMeldCardVariants(cards)) {
          if (!variant.result.isValid) {
            continue;
          }
          if (best == null || variant.result.value > best.result.value) {
            best = variant;
          }
        }
        if (best == null) {
          continue;
        }
        resolved = best;
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

// Cap on enumerated extension chains per table meld. Run extensions grow from
// both sequence ends and joker covers fan out, so an uncapped walk could
// explode on joker-heavy hands; real chains stay far below this.
const _maxExtensionsPerTarget = 64;

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

class _CoverTargetExtensions {
  const _CoverTargetExtensions({
    required this.owner,
    required this.meldIndex,
    required this.extensions,
  });

  final PlayerSeat owner;
  final int meldIndex;
  final List<_CoverExtensionCandidate> extensions;
}

class _CoverExtensionCandidate {
  const _CoverExtensionCandidate({
    required this.mask,
    required this.orderedCards,
  });

  final int mask;
  final List<HareegCard> orderedCards;
}
