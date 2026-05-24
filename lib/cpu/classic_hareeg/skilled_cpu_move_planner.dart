import '../../domain/classic_hareeg/game/classic_hareeg_action.dart';
import '../../domain/classic_hareeg/game/classic_hareeg_round.dart';
import '../../domain/classic_hareeg/models/playing_card.dart';
import '../../domain/classic_hareeg/rules/opening_rules.dart';
import 'cpu_move_plan.dart';
import 'cpu_observation.dart';
import 'priority_cpu_move_planner.dart';

class _SkilledCpuLegalAction {
  const _SkilledCpuLegalAction({
    required this.actionId,
    required this.descriptor,
  });

  final String actionId;
  final ClassicHareegActionDescriptor descriptor;
}

/// Skilled CPU planner that scores visible table state, memory, and partitions.
class SkilledCpuMovePlanner implements CpuMovePlanner {
  /// Creates a skilled CPU move planner.
  const SkilledCpuMovePlanner();

  static const _partitionLimit = 96;
  static const _discardPickupMemory = 3;
  static const _discardHistoryDepth = 5;
  static const _fiftyHoldStockFloor = 10;
  static const _fiftyHoldHandValueFloor = 30;
  static const _nearEliminationScore = 25;
  static const _benchmarkPushTarget = 10;

