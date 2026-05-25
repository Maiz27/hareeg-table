import '../../domain/classic_hareeg/models/playing_card.dart';
import '../../domain/classic_hareeg/rules/opening_rules.dart';
import 'cpu_move_plan.dart';
import 'cpu_move_plan_pipeline.dart';
import 'cpu_observation.dart';
import 'skilled_cpu_move_planner.dart';

/// Expert CPU planner with offensive Fifty posture and opponent-aware defence.
///
/// This tier is a thin adapter — every stage of `plan()` runs in
/// [CpuMovePlanPipeline]; this class only supplies the per-stage scoring weights
/// for Expert's posture (opening-band push, interior-joker preference,
/// opponent-threat discard model, finish-gated joker replacement).
class ExpertCpuMovePlanner implements CpuMovePlanner {
  /// Creates an expert CPU move planner.
  const ExpertCpuMovePlanner();

  static const _partitionLimit = 256;
  static const _fiftyHoldStockFloor = 8;
  static const _fiftyHoldHandValueFloor = 25;
  static const _highRiskScoreFloor = 25;
  static const _eliminationTargetScoreFloor = 28;
  static const _thinStockCount = 8;
  static const _freshStockCount = 30;
  static const _benchmarkTarget = 75;
  static const _benchmarkFloor = 70;
  static const _benchmarkCeiling = 80;

  @override
  ClassicHareegCpuMovePlan plan(CpuObservation observation) {
    return _ExpertPipeline(_ExpertCpuPlanPolicy()).plan(observation);
  }
}

/// Expert uses a larger partition fan-out cap than the Skilled default. The
/// pipeline exposes the cap via the [bestMeldAction] parameter, so we override
/// the spine's call to inject Expert's 256-partition cap.
class _ExpertPipeline extends CpuMovePlanPipeline {
  const _ExpertPipeline(super.policy);

  @override
  String? bestMeldAction(
    CpuObservation observation, {
    required int partitionLimit,
  }) {
    return super.bestMeldAction(
      observation,
      partitionLimit: ExpertCpuMovePlanner._partitionLimit,
    );
  }
}

class _ExpertCpuPlanPolicy implements CpuPlanPolicy {
  const _ExpertCpuPlanPolicy();

  @override
  bool shouldClaimFifty(CpuObservation observation) {
    return canSuccessfullyClaimFiftyFor(observation);
  }

  @override
  int comparePartitions(
    CpuObservation observation,
    MeldPartition left,
    MeldPartition right,
  ) {
    if (!observation.ownHasOpened()) {
      return _compareOpeningPartitions(observation, left, right);
    }

    final leftFinishes = left.cardsRemaining.length == 1;
    final rightFinishes = right.cardsRemaining.length == 1;
    final finishCompare = boolDesc(leftFinishes, rightFinishes);
    if (finishCompare != 0) {
      return finishCompare;
    }

    if (observation.stockCount <= ExpertCpuMovePlanner._thinStockCount) {
      final remainingCompare = _remainingPips(
        left,
      ).compareTo(_remainingPips(right));
      if (remainingCompare != 0) {
        return remainingCompare;
      }
    }

    final surfaceCompare = right.meldCount.compareTo(left.meldCount);
    if (surfaceCompare != 0) {
      return surfaceCompare;
    }

    final interiorCompare = _interiorJokerScore(
      right,
    ).compareTo(_interiorJokerScore(left));
    if (interiorCompare != 0) {
      return interiorCompare;
    }

    final jokerCompare = left.jokerCount.compareTo(right.jokerCount);
    if (jokerCompare != 0) {
      return jokerCompare;
    }

    final pipCompare = _remainingPips(left).compareTo(_remainingPips(right));
    if (pipCompare != 0) {
      return pipCompare;
    }

    final valueCompare = right.totalValue.compareTo(left.totalValue);
    if (valueCompare != 0) {
      return valueCompare;
    }

    return _partitionKey(left).compareTo(_partitionKey(right));
  }

  @override
  List<HareegCard> selectMeldCards(
    CpuObservation observation,
    MeldPartition partition,
  ) {
    return CpuMovePlanPipeline.cardsInHandOrder(
      observation,
      partition.cardsUsed,
    );
  }

