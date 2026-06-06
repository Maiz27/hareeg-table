import '../../../../domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import 'practice_lesson_script.dart';

/// How the session handled one submitted action.
enum PracticeSubmitStatus {
  /// The engine rejected the action (or reverted it with a penalty under the
  /// stricter tiers); the step is unchanged. The result message explains why
  /// (real rules feedback).
  rejected,

  /// The action is not offered by the current step; nothing was applied.
  notAllowed,

  /// The action applied but did not finish the step (multi-action steps).
  accepted,

  /// The action applied and completed the current step.
  stepCompleted,

  /// The action applied and completed the final step: lesson done.
  lessonCompleted,
}

/// Outcome of [PracticeSession.submit].
class PracticeSubmitResult {
  const PracticeSubmitResult._(this.status, this.message);

  /// What happened to the step/lesson.
  final PracticeSubmitStatus status;

  /// Raw engine message for rejected actions (empty otherwise). UI localizes
  /// it via `AppStrings.gameMessage`.
  final String message;

  /// Whether the action mutated the board.
  bool get applied {
    return status != PracticeSubmitStatus.rejected &&
        status != PracticeSubmitStatus.notAllowed;
  }
}

/// Runtime for one guided practice lesson.
///
/// Owns a private [ClassicHareegGameController] built from the script's
/// deterministic snapshot. The session never touches the active-match store
/// and never runs CPU turns; the lesson ends the moment the final step is
/// demonstrated.
class PracticeSession {
  /// Starts (or restarts) a lesson run.
  PracticeSession({required this.script})
    : controller = ClassicHareegGameController.fromSnapshot(
        script.buildSnapshot(),
      );

  /// Script being taught.
  final PracticeLessonScript script;

  /// Live lesson controller. Read-only access for the teaching surface;
  /// mutations must go through [submit] so step progress stays in sync.
  final ClassicHareegGameController controller;

  var _stepIndex = 0;

  /// Legal-action surface for the current board state; computing it runs the
  /// engine's combinatorial meld enumeration, so it is cached until [submit]
  /// mutates the board or advances the step.
  List<ClassicHareegActionDescriptor>? _allowedActionsCache;
  Set<String>? _allowedActionIdsCache;

  /// Seat the player controls.
  PlayerSeat get seat => script.seat;

  /// Zero-based index of the active step.
  int get stepIndex => _stepIndex;

  /// Total step count.
  int get stepCount => script.steps.length;

  /// Whether every step has been demonstrated.
  bool get isComplete => _stepIndex >= script.steps.length;

  /// Active step, or null once the lesson is complete.
  PracticeStep? get currentStep => isComplete ? null : script.steps[_stepIndex];

  /// Legal engine actions the current step offers, as parsed descriptors.
  ///
  /// This is the real rules surface filtered by the script — practice never
  /// invents actions the engine would not accept.
  List<ClassicHareegActionDescriptor> get allowedActions {
    final step = currentStep;
    if (step == null) {
      return const [];
    }
    return _allowedActionsCache ??= [
      for (final action
          in controller
              .legalActionIdsFor(seat)
              .map(ClassicHareegActionIds.describe))
        if (step.allows(action)) action,
    ];
  }

  /// Raw ids of [allowedActions] — the table's practice affordance gate, so
  /// only on-script moves light up as tappable/draggable targets.
  Set<String> get allowedActionIds {
    return _allowedActionIdsCache ??= {
      for (final action in allowedActions) action.id,
    };
  }

  /// Applies one action through the real engine and advances step progress.
  PracticeSubmitResult submit(String actionId) {
    final step = currentStep;
    if (step == null) {
      return const PracticeSubmitResult._(PracticeSubmitStatus.notAllowed, '');
    }
    final action = ClassicHareegActionIds.describe(actionId);
    if (!step.allows(action)) {
      return const PracticeSubmitResult._(PracticeSubmitStatus.notAllowed, '');
    }

    final result = controller.applyAction(actionId);
    if (result.isSuccess) {
      _allowedActionsCache = null;
      _allowedActionIdsCache = null;
    }
    if (!result.isSuccess || result.revertedCardId != null) {
      // A reverted action (stricter tiers) only applied a penalty — the move
      // itself was taken back, so the step was not demonstrated.
      return PracticeSubmitResult._(
        PracticeSubmitStatus.rejected,
        result.message,
      );
    }

    final context = PracticeStepContext(
      controller: controller,
      action: action,
      result: result,
    );
    if (!step.isSatisfied(context)) {
      return const PracticeSubmitResult._(PracticeSubmitStatus.accepted, '');
    }

    _stepIndex += 1;
    return PracticeSubmitResult._(
      isComplete
          ? PracticeSubmitStatus.lessonCompleted
          : PracticeSubmitStatus.stepCompleted,
      '',
    );
  }
}
