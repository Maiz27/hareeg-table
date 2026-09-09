import '../../../domain/classic_hareeg/analysis/partial_hand_groups.dart';
import '../../../domain/classic_hareeg/analysis/table_reading_analysis.dart';
import '../../../domain/classic_hareeg/game/classic_hareeg_action.dart'
    show ClassicHareegActionKind;
import '../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../domain/classic_hareeg/replay/review_observation.dart';
import '../../../domain/classic_hareeg/rules/cover_rules.dart';
import '../cpu_move_plan_pipeline.dart' show partialSoloValue;
import 'analysis_coach_settings.dart';
import 'review_insight.dart';

/// Reviews one applied action using only what the table showed.
///
/// The signature is the boundary. [review] can be handed an observation, an
/// action and the player's settings — and nothing else. There is no parameter
/// for a controller, a snapshot, a transcript or a timeline, so the coach has
/// no route to a hidden hand, the stock, or anything that happened later. Two
/// positions with the same observable history therefore cannot produce
/// different advice, because the coach cannot tell them apart.
///
/// The live [ClassicHareegCoachingAdvisor] is the opposite: it reads the whole
/// controller, because coaching a live player is allowed to use the player's
/// own full state. Review is watched by someone who wants to learn what was
/// knowable at the time.
abstract final class ReplayAnalysisCoach {
  /// Returns the insights to show for one applied action.
  static List<ReviewInsight> review({
    required ReviewObservation observation,
    required ReviewedAction action,
    required AnalysisCoachSettings settings,
  }) {
    return applySettings(
      generate(observation: observation, action: action),
      settings,
    );
  }

  /// Every insight the evidence supports, before the player's settings are
  /// applied.
  ///
  /// Public so that "settings filter, they do not change the analysis" is
  /// directly testable: the same position must generate the same list whatever
  /// the player has chosen to be shown.
  static List<ReviewInsight> generate({
    required ReviewObservation observation,
    required ReviewedAction action,
  }) {
    final insights = <ReviewInsight>[];
    final kind = action.descriptor.kind;

    _addFiftyWindow(observation, kind, insights);

    if (action.actingSeat == observation.perspective) {
      if (_isDiscard(kind)) {
        final discarded = _discardedCard(observation, action);
        if (discarded != null) {
          _addFeedJudgement(observation, discarded, insights);
          _addDeadDevelopment(observation, discarded, insights);
          _addMissedCover(observation, discarded, insights);
        }
      } else if (_isPickup(kind)) {
        final taken = _takenCard(observation, kind);
        if (taken != null) {
          _addDeadPickup(observation, taken, insights);
        }
      }
    } else {
      if (_isPickup(kind)) {
        final taken = _takenCard(observation, kind);
        if (taken != null) {
          _addCollectingTell(observation, action.actingSeat, taken, insights);
        }
      } else if (_isMeldPlay(kind)) {
        _addOpponentOpened(observation, action.actingSeat, insights);
      }
    }

    insights.sort((left, right) {
      final bySeverity = right.severity.index.compareTo(left.severity.index);
      if (bySeverity != 0) {
        return bySeverity;
      }
      return left.category.index.compareTo(right.category.index);
    });
    return List.unmodifiable(insights);
  }

  /// Applies the player's verbosity and dead-card preferences.
  ///
  /// Filtering happens after generation, never instead of it, so a setting can
  /// only change what is shown — not what the coach concluded.
  static List<ReviewInsight> applySettings(
    List<ReviewInsight> insights,
    AnalysisCoachSettings settings,
  ) {
    return List.unmodifiable([
      for (final insight in insights)
        if (_passesFilter(insight, settings)) insight,
    ]);
  }

  static bool _passesFilter(
    ReviewInsight insight,
    AnalysisCoachSettings settings,
  ) {
    if (insight.category.isCardDeathWarning && !settings.cardDeathWarnings) {
      return false;
    }
    return switch (settings.verbosity) {
      AnalysisVerbosity.narrateAll => true,
      AnalysisVerbosity.keyMoments =>
        insight.severity != ReviewSeverity.narration,
      AnalysisVerbosity.clearMistakes =>
        insight.severity == ReviewSeverity.mistake,
    };
  }