  @override
  bool shouldTakeDiscard(CpuObservation observation) {
    // Call the shared predicate directly instead of recursing through
    // Skilled's full plan — that path re-enumerates partitions and rebuilds
    // threat profiles just to read this boolean.
    if (shouldTakeDiscardForObservationCore(observation)) {
      return true;
    }
    // Defensive thin-stock pickup only makes sense if the seat has already
    // opened (or the pickup itself can satisfy opening). Picking up an
    // unusable discard pre-opening forces the rules engine to return it,
    // and the next draw choice will face the same discard top → loop.
    if (observation.stockCount > ExpertCpuMovePlanner._thinStockCount ||
        observation.topDiscard == null) {
      return false;
    }
    return observation.ownHasOpened();
  }

  @override
  bool shouldHoldNormalFinishForFifty(CpuObservation observation) {
    if (observation.finishingPartition() == null ||
        observation.stockCount < ExpertCpuMovePlanner._fiftyHoldStockFloor ||
        handPipValue(observation.ownHand) <=
            ExpertCpuMovePlanner._fiftyHoldHandValueFloor) {
      return false;
    }

    if (observation.ownScore >= ExpertCpuMovePlanner._highRiskScoreFloor) {
      return true;
    }
    return observation.opponents.any((opponent) {
      return observation.scoreFor(opponent) >=
          ExpertCpuMovePlanner._highRiskScoreFloor;
    });
  }

  @override
  bool gateJokerReplacement(CpuObservation observation) {
    return observation.finishingPartition() != null;
  }

  @override
  bool shouldHoldCover(CpuObservation observation, CpuLegalAction cover) {
    final target = cover.descriptor.coverTarget;
    if (target == null || target.targetSeat != observation.seat) {
      return false;
    }
    final cardIds = cover.descriptor.cardIds;
    if (cardIds.length != 1) {
      return false;
    }
    final card = _cardById(observation, cardIds.single);
    final identity = card?.effectiveIdentity;
    if (identity == null) {
      return false;
    }
    final ownMelds = observation.tableMeldsFor(observation.seat);
    if (target.meldIndex < 0 || target.meldIndex >= ownMelds.length) {
      return false;
    }
    final orders = _sequenceOrders(ownMelds[target.meldIndex]);
    if (orders == null) {
      return false;
    }
    final order = _rankOrder(identity.rank, highAce: orders.last == 14);
    return order == orders.first - 1 || order == orders.last + 1;
  }

  @override
  Comparator<CpuDiscardCandidate> discardComparator(
    CpuObservation observation,
  ) {
    // Expert's legacy planner used `_shouldHoldForFifty` (the high-risk
    // posture check) rather than the normal-finish hold gate when sorting
    // discards. The two predicates share their hold-for-fifty floors but
    // diverge on the "any opponent near-score" branch, so we keep the
    // posture-only check here to preserve behaviour exactly.
    final profile = _OpponentThreatProfile.fromObservation(observation);
    final holdForFifty = shouldHoldNormalFinishForFifty(observation);

    return (left, right) {
      final leftCard = left.card;
      final rightCard = right.card;
      final leftDanger = profile.dangerScore(leftCard);
      final rightDanger = profile.dangerScore(rightCard);
      final dangerCompare = leftDanger.compareTo(rightDanger);
      if (dangerCompare != 0) {
        return dangerCompare;
      }

      final leftTarget = profile.fiftySetupScore(leftCard);
      final rightTarget = profile.fiftySetupScore(rightCard);
      final targetCompare = leftTarget.compareTo(rightTarget);
      if (targetCompare != 0) {
        return targetCompare;
      }

      final leftValue = cardPipValue(leftCard);
      final rightValue = cardPipValue(rightCard);
      return holdForFifty
          ? rightValue.compareTo(leftValue)
          : leftValue.compareTo(rightValue);
    };
  }

  @override
  bool allowAnyLegalMeldFallback(CpuObservation observation) => false;

  @override
  ClassicHareegCpuMovePlan fallback(CpuObservation observation) {
    return const SkilledCpuMovePlanner().plan(observation);
  }

