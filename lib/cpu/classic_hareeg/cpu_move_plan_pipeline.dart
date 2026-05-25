import '../../domain/classic_hareeg/game/classic_hareeg_action.dart';
import '../../domain/classic_hareeg/game/classic_hareeg_round.dart';
import '../../domain/classic_hareeg/models/playing_card.dart';
import 'cpu_move_plan.dart';
import 'cpu_observation.dart';

/// Legal action paired with its decoded descriptor.
///
/// The pipeline decodes legal action ids once and hands the resulting list to
/// every policy hook so tiers don't each re-run `ClassicHareegActionIds.describe`.
class CpuLegalAction {
  /// Creates a decoded legal action.
  const CpuLegalAction({required this.actionId, required this.descriptor});

  /// Legal action id from the rules engine.
  final String actionId;

  /// Decoded descriptor for [actionId].
  final ClassicHareegActionDescriptor descriptor;
}

/// Discard candidate considered by [CpuPlanPolicy.compareDiscards].
class CpuDiscardCandidate {
  /// Creates a discard candidate from a safe-discard action.
  const CpuDiscardCandidate({required this.action, required this.card});

  /// Legal action backing this candidate.
  final CpuLegalAction action;

  /// Card from the CPU hand that the action will discard.
  final HareegCard card;
}

/// Per-stage scoring policy supplied by a CPU tier to [CpuMovePlanPipeline].
///
/// The pipeline owns the plan spine — action decoding, branch ordering, the
/// partition / discard / cover walks — and asks the policy to fill in the
/// tier-specific scoring weights and posture for each stage.
abstract interface class CpuPlanPolicy {
  /// True when the CPU should attempt a Fifty claim with the current state.
  bool shouldClaimFifty(CpuObservation observation);

  /// Compares two playable partitions; lower wins (sorted ascending).
  int comparePartitions(
    CpuObservation observation,
    MeldPartition left,
    MeldPartition right,
  );

  /// Selects the cards to play from [partition] for the meld action id.
  ///
  /// Skilled and Expert differ on whether they preserve the full partition
  /// or peel a single meld for opened hands.
  List<HareegCard> selectMeldCards(
    CpuObservation observation,
    MeldPartition partition,
  );

  /// True when the CPU should take the top discard during the draw phase.
  bool shouldTakeDiscard(CpuObservation observation);

  /// True when a normal finish should be held back in favour of a Fifty setup.
  bool shouldHoldNormalFinishForFifty(CpuObservation observation);

  /// True when the joker-replacement branch should fire for this observation.
  ///
  /// Skilled always replaces; Expert delays until a finish is visible.
  bool gateJokerReplacement(CpuObservation observation);

  /// True when the cover branch should pass over [cover] (e.g. when the cover
  /// is more valuable in hand than on the table).
  bool shouldHoldCover(CpuObservation observation, CpuLegalAction cover);

  /// Builds a comparator for safe-discard candidates.
  ///
  /// The policy is invoked once per plan, before the candidate sort, so it can
  /// hoist per-plan state (recent-pickup ranks, opponent threat profile, etc.)
  /// out of the comparator hot path. The returned comparator runs O(n log n)
  /// times during the sort and must be pure.
  Comparator<CpuDiscardCandidate> discardComparator(CpuObservation observation);

  /// True when, after [bestMeldAction] returns null but the policy is not
  /// holding for Fifty, the pipeline should grab the first legal meld of any
  /// kind as a meld-stage fallback.
  ///
  /// Skilled enables this (its priority fallback only reads legal action ids,
  /// so it can't run the same partition-ranking comparator and would otherwise
  /// miss obvious melds). Expert does not, because its Skilled fallback will
  /// re-run the partition ranker.
  bool allowAnyLegalMeldFallback(CpuObservation observation);

  /// Last-resort plan when no earlier branch chose a move.
  ClassicHareegCpuMovePlan fallback(CpuObservation observation);
}

