import 'package:hareeg_table/cpu/classic_hareeg/cpu_observation.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_strategy.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';

import 'classic_hareeg_scenario.dart';

/// Why a full-match driver run stopped.
enum MatchStopReason {
  /// A round produced a match winner — the natural end of a match.
  matchWinner,

  /// The driver hit its per-match action cap before a winner emerged. Not a
  /// hard correctness failure: weak CPUs can draw rounds indefinitely. The
  /// correctness invariants still hold up to the cap; liveness is asserted
  /// separately, only for configurations expected to converge.
  actionLimit,

  /// The driver hit its per-match round cap before a winner emerged.
  roundLimit,

  /// A live (non-removed) seat had no legal CPU actions while the round was
  /// still open, even after a Fifty window was expired. A real anomaly: the
  /// action surface stranded a seat mid-round.
  stuckNoLegalActions,
}

/// One applied action within a driven match, captured *after* the action with
/// cheap live counts (no per-step snapshot, which would dominate runtime).
class MatchStep {
  /// Creates a driven match step.
  const MatchStep({
    required this.roundNumber,
    required this.actionIndex,
    required this.seat,
    required this.phase,
    required this.actionId,
    required this.legalActionIds,
    required this.handCounts,
    required this.stockCount,
    required this.discardCount,
    required this.meldCardCount,
    required this.removedSeats,
    required this.scores,
    required this.roundEndedAfter,
  });

  /// One-based dealt round this action belonged to.
  final int roundNumber;

  /// One-based index of this action within the whole match.
  final int actionIndex;

  /// Seat that acted.
  final PlayerSeat seat;

  /// Turn phase before the action was applied.
  final TurnPhase phase;

  /// Action id that was applied.
  final String actionId;

  /// Legal CPU action ids offered to the seat for this decision.
  final List<String> legalActionIds;

  /// Hand size per seat after the action.
  final Map<PlayerSeat, int> handCounts;

  /// Stock size after the action.
  final int stockCount;

  /// Discard-pile size after the action. A pending (taken) discard stays on
  /// the pile, so this count already includes it.
  final int discardCount;

  /// Total cards across all table melds after the action.
  final int meldCardCount;

  /// Seats removed from the round after the action.
  final Set<PlayerSeat> removedSeats;

  /// Persisted match scores after the action.
  final Map<PlayerSeat, int> scores;

  /// Whether this action ended the round. On the round-ending action the
  /// displayed scores legitimately flip to the round result, so the
  /// scores-stable-within-round invariant exempts this step.
  final bool roundEndedAfter;

  /// Total physical cards accounted for at this step.
  int get totalCards =>
      handCounts.values.fold(0, (a, b) => a + b) +
      stockCount +
      discardCount +
      meldCardCount;
}

/// Result of a single completed round inside a driven match.
class DrivenRoundReport {
  /// Creates a driven round report.
  const DrivenRoundReport({
    required this.roundNumber,
    required this.result,
    required this.progress,
    required this.scoresBefore,
    required this.scoresAfter,
    required this.snapshotAtRoundOver,
  });

  /// One-based dealt round number.
  final int roundNumber;

  /// Round result produced by the controller.
  final RoundProgressResult? result;

  /// Match progress produced by applying [result].
  final MatchProgressState? progress;

  /// Persisted match scores at the moment the round started (baseline).
  final Map<PlayerSeat, int> scoresBefore;

  /// Displayed match scores after the round result was applied.
  final Map<PlayerSeat, int> scoresAfter;

  /// Full game state captured once the round ended — the surface for
  /// per-round identity (multiset) conservation.
  final ClassicHareegMatchSnapshot snapshotAtRoundOver;
}

/// Final report for a driven match.
class MatchRunReport {
  /// Creates a match run report.
  const MatchRunReport({
    required this.stopReason,
    required this.winner,
    required this.rounds,
    required this.totalActions,
    required this.setup,
    required this.seed,
  });

  /// Why the driver stopped.
  final MatchStopReason stopReason;

  /// Match winner, when [stopReason] is [MatchStopReason.matchWinner].
  final PlayerSeat? winner;

  /// Per-round reports in play order.
  final List<DrivenRoundReport> rounds;

  /// Total actions applied across the whole match.
  final int totalActions;

  /// Setup the match was driven with.
  final ClassicHareegSetup setup;

  /// Seed the opening round was dealt with.
  final int seed;

  /// Whether the match ended naturally with a single winner.
  bool get endedNaturally => stopReason == MatchStopReason.matchWinner;
}

/// Per-action observer; invoked after every applied action.
typedef MatchStepObserver = void Function(MatchStep step);

/// Per-round observer; invoked when each round ends, before the next deal.
typedef MatchRoundObserver = void Function(DrivenRoundReport report);

