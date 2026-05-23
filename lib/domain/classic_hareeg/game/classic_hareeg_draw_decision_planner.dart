import 'classic_hareeg_action.dart';
import 'classic_hareeg_fifty_claim_planner.dart';
import 'classic_hareeg_round.dart';

/// Draw-phase scenario for a seat's next decision.
enum ClassicHareegDrawDecisionScenario {
  /// The queried seat cannot act in the current round state.
  inactive,

  /// The current turn is waiting for a pending discard to be used or returned.
  pendingDiscard,

  /// The current turn is not in draw phase.
  notDrawPhase,

  /// The seat can only draw from stock.
  stockDrawOnly,

  /// The seat can draw from stock or take the previous discard.
  stockDrawOrDiscardPickup,

  /// The seat can claim Fifty and draw from stock.
  fiftyAndStockDraw,

  /// The seat can claim Fifty, draw from stock, or take the previous discard.
  fiftyStockDrawAndDiscardPickup,

  /// Stock is empty and taking the previous discard can finish the round.
  stockExhaustedPickupFinishOnly,

  /// Stock is empty and only a Fifty claim is currently available.
  fiftyOnly,

  /// Stock is empty, Fifty is claimable, and pickup can finish the round.
  fiftyAndStockExhaustedPickupFinish,

  /// Stock is empty and no legal pickup finish remains, so the round is a draw.
  stockExhaustedRoundDraw,
}

/// Complete draw-phase action plan for one seat.
class ClassicHareegDrawDecisionPlan {
  /// Creates a draw decision plan.
  const ClassicHareegDrawDecisionPlan({
    required this.scenario,
    required this.actionIds,
    required this.fiftyClaimPlan,
    required this.stockIsEmpty,
    required this.canTakePreviousDiscard,
    required this.pickupWouldFinish,
    required this.shouldEndRoundAsDraw,
    required this.canDrawStock,
    required this.canTakeDiscard,
  });

  /// Identified draw decision scenario.
  final ClassicHareegDrawDecisionScenario scenario;

  /// Legal action ids to expose for this draw decision. By convention not
  /// mutated by callers.
  final List<String> actionIds;

  /// Fifty claim decision considered before normal draw/pickup actions.
  final ClassicHareegFiftyClaimPlan fiftyClaimPlan;

  /// Whether stock is currently exhausted.
  final bool stockIsEmpty;

  /// Whether turn order allows this seat to take the previous discard.
  final bool canTakePreviousDiscard;

  /// Whether taking the previous discard can finish when stock is exhausted.
  final bool pickupWouldFinish;

  /// Whether the round should immediately end as a draw.
  final bool shouldEndRoundAsDraw;

  /// Whether the Fifty claim action should be advertised.
  bool get canClaimFifty => fiftyClaimPlan.shouldAdvertise;

  /// Whether the stock draw action should be advertised.
  final bool canDrawStock;

  /// Whether the previous discard pickup action should be advertised.
  final bool canTakeDiscard;
}