/// Pipeline shared by every table-aware CPU tier.
///
/// Owns the structural spine — action decoding, the branch order, the partition
/// catalog, the discard threat walk, the Fifty posture, and the final plan
/// assembly. Tiers supply a [CpuPlanPolicy] that fills in the per-stage scoring.
class CpuMovePlanPipeline {
  /// Creates a pipeline bound to [policy].
  const CpuMovePlanPipeline(this.policy);

  /// Per-stage scoring policy for this tier.
  final CpuPlanPolicy policy;

  /// Default upper bound for partition enumeration. Tiers can override via
  /// the policy if they need a different fan-out cap.
  static const int defaultPartitionLimit = 96;

  /// Runs the full plan pipeline for [observation].
  ClassicHareegCpuMovePlan plan(CpuObservation observation) {
    final actions = decodeLegalActions(observation);
    if (actions.isEmpty) {
      return const ClassicHareegCpuMovePlan(
        scenario: ClassicHareegCpuMoveScenario.noLegalActions,
        actionId: null,
      );
    }

    final fifty = firstActionOfKind(
      actions,
      ClassicHareegActionKind.claimFifty,
    );
    if (fifty != null && policy.shouldClaimFifty(observation)) {
      return ClassicHareegCpuMovePlan(
        scenario: ClassicHareegCpuMoveScenario.fiftyClaim,
        actionId: fifty.actionId,
      );
    }

    if (observation.pendingDiscard != null) {
      final pendingMeld = bestMeldAction(
        observation,
        partitionLimit: defaultPartitionLimit,
      );
      if (pendingMeld != null) {
        return ClassicHareegCpuMovePlan(
          scenario: ClassicHareegCpuMoveScenario.meldPlay,
          actionId: pendingMeld,
        );
      }
      final pendingReturn = firstActionOfKind(
        actions,
        ClassicHareegActionKind.returnPendingDiscard,
      );
      if (pendingReturn != null) {
        return ClassicHareegCpuMovePlan(
          scenario: ClassicHareegCpuMoveScenario.returnPendingDiscard,
          actionId: pendingReturn.actionId,
        );
      }
    }

    if (observation.turnPhase == TurnPhase.draw) {
      final takeDiscard = firstActionOfKind(
        actions,
        ClassicHareegActionKind.takeDiscard,
      );
      if (takeDiscard != null && policy.shouldTakeDiscard(observation)) {
        return ClassicHareegCpuMovePlan(
          scenario: ClassicHareegCpuMoveScenario.takeDiscard,
          actionId: takeDiscard.actionId,
        );
      }
      final drawStock = firstActionOfKind(
        actions,
        ClassicHareegActionKind.drawStock,
      );
      if (drawStock != null) {
        return ClassicHareegCpuMovePlan(
          scenario: ClassicHareegCpuMoveScenario.drawStock,
          actionId: drawStock.actionId,
        );
      }
    }

    final holdForFifty = policy.shouldHoldNormalFinishForFifty(observation);
    if (!holdForFifty) {
      final meldAction = bestMeldAction(
        observation,
        partitionLimit: defaultPartitionLimit,
      );
      if (meldAction != null) {
        return ClassicHareegCpuMovePlan(
          scenario: ClassicHareegCpuMoveScenario.meldPlay,
          actionId: meldAction,
        );
      }
      if (policy.allowAnyLegalMeldFallback(observation)) {
        final legalMeld = _firstMeldAction(actions);
        if (legalMeld != null) {
          return ClassicHareegCpuMovePlan(
            scenario: ClassicHareegCpuMoveScenario.meldPlay,
            actionId: legalMeld.actionId,
          );
        }
      }
    }

    final replacement = firstActionOfKind(
      actions,
      ClassicHareegActionKind.replaceJoker,
    );
    if (replacement != null && policy.gateJokerReplacement(observation)) {
      return ClassicHareegCpuMovePlan(
        scenario: ClassicHareegCpuMoveScenario.jokerReplacement,
        actionId: replacement.actionId,
      );
    }

    final cover = firstActionOfKind(actions, ClassicHareegActionKind.placeCover);
    if (cover != null && !policy.shouldHoldCover(observation, cover)) {
      return ClassicHareegCpuMovePlan(
        scenario: ClassicHareegCpuMoveScenario.cover,
        actionId: cover.actionId,
      );
    }

    final discard = bestDiscardAction(observation, actions);
    if (discard != null) {
      return ClassicHareegCpuMovePlan(
        scenario: ClassicHareegCpuMoveScenario.safeDiscard,
        actionId: discard.actionId,
      );
    }

    return policy.fallback(observation);
  }

