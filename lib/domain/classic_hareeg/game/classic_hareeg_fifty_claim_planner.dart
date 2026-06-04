import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../models/table_strictness.dart';
import '../rules/fifty_rules.dart';
import '../rules/finish_rules.dart';
import '../rules/mistake_preset_rules.dart';
import '../rules/opening_rules.dart';
import '../rules/strictness_rule_profile.dart';
import 'classic_hareeg_finish_planner.dart';
import 'classic_hareeg_round.dart';

/// Why a Fifty claim is visible, accepted, blocked, or penalized.
enum ClassicHareegFiftyClaimScenario {
  /// No active Fifty window exists.
  noWindow,

  /// A Fifty window exists, but another seat is the claimant.
  notClaimant,

  /// Fifty can only be claimed in draw phase.
  wrongPhase,

  /// The timer expired before the claim.
  expired,

  /// The top discard no longer matches the active Fifty window.
  missingDiscard,

  /// Penalty tiers may advertise the claim before proving the finish.
  claimWindowOpen,

  /// The discarded card completes a valid Fifty finish.
  validClaim,

  /// The claim is not a finish and the active strictness blocks it.
  blockedWrongClaim,

  /// The claim is not a finish and the active strictness penalizes it.
  penalizedWrongClaim,
}

/// Whether the caller is asking about action ids or applying the claim.
enum ClassicHareegFiftyClaimPurpose {
  /// Resolve whether the claim action should be advertised.
  advertise,

  /// Resolve the outcome of applying a claim action.
  apply,
}

/// Planned perfect-hand finish using the previous discard.
class ClassicHareegFinishPlan {
  /// Creates a finish plan.
  const ClassicHareegFinishPlan({
    required this.melds,
    required this.finalDiscard,
  });

  /// Melds that use every card except [finalDiscard].
  final List<PlacedMeld> melds;

  /// Final discard that completes the finish.
  final HareegCard finalDiscard;
}

/// Complete Fifty claim decision for one seat.
class ClassicHareegFiftyClaimPlan {
  /// Creates a Fifty claim plan.
  const ClassicHareegFiftyClaimPlan({
    required this.scenario,
    required this.shouldAdvertise,
    required this.canApply,
    required this.message,
    this.finishPlan,
    this.claimResult,
    this.mistakeResolution,
  });

  /// Identified claim scenario.
  final ClassicHareegFiftyClaimScenario scenario;

  /// Whether `claim-fifty` should appear in legal action ids.
  final bool shouldAdvertise;

  /// Whether applying the action should mutate state.
  final bool canApply;

  /// Player-facing explanation for the decision.
  final String message;

  /// Valid finish plan when [scenario] is [ClassicHareegFiftyClaimScenario.validClaim].
  final ClassicHareegFinishPlan? finishPlan;

  /// Pure Fifty validation result, when a finish plan was available.
  final FiftyClaimResult? claimResult;

  /// Mistake behavior when a wrong claim is allowed by the active strictness.
  final MistakeResolution? mistakeResolution;

  /// Whether this claim proceeds as a mistake penalty instead of a finish.
  bool get appliesMistake => mistakeResolution?.isAllowed ?? false;
}