  // --- categories --------------------------------------------------------

  static void _addFiftyWindow(
    ReviewObservation observation,
    ClassicHareegActionKind kind,
    List<ReviewInsight> out,
  ) {
    final window = observation.fiftyWindow;
    if (window == null || kind == ClassicHareegActionKind.claimFifty) {
      return;
    }
    out.add(
      ReviewInsight(
        category: ReviewInsightCategory.fiftyWindowOpen,
        subjectSeat: window.discarder,
        cardIds: [if (window.cardId != null) window.cardId!],
        evidence: [
          ReviewEvidence(
            kind: ReviewEvidenceKind.fiftyWindow,
            seat: window.discarder,
            cardIds: [if (window.cardId != null) window.cardId!],
            value: window.secondsRemaining,
          ),
        ],
      ),
    );
  }

  /// Feed risk and its absence are one judgement about one discard, so exactly
  /// one of the two always fires — unless there is no seat to feed at all, in
  /// which case there is nothing to say either way.
  static void _addFeedJudgement(
    ReviewObservation observation,
    HareegCard discarded,
    List<ReviewInsight> out,
  ) {
    final target = FeedRiskAnalysis.nextActiveSeat(
      from: observation.perspective,
      activeSeats: observation.activeSeats,
    );
    if (target == null) {
      return;
    }

    // Review has no tier and therefore no memory limit: every pickup in the
    // observable history was seen by everyone at the table.
    final pickups = observation.pickupsBy(target);
    final targetMelds = observation.visibleMelds[target] ?? const [];
    final assessment = FeedRiskAnalysis.assess(
      candidate: discarded,
      perspective: observation.perspective,
      activeSeats: observation.activeSeats,
      recentPickups: pickups,
      targetMelds: targetMelds,
      targetHasOpened: observation.hasOpened(target),
    );

    if (!assessment.isRisky) {
      out.add(
        ReviewInsight(
          category: ReviewInsightCategory.safeDiscard,
          subjectSeat: target,
          cardIds: [discarded.id],
          evidence: [
            // The claim is that nothing public suggests this card serves the
            // next seat, so the evidence has to be that absence itself —
            // which pickups were checked, and how many visible melds. Their
            // hand size is observable but would not support the claim.
            ReviewEvidence(
              kind: ReviewEvidenceKind.noPublicTell,
              seat: target,
              cardIds: [for (final card in pickups) card.id],
              value: targetMelds.length,
            ),
          ],
        ),
      );
      return;
    }

    final evidence = <ReviewEvidence>[];
    if (assessment.evidence.contains(FeedEvidenceKind.recentPickup)) {
      evidence.add(
        ReviewEvidence(
          kind: ReviewEvidenceKind.discardPilePickup,
          seat: target,
          cardIds: [for (final card in pickups) card.id],
        ),
      );
    }
    if (assessment.evidence.contains(FeedEvidenceKind.coverExtension) ||
        assessment.evidence.contains(FeedEvidenceKind.jokerReplacement)) {
      evidence.add(
        ReviewEvidence(
          kind: ReviewEvidenceKind.visibleMeld,
          seat: target,
          cardIds: [
            for (final meld in targetMelds)
              for (final card in meld.cards) card.id,
          ],
        ),
      );
    }

    out.add(
      ReviewInsight(
        category: ReviewInsightCategory.feedRiskDiscard,
        subjectSeat: target,
        cardIds: [discarded.id],
        evidence: evidence,
      ),
    );
  }

  static void _addDeadDevelopment(
    ReviewObservation observation,
    HareegCard discarded,
    List<ReviewInsight> out,
  ) {
    final analysis = _analysisOf(observation);
    PartialHandGroup? worst;
    for (final group in analysis.partialGroups) {
      if (!analysis.isGroupStarved(group)) {
        continue;
      }
      // A group the player just broke up is not one they "kept".
      if (group.cards.any((card) => card.id == discarded.id)) {
        continue;
      }
      if (worst == null || group.value > worst.value) {
        worst = group;
      }
    }
    if (worst == null) {
      return;
    }

    final dead = TableReadingAnalysis.completionsFor(worst);
    out.add(
      ReviewInsight(
        category: ReviewInsightCategory.deadDevelopmentKept,
        subjectSeat: observation.perspective,
        cardIds: [for (final card in worst.cards) card.id],
        evidence: [
          ReviewEvidence(
            kind: ReviewEvidenceKind.ownHand,
            seat: observation.perspective,
            cardIds: [for (final card in worst.cards) card.id],
          ),
          for (final identity in dead)
            ReviewEvidence(
              kind: ReviewEvidenceKind.deadIdentity,
              rankLabel: identity.rank.name,
              suitLabel: identity.suit.name,
              value: observation.deckCopyCount,
            ),
        ],
      ),
    );
  }

