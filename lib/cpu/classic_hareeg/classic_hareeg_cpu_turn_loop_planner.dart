/// CPU turn loop scenario selected by the runner gate planner.
enum ClassicHareegCpuTurnLoopScenario {
  /// CPU flow can continue to the next decision point.
  continueTurn,

  /// The runner stopped because the active seat is the human seat.
  humanTurn,

  /// The runner stopped because the round ended.
  roundOver,

  /// The current CPU seat had no legal actions to apply.
  noLegalActions,

  /// A caller hook asked the runner to stop.
  hookStopped,

  /// The action limit was reached before control returned to the human seat.
  safetyLimit,
}

/// Planned outcome for one CPU turn loop gate.
class ClassicHareegCpuTurnLoopPlan {
  /// Creates a CPU turn loop plan.
  const ClassicHareegCpuTurnLoopPlan({required this.scenario});

  /// Scenario chosen for the gate.
  final ClassicHareegCpuTurnLoopScenario scenario;

  /// Whether the runner should keep advancing CPU flow.
  bool get canContinue =>
      scenario == ClassicHareegCpuTurnLoopScenario.continueTurn;

  /// Whether the runner should stop at this gate.
  bool get shouldStop => !canContinue;
}

/// Plans the stop/continue gates for a Classic Hareeg CPU turn loop.
abstract final class ClassicHareegCpuTurnLoopPlanner {
  /// Evaluates the gate before preparing another CPU decision.
  static ClassicHareegCpuTurnLoopPlan turnGate({
    required bool isRoundOver,
    required bool isHumanTurn,
    required int appliedActionCount,
    required int actionLimit,
  }) {
    assert(appliedActionCount >= 0);
    assert(actionLimit > 0);

    if (isRoundOver) {
      return const ClassicHareegCpuTurnLoopPlan(
        scenario: ClassicHareegCpuTurnLoopScenario.roundOver,
      );
    }
    if (isHumanTurn) {
      return const ClassicHareegCpuTurnLoopPlan(
        scenario: ClassicHareegCpuTurnLoopScenario.humanTurn,
      );
    }
    if (appliedActionCount >= actionLimit) {
      return const ClassicHareegCpuTurnLoopPlan(
        scenario: ClassicHareegCpuTurnLoopScenario.safetyLimit,
      );
    }
    return const ClassicHareegCpuTurnLoopPlan(
      scenario: ClassicHareegCpuTurnLoopScenario.continueTurn,
    );
  }

  /// Evaluates a hook-controlled gate.
  static ClassicHareegCpuTurnLoopPlan hookGate({required bool shouldContinue}) {
    if (shouldContinue) {
      return const ClassicHareegCpuTurnLoopPlan(
        scenario: ClassicHareegCpuTurnLoopScenario.continueTurn,
      );
    }
    return const ClassicHareegCpuTurnLoopPlan(
      scenario: ClassicHareegCpuTurnLoopScenario.hookStopped,
    );
  }

  /// Evaluates the gate after reading CPU legal actions.
  static ClassicHareegCpuTurnLoopPlan legalActionGate({
    required bool hasLegalActions,
  }) {
    if (hasLegalActions) {
      return const ClassicHareegCpuTurnLoopPlan(
        scenario: ClassicHareegCpuTurnLoopScenario.continueTurn,
      );
    }
    return const ClassicHareegCpuTurnLoopPlan(
      scenario: ClassicHareegCpuTurnLoopScenario.noLegalActions,
    );
  }

  /// Evaluates the special gate after an action was applied.
  static ClassicHareegCpuTurnLoopPlan afterApplyHookGate({
    required bool shouldContinue,
    required bool isRoundOver,
  }) {
    if (shouldContinue) {
      return const ClassicHareegCpuTurnLoopPlan(
        scenario: ClassicHareegCpuTurnLoopScenario.continueTurn,
      );
    }
    if (isRoundOver) {
      return const ClassicHareegCpuTurnLoopPlan(
        scenario: ClassicHareegCpuTurnLoopScenario.roundOver,
      );
    }
    return const ClassicHareegCpuTurnLoopPlan(
      scenario: ClassicHareegCpuTurnLoopScenario.hookStopped,
    );
  }
}
