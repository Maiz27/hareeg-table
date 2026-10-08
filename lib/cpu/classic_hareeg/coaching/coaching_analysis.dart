part of 'classic_hareeg_coaching_advisor.dart';

/// Discard guidance for one discard-carrying insight: the recommended card and
/// an optional hold-back warning.
class _DiscardGuidance {
  const _DiscardGuidance({
    required this.discardCardId,
    this.avoidCardId,
    this.avoidOpponent,
    this.avoidReason,
    this.avoidRank,
    this.avoidSuit,
  });

  final String discardCardId;
  final String? avoidCardId;
  final PlayerSeat? avoidOpponent;
  final CoachAvoidReason? avoidReason;
  final CardRank? avoidRank;
  final CardSuit? avoidSuit;
}

/// Read model shared across one [ClassicHareegCoachingAdvisor.adviseFor] call.
///
/// The builders each used to re-derive the same facts — the best meld partition,
/// the keep-scores, the Expert plan — independently, enumerating the partition
/// lattice several times per coaching frame. This collects those facts behind
/// `late final` fields so each is computed at most once, and ONLY if a builder
/// actually reaches for it (an opened seat never needs the keep-scores; an
/// unopened seat never needs the Expert discard). It stays a pure function of the
/// hand and observation, preserving the advisor's no-mutation/IO/time contract.
class _CoachingAnalysis {
  _CoachingAnalysis({
    required this.controller,
    required this.seat,
    required CpuObservation observation,
  }) : _observation = observation,
       hand = controller.handFor(seat);

  /// Live controller read surface for facts not exposed by [CpuObservation].
  final ClassicHareegGameController controller;

  /// Seat receiving coaching.
  final PlayerSeat seat;

  final CpuObservation _observation;

  /// The seat's current hand.
  final List<HareegCard> hand;

  /// Legal safe discard card ids for this advice pass.
  late final List<String> legalSafeDiscardIds =
      ClassicHareegCoachingAdvisor._legalSafeDiscardIds(_observation);

  /// Legal single-card cover actions for this advice pass.
  late final List<_LegalCover> legalCovers =
      ClassicHareegCoachingAdvisor._legalCovers(controller, seat);

  /// The single highest-value meld partition over [hand] — the cards worth
  /// keeping, used for opening / play-meld highlighting. Null when the hand
  /// melds nothing.
  late final MeldPartition? bestPartition = _computeBestPartition();

  /// The engine-grade full-hand finish for this turn, or null when none: fresh
  /// melds + cover placements consuming every card except one final discard.
  /// Built on the same [ClassicHareegFinishPlanner] the rules engine uses for
  /// its finish proofs, so the coach detects exactly the finishes the engine
  /// accepts — including cover-routed wins and the unopened-seat routes (the
  /// melds-only perfect hand, exempt from the opening requirement, and the
  /// cover-routed opening-finish whose fresh melds clear it).
  late final ClassicHareegFinishPlan? finishPlan = _computeFinishPlan();

  /// Per-card keep scores from the shared disjoint best-grouping model.
  late final Map<String, int> keepScores = handKeepScores(hand);

  /// The Expert brain's full plan for this observation, computed once.
  late final _expertPlan = const ExpertCpuMovePlanner().plan(_observation);

  /// The Expert brain's opponent threat model — the SAME profile its discard
  /// comparator weighs (CPU-first), so the coach's hold-back warnings narrate
  /// exactly the signals the CPUs play: recent unconsumed pickups from
  /// opponents still building, and visible run-end fits.
  late final OpponentThreatProfile threatProfile =
      OpponentThreatProfile.fromObservation(_observation);

  /// The card id the Expert brain would discard, or null when it would not
  /// discard (it can play a meld, or it is the draw phase). Lets the opened-seat
  /// discard hint match the Expert CPU without building a second whole plan.
  String? get expertDiscardId {
    final actionId = _expertPlan.actionId;
    if (actionId == null) {
      return null;
    }
    final action = ClassicHareegActionIds.describe(actionId);
    return action.isSafeDiscard ? action.cardId : null;
  }

  /// Whether the Expert brain's plan is to place a cover this turn. The coach
  /// presents cover advice ONLY when this is true, so it inherits the brain's
  /// Fifty-hold / never-burn-a-joker cover posture instead of re-deriving one.
  bool get expertCovers =>
      _expertPlan.scenario == ClassicHareegCpuMoveScenario.cover;

  /// The Expert brain's hold reason for each legal cover it would HOLD in hand
  /// rather than play, keyed by cover card id. Same brain, same call — lets
  /// the coach narrate a deliberate hold (playtest: a freshly drawn cover got
  /// no mention at all until the brain's posture flipped a turn later).
  late final Map<String, CoverHoldReason> coverHoldReasons =
      _computeCoverHoldReasons();

  /// The first legal cover the brain is holding, with its reason — the one
  /// the discard hint narrates. Null when the brain is covering this turn or
  /// no legal cover is held.
  ({_LegalCover cover, CoverHoldReason reason})? get heldCover {
    if (expertCovers) {
      return null;
    }
    for (final cover in legalCovers) {
      final reason = coverHoldReasons[cover.cardId];
      if (reason != null) {
        return (cover: cover, reason: reason);
      }
    }
    return null;
  }

  Map<String, CoverHoldReason> _computeCoverHoldReasons() {
    final reasons = <String, CoverHoldReason>{};
    for (final cover in legalCovers) {
      final reason = ExpertCpuMovePlanner.coverHoldReasonFor(
        _observation,
        CpuLegalAction(
          actionId: cover.actionId,
          descriptor: ClassicHareegActionIds.describe(cover.actionId),
        ),
      );
      if (reason != null) {
        reasons[cover.cardId] = reason;
      }
    }
    return reasons;
  }

