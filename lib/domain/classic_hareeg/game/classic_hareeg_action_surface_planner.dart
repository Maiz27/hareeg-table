import '../models/player_seat.dart';
import 'classic_hareeg_action.dart';
import 'classic_hareeg_draw_decision_planner.dart';
import 'classic_hareeg_round.dart';

/// Caller-facing action surface to expose.
enum ClassicHareegActionSurfacePurpose {
  /// Complete legal action ids for rules tests and rich UI affordances.
  full,

  /// Cheap action ids needed by frame-build UI controls.
  control,

  /// Bounded, priority-ordered action ids for CPU strategy.
  cpu,
}

/// High-level turn scenario behind an action surface.
enum ClassicHareegActionSurfaceScenario {
  /// The queried seat cannot act.
  inactive,

  /// The turn is waiting for a picked-up discard to be used or returned.
  pendingDiscard,

  /// The active seat is in action phase.
  actionTurn,

  /// The active seat is in draw phase.
  drawDecision,
}

/// How [ClassicHareegGameController.applyAction] should validate an action id.
enum ClassicHareegActionApplyRoute {
  /// The action carries target data and is validated by its apply method.
  directValidation,

  /// The action must appear on the current cheap control surface first.
  controlSurface,

  /// The action id is not recognized.
  unknown,
}

/// Action-id producers behind one rules-engine query.
///
/// Implementations live alongside the controller so the planner can ask for
/// only the surfaces it needs without binding closures per frame. A logging
/// or test variant can wrap a live facts implementation.
abstract class ClassicHareegActionSurfaceFacts {
  /// Full play-meld action ids, optionally constrained to one physical card.
  List<String> playMeldActionIds(PlayerSeat seat, {String? mustUseCardId});

  /// First CPU-priority play-meld action id.
  String? firstPlayMeldActionId(PlayerSeat seat, {String? mustUseCardId});

  /// Represented-joker replacement action ids.
  List<String> replaceJokerActionIds(PlayerSeat seat, {String? mustUseCardId});

  /// Cover action ids.
  List<String> coverActionIds(PlayerSeat seat, {String? mustUseCardId});

  /// Discard action ids.
  List<String> discardActionIds(PlayerSeat seat);

  /// Whether table plays made this turn can be returned.
  bool canReturnOpeningMelds(PlayerSeat seat);

  /// Whether the unused pending discard may be returned right now.
  ///
  /// False for unopened seats with staged opening melds (the staged plays
  /// must be taken back first) and during a Fifty proof turn (the claimed
  /// card cannot be returned).
  bool canReturnPendingDiscard(PlayerSeat seat);

  /// Draw decision plan for draw phase.
  ClassicHareegDrawDecisionPlan drawDecisionPlan(PlayerSeat seat);
}

/// Planned action ids for one caller-facing surface.
class ClassicHareegActionSurfacePlan {
  /// Creates an action surface plan.
  const ClassicHareegActionSurfacePlan({
    required this.purpose,
    required this.scenario,
    required this.actionIds,
    required this.reason,
    this.drawDecisionPlan,
  });

  /// Surface being exposed.
  final ClassicHareegActionSurfacePurpose purpose;

  /// Identified turn scenario.
  final ClassicHareegActionSurfaceScenario scenario;

  /// Action ids to expose to the caller. By convention not mutated by callers.
  final List<String> actionIds;

  /// Short diagnostic reason for logs.
  final String reason;

  /// Draw-phase decision when [scenario] is
  /// [ClassicHareegActionSurfaceScenario.drawDecision].
  final ClassicHareegDrawDecisionPlan? drawDecisionPlan;

  /// Whether [actionId] appears on this surface.
  bool allows(String actionId) => actionIds.contains(actionId);
}

