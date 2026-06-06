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
    this.introActionIds = const [],
    this.seat = PlayerSeat.south,
  });

  /// Stable catalog lesson id this script teaches (see `PracticeCatalog`).
  final String lessonId;

  /// Builds the deterministic starting board. Called once per run/replay.
  final ClassicHareegMatchSnapshot Function() buildSnapshot;

  /// Teaching steps in order. Must not be empty.
  final List<PracticeStep> steps;

  /// Scripted prologue the other seats play before the player's first step —
  /// e.g. west drawing and throwing the card the lesson teaches the player
  /// to take, or visibly opening its melds. Applied in order through the
  /// real engine with the table's normal CPU pacing and flights, so the
  /// player watches how seats actually behave. The board must start with
  /// its `currentSeat` on the acting seat, and the final action must hand
  /// the turn to [seat].
  final List<String> introActionIds;

  /// Seat the player controls. Practice lessons drive only this seat; beyond
  /// the scripted intro, no CPU autonomy runs on the teaching surface.
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
    this.holdNote,
    this.highlightCardIds = const {},
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
    this.holdNote,
    this.highlightCardIds = const {},
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

  /// Optional localized reaction for an allowed action that applied but left
  /// the step unsatisfied (e.g. a valid partial run staged below the
  /// benchmark) — the lesson's chance to say what to do about it instead of
  /// repeating the static prompt. Take-backs never trigger it.
  final String Function(AppStrings strings)? holdNote;

  /// Card ids the table rings with the coach highlight while this step is
  /// active — the specific cards the step asks the player to find, in the
  /// same visual language the live coaching tier uses. Steps that
  /// deliberately leave the choice open (pick any discard) ring nothing.
  /// Stock and pile-take rings are derived from the step's allowed kinds,
  /// not listed here.
  final Set<String> highlightCardIds;

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