  /// The cover action id the Expert brain chose, or null when it is not
  /// covering — lets the coach present the brain's exact cover.
  String? get expertCoverActionId => expertCovers ? _expertPlan.actionId : null;

  /// The meld-play action id the Expert brain chose, or null when its move is
  /// not a meld play — lets the play-meld hint present the brain's exact meld.
  String? get expertMeldActionId =>
      _expertPlan.scenario == ClassicHareegCpuMoveScenario.meldPlay
      ? _expertPlan.actionId
      : null;

  MeldPartition? _computeBestPartition() {
    final best = MeldPartitionEnumerator.topPartitions(
      hand,
      comparator: MeldPartitionRankers.byTotalValueDesc,
      take: 1,
      safetyCap: ClassicHareegCoachingAdvisor._partitionLimit,
    );
    return best.isEmpty ? null : best.first;
  }

  ClassicHareegFinishPlan? _computeFinishPlan() {
    // A finish needs at least one play plus the final discard; the planner's
    // meld enumeration also caps out above 20 cards (full hands stay far
    // below). The one-card trivial finish is handled directly by _addFinish.
    if (hand.length < 2 || hand.length > 20) {
      return null;
    }
    final planner = ClassicHareegFinishPlanner(
      hand,
      coverTargets: ClassicHareegFinishCoverTarget.allFrom(
        controller.tableMelds,
      ),
      // Mirrors the engine's finish proofs: an unopened seat's cover-routed
      // plan must clear the opening requirement with its fresh melds, while a
      // melds-only perfect hand stays exempt (the opening bypass).
      coverPlanMinimumMeldValue: _observation.ownHasOpened()
          ? null
          : _observation.currentOpeningRequirement,
    );
    final pendingId = controller.pendingDiscard?.id;
    for (final candidate in hand) {
      if (candidate.id == pendingId) {
        // The taken card must end the turn in a meld or cover — it can never
        // leave as the closing discard.
        continue;
      }
      final parts = planner.planWithout(candidate);
      if (parts != null) {
        return ClassicHareegFinishPlan(
          melds: parts.melds,
          covers: parts.covers,
          finalDiscard: candidate,
        );
      }
    }
    return null;
  }

  /// The material threat against discarding [card], or null when none —
  /// straight from the Expert brain's threat profile.
  OpponentThreat? threatFor(HareegCard card) =>
      threatProfile.primaryThreatFor(card);

  /// Picks the discard to recommend among the legal safe discards outside
  /// [keepIds], plus an optional hold-back warning.
  ///
  /// The NAIVE pick (lowest keep-score, danger-blind — what a learner would
  /// likely throw) is compared against the recommendation ([preferredId] when
  /// given — the Expert plan's own pick — otherwise the threat-aware safe
  /// pick). The warning fires ONLY when it changes the decision: the naive
  /// pick is materially threatened while the recommendation is not. When every
  /// option is threatened there is no warning — telling the player to avoid a
  /// card with nothing safer to offer is noise they cannot act on.
  _DiscardGuidance? discardGuidance({
    required Set<String> keepIds,
    String? preferredId,
  }) {
    final candidates = <HareegCard>[];
    for (final id in legalSafeDiscardIds) {
      if (keepIds.contains(id)) {
        continue;
      }
      final card = handCardById(hand, id);
      if (card != null) {
        candidates.add(card);
      }
    }
    if (candidates.isEmpty) {
      return null;
    }

    HareegCard pickBy(int Function(HareegCard) primary) {
      var pick = candidates.first;
      var pickPrimary = primary(pick);
      var pickScore = keepScores[pick.id] ?? 0;
      var pickPip = cardPipValue(pick);
      for (final card in candidates.skip(1)) {
        final cardPrimary = primary(card);
        final score = keepScores[card.id] ?? 0;
        final pip = cardPipValue(card);
        // Lowest keep-score wins; on a tie shed the LOWER pip so the higher-
        // ceiling card is kept (mirrors the Expert comparator's value term).
        if (cardPrimary < pickPrimary ||
            (cardPrimary == pickPrimary &&
                (score < pickScore || (score == pickScore && pip < pickPip)))) {
          pick = card;
          pickPrimary = cardPrimary;
          pickScore = score;
          pickPip = pip;
        }
      }
      return pick;
    }

    final naive = pickBy((_) => 0);
    HareegCard chosen;
    if (preferredId != null) {
      chosen = candidates.firstWhere(
        (card) => card.id == preferredId,
        orElse: () => pickBy((card) => threatFor(card) == null ? 0 : 1),
      );
    } else {
      chosen = pickBy((card) => threatFor(card) == null ? 0 : 1);
    }

    if (chosen.id == naive.id) {
      return _DiscardGuidance(discardCardId: chosen.id);
    }
    final naiveThreat = threatFor(naive);
    if (naiveThreat == null || threatFor(chosen) != null) {
      return _DiscardGuidance(discardCardId: chosen.id);
    }
    return _DiscardGuidance(
      discardCardId: chosen.id,
      avoidCardId: naive.id,
      avoidOpponent: naiveThreat.opponent,
      avoidReason: switch (naiveThreat.kind) {
        OpponentThreatKind.runEnd => CoachAvoidReason.runEnd,
        OpponentThreatKind.collecting => CoachAvoidReason.collecting,
      },
      avoidRank: naiveThreat.rank,
      avoidSuit: naiveThreat.suit,
    );
  }
}
