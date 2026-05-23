/// Scheduled table-side action after a frame or CPU turn.
enum ClassicHareegTableTurnFlowAction {
  /// Play the opening deal choreography before any other side effect.
  playOpeningDeal,

  /// Let the CPU runner advance non-human turns.
  runCpuTurns,

  /// Persist the current table state.
  persistTable,

  /// Stop because the caller cannot safely continue.
  stop,
}

/// Turn-flow scheduling scenario selected by the planner.
enum ClassicHareegTableTurnFlowScenario {
  /// The opening deal choreography must finish first.
  openingDeal,

  /// A CPU seat owns the current turn.
  cpuTurn,

  /// The human owns the current turn, so the table should persist.
  humanTurnPersistence,

  /// The round is over, so the table should persist result state.
  roundOverPersistence,

  /// CPU flow is blocked by another table side effect.
  blockedCpuPersistence,

  /// A CPU run already persisted or navigated.
  cpuAlreadyHandled,

  /// A CPU run did not persist, so the scheduler should persist.
  cpuNeedsPersistence,

  /// The widget is no longer mounted.
  unmounted,
}

/// Planned table turn-flow action.
class ClassicHareegTableTurnFlowPlan {
  /// Creates a table turn-flow plan.
  const ClassicHareegTableTurnFlowPlan({
    required this.action,
    required this.scenario,
  });

  /// Action the widget adapter should perform.
  final ClassicHareegTableTurnFlowAction action;

  /// Scenario that explains the selected action.
  final ClassicHareegTableTurnFlowScenario scenario;

  /// Whether no further side effect should run.
  bool get shouldStop => action == ClassicHareegTableTurnFlowAction.stop;
}

/// Plans frame-scheduled table side effects for Classic Hareeg.
abstract final class ClassicHareegTableTurnFlowPlanner {
  /// Evaluates the first scheduled action for a post-frame turn-flow pass.
  static ClassicHareegTableTurnFlowPlan afterFrame({
    required bool isMounted,
    required bool hasOpeningDealToPlay,
    required bool isCpuRunning,
    required bool isOpeningDealRunning,
    required bool isRoundOver,
    required bool isHumanTurn,
  }) {
    if (!isMounted) {
      return const ClassicHareegTableTurnFlowPlan(
        action: ClassicHareegTableTurnFlowAction.stop,
        scenario: ClassicHareegTableTurnFlowScenario.unmounted,
      );
    }
    if (hasOpeningDealToPlay) {
      return const ClassicHareegTableTurnFlowPlan(
        action: ClassicHareegTableTurnFlowAction.playOpeningDeal,
        scenario: ClassicHareegTableTurnFlowScenario.openingDeal,
      );
    }
    return afterOpeningDeal(
      isMounted: isMounted,
      isCpuRunning: isCpuRunning,
      isOpeningDealRunning: isOpeningDealRunning,
      isRoundOver: isRoundOver,
      isHumanTurn: isHumanTurn,
    );
  }

  /// Evaluates the next action after opening-deal work has finished or skipped.
  static ClassicHareegTableTurnFlowPlan afterOpeningDeal({
    required bool isMounted,
    required bool isCpuRunning,
    required bool isOpeningDealRunning,
    required bool isRoundOver,
    required bool isHumanTurn,
  }) {
    if (!isMounted) {
      return const ClassicHareegTableTurnFlowPlan(
        action: ClassicHareegTableTurnFlowAction.stop,
        scenario: ClassicHareegTableTurnFlowScenario.unmounted,
      );
    }
    if (!isCpuRunning &&
        !isOpeningDealRunning &&
        !isRoundOver &&
        !isHumanTurn) {
      return const ClassicHareegTableTurnFlowPlan(
        action: ClassicHareegTableTurnFlowAction.runCpuTurns,
        scenario: ClassicHareegTableTurnFlowScenario.cpuTurn,
      );
    }
    if (isRoundOver) {
      return const ClassicHareegTableTurnFlowPlan(
        action: ClassicHareegTableTurnFlowAction.persistTable,
        scenario: ClassicHareegTableTurnFlowScenario.roundOverPersistence,
      );
    }
    if (isHumanTurn) {
      return const ClassicHareegTableTurnFlowPlan(
        action: ClassicHareegTableTurnFlowAction.persistTable,
        scenario: ClassicHareegTableTurnFlowScenario.humanTurnPersistence,
      );
    }
    return const ClassicHareegTableTurnFlowPlan(
      action: ClassicHareegTableTurnFlowAction.persistTable,
      scenario: ClassicHareegTableTurnFlowScenario.blockedCpuPersistence,
    );
  }

  /// Evaluates the next action after a CPU turn runner pass.
  static ClassicHareegTableTurnFlowPlan afterCpuTurns({
    required bool isMounted,
    required bool didCpuPersistOrNavigate,
  }) {
    if (!isMounted) {
      return const ClassicHareegTableTurnFlowPlan(
        action: ClassicHareegTableTurnFlowAction.stop,
        scenario: ClassicHareegTableTurnFlowScenario.unmounted,
      );
    }
    if (didCpuPersistOrNavigate) {
      return const ClassicHareegTableTurnFlowPlan(
        action: ClassicHareegTableTurnFlowAction.stop,
        scenario: ClassicHareegTableTurnFlowScenario.cpuAlreadyHandled,
      );
    }
    return const ClassicHareegTableTurnFlowPlan(
      action: ClassicHareegTableTurnFlowAction.persistTable,
      scenario: ClassicHareegTableTurnFlowScenario.cpuNeedsPersistence,
    );
  }
}
