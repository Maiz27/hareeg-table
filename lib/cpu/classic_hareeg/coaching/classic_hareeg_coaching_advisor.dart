import '../../../domain/classic_hareeg/game/classic_hareeg_fifty_claim_planner.dart'
    show ClassicHareegFiftyClaimPlanner, ClassicHareegFinishPlan;
import '../../../domain/classic_hareeg/game/classic_hareeg_finish_planner.dart';
import '../../../domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import '../../../domain/classic_hareeg/game/classic_hareeg_round.dart'
    show TurnPhase;
import '../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../domain/classic_hareeg/rules/cover_rules.dart';
import '../../../domain/classic_hareeg/models/classic_hareeg_setup.dart'
    show CpuDifficulty;
import '../cpu_move_plan.dart' show ClassicHareegCpuMoveScenario;
import '../cpu_move_plan_pipeline.dart'
    show CpuLegalAction, cardPipValue, cardsCanMeldTogether, handKeepScores;
import '../cpu_observation.dart';
import '../expert_cpu_move_planner.dart';
import 'coaching_insight.dart';

typedef _LegalCover = ({
  String actionId,
  String cardId,
  PlayerSeat owner,
  int meldIndex,
  List<String> meldCardIds,
});

/// Pure, structured coaching advisor for Classic Hareeg.
///
/// [adviseFor] is a pure function of the passed-in controller state and seat:
/// no mutation, no I/O, no time. It reuses the same analysis brain the Expert
/// CPU uses ([CpuObservation] / [MeldPartitionEnumerator] / cover rules) to
/// classify the human player's situation into prioritized [CoachingInsight]s.
///
/// The advisor emits localization-free structured data only; mapping each
/// insight to EN/AR text is the UI stage's job. Cross-turn dedup (stage
/// banners showing once per round) is also the UI stage's job
/// ([CoachInsightFlow]) — the advisor stays pure and re-emits every applicable
/// insight on every call.
abstract final class ClassicHareegCoachingAdvisor {
  // Insight priorities live on [CoachingInsightCategory] (a single descending
  // ladder); each builder passes its category's `.priority` so the ordering is
  // never restated here.

  // Cap matching the Expert planner's partition fan-out.
  static const _partitionLimit = 256;

  // An opened opponent at or below this many cards triggers the
  // close-to-finish stage banner.
  static const _opponentCloseHandMax = 3;

  /// Returns priority-sorted coaching insights for [seat] given [controller].
  ///
  /// Highest-priority insight is first; callers may show only `result.first`
  /// (the live table routes the list through [CoachInsightFlow] so stage
  /// banners dedupe per round).
  static List<CoachingInsight> adviseFor(
    ClassicHareegGameController controller,
    PlayerSeat seat,
  ) {
    final observation = _observationFor(controller, seat);
    // One shared read model for the whole call: the best meld partition, the
    // keep-scores, and the Expert plan are each derived at most once (lazily)
    // and reused by every builder, instead of each builder re-enumerating the
    // same partition lattice.
    final analysis = _CoachingAnalysis(
      controller: controller,
      seat: seat,
      observation: observation,
    );
    final insights = <CoachingInsight>[];

    _addFinish(controller, seat, observation, analysis, insights);
    _addFifty(controller, seat, observation, insights);
    _addTakeAndFinish(controller, seat, observation, insights);
    _addOpening(controller, seat, observation, analysis, insights);
    _addPlayMeld(controller, seat, analysis, insights);
    _addPickup(controller, seat, observation, insights);
    // Cover advice is driven by the Expert plan (see _addCover). Order matters:
    // it runs before _addDiscardSuggestion, which suppresses its floor when the
    // plan surfaced a cover instead.
    _addCover(controller, seat, analysis, insights);
    _addJokerAdvice(controller, seat, insights);
    _addStageBanners(controller, seat, observation, insights);
    _addDiscardSuggestion(controller, seat, observation, analysis, insights);
    _addDrawStock(seat, observation, insights);

    insights.sort((left, right) => right.priority.compareTo(left.priority));
    return List.unmodifiable(insights);
  }

  static CpuObservation _observationFor(
    ClassicHareegGameController controller,
    PlayerSeat seat,
  ) {
    return LiveCpuObservation(
      controller: controller,
      seat: seat,
      legalActionIds: controller.legalActionIdsFor(seat),
      // The coach always reasons at the strongest level, independent of the
      // table's CPU difficulty, so it teaches expert-grade moves (discards,
      // covers, lay-offs) regardless of who the player is sitting against.
      difficulty: CpuDifficulty.expert,
    );
  }

