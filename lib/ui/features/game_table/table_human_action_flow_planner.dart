import '../../../domain/classic_hareeg/game/classic_hareeg_action.dart';
import '../../core/audio/table_audio.dart';
import '../../core/haptics/table_haptics.dart';
import 'table_action_presentation_planner.dart';

/// Planned UI follow-up for one human table action application.
class ClassicHareegHumanActionFlowPlan {
  /// Creates a human action flow plan.
  const ClassicHareegHumanActionFlowPlan({
    required this.didApplyAction,
    required this.feedbackMessage,
    required this.feedbackIsError,
    required this.haptic,
    required this.sound,
    required this.shouldClearSelection,
    required this.shouldEnsureFiftyTicker,
    required this.shouldPersist,
    required this.shouldRunCpuAfterPersist,
  });

  /// Whether the controller accepted and applied the action.
  final bool didApplyAction;

  /// Feedback message from the controller.
  final String? feedbackMessage;

  /// Whether the feedback should render as an error.
  final bool feedbackIsError;

  /// Haptic cue to fire, if any.
  final TableHapticEvent? haptic;

  /// Sound cue to play, if any.
  final TableSoundEvent? sound;

  /// Whether local selected-card state should be cleared.
  final bool shouldClearSelection;

  /// Whether the Fifty ticker should be synced after the action.
  final bool shouldEnsureFiftyTicker;

  /// Whether the table should persist after this result.
  final bool shouldPersist;

  /// Whether CPU turns should run after persistence completes.
  final bool shouldRunCpuAfterPersist;
}

/// Plans table-side follow-up work after a human action apply attempt.
abstract final class ClassicHareegHumanActionFlowPlanner {
  /// Evaluates the flow plan after the controller applies or rejects [actionId].
  static ClassicHareegHumanActionFlowPlan afterApply({
    required String actionId,
    required bool isSuccess,
    required String? message,
    required bool soundPlayedWithFlight,
  }) {
    if (!isSuccess) {
      return ClassicHareegHumanActionFlowPlan(
        didApplyAction: false,
        feedbackMessage: message,
        feedbackIsError: true,
        haptic: TableHapticEvent.illegalAction,
        sound: TableSoundEvent.invalidAction,
        shouldClearSelection: false,
        shouldEnsureFiftyTicker: false,
        shouldPersist: false,
        shouldRunCpuAfterPersist: false,
      );
    }

    final presentation = ClassicHareegActionPresentationPlanner.forHumanAction(
      actionId,
    );
    final action = ClassicHareegActionIds.describe(actionId);

    return ClassicHareegHumanActionFlowPlan(
      didApplyAction: true,
      feedbackMessage: message,
      feedbackIsError: false,
      haptic: presentation.haptic,
      sound: soundPlayedWithFlight ? null : presentation.sound,
      shouldClearSelection: action.clearsSelection,
      shouldEnsureFiftyTicker: true,
      shouldPersist: true,
      shouldRunCpuAfterPersist: true,
    );
  }
}
