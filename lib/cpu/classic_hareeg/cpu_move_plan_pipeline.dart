import '../../domain/classic_hareeg/game/classic_hareeg_action.dart';
import '../../domain/classic_hareeg/game/classic_hareeg_fifty_claim_planner.dart';
import '../../domain/classic_hareeg/game/classic_hareeg_finish_planner.dart';
import '../../domain/classic_hareeg/game/classic_hareeg_round.dart';
import '../../domain/classic_hareeg/models/playing_card.dart';
import 'cpu_difficulty_profile.dart';
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

    final cover = firstActionOfKind(
      actions,
      ClassicHareegActionKind.placeCover,
    );
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
/// finishing plan — i.e. the claim would land on the success branch
/// instead of the wrong-claim mistake branch.
///
/// Shared across every tier: the rules engine advertises claim-fifty for any
/// open window so humans can attempt wrong claims, and the CPU should never
/// take that branch. Cover-aware: a finish that routes through covers of
/// existing table melds counts.
bool canSuccessfullyClaimFiftyFor(CpuObservation observation) {
  if (!observation.ownIsFiftyClaimant) return false;
  final discarded = observation.topDiscard;
  if (discarded != null) {
    return ClassicHareegFiftyClaimPlanner.finishPlanForClaim(
          hand: observation.ownHand,
          discarded: discarded,
          playerOpened: observation.ownHasOpened(),
          coverTargets: coverTargetsForObservation(observation),
          openingRequirement: observation.currentOpeningRequirement,
        ) !=
        null;
  }
  return observation.finishingPartition() != null;
}

/// Every table meld in [observation] as a cover target for cover-aware
/// finish planning.
List<ClassicHareegFinishCoverTarget> coverTargetsForObservation(
  CpuObservation observation,
) {
  return [
    for (final entry in observation.tableMelds.entries)
      for (var index = 0; index < entry.value.length; index += 1)
        ClassicHareegFinishCoverTarget(
          owner: entry.key,
          meldIndex: index,
          meldCards: entry.value[index].cards,
        ),
  ];
}

/// True when the CPU should actually take a valid Fifty claim.
///
/// Validity and miss chance are intentionally separated: the rules engine still
/// decides whether a claim can finish, while the difficulty profile controls
/// whether this CPU notices the opportunity in time.
bool shouldAttemptFiftyClaimFor(
  CpuObservation observation, {
  CpuDifficultyProfile? profile,
}) {
  if (!canSuccessfullyClaimFiftyFor(observation)) {
    return false;
  }
  return !shouldMissFiftyClaimFor(observation, profile: profile);
}

/// Deterministic miss check for a valid Fifty opportunity.
///
/// The bucket is derived from visible, stable decision facts instead of random
/// process state, so replayed seeds and tests stay reproducible while the
/// difficulty profile still creates a miss distribution over many positions.
bool shouldMissFiftyClaimFor(
  CpuObservation observation, {
  CpuDifficultyProfile? profile,
}) {
  final activeProfile = profile ?? observation.difficultyProfile;
  final missChance = activeProfile.fiftyMissChance;
  if (missChance <= 0) {
    return false;
  }
  if (missChance >= 1) {
    return true;
  }

  final bucket = _stableFiftyDecisionBucket(observation);
  final threshold = (missChance * 10000).round();
  return bucket < threshold;
}

int _stableFiftyDecisionBucket(CpuObservation observation) {
  final handIds = observation.ownHand.map((card) => card.id).toList()..sort();
  final parts = [
    observation.difficulty.name,
    observation.seat.name,
    observation.topDiscard?.id ?? '-',
    observation.topDiscard?.effectiveIdentity?.key ?? '-',
    '${observation.stockCount}',
    '${observation.discardCount}',
    '${observation.currentOpeningRequirement}',
    handIds.join(','),
  ];
  return _stableBucket(parts.join('|'), modulo: 10000);
}