  // 1. finishAvailable / fiftyHold — the seat can empty its hand this turn.
  // Detection runs on the engine's own [ClassicHareegFinishPlanner] (via
  // [_CoachingAnalysis.finishPlan]), so the coach sees every finish the rules
  // accept: melds-only, cover-routed (cards laid onto existing table melds),
  // and the unopened-seat routes — the perfect-hand opening bypass and the
  // opening-finish whose fresh melds clear the requirement. (The playtest gap:
  // a 3-card set + a cover + the final discard was a full win AND the player's
  // opening, but the melds-only partition scan saw only "you can lay a meld".)
  // When the Expert brain would HOLD the finish to chase a Fifty, the coach
  // surfaces fiftyHold instead of contradicting it with a bare "you can win".
  static void _addFinish(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    CpuObservation observation,
    _CoachingAnalysis analysis,
    List<CoachingInsight> out,
  ) {
    if (observation.turnPhase != TurnPhase.action) {
      // A normal finish needs the seat to act on its hand, which only happens
      // after it has drawn. In the draw phase the actionable hint is to draw
      // (or take the discard) first — surfacing "you can win" here is premature
      // (e.g. down to one card at the start of the turn: you must draw before
      // you can discard it). The Fifty/pickup paths cover draw-phase finishes.
      return;
    }
    // Relaxed taken-discard rule: the pending (or claimed) card can never be
    // the closing discard. [finishPlan] never selects it as the final discard
    // (and uses every other card), but the one-card trivial case below can
    // reach a hand holding ONLY the unused pending card; guard it directly.
    final pendingId = controller.pendingDiscard?.id;
    // The trivial finish: a single card left, where discarding it empties the
    // hand and wins (a final discard is exempt from the cover block). The
    // planner has no melds to prove for a one-card hand, so detect this
    // directly and ring the last card. Opened seats only — an unopened seat
    // cannot reach a one-card hand.
    final hand = analysis.hand;
    if (hand.length == 1) {
      if (!observation.ownHasOpened() || hand.first.id == pendingId) {
        return;
      }
      out.add(
        CoachingInsight(
          category: CoachingInsightCategory.finishAvailable,
          priority: CoachingInsightCategory.finishAvailable.priority,
          highlightCardIds: [hand.first.id],
        ),
      );
      return;
    }
    final plan = analysis.finishPlan;
    if (plan == null) {
      return;
    }
    // CPU-first: when Expert holds this finish for a Fifty, teach the hold —
    // otherwise the visible discard suggestion below the finish looks wrong to
    // a player who can see their own win. (The hold gate reasons on the
    // melds-only finishing partition, so a cover-routed plan never holds: its
    // Fifty kernel cannot be re-proven after the covers are spent.)
    if (ExpertCpuMovePlanner.holdsNormalFinishForFifty(observation)) {
      _emitFiftyHold(observation, analysis, plan, out);
      return;
    }
    out.add(
      CoachingInsight(
        category: CoachingInsightCategory.finishAvailable,
        priority: CoachingInsightCategory.finishAvailable.priority,
        coverFinishes: plan.covers.isNotEmpty,
        bypassesOpening: !observation.ownHasOpened(),
        discardCardId: plan.finalDiscard.id,
        highlightCardIds: [
          for (final group in _finishPlanGroups(controller, plan)) ...group,
        ],
        meldGroups: _finishPlanGroups(controller, plan),
      ),
    );
  }

  // The fiftyHold insight: the finish stays ringed so the player sees the
  // choice, the punishable seat is named, and the hold-sustaining throw is
  // recommended.
  static void _emitFiftyHold(
    CpuObservation observation,
    _CoachingAnalysis analysis,
    ClassicHareegFinishPlan plan,
    List<CoachingInsight> out,
  ) {
    // A Fifty's +3 can only hit the seat whose discard the claim takes — the
    // active seat immediately before this one (the Expert hold gate already
    // weighed exactly that seat). Naming anyone else is factually wrong: the
    // playtest hint implied the high-score seat across the table would pay.
    final ownScore = observation.ownScore;
    final subjectIsSelf =
        ownScore >= ExpertCpuMovePlanner.highRiskScoreFloor;
    final target = subjectIsSelf
        ? observation.seat
        : ExpertCpuMovePlanner.fiftyPunishTarget(observation);
    if (target == null) {
      return;
    }
    out.add(
      CoachingInsight(
        category: CoachingInsightCategory.fiftyHold,
        priority: CoachingInsightCategory.fiftyHold.priority,
        subjectSeat: target,
        subjectIsSelf: subjectIsSelf,
        subjectValue: subjectIsSelf ? ownScore : observation.scoreFor(target),
        // The throw that keeps the hold alive — the Expert plan's own discard,
        // drawn from the LEGAL surface, so a cover-blocked card (which cannot
        // leave as a plain discard) is never recommended. Without this the
        // hint said "hold" but left the player guessing how to end the turn.
        discardCardId: analysis.expertDiscardId,
        highlightCardIds: [
          for (final meld in plan.melds)
            for (final card in meld.cards) card.id,
        ],
        meldGroups: [
          for (final meld in plan.melds)
            [for (final card in meld.cards) card.id],
        ],
      ),
    );
  }

  // Ring groups for a full finish plan: each fresh meld, then each cover with
  // the table meld it extends (both ends of the lay-off), in play order.
  static List<List<String>> _finishPlanGroups(
    ClassicHareegGameController controller,
    ClassicHareegFinishPlan plan,
  ) {
    final groups = <List<String>>[
      for (final meld in plan.melds)
        [for (final card in meld.cards) card.id],
    ];
    for (final cover in plan.covers) {
      final melds = controller.tableMeldsFor(cover.targetSeat);
      groups.add([
        for (final card in cover.cards) card.id,
        if (cover.meldIndex >= 0 && cover.meldIndex < melds.length)
          for (final card in melds[cover.meldIndex].cards) card.id,
      ]);
    }
    return groups;
  }

  // 2. fiftyAvailable — the seat owns the Fifty window AND `claim-fifty` is
  // live on the legal surface. The window object outlives its timer (it is
  // only cleared by the next action), so gating on `fiftyClaimant` alone kept
  // advising "Claim the Fifty" after the timer lapsed — an impossible action;
  // once the advertisement is gone, the take-and-finish hint takes over and
  // teaches the −1 path instead. No bespoke finish check is needed: on the
  // coaching tier the engine only advertises the claim after validating a
  // full finish proof (fiftyClaimNeedsFinishProofForAdvertise), including the
  // cover-routed finishes a melds-only partition scan would miss.
  static void _addFifty(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    CpuObservation observation,
    List<CoachingInsight> out,
  ) {
    if (observation.fiftyClaimant != seat) {
      return;
    }
    if (!observation.legalActionIds.contains(
      ClassicHareegActionIds.claimFifty,
    )) {
      return;
    }
    final topDiscard = controller.topDiscard;
    if (topDiscard == null) {
      return;
    }
    out.add(
      CoachingInsight(
        category: CoachingInsightCategory.fiftyAvailable,
        priority: CoachingInsightCategory.fiftyAvailable.priority,
        highlightCardIds: [topDiscard.id],
      ),
    );
  }

