import '../../domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import '../../domain/classic_hareeg/game/classic_hareeg_round.dart';
import '../../domain/classic_hareeg/models/player_seat.dart';
import '../../domain/classic_hareeg/models/playing_card.dart';
import 'classic_hareeg_cpu_turn_loop_planner.dart';
import 'cpu_strategy.dart';

/// Why a CPU turn run stopped.
enum ClassicHareegCpuTurnStopReason {
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

/// Immutable snapshot of the CPU loop before one CPU decision.
class ClassicHareegCpuTurnStep {
  /// Creates a CPU turn step.
  const ClassicHareegCpuTurnStep({
    required this.index,
    required this.seat,
    required this.phase,
    required this.stockCount,
    required this.discardCount,
    this.pendingDiscard,
  });

  /// One-based index within the current CPU run.
  final int index;

  /// CPU seat making the decision.
  final PlayerSeat seat;

  /// Current turn phase before choosing the action.
  final TurnPhase phase;

  /// Pending discard that must be used or returned, if any.
  final HareegCard? pendingDiscard;

  /// Stock size before choosing the action.
  final int stockCount;

  /// Discard-pile size before choosing the action.
  final int discardCount;
}

/// CPU action chosen for one runner step.
class ClassicHareegCpuTurnDecision {
  /// Creates a CPU turn decision.
  ClassicHareegCpuTurnDecision({
    required this.step,
    required Iterable<String> legalActionIds,
    required this.actionId,
  }) : legalActionIds = List.unmodifiable(legalActionIds);

  /// Step that produced this decision.
  final ClassicHareegCpuTurnStep step;

  /// Legal action ids offered to the CPU strategy.
  final List<String> legalActionIds;

  /// Action id selected by the CPU strategy.
  final String actionId;

  /// CPU seat making the decision.
  PlayerSeat get seat => step.seat;
}

/// Optional side-effect hooks around CPU flow.
///
/// The runner owns the game-flow loop and legality validation. Flutter callers
/// use hooks for animation delays, card flights, persistence, and logging.
class ClassicHareegCpuTurnHooks {
  /// Creates CPU turn hooks.
  const ClassicHareegCpuTurnHooks({
    this.beforeDecision,
    this.onLegalActions,
    this.onActionChosen,
    this.beforeApply,
    this.afterApply,
    this.beforeNextAction,
  });

  /// Runs before legal actions are read for a step.
  final Future<bool> Function(ClassicHareegCpuTurnStep step)? beforeDecision;

  /// Runs after legal actions are read.
  final void Function(
    ClassicHareegCpuTurnStep step,
    List<String> legalActionIds,
  )?
  onLegalActions;

  /// Runs after the CPU strategy has selected an action.
  final void Function(ClassicHareegCpuTurnDecision decision)? onActionChosen;

  /// Runs after an action has been chosen but before it is applied.
  final Future<bool> Function(ClassicHareegCpuTurnDecision decision)?
  beforeApply;

  /// Runs after an action is applied successfully.
  final Future<bool> Function(
    ClassicHareegCpuTurnDecision decision,
    ApplyActionResult result,
  )?
  afterApply;

  /// Runs between successful CPU actions, while control still belongs to a CPU.
  final Future<bool> Function(ClassicHareegCpuTurnDecision decision)?
  beforeNextAction;
}

/// Result of running CPU turns until control leaves CPU flow.
class ClassicHareegCpuTurnRunResult {
  /// Creates a CPU turn runner result.
  ClassicHareegCpuTurnRunResult({
    required this.stopReason,
    required this.appliedActionCount,
    required Iterable<ClassicHareegCpuTurnDecision> appliedDecisions,
  }) : appliedDecisions = List.unmodifiable(appliedDecisions);

  /// Why the runner stopped.
  final ClassicHareegCpuTurnStopReason stopReason;

  /// Number of CPU actions successfully applied.
  final int appliedActionCount;

  /// Decisions whose actions were successfully applied.
  final List<ClassicHareegCpuTurnDecision> appliedDecisions;

  /// Whether any CPU action was applied.
  bool get didApplyAction => appliedActionCount > 0;

