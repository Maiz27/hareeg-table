import '../models/playing_card.dart';
import 'joker_meld_assignment.dart';
import 'joker_rules.dart';
import 'meld_candidate_search.dart';
import 'meld_partition.dart';
import 'opening_rules.dart';

/// Lazy enumeration of legal multi-meld partitions for a Classic Hareeg hand.
abstract final class MeldPartitionEnumerator {
  /// Default guard against pathological hand searches.
  static const defaultSafetyCap = 2048;

  /// Returns legal partitions for [hand] without materializing all results.
  static Iterable<MeldPartition> partitionsOf(
    List<HareegCard> hand, {
    int minMelds = 1,
    int maxMelds = 5,
    String? mustUseCardId,
    int? minTotalValue,
    int safetyCap = defaultSafetyCap,
  }) sync* {
    final effectiveMinMelds = minMelds < 1 ? 1 : minMelds;
    if (hand.length < 3 ||
        maxMelds < effectiveMinMelds ||
        maxMelds <= 0 ||
        safetyCap <= 0) {
      return;
    }

    final search = _PartitionSearch(
      hand: hand,
      minMelds: effectiveMinMelds,
      maxMelds: maxMelds,
      mustUseCardId: mustUseCardId,
      minTotalValue: minTotalValue,
      safetyCap: safetyCap,
    );
    yield* search.run();
  }

  /// Returns the top [take] partitions after sorting by [comparator].
  static List<MeldPartition> topPartitions(
    List<HareegCard> hand, {
    required Comparator<MeldPartition> comparator,
    int take = 5,
    int minMelds = 1,
    int maxMelds = 5,
    String? mustUseCardId,
    int? minTotalValue,
    int safetyCap = defaultSafetyCap,
  }) {
    if (take <= 0) {
      return const [];
    }

    final partitions = partitionsOf(
      hand,
      minMelds: minMelds,
      maxMelds: maxMelds,
      mustUseCardId: mustUseCardId,
      minTotalValue: minTotalValue,
      safetyCap: safetyCap,
    ).toList()..sort(comparator);
    return List.unmodifiable(partitions.take(take));
  }
}

/// Common ranking functions for CPU meld-partition selection.
abstract final class MeldPartitionRankers {
  /// Shorter average meld length first, then higher value.
  static int byMeanMeldLengthAsc(MeldPartition left, MeldPartition right) {
    return _compareChain([
      left.meanMeldLength.compareTo(right.meanMeldLength),
      right.totalValue.compareTo(left.totalValue),
      right.meldCount.compareTo(left.meldCount),
      _stablePartitionKey(left).compareTo(_stablePartitionKey(right)),
    ]);
  }

  /// More independent melds first, then more covered cards.
  static int byCoverSurfaceDesc(MeldPartition left, MeldPartition right) {
    return _compareChain([
      right.meldCount.compareTo(left.meldCount),
      right.cardsUsed.length.compareTo(left.cardsUsed.length),
      right.totalValue.compareTo(left.totalValue),
      _stablePartitionKey(left).compareTo(_stablePartitionKey(right)),
    ]);
  }

  /// Higher opening value first.
  static int byTotalValueDesc(MeldPartition left, MeldPartition right) {
    return _compareChain([
      right.totalValue.compareTo(left.totalValue),
      right.cardsUsed.length.compareTo(left.cardsUsed.length),
      right.meldCount.compareTo(left.meldCount),
      _stablePartitionKey(left).compareTo(_stablePartitionKey(right)),
    ]);
  }
}

final class _PartitionSearch {
  _PartitionSearch({
    required List<HareegCard> hand,
    required this.minMelds,
    required this.maxMelds,
    required this.mustUseCardId,
    required this.minTotalValue,
    required this.safetyCap,
  }) : hand = List.unmodifiable(hand);

  static const _maxCandidateGroupsPerNode = 512;

  final List<HareegCard> hand;
  final int minMelds;
  final int maxMelds;
  final String? mustUseCardId;
  final int? minTotalValue;
  final int safetyCap;

  final Map<String, List<List<HareegCard>>> _candidateGroupsCache = {};
  final Map<String, List<_ResolvedPartitionMeld>> _resolvedMeldCache = {};
  final Set<String> _seen = <String>{};
  // Tracks every recursion node so [safetyCap] stops pathological searches
  // that emit few (or zero) partitions but still walk a huge tree — e.g.
  // narrow `mustUseCardId` / `minTotalValue` filters that reject most
  // branches still benefit from the cap.
  int _traversed = 0;

  Iterable<MeldPartition> run() sync* {
    yield* _search(
      available: hand,
      leftovers: const [],
      melds: const [],
      cardsUsed: const [],
      jokerAssignments: const [],
    );
  }

