import '../../../../domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../l10n/app_strings.dart';
import 'practice_board_grammar.dart';

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
    this.boardAuditSpec,
    this.taughtMelds,
    this.introActionIds = const [],
    this.seat = PlayerSeat.south,
    this.completionNote,
    this.showScoresOnCompletion = false,
    this.fiftyTimerPausesAtSeconds,
  }) : assert(steps.length > 0, 'A lesson script needs at least one step.');

  /// Stable catalog lesson id this script teaches (see `PracticeCatalog`).
  final String lessonId;

  /// Builds the deterministic starting board. Called once per run/replay.
  final ClassicHareegMatchSnapshot Function() buildSnapshot;

  /// Declared board-design proof for this lesson's starting board.
  ///
  /// Null means the lesson deliberately has no grammar claim yet. Scripted
  /// lesson packs should prefer declaring this so the board-design rules live
  /// with the deterministic board instead of only in tests.
  final PracticeBoardAuditSpec? boardAuditSpec;

  /// Declared teaching-card groups in the player's hand — the cards each step
  /// asks the player to use. Everything else in the starting hand is a filler,
  /// and the board grammar proves the fillers form no unintended meld (the
  /// executable form of the per-lesson "Fillers: no meld" comment). An empty
  /// list claims the whole hand is meld-free (bait / trapped-card lessons);
  /// null makes no hand-cleanliness claim.
  final List<Set<String>>? taughtMelds;

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

  /// Optional localized outcome note for the completion panel. Receives the
  /// finished controller so finish/Fifty lessons can cite the real score
  /// impact the engine just applied.
  final String Function(
    AppStrings strings,
    ClassicHareegGameController controller,
  )?
  completionNote;

  /// Whether the real score sheet opens over the finished board before the
  /// completion panel — scoring lessons let the player read the round's
  /// effect where a match would show it, instead of narrating numbers in
  /// the panel text.
  final bool showScoresOnCompletion;

  /// When set, the lesson clock freezes once the live Fifty window counts
  /// down to this many seconds — the ring ticks long enough to feel real,
  /// then holds so reading the prompt is never punished. Null lets the
  /// window expire like a match (the dead-end restart path).
  final int? fiftyTimerPausesAtSeconds;

  /// Audits [snapshot] against this script's declared board grammar.
  PracticeBoardAuditResult? auditSnapshot(ClassicHareegMatchSnapshot snapshot) {
    final spec = boardAuditSpec;
    if (spec == null) {
      return null;
    }
    return PracticeBoardGrammar.auditSnapshot(
      snapshot,
      spec,
      compositionSeat: seat,
      taughtMelds: taughtMelds,
    );
  }

  /// Builds and audits the initial board.
  PracticeBoardAuditResult? auditInitialBoard() {
    return auditSnapshot(buildSnapshot());
  }
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
    this.deadEndNote,
    this.highlightCardIds = const {},
    this.highlightGroups = const [],
    this.completesOnPenalty = false,
    bool Function(ClassicHareegActionDescriptor action)? allows,
    bool Function(PracticeStepContext context)? isSatisfied,
    bool Function(ClassicHareegGameController controller)? isDemonstrated,
    bool Function(ClassicHareegGameController controller)? isDeadEnd,
  }) : _allows = allows,
       _isSatisfied = isSatisfied,
       _isDemonstrated = isDemonstrated,
       _isDeadEnd = isDeadEnd;

  /// Convenience step that allows exactly the given action kinds and is
  /// satisfied by any successful allowed action.
  PracticeStep.kinds({
    required this.prompt,
    required Set<ClassicHareegActionKind> kinds,
    this.successNote,
    this.hint,
    this.holdNote,
    this.deadEndNote,
    this.highlightCardIds = const {},
    this.highlightGroups = const [],
    this.completesOnPenalty = false,
    bool Function(PracticeStepContext context)? isSatisfied,
    bool Function(ClassicHareegGameController controller)? isDemonstrated,
    bool Function(ClassicHareegGameController controller)? isDeadEnd,
  }) : _allows = ((action) => kinds.contains(action.kind)),
       _isSatisfied = isSatisfied,
       _isDemonstrated = isDemonstrated,
       _isDeadEnd = isDeadEnd;

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

  /// Optional localized explanation shown when the step dead-ends (see
  /// [isDeadEnd]) — what went wrong and what the restart will teach.
  final String Function(AppStrings strings)? deadEndNote;

  /// Card ids the table rings with the coach highlight while this step is
  /// active — the specific cards the step asks the player to find, in the
  /// same visual language the live coaching tier uses. Steps that
  /// deliberately leave the choice open (pick any discard) ring nothing.
  /// Stock and pile-take rings are derived from the step's allowed kinds,
  /// not listed here.
  final Set<String> highlightCardIds;

  /// Ordered highlight groups for cross-zone steps that ring two distinct
  /// things at once — the palette index is the group's position
  /// ([LoungeTokens.coachRingPalette], the same hues the live coach uses).
  /// Group 0 is "the card(s) you play or hold"; group 1 is "the target meld
  /// already on the table". When empty, [highlightCardIds] is the single-group
  /// shorthand and every ring is the default teal; when non-empty, the table
  /// rings each group in its own colour.
  final List<Set<String>> highlightGroups;

  /// Whether a reverted (penalised) allowed action can complete this step.
  ///
  /// Default false: the session collapses a reverted engine result (a Strict
  /// paid mistake, where the score is charged but the card snaps back and the
  /// turn does not advance) into a non-advancing rejection, so a take-back or
  /// an unintended penalty never counts as progress. A Strict lesson that
  /// teaches the penalty itself opts in here: the reverted throw is the taught
  /// move, so the session evaluates [isSatisfied] on it the same way it would
  /// an accepted action and the lesson can complete on the +N. Only reachable
  /// from `TableStrictness.strict` lessons — every other tier blocks the
  /// mistake before it can revert.
  final bool completesOnPenalty;

  final bool Function(ClassicHareegActionDescriptor action)? _allows;
  final bool Function(PracticeStepContext context)? _isSatisfied;
  final bool Function(ClassicHareegGameController controller)? _isDemonstrated;
  final bool Function(ClassicHareegGameController controller)? _isDeadEnd;

  /// Whether this step can re-verify its outcome from board state alone.
  bool get hasDemonstrationCheck => _isDemonstrated != null;

  /// Whether the teaching surface should offer [action] during this step.
  ///
  /// Defaults to allowing every legal action when the script does not narrow
  /// the surface.
  bool allows(ClassicHareegActionDescriptor action) {
    return _allows?.call(action) ?? true;
  }

  /// Whether a successful allowed action completes this step. Defaults to
  /// the step's board-state proof when one is declared (see
  /// [isDemonstrated]), else to true: most steps are demonstrated by
  /// performing any allowed action.
  bool isSatisfied(PracticeStepContext context) {
    final satisfied = _isSatisfied;
    if (satisfied != null) {
      return satisfied(context);
    }
    return _isDemonstrated?.call(context.controller) ?? true;
  }

  /// Whether this step's outcome currently holds on the board — the
  /// state-level proof behind the action-level [isSatisfied]. The session
  /// re-checks it after every take-back: a retract that undoes a completed
  /// step's meld walks the lesson back to that step's prompt, and a step
  /// whose outcome already stands (re-melding after a deeper retract) is
  /// skipped on the way forward. Steps without a check are action-proofs
  /// (a draw, a discard) that no take-back can undo.
  bool isDemonstrated(ClassicHareegGameController controller) {
    return _isDemonstrated?.call(controller) ?? true;
  }

  /// Whether the board can no longer demonstrate this step — a timed window
  /// expired and the taught move left the rules surface for good. Most steps
  /// can never strand (the default is false); a dead-ended lesson restarts
  /// on a fresh board instead of leaving the prompt pointing at nothing.
  bool isDeadEnd(ClassicHareegGameController controller) {
    return _isDeadEnd?.call(controller) ?? false;
  }
}
