import '../../../../domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../l10n/app_strings.dart';

/// Declarative definition of one guided practice lesson.
///
/// A script pairs a deterministic board (built fresh for every run, so replay
/// always starts identically) with an ordered list of teaching steps. The
/// lesson is complete when the final step is satisfied. All move legality is
/// enforced by the real [ClassicHareegGameController] — the script only
/// narrows which legal actions the teaching surface exposes and decides when
/// the player has demonstrated the mechanic.
class PracticeLessonScript {
  /// Creates a lesson script.
  const PracticeLessonScript({
    required this.lessonId,
    required this.buildSnapshot,
    required this.steps,
    this.seat = PlayerSeat.south,
  });

  /// Stable catalog lesson id this script teaches (see `PracticeCatalog`).
  final String lessonId;

  /// Builds the deterministic starting board. Called once per run/replay.
  final ClassicHareegMatchSnapshot Function() buildSnapshot;

  /// Teaching steps in order. Must not be empty.
  final List<PracticeStep> steps;

  /// Seat the player controls. Practice lessons drive only this seat; no CPU
  /// turns run on the teaching surface.
  final PlayerSeat seat;
}

/// Everything a step predicate can inspect after a successful action.
class PracticeStepContext {
  /// Creates a step context.
  const PracticeStepContext({
    required this.controller,
    required this.action,
    required this.result,
  });

  /// Live lesson controller (already mutated by the action).
  final ClassicHareegGameController controller;

  /// Parsed action the player just performed.
  final ClassicHareegActionDescriptor action;

  /// Engine result for the action.
  final ApplyActionResult result;
}

/// One teaching step: an instruction, a filter for which legal actions the
/// surface offers, and a completion check.
class PracticeStep {
  /// Creates a teaching step.
  PracticeStep({
    required this.prompt,
    this.successNote,
    this.hint,
    bool Function(ClassicHareegActionDescriptor action)? allows,
    bool Function(PracticeStepContext context)? isSatisfied,
  }) : _allows = allows,
       _isSatisfied = isSatisfied;

  /// Convenience step that allows exactly the given action kinds and is
  /// satisfied by any successful allowed action.
  PracticeStep.kinds({
    required this.prompt,
    required Set<ClassicHareegActionKind> kinds,
    this.successNote,
    this.hint,
    bool Function(PracticeStepContext context)? isSatisfied,
  }) : _allows = ((action) => kinds.contains(action.kind)),
       _isSatisfied = isSatisfied;

  /// Localized instruction shown while the step is active.
  final String Function(AppStrings strings) prompt;

  /// Optional localized confirmation shown when the step completes.
  final String Function(AppStrings strings)? successNote;

  /// Optional localized nudge shown under the prompt (e.g. which cards to
  /// look at).
  final String Function(AppStrings strings)? hint;

  final bool Function(ClassicHareegActionDescriptor action)? _allows;
  final bool Function(PracticeStepContext context)? _isSatisfied;

  /// Whether the teaching surface should offer [action] during this step.
  ///
  /// Defaults to allowing every legal action when the script does not narrow
  /// the surface.
  bool allows(ClassicHareegActionDescriptor action) {
    return _allows?.call(action) ?? true;
  }

  /// Whether a successful allowed action completes this step. Defaults to
  /// true: most steps are demonstrated by performing any allowed action.
  bool isSatisfied(PracticeStepContext context) {
    return _isSatisfied?.call(context) ?? true;
  }
}
