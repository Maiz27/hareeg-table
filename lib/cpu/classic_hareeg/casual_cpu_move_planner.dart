import '../../domain/classic_hareeg/models/playing_card.dart';
import 'cpu_move_plan.dart';
import 'cpu_move_plan_pipeline.dart';
import 'cpu_observation.dart';
import 'priority_cpu_move_planner.dart';

/// Casual CPU planner with immediate hand tactics but no opponent modelling.
///
/// This tier sits between Beginner's priority-only play and Skilled's memory /
/// table-aware posture. It takes discards that directly improve the hand,
/// prefers compact melds, sheds high pips, and claims valid Fifties subject to
/// the difficulty miss profile.
class CasualCpuMovePlanner implements CpuMovePlanner {
  /// Creates a casual CPU move planner.
  const CasualCpuMovePlanner();

  @override
  ClassicHareegCpuMovePlan plan(CpuObservation observation) {
    return const CpuMovePlanPipeline(_CasualCpuPlanPolicy()).plan(observation);
  }
}

class _CasualCpuPlanPolicy implements CpuPlanPolicy {
  const _CasualCpuPlanPolicy();

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

    return MeldPartitionRankers.byMeanMeldLengthAsc(left, right);
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
    return shouldTakeDiscardForObservationCore(observation);
  }

  @override
  bool shouldHoldNormalFinishForFifty(CpuObservation observation) => false;

  @override
  bool gateJokerReplacement(CpuObservation observation) => true;

  @override
  bool shouldHoldCover(CpuObservation observation, CpuLegalAction cover) {
    return false;
  }

  @override
  Comparator<CpuDiscardCandidate> discardComparator(
    CpuObservation observation,
  ) {
    return (left, right) {
      final valueCompare = cardPipValue(
        right.card,
      ).compareTo(cardPipValue(left.card));
      if (valueCompare != 0) {
        return valueCompare;
      }
      return left.action.actionId.compareTo(right.action.actionId);
    };
  }

  @override
  bool allowAnyLegalMeldFallback(CpuObservation observation) => true;

  @override
  ClassicHareegCpuMovePlan fallback(CpuObservation observation) {
    return PriorityCpuMovePlanner.evaluate(observation.legalActionIds);
  }
}