  /// Decodes legal action ids into structured [CpuLegalAction]s once per plan.
  static List<CpuLegalAction> decodeLegalActions(CpuObservation observation) {
    return [
      for (final id in observation.legalActionIds)
        CpuLegalAction(
          actionId: id,
          descriptor: ClassicHareegActionIds.describe(id),
        ),
    ];
  }

  /// Returns the first decoded action of [kind], or null when absent.
  static CpuLegalAction? firstActionOfKind(
    List<CpuLegalAction> actions,
    ClassicHareegActionKind kind,
  ) {
    for (final action in actions) {
      if (action.descriptor.kind == kind) {
        return action;
      }
    }
    return null;
  }

  static CpuLegalAction? _firstMeldAction(List<CpuLegalAction> actions) {
    for (final action in actions) {
      if (action.descriptor.isMeldPlay) {
        return action;
      }
    }
    return null;
  }

  /// Enumerates playable partitions ranked by [policy] and returns the meld
  /// action id for the chosen partition, or null when none is playable.
  String? bestMeldAction(
    CpuObservation observation, {
    required int partitionLimit,
  }) {
    if (observation.turnPhase != TurnPhase.action) {
      return null;
    }

    final pending = observation.pendingDiscard;
    final partitions = observation.partitions
        .enumerate(
          maxPartitions: partitionLimit,
          minMelds: 1,
          maxMelds: 5,
          mustUseCardId: pending?.id,
          minTotalValue: observation.ownHasOpened()
              ? null
              : observation.currentOpeningRequirement,
        )
        .where((partition) => _canPlayPartition(observation, partition))
        .toList();
    if (partitions.isEmpty) {
      return null;
    }

    partitions.sort(
      (left, right) => policy.comparePartitions(observation, left, right),
    );
    final partition = partitions.first;
    final cards = policy.selectMeldCards(observation, partition);
    if (cards.isEmpty || cards.length >= observation.ownHand.length) {
      return null;
    }
    return playMeldActionId(cards, partition.jokerAssignments);
  }

  bool _canPlayPartition(CpuObservation observation, MeldPartition partition) {
    if (partition.cardsUsed.isEmpty || partition.cardsRemaining.isEmpty) {
      return false;
    }

    final pending = observation.pendingDiscard;
    if (pending != null && !partition.usesCardId(pending.id)) {
      return false;
    }

    if (!observation.ownHasOpened() &&
        partition.totalValue < observation.currentOpeningRequirement) {
      return false;
    }
    return true;
  }

  /// Builds the canonical play-meld action id for [cards] and [assignments].
  static String playMeldActionId(
    List<HareegCard> cards,
    List<JokerMeldAssignment> assignments,
  ) {
    final cardIds = cards.map((card) => card.id).toList(growable: false);
    final selectedIds = cardIds.toSet();
    final selectedAssignments = [
      for (final assignment in assignments)
        if (selectedIds.contains(assignment.jokerId)) assignment,
    ];
    if (selectedAssignments.isEmpty) {
      return ClassicHareegActionIds.playMeldActionId(cardIds);
    }
    return ClassicHareegActionIds.playMeldWithJokerIdentitiesActionId(
      cardIds: cardIds,
      assignments: selectedAssignments,
    );
  }