int _stableBucket(String value, {required int modulo}) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash % modulo;
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

/// Partition cap for [handKeepScores]'s complete-meld grouping. Matches the
/// Expert planner's fan-out; keep-scoring enumerates the hand only ONCE per
/// discard decision (group-value attribution scores every card from a single
/// grouping), so the larger cap is cheap here.
const int _keepScorePartitionCap = 256;

/// Per-card "keep score" for every card in [hand]: the value of the meld/group
/// the card belongs to in the hand's best DISJOINT grouping. Higher means more
/// worth keeping; the discard logic sheds the lowest-scoring legal card.
///
/// The grouping is built once — the best complete-meld partition (via the
/// battle-tested [MeldPartitionEnumerator], which handles jokers and ace
/// high/low) plus a max-value pair / two-run matching over the leftover cards —
/// and then each card is scored by the value of the single group it lands in.
/// Because the grouping is DISJOINT (every card belongs to exactly one group),
/// no card can claim a run/set partner that another card already used. That is
/// the whole point: it kills the double-counting the old per-card neighbour sum
/// suffered from. Concretely:
///
/// - A card committed to a complete meld scores that meld's full value, so all
///   members of a meld outrank loose cards (a run anchor is protected) — but a
///   redundant duplicate cannot borrow the meld's value, because the distinct
///   members already fill the meld and the duplicate falls to a solo group.
/// - A developing PAIR / two-run scores its group value (`value × 2` for a pair,
///   the pip sum for a two-run), so a high developing pair can outrank a low
///   COMPLETE set — matching the owner's "keep the 8s, shed the low 3-set" call.
/// - A SOLO card scores its own pip (its ceiling — a lone King beats a loose low
///   pair), UNLESS it has a rank-AND-suit twin elsewhere (a true duplicate),
///   in which case it scores 0 and is shed first.
/// - A joker is never deadwood and scores very high.
///
/// This is the single root model shared by the Expert discard comparator and the
/// coach; it subsumes the earlier hand-by-hand patches (committed-meld inflation,
/// redundant duplicates, run/set-anchor protection) under one disjoint grouping.
Map<String, int> handKeepScores(List<HareegCard> hand) {
  final scores = <String, int>{};
  var leftovers = hand;
  if (hand.length >= 3) {
    final best = MeldPartitionEnumerator.topPartitions(
      hand,
      comparator: MeldPartitionRankers.byTotalValueDesc,
      take: 1,
      safetyCap: _keepScorePartitionCap,
    );
    if (best.isNotEmpty) {
      final partition = best.first;
      for (final meld in partition.melds) {
        final value = meld.valueSnapshot;
        for (final card in meld.cards) {
          scores[card.id] = value;
        }
      }
      leftovers = partition.cardsRemaining;
    }
  }

  final partials = _bestPartials(leftovers, hand, {});
  scores.addAll(partials.scores);

  for (final card in hand) {
    scores.putIfAbsent(card.id, () => _soloScore(card, hand));
  }
  return scores;
}

/// Keep score for a single [card] within [hand]; thin lookup over
/// [handKeepScores]. Callers scoring many cards should call [handKeepScores]
/// once and read the map instead of paying the grouping cost per card.
int discardKeepScore(HareegCard card, List<HareegCard> hand) {
  return handKeepScores(hand)[card.id] ?? _soloScore(card, hand);
}

/// Solo-group value for [card]: its pip ceiling, or 0 when [hand] holds a true
/// duplicate (another card of the same rank AND suit) — a redundant copy whose
/// rank potential is already carried by its twin, so it is shed first.
int _soloScore(HareegCard card, List<HareegCard> hand) {
  if (card.isJoker) {
    return 1 << 20;
  }
  final identity = card.effectiveIdentity;
  if (identity == null) {
    return 1 << 20;
  }
  for (final other in hand) {
    if (other.id == card.id) {
      continue;
    }
    final otherIdentity = other.effectiveIdentity;
    if (otherIdentity != null &&
        otherIdentity.rank == identity.rank &&
        otherIdentity.suit == identity.suit) {
      return 0;
    }
  }
  return identity.rank.value;
}