/// Plays a complete Classic Hareeg *match* — every seat driven by the real
/// production CPU strategy — deterministically from a seed and setup, advancing
/// round to round until a winner emerges or a safety cap fires.
///
/// See the file-level rationale in the sweep test. Determinism comes from the
/// seeded deal, pure CPU planners, and an injected clock. All seats are driven
/// through `cpuActionIdsFor` (mistake-class actions excluded), so a driven
/// match is always a fully legal game.
///
/// Fifty windows: a synchronous driver has no wall clock, but a CPU that
/// declines a hopeless Fifty claim relies on the window expiring in real time.
/// When the strategy declines (its planner returns no choice) and a Fifty
/// window is open for the seat, the driver advances its clock past the timer
/// and re-polls — faithfully modelling the app's watchdog-driven expiry instead
/// of deadlocking.
class ClassicHareegMatchDriver {
  /// Creates a match driver.
  ClassicHareegMatchDriver({
    this.strategy = const ClassicHareegCpuStrategy(),
    this.actionLimit = 2500,
    this.roundLimit = 60,
    DateTime? clockStart,
    Duration clockStep = const Duration(seconds: 1),
  }) : _initialClock = clockStart ?? DateTime.utc(2026, 1, 1),
       _clockStep = clockStep;

  /// CPU strategy used for every seat.
  final CpuStrategy strategy;

  /// Maximum actions before stopping with [MatchStopReason.actionLimit].
  final int actionLimit;

  /// Maximum rounds before stopping with [MatchStopReason.roundLimit].
  final int roundLimit;

  final Duration _clockStep;

  /// Clock the constructor was configured with; [run] resets [_clock] to this
  /// before each match so the same driver instance replays identically when
  /// reused across runs (rather than carrying the previous run's advanced time).
  final DateTime _initialClock;
  late DateTime _clock;

  /// Returns the current clock *without* advancing it. The clock is stable
  /// within a single decision step so the legal surface and the applied action
  /// observe the same instant — otherwise a short Fifty window could open when
  /// the surface is computed and expire by the time the action is applied. Time
  /// advances explicitly between steps via [_tick].
  DateTime _now() => _clock;

  void _tick() {
    _clock = _clock.add(_clockStep);
  }

  /// Drives a complete match from a fresh seeded deal.
  MatchRunReport run({
    required ClassicHareegSetup setup,
    int seed = 7,
    MatchStepObserver? onStep,
    MatchRoundObserver? onRoundEnd,
  }) {
    // Reset the clock so a reused driver instance replays identically.
    _clock = _initialClock;
    var controller = ClassicHareegScenario.deal(
      setup: setup,
      seed: seed,
      now: _now,
    ).controller;

    final rounds = <DrivenRoundReport>[];
    var totalActions = 0;
    var roundCount = 0;

    while (true) {
      if (roundCount >= roundLimit) {
        return _report(MatchStopReason.roundLimit, null, rounds, totalActions,
            setup, seed);
      }
      roundCount += 1;

      final scoresBefore = Map<PlayerSeat, int>.of(controller.scores);

      while (!controller.isRoundOver) {
        final seat = controller.currentSeat;
        var legalActionIds = controller.cpuActionIdsFor(seat);
        if (legalActionIds.isEmpty) {
          return _report(MatchStopReason.stuckNoLegalActions, null, rounds,
              totalActions, setup, seed);
        }

        var intent = _tryChoose(controller, seat, legalActionIds);
        if (intent == null) {
          // The strategy declined every legal action — in practice a hopeless
          // Fifty claim being the only option. Model wall-clock expiry of the
          // Fifty window and re-poll once.
          if (controller.fiftyClaimant != seat) {
            _throwNoChoice(controller, seat, legalActionIds);
          }
          _expireFiftyWindow(controller);
          legalActionIds = controller.cpuActionIdsFor(seat);
          if (legalActionIds.isEmpty) {
            return _report(MatchStopReason.stuckNoLegalActions, null, rounds,
                totalActions, setup, seed);
          }
          intent = _tryChoose(controller, seat, legalActionIds);
          if (intent == null) {
            _throwNoChoice(controller, seat, legalActionIds);
          }
        }

        final phaseBefore = controller.turnPhase;
        final result = controller.applyAction(intent.actionId);
        if (!result.isSuccess) {
          throw StateError(
            'Driver: CPU strategy returned an illegal action.\n'
            '  seat=${seat.name} action=${intent.actionId}\n'
            '  message=${result.message}\n  legal=$legalActionIds',
          );
        }
        if (result.wasReverted) {
          throw StateError(
            'Driver: action ${intent.actionId} was reverted with a mistake '
            'penalty — cpuActionIdsFor must never surface mistake-class ids. '
            'seat=${seat.name} message=${result.message}',
          );
        }

        totalActions += 1;
        if (onStep != null) {
          onStep(_captureStep(controller, seat, phaseBefore, intent.actionId,
              legalActionIds, totalActions));
        }
        if (totalActions >= actionLimit) {
          return _report(MatchStopReason.actionLimit, null, rounds,
              totalActions, setup, seed);
        }
        // Advance the clock once per applied action so Fifty windows age across
        // turns and eventually expire when no one claims.
        _tick();
      }

      final report = DrivenRoundReport(
        roundNumber: controller.roundNumber,
        result: controller.roundResult,
        progress: controller.roundProgress,
        scoresBefore: scoresBefore,
        scoresAfter: Map<PlayerSeat, int>.of(controller.scores),
        snapshotAtRoundOver: controller.toSnapshot(savedAt: _now()),
      );
      rounds.add(report);
      onRoundEnd?.call(report);

      final next = controller.nextRoundSnapshot(savedAt: _now());
      if (next == null) {
        return _report(MatchStopReason.matchWinner,
            controller.roundProgress?.matchWinner, rounds, totalActions, setup,
            seed);
      }
      controller = ClassicHareegGameController.fromSnapshot(next, now: _now);
    }
  }

