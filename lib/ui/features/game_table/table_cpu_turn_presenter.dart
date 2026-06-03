import '../../../cpu/classic_hareeg/classic_hareeg_cpu_turn_runner.dart';
import '../../../cpu/classic_hareeg/cpu_strategy.dart';
import '../../../domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import '../../../domain/classic_hareeg/models/player_seat.dart';

/// Callback surface used by [ClassicHareegTableCpuTurnPresenter].
///
/// The presenter owns CPU-run ordering; the widget supplies rendering and IO
/// adapters at this seam.
class ClassicHareegTableCpuTurnPresenterHooks {
  /// Creates CPU turn presenter hooks.
  const ClassicHareegTableCpuTurnPresenterHooks({
    required this.isMounted,
    required this.hasRoundResultPresentation,
    required this.log,
    required this.playFlightForCpuAction,
    required this.capturePlacedJokersForAction,
    required this.emitJokerFeedback,
    required this.clearPlacedJokerSnapshot,
    required this.dropPendingSettledFor,
    required this.ensureFiftyTicker,
    required this.persistAndMaybeFinish,
    required this.postActionDwell,
  });

  /// Whether the host widget can still receive callbacks.
  final bool Function() isMounted;

  /// Whether a round-result overlay is already pending.
  final bool Function() hasRoundResultPresentation;

  /// Debug log sink.
  final void Function(String message) log;

  /// Plays a visible card flight for one CPU action.
  final Future<void> Function(PlayerSeat seat, String actionId)
  playFlightForCpuAction;

  /// Captures pre-apply joker state for actions that can place jokers.
  final void Function(String actionId) capturePlacedJokersForAction;

  /// Emits any post-apply joker feedback.
  final void Function() emitJokerFeedback;

  /// Clears the pending joker diff snapshot.
  final void Function() clearPlacedJokerSnapshot;

  /// Drops UI-only settled meld ghosts after the controller owns the melds.
  final void Function(PlayerSeat seat) dropPendingSettledFor;

  /// Syncs the Fifty ticker with the controller state.
  final void Function() ensureFiftyTicker;

  /// Persists the controller state and optionally presents round result UI.
  final Future<bool> Function() persistAndMaybeFinish;

  /// Dwell to wait after one CPU action.
  final Duration Function(String actionId) postActionDwell;
}

/// Runs Classic Hareeg CPU turns in table presentation modes.
///
/// The CPU runner remains the rules-engine loop. This module owns the UI-side
/// ordering around that loop: visible delays, flights, joker cue diffing,
/// per-step persistence, and the silent fast-forward mode.
class ClassicHareegTableCpuTurnPresenter {
  /// Creates a CPU turn presenter.
  const ClassicHareegTableCpuTurnPresenter({
    required this.controller,
    required this.strategy,
    required this.hooks,
    this.actionLimit = 64,
    this.readPause = Duration.zero,
    this.humanSeat = PlayerSeat.south,
  }) : assert(actionLimit > 0);

  /// Rules-engine controller to advance.
  final ClassicHareegGameController controller;

  /// CPU strategy used for non-human seats.
  final CpuStrategy strategy;

  /// Host adapters for effects and persistence.
  final ClassicHareegTableCpuTurnPresenterHooks hooks;

  /// Maximum actions for one visible run.
  final int actionLimit;

  /// Delay before each visible CPU decision.
  final Duration readPause;

  /// Human-controlled seat.
  final PlayerSeat humanSeat;

  /// Runs visible CPU turns until control leaves CPU flow.
  Future<ClassicHareegCpuTurnRunResult> runVisible() {
    return ClassicHareegCpuTurnRunner(
      controller: controller,
      strategy: strategy,
      actionLimit: actionLimit,
      humanSeat: humanSeat,
      hooks: ClassicHareegCpuTurnHooks(
        beforeDecision: _beforeDecision,
        onLegalActions: _onLegalActions,
        onActionChosen: _onActionChosen,
        beforeApply: _beforeApply,
        afterApply: _afterApply,
        beforeNextAction: _beforeNextAction,
      ),
    ).run();
  }

