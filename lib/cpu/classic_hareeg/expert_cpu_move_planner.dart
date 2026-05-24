import '../../domain/classic_hareeg/game/classic_hareeg_action.dart';
import '../../domain/classic_hareeg/game/classic_hareeg_round.dart';
import '../../domain/classic_hareeg/models/playing_card.dart';
import '../../domain/classic_hareeg/rules/opening_rules.dart';
import 'cpu_move_plan.dart';
import 'cpu_observation.dart';
import 'skilled_cpu_move_planner.dart';

class _ExpertCpuLegalAction {
  const _ExpertCpuLegalAction({
    required this.actionId,
    required this.descriptor,
  });

  final String actionId;
  final ClassicHareegActionDescriptor descriptor;
}

/// Expert CPU planner with offensive Fifty posture and opponent-aware defence.
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
    final legalActions = [
      for (final id in observation.legalActionIds)
        _ExpertCpuLegalAction(
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
    if (fifty != null &&
        SkilledCpuMovePlanner.canSuccessfullyClaimFifty(observation)) {
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

    final holdForFifty = _shouldHoldForFifty(observation);
    if (!holdForFifty) {
      final meldAction = _bestMeldAction(observation);
      if (meldAction != null) {
        return ClassicHareegCpuMovePlan(
          scenario: ClassicHareegCpuMoveScenario.meldPlay,
          actionId: meldAction,
        );
      }
    }

    final replacement = _firstActionOfKind(
      legalActions,
      ClassicHareegActionKind.replaceJoker,
    );
    if (replacement != null && observation.finishingPartition() != null) {
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

    return const SkilledCpuMovePlanner().plan(observation);
  }

  _ExpertCpuLegalAction? _firstActionOfKind(
    List<_ExpertCpuLegalAction> actions,
    ClassicHareegActionKind kind,
  ) {
    for (final action in actions) {
      if (action.descriptor.kind == kind) {
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
    final cards = _cardsInHandOrder(observation, partition.cardsUsed);
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
    if (!observation.ownHasOpened()) {
      return _compareOpeningPartitions(observation, left, right);
    }

    final leftFinishes = left.cardsRemaining.length == 1;
    final rightFinishes = right.cardsRemaining.length == 1;
    final finishCompare = _boolDesc(leftFinishes, rightFinishes);
    if (finishCompare != 0) {
      return finishCompare;
    }

    if (observation.stockCount <= _thinStockCount) {
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

  int _compareOpeningPartitions(
    CpuObservation observation,
    MeldPartition left,
    MeldPartition right,
  ) {
    if (observation.benchmarkOwner == null &&
        observation.stockCount >= _freshStockCount) {
      final leftBand = _benchmarkBandScore(left.totalValue);
      final rightBand = _benchmarkBandScore(right.totalValue);
      final bandCompare = rightBand.compareTo(leftBand);
      if (bandCompare != 0) {
        return bandCompare;
      }

      final targetCompare = (left.totalValue - _benchmarkTarget)
          .abs()
          .compareTo((right.totalValue - _benchmarkTarget).abs());
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
    if (value >= _benchmarkFloor && value <= _benchmarkCeiling) {
      return 2;
    }
    if (value > _benchmarkCeiling) {
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
    // Call the shared predicate directly instead of recursing through
    // Skilled's full plan — that path re-enumerates partitions and rebuilds
    // threat profiles just to read this boolean.
    if (SkilledCpuMovePlanner.shouldTakeDiscardForObservation(observation)) {
      return true;
    }
    // Defensive thin-stock pickup only makes sense if the seat has already
    // opened (or the pickup itself can satisfy opening). Picking up an
    // unusable discard pre-opening forces the rules engine to return it,
    // and the next draw choice will face the same discard top → loop.
    if (observation.stockCount > _thinStockCount ||
        observation.topDiscard == null) {
      return false;
    }
    return observation.ownHasOpened();
  }

  bool _shouldHoldForFifty(CpuObservation observation) {
    if (observation.finishingPartition() == null ||
        observation.stockCount < _fiftyHoldStockFloor ||
        _handPipValue(observation.ownHand) <= _fiftyHoldHandValueFloor) {
      return false;
    }

    if (observation.ownScore >= _highRiskScoreFloor) {
      return true;
    }
    return observation.opponents.any((opponent) {
      return observation.scoreFor(opponent) >= _highRiskScoreFloor;
    });
  }

  bool _shouldHoldCover(
    CpuObservation observation,
    _ExpertCpuLegalAction cover,
  ) {
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

  _ExpertCpuLegalAction? _bestDiscardAction(
    CpuObservation observation,
    List<_ExpertCpuLegalAction> actions,
  ) {
    final discards = [
      for (final action in actions)
        if (action.descriptor.isSafeDiscard)
          _ExpertDiscardCandidate(
            action: action,
            card: _cardForAction(observation, action),
          ),
    ].where((candidate) => candidate.card != null).toList();
    if (discards.isEmpty) {
      return null;
    }

    final profile = _OpponentThreatProfile.fromObservation(observation);
    final holdForFifty = _shouldHoldForFifty(observation);
    discards.sort((left, right) {
      final leftCard = left.card!;
      final rightCard = right.card!;
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

      final leftValue = _cardPipValue(leftCard);
      final rightValue = _cardPipValue(rightCard);
      final valueCompare = holdForFifty
          ? rightValue.compareTo(leftValue)
          : leftValue.compareTo(rightValue);
      if (valueCompare != 0) {
        return valueCompare;
      }
      return left.action.actionId.compareTo(right.action.actionId);
    });
    return discards.first.action;
  }

  HareegCard? _cardForAction(
    CpuObservation observation,
    _ExpertCpuLegalAction action,
  ) {
    final cardId = action.descriptor.cardId;
    if (cardId == null) {
      return null;
    }
    return _cardById(observation, cardId);
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
    return _handPipValue(partition.cardsRemaining);
  }

  int _handPipValue(List<HareegCard> cards) {
    return cards.fold<int>(0, (total, card) => total + _cardPipValue(card));
  }

  static int _cardPipValue(HareegCard card) {
    return card.effectiveIdentity?.rank.value ?? 25;
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

  int _boolDesc(bool left, bool right) {
    if (left == right) {
      return 0;
    }
    return left ? -1 : 1;
  }
}

class _ExpertDiscardCandidate {
  const _ExpertDiscardCandidate({required this.action, required this.card});

  final _ExpertCpuLegalAction action;
  final HareegCard? card;
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
    if (!_isConsecutive(orders)) {
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

  static bool _isConsecutive(List<int> orders) {
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
