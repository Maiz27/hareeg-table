import '../../domain/classic_hareeg/models/playing_card.dart';
import '../../domain/classic_hareeg/rules/opening_rules.dart';
import 'cpu_move_plan.dart';
import 'cpu_move_plan_pipeline.dart';
import 'cpu_observation.dart';
import 'priority_cpu_move_planner.dart';

/// Skilled CPU planner that scores visible table state, memory, and partitions.
///
/// This tier is a thin adapter — every stage of `plan()` runs in
/// [CpuMovePlanPipeline]; this class only supplies the per-stage scoring weights
/// for Skilled's posture (partition push to benchmark, hot-rank memory, hold
/// normal finishes when opponents are quiet).
class SkilledCpuMovePlanner implements CpuMovePlanner {
  /// Creates a skilled CPU move planner.
  const SkilledCpuMovePlanner();

  static const _discardPickupMemory = 3;
  static const _discardHistoryDepth = 5;
  static const _fiftyHoldStockFloor = 10;
  static const _fiftyHoldHandValueFloor = 30;
  static const _nearEliminationScore = 25;
  static const _benchmarkPushTarget = 10;

  @override
  ClassicHareegCpuMovePlan plan(CpuObservation observation) {
    return const CpuMovePlanPipeline(_SkilledCpuPlanPolicy()).plan(observation);
  }

  /// Public variant retained for Expert / Priority planners that share the
  /// same Fifty-claim filter via static call.
  static bool canSuccessfullyClaimFifty(CpuObservation observation) {
    return canSuccessfullyClaimFiftyFor(observation);
  }

  /// Pure predicate shared with [ExpertCpuMovePlanner] so Expert doesn't have
  /// to recurse into Skilled's full `plan()` (which would re-enumerate
  /// partitions and rebuild threat profiles) just to read this boolean.
  static bool shouldTakeDiscardForObservation(CpuObservation observation) {
    return shouldTakeDiscardForObservationCore(observation);
  }
}

class _SkilledCpuPlanPolicy implements CpuPlanPolicy {
  const _SkilledCpuPlanPolicy();

  @override
  bool shouldClaimFifty(CpuObservation observation) {
    return shouldAttemptFiftyClaimFor(observation);
  }

  @override
  int comparePartitions(
    CpuObservation observation,
    MeldPartition left,
    MeldPartition right,
  ) {
    final leftFinishes = left.cardsRemaining.length == 1;
    final rightFinishes = right.cardsRemaining.length == 1;
    final finishCompare = boolDesc(leftFinishes, rightFinishes);
    if (finishCompare != 0) {
      return finishCompare;
    }

    if (!observation.ownHasOpened()) {
      final requirement = observation.currentOpeningRequirement;
      final overCompare = (left.totalValue - requirement).compareTo(
        right.totalValue - requirement,
      );
      if (overCompare != 0) {
        return overCompare;
      }
    }

    if (_canPushBenchmark(observation)) {
      final leftPush = _benchmarkPushScore(left.totalValue);
      final rightPush = _benchmarkPushScore(right.totalValue);
      final pushCompare = rightPush.compareTo(leftPush);
      if (pushCompare != 0) {
        return pushCompare;
      }
    }

    final jokerSeenCompare = _jokerSeenScore(
      observation,
      right,
    ).compareTo(_jokerSeenScore(observation, left));
    if (jokerSeenCompare != 0) {
      return jokerSeenCompare;
    }

    return MeldPartitionRankers.byMeanMeldLengthAsc(left, right);
  }

  @override
  List<HareegCard> selectMeldCards(
    CpuObservation observation,
    MeldPartition partition,
  ) {
    if (!observation.ownHasOpened() || partition.cardsRemaining.length == 1) {
      return CpuMovePlanPipeline.cardsInHandOrder(
        observation,
        partition.cardsUsed,
      );
    }

    final pending = observation.pendingDiscard;
    final melds = List<PlacedMeld>.of(partition.melds);
    melds.sort((left, right) {
      if (pending != null) {
        final leftUsesPending = _meldUsesCard(left, pending.id);
        final rightUsesPending = _meldUsesCard(right, pending.id);
        final pendingCompare = boolDesc(leftUsesPending, rightUsesPending);
        if (pendingCompare != 0) {
          return pendingCompare;
        }
      }
      final lengthCompare = left.cards.length.compareTo(right.cards.length);
      if (lengthCompare != 0) {
        return lengthCompare;
      }
      return right.valueSnapshot.compareTo(left.valueSnapshot);
    });
    return CpuMovePlanPipeline.cardsInHandOrder(observation, melds.first.cards);
  }

  @override
  bool shouldTakeDiscard(CpuObservation observation) {
    return shouldTakeDiscardForObservationCore(observation);
  }