  /// Whether the CPU action safety limit was reached.
  bool get reachedSafetyLimit =>
      stopReason == ClassicHareegCpuTurnStopReason.safetyLimit;
}

/// Runs Classic Hareeg CPU turns against the rules-engine controller.
///
/// This module is the CPU/game-flow seam: it asks the controller for bounded
/// legal CPU actions, asks the CPU strategy to choose one, applies that action
/// back through the controller, and repeats until the human seat, round end, a
/// hook stop, or the safety limit stops the loop.
class ClassicHareegCpuTurnRunner {
  /// Creates a CPU turn runner.
  const ClassicHareegCpuTurnRunner({
    required this.controller,
    required this.strategy,
    this.humanSeat = PlayerSeat.south,
    this.actionLimit = 64,
    this.hooks = const ClassicHareegCpuTurnHooks(),
  }) : assert(actionLimit > 0);

  /// Rules-engine controller being advanced.
  final ClassicHareegGameController controller;

  /// CPU strategy used to pick from legal action ids.
  final CpuStrategy strategy;

  /// Seat controlled by the human player.
  final PlayerSeat humanSeat;

  /// Maximum CPU actions before stopping with [safetyLimit].
  final int actionLimit;

  /// Side-effect hooks used by callers around runner-owned flow.
  final ClassicHareegCpuTurnHooks hooks;

  /// Runs CPU turns until control leaves CPU flow.
  Future<ClassicHareegCpuTurnRunResult> run() async {
    final appliedDecisions = <ClassicHareegCpuTurnDecision>[];
    var appliedActionCount = 0;

    while (true) {
      final turnStop = _stopResultFor(
        _turnGate(appliedActionCount),
        appliedActionCount,
        appliedDecisions,
      );
      if (turnStop != null) {
        return turnStop;
      }

      final step = _step(appliedActionCount + 1);
      final beforeDecisionStop = _stopResultFor(
        ClassicHareegCpuTurnLoopPlanner.hookGate(
          shouldContinue: await _callStepHook(hooks.beforeDecision, step),
        ),
        appliedActionCount,
        appliedDecisions,
      );
      if (beforeDecisionStop != null) {
        return beforeDecisionStop;
      }

      final legalActionIds = controller.cpuActionIdsFor(step.seat);
      hooks.onLegalActions?.call(step, legalActionIds);
      final legalActionStop = _stopResultFor(
        ClassicHareegCpuTurnLoopPlanner.legalActionGate(
          hasLegalActions: legalActionIds.isNotEmpty,
        ),
        appliedActionCount,
        appliedDecisions,
      );
      if (legalActionStop != null) {
        return legalActionStop;
      }

      final intent = strategy.chooseMove(
        CpuTurnSnapshot(
          seat: step.seat,
          legalActionIds: legalActionIds,
          difficulty: controller.setup.cpuDifficulty,
        ),
      );
      final decision = ClassicHareegCpuTurnDecision(
        step: step,
        legalActionIds: legalActionIds,
        actionId: intent.actionId,
      );
      hooks.onActionChosen?.call(decision);

      final beforeApplyStop = _stopResultFor(
        ClassicHareegCpuTurnLoopPlanner.hookGate(
          shouldContinue: await _callDecisionHook(hooks.beforeApply, decision),
        ),
        appliedActionCount,
        appliedDecisions,
      );
      if (beforeApplyStop != null) {
        return beforeApplyStop;
      }

      final applyResult = controller.applyAction(intent.actionId);
      if (!applyResult.isSuccess) {
        throw StateError(
          'CPU strategy returned illegal action ${intent.actionId}: '
          '${applyResult.message}',
        );
      }

      appliedActionCount += 1;
      appliedDecisions.add(decision);

      final afterApplyStop = _stopResultFor(
        ClassicHareegCpuTurnLoopPlanner.afterApplyHookGate(
          shouldContinue: await _callAfterApplyHook(
            hooks.afterApply,
            decision,
            applyResult,
          ),
          isRoundOver: controller.isRoundOver,
        ),
        appliedActionCount,
        appliedDecisions,
      );
      if (afterApplyStop != null) {
        return afterApplyStop;
      }

      final postApplyStop = _stopResultFor(
        _turnGate(appliedActionCount),
        appliedActionCount,
        appliedDecisions,
      );
      if (postApplyStop != null) {
        return postApplyStop;
      }

      final beforeNextActionStop = _stopResultFor(
        ClassicHareegCpuTurnLoopPlanner.hookGate(
          shouldContinue: await _callDecisionHook(
            hooks.beforeNextAction,
            decision,
          ),
        ),
        appliedActionCount,
        appliedDecisions,
      );
      if (beforeNextActionStop != null) {
        return beforeNextActionStop;
      }
    }
  }