  int _compareOpeningPartitions(
    CpuObservation observation,
    MeldPartition left,
    MeldPartition right,
  ) {
    if (observation.benchmarkOwner == null &&
        observation.stockCount >= ExpertCpuMovePlanner._freshStockCount) {
      final leftBand = _benchmarkBandScore(left.totalValue);
      final rightBand = _benchmarkBandScore(right.totalValue);
      final bandCompare = rightBand.compareTo(leftBand);
      if (bandCompare != 0) {
        return bandCompare;
      }

      final targetCompare =
          (left.totalValue - ExpertCpuMovePlanner._benchmarkTarget)
              .abs()
              .compareTo(
                (right.totalValue - ExpertCpuMovePlanner._benchmarkTarget).abs(),
              );
      if (targetCompare != 0) {
        return targetCompare;
      }

      final valueCompare = right.totalValue.compareTo(left.totalValue);
      if (valueCompare != 0) {
        return valueCompare;
      }
    }

    final requirement = observation.currentOpeningRequirement;
    final overCompare = (left.totalValue - requirement).compareTo(
      right.totalValue - requirement,
    );
    if (overCompare != 0) {
      return overCompare;
    }
    return _partitionKey(left).compareTo(_partitionKey(right));
  }

  int _benchmarkBandScore(int value) {
    if (value >= ExpertCpuMovePlanner._benchmarkFloor &&
        value <= ExpertCpuMovePlanner._benchmarkCeiling) {
      return 2;
    }
    if (value > ExpertCpuMovePlanner._benchmarkCeiling) {
      return 1;
    }
    return 0;
  }

  int _interiorJokerScore(MeldPartition partition) {
    var score = 0;
    for (final meld in partition.melds) {
      final orders = _sequenceOrders(meld);
      if (orders == null || orders.length < 3) {
        continue;
      }
      final minOrder = orders.reduce(
        (left, right) => left < right ? left : right,
      );
      final maxOrder = orders.reduce(
        (left, right) => left > right ? left : right,
      );
      for (final card in meld.cards) {
        if (!card.isJoker) {
          continue;
        }
        final identity = card.effectiveIdentity;
        if (identity == null) {
          continue;
        }
        final order = _rankOrder(identity.rank, highAce: maxOrder == 14);
        if (order > minOrder && order < maxOrder) {
          score += 1;
        }
      }
    }
    return score;
  }

  HareegCard? _cardById(CpuObservation observation, String cardId) {
    for (final card in observation.ownHand) {
      if (card.id == cardId) {
        return card;
      }
    }
    return null;
  }

  int _remainingPips(MeldPartition partition) {
    return handPipValue(partition.cardsRemaining);
  }

  String _partitionKey(MeldPartition partition) {
    final meldKeys =
        partition.melds
            .map(
              (meld) => meld.cards
                  .map(
                    (card) => '${card.id}:${card.effectiveIdentity?.key ?? ''}',
                  )
                  .join(','),
            )
            .toList()
          ..sort();
    return meldKeys.join('/');
  }
}

List<int>? _sequenceOrders(PlacedMeld meld) {
  final identities = meld.cards
      .map((card) => card.effectiveIdentity)
      .whereType<CardIdentity>()
      .toList(growable: false);
  if (identities.length != meld.cards.length || identities.length < 3) {
    return null;
  }
  final suit = identities.first.suit;
  if (identities.any((identity) => identity.suit != suit)) {
    return null;
  }

  final lowOrders = identities.map((identity) => identity.rank.order).toList()
    ..sort();
  if (_isConsecutive(lowOrders)) {
    return lowOrders;
  }

  final highOrders =
      identities
          .map((identity) => _rankOrder(identity.rank, highAce: true))
          .toList()
        ..sort();
  if (_isConsecutive(highOrders)) {
    return highOrders;
  }
  return null;
}

bool _isConsecutive(List<int> orders) {
  for (var index = 1; index < orders.length; index += 1) {
    if (orders[index] != orders[index - 1] + 1) {
      return false;
    }
  }
  return true;
}

int _rankOrder(CardRank rank, {required bool highAce}) {
  if (highAce && rank == CardRank.ace) {
    return 14;
  }
  return rank.order;
}

class _OpponentThreatProfile {
  const _OpponentThreatProfile({
    required this.hotRanks,
    required this.hotSuits,
    required this.hotIdentities,
    required this.nearScoreRanks,
    required this.nearScoreSuits,
    required this.nearScoreIdentities,
    required this.runEndThreats,
    required this.eliminationTargetIdentities,
  });

  final Set<CardRank> hotRanks;
  final Set<CardSuit> hotSuits;
  final Set<String> hotIdentities;
  final Set<CardRank> nearScoreRanks;
  final Set<CardSuit> nearScoreSuits;
  final Set<String> nearScoreIdentities;
  final Set<String> runEndThreats;
  final Set<String> eliminationTargetIdentities;