/// True when [a] and [b] can still combine into the same meld — a SET (same
/// rank, distinct suits) or a RUN (same suit, within two ranks so a one-card gap
/// can still be filled). This is the single definition of "two cards build
/// toward a meld together", shared by the keep-score grouping ([_bestPartials])
/// and the coach's "isolated card" cover gate, so the two never drift.
///
/// A true duplicate (same rank AND suit) returns false: it can neither join a
/// set (which needs distinct suits) nor run with itself, so it is genuinely
/// isolated — consistent with [discardKeepScore] treating a redundant copy as
/// sheddable.
bool cardsCanMeldTogether(CardIdentity a, CardIdentity b) {
  if (a.rank == b.rank) {
    return a.suit != b.suit; // set: distinct suits only
  }
  if (a.suit == b.suit) {
    final distance = (a.rank.order - b.rank.order).abs();
    return distance >= 1 && distance <= 2; // run within two ranks
  }
  return false;
}

/// Best disjoint pair / two-run / solo grouping over [cards] (the leftovers a
/// complete-meld partition could not place), scoring each card by its chosen
/// group's value. A pair (same rank, distinct suits) is worth `value × 2`; a
/// two-run (same suit within two ranks) the pip sum; an unmatched card its
/// [_soloScore]. Maximises total group value, preferring a group over leaving a
/// card solo on ties, so developing pairs/runs are recognised rather than
/// dissolved. Memoised on the remaining-card signature.
({int total, Map<String, int> scores}) _bestPartials(
  List<HareegCard> cards,
  List<HareegCard> hand,
  Map<String, ({int total, Map<String, int> scores})> memo,
) {
  if (cards.isEmpty) {
    return (total: 0, scores: const <String, int>{});
  }
  final key = (cards.map((card) => card.id).toList()..sort()).join('|');
  final cached = memo[key];
  if (cached != null) {
    return cached;
  }

  final anchor = cards.first;
  final rest = cards.sublist(1);

  // Candidate: anchor stays solo. Solo is the fallback (rank 0); a tying group
  // is preferred (rank 1) so a developing pair/run is not dissolved.
  final soloValue = _soloScore(anchor, hand);
  final soloSub = _bestPartials(rest, hand, memo);
  var bestTotal = soloValue + soloSub.total;
  var bestRank = 0;
  var bestScores = <String, int>{anchor.id: soloValue, ...soloSub.scores};

  final anchorIdentity = anchor.effectiveIdentity;
  if (anchorIdentity != null && !anchor.isJoker) {
    for (var index = 0; index < rest.length; index += 1) {
      final other = rest[index];
      final otherIdentity = other.effectiveIdentity;
      if (otherIdentity == null || other.isJoker) {
        continue;
      }
      if (!cardsCanMeldTogether(anchorIdentity, otherIdentity)) {
        continue;
      }
      // Developing set (pair, distinct suits) scores value × 2; developing run
      // (same suit within two ranks) scores the pip sum.
      final groupValue = anchorIdentity.rank == otherIdentity.rank
          ? anchorIdentity.rank.value * 2
          : anchorIdentity.rank.value + otherIdentity.rank.value;
      final remaining = [
        for (var position = 0; position < rest.length; position += 1)
          if (position != index) rest[position],
      ];
      final sub = _bestPartials(remaining, hand, memo);
      final total = groupValue + sub.total;
      if (total > bestTotal || (total == bestTotal && bestRank == 0)) {
        bestTotal = total;
        bestRank = 1;
        bestScores = <String, int>{
          anchor.id: groupValue,
          other.id: groupValue,
          ...sub.scores,
        };
      }
    }
  }

  final result = (total: bestTotal, scores: bestScores);
  memo[key] = result;
  return result;
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