  // 3. takeAndFinish — no live Fifty claim is available to the seat, but
  // taking the top discard still completes a finish for the normal −1. Teaches
  // the claim-vs-take distinction (a lapsed window does NOT take the finish
  // away, only the −3) that confused real players.
  static void _addTakeAndFinish(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    CpuObservation observation,
    List<CoachingInsight> out,
  ) {
    if (_containsCategory(out, CoachingInsightCategory.fiftyAvailable)) {
      // The claim hint owns this discard while the claim is live.
      return;
    }
    final topDiscard = controller.topDiscard;
    if (topDiscard == null) {
      return;
    }
    if (!observation.legalActionIds.contains(
      ClassicHareegActionIds.takeDiscard,
    )) {
      return;
    }
    if (!_finishesOnTopDiscard(controller, seat, observation, topDiscard)) {
      return;
    }
    out.add(
      CoachingInsight(
        category: CoachingInsightCategory.takeAndFinish,
        priority: CoachingInsightCategory.takeAndFinish.priority,
        highlightCardIds: [topDiscard.id],
      ),
    );
  }

  // Whether [seat]'s hand plus [topDiscard] is a full finish that consumes
  // the discard and ends with exactly one final discard. Proven by the same
  // [ClassicHareegFiftyClaimPlanner] proof the engine uses (it plans melds +
  // covers over the hand plus the taken card and requires the taken card to
  // be used), so cover-routed take-and-finishes are detected — the old
  // melds-only partition scan under-promised on them. Mirrors the engine's
  // pickup realizability rule for an UNOPENED seat: the taken card must land
  // in a fresh meld (covers need a prior opening, but the taken card must be
  // used immediately), so it is barred from cover use in that proof.
  static bool _finishesOnTopDiscard(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    CpuObservation observation,
    HareegCard topDiscard,
  ) {
    final hand = controller.handFor(seat);
    final coverTargets = ClassicHareegFinishCoverTarget.allFrom(
      controller.tableMelds,
    );
    if (!observation.ownHasOpened()) {
      final planner = ClassicHareegFinishPlanner(
        [...hand, topDiscard],
        coverTargets: coverTargets,
        coverPlanMinimumMeldValue: observation.currentOpeningRequirement,
        coverDisallowedCardIds: {topDiscard.id},
      );
      if (!planner.hasValidMeldContaining(topDiscard.id)) {
        return false;
      }
      return ClassicHareegFiftyClaimPlanner.finishPlanForClaim(
            hand: hand,
            discarded: topDiscard,
            playerOpened: false,
            planner: planner,
          ) !=
          null;
    }
    return ClassicHareegFiftyClaimPlanner.finishPlanForClaim(
          hand: hand,
          discarded: topDiscard,
          playerOpened: true,
          coverTargets: coverTargets,
          openingRequirement: observation.currentOpeningRequirement,
        ) !=
        null;
  }

  // 4. openNow vs openingProgress — an unopened seat. Best openable value comes
  // from the highest-value partition. If it clears the requirement we surface
  // openNow with the play action; otherwise openingProgress with the shortfall.
  //
  // Deliberate divergence from the Expert opening-band posture: Expert may open
  // in the 70–80 band as first opener instead of at max value. The coach shows
  // the max-value partition — "open fat as first opener" is the same defensible
  // lesson, and ringing a partition the copy's number does not match would
  // confuse more than the band nuance teaches.
  static void _addOpening(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    CpuObservation observation,
    _CoachingAnalysis analysis,
    List<CoachingInsight> out,
  ) {
    if (observation.ownHasOpened()) {
      return;
    }
    // Value already committed to the table this turn as STAGED opening melds.
    // While the seat is mid-opening (not yet fully opened) those melds count
    // toward the requirement, so the remaining hand only has to cover the rest.
    // Without this the hint ignores the staged melds (e.g. "45/51, 6 to go"
    // after staging a 30-set) and lands at low priority, letting an unrelated
    // cover hint outrank the "lay these to finish opening" guidance.
    var stagedValue = 0;
    for (final meld in controller.tableMeldsFor(seat)) {
      for (final card in meld.cards) {
        stagedValue += cardPipValue(card);
      }
    }
    final partition = analysis.bestPartition;
    final requirement = observation.currentOpeningRequirement;
    if (partition == null) {
      // No melds in hand: teach the (staged-adjusted) shortfall, and name the
      // lowest-potential card to shed (no keepers to protect yet).
      final shortfall = requirement - stagedValue;
      final guidance = analysis.discardGuidance(keepIds: const {});
      out.add(
        CoachingInsight(
          category: CoachingInsightCategory.openingProgress,
          priority: CoachingInsightCategory.openingProgress.priority,
          openingShortfall: shortfall > 0 ? shortfall : 0,
          openingBestValue: stagedValue,
          openingRequirement: requirement,
          discardCardId: guidance?.discardCardId,
          avoidCardId: guidance?.avoidCardId,
          avoidOpponent: guidance?.avoidOpponent,
          avoidReason: guidance?.avoidReason,
          avoidRank: guidance?.avoidRank,
          avoidSuit: guidance?.avoidSuit,
        ),
      );
      return;
    }
    final effectiveValue = stagedValue + partition.totalValue;
    final highlight = [for (final card in partition.cardsUsed) card.id];
    // openNow is an ACTION-phase instruction — opening happens after the
    // draw. In the draw phase a requirement-meeting hand falls through to
    // openingProgress (shortfall clamped to 0), which the draw hint folds in
    // as "you can open after drawing" instead of hijacking the draw decision.
    if (effectiveValue >= requirement &&
        observation.turnPhase == TurnPhase.action) {
      out.add(
        CoachingInsight(
          category: CoachingInsightCategory.openNow,
          priority: CoachingInsightCategory.openNow.priority,
          openingBestValue: effectiveValue,
          openingRequirement: requirement,
          meldActionId: ClassicHareegActionIds.playMeldActionId(
            partition.melds.first.cards.map((card) => card.id),
          ),
          highlightCardIds: highlight,
          meldGroups: _groupsOf(partition),
        ),
      );
      return;
    }
    // Choose the discard from cards OUTSIDE the highlighted keep partition,
    // so the hint never rings a card teal ("keep") and pink ("discard") at
    // once — e.g. it must not tell you to shed the 4♣ that anchors the very
    // 4-5-6-7 run it is telling you to keep.
    final guidance = analysis.discardGuidance(keepIds: highlight.toSet());
    final shortfall = requirement - effectiveValue;
    out.add(
      CoachingInsight(
        category: CoachingInsightCategory.openingProgress,
        priority: CoachingInsightCategory.openingProgress.priority,
        // Clamped: a draw-phase hand that already meets the requirement
        // carries shortfall 0, which the draw hint presents as "you can open
        // after drawing".
        openingShortfall: shortfall > 0 ? shortfall : 0,
        openingBestValue: effectiveValue,
        openingRequirement: requirement,
        highlightCardIds: highlight,
        meldGroups: _groupsOf(partition),
        discardCardId: guidance?.discardCardId,
        avoidCardId: guidance?.avoidCardId,
        avoidOpponent: guidance?.avoidOpponent,
        avoidReason: guidance?.avoidReason,
        avoidRank: guidance?.avoidRank,
        avoidSuit: guidance?.avoidSuit,
      ),
    );
  }