  /// Asks the strategy for a move, returning null when its planner declines
  /// every legal action (the "needs at least one legal action" path).
  CpuMoveIntent? _tryChoose(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    List<String> legalActionIds,
  ) {
    try {
      return strategy.chooseMove(
        CpuTurnSnapshot(
          seat: seat,
          legalActionIds: legalActionIds,
          difficulty: controller.setup.cpuDifficulty,
        ),
        observation: LiveCpuObservation(
          controller: controller,
          seat: seat,
          legalActionIds: legalActionIds,
          difficulty: controller.setup.cpuDifficulty,
        ),
      );
    } on StateError catch (error) {
      // Only the planner's "no choice" decline (a hopeless claim-fifty being
      // the lone option) is treated as a decline; any other StateError — e.g. a
      // planner misuse like "requires a CpuObservation" — is a real bug and
      // must surface rather than be silently absorbed as a Fifty decline.
      if (error.message.contains('at least one legal action')) {
        return null;
      }
      rethrow;
    }
  }

  void _expireFiftyWindow(ClassicHareegGameController controller) {
    // Jump the clock well past the timer so the next surface read sees the
    // window expired and drops claim-fifty in favour of the normal draw
    // options (or a stock-exhaustion round end).
    _clock = _clock.add(
      Duration(seconds: controller.setup.fiftyTimerSeconds + 30),
    );
  }

  Never _throwNoChoice(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    List<String> legalActionIds,
  ) {
    throw StateError(
      'Driver: CPU planner returned no choice from a non-empty legal surface '
      'and it was not a resolvable Fifty window.\n'
      '  seat=${seat.name} phase=${controller.turnPhase.name} '
      'difficulty=${controller.setup.cpuDifficulty.name} '
      'strictness=${controller.setup.tableStrictness.name}\n'
      '  legal=$legalActionIds\n'
      '  fiftyClaimant=${controller.fiftyClaimant?.name} '
      'pendingDiscard=${controller.pendingDiscard?.id} '
      'topDiscard=${controller.topDiscard?.id} stock=${controller.stockCount}',
    );
  }

  MatchStep _captureStep(
    ClassicHareegGameController controller,
    PlayerSeat seat,
    TurnPhase phaseBefore,
    String actionId,
    List<String> legalActionIds,
    int actionIndex,
  ) {
    var meldCards = 0;
    for (final s in PlayerSeat.values) {
      for (final meld in controller.tableMeldsFor(s)) {
        meldCards += meld.cards.length;
      }
    }
    return MatchStep(
      roundNumber: controller.roundNumber,
      actionIndex: actionIndex,
      seat: seat,
      phase: phaseBefore,
      actionId: actionId,
      legalActionIds: legalActionIds,
      handCounts: {
        for (final s in PlayerSeat.values) s: controller.cardCountFor(s),
      },
      stockCount: controller.stockCount,
      discardCount: controller.discardPile.length,
      meldCardCount: meldCards,
      removedSeats: controller.removedSeats,
      scores: Map<PlayerSeat, int>.of(controller.scores),
      roundEndedAfter: controller.isRoundOver,
    );
  }

  MatchRunReport _report(
    MatchStopReason reason,
    PlayerSeat? winner,
    List<DrivenRoundReport> rounds,
    int totalActions,
    ClassicHareegSetup setup,
    int seed,
  ) {
    return MatchRunReport(
      stopReason: reason,
      winner: winner,
      rounds: List.unmodifiable(rounds),
      totalActions: totalActions,
      setup: setup,
      seed: seed,
    );
  }
}
