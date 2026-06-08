import '../../../cpu/classic_hareeg/cpu_strategy.dart';
import '../../../domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import '../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../l10n/app_strings.dart';
import '../learning/practice/practice_lesson_script.dart';
import '../learning/practice/practice_session.dart';
import 'coach/coach_highlighting.dart';
import 'table_interaction_planner.dart';

/// Practice-mode run state hosted by the real table surface.
///
/// The lesson [PracticeSession] owns real rule-engine mutations and step
/// gating. This module owns the table-facing presentation state that follows
/// from those mutations: banner reactions, score reveal hand-off, completion,
/// dead-end detection, and coach-style highlighting.
class PracticeTableRun {
  /// Starts a practice run from an existing session.
  PracticeTableRun(PracticeSession session) : _session = session;

  PracticeSession _session;
  var _complete = false;
  var _scoreReveal = false;
  String Function(AppStrings strings)? _reaction;

  /// Active lesson session.
  PracticeSession get session => _session;

  /// Active lesson script.
  PracticeLessonScript get script => _session.script;

  /// Controller for the deterministic practice board.
  ClassicHareegGameController get controller => _session.controller;

  /// Whether the lesson has completed and the completion overlay should show.
  bool get isComplete => _complete;

  /// Whether a scoring lesson is showing the score sheet before completion.
  bool get isScoreReveal => _scoreReveal;

  /// Banner reaction from the latest practice action.
  String Function(AppStrings strings)? get reaction => _reaction;

  /// Current step before the next submitted action.
  PracticeStep? get currentStep => _session.currentStep;

  /// Scripted prologue action ids, played visibly before the player's step.
  List<String> get introActionIds => _session.script.introActionIds;

  /// Control actions that the active practice step allows.
  List<String> controlActionIdsFor({
    required Iterable<String> actionIds,
    required bool isHumanTurn,
  }) {
    final gate = actionGate(isHumanTurn: isHumanTurn);
    return [
      for (final id in actionIds)
        if (gate.allows(id)) id,
    ];
  }

  /// Action gate for the active practice step.
  TableInteractionActionGate actionGate({required bool isHumanTurn}) {
    if (!isHumanTurn || _complete) {
      return const BlockAllTableInteractionActionGate();
    }
    return PredicateTableInteractionActionGate(_session.offersActionId);
  }

  /// Step banner projection for the table surface, or null when practice
  /// narration should step aside for another overlay or scripted intro.
  PracticeTableBannerState? bannerState({
    required bool blockedByOverlay,
    required bool scriptedIntroRunning,
  }) {
    if (_complete ||
        blockedByOverlay ||
        scriptedIntroRunning ||
        controller.currentSeat != _session.seat ||
        isDeadEnd(scriptedIntroRunning: scriptedIntroRunning)) {
      return null;
    }
    final step = _session.currentStep;
    if (step == null) {
      return null;
    }
    return PracticeTableBannerState(
      stepIndex: _session.stepIndex,
      stepCount: _session.stepCount,
      prompt: step.prompt,
      hint: step.hint,
      reaction: _reaction,
    );
  }

  /// Starts [script] on a fresh board, resetting all presentation state.
  void restart(PracticeLessonScript script) {
    _session = PracticeSession(script: script);
    _complete = false;
    _scoreReveal = false;
    _reaction = null;
  }

  /// Restarts the current lesson script on a fresh board.
  void restartCurrent() {
    restart(_session.script);
  }

  /// Script that continues the current pack, if the shell supplies one.
  PracticeLessonScript? nextScript(
    PracticeLessonScript? Function(String lessonId)? resolve,
  ) {
    return resolve?.call(_session.script.lessonId);
  }

  /// Submits [actionId] through the session.
  PracticeSubmitResult submit(String actionId) {
    return _session.submit(actionId);
  }

  /// Submits [actionId] and maps it onto the table action result shape.
  PracticeTableActionSubmission submitTableAction(String actionId) {
    final completedStep = _session.currentStep;
    final result = _session.submit(actionId);
    return PracticeTableActionSubmission(
      result: result,
      completedStep: completedStep,
    );
  }

  /// Completes the score reveal hand-off for a scoring lesson.
  void finishScoreReveal() {
    _scoreReveal = false;
    _complete = true;
  }

  /// Completion-panel note derived from the finished controller state.
  String? completionNote(AppStrings strings) {
    return _session.script.completionNote?.call(strings, controller);
  }

  /// Missed-lesson note for a dead-ended run.
  String missedNote(AppStrings strings, {required String fallback}) {
    return _session.currentStep?.deadEndNote?.call(strings) ?? fallback;
  }

  /// Whether the scripted intro should run now.
  bool shouldRunScriptedIntro({required bool isCpuRunning}) {
    return introActionIds.isNotEmpty &&
        controller.currentSeat != _session.seat &&
        !isCpuRunning;
  }

  /// Whether the current run has stranded on a step that cannot be
  /// demonstrated anymore.
  bool isDeadEnd({required bool scriptedIntroRunning}) {
    return !_complete && !scriptedIntroRunning && _session.isDeadEnd;
  }