  // 5. playMeld — an opened seat that can lay a complete meld from hand.
  //
  // A full meld is always better coaching than breaking a single card off for a
  // cover, so this must surface (priority 700) ahead of the cover hint (550)
  // whenever a settable meld exists. CPU-first: when the Expert plan's chosen
  // move IS a meld play, present exactly that meld. Otherwise fall back to an
  // advertised play-meld id, then to enumerating the hand directly: the legal
  // surface's candidate generator can miss a valid meld, and a pending discard
  // narrows the surface to only melds using that card — in both cases the
  // player still has a complete meld worth laying, and the coach should point
  // at it.
  static void _addPlayMeld(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    _CoachingAnalysis analysis,
    List<CoachingInsight> out,
  ) {
    if (controller.turnPhase != TurnPhase.action) {
      // A meld can only be laid AFTER the draw. Without this gate a meldable
      // hand (e.g. a joker set) hijacked the whole draw phase at priority 700
      // — the coach kept saying "lay this meld" while the actual decision was
      // draw-vs-take (the playtest joker fixation).
      return;
    }
    if (!controller.openingState.hasOpened(seat)) {
      return;
    }
    final planMeldId = analysis.expertMeldActionId;
    if (planMeldId != null) {
      final action = ClassicHareegActionIds.describe(planMeldId);
      if (action.isMeldPlay) {
        _emitPlayMeld(controller, seat, analysis, action.cardIds, planMeldId, out);
        return;
      }
    }
    for (final id in controller.legalActionIdsFor(seat)) {
      final action = ClassicHareegActionIds.describe(id);
      if (action.isMeldPlay) {
        _emitPlayMeld(controller, seat, analysis, action.cardIds, id, out);
        return;
      }
    }

    // Relaxed taken-discard rule: melds that do not use the pending card are
    // legal, so the fallback may suggest them — the turn simply cannot end
    // while the taken card sits unused.
    final hand = analysis.hand;
    final partition = analysis.bestPartition;
    if (partition == null) {
      return;
    }
    // Pick a standalone settable meld (a set or run of 3+). Playing it must
    // still leave at least one card for the turn-ending discard, mirroring the
    // rules engine's regular-meld eligibility.
    for (final meld in partition.melds) {
      if (meld.cards.length < 3 || meld.cards.length >= hand.length) {
        continue;
      }
      final cardIds = [for (final card in meld.cards) card.id];
      _emitPlayMeld(
        controller,
        seat,
        analysis,
        cardIds,
        ClassicHareegActionIds.playMeldActionId(cardIds),
        out,
      );
      return;
    }
  }

  // Emits a playMeld insight for [meldCardIds], and when the seat ALSO holds an
  // isolated card that lays off as a cover, COMBINES it into the same hint (a
  // second ring group + an "also lay off X" line in the presenter), so the
  // player sees both plays at once instead of just the meld.
  static void _emitPlayMeld(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    _CoachingAnalysis analysis,
    List<String> meldCardIds,
    String? meldActionId,
    List<CoachingInsight> out,
  ) {
    var cover = _isolatedCoverFor(controller, seat, meldCardIds.toSet());
    if (cover != null &&
        analysis.coverHoldReasons[cover.cardId] ==
            CoverHoldReason.fiftyDevelopment) {
      // The brain is holding that lay-off to protect a developing Fifty —
      // combining it into the meld hint would push the exact play the brain
      // declined. An own-run-end hold stays combined: it is a soft timing
      // preference, and the combined "play the meld + lay this off" display
      // is owner-validated for that shape. (A joker never reaches here —
      // [_isolatedCoverFor] skips jokers.)
      cover = null;
    }
    final highlight = <String>[...meldCardIds];
    final groups = <List<String>>[List<String>.of(meldCardIds)];
    if (cover != null) {
      final coverGroup = [cover.cardId, ...cover.meldCardIds];
      highlight.addAll(coverGroup);
      groups.add(coverGroup);
    }
    out.add(
      CoachingInsight(
        category: CoachingInsightCategory.playMeld,
        priority: CoachingInsightCategory.playMeld.priority,
        meldActionId: meldActionId,
        coverCardId: cover?.cardId,
        coverMeldOwner: cover?.owner,
        coverMeldIndex: cover?.meldIndex,
        highlightCardIds: highlight,
        meldGroups: groups,
      ),
    );
  }

