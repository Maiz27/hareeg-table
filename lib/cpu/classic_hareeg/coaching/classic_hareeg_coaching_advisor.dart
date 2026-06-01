import '../../../domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import '../../../domain/classic_hareeg/game/classic_hareeg_round.dart' show TurnPhase;
import '../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../domain/classic_hareeg/rules/cover_rules.dart';
import '../../../domain/classic_hareeg/models/classic_hareeg_setup.dart'
    show CpuDifficulty;
import '../cpu_move_plan.dart' show ClassicHareegCpuMoveScenario;
import '../cpu_move_plan_pipeline.dart'
    show cardPipValue, cardsCanMeldTogether, handKeepScores;
import '../cpu_observation.dart';
import '../expert_cpu_move_planner.dart';
import 'coaching_insight.dart';

/// Pure, structured coaching advisor for Classic Hareeg.
///
/// [adviseFor] is a pure function of the passed-in controller state and seat:
/// no mutation, no I/O, no time. It reuses the same analysis brain the Expert
/// CPU uses ([CpuObservation] / [MeldPartitionEnumerator] / cover rules) to
/// classify the human player's situation into prioritized [CoachingInsight]s.
///
/// The advisor emits localization-free structured data only; mapping each
/// insight to EN/AR text is the UI stage's job.
abstract final class ClassicHareegCoachingAdvisor {
  // Insight priorities live on [CoachingInsightCategory] (a single descending
  // ladder); each builder passes its category's `.priority` so the ordering is
  // never restated here.

  // Cap matching the Expert planner's partition fan-out.
  static const _partitionLimit = 256;