  @override
  ClassicHareegCpuMovePlan plan(CpuObservation observation) {
    final legalActions = [
      for (final id in observation.legalActionIds)
        _SkilledCpuLegalAction(
          actionId: id,
          descriptor: ClassicHareegActionIds.describe(id),
        ),
    ];
    if (legalActions.isEmpty) {
      return const ClassicHareegCpuMovePlan(
        scenario: ClassicHareegCpuMoveScenario.noLegalActions,
        actionId: null,
      );
    }

    final fifty = _firstActionOfKind(
      legalActions,
      ClassicHareegActionKind.claimFifty,
    );
    // The rules engine advertises claim-fifty whenever the Fifty window is
    // open and points at this seat — even with no valid finish, because it
    // also needs to surface "wrong claim" attempts for human players. For
    // a CPU there's no upside in attempting a wrong claim (just a penalty
    // and a wasted action), so only pick it when the seat actually has a
    // finishing partition that uses the discarded card.
    if (fifty != null && _canSuccessfullyClaimFifty(observation)) {
      return ClassicHareegCpuMovePlan(
        scenario: ClassicHareegCpuMoveScenario.fiftyClaim,
        actionId: fifty.actionId,
      );
    }

    if (observation.pendingDiscard != null) {
      final pendingMeld = _bestMeldAction(observation);
      if (pendingMeld != null) {
        return ClassicHareegCpuMovePlan(
          scenario: ClassicHareegCpuMoveScenario.meldPlay,
          actionId: pendingMeld,
        );
      }
      final pendingReturn = _firstActionOfKind(
        legalActions,
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
      final takeDiscard = _firstActionOfKind(
        legalActions,
        ClassicHareegActionKind.takeDiscard,
      );
      if (takeDiscard != null && _shouldTakeDiscard(observation)) {
        return ClassicHareegCpuMovePlan(
          scenario: ClassicHareegCpuMoveScenario.takeDiscard,
          actionId: takeDiscard.actionId,
        );
      }
      final drawStock = _firstActionOfKind(
        legalActions,
        ClassicHareegActionKind.drawStock,
      );
      if (drawStock != null) {
        return ClassicHareegCpuMovePlan(
          scenario: ClassicHareegCpuMoveScenario.drawStock,
          actionId: drawStock.actionId,
        );
      }
    }

    final holdForFifty = _shouldHoldNormalFinishForFifty(observation);
    if (!holdForFifty) {
      final meldAction = _bestMeldAction(observation);
      if (meldAction != null) {
        return ClassicHareegCpuMovePlan(
          scenario: ClassicHareegCpuMoveScenario.meldPlay,
          actionId: meldAction,
        );
      }
      final legalMeld = _firstMeldAction(legalActions);
      if (legalMeld != null) {
        return ClassicHareegCpuMovePlan(
          scenario: ClassicHareegCpuMoveScenario.meldPlay,
          actionId: legalMeld.actionId,
        );
      }
    }

    final replacement = _firstActionOfKind(
      legalActions,
      ClassicHareegActionKind.replaceJoker,
    );
    if (replacement != null) {
      return ClassicHareegCpuMovePlan(
        scenario: ClassicHareegCpuMoveScenario.jokerReplacement,
        actionId: replacement.actionId,
      );
    }

    final cover = _firstActionOfKind(
      legalActions,
      ClassicHareegActionKind.placeCover,
    );
    if (cover != null && !_shouldHoldCover(observation, cover)) {
      return ClassicHareegCpuMovePlan(
        scenario: ClassicHareegCpuMoveScenario.cover,
        actionId: cover.actionId,
      );
    }

    final discard = _bestDiscardAction(observation, legalActions);
    if (discard != null) {
      return ClassicHareegCpuMovePlan(
        scenario: ClassicHareegCpuMoveScenario.safeDiscard,
        actionId: discard.actionId,
      );
    }

    return PriorityCpuMovePlanner.evaluate(observation.legalActionIds);
  }

  _SkilledCpuLegalAction? _firstActionOfKind(
    List<_SkilledCpuLegalAction> actions,
    ClassicHareegActionKind kind,
  ) {
    for (final action in actions) {
      if (action.descriptor.kind == kind) {
        return action;
      }
    }
    return null;
  }

  _SkilledCpuLegalAction? _firstMeldAction(
    List<_SkilledCpuLegalAction> actions,
  ) {
    for (final action in actions) {
      if (action.descriptor.isMeldPlay) {
        return action;
      }
    }
    return null;
  }

  String? _bestMeldAction(CpuObservation observation) {
    if (observation.turnPhase != TurnPhase.action) {
      return null;
    }

    final pending = observation.pendingDiscard;
    final partitions = observation.partitions
        .enumerate(
          maxPartitions: _partitionLimit,
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

    partitions.sort((left, right) {
      return _comparePartitions(observation, left, right);
    });
    final partition = partitions.first;
    final cards = _cardsForMeldAction(observation, partition);
    if (cards.isEmpty || cards.length >= observation.ownHand.length) {
      return null;
    }
    return _playMeldActionId(cards, partition.jokerAssignments);
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

  int _comparePartitions(
    CpuObservation observation,
    MeldPartition left,
    MeldPartition right,
  ) {
    final leftFinishes = left.cardsRemaining.length == 1;
    final rightFinishes = right.cardsRemaining.length == 1;
    final finishCompare = _boolDesc(leftFinishes, rightFinishes);
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

  bool _canPushBenchmark(CpuObservation observation) {
    return observation.ownHasOpened() &&
        observation.benchmarkOwner == observation.seat &&
        !observation.openingState.isLocked;
  }

  int _benchmarkPushScore(int totalValue) {
    return totalValue > _benchmarkPushTarget
        ? _benchmarkPushTarget
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

  List<HareegCard> _cardsForMeldAction(
    CpuObservation observation,
    MeldPartition partition,
  ) {
    if (!observation.ownHasOpened() || partition.cardsRemaining.length == 1) {
      return _cardsInHandOrder(observation, partition.cardsUsed);
    }

    final pending = observation.pendingDiscard;
    final melds = List<PlacedMeld>.of(partition.melds);
    melds.sort((left, right) {
      if (pending != null) {
        final leftUsesPending = _meldUsesCard(left, pending.id);
        final rightUsesPending = _meldUsesCard(right, pending.id);
        final pendingCompare = _boolDesc(leftUsesPending, rightUsesPending);
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
    return _cardsInHandOrder(observation, melds.first.cards);
  }

  bool _meldUsesCard(PlacedMeld meld, String cardId) {
    return meld.cards.any((card) => card.id == cardId);
  }

  List<HareegCard> _cardsInHandOrder(
    CpuObservation observation,
    Iterable<HareegCard> selected,
  ) {
    final selectedIds = selected.map((card) => card.id).toSet();
    return [
      for (final card in observation.ownHand)
        if (selectedIds.contains(card.id)) card,
    ];
  }

  String _playMeldActionId(
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

  bool _shouldTakeDiscard(CpuObservation observation) {
    return shouldTakeDiscardForObservation(observation);
  }

  /// True when the CPU seat owns the Fifty claim window and actually has a
  /// finishing partition — i.e. the claim would land on the success branch
  /// instead of the wrong-claim mistake branch. Shared with Expert so both
  /// planners filter the same way.
  static bool _canSuccessfullyClaimFifty(CpuObservation observation) {
    if (!observation.ownIsFiftyClaimant) return false;
    return observation.finishingPartition() != null;
  }

  /// Public variant of [_canSuccessfullyClaimFifty] for Expert / Priority
  /// planners that share the same filter.
  static bool canSuccessfullyClaimFifty(CpuObservation observation) =>
      _canSuccessfullyClaimFifty(observation);

  /// Pure predicate shared with [ExpertCpuMovePlanner] so Expert doesn't have
  /// to recurse into Skilled's full `plan()` (which would re-enumerate
  /// partitions and rebuild threat profiles) just to read this boolean.
  static bool shouldTakeDiscardForObservation(CpuObservation observation) {
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

  static bool _extendsSetToFour(HareegCard discarded, MeldPartition partition) {
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

  _SkilledCpuLegalAction? _bestDiscardAction(
    CpuObservation observation,
    List<_SkilledCpuLegalAction> actions,
  ) {
    final discards = [
      for (final action in actions)
        if (action.descriptor.isSafeDiscard)
          _DiscardCandidate(
            action: action,
            card: _cardForAction(observation, action),
          ),
    ].where((candidate) => candidate.card != null).toList();
    if (discards.isEmpty) {
      return null;
    }

    final hotRanks = _recentPickupRanks(observation);
    final recentDiscards = _recentOpponentDiscardIdentities(observation);
    final nearElimination = _nearElimination(observation);
    discards.sort((left, right) {
      final leftCard = left.card!;
      final rightCard = right.card!;
      final leftIdentity = leftCard.effectiveIdentity;
      final rightIdentity = rightCard.effectiveIdentity;

      final leftHot =
          leftIdentity != null && hotRanks.contains(leftIdentity.rank);
      final rightHot =
          rightIdentity != null && hotRanks.contains(rightIdentity.rank);
      final hotCompare = _boolAsc(leftHot, rightHot);
      if (hotCompare != 0) {
        return hotCompare;
      }

      final leftRecent =
          leftIdentity != null && recentDiscards.contains(leftIdentity.key);
      final rightRecent =
          rightIdentity != null && recentDiscards.contains(rightIdentity.key);
      final recentCompare = _boolAsc(leftRecent, rightRecent);
      if (recentCompare != 0) {
        return recentCompare;
      }

      final leftValue = _cardPipValue(leftCard);
      final rightValue = _cardPipValue(rightCard);
      final pipCompare = nearElimination
          ? leftValue.compareTo(rightValue)
          : rightValue.compareTo(leftValue);
      if (pipCompare != 0) {
        return pipCompare;
      }
      return left.action.actionId.compareTo(right.action.actionId);
    });
    return discards.first.action;
  }

  HareegCard? _cardForAction(
    CpuObservation observation,
    _SkilledCpuLegalAction action,
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

  Set<CardRank> _recentPickupRanks(CpuObservation observation) {
    return {
      for (final opponent in observation.opponents)
        for (final card in observation.discardHistory.lastPickupsBy(
          opponent,
          _discardPickupMemory,
        ))
          if (card.effectiveIdentity != null) card.effectiveIdentity!.rank,
    };
  }

  Set<String> _recentOpponentDiscardIdentities(CpuObservation observation) {
    return {
      for (final opponent in observation.opponents)
        for (final card in observation.discardHistory.lastDiscardsBy(
          opponent,
          _discardHistoryDepth,
        ))
          if (card.effectiveIdentity != null) card.effectiveIdentity!.key,
    };
  }

  bool _shouldHoldNormalFinishForFifty(CpuObservation observation) {
    if (_nearElimination(observation) ||
        observation.stockCount < _fiftyHoldStockFloor ||
        _handPipValue(observation.ownHand) <= _fiftyHoldHandValueFloor ||
        observation.finishingPartition() == null) {
      return false;
    }

    for (final opponent in observation.opponents) {
      if (observation.discardHistory
          .lastDiscardsBy(opponent, _discardHistoryDepth)
          .isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  bool _nearElimination(CpuObservation observation) {
    final thresholdWindow = observation.eliminationThreshold - 6;
    final scoreFloor = thresholdWindow > _nearEliminationScore
        ? thresholdWindow
        : _nearEliminationScore;
    return observation.ownScore >= scoreFloor;
  }

  bool _shouldHoldCover(
    CpuObservation observation,
    _SkilledCpuLegalAction cover,
  ) {
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

  int _handPipValue(List<HareegCard> cards) {
    return cards.fold<int>(0, (total, card) => total + _cardPipValue(card));
  }

  int _cardPipValue(HareegCard card) {
    return card.effectiveIdentity?.rank.value ?? 25;
  }

  int _boolDesc(bool left, bool right) {
    if (left == right) {
      return 0;
    }
    return left ? -1 : 1;
  }

  int _boolAsc(bool left, bool right) {
    if (left == right) {
      return 0;
    }
    return left ? 1 : -1;
  }
}

class _DiscardCandidate {
  const _DiscardCandidate({required this.action, required this.card});

  final _SkilledCpuLegalAction action;
  final HareegCard? card;
}