  // The first ISOLATED hand card (not in [exclude], not a joker, sharing no rank
  // or near-suit with another hand card) that lays off as a cover onto any table
  // meld (own or opponent's). Shared by the play-meld combine and the standalone
  // lay-off hint. Returns the card, the meld's owner/index, and the meld's card
  // ids (for highlighting), or null when no such cover exists.
  static ({
    String cardId,
    PlayerSeat owner,
    int meldIndex,
    List<String> meldCardIds,
  })?
  _isolatedCoverFor(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    Set<String> exclude,
  ) {
    final hand = controller.handFor(seat);
    final owners = [seat, ..._opponentsOf(controller, seat)];
    for (final owner in owners) {
      final melds = controller.tableMeldsFor(owner);
      for (var index = 0; index < melds.length; index += 1) {
        for (final card in hand) {
          final identity = card.effectiveIdentity;
          if (card.isJoker || identity == null || exclude.contains(card.id)) {
            continue;
          }
          if (_hasMeldPartner(hand, card, identity)) {
            continue;
          }
          final extension = ClassicHareegCoverRules.resolveCoverExtension(
            tableMeld: melds[index].cards,
            candidate: card,
          );
          if (extension == null) {
            continue;
          }
          return (
            cardId: card.id,
            owner: owner,
            meldIndex: index,
            meldCardIds: [
              for (final meldCard in melds[index].cards) meldCard.id,
            ],
          );
        }
      }
    }
    return null;
  }

  // 6. pickupCompletesMeld / baitDiscard — taking the top discard would
  // complete/improve a meld: a legal partition uses the discard and leaves
  // fewer cards in hand. For an UNOPENED seat the partition must also clear
  // the opening requirement — a pickup that fits the hand but cannot open is
  // the classic bait: taking it reveals the plan for nothing, so the coach
  // surfaces the bait-discard lesson instead of staying silent about why the
  // tempting card should be left alone.
  static void _addPickup(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    CpuObservation observation,
    List<CoachingInsight> out,
  ) {
    final topDiscard = controller.topDiscard;
    if (topDiscard == null) {
      return;
    }
    if (!observation.legalActionIds.contains(
      ClassicHareegActionIds.takeDiscard,
    )) {
      return;
    }
    final hand = controller.handFor(seat);
    final withDiscard = [...hand, topDiscard];
    final fitting = MeldPartitionEnumerator.topPartitions(
      withDiscard,
      comparator: MeldPartitionRankers.byCoverSurfaceDesc,
      take: 1,
      mustUseCardId: topDiscard.id,
      safetyCap: _partitionLimit,
    );
    if (fitting.isEmpty || fitting.first.cardsRemaining.length >= hand.length) {
      // The discard does not pull any hand card into a meld.
      return;
    }
    if (!observation.ownHasOpened()) {
      final openable = MeldPartitionEnumerator.topPartitions(
        withDiscard,
        comparator: MeldPartitionRankers.byCoverSurfaceDesc,
        take: 1,
        mustUseCardId: topDiscard.id,
        minTotalValue: observation.currentOpeningRequirement,
        safetyCap: _partitionLimit,
      );
      if (openable.isEmpty ||
          openable.first.cardsRemaining.length >= hand.length) {
        // Fits, but cannot reach the opening value: the bait lesson.
        out.add(
          CoachingInsight(
            category: CoachingInsightCategory.baitDiscard,
            priority: CoachingInsightCategory.baitDiscard.priority,
            highlightCardIds: [topDiscard.id],
          ),
        );
        return;
      }
      _emitPickup(openable.first, topDiscard, out);
      return;
    }
    _emitPickup(fitting.first, topDiscard, out);
  }

  static void _emitPickup(
    MeldPartition partition,
    HareegCard topDiscard,
    List<CoachingInsight> out,
  ) {
    out.add(
      CoachingInsight(
        category: CoachingInsightCategory.pickupCompletesMeld,
        priority: CoachingInsightCategory.pickupCompletesMeld.priority,
        highlightCardIds: [
          topDiscard.id,
          for (final card in partition.cardsUsed)
            if (card.id != topDiscard.id) card.id,
        ],
      ),
    );
  }

