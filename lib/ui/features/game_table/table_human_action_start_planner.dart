import 'table_action_presentation_planner.dart';

/// Scenario selected before a human table action is applied.
enum ClassicHareegHumanActionStartScenario {
  /// CPU flow is already running.
  blockedByCpu,

  /// The opening deal choreography is still running.
  blockedByOpeningDeal,

  /// Another human action is already in its pre-apply/apply path.
  blockedByPendingHumanAction,

  /// The action can apply without a pre-apply card flight.
  applyWithoutFlight,

  /// A pre-apply card flight should run before the controller apply.
  playFlightBeforeApply,
}

/// Scenario selected after optional pre-apply work finishes.
enum ClassicHareegHumanActionApplyGateScenario {
  /// The widget is still mounted and the controller action can be applied.
  readyToApply,

  /// The widget unmounted before the controller action could be applied.
  unmounted,
}

/// Planned start behavior for one human action request.
class ClassicHareegHumanActionStartPlan {
  /// Creates a human action start plan.
  const ClassicHareegHumanActionStartPlan({
    required this.scenario,
    required this.actionId,
    required this.presentation,
  });

  /// Scenario selected by the start gate.
  final ClassicHareegHumanActionStartScenario scenario;

  /// Requested action id.
  final String actionId;

  /// Presentation facts for allowed actions.
  final TableActionPresentationPlan? presentation;

  /// Whether the widget should enter its pending human-action lock.
  bool get shouldLockInput =>
      scenario == ClassicHareegHumanActionStartScenario.applyWithoutFlight ||
      scenario == ClassicHareegHumanActionStartScenario.playFlightBeforeApply;

  /// Whether the request should proceed past the start gate.
  bool get shouldStart => shouldLockInput;

  /// Whether a pre-apply card flight should be attempted.
  bool get shouldPlayFlight =>
      scenario == ClassicHareegHumanActionStartScenario.playFlightBeforeApply;
}

/// Planned controller-apply gate after optional pre-apply work.
class ClassicHareegHumanActionApplyGate {
  /// Creates a human action apply gate.
  const ClassicHareegHumanActionApplyGate({
    required this.scenario,
    required this.soundPlayedWithFlight,
  });

  /// Scenario selected by the apply gate.
  final ClassicHareegHumanActionApplyGateScenario scenario;

  /// Whether the action sound was already played by a successful flight.
  final bool soundPlayedWithFlight;

  /// Whether the controller action should now be applied.
  bool get shouldApply =>
      scenario == ClassicHareegHumanActionApplyGateScenario.readyToApply;
}

/// Plans the pre-apply path for human table actions.
abstract final class ClassicHareegHumanActionStartPlanner {
  /// Evaluates whether [actionId] should start and whether it needs a flight.
  static ClassicHareegHumanActionStartPlan start({
    required String actionId,
    required bool playFlight,
    required bool isCpuRunning,
    required bool isOpeningDealRunning,
    required bool isHumanActionPending,
  }) {
    if (isCpuRunning) {
      return ClassicHareegHumanActionStartPlan(
        scenario: ClassicHareegHumanActionStartScenario.blockedByCpu,
        actionId: actionId,
        presentation: null,
      );
    }
    if (isOpeningDealRunning) {
      return ClassicHareegHumanActionStartPlan(
        scenario: ClassicHareegHumanActionStartScenario.blockedByOpeningDeal,
        actionId: actionId,
        presentation: null,
      );
    }
    if (isHumanActionPending) {
      return ClassicHareegHumanActionStartPlan(
        scenario:
            ClassicHareegHumanActionStartScenario.blockedByPendingHumanAction,
        actionId: actionId,
        presentation: null,
      );
    }

    final presentation = ClassicHareegActionPresentationPlanner.forHumanAction(
      actionId,
    );
    return ClassicHareegHumanActionStartPlan(
      scenario: playFlight && presentation.flight != null
          ? ClassicHareegHumanActionStartScenario.playFlightBeforeApply
          : ClassicHareegHumanActionStartScenario.applyWithoutFlight,
      actionId: actionId,
      presentation: presentation,
    );
  }

  /// Evaluates whether the controller action may apply after pre-apply work.
  static ClassicHareegHumanActionApplyGate afterPreApply({
    required bool isMounted,
    required bool plannedFlight,
    required bool flightPlayed,
  }) {
    if (!isMounted) {
      return const ClassicHareegHumanActionApplyGate(
        scenario: ClassicHareegHumanActionApplyGateScenario.unmounted,
        soundPlayedWithFlight: false,
      );
    }
    return ClassicHareegHumanActionApplyGate(
      scenario: ClassicHareegHumanActionApplyGateScenario.readyToApply,
      soundPlayedWithFlight: plannedFlight && flightPlayed,
    );
  }
}