  /// Returns priority-sorted coaching insights for [seat] given [controller].
  ///
  /// Highest-priority insight is first; callers may show only `result.first`.
  static List<CoachingInsight> adviseFor(
    ClassicHareegGameController controller,
    PlayerSeat seat,
  ) {
    final observation = _observationFor(controller, seat);
    // One shared read model for the whole call: the best meld partition, the
    // keep-scores, and the Expert plan are each derived at most once (lazily)
    // and reused by every builder, instead of each builder re-enumerating the
    // same partition lattice.
    final analysis = _CoachingAnalysis(observation, controller.handFor(seat));
    final insights = <CoachingInsight>[];

    _addFinish(controller, seat, observation, insights);
    _addFifty(controller, seat, observation, insights);
    _addOpening(controller, seat, observation, analysis, insights);
    _addPlayMeld(controller, seat, analysis, insights);
    _addPickup(controller, seat, observation, insights);
    // Cover advice is driven by the Expert plan (see _addCover). Order matters:
    // it runs before _addDiscardSuggestion, which suppresses its floor when the
    // plan surfaced a cover instead.
    _addCover(controller, seat, analysis, insights);
    _addJokerAdvice(controller, seat, insights);
    _addDefensiveDiscard(controller, seat, insights);
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

  // 1. finishAvailable — the seat can empty its hand this turn. A finishing
  // partition leaves <= 1 card remaining (the last card is the final discard).
  static void _addFinish(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    CpuObservation observation,
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
    if (!observation.ownHasOpened()) {
      // An unopened seat cannot finish: it must first satisfy the opening
      // benchmark, so a "finish" partition is not actionable as a finish.
      return;
    }
    // The trivial finish: a single card left, where discarding (or covering)
    // it empties the hand and wins. The meld-partition enumerator yields no
    // partition for a meldless hand, so detect this directly and ring the last
    // card. Checked before [finishingPartition] so the case is handled
    // regardless of how the enumerator treats a one-card hand.
    final hand = controller.handFor(seat);
    if (hand.length == 1) {
      out.add(
        CoachingInsight(
          category: CoachingInsightCategory.finishAvailable,
          priority: CoachingInsightCategory.finishAvailable.priority,
          highlightCardIds: [hand.first.id],
        ),
      );
      return;
    }
    final finishing = observation.finishingPartition();
    if (finishing == null) {
      return;
    }
    final highlight = [
      for (final card in finishing.cardsUsed) card.id,
    ];
    out.add(
      CoachingInsight(
        category: CoachingInsightCategory.finishAvailable,
        priority: CoachingInsightCategory.finishAvailable.priority,
        highlightCardIds: highlight,
        meldGroups: _groupsOf(finishing),
      ),
    );
  }

  // 2. fiftyAvailable — the seat owns the Fifty window AND a real finishing
  // partition uses the top discard. This mirrors canSuccessfullyClaimFiftyFor
  // but additionally requires the finish to consume the claimed discard so the
  // claim is genuine rather than a wrong-claim mistake.
  static void _addFifty(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    CpuObservation observation,
    List<CoachingInsight> out,
  ) {
    if (observation.fiftyClaimant != seat) {
      return;
    }
    final topDiscard = controller.topDiscard;
    if (topDiscard == null) {
      return;
    }
    // Require a finishing partition that consumes the claimed discard. We read
    // the claim directly from `fiftyClaimant` + the partition primitive rather
    // than the legal `claim-fifty` advertisement: that advertisement is gated
    // on window timing/grace that a coaching hint should not depend on, and the
    // spec defines availability as "seat is fiftyClaimant AND a real finishing
    // partition uses the top discard".
    final hand = controller.handFor(seat);
    final withDiscard = [...hand, topDiscard];
    final finishesOnDiscard = MeldPartitionEnumerator.partitionsOf(
      withDiscard,
      mustUseCardId: topDiscard.id,
      safetyCap: _partitionLimit,
    ).any((partition) => partition.cardsRemaining.length <= 1);
    if (!finishesOnDiscard) {
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

  // 3. openNow vs openingProgress — an unopened seat. Best openable value comes
  // from the highest-value partition. If it clears the requirement we surface
  // openNow with the play action; otherwise openingProgress with the shortfall.
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
      out.add(
        CoachingInsight(
          category: CoachingInsightCategory.openingProgress,
          priority: CoachingInsightCategory.openingProgress.priority,
          openingShortfall: shortfall > 0 ? shortfall : 0,
          openingBestValue: stagedValue,
          openingRequirement: requirement,
          discardCardId: _buildingDiscardId(controller, seat, analysis, const {}),
        ),
      );
      return;
    }
    final effectiveValue = stagedValue + partition.totalValue;
    final highlight = [for (final card in partition.cardsUsed) card.id];
    if (effectiveValue >= requirement) {
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
    out.add(
      CoachingInsight(
        category: CoachingInsightCategory.openingProgress,
        priority: CoachingInsightCategory.openingProgress.priority,
        openingShortfall: requirement - effectiveValue,
        openingBestValue: effectiveValue,
        openingRequirement: requirement,
        highlightCardIds: highlight,
        meldGroups: _groupsOf(partition),
        // Choose the discard from cards OUTSIDE the highlighted keep partition,
        // so the hint never rings a card teal ("keep") and pink ("discard") at
        // once — e.g. it must not tell you to shed the 4♣ that anchors the very
        // 4-5-6-7 run it is telling you to keep.
        discardCardId: _buildingDiscardId(
          controller,
          seat,
          analysis,
          highlight.toSet(),
        ),
      ),
    );
  }

  // The lowest-potential LEGAL safe discard among cards NOT in [keepIds] (the
  // best opening partition the hint highlights). Potential-weighted via
  // [discardKeepScore]; ties shed the higher pip first. Restricting to legal
  // safe discards drops cover cards that cannot be discarded. Returns null in
  // the draw phase (no legal discard) or when every legal card is a keeper.
  static String? _buildingDiscardId(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    _CoachingAnalysis analysis,
    Set<String> keepIds,
  ) {
    final hand = analysis.hand;
    // Keep scores from the shared disjoint best-grouping model over the WHOLE
    // hand: each card is scored by the value of the single meld / group it lands
    // in, so a card already committed to a meld scores that meld's value and
    // cannot inflate a loose deadwood neighbour (the A♥ locked in the aces set is
    // not borrowed as a heart-run partner for a loose 2♥/3♥). No free-hand
    // trimming is needed for scoring. [keepIds] is excluded from the discard
    // CANDIDATES only — a UI contract so the hint never rings one card as both a
    // "keep" (teal) and the recommended "discard" (rose).
    final keepScores = analysis.keepScores;
    HareegCard? pick;
    var pickScore = 1 << 30;
    var pickPip = 1 << 30;
    for (final id in controller.legalActionIdsFor(seat)) {
      final action = ClassicHareegActionIds.describe(id);
      if (!action.isSafeDiscard || action.cardId == null) {
        continue;
      }
      final cardId = action.cardId!;
      if (keepIds.contains(cardId)) {
        continue;
      }
      HareegCard? card;
      for (final candidate in hand) {
        if (candidate.id == cardId) {
          card = candidate;
          break;
        }
      }
      if (card == null) {
        continue;
      }
      final score = keepScores[card.id] ?? 0;
      final pip = cardPipValue(card);
      // Lowest keep-score wins; on a tie shed the LOWER pip so the higher-
      // ceiling card is kept (mirrors the Expert comparator's value term).
      if (pick == null ||
          score < pickScore ||
          (score == pickScore && pip < pickPip)) {
        pick = card;
        pickScore = score;
        pickPip = pip;
      }
    }
    return pick?.id;
  }

  // 4. playMeld — an opened seat that can lay a complete meld from hand.
  //
  // A full meld is always better coaching than breaking a single card off for a
  // cover, so this must surface (priority 700) ahead of the cover hints (550 /
  // 500) whenever a settable meld exists. We first trust an advertised play-meld
  // id, then fall back to enumerating the hand directly: the legal surface's
  // candidate generator can miss a valid meld, and a pending discard narrows the
  // surface to only melds using that card — in both cases the player still has a
  // complete meld worth laying, and the coach should point at it.
  static void _addPlayMeld(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    _CoachingAnalysis analysis,
    List<CoachingInsight> out,
  ) {
    if (!controller.openingState.hasOpened(seat)) {
      return;
    }
    for (final id in controller.legalActionIdsFor(seat)) {
      final action = ClassicHareegActionIds.describe(id);
      if (action.isMeldPlay) {
        _emitPlayMeld(controller, seat, action.cardIds, id, out);
        return;
      }
    }

    // Fallback: a pending discard must be resolved (used in a meld or returned)
    // before any other meld can be played, so do not suggest an unrelated meld
    // while one is pending — that play would be rejected by the rules engine.
    if (controller.pendingDiscard != null) {
      return;
    }
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
    List<String> meldCardIds,
    String? meldActionId,
    List<CoachingInsight> out,
  ) {
    final cover = _isolatedCoverFor(controller, seat, meldCardIds.toSet());
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
  })? _isolatedCoverFor(
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
            meldCardIds: [for (final meldCard in melds[index].cards) meldCard.id],
          );
        }
      }
    }
    return null;
  }

  // 5. pickupCompletesMeld — taking the top discard would complete/improve a
  // meld: a legal partition uses the discard and leaves fewer cards in hand.
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
    final openingFloor = observation.ownHasOpened()
        ? null
        : observation.currentOpeningRequirement;
    final completing = MeldPartitionEnumerator.topPartitions(
      withDiscard,
      comparator: MeldPartitionRankers.byCoverSurfaceDesc,
      take: 1,
      mustUseCardId: topDiscard.id,
      minTotalValue: openingFloor,
      safetyCap: _partitionLimit,
    );
    if (completing.isEmpty) {
      return;
    }
    final partition = completing.first;
    if (partition.cardsRemaining.length >= hand.length) {
      // The discard did not actually pull any hand card into a meld.
      return;
    }
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

  // 6. Cover advice, driven ENTIRELY by the Expert plan's chosen move. When the
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
    final covers = _legalCovers(controller, seat);
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
    final hasSafeDiscard = controller
        .legalActionIdsFor(seat)
        .any((id) => ClassicHareegActionIds.describe(id).isSafeDiscard);
    if (!hasSafeDiscard) {
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
  static List<
    ({
      String actionId,
      String cardId,
      PlayerSeat owner,
      int meldIndex,
      List<String> meldCardIds,
    })
  >
  _legalCovers(ClassicHareegGameController controller, PlayerSeat seat) {
    final covers =
        <
          ({
            String actionId,
            String cardId,
            PlayerSeat owner,
            int meldIndex,
            List<String> meldCardIds,
          })
        >[];
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
        meldCardIds: [for (final card in melds[target.meldIndex].cards) card.id],
      ));
    }
    return covers;
  }

  // 7. jokerAdvice — the seat can replace a represented joker on the table with
  // a real card it holds (a concrete, actionable upgrade). A replace-joker id
  // on the legal surface is the cleanest signal.
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
        out.add(
          CoachingInsight(
            category: CoachingInsightCategory.jokerAdvice,
            priority: CoachingInsightCategory.jokerAdvice.priority,
            jokerCardId: action.cardId,
            jokerReplacementActionId: id,
            highlightCardIds: [
              if (action.cardId != null) action.cardId!,
              ...meldCardIds,
            ],
          ),
        );
        return;
      }
    }
  }

  // 8. defensiveDiscard — a LEGAL discard whose rank/suit an opponent is
  // visibly collecting. The signal is opponent PICKUPS from the discard pile
  // only: deliberately taking a card is the genuine "collecting" tell. A card
  // an opponent DISCARDED is one they did not want, so counting discards (as a
  // raw threat profile does) inverts the meaning and produces misleading,
  // too-eager warnings on turn one. Coaching copy must be defensible to a
  // human learner, so we diverge from the Expert profile here and require a
  // real pickup. Framing it as "avoid" is correct because the discard is legal.
  static void _addDefensiveDiscard(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    List<CoachingInsight> out,
  ) {
    final history = controller.discardHistory;
    final opponents = _opponentsOf(controller, seat);
    if (opponents.isEmpty) {
      return;
    }

    // Build a per-opponent hot rank/suit list from discards + pickups, the same
    // signal the Expert threat profile collects.
    final hotByOpponent = <PlayerSeat, _HotSet>{};
    for (final opponent in opponents) {
      final hot = _HotSet();
      for (final card in history.lastPickupsBy(opponent, 99)) {
        final identity = card.effectiveIdentity;
        if (identity == null) {
          continue;
        }
        hot.ranks.add(identity.rank);
        hot.suits.add(identity.suit);
      }
      if (hot.ranks.isNotEmpty || hot.suits.isNotEmpty) {
        hotByOpponent[opponent] = hot;
      }
    }
    if (hotByOpponent.isEmpty) {
      return;
    }

    // Only advise on cards that are actually legal plain discards right now.
    final legalDiscardIds = <String>{
      for (final id in controller.legalActionIdsFor(seat))
        if (ClassicHareegActionIds.describe(id).isSafeDiscard)
          ClassicHareegActionIds.describe(id).cardId!,
    };
    if (legalDiscardIds.isEmpty) {
      return;
    }

    for (final card in controller.handFor(seat)) {
      if (!legalDiscardIds.contains(card.id)) {
        continue;
      }
      final identity = card.effectiveIdentity;
      if (identity == null) {
        continue;
      }
      for (final entry in hotByOpponent.entries) {
        final hot = entry.value;
        final rankHot = hot.ranks.contains(identity.rank);
        final suitHot = hot.suits.contains(identity.suit);
        if (!rankHot && !suitHot) {
          continue;
        }
        out.add(
          CoachingInsight(
            category: CoachingInsightCategory.defensiveDiscard,
            priority: CoachingInsightCategory.defensiveDiscard.priority,
            discardCardId: card.id,
            hotOpponent: entry.key,
            hotRank: rankHot ? identity.rank : null,
            hotSuit: suitHot ? identity.suit : null,
            highlightCardIds: [card.id],
          ),
        );
        return;
      }
    }
  }

  // 9. drawStock — the draw-phase instruction. When drawing from the stock is a
  // legal action the seat still owes a draw and nothing more urgent (finish /
  // meld / pickup / cover / joker / defensive) applied, so the actionable
  // coaching default is "draw a card". It sits above openingProgress so an
  // unopened seat is told to draw rather than only shown its shortfall — but the
  // opening numbers are folded in here (copied off the openingProgress insight
  // that [_addOpening] appended earlier in [adviseFor]) so the player still sees
  // progress in the draw body. Outranked by any real play insight.
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

  // discardSuggestion — the action-phase discard floor, taken straight from the
  // Expert brain so the coaching is hand-by-hand and matches expert play (it
  // weighs card value, run/set potential, held duplicates, and the opponent
  // threat profile, via the shared keep-score model). A floor so the turn is
  // never silent; its low priority keeps it from overriding any real play.
  //
  // OPENED seats only: an unopened seat below the benchmark is guided by openNow
  // / openingProgress (which teach "build toward N" and ring the keepers).
  // Emitting a discard floor there is actively harmful — the seat cannot meld
  // yet, so the Expert plan falls to "discard the lowest-pip card" with no
  // protection for a developing-meld anchor. And when a lay-off cover was already
  // surfaced ([_addPlayCover], higher priority) it is the better action, so the
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
    final legalDiscardIds = _legalSafeDiscardIds(observation);
    if (legalDiscardIds.isEmpty) {
      return;
    }
    // The Expert brain's pick when it discards, else a legal discard floor.
    final cardId = analysis.expertDiscardId ?? legalDiscardIds.first;
    out.add(
      CoachingInsight(
        category: CoachingInsightCategory.discardSuggestion,
        priority: CoachingInsightCategory.discardSuggestion.priority,
        discardCardId: cardId,
        highlightCardIds: [cardId],
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

class _HotSet {
  final Set<CardRank> ranks = {};
  final Set<CardSuit> suits = {};
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
  _CoachingAnalysis(this._observation, this.hand);

  final CpuObservation _observation;

  /// The seat's current hand.
  final List<HareegCard> hand;

  /// The single highest-value meld partition over [hand] — the cards worth
  /// keeping, used for opening / play-meld highlighting. Null when the hand
  /// melds nothing.
  late final MeldPartition? bestPartition = _computeBestPartition();

  /// Per-card keep scores from the shared disjoint best-grouping model.
  late final Map<String, int> keepScores = handKeepScores(hand);

  /// The Expert brain's full plan for this observation, computed once.
  late final _expertPlan = const ExpertCpuMovePlanner().plan(_observation);

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

  /// The cover action id the Expert brain chose, or null when it is not
  /// covering — lets the coach present the brain's exact cover.
  String? get expertCoverActionId =>
      expertCovers ? _expertPlan.actionId : null;

  MeldPartition? _computeBestPartition() {
    final best = MeldPartitionEnumerator.topPartitions(
      hand,
      comparator: MeldPartitionRankers.byTotalValueDesc,
      take: 1,
      safetyCap: ClassicHareegCoachingAdvisor._partitionLimit,
    );
    return best.isEmpty ? null : best.first;
  }
}