/// Resolves Fifty visibility and claim application as one rich scenario.
abstract final class ClassicHareegFiftyClaimPlanner {
  /// Evaluates a Fifty claim for [claimant].
  static ClassicHareegFiftyClaimPlan evaluate({
    required ClassicHareegFiftyClaimPurpose purpose,
    required TableStrictness strictness,
    required FiftyClaimWindow? window,
    required PlayerSeat claimant,
    required TurnPhase phase,
    required int elapsedSeconds,
    required HareegCard? topDiscard,
    required ClassicHareegFinishPlan? Function() finishPlanResolver,
  }) {
    if (window == null) {
      return const ClassicHareegFiftyClaimPlan(
        scenario: ClassicHareegFiftyClaimScenario.noWindow,
        shouldAdvertise: false,
        canApply: false,
        message: 'Only the immediate next player can claim Fifty.',
      );
    }

    if (window.claimant != claimant) {
      return const ClassicHareegFiftyClaimPlan(
        scenario: ClassicHareegFiftyClaimScenario.notClaimant,
        shouldAdvertise: false,
        canApply: false,
        message: 'Only the immediate next player can claim Fifty.',
      );
    }

    if (phase != TurnPhase.draw) {
      return const ClassicHareegFiftyClaimPlan(
        scenario: ClassicHareegFiftyClaimScenario.wrongPhase,
        shouldAdvertise: false,
        canApply: false,
        message: 'Fifty can only be claimed before drawing.',
      );
    }

    if (window.isExpired(elapsedSeconds)) {
      return const ClassicHareegFiftyClaimPlan(
        scenario: ClassicHareegFiftyClaimScenario.expired,
        shouldAdvertise: false,
        canApply: false,
        message: 'Fifty timer expired.',
      );
    }

    if (topDiscard == null || topDiscard.id != window.discardedCard.id) {
      return const ClassicHareegFiftyClaimPlan(
        scenario: ClassicHareegFiftyClaimScenario.missingDiscard,
        shouldAdvertise: false,
        canApply: false,
        message: 'No active Fifty discard.',
      );
    }

    final needsFinishProof =
        purpose == ClassicHareegFiftyClaimPurpose.apply ||
        strictness.fiftyClaimNeedsFinishProofForAdvertise;
    if (!needsFinishProof) {
      return const ClassicHareegFiftyClaimPlan(
        scenario: ClassicHareegFiftyClaimScenario.claimWindowOpen,
        shouldAdvertise: true,
        canApply: false,
        message: 'Fifty claim is available.',
      );
    }

    final finishPlan = finishPlanResolver();
    if (finishPlan == null) {
      return _wrongClaimPlan(strictness: strictness);
    }

    final claim = ClassicHareegFiftyRules.validateClaim(
      window: window,
      claimant: claimant,
      elapsedSeconds: elapsedSeconds,
      finishingMelds: finishPlan.melds,
      finalDiscard: finishPlan.finalDiscard,
    );
    if (!claim.isValid) {
      return _wrongClaimPlan(strictness: strictness, message: claim.message);
    }

    return ClassicHareegFiftyClaimPlan(
      scenario: ClassicHareegFiftyClaimScenario.validClaim,
      shouldAdvertise: true,
      canApply: true,
      message: 'Fifty claimed.',
      finishPlan: finishPlan,
      claimResult: claim,
    );
  }

  /// Finds a perfect-hand finish that must use [discarded].
  static ClassicHareegFinishPlan? finishPlanForClaim({
    required List<HareegCard> hand,
    required HareegCard discarded,
    required bool playerOpened,
    ClassicHareegFinishPlanner? planner,
  }) {
    final cards = [...hand, discarded];
    final finishPlanner = planner ?? ClassicHareegFinishPlanner(cards);
    if (!finishPlanner.hasValidMeldContaining(discarded.id)) {
      return null;
    }

    for (final finalDiscard in cards) {
      if (finalDiscard.id == discarded.id) {
        continue;
      }
      final melds = finishPlanner.partitionWithout(finalDiscard);
      if (melds == null) {
        continue;
      }

      final finish = ClassicHareegFinishRules.validateFinish(
        playedMelds: melds,
        finalDiscard: finalDiscard,
        playerOpened: playerOpened,
        source: FinishCardSource.previousDiscard,
        perfectHandAttempt: true,
      );
      if (finish.isValid) {
        return ClassicHareegFinishPlan(
          melds: melds,
          finalDiscard: finalDiscard,
        );
      }
    }
    return null;
  }

  static ClassicHareegFiftyClaimPlan _wrongClaimPlan({
    required TableStrictness strictness,
    String message = 'That discard does not complete a valid Fifty.',
  }) {
    final resolution = ClassicHareegMistakePresetRules.resolve(
      strictness: strictness,
      mistake: MistakeType.wrongFiftyClaim,
    );
    if (!resolution.isAllowed) {
      return ClassicHareegFiftyClaimPlan(
        scenario: ClassicHareegFiftyClaimScenario.blockedWrongClaim,
        shouldAdvertise: false,
        canApply: false,
        message: message,
      );
    }

    return ClassicHareegFiftyClaimPlan(
      scenario: ClassicHareegFiftyClaimScenario.penalizedWrongClaim,
      shouldAdvertise: true,
      canApply: true,
      message: resolution.message,
      mistakeResolution: resolution,
    );
  }
}