/// Plans action surfaces behind one rules-engine interface.
abstract final class ClassicHareegActionSurfacePlanner {
  /// Evaluates one surface for the queried seat.
  static ClassicHareegActionSurfacePlan evaluate({
    required ClassicHareegActionSurfacePurpose purpose,
    required PlayerSeat seat,
    required bool isRoundOver,
    required bool isSeatTurn,
    required bool isSeatActive,
    required TurnPhase phase,
    required String? pendingDiscardId,
    required ClassicHareegActionSurfaceFacts facts,
  }) {
    if (isRoundOver || !isSeatTurn || !isSeatActive) {
      return ClassicHareegActionSurfacePlan(
        purpose: purpose,
        scenario: ClassicHareegActionSurfaceScenario.inactive,
        actionIds: const [],
        reason: 'inactive',
      );
    }

    final pending = pendingDiscardId;
    if (pending != null) {
      return _pendingDiscardPlan(
        purpose: purpose,
        seat: seat,
        pendingDiscardId: pending,
        facts: facts,
      );
    }

    if (phase == TurnPhase.action) {
      return _actionTurnPlan(purpose: purpose, seat: seat, facts: facts);
    }

    final drawPlan = facts.drawDecisionPlan(seat);
    return ClassicHareegActionSurfacePlan(
      purpose: purpose,
      scenario: ClassicHareegActionSurfaceScenario.drawDecision,
      actionIds: drawPlan.actionIds,
      reason: 'draw:${drawPlan.scenario.name}',
      drawDecisionPlan: drawPlan,
    );
  }

  /// Returns the apply validation route for [kind].
  static ClassicHareegActionApplyRoute applyRouteFor(
    ClassicHareegActionKind kind,
  ) {
    return switch (kind) {
      ClassicHareegActionKind.playMeld ||
      ClassicHareegActionKind.playMeldWithJoker ||
      ClassicHareegActionKind.placeCover ||
      ClassicHareegActionKind.replaceJoker ||
      ClassicHareegActionKind.returnTablePlay =>
        ClassicHareegActionApplyRoute.directValidation,
      ClassicHareegActionKind.drawStock ||
      ClassicHareegActionKind.takeDiscard ||
      ClassicHareegActionKind.usePendingDiscard ||
      ClassicHareegActionKind.returnPendingDiscard ||
      ClassicHareegActionKind.returnOpeningMelds ||
      ClassicHareegActionKind.claimFifty ||
      ClassicHareegActionKind.discard ||
      ClassicHareegActionKind.discardBlockedCover ||
      ClassicHareegActionKind.discardJoker =>
        ClassicHareegActionApplyRoute.controlSurface,
      ClassicHareegActionKind.unknown => ClassicHareegActionApplyRoute.unknown,
    };
  }