  /// Maps the active step into the same highlight language the live coach uses.
  CoachHighlighting highlighting({
    required bool isHumanTurn,
    required HareegCard? topDiscard,
  }) {
    final step = !isHumanTurn || _complete ? null : _session.currentStep;
    if (step == null) {
      return CoachHighlighting.none;
    }
    final allowsTake =
        step.allows(
          ClassicHareegActionIds.describe(ClassicHareegActionIds.takeDiscard),
        ) ||
        step.allows(
          ClassicHareegActionIds.describe(ClassicHareegActionIds.claimFifty),
        );
    final highlightStock = step.allows(
      ClassicHareegActionIds.describe(ClassicHareegActionIds.drawStock),
    );
    final highlightIds = {
      ...step.highlightCardIds,
      if (allowsTake && topDiscard != null) topDiscard.id,
    };
    // A grouped step rings each group in its own palette hue (group 0 = teal),
    // exactly the way CoachHighlighting.fromHint flattens a coach hint's ring
    // groups; the take/pile-derived ring stays a plain teal highlight.
    final groupOf = <String, int>{};
    for (var group = 0; group < step.highlightGroups.length; group += 1) {
      for (final id in step.highlightGroups[group]) {
        groupOf[id] = group;
      }
    }
    return CoachHighlighting(
      highlightIds: highlightIds,
      groupOf: groupOf,
      highlightStock: highlightStock,
    );
  }

  /// Updates presentation state from [result] and reports table-side effects.
  PracticeTableRunEffect applyProgress(
    PracticeSubmitResult result,
    PracticeStep? completedStep,
  ) {
    switch (result.status) {
      case PracticeSubmitStatus.rejected:
      case PracticeSubmitStatus.notAllowed:
        return const PracticeTableRunEffect();
      case PracticeSubmitStatus.corrected:
        final changed = _reaction != null;
        _reaction = null;
        return PracticeTableRunEffect(shouldRebuild: changed);
      case PracticeSubmitStatus.accepted:
        final note = completedStep?.holdNote;
        final changed = _reaction != note;
        _reaction = note;
        return PracticeTableRunEffect(shouldRebuild: changed);
      case PracticeSubmitStatus.stepCompleted:
        _reaction = completedStep?.successNote;
        return const PracticeTableRunEffect(shouldRebuild: true);
      case PracticeSubmitStatus.lessonCompleted:
        _reaction = null;
        if (_session.script.showScoresOnCompletion) {
          _scoreReveal = true;
        } else {
          _complete = true;
        }
        return PracticeTableRunEffect(
          shouldRebuild: true,
          shouldPersistCompletion: true,
          lessonId: _session.script.lessonId,
          shouldOpenScoreReveal: _scoreReveal,
        );
    }
  }
}

/// Table-ready projection of the active practice step banner.
class PracticeTableBannerState {
  /// Creates banner state.
  const PracticeTableBannerState({
    required this.stepIndex,
    required this.stepCount,
    required this.prompt,
    this.hint,
    this.reaction,
  });

  /// Zero-based active step index.
  final int stepIndex;

  /// Total steps in the lesson.
  final int stepCount;

  /// Localized step prompt.
  final String Function(AppStrings strings) prompt;

  /// Optional localized hint under the prompt.
  final String Function(AppStrings strings)? hint;

  /// Optional localized reaction from the latest practice action.
  final String Function(AppStrings strings)? reaction;
}

/// Practice action submission with the table flow result precomputed.
class PracticeTableActionSubmission {
  /// Creates a submission.
  const PracticeTableActionSubmission({
    required this.result,
    required this.completedStep,
  });

  /// Practice-session result.
  final PracticeSubmitResult result;

  /// Step that was active before this action, used for success/hold notes.
  final PracticeStep? completedStep;

  /// Whether the action was legal in the engine but outside the lesson step.
  bool get isOffScript => result.status == PracticeSubmitStatus.notAllowed;

  /// Result shape consumed by the normal table flow planner.
  ApplyActionResult get tableResult {
    return switch (result.status) {
      PracticeSubmitStatus.rejected || PracticeSubmitStatus.notAllowed =>
        ApplyActionResult.failure(result.message),
      PracticeSubmitStatus.accepted ||
      PracticeSubmitStatus.corrected ||
      PracticeSubmitStatus.stepCompleted ||
      PracticeSubmitStatus.lessonCompleted => const ApplyActionResult.success(),
    };
  }
}

/// Table-side consequences of a practice progress update.
class PracticeTableRunEffect {
  /// Creates a progress effect.
  const PracticeTableRunEffect({
    this.shouldRebuild = false,
    this.shouldPersistCompletion = false,
    this.lessonId,
    this.shouldOpenScoreReveal = false,
  });

  /// Whether the table should rebuild after the run state changed.
  final bool shouldRebuild;

  /// Whether the app shell should persist the completed lesson id.
  final bool shouldPersistCompletion;

  /// Completed lesson id, when [shouldPersistCompletion] is true.
  final String? lessonId;

  /// Whether the score sheet should open before completion.
  final bool shouldOpenScoreReveal;
}

/// Replays a lesson's scripted intro actions in order through the CPU turn
/// presenter. Exhausting the queue means the lesson board and intro disagree.
class PracticeIntroStrategy implements CpuStrategy {
  /// Creates an intro strategy.
  PracticeIntroStrategy(this._actionIds);

  final List<String> _actionIds;
  var _index = 0;

  @override
  CpuMoveIntent chooseMove(
    CpuTurnSnapshot snapshot, {
    CpuObservation? observation,
  }) {
    if (_index >= _actionIds.length) {
      throw StateError(
        'Practice intro script exhausted at ${snapshot.seat.name}.',
      );
    }
    return CpuMoveIntent(actionId: _actionIds[_index++]);
  }
}