  @override
  bool shouldHoldNormalFinishForFifty(CpuObservation observation) {
    if (_nearElimination(observation) ||
        observation.stockCount < SkilledCpuMovePlanner._fiftyHoldStockFloor ||
        handPipValue(observation.ownHand) <=
            SkilledCpuMovePlanner._fiftyHoldHandValueFloor ||
        observation.finishingPartition() == null) {
      return false;
    }

    for (final opponent in observation.opponents) {
      if (observation.discardHistory
          .lastDiscardsBy(opponent, SkilledCpuMovePlanner._discardHistoryDepth)
          .isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  @override
  bool gateJokerReplacement(CpuObservation observation) => true;

  @override
  bool shouldHoldCover(CpuObservation observation, CpuLegalAction cover) {
    final cardIds = cover.descriptor.cardIds;
    if (cardIds.length != 1) {
      return false;
    }
    final cardId = cardIds.single;
    HareegCard? coverCard;
    for (final card in observation.ownHand) {
      if (card.id == cardId) {
        coverCard = card;
        break;
      }
    }
    if (coverCard == null) {
      return false;
    }
    final identity = coverCard.effectiveIdentity;
    if (identity == null) {
      return false;
    }

    var adjacentCount = 0;
    for (final card in observation.ownHand) {
      if (card.id == coverCard.id) {
        continue;
      }
      final candidate = card.effectiveIdentity;
      if (candidate == null || candidate.suit != identity.suit) {
        continue;
      }
      if ((candidate.rank.order - identity.rank.order).abs() <= 2) {
        adjacentCount += 1;
      }
    }
    return adjacentCount >= 2;
  }

  @override
  Comparator<CpuDiscardCandidate> discardComparator(
    CpuObservation observation,
  ) {
    final hotRanks = _recentPickupRanks(observation);
    final recentDiscards = _recentOpponentDiscardIdentities(observation);
    final nearElimination = _nearElimination(observation);

    return (left, right) {
      final leftCard = left.card;
      final rightCard = right.card;
      final leftIdentity = leftCard.effectiveIdentity;
      final rightIdentity = rightCard.effectiveIdentity;

      final leftHot =
          leftIdentity != null && hotRanks.contains(leftIdentity.rank);
      final rightHot =
          rightIdentity != null && hotRanks.contains(rightIdentity.rank);
      final hotCompare = boolAsc(leftHot, rightHot);
      if (hotCompare != 0) {
        return hotCompare;
      }

      final leftRecent =
          leftIdentity != null && recentDiscards.contains(leftIdentity.key);
      final rightRecent =
          rightIdentity != null && recentDiscards.contains(rightIdentity.key);
      final recentCompare = boolAsc(leftRecent, rightRecent);
      if (recentCompare != 0) {
        return recentCompare;
      }

      final leftValue = cardPipValue(leftCard);
      final rightValue = cardPipValue(rightCard);
      return nearElimination
          ? leftValue.compareTo(rightValue)
          : rightValue.compareTo(leftValue);
    };
  }

  @override
  bool allowAnyLegalMeldFallback(CpuObservation observation) => true;

  @override
  ClassicHareegCpuMovePlan fallback(CpuObservation observation) {
    return PriorityCpuMovePlanner.evaluate(observation.legalActionIds);
  }

  bool _canPushBenchmark(CpuObservation observation) {
    return observation.ownHasOpened() &&
        observation.benchmarkOwner == observation.seat &&
        !observation.openingState.isLocked;
  }

  int _benchmarkPushScore(int totalValue) {
    return totalValue > SkilledCpuMovePlanner._benchmarkPushTarget
        ? SkilledCpuMovePlanner._benchmarkPushTarget
        : totalValue;
  }

  int _jokerSeenScore(CpuObservation observation, MeldPartition partition) {
    var score = 0;
    for (final assignment in partition.jokerAssignments) {
      final identity = assignment.identity;
      if (observation.discardHistory.cardSeenAt(identity.rank, identity.suit)) {
        score += 1;
      }
    }
    return score;
  }

  bool _meldUsesCard(PlacedMeld meld, String cardId) {
    return meld.cards.any((card) => card.id == cardId);
  }

  Set<CardRank> _recentPickupRanks(CpuObservation observation) {
    return {
      for (final opponent in observation.opponents)
        for (final card in observation.discardHistory.lastPickupsBy(
          opponent,
          SkilledCpuMovePlanner._discardPickupMemory,
        ))
          if (card.effectiveIdentity != null) card.effectiveIdentity!.rank,
    };
  }

  Set<String> _recentOpponentDiscardIdentities(CpuObservation observation) {
    return {
      for (final opponent in observation.opponents)
        for (final card in observation.discardHistory.lastDiscardsBy(
          opponent,
          SkilledCpuMovePlanner._discardHistoryDepth,
        ))
          if (card.effectiveIdentity != null) card.effectiveIdentity!.key,
    };
  }

  bool _nearElimination(CpuObservation observation) {
    final thresholdWindow = observation.eliminationThreshold - 6;
    final scoreFloor =
        thresholdWindow > SkilledCpuMovePlanner._nearEliminationScore
        ? thresholdWindow
        : SkilledCpuMovePlanner._nearEliminationScore;
    return observation.ownScore >= scoreFloor;
  }
}