  static ClassicHareegActionSurfacePlan _pendingDiscardPlan({
    required ClassicHareegActionSurfacePurpose purpose,
    required PlayerSeat seat,
    required String pendingDiscardId,
    required ClassicHareegActionSurfaceFacts facts,
  }) {
    // Relaxed taken-discard rule: while the pending card sits unused, every
    // table play stays legal (using the pending card or not) — only ending
    // the turn is off the surface. Returning the pending card stays available
    // while no rule forbids it (see [canReturnPendingDiscard]).
    final canReturnPending = facts.canReturnPendingDiscard(seat);

    if (purpose == ClassicHareegActionSurfacePurpose.control) {
      return ClassicHareegActionSurfacePlan(
        purpose: ClassicHareegActionSurfacePurpose.control,
        scenario: ClassicHareegActionSurfaceScenario.pendingDiscard,
        actionIds: [
          if (facts.canReturnOpeningMelds(seat))
            ClassicHareegActionIds.returnOpeningMelds,
          if (canReturnPending) ClassicHareegActionIds.returnPendingDiscard,
          // Empty while a normal taken card sits unused; during a Fifty proof
          // turn on the mistake-allowing tiers these are the priced exits.
          ...facts.discardActionIds(seat),
        ],
        reason: 'pending-control',
      );
    }

    if (purpose == ClassicHareegActionSurfacePurpose.cpu) {
      // CPU posture: use the pending card as soon as a play accepts it; the
      // relaxed ordering keeps that play legal whenever it exists, so the
      // use-first priority remains optimal for the CPU.
      final playMeld = facts.firstPlayMeldActionId(
        seat,
        mustUseCardId: pendingDiscardId,
      );
      if (playMeld != null) {
        return ClassicHareegActionSurfacePlan(
          purpose: purpose,
          scenario: ClassicHareegActionSurfaceScenario.pendingDiscard,
          actionIds: [playMeld],
          reason: 'pending-meld',
        );
      }

      final replace = facts.replaceJokerActionIds(
        seat,
        mustUseCardId: pendingDiscardId,
      );
      if (replace.isNotEmpty) {
        return ClassicHareegActionSurfacePlan(
          purpose: purpose,
          scenario: ClassicHareegActionSurfaceScenario.pendingDiscard,
          actionIds: [replace.first],
          reason: 'pending-replace',
        );
      }

      final cover = facts.coverActionIds(seat, mustUseCardId: pendingDiscardId);
      if (cover.isNotEmpty) {
        return ClassicHareegActionSurfacePlan(
          purpose: purpose,
          scenario: ClassicHareegActionSurfaceScenario.pendingDiscard,
          actionIds: [cover.first],
          reason: 'pending-cover',
        );
      }

      if (canReturnPending) {
        return ClassicHareegActionSurfacePlan(
          purpose: purpose,
          scenario: ClassicHareegActionSurfaceScenario.pendingDiscard,
          actionIds: const [ClassicHareegActionIds.returnPendingDiscard],
          reason: 'pending-return',
        );
      }

      return ClassicHareegActionSurfacePlan(
        purpose: purpose,
        scenario: ClassicHareegActionSurfaceScenario.pendingDiscard,
        actionIds: [
          if (facts.canReturnOpeningMelds(seat))
            ClassicHareegActionIds.returnOpeningMelds,
        ],
        reason: 'pending-stuck',
      );
    }

    return ClassicHareegActionSurfacePlan(
      purpose: purpose,
      scenario: ClassicHareegActionSurfaceScenario.pendingDiscard,
      actionIds: [
        if (facts.canReturnOpeningMelds(seat))
          ClassicHareegActionIds.returnOpeningMelds,
        ...facts.playMeldActionIds(seat),
        ...facts.replaceJokerActionIds(seat),
        ...facts.coverActionIds(seat),
        if (canReturnPending) ClassicHareegActionIds.returnPendingDiscard,
        // Empty while a normal taken card sits unused; during a Fifty proof
        // turn on the mistake-allowing tiers these are the priced exits.
        ...facts.discardActionIds(seat),
      ],
      reason: 'pending-full',
    );
  }

  static ClassicHareegActionSurfacePlan _actionTurnPlan({
    required ClassicHareegActionSurfacePurpose purpose,
    required PlayerSeat seat,
    required ClassicHareegActionSurfaceFacts facts,
  }) {
    if (purpose == ClassicHareegActionSurfacePurpose.control) {
      return ClassicHareegActionSurfacePlan(
        purpose: purpose,
        scenario: ClassicHareegActionSurfaceScenario.actionTurn,
        actionIds: [
          if (facts.canReturnOpeningMelds(seat))
            ClassicHareegActionIds.returnOpeningMelds,
          ...facts.discardActionIds(seat),
        ],
        reason: 'action-control',
      );
    }

    if (purpose == ClassicHareegActionSurfacePurpose.cpu) {
      final ids = <String>[];
      final playMeld = facts.firstPlayMeldActionId(seat);
      if (playMeld != null) {
        ids.add(playMeld);
      }
      final replace = facts.replaceJokerActionIds(seat);
      if (replace.isNotEmpty) {
        ids.add(replace.first);
      }
      final cover = facts.coverActionIds(seat);
      if (cover.isNotEmpty) {
        ids.add(cover.first);
      }
      ids.addAll(facts.discardActionIds(seat));
      return ClassicHareegActionSurfacePlan(
        purpose: purpose,
        scenario: ClassicHareegActionSurfaceScenario.actionTurn,
        actionIds: ids,
        reason: 'action',
      );
    }

    return ClassicHareegActionSurfacePlan(
      purpose: purpose,
      scenario: ClassicHareegActionSurfaceScenario.actionTurn,
      actionIds: [
        if (facts.canReturnOpeningMelds(seat))
          ClassicHareegActionIds.returnOpeningMelds,
        ...facts.playMeldActionIds(seat),
        ...facts.replaceJokerActionIds(seat),
        ...facts.coverActionIds(seat),
        ...facts.discardActionIds(seat),
      ],
      reason: 'action-full',
    );
  }
}