  // 7. Cover advice, driven ENTIRELY by the Expert plan's chosen move. When the
  // plan places a cover, the coach presents it; when the plan instead HOLDS — it
  // keeps a developing hand or a joker for a Fifty and discards — the coach shows
  // the plan's discard (via _addDiscardSuggestion), never a bespoke cover hint.
  //
  // This is the CPU-first contract: the Expert brain decides whether covering is
  // the right move (it carries the Fifty-hold / never-burn-a-joker posture), and
  // the coach only teaches that decision. The old bespoke re-detection
  // (_addCoverKeep + a standalone lay-off hint) diverged from the brain and
  // produced the playtest bugs — pushing a held joker onto a cover, covering a
  // card away when holding for a Fifty was better, and blacking out entirely in a
  // cover-only endgame the bespoke detector bailed on.
  //
  // Two presentation extras layer on top of the plan's move: a finish-by-cover
  // (covering empties the hand → a win) is reframed at finish priority, and
  // several independent covers are surfaced as a choice.
  static void _addCover(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    _CoachingAnalysis analysis,
    List<CoachingInsight> out,
  ) {
    // Covering needs an opened seat; gating here also avoids building the Expert
    // plan for unopened seats (guided instead by openNow / openingProgress).
    if (!controller.openingState.hasOpened(seat)) {
      return;
    }
    if (!analysis.expertCovers) {
      return;
    }
    final covers = analysis.legalCovers;
    if (covers.isEmpty) {
      return;
    }

    // Finish-by-cover: the seat cannot end its turn with a plain discard
    // (cover-only surface), so it must cover its way out — covering empties the
    // hand and wins. The rules engine advertises covers one at a time, so we key
    // off "no legal safe discard" (Issue A's exact state) rather than trying to
    // see every cover at once. _addFinish handles meld-based finishes; this is
    // the cover-only endgame its enumerator misses — the blackout the bespoke
    // detector hit (covers on an opponent meld, no safe discard, it bailed).
    final hasSafeDiscard = analysis.legalSafeDiscardIds.isNotEmpty;
    if (!hasSafeDiscard &&
        !_containsCategory(out, CoachingInsightCategory.finishAvailable)) {
      final groups = [
        for (final cover in covers) [cover.cardId, ...cover.meldCardIds],
      ];
      out.add(
        CoachingInsight(
          category: CoachingInsightCategory.finishAvailable,
          priority: CoachingInsightCategory.finishAvailable.priority,
          coverFinishes: true,
          highlightCardIds: [for (final group in groups) ...group],
          meldGroups: groups,
        ),
      );
      return;
    }

    // Present the plan's chosen cover. When several independent covers exist
    // (distinct hand cards) surface them as a choice and ring each option in its
    // own group.
    final coverableIds = {for (final cover in covers) cover.cardId};
    final planCover = covers.firstWhere(
      (cover) => cover.actionId == analysis.expertCoverActionId,
      orElse: () => covers.first,
    );
    final isChoice = coverableIds.length > 1;
    final groups = isChoice
        ? [
            for (final cover in covers) [cover.cardId, ...cover.meldCardIds],
          ]
        : const <List<String>>[];
    out.add(
      CoachingInsight(
        category: CoachingInsightCategory.playCover,
        priority: CoachingInsightCategory.playCover.priority,
        coverCardId: planCover.cardId,
        coverMeldOwner: planCover.owner,
        coverMeldIndex: planCover.meldIndex,
        coverIsChoice: isChoice,
        highlightCardIds: isChoice
            ? [for (final group in groups) ...group]
            : [planCover.cardId, ...planCover.meldCardIds],
        meldGroups: groups,
      ),
    );
  }

  // All legal single-card place-cover actions for [seat], decoded to the cover
  // card id, the target meld's owner/index, and the meld's card ids (so the hint
  // can ring both ends of each lay-off).
  static List<_LegalCover> _legalCovers(
    ClassicHareegGameController controller,
    PlayerSeat seat,
  ) {
    final covers = <_LegalCover>[];
    for (final id in controller.legalActionIdsFor(seat)) {
      final action = ClassicHareegActionIds.describe(id);
      if (action.kind != ClassicHareegActionKind.placeCover) {
        continue;
      }
      final target = action.coverTarget;
      if (target == null || action.cardIds.length != 1) {
        continue;
      }
      final melds = controller.tableMeldsFor(target.targetSeat);
      if (target.meldIndex < 0 || target.meldIndex >= melds.length) {
        continue;
      }
      covers.add((
        actionId: id,
        cardId: action.cardIds.single,
        owner: target.targetSeat,
        meldIndex: target.meldIndex,
        meldCardIds: [
          for (final card in melds[target.meldIndex].cards) card.id,
        ],
      ));
    }
    return covers;
  }

  // 8. jokerAdvice — the seat can replace a represented joker on the table with
  // a real card it holds (a concrete, actionable upgrade). A replace-joker id
  // on the legal surface is the cleanest signal. Outranks playMeld (see the
  // category doc): the swap is free and must come FIRST — when the swap card
  // also anchors a playable meld, melding first burns the swap, so the hint
  // folds that meld in ("your meld still works after the swap") instead of
  // letting the meld hint shadow the better move.
  static void _addJokerAdvice(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    List<CoachingInsight> out,
  ) {
    for (final id in controller.legalActionIdsFor(seat)) {
      final action = ClassicHareegActionIds.describe(id);
      if (action.kind == ClassicHareegActionKind.replaceJoker) {
        // Ring the hand card AND the table meld that holds the joker it
        // replaces, so the hint points at both ends of the swap (the hand card
        // alone left the player guessing which table meld to act on).
        final target = action.jokerReplacementTarget;
        final meldCardIds = <String>[];
        if (target != null) {
          final melds = controller.tableMeldsFor(target.targetSeat);
          if (target.meldIndex >= 0 && target.meldIndex < melds.length) {
            for (final card in melds[target.meldIndex].cards) {
              meldCardIds.add(card.id);
            }
          }
        }
        // The swap card may also anchor a playable in-hand meld (playtest:
        // 8♥ 8♦ + a drawn 8♣ that could reclaim the table joker). Carry that
        // meld as a ring group so the hint teaches both: swap first, the
        // meld still works with the freed joker in the 8♣'s place.
        List<String> swapMeldGroup = const [];
        final cardId = action.cardId;
        if (cardId != null) {
          for (final insight in out) {
            if (insight.category != CoachingInsightCategory.playMeld) {
              continue;
            }
            for (final group in insight.meldGroups) {
              if (group.contains(cardId)) {
                swapMeldGroup = group;
                break;
              }
            }
            if (swapMeldGroup.isNotEmpty) {
              break;
            }
          }
        }
        out.add(
          CoachingInsight(
            category: CoachingInsightCategory.jokerAdvice,
            priority: CoachingInsightCategory.jokerAdvice.priority,
            jokerCardId: cardId,
            jokerReplacementActionId: id,
            highlightCardIds: [
              ?cardId,
              ...meldCardIds,
              for (final id in swapMeldGroup)
                if (id != cardId) id,
            ],
            meldGroups: swapMeldGroup.isEmpty ? const [] : [swapMeldGroup],
          ),
        );
        return;
      }
    }
  }

