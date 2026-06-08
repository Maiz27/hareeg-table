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

  /// The action applied but did not finish the step (multi-action steps or
  /// a staged play that has not satisfied the step yet).
  accepted,

  /// A take-back applied; step progress is untouched. Distinct from
  /// [accepted] so the surface never narrates a correction as a stall.
  corrected,

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
  ///
  /// [now] overrides the base clock; Fifty lessons inject it in tests to
  /// walk the claim window deterministically. When the script pauses the
  /// Fifty timer, the controller reads the base clock through a cap that
  /// freezes once the window counts down to the script's hold point.
  PracticeSession({required this.script, DateTime Function()? now})
    : _baseNow = now ?? DateTime.now {
    final snapshot = script.buildSnapshot();
    final boardAudit = script.auditSnapshot(snapshot);
    if (boardAudit != null && !boardAudit.passed) {
      throw StateError(
        'Practice lesson ${script.lessonId} board grammar failed:\n'
        '${boardAudit.failures.join('\n')}',
      );
    }
    _controller = ClassicHareegGameController.fromSnapshot(
      snapshot,
      now: _lessonNow,
    );
  }

  final DateTime Function() _baseNow;

  /// Window stamp the hold has blessed: it was seen while genuinely live,
  /// so the clock caps for it.
  DateTime? _heldWindowOpenedAt;

  /// Window stamp the hold refuses: it was already expired at first sight
  /// (snapshot restore stamps a deliberately ancient time precisely so a
  /// dressed pile never restores a live claim) — capping it would resurrect
  /// a window the board never offered.
  DateTime? _ignoredWindowOpenedAt;

  /// The lesson clock: real time, capped so a live Fifty window never
  /// counts below the script's hold point. The cap re-derives from the
  /// controller's own window stamp, so every freshly opened window (replay,
  /// restart, the intro's throw) gets its own running-then-held countdown.
  /// The null check covers the controller's own construction, which may
  /// read the clock before the backing field is assigned.
  DateTime _lessonNow() {
    final base = _baseNow();
    final pauseAt = script.fiftyTimerPausesAtSeconds;
    final controller = _controller;
    if (pauseAt == null || controller == null) {
      return base;
    }
    final openedAt = controller.fiftyWindowOpenedAt;
    if (openedAt == null) {
      return base;
    }
    if (openedAt == _ignoredWindowOpenedAt) {
      return base;
    }
    if (openedAt != _heldWindowOpenedAt) {
      // First sight of this window decides its fate: only a stamp that is
      // still inside its own countdown is held; anything older (or oddly
      // in the future) stays on the real clock and expires as it should.
      final age = base.difference(openedAt);
      if (age.isNegative ||
          age.inSeconds >= controller.setup.fiftyTimerSeconds) {
        _ignoredWindowOpenedAt = openedAt;
        return base;
      }
      _heldWindowOpenedAt = openedAt;
    }
    final cap = openedAt.add(
      Duration(seconds: controller.setup.fiftyTimerSeconds - pauseAt),
    );
    return base.isAfter(cap) ? cap : base;
  }

  /// Action kinds that take a staged play back rather than make a move.
  ///
  /// Corrections are how a player recovers from staging the wrong cards
  /// (e.g. a valid-but-partial run that can never reach the opening), so
  /// practice always offers them whenever the engine does — gating them
  /// behind the step filter would strand the lesson. An unsolicited
  /// correction never advances step progress; a step whose filter explicitly
  /// teaches the take-back (benchmark-pressure's retract) completes through
  /// the normal path instead.
  static const _correctionKinds = {
    ClassicHareegActionKind.returnOpeningMelds,
    ClassicHareegActionKind.returnTablePlay,
  };

  /// Script being taught.
  final PracticeLessonScript script;

  ClassicHareegGameController? _controller;

  /// Live lesson controller. Read-only access for the teaching surface;
  /// mutations must go through [submit] so step progress stays in sync.
  ClassicHareegGameController get controller => _controller!;

  var _stepIndex = 0;

  /// Legal-action surface for the current board state; computing it runs the
  /// engine's combinatorial meld enumeration, so it is cached until [submit]
  /// mutates the board or advances the step.
  List<ClassicHareegActionDescriptor>? _allowedActionsCache;

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

  /// Whether the active step can no longer be demonstrated on this board
  /// (e.g. the Fifty window expired while the lesson taught the claim). A
  /// dead-ended run only recovers by restarting on a fresh board.
  bool get isDeadEnd => currentStep?.isDeadEnd(controller) ?? false;

  /// Legal engine actions the current step offers, as parsed descriptors.
  ///
  /// This is the real rules surface filtered by the script — practice never
  /// invents actions the engine would not accept.
  List<ClassicHareegActionDescriptor> get allowedActions {
    final step = currentStep;
    if (step == null) {
      return const [];
    }
    final cached = _allowedActionsCache;
    if (cached != null) {
      return cached;
    }
    final actions = [
      for (final action
          in controller
              .legalActionIdsFor(seat)
              .map(ClassicHareegActionIds.describe))
        if (step.allows(action)) action,
    ];
    // An empty surface mid-step means it is not the player's turn yet — the
    // lesson's scripted intro mutates the board outside [submit], so caching
    // here would freeze the gate before the player's turn arrives.
    if (actions.isEmpty) {
      return actions;
    }
    return _allowedActionsCache = actions;
  }

  /// Whether the active step offers the move encoded by [actionId].
  ///
  /// This is the affordance gate's membership check and it mirrors [submit]'s
  /// step filter exactly: the step decides by parsed action meaning, while
  /// legality is the caller's contract — every id passed here must already be
  /// a real offer computed from the live controller (the table's interaction
  /// readers only produce engine-legal offers). Matching against the
  /// enumerated legal-id surface instead would wrongly darken legal moves the
  /// enumeration chooses not to advertise (staging an opening meld below the
  /// benchmark) or encodes in a different card order (selection-order meld
  /// ids).
  bool offersActionId(String actionId) {
    final step = currentStep;
    if (step == null) {
      return false;
    }
    final action = ClassicHareegActionIds.describe(actionId);
    if (_correctionKinds.contains(action.kind)) {
      return true;
    }
    return step.allows(action);
  }

  /// Applies one action through the real engine and advances step progress.
  PracticeSubmitResult submit(String actionId) {
    final step = currentStep;
    if (step == null) {
      return const PracticeSubmitResult._(PracticeSubmitStatus.notAllowed, '');
    }
    final action = ClassicHareegActionIds.describe(actionId);
    // A take-back the step does not ask for is a correction: applied, never
    // advancing. When the step's own filter names the take-back kind, the
    // retract IS the taught move and completes the step like any other.
    if (_correctionKinds.contains(action.kind) && !step.allows(action)) {
      return _applyCorrection(actionId);
    }
    if (!step.allows(action)) {
      return const PracticeSubmitResult._(PracticeSubmitStatus.notAllowed, '');
    }

    final result = controller.applyAction(actionId);
    if (result.isSuccess) {
      _allowedActionsCache = null;
    }
    if (!result.isSuccess) {
      return PracticeSubmitResult._(
        PracticeSubmitStatus.rejected,
        result.message,
      );
    }
    // A reverted action (stricter tiers) only applied a penalty — the move
    // itself was taken back. By default the step was not demonstrated, so the
    // session reports a non-advancing rejection. A Strict lesson that teaches
    // the penalty opts in via `completesOnPenalty`: there the reverted throw
    // IS the taught move, so it falls through to the normal completion check
    // and the +N completes the step like any accepted action.
    if (result.revertedCardId != null && !step.completesOnPenalty) {
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
    // A step whose outcome already stands is not re-taught: replaying the
    // queens after a deep retract must not ask for the still-placed run
    // again (its only legal "play" would be a card no longer in hand).
    while (!isComplete) {
      final next = script.steps[_stepIndex];
      if (!next.hasDemonstrationCheck || !next.isDemonstrated(controller)) {
        break;
      }
      _stepIndex += 1;
    }
    return PracticeSubmitResult._(
      isComplete
          ? PracticeSubmitStatus.lessonCompleted
          : PracticeSubmitStatus.stepCompleted,
      '',
    );
  }

  /// Applies a take-back through the real engine without touching step
  /// progress — the step's move still has to be demonstrated afterwards.
  ///
  /// A take-back can also un-demonstrate an already-completed step (the
  /// nines retracted off the table while the lesson asks for the closing
  /// discard), so completed steps re-verify their board-state proof and the
  /// lesson walks back to the first one that no longer holds — the prompt
  /// follows the player instead of pointing at a move the board lost.
  PracticeSubmitResult _applyCorrection(String actionId) {
    final result = controller.applyAction(actionId);
    if (!result.isSuccess) {
      return PracticeSubmitResult._(
        PracticeSubmitStatus.rejected,
        result.message,
      );
    }
    _allowedActionsCache = null;
    for (var i = 0; i < _stepIndex; i++) {
      final step = script.steps[i];
      if (step.hasDemonstrationCheck && !step.isDemonstrated(controller)) {
        _stepIndex = i;
        break;
      }
    }
    return const PracticeSubmitResult._(PracticeSubmitStatus.corrected, '');
  }
}