  factory _OpponentThreatProfile.fromObservation(CpuObservation observation) {
    final hotRanks = <CardRank>{};
    final hotSuits = <CardSuit>{};
    final hotIdentities = <String>{};
    final nearScoreRanks = <CardRank>{};
    final nearScoreSuits = <CardSuit>{};
    final nearScoreIdentities = <String>{};
    final runEndThreats = <String>{};
    final eliminationTargetIdentities = <String>{};

    for (final opponent in observation.opponents) {
      final score = observation.scoreFor(opponent);
      final nearScore = score >= ExpertCpuMovePlanner._highRiskScoreFloor;
      final eliminationTarget =
          score >= ExpertCpuMovePlanner._eliminationTargetScoreFloor;
      final cards = [
        ...observation.discardHistory.lastDiscardsBy(opponent, 99),
        ...observation.discardHistory.lastPickupsBy(opponent, 99),
      ];
      for (final card in cards) {
        final identity = card.effectiveIdentity;
        if (identity == null) {
          continue;
        }
        hotRanks.add(identity.rank);
        hotSuits.add(identity.suit);
        hotIdentities.add(identity.key);
        if (nearScore) {
          nearScoreRanks.add(identity.rank);
          nearScoreSuits.add(identity.suit);
          nearScoreIdentities.add(identity.key);
        }
        if (eliminationTarget) {
          eliminationTargetIdentities.add(identity.key);
        }
      }

      for (final meld in observation.tableMeldsFor(opponent)) {
        for (final identity in _runEndCoverThreats(meld)) {
          runEndThreats.add(identity.key);
        }
      }
    }

    return _OpponentThreatProfile(
      hotRanks: hotRanks,
      hotSuits: hotSuits,
      hotIdentities: hotIdentities,
      nearScoreRanks: nearScoreRanks,
      nearScoreSuits: nearScoreSuits,
      nearScoreIdentities: nearScoreIdentities,
      runEndThreats: runEndThreats,
      eliminationTargetIdentities: eliminationTargetIdentities,
    );
  }

  int dangerScore(HareegCard card) {
    final identity = card.effectiveIdentity;
    if (identity == null) {
      return 40;
    }
    var score = 0;
    if (runEndThreats.contains(identity.key)) {
      score += 120;
    }
    if (nearScoreIdentities.contains(identity.key)) {
      score += 90;
    }
    if (nearScoreRanks.contains(identity.rank)) {
      score += 45;
    }
    if (nearScoreSuits.contains(identity.suit)) {
      score += 20;
    }
    if (hotIdentities.contains(identity.key)) {
      score += 35;
    }
    if (hotRanks.contains(identity.rank)) {
      score += 15;
    }
    if (hotSuits.contains(identity.suit)) {
      score += 5;
    }
    return score;
  }

  int fiftySetupScore(HareegCard card) {
    final identity = card.effectiveIdentity;
    if (identity == null) {
      return 0;
    }
    if (eliminationTargetIdentities.contains(identity.key)) {
      return 3;
    }
    if (nearScoreIdentities.contains(identity.key)) {
      return 2;
    }
    if (hotIdentities.contains(identity.key)) {
      return 1;
    }
    return 0;
  }

  static List<CardIdentity> _runEndCoverThreats(PlacedMeld meld) {
    final identities = meld.cards
        .map((card) => card.effectiveIdentity)
        .whereType<CardIdentity>()
        .toList(growable: false);
    if (identities.length != meld.cards.length || identities.length < 3) {
      return const [];
    }
    final suit = identities.first.suit;
    if (identities.any((identity) => identity.suit != suit)) {
      return const [];
    }

    final orders = identities.map((identity) => identity.rank.order).toList()
      ..sort();
    if (!_isConsecutiveOrders(orders)) {
      return const [];
    }

    final threats = <CardIdentity>[];
    final lower = _rankByOrder(orders.first - 1);
    if (lower != null) {
      threats.add(CardIdentity(rank: lower, suit: suit));
    }
    final upper = _rankByOrder(orders.last + 1);
    if (upper != null) {
      threats.add(CardIdentity(rank: upper, suit: suit));
    }
    return threats;
  }

  static bool _isConsecutiveOrders(List<int> orders) {
    for (var index = 1; index < orders.length; index += 1) {
      if (orders[index] != orders[index - 1] + 1) {
        return false;
      }
    }
    return true;
  }

  static CardRank? _rankByOrder(int order) {
    for (final rank in CardRank.values) {
      if (rank.order == order) {
        return rank;
      }
    }
    return null;
  }
}
