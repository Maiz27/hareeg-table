import '../../domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'cpu_move_plan.dart';
import 'cpu_move_plan_pipeline.dart';
import 'cpu_observation.dart';

class _ClassicHareegCpuPriority {
  const _ClassicHareegCpuPriority(this.kind, this.scenario);

  final ClassicHareegActionKind kind;
  final ClassicHareegCpuMoveScenario scenario;
}

/// Current priority-order CPU move planner.
///
/// This planner preserves the original Beginner/Casual behavior: it only reads
/// legal action ids and ignores the richer table state on [CpuObservation].
class PriorityCpuMovePlanner implements CpuMovePlanner {
  /// Creates a priority-order CPU move planner.
  const PriorityCpuMovePlanner();

  static const _priority = [
    _ClassicHareegCpuPriority(
      ClassicHareegActionKind.claimFifty,
      ClassicHareegCpuMoveScenario.fiftyClaim,
    ),
    _ClassicHareegCpuPriority(
      ClassicHareegActionKind.playMeld,
      ClassicHareegCpuMoveScenario.meldPlay,
    ),
    _ClassicHareegCpuPriority(
      ClassicHareegActionKind.playMeldWithJoker,
      ClassicHareegCpuMoveScenario.meldPlay,
    ),
    _ClassicHareegCpuPriority(
      ClassicHareegActionKind.replaceJoker,
      ClassicHareegCpuMoveScenario.jokerReplacement,
    ),
    _ClassicHareegCpuPriority(
      ClassicHareegActionKind.placeCover,
      ClassicHareegCpuMoveScenario.cover,
    ),
    _ClassicHareegCpuPriority(
      ClassicHareegActionKind.drawStock,
      ClassicHareegCpuMoveScenario.drawStock,
    ),
    _ClassicHareegCpuPriority(
      ClassicHareegActionKind.takeDiscard,
      ClassicHareegCpuMoveScenario.takeDiscard,
    ),
  ];

  @override
  ClassicHareegCpuMovePlan plan(CpuObservation observation) {
    // Mid-proof on a claimed Fifty the engine serves the next step of the
    // validated finish plan as the single legal action — take it verbatim
    // instead of re-deriving the move by kind priority.
    if (observation.ownIsFiftyProofTurn &&
        observation.legalActionIds.isNotEmpty) {
      return ClassicHareegCpuMovePlan(
        scenario: ClassicHareegCpuMoveScenario.fiftyProof,
        actionId: observation.legalActionIds.first,
      );
    }

    // The rules engine advertises claim-fifty even for hopeless claims so
    // human players can attempt a wrong-claim (penalty) flow. CPU has no
    // upside in attempting one — it loops the priority pick until the
    // Fifty timer expires — so strip it from the legal set when there's
    // no finishing partition to back it.
    final canClaim = shouldAttemptFiftyClaimFor(observation);
    if (canClaim) {
      return evaluate(observation.legalActionIds);
    }
    return evaluate(
      observation.legalActionIds.where(
        (id) =>
            ClassicHareegActionIds.describe(id).kind !=
            ClassicHareegActionKind.claimFifty,
      ),
    );
  }

  /// Evaluates the priority plan for [legalActionIds].
  static ClassicHareegCpuMovePlan evaluate(Iterable<String> legalActionIds) {
    final actions = [
      for (final id in legalActionIds)
        _ClassicHareegCpuLegalAction(
          actionId: id,
          descriptor: ClassicHareegActionIds.describe(id),
        ),
    ];
    if (actions.isEmpty) {
      return const ClassicHareegCpuMovePlan(
        scenario: ClassicHareegCpuMoveScenario.noLegalActions,
        actionId: null,
      );
    }

    for (final priority in _priority) {
      for (final action in actions) {
        if (action.descriptor.kind == priority.kind) {
          return ClassicHareegCpuMovePlan(
            scenario: priority.scenario,
            actionId: action.actionId,
          );
        }
      }
    }

    for (final action in actions) {
      if (action.descriptor.isSafeDiscard) {
        return ClassicHareegCpuMovePlan(
          scenario: ClassicHareegCpuMoveScenario.safeDiscard,
          actionId: action.actionId,
        );
      }
    }

    for (final action in actions) {
      if (action.descriptor.kind ==
          ClassicHareegActionKind.returnPendingDiscard) {
        return ClassicHareegCpuMovePlan(
          scenario: ClassicHareegCpuMoveScenario.returnPendingDiscard,
          actionId: action.actionId,
        );
      }
    }

    return ClassicHareegCpuMovePlan(
      scenario: ClassicHareegCpuMoveScenario.fallback,
      actionId: actions.first.actionId,
    );
  }
}

class _ClassicHareegCpuLegalAction {
  const _ClassicHareegCpuLegalAction({
    required this.actionId,
    required this.descriptor,
  });

  final String actionId;
  final ClassicHareegActionDescriptor descriptor;
}