  Iterable<MeldPartition> _search({
    required List<HareegCard> available,
    required List<HareegCard> leftovers,
    required List<PlacedMeld> melds,
    required List<HareegCard> cardsUsed,
    required List<JokerMeldAssignment> jokerAssignments,
  }) sync* {
    _traversed += 1;
    if (_traversed >= safetyCap) {
      return;
    }

    if (melds.length >= minMelds) {
      final partition = MeldPartition(
        melds: melds,
        cardsUsed: cardsUsed,
        cardsRemaining: [...leftovers, ...available],
        jokerAssignments: jokerAssignments,
      );
      if (_passesFilters(partition) && _seen.add(_partitionKey(partition))) {
        yield partition;
        if (_traversed >= safetyCap) {
          return;
        }
      }
    }

    if (available.length < 3 || melds.length >= maxMelds) {
      return;
    }

    final anchor = available.first;
    for (final group in _candidateGroupsContainingAnchor(available, anchor)) {
      if (_traversed >= safetyCap) {
        return;
      }
      final groupIds = group.map((card) => card.id).toSet();
      final remaining = [
        for (final card in available)
          if (!groupIds.contains(card.id)) card,
      ];

      for (final resolved in _resolvedMelds(group)) {
        if (_traversed >= safetyCap) {
          return;
        }
        yield* _search(
          available: remaining,
          leftovers: leftovers,
          melds: [...melds, resolved.meld],
          cardsUsed: [...cardsUsed, ...resolved.meld.cards],
          jokerAssignments: [...jokerAssignments, ...resolved.jokerAssignments],
        );
      }
    }

    if (mustUseCardId == anchor.id) {
      return;
    }

    yield* _search(
      available: List.unmodifiable(available.skip(1)),
      leftovers: [...leftovers, anchor],
      melds: melds,
      cardsUsed: cardsUsed,
      jokerAssignments: jokerAssignments,
    );
  }

  List<List<HareegCard>> _candidateGroupsContainingAnchor(
    List<HareegCard> available,
    HareegCard anchor,
  ) {
    final cacheKey = '${anchor.id}|${_physicalGroupKey(available)}';
    final cached = _candidateGroupsCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final seen = <String>{};
    final anchoredGroups = <List<HareegCard>>[];
    final groups = ClassicHareegMeldCandidateSearch.candidateMeldGroups(
      available,
      preferredCardId: anchor.id,
      maxPhysicalVariants: _maxCandidateGroupsPerNode,
    );
    for (final group in groups) {
      if (!group.any((card) => card.id == anchor.id)) {
        continue;
      }
      final key = _physicalGroupKey(group);
      if (seen.add(key)) {
        anchoredGroups.add(group);
      }
    }
    final result = List<List<HareegCard>>.unmodifiable(anchoredGroups);
    _candidateGroupsCache[cacheKey] = result;
    return result;
  }

  List<_ResolvedPartitionMeld> _resolvedMelds(List<HareegCard> group) {
    final cacheKey = _physicalGroupKey(group);
    final cached = _resolvedMeldCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final variants = ClassicHareegJokerRules.resolveMeldVariants(
      group,
      limit: 52,
    );
    final resolved = <_ResolvedPartitionMeld>[];
    for (final variant in variants) {
      if (!variant.result.isValid) {
        continue;
      }
      final meld = PlacedMeld.fromCards(variant.cards);
      final assignments = [
        for (final entry in variant.assignments.entries)
          JokerMeldAssignment(jokerId: entry.key, identity: entry.value),
      ];
      resolved.add(
        _ResolvedPartitionMeld(
          meld: meld,
          jokerAssignments: List.unmodifiable(assignments),
        ),
      );
    }
    final result = List<_ResolvedPartitionMeld>.unmodifiable(resolved);
    _resolvedMeldCache[cacheKey] = result;
    return result;
  }

  bool _passesFilters(MeldPartition partition) {
    final requiredCard = mustUseCardId;
    if (requiredCard != null && !partition.usesCardId(requiredCard)) {
      return false;
    }
    final valueFloor = minTotalValue;
    if (valueFloor != null && partition.totalValue < valueFloor) {
      return false;
    }
    return true;
  }
}

final class _ResolvedPartitionMeld {
  const _ResolvedPartitionMeld({
    required this.meld,
    required this.jokerAssignments,
  });

  final PlacedMeld meld;
  final List<JokerMeldAssignment> jokerAssignments;
}

int _compareChain(List<int> comparisons) {
  for (final comparison in comparisons) {
    if (comparison != 0) {
      return comparison;
    }
  }
  return 0;
}

String _partitionKey(MeldPartition partition) {
  final meldKeys = partition.melds.map(_meldKey).toList()..sort();
  final remaining = partition.cardsRemaining.map((card) => card.id).toList()
    ..sort();
  return '${meldKeys.join('/')}|remaining:${remaining.join(',')}';
}

String _stablePartitionKey(MeldPartition partition) {
  final meldKeys = partition.melds.map(_meldKey).toList()..sort();
  return '${meldKeys.join('/')}|value:${partition.totalValue}';
}

String _meldKey(PlacedMeld meld) {
  return meld.cards.map(_cardIdentityKey).join(',');
}

String _cardIdentityKey(HareegCard card) {
  final identity = card.effectiveIdentity;
  return '${card.id}:${identity?.key ?? 'unresolved'}';
}

String _physicalGroupKey(List<HareegCard> group) {
  final ids = group.map((card) => card.id).toList()..sort();
  return ids.join('|');
}