  // 9. Stage banners — game-stage posture the brain already weighs but the
  // coach never narrated: score pressure, thin stock, an opponent about to
  // finish, a raised benchmark. Emitted on every applicable call (the advisor
  // is pure); the UI's [CoachInsightFlow] shows each at most once per round so
  // they teach without nagging.
  static void _addStageBanners(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    CpuObservation observation,
    List<CoachingInsight> out,
  ) {
    // scorePosture — self at high risk wins over an opponent target: the
    // player's own survival changes every decision; pressing a lead changes a
    // few.
    final ownScore = observation.ownScore;
    if (ownScore >= ExpertCpuMovePlanner.highRiskScoreFloor) {
      out.add(
        CoachingInsight(
          category: CoachingInsightCategory.scorePosture,
          priority: CoachingInsightCategory.scorePosture.priority,
          subjectSeat: seat,
          subjectIsSelf: true,
          subjectValue: ownScore,
          subjectThreshold: observation.eliminationThreshold,
        ),
      );
    } else {
      PlayerSeat? target;
      var targetScore = 0;
      for (final opponent in observation.opponents) {
        final score = observation.scoreFor(opponent);
        if (score >= ExpertCpuMovePlanner.eliminationTargetScoreFloor &&
            score > targetScore) {
          target = opponent;
          targetScore = score;
        }
      }
      if (target != null) {
        out.add(
          CoachingInsight(
            category: CoachingInsightCategory.scorePosture,
            priority: CoachingInsightCategory.scorePosture.priority,
            subjectSeat: target,
            subjectValue: targetScore,
          ),
        );
      }
    }

    // endgameStockLow — the same threshold that flips Expert into its
    // pip-shedding endgame comparator.
    final stock = observation.stockCount;
    if (stock > 0 && stock <= ExpertCpuMovePlanner.thinStockCount) {
      out.add(
        CoachingInsight(
          category: CoachingInsightCategory.endgameStockLow,
          priority: CoachingInsightCategory.endgameStockLow.priority,
          subjectValue: stock,
        ),
      );
    }

    // opponentCloseToFinish — an OPENED opponent down to a few cards. (An
    // unopened opponent always holds a full hand, so the opened check also
    // guards against miscounting mid-deal states.)
    PlayerSeat? closest;
    var closestCount = _opponentCloseHandMax + 1;
    for (final opponent in observation.opponents) {
      if (!observation.hasOpened(opponent)) {
        continue;
      }
      final count = observation.handCountFor(opponent);
      if (count > 0 && count < closestCount) {
        closest = opponent;
        closestCount = count;
      }
    }
    if (closest != null) {
      out.add(
        CoachingInsight(
          category: CoachingInsightCategory.opponentCloseToFinish,
          priority: CoachingInsightCategory.opponentCloseToFinish.priority,
          subjectSeat: closest,
          subjectValue: closestCount,
        ),
      );
    }

    // benchmarkAlert — an unopened seat facing a LIVE raised requirement. Once
    // a second player opens the benchmark LOCKS and can never rise again, so
    // the "can keep raising" teaching is over: the number is just the
    // requirement, which the opening-progress hint already shows. (Playtest:
    // the alert fired after two other seats had already opened — stale and
    // factually wrong.)
    final benchmarkOwner = observation.benchmarkOwner;
    if (!observation.ownHasOpened() &&
        benchmarkOwner != null &&
        benchmarkOwner != seat &&
        !controller.openingState.isLocked &&
        observation.currentOpeningRequirement >
            controller.openingState.baseRequirement) {
      out.add(
        CoachingInsight(
          category: CoachingInsightCategory.benchmarkAlert,
          priority: CoachingInsightCategory.benchmarkAlert.priority,
          subjectSeat: benchmarkOwner,
          openingRequirement: observation.currentOpeningRequirement,
        ),
      );
    }
  }

  // 10. discardSuggestion — the action-phase discard floor, taken straight from
  // the Expert brain so the coaching is hand-by-hand and matches expert play (it
  // weighs card value, run/set potential, held duplicates, and the opponent
  // threat profile, via the shared keep-score model). A floor so the turn is
  // never silent; its low priority keeps it from overriding any real play.
  // Carries the hold-back warning when the obvious throw is materially
  // dangerous and the recommendation dodges it.
  //
  // OPENED seats only: an unopened seat below the benchmark is guided by openNow
  // / openingProgress (which teach "build toward N" and ring the keepers).
  // Emitting a discard floor there is actively harmful — the seat cannot meld
  // yet, so the Expert plan falls to "discard the lowest-pip card" with no
  // protection for a developing-meld anchor. And when a lay-off cover was already
  // surfaced ([_addCover], higher priority) it is the better action, so the
  // floor is suppressed.
  static void _addDiscardSuggestion(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    CpuObservation observation,
    _CoachingAnalysis analysis,
    List<CoachingInsight> out,
  ) {
    if (!controller.openingState.hasOpened(seat)) {
      return;
    }
    if (_containsCategory(out, CoachingInsightCategory.playCover)) {
      return;
    }
    final legalDiscardIds = analysis.legalSafeDiscardIds;
    if (legalDiscardIds.isEmpty) {
      return;
    }
    // The Expert brain's pick when it discards (already threat-aware), else
    // the analysis' safe pick.
    final guidance = analysis.discardGuidance(
      keepIds: const {},
      preferredId: analysis.expertDiscardId,
    );
    final cardId = guidance?.discardCardId ?? legalDiscardIds.first;
    // When the brain is deliberately HOLDING a legal cover (it discards
    // instead), narrate the hold on this hint: a freshly drawn lay-off the
    // coach says nothing about reads as blindness, not strategy (playtest:
    // the cover was only "discovered" a turn later when the posture flipped).
    final held = analysis.heldCover;
    out.add(
      CoachingInsight(
        category: CoachingInsightCategory.discardSuggestion,
        priority: CoachingInsightCategory.discardSuggestion.priority,
        discardCardId: cardId,
        avoidCardId: guidance?.avoidCardId,
        avoidOpponent: guidance?.avoidOpponent,
        avoidReason: guidance?.avoidReason,
        avoidRank: guidance?.avoidRank,
        avoidSuit: guidance?.avoidSuit,
        coverCardId: held?.cover.cardId,
        coverMeldOwner: held?.cover.owner,
        coverMeldIndex: held?.cover.meldIndex,
        holdCoverReason: switch (held?.reason) {
          null => null,
          CoverHoldReason.jokerGuard => CoachCoverHoldReason.jokerGuard,
          CoverHoldReason.fiftyDevelopment =>
            CoachCoverHoldReason.fiftyDevelopment,
          CoverHoldReason.ownRunExtension =>
            CoachCoverHoldReason.ownRunExtension,
        },
        highlightCardIds: [
          cardId,
          if (held != null) ...[held.cover.cardId, ...held.cover.meldCardIds],
        ],
        // The held cover and its target meld ring as one cool keep group so
        // the note points at both ends of the lay-off being declined.
        meldGroups: held == null
            ? const []
            : [
                [held.cover.cardId, ...held.cover.meldCardIds],
              ],
      ),
    );
  }

