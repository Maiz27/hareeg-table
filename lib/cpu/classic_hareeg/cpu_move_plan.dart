import 'cpu_observation.dart';

/// CPU move scenario selected from a legal action surface.
enum ClassicHareegCpuMoveScenario {
  /// No legal actions were available.
  noLegalActions,

  /// Claim Fifty / Khamsin before any other move.
  fiftyClaim,

  /// Replay the next step of an active Fifty proof verbatim.
  fiftyProof,

  /// Play a meld, including represented-joker melds.
  meldPlay,

  /// Replace a represented table joker.
  jokerReplacement,

  /// Place a cover on an existing meld.
  cover,

  /// Draw from stock.
  drawStock,

  /// Take the previous discard.
  takeDiscard,

  /// Discard a safe plain card.
  safeDiscard,

  /// Return a picked-up discard when no useful pending play exists.
  returnPendingDiscard,

  /// Last-resort legal action.
  fallback,
}

/// Planned CPU move.
class ClassicHareegCpuMovePlan {
  /// Creates a planned CPU move.
  const ClassicHareegCpuMovePlan({
    required this.scenario,
    required this.actionId,
  });

  /// Legal action category selected by the planner.
  final ClassicHareegCpuMoveScenario scenario;

  /// Legal action id to apply, or null when no action exists.
  final String? actionId;

  /// Whether the plan contains an action.
  bool get hasAction => actionId != null;
}

/// Strategy-specific planner that scores a CPU observation into one move plan.
abstract interface class CpuMovePlanner {
  /// Plans a CPU move from visible state and legal action ids.
  ClassicHareegCpuMovePlan plan(CpuObservation observation);
}
