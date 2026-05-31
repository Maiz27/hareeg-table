import '../../../domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import '../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../domain/classic_hareeg/rules/cover_rules.dart';
import '../cpu_observation.dart';
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
  // Priority bands, high → low. Distinct constants keep the relative ordering
  // explicit and let categories that can co-occur sort deterministically.
  static const _priorityFinish = 1000;
  static const _priorityFifty = 900;
  static const _priorityOpenNow = 800;
  static const _priorityPlayMeld = 700;
  static const _priorityPickup = 600;
  static const _priorityCoverKeep = 500;
  static const _priorityJoker = 400;
  static const _priorityDefensive = 300;
  static const _priorityOpeningProgress = 200;

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
    final insights = <CoachingInsight>[];

    _addFinish(controller, seat, observation, insights);
    _addFifty(controller, seat, observation, insights);
    _addOpening(controller, seat, observation, insights);
    _addPlayMeld(controller, seat, insights);
    _addPickup(controller, seat, observation, insights);
    _addCoverKeep(controller, seat, insights);
    _addJokerAdvice(controller, seat, insights);
    _addDefensiveDiscard(controller, seat, insights);

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
      difficulty: controller.setup.cpuDifficulty,
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
    if (!observation.ownHasOpened()) {
      // An unopened seat cannot finish: it must first satisfy the opening
      // benchmark, so a "finish" partition is not actionable as a finish.
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
        priority: _priorityFinish,
        highlightCardIds: highlight,
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
        priority: _priorityFifty,
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
    List<CoachingInsight> out,
  ) {
    if (observation.ownHasOpened()) {
      return;
    }
    final hand = controller.handFor(seat);
    final best = MeldPartitionEnumerator.topPartitions(
      hand,
      comparator: MeldPartitionRankers.byTotalValueDesc,
      take: 1,
      safetyCap: _partitionLimit,
    );
    final requirement = observation.currentOpeningRequirement;
    if (best.isEmpty) {
      // No melds at all: still teach the requirement with a full shortfall.
      out.add(
        CoachingInsight(
          category: CoachingInsightCategory.openingProgress,
          priority: _priorityOpeningProgress,
          openingShortfall: requirement,
          openingBestValue: 0,
          openingRequirement: requirement,
        ),
      );
      return;
    }
    final partition = best.first;
    final bestValue = partition.totalValue;
    final highlight = [for (final card in partition.cardsUsed) card.id];
    if (bestValue >= requirement) {
      out.add(
        CoachingInsight(
          category: CoachingInsightCategory.openNow,
          priority: _priorityOpenNow,
          openingBestValue: bestValue,
          openingRequirement: requirement,
          meldActionId: ClassicHareegActionIds.playMeldActionId(
            partition.melds.first.cards.map((card) => card.id),
          ),
          highlightCardIds: highlight,
        ),
      );
      return;
    }
    out.add(
      CoachingInsight(
        category: CoachingInsightCategory.openingProgress,
        priority: _priorityOpeningProgress,
        openingShortfall: requirement - bestValue,
        openingBestValue: bestValue,
        openingRequirement: requirement,
        highlightCardIds: highlight,
      ),
    );
  }

  // 4. playMeld — an opened seat with a play-meld id on the legal surface.
  static void _addPlayMeld(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    List<CoachingInsight> out,
  ) {
    if (!controller.openingState.hasOpened(seat)) {
      return;
    }
    for (final id in controller.legalActionIdsFor(seat)) {
      final action = ClassicHareegActionIds.describe(id);
      if (action.isMeldPlay) {
        out.add(
          CoachingInsight(
            category: CoachingInsightCategory.playMeld,
            priority: _priorityPlayMeld,
            meldActionId: id,
            highlightCardIds: action.cardIds,
          ),
        );
        return;
      }
    }
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
        priority: _priorityPickup,
        highlightCardIds: [
          topDiscard.id,
          for (final card in partition.cardsUsed)
            if (card.id != topDiscard.id) card.id,
        ],
      ),
    );
  }

  // 6. coverKeep — a hand card that covers/extends one of the SEAT'S OWN table
  // melds. Framed positively: the card is worth keeping. On coaching tier the
  // illegal cover discard is already prevented, so we never frame it as a
  // prohibition.
  static void _addCoverKeep(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    List<CoachingInsight> out,
  ) {
    final ownMelds = controller.tableMeldsFor(seat);
    if (ownMelds.isEmpty) {
      return;
    }
    for (final card in controller.handFor(seat)) {
      for (var index = 0; index < ownMelds.length; index += 1) {
        final extension = ClassicHareegCoverRules.resolveCoverExtension(
          tableMeld: ownMelds[index].cards,
          candidate: card,
        );
        if (extension == null) {
          continue;
        }
        out.add(
          CoachingInsight(
            category: CoachingInsightCategory.coverKeep,
            priority: _priorityCoverKeep,
            coverCardId: card.id,
            coverMeldOwner: seat,
            coverMeldIndex: index,
            highlightCardIds: [card.id],
          ),
        );
        return;
      }
    }
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
        out.add(
          CoachingInsight(
            category: CoachingInsightCategory.jokerAdvice,
            priority: _priorityJoker,
            jokerCardId: action.cardId,
            jokerReplacementActionId: id,
            highlightCardIds: [
              if (action.cardId != null) action.cardId!,
            ],
          ),
        );
        return;
      }
    }
  }

  // 8. defensiveDiscard — a LEGAL discard whose rank/suit an opponent is
  // visibly collecting (discard-history hot-list). Reuses the same hot-list
  // idea the Expert planner's threat profile uses. Framing it as "avoid" is
  // correct here because the discard is legal.
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
      for (final card in [
        ...history.lastPickupsBy(opponent, 99),
        ...history.lastDiscardsBy(opponent, 99),
      ]) {
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
            priority: _priorityDefensive,
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