  // 11. drawStock — the draw-phase instruction. When drawing from the stock is a
  // legal action the seat still owes a draw and nothing more urgent (finish /
  // meld / pickup / cover / joker) applied, so the actionable coaching default
  // is "draw a card". It sits above openingProgress so an unopened seat is told
  // to draw rather than only shown its shortfall — but the opening numbers are
  // folded in here (copied off the openingProgress insight that [_addOpening]
  // appended earlier in [adviseFor]) so the player still sees progress in the
  // draw body. Outranked by any real play insight.
  static void _addDrawStock(
    PlayerSeat seat,
    CpuObservation observation,
    List<CoachingInsight> out,
  ) {
    if (!observation.legalActionIds.contains(
      ClassicHareegActionIds.drawStock,
    )) {
      return;
    }
    // Fold in the opening progress numbers if an unopened seat has them, so the
    // draw hint can show "…, N more to open" without losing the teaching.
    CoachingInsight? opening;
    for (final insight in out) {
      if (insight.category == CoachingInsightCategory.openingProgress) {
        opening = insight;
        break;
      }
    }
    out.add(
      CoachingInsight(
        category: CoachingInsightCategory.drawStock,
        priority: CoachingInsightCategory.drawStock.priority,
        openingBestValue: opening?.openingBestValue,
        openingRequirement: opening?.openingRequirement,
        openingShortfall: opening?.openingShortfall,
        // Carry the opening partition's cards so the draw hint still rings the
        // in-hand cards that make up the player's best meld-in-progress (the
        // stock is highlighted separately by the UI). Without this the draw
        // hint would show the shortfall but point at nothing in the hand.
        highlightCardIds: opening?.highlightCardIds ?? const [],
        meldGroups: opening?.meldGroups ?? const [],
      ),
    );
  }

  // The card ids of every legal safe (plain) discard for [observation].
  static List<String> _legalSafeDiscardIds(CpuObservation observation) {
    return [
      for (final id in observation.legalActionIds)
        if (ClassicHareegActionIds.describe(id).isSafeDiscard)
          ClassicHareegActionIds.describe(id).cardId!,
    ];
  }

  // True when [out] already carries an insight of [category].
  static bool _containsCategory(
    List<CoachingInsight> out,
    CoachingInsightCategory category,
  ) {
    for (final insight in out) {
      if (insight.category == category) {
        return true;
      }
    }
    return false;
  }

  // Whether [card] can still combine with any OTHER hand card into a set or run
  // — i.e. whether holding it builds toward a meld. A card with no such partner
  // is truly isolated (it builds nothing) and is safe to lay off as a cover.
  // Uses the shared [cardsCanMeldTogether] definition so this isolation gate
  // stays consistent-by-construction with the keep-score grouping: a redundant
  // duplicate (rank + suit twin, never meldable beside it) counts as isolated.
  static bool _hasMeldPartner(
    List<HareegCard> hand,
    HareegCard card,
    CardIdentity identity,
  ) {
    for (final other in hand) {
      if (other.id == card.id) {
        continue;
      }
      final otherIdentity = other.effectiveIdentity;
      if (otherIdentity == null) {
        continue;
      }
      if (cardsCanMeldTogether(identity, otherIdentity)) {
        return true;
      }
    }
    return false;
  }

  // Splits a partition into its melds as card-id groups for grouped UI
  // highlighting.
  static List<List<String>> _groupsOf(MeldPartition partition) {
    return [
      for (final meld in partition.melds)
        [for (final card in meld.cards) card.id],
    ];
  }

  static List<PlayerSeat> _opponentsOf(
    ClassicHareegGameController controller,
    PlayerSeat seat,
  ) {
    final active = controller.activeSeats;
    final opponents = <PlayerSeat>[];
    var cursor = seat.nextAntiClockwise;
    while (cursor != seat) {
      if (active.contains(cursor)) {
        opponents.add(cursor);
      }
      cursor = cursor.nextAntiClockwise;
    }
    return opponents;
  }
}

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

  /// Active opponents in turn order.
  late final List<PlayerSeat> opponents =
      ClassicHareegCoachingAdvisor._opponentsOf(controller, seat);

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
  OpponentThreat? threatFor(HareegCard card) => threatProfile
      .primaryThreatFor(card);

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
      for (final card in hand) {
        if (card.id == id) {
          candidates.add(card);
          break;
        }
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
                (score < pickScore ||
                    (score == pickScore && pip < pickPip)))) {
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
