import '../../../domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import '../../../domain/classic_hareeg/game/classic_hareeg_score_ledger.dart';
import '../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../domain/classic_hareeg/rules/match_progression_rules.dart';

/// Table persistence action selected after a controller state change.
enum ClassicHareegTablePersistenceAction {
  /// Save the still-active match snapshot.
  saveActiveMatch,

  /// Save the prebuilt next-round snapshot.
  saveNextRound,

  /// Clear the active match because the match is complete.
  abandonActiveMatch,
}

/// Table persistence scenario selected after a controller state change.
enum ClassicHareegTablePersistenceScenario {
  /// The active round continues.
  activeRound,

  /// The round ended and a next round should be saved.
  roundCompleteWithNextRound,

  /// The round ended and no next round exists.
  matchComplete,

  /// The round ended, but presentation facts were incomplete.
  roundCompleteMissingPresentation,
}

/// Table action after a persisted round result has been presented.
enum ClassicHareegRoundAdvanceAction {
  /// No round-advance work should run.
  none,

  /// Navigate to the match-over screen.
  openMatchOver,

  /// Swap in the saved next-round snapshot.
  advanceToNextRound,
}

/// Round result payload needed by the table overlay.
class ClassicHareegRoundResultPresentation {
  /// Creates a round result presentation payload.
  ClassicHareegRoundResultPresentation({
    required this.result,
    required this.progress,
    required Map<PlayerSeat, int> previousScores,
    required this.nextSnapshot,
  }) : previousScores = Map.unmodifiable(previousScores);

  /// Completed round result.
  final RoundProgressResult result;

  /// Match progress after applying the completed round.
  final MatchProgressState progress;

  /// Scores before the completed round result was applied.
  final Map<PlayerSeat, int> previousScores;

  /// Snapshot to continue with, or null when the match is complete.
  final ClassicHareegMatchSnapshot? nextSnapshot;
}

/// Planned delayed action after the round-result overlay is shown.
class ClassicHareegRoundAdvancePlan {
  /// Creates a round-advance plan.
  const ClassicHareegRoundAdvancePlan({
    required this.action,
    required this.delay,
    this.nextSnapshot,
  });

  /// No-op round-advance plan.
  const ClassicHareegRoundAdvancePlan.none()
    : action = ClassicHareegRoundAdvanceAction.none,
      delay = Duration.zero,
      nextSnapshot = null;

  /// Action to run after [delay].
  final ClassicHareegRoundAdvanceAction action;

  /// Dwell before [action] runs.
  final Duration delay;

  /// Snapshot to continue with when [action] is
  /// [ClassicHareegRoundAdvanceAction.advanceToNextRound].
  final ClassicHareegMatchSnapshot? nextSnapshot;

  /// Whether this plan schedules any follow-up work.
  bool get shouldSchedule => action != ClassicHareegRoundAdvanceAction.none;
}

/// Planned persistence and optional presentation for the table state.
class ClassicHareegTablePersistencePlan {
  /// Creates a table persistence plan.
  const ClassicHareegTablePersistencePlan({
    required this.scenario,
    required this.action,
    required this.snapshotToSave,
    required this.roundResultPresentation,
  });

  /// High-level scenario selected by the planner.
  final ClassicHareegTablePersistenceScenario scenario;

  /// Repository action the widget adapter should perform.
  final ClassicHareegTablePersistenceAction action;

  /// Snapshot to save for save actions.
  final ClassicHareegMatchSnapshot? snapshotToSave;

  /// Round-result overlay payload to show after successful persistence.
  final ClassicHareegRoundResultPresentation? roundResultPresentation;

  /// Whether successful persistence should show the round-result overlay.
  bool get shouldShowRoundResult => roundResultPresentation != null;

  /// Stable log label matching the old widget persistence paths.
  String get logPath {
    return switch (action) {
      ClassicHareegTablePersistenceAction.saveActiveMatch => 'active',
      ClassicHareegTablePersistenceAction.saveNextRound => 'next-round',
      ClassicHareegTablePersistenceAction.abandonActiveMatch => 'abandon',
    };
  }
}

/// Plans post-overlay round advancement for Classic Hareeg.
abstract final class ClassicHareegRoundAdvancePlanner {
  /// Evaluates the delayed action to schedule after showing [presentation].
  static ClassicHareegRoundAdvancePlan afterRoundResultShown({
    required ClassicHareegRoundResultPresentation presentation,
    required bool isHumanEliminated,
    required Duration nextRoundDelay,
    required Duration matchEndDelay,
  }) {
    final nextSnapshot = presentation.nextSnapshot;
    if (nextSnapshot == null || isHumanEliminated) {
      return ClassicHareegRoundAdvancePlan(
        action: ClassicHareegRoundAdvanceAction.openMatchOver,
        delay: matchEndDelay,
      );
    }

    return ClassicHareegRoundAdvancePlan(
      action: ClassicHareegRoundAdvanceAction.advanceToNextRound,
      delay: nextRoundDelay,
      nextSnapshot: nextSnapshot,
    );
  }
}

/// Plans table persistence and result presentation for Classic Hareeg.
abstract final class ClassicHareegTablePersistencePlanner {
  /// Evaluates the persistence plan for the current controller facts.
  static ClassicHareegTablePersistencePlan plan({
    required bool isRoundOver,
    required ClassicHareegMatchSnapshot? activeSnapshot,
    required ClassicHareegMatchSnapshot? nextRoundSnapshot,
    required RoundProgressResult? roundResult,
    required ClassicHareegScoreView scoreView,
  }) {
    if (!isRoundOver) {
      final snapshot = activeSnapshot;
      if (snapshot == null) {
        throw ArgumentError('Active-round persistence needs a snapshot.');
      }
      return ClassicHareegTablePersistencePlan(
        scenario: ClassicHareegTablePersistenceScenario.activeRound,
        action: ClassicHareegTablePersistenceAction.saveActiveMatch,
        snapshotToSave: snapshot,
        roundResultPresentation: null,
      );
    }

    final presentation = _roundResultPresentation(
      roundResult: roundResult,
      scoreView: scoreView,
      nextRoundSnapshot: nextRoundSnapshot,
    );
    final action = nextRoundSnapshot == null
        ? ClassicHareegTablePersistenceAction.abandonActiveMatch
        : ClassicHareegTablePersistenceAction.saveNextRound;
    final scenario = presentation == null
        ? ClassicHareegTablePersistenceScenario.roundCompleteMissingPresentation
        : nextRoundSnapshot == null
        ? ClassicHareegTablePersistenceScenario.matchComplete
        : ClassicHareegTablePersistenceScenario.roundCompleteWithNextRound;

    return ClassicHareegTablePersistencePlan(
      scenario: scenario,
      action: action,
      snapshotToSave: nextRoundSnapshot,
      roundResultPresentation: presentation,
    );
  }

  static ClassicHareegRoundResultPresentation? _roundResultPresentation({
    required RoundProgressResult? roundResult,
    required ClassicHareegScoreView scoreView,
    required ClassicHareegMatchSnapshot? nextRoundSnapshot,
  }) {
    final progress = scoreView.progress;
    if (roundResult == null || progress == null) {
      return null;
    }
    return ClassicHareegRoundResultPresentation(
      result: roundResult,
      progress: progress,
      previousScores: scoreView.previousScores,
      nextSnapshot: nextRoundSnapshot,
    );
  }
}