  static void _addDeadPickup(
    ReviewObservation observation,
    HareegCard taken,
    List<ReviewInsight> out,
  ) {
    // The position as it stands the instant after the pickup, derived from
    // observable state alone: the card moves from the pile into the hand, so
    // its accounted copies must not be counted in both places.
    final analysis = _analysisOf(
      observation,
      handOverride: [...observation.perspectiveHand, taken],
      pileOverride: _withoutFirstMatch(observation.discardPile, taken),
    );

    for (final group in analysis.partialGroups) {
      if (!group.cards.any((card) => card.id == taken.id)) {
        continue;
      }
      if (!analysis.isGroupStarved(group)) {
        continue;
      }
      final dead = TableReadingAnalysis.completionsFor(group);
      out.add(
        ReviewInsight(
          category: ReviewInsightCategory.deadPickup,
          subjectSeat: observation.perspective,
          cardIds: [for (final card in group.cards) card.id],
          evidence: [
            ReviewEvidence(
              kind: ReviewEvidenceKind.ownHand,
              seat: observation.perspective,
              cardIds: [taken.id],
            ),
            for (final identity in dead)
              ReviewEvidence(
                kind: ReviewEvidenceKind.deadIdentity,
                rankLabel: identity.rank.name,
                suitLabel: identity.suit.name,
                value: observation.deckCopyCount,
              ),
          ],
        ),
      );
      return;
    }
  }

  /// A lay-off is only "missed" if the rules would actually have accepted it,
  /// so this asks the real cover rule rather than guessing from rank adjacency.
  static void _addMissedCover(
    ReviewObservation observation,
    HareegCard discarded,
    List<ReviewInsight> out,
  ) {
    if (!observation.hasOpened(observation.perspective)) {
      return;
    }
    final meldCards = [
      for (final entry in observation.visibleMelds.entries)
        for (final meld in entry.value) meld.cards,
    ];
    if (meldCards.isEmpty) {
      return;
    }

    for (final card in observation.perspectiveHand) {
      if (card.id == discarded.id) {
        continue;
      }
      if (!ClassicHareegCoverRules.isAnyCover(
        tableMelds: meldCards,
        candidate: card,
      )) {
        continue;
      }
      out.add(
        ReviewInsight(
          category: ReviewInsightCategory.missedCover,
          subjectSeat: observation.perspective,
          cardIds: [card.id],
          evidence: [
            ReviewEvidence(
              kind: ReviewEvidenceKind.ownHand,
              seat: observation.perspective,
              cardIds: [card.id],
            ),
            ReviewEvidence(
              kind: ReviewEvidenceKind.visibleMeld,
              cardIds: [
                for (final meld in meldCards)
                  for (final meldCard in meld) meldCard.id,
              ],
            ),
            ReviewEvidence(
              kind: ReviewEvidenceKind.openingState,
              seat: observation.perspective,
              value: observation.openingRequirement,
            ),
          ],
        ),
      );
      return;
    }
  }