  /// Runs CPU turns without presentation until the round ends or progress stops.
  Future<bool> fastForwardUntilRoundOver({int actionLimit = 4096}) async {
    var didApplyAny = false;
    while (hooks.isMounted() && !controller.isRoundOver) {
      final runner = ClassicHareegCpuTurnRunner(
        controller: controller,
        strategy: strategy,
        humanSeat: humanSeat,
        actionLimit: actionLimit,
      );
      final result = await runner.run();
      didApplyAny = didApplyAny || result.didApplyAction;
      if (!result.didApplyAction && !controller.isRoundOver) {
        break;
      }
    }
    return didApplyAny;
  }

  Future<bool> _beforeDecision(ClassicHareegCpuTurnStep step) async {
    hooks.log(
      'cpu step ${step.index} start seat=${step.seat.name} '
      'phase=${step.phase} pending=${step.pendingDiscard?.label} '
      'stock=${step.stockCount} discard=${step.discardCount}',
    );
    if (readPause > Duration.zero) {
      await Future<void>.delayed(readPause);
    }
    return hooks.isMounted();
  }

  void _onLegalActions(
    ClassicHareegCpuTurnStep step,
    List<String> legalActionIds,
  ) {
    hooks.log(
      'cpu step ${step.index} legal seat=${step.seat.name} '
      'count=${legalActionIds.length} '
      'actions=${_debugActionSummary(legalActionIds)}',
    );
    if (legalActionIds.isEmpty) {
      hooks.log('cpu step ${step.index} break no legal actions');
    }
  }

  void _onActionChosen(ClassicHareegCpuTurnDecision decision) {
    hooks.log(
      'cpu step ${decision.step.index} chose action=${decision.actionId}',
    );
  }

  Future<bool> _beforeApply(ClassicHareegCpuTurnDecision decision) async {
    final flightWatch = Stopwatch()..start();
    await hooks.playFlightForCpuAction(decision.seat, decision.actionId);
    flightWatch.stop();
    hooks.log(
      'cpu step ${decision.step.index} flight action=${decision.actionId} '
      'elapsed=${flightWatch.elapsedMilliseconds}ms',
    );
    hooks.capturePlacedJokersForAction(decision.actionId);
    return hooks.isMounted();
  }

  Future<bool> _afterApply(
    ClassicHareegCpuTurnDecision decision,
    ApplyActionResult result,
  ) async {
    hooks.log(
      'cpu step ${decision.step.index} applied '
      'action=${decision.actionId} success=${result.isSuccess} '
      'current=${controller.currentSeat.name} phase=${controller.turnPhase}',
    );
    if (result.isSuccess) {
      hooks.emitJokerFeedback();
    } else {
      hooks.clearPlacedJokerSnapshot();
    }
    hooks.dropPendingSettledFor(decision.seat);
    hooks.ensureFiftyTicker();
    final persistWatch = Stopwatch()..start();
    await hooks.persistAndMaybeFinish();
    persistWatch.stop();
    hooks.log(
      'cpu step ${decision.step.index} persist returned '
      'elapsed=${persistWatch.elapsedMilliseconds}ms '
      'roundOver=${controller.isRoundOver}',
    );
    return hooks.isMounted() &&
        !controller.isRoundOver &&
        !hooks.hasRoundResultPresentation();
  }

  Future<bool> _beforeNextAction(ClassicHareegCpuTurnDecision decision) async {
    final dwell = hooks.postActionDwell(decision.actionId);
    if (dwell > Duration.zero) {
      await Future<void>.delayed(dwell);
    }
    return hooks.isMounted();
  }
}

String _debugActionSummary(Iterable<String> actionIds) {
  final ids = actionIds.toList(growable: false);
  if (ids.isEmpty) {
    return '[]';
  }
  const maxShown = 5;
  final shown = ids.take(maxShown).join(', ');
  if (ids.length <= maxShown) {
    return '[$shown]';
  }
  return '[$shown, +${ids.length - maxShown} more]';
}