/// Resolves draw-phase actions and stock-exhaustion consequences.
abstract final class ClassicHareegDrawDecisionPlanner {
  /// Evaluates one seat's draw decision.
  static ClassicHareegDrawDecisionPlan evaluate({
    required bool isRoundOver,
    required bool isSeatTurn,
    required bool isSeatActive,
    required TurnPhase phase,
    required bool hasPendingDiscard,
    required bool stockIsEmpty,
    required bool canTakePreviousDiscard,
    required bool pickupWouldFinish,
    required ClassicHareegFiftyClaimPlan fiftyClaimPlan,
  }) {
    if (isRoundOver || !isSeatTurn || !isSeatActive) {
      return _blocked(
        scenario: ClassicHareegDrawDecisionScenario.inactive,
        fiftyClaimPlan: fiftyClaimPlan,
        stockIsEmpty: stockIsEmpty,
        canTakePreviousDiscard: canTakePreviousDiscard,
        pickupWouldFinish: pickupWouldFinish,
      );
    }

    if (hasPendingDiscard) {
      return _blocked(
        scenario: ClassicHareegDrawDecisionScenario.pendingDiscard,
        fiftyClaimPlan: fiftyClaimPlan,
        stockIsEmpty: stockIsEmpty,
        canTakePreviousDiscard: canTakePreviousDiscard,
        pickupWouldFinish: pickupWouldFinish,
      );
    }

    if (phase != TurnPhase.draw) {
      return _blocked(
        scenario: ClassicHareegDrawDecisionScenario.notDrawPhase,
        fiftyClaimPlan: fiftyClaimPlan,
        stockIsEmpty: stockIsEmpty,
        canTakePreviousDiscard: canTakePreviousDiscard,
        pickupWouldFinish: pickupWouldFinish,
      );
    }

    final canClaimFifty = fiftyClaimPlan.shouldAdvertise;
    final canDrawStock = !stockIsEmpty;
    final canTakeDiscard =
        canTakePreviousDiscard && (canDrawStock || pickupWouldFinish);
    final shouldEndRoundAsDraw =
        stockIsEmpty &&
        !canClaimFifty &&
        (!canTakePreviousDiscard || !pickupWouldFinish);

    return ClassicHareegDrawDecisionPlan(
      scenario: _scenarioFor(
        canClaimFifty: canClaimFifty,
        canDrawStock: canDrawStock,
        canTakeDiscard: canTakeDiscard,
        shouldEndRoundAsDraw: shouldEndRoundAsDraw,
      ),
      actionIds: [
        if (canClaimFifty) ClassicHareegActionIds.claimFifty,
        if (canDrawStock) ClassicHareegActionIds.drawStock,
        if (canTakeDiscard) ClassicHareegActionIds.takeDiscard,
      ],
      fiftyClaimPlan: fiftyClaimPlan,
      stockIsEmpty: stockIsEmpty,
      canTakePreviousDiscard: canTakePreviousDiscard,
      pickupWouldFinish: pickupWouldFinish,
      shouldEndRoundAsDraw: shouldEndRoundAsDraw,
      canDrawStock: canDrawStock,
      canTakeDiscard: canTakeDiscard,
    );
  }

  static ClassicHareegDrawDecisionPlan _blocked({
    required ClassicHareegDrawDecisionScenario scenario,
    required ClassicHareegFiftyClaimPlan fiftyClaimPlan,
    required bool stockIsEmpty,
    required bool canTakePreviousDiscard,
    required bool pickupWouldFinish,
  }) {
    return ClassicHareegDrawDecisionPlan(
      scenario: scenario,
      actionIds: const [],
      fiftyClaimPlan: fiftyClaimPlan,
      stockIsEmpty: stockIsEmpty,
      canTakePreviousDiscard: canTakePreviousDiscard,
      pickupWouldFinish: pickupWouldFinish,
      shouldEndRoundAsDraw: false,
      canDrawStock: false,
      canTakeDiscard: false,
    );
  }

  static ClassicHareegDrawDecisionScenario _scenarioFor({
    required bool canClaimFifty,
    required bool canDrawStock,
    required bool canTakeDiscard,
    required bool shouldEndRoundAsDraw,
  }) {
    if (shouldEndRoundAsDraw) {
      return ClassicHareegDrawDecisionScenario.stockExhaustedRoundDraw;
    }
    if (!canDrawStock) {
      if (canClaimFifty && canTakeDiscard) {
        return ClassicHareegDrawDecisionScenario
            .fiftyAndStockExhaustedPickupFinish;
      }
      if (canClaimFifty) {
        return ClassicHareegDrawDecisionScenario.fiftyOnly;
      }
      return ClassicHareegDrawDecisionScenario.stockExhaustedPickupFinishOnly;
    }
    if (canClaimFifty && canTakeDiscard) {
      return ClassicHareegDrawDecisionScenario.fiftyStockDrawAndDiscardPickup;
    }
    if (canClaimFifty) {
      return ClassicHareegDrawDecisionScenario.fiftyAndStockDraw;
    }
    if (canTakeDiscard) {
      return ClassicHareegDrawDecisionScenario.stockDrawOrDiscardPickup;
    }
    return ClassicHareegDrawDecisionScenario.stockDrawOnly;
  }
}