  /// Filters [cards] to the CPU hand order (drops anything not in hand).
  static List<HareegCard> cardsInHandOrder(
    CpuObservation observation,
    Iterable<HareegCard> selected,
  ) {
    final selectedIds = selected.map((card) => card.id).toSet();
    return [
      for (final card in observation.ownHand)
        if (selectedIds.contains(card.id)) card,
    ];
  }

  /// Picks the highest-ranked safe-discard candidate using [policy].
  CpuLegalAction? bestDiscardAction(
    CpuObservation observation,
    List<CpuLegalAction> actions,
  ) {
    final candidates = <CpuDiscardCandidate>[];
    for (final action in actions) {
      if (!action.descriptor.isSafeDiscard) {
        continue;
      }
      final card = _cardForAction(observation, action);
      if (card == null) {
        continue;
      }
      candidates.add(CpuDiscardCandidate(action: action, card: card));
    }
    if (candidates.isEmpty) {
      return null;
    }

    final comparator = policy.discardComparator(observation);
    candidates.sort((left, right) {
      final compare = comparator(left, right);
      if (compare != 0) {
        return compare;
      }
      return left.action.actionId.compareTo(right.action.actionId);
    });
    return candidates.first.action;
  }

  static HareegCard? _cardForAction(
    CpuObservation observation,
    CpuLegalAction action,
  ) {
    final cardId = action.descriptor.cardId;
    if (cardId == null) {
      return null;
    }
    for (final card in observation.ownHand) {
      if (card.id == cardId) {
        return card;
      }
    }
    return null;
  }
}

/// True when the CPU seat owns the Fifty claim window and actually has a
/// finishing partition — i.e. the claim would land on the success branch
/// instead of the wrong-claim mistake branch.
///
/// Shared across every tier: the rules engine advertises claim-fifty for any
/// open window so humans can attempt wrong claims, and the CPU should never
/// take that branch.
bool canSuccessfullyClaimFiftyFor(CpuObservation observation) {
  if (!observation.ownIsFiftyClaimant) return false;
  return observation.finishingPartition() != null;
}

/// Pure predicate: should the CPU take the top discard during the draw phase?
///
/// Used by every tier as a shared baseline; Expert adds a thin-stock fallback
/// on top of this result.
bool shouldTakeDiscardForObservationCore(CpuObservation observation) {
  final discarded = observation.topDiscard;
  if (discarded == null) {
    return false;
  }
  final cards = [...observation.ownHand, discarded];
  final openingFloor = observation.ownHasOpened()
      ? null
      : observation.currentOpeningRequirement;
  final partitions = MeldPartitionEnumerator.partitionsOf(
    cards,
    mustUseCardId: discarded.id,
    minTotalValue: openingFloor,
    safetyCap: 24,
  );
  for (final partition in partitions) {
    if (partition.cardsRemaining.length < observation.ownHand.length ||
        _extendsSetToFour(discarded, partition)) {
      return true;
    }
  }
  return false;
}

bool _extendsSetToFour(HareegCard discarded, MeldPartition partition) {
  final identity = discarded.effectiveIdentity;
  if (identity == null) {
    return false;
  }
  for (final meld in partition.melds) {
    final identities = meld.cards
        .map((card) => card.effectiveIdentity)
        .whereType<CardIdentity>()
        .toList(growable: false);
    if (identities.length == 4 &&
        identities.every((candidate) => candidate.rank == identity.rank)) {
      return true;
    }
  }
  return false;
}

/// Pip value used by every tier's hand / partition scoring.
int cardPipValue(HareegCard card) {
  return card.effectiveIdentity?.rank.value ?? 25;
}

/// Sum of [cardPipValue] across [cards].
int handPipValue(Iterable<HareegCard> cards) {
  return cards.fold<int>(0, (total, card) => total + cardPipValue(card));
}

/// Stable descending boolean compare: true sorts before false.
int boolDesc(bool left, bool right) {
  if (left == right) {
    return 0;
  }
  return left ? -1 : 1;
}

/// Stable ascending boolean compare: false sorts before true.
int boolAsc(bool left, bool right) {
  if (left == right) {
    return 0;
  }
  return left ? 1 : -1;
}