  static void _addCollectingTell(
    ReviewObservation observation,
    PlayerSeat actor,
    HareegCard taken,
    List<ReviewInsight> out,
  ) {
    final priorPickups = [
      for (final card in observation.pickupsBy(actor))
        if (card.id != taken.id) card,
    ];
    final melds = observation.visibleMelds[actor] ?? const [];

    // A joker has no standard identity, so it cannot establish that a seat is
    // collecting a particular rank or run.
    final takenIdentity = taken.identity;
    final related = <HareegCard>[
      if (takenIdentity != null)
        for (final card in priorPickups)
          if (card.identity case final identity?)
            if (cardsCanMeldTogether(identity, takenIdentity)) card,
    ];
    final extendsMeld =
        melds.isNotEmpty &&
        ClassicHareegCoverRules.isAnyCover(
          tableMelds: [for (final meld in melds) meld.cards],
          candidate: taken,
        );

    if (related.isEmpty && !extendsMeld) {
      return;
    }

    out.add(
      ReviewInsight(
        category: ReviewInsightCategory.opponentCollectingTell,
        subjectSeat: actor,
        cardIds: [taken.id],
        evidence: [
          if (related.isNotEmpty)
            ReviewEvidence(
              kind: ReviewEvidenceKind.discardPilePickup,
              seat: actor,
              cardIds: [taken.id, for (final card in related) card.id],
            ),
          if (extendsMeld)
            ReviewEvidence(
              kind: ReviewEvidenceKind.visibleMeld,
              seat: actor,
              cardIds: [
                for (final meld in melds)
                  for (final card in meld.cards) card.id,
              ],
            ),
        ],
      ),
    );
  }

  /// A seat that had not opened and just played a meld has, by the rules,
  /// opened with it. That makes the transition readable from the state before
  /// the action plus the action itself — which matters, because a post-action
  /// observation would depend on hidden state for other action kinds and would
  /// break the invariance the whole review rests on.
  static void _addOpponentOpened(
    ReviewObservation observation,
    PlayerSeat actor,
    List<ReviewInsight> out,
  ) {
    if (observation.hasOpened(actor)) {
      return;
    }
    out.add(
      ReviewInsight(
        category: ReviewInsightCategory.opponentOpened,
        subjectSeat: actor,
        evidence: [
          ReviewEvidence(
            kind: ReviewEvidenceKind.openingState,
            seat: actor,
            value: observation.openingRequirement,
          ),
        ],
      ),
    );
  }

  // --- helpers -----------------------------------------------------------

  static TableReadingAnalysis _analysisOf(
    ReviewObservation observation, {
    List<HareegCard>? handOverride,
    List<HareegCard>? pileOverride,
  }) {
    return TableReadingAnalysis(
      perspectiveHand: handOverride ?? observation.perspectiveHand,
      discardPile: pileOverride ?? observation.discardPile,
      visibleMelds: observation.visibleMelds,
      deckCopyCount: observation.deckCopyCount,
      soloValue: partialSoloValue,
    );
  }

  static List<HareegCard> _withoutFirstMatch(
    List<HareegCard> cards,
    HareegCard target,
  ) {
    final remaining = [...cards];
    final index = remaining.indexWhere((card) => card.id == target.id);
    if (index >= 0) {
      remaining.removeAt(index);
    }
    return remaining;
  }

  static bool _isDiscard(ClassicHareegActionKind kind) => switch (kind) {
    ClassicHareegActionKind.discard ||
    ClassicHareegActionKind.discardBlockedCover ||
    ClassicHareegActionKind.discardJoker => true,
    _ => false,
  };

  static bool _isPickup(ClassicHareegActionKind kind) => switch (kind) {
    ClassicHareegActionKind.takeDiscard ||
    ClassicHareegActionKind.usePendingDiscard => true,
    _ => false,
  };

  static bool _isMeldPlay(ClassicHareegActionKind kind) => switch (kind) {
    ClassicHareegActionKind.playMeld ||
    ClassicHareegActionKind.playMeldWithJoker => true,
    _ => false,
  };

  static HareegCard? _discardedCard(
    ReviewObservation observation,
    ReviewedAction action,
  ) {
    final id = action.descriptor.cardId;
    if (id == null) {
      return null;
    }
    for (final card in observation.perspectiveHand) {
      if (card.id == id) {
        return card;
      }
    }
    return null;
  }

  static HareegCard? _takenCard(
    ReviewObservation observation,
    ClassicHareegActionKind kind,
  ) {
    if (kind == ClassicHareegActionKind.usePendingDiscard) {
      return observation.pendingDiscard;
    }
    return observation.discardPile.isEmpty
        ? null
        : observation.discardPile.last;
  }
}