  ClassicHareegCpuTurnLoopPlan _turnGate(int appliedActionCount) {
    return ClassicHareegCpuTurnLoopPlanner.turnGate(
      isRoundOver: controller.isRoundOver,
      isHumanTurn: controller.currentSeat == humanSeat,
      appliedActionCount: appliedActionCount,
      actionLimit: actionLimit,
    );
  }

  ClassicHareegCpuTurnRunResult? _stopResultFor(
    ClassicHareegCpuTurnLoopPlan plan, [
    int appliedActionCount = 0,
    Iterable<ClassicHareegCpuTurnDecision> appliedDecisions = const [],
  ]) {
    if (plan.canContinue) {
      return null;
    }
    return _result(
      _stopReasonFor(plan.scenario),
      appliedActionCount,
      appliedDecisions,
    );
  }

  ClassicHareegCpuTurnStopReason _stopReasonFor(
    ClassicHareegCpuTurnLoopScenario scenario,
  ) {
    return switch (scenario) {
      ClassicHareegCpuTurnLoopScenario.humanTurn =>
        ClassicHareegCpuTurnStopReason.humanTurn,
      ClassicHareegCpuTurnLoopScenario.roundOver =>
        ClassicHareegCpuTurnStopReason.roundOver,
      ClassicHareegCpuTurnLoopScenario.noLegalActions =>
        ClassicHareegCpuTurnStopReason.noLegalActions,
      ClassicHareegCpuTurnLoopScenario.hookStopped =>
        ClassicHareegCpuTurnStopReason.hookStopped,
      ClassicHareegCpuTurnLoopScenario.safetyLimit =>
        ClassicHareegCpuTurnStopReason.safetyLimit,
      ClassicHareegCpuTurnLoopScenario.continueTurn => throw ArgumentError(
        'Continue plans do not have a stop reason.',
      ),
    };
  }

  ClassicHareegCpuTurnStep _step(int index) {
    return ClassicHareegCpuTurnStep(
      index: index,
      seat: controller.currentSeat,
      phase: controller.turnPhase,
      pendingDiscard: controller.pendingDiscard,
      stockCount: controller.stockCount,
      discardCount: controller.discardPile.length,
    );
  }

  ClassicHareegCpuTurnRunResult _result(
    ClassicHareegCpuTurnStopReason reason, [
    int appliedActionCount = 0,
    Iterable<ClassicHareegCpuTurnDecision> appliedDecisions = const [],
  ]) {
    return ClassicHareegCpuTurnRunResult(
      stopReason: reason,
      appliedActionCount: appliedActionCount,
      appliedDecisions: appliedDecisions,
    );
  }
}

Future<bool> _callStepHook(
  Future<bool> Function(ClassicHareegCpuTurnStep step)? hook,
  ClassicHareegCpuTurnStep step,
) async {
  if (hook == null) {
    return true;
  }
  return hook(step);
}

Future<bool> _callDecisionHook(
  Future<bool> Function(ClassicHareegCpuTurnDecision decision)? hook,
  ClassicHareegCpuTurnDecision decision,
) async {
  if (hook == null) {
    return true;
  }
  return hook(decision);
}

Future<bool> _callAfterApplyHook(
  Future<bool> Function(
    ClassicHareegCpuTurnDecision decision,
    ApplyActionResult result,
  )?
  hook,
  ClassicHareegCpuTurnDecision decision,
  ApplyActionResult result,
) async {
  if (hook == null) {
    return true;
  }
  return hook(decision, result);
}
