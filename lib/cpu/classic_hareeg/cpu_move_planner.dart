import '../../domain/classic_hareeg/game/classic_hareeg_action.dart';

/// CPU move scenario selected from a legal action surface.
enum ClassicHareegCpuMoveScenario {
  /// No legal actions were available.
  noLegalActions,

  /// Claim Fifty / Khamsin before any other move.
  fiftyClaim,

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

class _ClassicHareegCpuPriority {
  const _ClassicHareegCpuPriority(this.kind, this.scenario);

  final ClassicHareegActionKind kind;
  final ClassicHareegCpuMoveScenario scenario;
}

/// Selects a CPU action from an already-legal Classic Hareeg action surface.
abstract final class ClassicHareegCpuMovePlanner {
  static const _priority = [
    _ClassicHareegCpuPriority(
      ClassicHareegActionKind.claimFifty,
      ClassicHareegCpuMoveScenario.fiftyClaim,
    ),
    _ClassicHareegCpuPriority(
      ClassicHareegActionKind.playMeld,
      ClassicHareegCpuMoveScenario.meldPlay,
    ),
    _ClassicHareegCpuPriority(
      ClassicHareegActionKind.playMeldWithJoker,
      ClassicHareegCpuMoveScenario.meldPlay,
    ),
    _ClassicHareegCpuPriority(
      ClassicHareegActionKind.replaceJoker,
      ClassicHareegCpuMoveScenario.jokerReplacement,
    ),
    _ClassicHareegCpuPriority(
      ClassicHareegActionKind.placeCover,
      ClassicHareegCpuMoveScenario.cover,
    ),
    _ClassicHareegCpuPriority(
      ClassicHareegActionKind.drawStock,
      ClassicHareegCpuMoveScenario.drawStock,
    ),
    _ClassicHareegCpuPriority(
      ClassicHareegActionKind.takeDiscard,
      ClassicHareegCpuMoveScenario.takeDiscard,
    ),
  ];

  /// Evaluates the CPU move plan for [legalActionIds].
  static ClassicHareegCpuMovePlan evaluate(Iterable<String> legalActionIds) {
    final actions = [
      for (final id in legalActionIds)
        _ClassicHareegCpuLegalAction(
          actionId: id,
          descriptor: ClassicHareegActionIds.describe(id),
        ),
    ];
    if (actions.isEmpty) {
      return const ClassicHareegCpuMovePlan(
        scenario: ClassicHareegCpuMoveScenario.noLegalActions,
        actionId: null,
      );
    }

    for (final priority in _priority) {
      for (final action in actions) {
        if (action.descriptor.kind == priority.kind) {
          return ClassicHareegCpuMovePlan(
            scenario: priority.scenario,
            actionId: action.actionId,
          );
        }
      }
    }

    for (final action in actions) {
      if (action.descriptor.isSafeDiscard) {
        return ClassicHareegCpuMovePlan(
          scenario: ClassicHareegCpuMoveScenario.safeDiscard,
          actionId: action.actionId,
        );
      }
    }

    for (final action in actions) {
      if (action.descriptor.kind ==
          ClassicHareegActionKind.returnPendingDiscard) {
        return ClassicHareegCpuMovePlan(
          scenario: ClassicHareegCpuMoveScenario.returnPendingDiscard,
          actionId: action.actionId,
        );
      }
    }

    return ClassicHareegCpuMovePlan(
      scenario: ClassicHareegCpuMoveScenario.fallback,
      actionId: actions.first.actionId,
    );
  }
}

class _ClassicHareegCpuLegalAction {
  const _ClassicHareegCpuLegalAction({
    required this.actionId,
    required this.descriptor,
  });

  final String actionId;
  final ClassicHareegActionDescriptor descriptor;
}
