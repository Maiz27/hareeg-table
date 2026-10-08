import 'dart:developer' as developer;

import '../models/classic_hareeg_setup.dart';
import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../rules/classic_hareeg_rules.dart';
import '../rules/cover_rules.dart';
import '../rules/fifty_rules.dart';
import '../rules/finish_rules.dart';
import '../rules/joker_rules.dart';
import '../rules/match_progression_rules.dart';
import '../rules/meld_candidate_search.dart';
import '../rules/meld_validator.dart';
import '../rules/mistake_preset_rules.dart';
import '../rules/opening_rules.dart';
import '../rules/strictness_rule_profile.dart';
import '../rules/turn_flow_rules.dart';
import '../reporting/match_diagnostic_event.dart';
import '../reporting/match_recorder.dart';
import 'classic_hareeg_action.dart';
import 'classic_hareeg_action_surface_planner.dart';
import 'classic_hareeg_discard_eligibility.dart';
import 'classic_hareeg_discard_history.dart';
import 'classic_hareeg_draw_decision_planner.dart';
import 'classic_hareeg_fifty_claim_planner.dart';
import 'classic_hareeg_finish_planner.dart';
import 'classic_hareeg_match_flow.dart';
import 'classic_hareeg_match_restoration.dart';
import 'classic_hareeg_match_snapshot.dart';
import 'round_seed_algorithm.dart';
import 'classic_hareeg_meld_play_eligibility.dart';
import 'classic_hareeg_mistake_consequence_planner.dart';
import 'classic_hareeg_round.dart';
import 'classic_hareeg_round_memory_recorder.dart';
import 'classic_hareeg_score_ledger.dart';
import 'classic_hareeg_table_play_planner.dart';
import 'classic_hareeg_table_play_retraction_planner.dart';
import 'classic_hareeg_turn_checkpoint.dart';
import 'classic_hareeg_turn_exit_planner.dart';
import 'classic_hareeg_turn_journal.dart';
import 'physical_card_match.dart';

export 'classic_hareeg_action.dart';

part 'classic_hareeg_action_application.dart';
part 'classic_hareeg_game_controller_action_surface.dart';
part 'classic_hareeg_game_controller_fifty.dart';
part 'classic_hareeg_game_controller_retraction.dart';
part 'classic_hareeg_game_controller_round_end.dart';
part 'classic_hareeg_game_controller_diagnostics.dart';

typedef _TurnMeldPlay = ClassicHareegTurnMeldPlay;
typedef _TurnCoverPlay = ClassicHareegTurnCoverPlay;

const _blockedFiftyClaimPlan = ClassicHareegFiftyClaimPlan(
  scenario: ClassicHareegFiftyClaimScenario.noWindow,
  shouldAdvertise: false,
  canApply: false,
  message: 'Only the immediate next player can claim Fifty.',
);

const _meldNoLongerOnTable = ApplyActionResult.failure(
  'That meld is no longer on table.',
);

/// Outcome of applying an action through the controller.
class ApplyActionResult {
  /// Creates an apply-action result.
  const ApplyActionResult({
    required this.isSuccess,
    required this.message,
    this.wasReverted = false,
    this.revertedCardId,
  });

  /// Successful result.
  const ApplyActionResult.success([this.message = ''])
    : isSuccess = true,
      wasReverted = false,
      revertedCardId = null;

  /// Strict-tier penalty result: the score was charged (and `message` carries
  /// the "+N" toast) but the action itself did not happen — the offending
  /// card is still in the seat's hand and the turn has not advanced. The UI
  /// uses [revertedCardId] to flash the wrong card.
  const ApplyActionResult.reverted({
    required this.message,
    required String this.revertedCardId,
  }) : isSuccess = true,
       wasReverted = true;

  /// Failed result with a player-facing explanation.
  const ApplyActionResult.failure(this.message)
    : isSuccess = false,
      wasReverted = false,
      revertedCardId = null;

  /// Whether the action was accepted and applied.
  final bool isSuccess;

  /// Player-facing explanation for blocked or rejected actions.
  final String message;

  /// True when the action was rejected after a penalty was applied (Strict
  /// tier mistakes). [isSuccess] is still true because side effects (the
  /// score change + toast) did happen.
  final bool wasReverted;

  /// Card id the seat tried to play when [wasReverted] is true. Lets the UI
  /// flash the card that should not have been discarded.
  final String? revertedCardId;
}

/// Live Classic Hareeg game state controller.
///
/// Owns the dealt round + turn-flow state and exposes the rules-engine seam
/// described in [ADR 0001](../../../docs/adr/0001-rules-engine-boundary.md).
/// The Flutter UI and CPU strategy both interact with the game exclusively
/// through [legalActionIdsFor] and [applyAction]; this is the single point at
/// which moves are validated against the rules engine.
class ClassicHareegGameController {
  static const _fiftyCueExpiryGraceSeconds = 2;

  /// Creates a controller from a dealt round.
  ClassicHareegGameController.fromRound(
    ClassicHareegRound round, {
    DateTime Function()? now,
    MatchRecorder? recorder,
  }) : _now = now ?? DateTime.now,
       _recorder = recorder,
       setup = round.setup,
       rules = round.rules,
       _hands = {
         for (final entry in round.hands.entries)
           entry.key: List<HareegCard>.of(entry.value),
       },
       _seed = round.seed,
       _roundSeedAlgorithm = RoundSeedAlgorithm.exact32,
       _stock = List<HareegCard>.of(round.stock),
       _discardPile = List<HareegCard>.of(round.discardPile),
       _tableMelds = {
         for (final seat in PlayerSeat.values) seat: <PlacedMeld>[],
       },
       _scores = {for (final seat in PlayerSeat.values) seat: 0},
       _activeSeats = List<PlayerSeat>.of(round.activeSeats),
       _openingState = OpeningState.initial(round.setup.openingRequirement),
       _roundNumber = 1,
       _removedSeats = <PlayerSeat>{},
       _seatEliminatedRound = <PlayerSeat, int>{},
       _starter = round.starter,
       _currentSeat = round.currentSeat,
       _phase = round.turnPhase,
       _pendingDiscard = null,
       _previousDiscardSeat = null,
       _fiftyWindow = null,
       _fiftyWindowOpenedAt = null,
       _roundOutcome = null,
       _roundResult = null,
       _discardHistory = DiscardHistory(),
       _turnJournal = ClassicHareegTurnJournal() {
    _syncUnlockedBenchmarkWithTable();
    _evaluateRoundEnd();
    _recorder?.captureInitialState(toSnapshot(savedAt: _now()));
  }

  /// Creates a controller restored from a persisted snapshot.
  factory ClassicHareegGameController.fromSnapshot(
    ClassicHareegMatchSnapshot snapshot, {
    ClassicHareegRules? rules,
    DateTime Function()? now,
    MatchRecorder? recorder,
  }) {
    final controller = ClassicHareegGameController._fromRestoredMatch(
      ClassicHareegMatchRestoration.fromSnapshot(snapshot, rules: rules),
      now: now,
      recorder: recorder,
    );
    final claim = controller._activeFiftyClaim;
    final script = claim?.script;
    if (claim != null && script != null) {
      // Persisted action encodings may be stale after an update. Validate the
      // whole suffix once through real rules, without mutating the restored
      // board or recording speculative actions. The private constructor does
      // not recurse through this validation.
      var valid = false;
      try {
        final probe = ClassicHareegGameController._fromRestoredMatch(
          ClassicHareegMatchRestoration.fromSnapshot(snapshot, rules: rules),
          now: controller._now,
        );
        valid = true;
        for (final action in script) {
          final result = probe.applyAction(action);
          if (!result.isSuccess || result.wasReverted) {
            valid = false;
            break;
          }
        }
        // The encoder always stores a complete suffix including the discard.
        // A legal but truncated plan is stale too; replan it from the board.
        valid =
            valid &&
            probe.roundResult?.type == RoundOutcomeType.fiftyFinish &&
            probe.roundResult?.winner == snapshot.currentSeat;
      } catch (_) {
        // A stale plan must not make an otherwise loadable board unusable.
        valid = false;
      }
      if (!valid) {
        claim
          ..script = null
          ..scriptIndex = 0;
      }
    }
    return controller;
  }

  ClassicHareegGameController._fromRestoredMatch(
    ClassicHareegRestoredMatchState restored, {
    DateTime Function()? now,
    MatchRecorder? recorder,
  }) : _now = now ?? DateTime.now,
       _recorder = recorder,
       setup = restored.setup,
       rules = restored.rules,
       _hands = restored.hands,
       _seed = restored.seed,
       _roundSeedAlgorithm = restored.roundSeedAlgorithm,
       _stock = restored.stock,
       _discardPile = restored.discardPile,
       _tableMelds = restored.tableMelds,
       _scores = restored.scores,
       _activeSeats = restored.activeSeats,
       _openingState = restored.openingState,
       _roundNumber = restored.roundNumber,
       _removedSeats = restored.removedSeats,
       _seatEliminatedRound = <PlayerSeat, int>{},
       _starter = restored.starter,
       _currentSeat = restored.currentSeat,
       _phase = restored.turnPhase,
       _pendingDiscard = restored.pendingDiscard,
       _previousDiscardSeat = restored.previousDiscardSeat,
       _lastReturnedPendingDiscard = restored.lastReturnedPendingDiscard,
       _fiftyWindow = restored.fiftyWindow,
       _fiftyWindowOpenedAt = restored.fiftyWindowOpenedAt,
       _roundOutcome = null,
       _roundResult = null,
       _discardHistory = restored.discardHistory,
       _turnJournal =
           restored.turnJournal?.restore() ??
           ClassicHareegTurnJournal(source: restored.turnSource) {
    final claimCardId = restored.activeFiftyClaimCardId;
    final claimDiscarder = restored.activeFiftyClaimDiscarder;
    if (claimCardId != null && claimDiscarder != null) {
      // Keep the committed proof suffix for exact saves. Older saves have no
      // script and re-plan lazily from their restored hand and table.
      _activeFiftyClaim = _ActiveFiftyClaim(
        claimedCardId: claimCardId,
        discarder: claimDiscarder,
        isFirstDealtRound: restored.activeFiftyClaimIsFirstDealtRound,
        script: restored.activeFiftyProofActions == null
            ? null
            : List.unmodifiable(restored.activeFiftyProofActions!),
      );
    }
    final windowedTakeCardId = restored.windowedTakeCardId;
    final windowedTakeDiscarder = restored.windowedTakeDiscarder;
    if (windowedTakeCardId != null && windowedTakeDiscarder != null) {
      // Resume the Fifty provenance of a plain windowed take so the finish
      // after restore still scores -3, not a normal -1.
      _windowedDiscardTake = _WindowedDiscardTake(
        cardId: windowedTakeCardId,
        discarder: windowedTakeDiscarder,
        isFirstDealtRound: restored.windowedTakeIsFirstDealtRound,
      );
    }
    _syncUnlockedBenchmarkWithTable();
    _evaluateRoundEnd();
    _concludeRoundIfHumanEliminated();
    _recorder?.captureInitialState(toSnapshot(savedAt: _now()));
  }

  /// Setup values used to deal the active round.
  final ClassicHareegSetup setup;

  /// Rules active for this round.
  final ClassicHareegRules rules;

  final DateTime Function() _now;

  /// Optional recorder fed the action transcript and diagnostic events at the
  /// [applyAction] seam. Null in tests and CPU-only harnesses that don't export
  /// reports, so recording adds zero overhead there.
  final MatchRecorder? _recorder;
  final Map<PlayerSeat, List<HareegCard>> _hands;
  final int? _seed;
  final RoundSeedAlgorithm _roundSeedAlgorithm;
  final List<HareegCard> _stock;
  final List<HareegCard> _discardPile;
  final Map<PlayerSeat, List<PlacedMeld>> _tableMelds;
  final Map<PlayerSeat, int> _scores;
  final List<PlayerSeat> _activeSeats;
  OpeningState _openingState;
  final int _roundNumber;
  final Set<PlayerSeat> _removedSeats;
  final Map<PlayerSeat, int> _seatEliminatedRound;
  final PlayerSeat _starter;
  PlayerSeat _currentSeat;
  TurnPhase _phase;
  HareegCard? _pendingDiscard;
  PlayerSeat? _previousDiscardSeat;
  // Tracks the (seat, cardId) of the most recent return-pending-discard. A
  // seat that just returned a card may not take it again on their next draw
  // — the rules engine would otherwise advertise take-discard for the same
  // card immediately, and a CPU planner would re-take it forever until the
  // safety cap fires. Cleared whenever the top of the discard pile changes.
  ({PlayerSeat seat, String cardId})? _lastReturnedPendingDiscard;
  FiftyClaimWindow? _fiftyWindow;
  DateTime? _fiftyWindowOpenedAt;
  _ActiveFiftyClaim? _activeFiftyClaim;
  // Provenance of a windowed discard the current seat took via plain
  // `take-discard` (not `claim-fifty`) while the Fifty window was still open.
  // If that same turn finishes using the taken card, the round is a Fifty —
  // identical to a claim — so this carries the discarder and the first-dealt-
  // round exception forward to the finish, which would otherwise score a plain
  // -1 normalFinish. Set on the windowed take, cleared on any other draw-phase
  // entry (draw-stock / claim-fifty / return) and when the turn advances.
  _WindowedDiscardTake? _windowedDiscardTake;
  RoundOutcomeType? _roundOutcome;
  RoundProgressResult? _roundResult;
  final DiscardHistory _discardHistory;
  final ClassicHareegTurnJournal _turnJournal;
  late final RoundMemoryRecorder _roundMemory =
      DiscardHistoryRoundMemoryRecorder(_discardHistory);
  late final ClassicHareegActionSurfaceFacts _actionSurfaceFacts =
      _LiveActionSurfaceFacts(this);
  // Memoised [_finishPlanWithPreviousDiscard] verdict (null plan = no finish),
  // valid while the cache key still describes the live state.
  String? _previousDiscardFinishCacheKey;
  ClassicHareegFinishPlan? _previousDiscardFinishPlanCacheValue;
  // Stock-exhaustion liveness backstop. Once stock is empty, the only cards
  // that can still leave a hand do so by being melded or covered onto the
  // table — taking and re-discarding the pile is net-zero. So the total card
  // count across active hands is monotonically non-increasing while stock is
  // empty. If a full rotation of active seats passes with no reduction in that
  // total, no seat can make progress toward a finish: the round is dead and
  // must be drawn. This guards against a seat that the finish detector believes
  // can finish (an optimistic pickup/Fifty finish) but that never actually
  // completes, taking and re-discarding the open window forever (a livelock the
  // CPU loop would otherwise re-enter indefinitely). Null until stock first
  // empties; reset whenever the active hand total drops (real progress).
  int? _stockExhaustionHandTotalBaseline;
  int _stockExhaustionNoProgressTurns = 0;

  // Set when the round was concluded by the stock-exhaustion liveness backstop
  // (a dead no-progress rotation forced a draw) rather than a normal draw or a
  // finish. The backstop only fires when the finish detector kept a round alive
  // believing a seat could finish while no seat ever completed it — so this flag
  // marks a detector/executor disagreement that the backstop merely masked. Test
  // harnesses read it to fail converging configs that should never need it; in
  // production it stays an invisible safety net. See [_evaluateRoundEnd].
  bool _roundEndedByLivelockBackstop = false;

  /// Seat that received 15 cards and starts in action phase.
  PlayerSeat get starter => _starter;

  /// Seat whose turn is active.
  PlayerSeat get currentSeat => _currentSeat;

  /// Current turn phase.
  TurnPhase get turnPhase => _phase;

  /// Pending discard awaiting use-or-return decision.
  HareegCard? get pendingDiscard => _pendingDiscard;

  /// Round outcome type, when the round has ended.
  RoundOutcomeType? get roundOutcome => _roundOutcome;

  /// Whether the active round has ended.
  bool get isRoundOver => _roundOutcome != null;

  /// Match scores the table should display now.
  Map<PlayerSeat, int> get scores => scoreView.currentScores;

  /// Score view that keeps completed-round baseline and current scores explicit.
  ClassicHareegScoreView get scoreView {
    return ClassicHareegScoreLedger.view(
      scores: _scores,
      progress: roundProgress,
    );
  }

  /// Seats still active in the match.
  List<PlayerSeat> get activeSeats => List.unmodifiable(_activeSeats);

  /// Seats removed from the current round (e.g. via Table tier penalty).
  /// They remain match-active but are out for this round.
  Set<PlayerSeat> get removedSeats => Set.unmodifiable(_removedSeats);

  /// Seats still playing this round (match-active minus round-removed).
  List<PlayerSeat> get roundActiveSeats => _roundActiveSeats;

  /// Opening benchmark state for the active round.
  OpeningState get openingState => _openingState;

  /// Read-only per-round discard memory for CPU strategy.
  DiscardHistoryView get discardHistory => _discardHistory;

  /// One-based dealt round number.
  int get roundNumber => _roundNumber;

  /// Seed used to shuffle the current dealt round, when known.
  int? get seed => _seed;

  /// Round number in which seats were eliminated during this controller's
  /// lifetime.
  Map<PlayerSeat, int> get seatEliminatedRound {
    return Map<PlayerSeat, int>.unmodifiable(_seatEliminatedRound);
  }

  /// Full round result once the round has ended.
  RoundProgressResult? get roundResult => _roundResult;

  /// Whether the just-completed round was forced to a draw by the
  /// stock-exhaustion liveness backstop (a dead no-progress rotation) rather
  /// than ending naturally. True only when the finish detector kept the round
  /// alive on a finish no seat ever realized — a detector/executor disagreement
  /// the backstop masked. Test harnesses assert this stays false for
  /// mistake-free (converging) configurations.
  bool get roundEndedByLivelockBackstop => _roundEndedByLivelockBackstop;

  /// Match progress produced by the completed round, if any.
  MatchProgressState? get roundProgress => _matchFlow.progressFor(_roundResult);

  /// Whether the human seat ([PlayerSeat.south]) has been eliminated from the
  /// match by score after the just-completed round.
  ///
  /// Returns true only when the active round has produced a result and that
  /// result drops south out of [MatchProgressState.activeSeats]. Watching CPUs
  /// finish the match without the human is pointless, so the table screen
  /// short-circuits to the match-over surface when this flips true.
  bool get isHumanEliminated {
    final progress = roundProgress;
    if (progress == null) {
      return false;
    }
    return !progress.activeSeats.contains(PlayerSeat.south);
  }

  ClassicHareegMatchFlow get _matchFlow {
    return ClassicHareegMatchFlow(
      setup: setup,
      rules: rules,
      scores: _scores,
      activeSeats: _activeSeats,
      currentStarter: _starter,
      roundNumber: _roundNumber,
      roundSeedAlgorithm: _roundSeedAlgorithm,
    );
  }

  ClassicHareegTablePlayPlanner get _tablePlayPlanner {
    return ClassicHareegTablePlayPlanner(
      currentSeat: _currentSeat,
      phase: _phase,
      pendingDiscard: _pendingDiscard,
      hands: _hands,
      tableMelds: _tableMelds,
      openingState: _openingState,
    );
  }

  List<PlacedMeld> get _turnFinishPlays => _turnJournal.finishMeldsView;

  List<PlacedMeld> get _turnOpeningMelds => _turnJournal.openingMeldsView;

  FinishCardSource get _turnSource => _turnJournal.source;

  /// Live card count for a seat.
  int cardCountFor(PlayerSeat seat) => _hands[seat]?.length ?? 0;

  /// Live read-only hand for a seat.
  List<HareegCard> handFor(PlayerSeat seat) {
    return List.unmodifiable(_hands[seat] ?? const []);
  }

  /// Live stock count.
  int get stockCount => _stock.length;

  /// Live top of discard pile, or null when empty.
  HareegCard? get topDiscard => _discardPile.isEmpty ? null : _discardPile.last;

  /// Live read-only discard pile, ordered from oldest to newest.
  List<HareegCard> get discardPile => List.unmodifiable(_discardPile);

  /// Live read-only table melds for a seat.
  List<PlacedMeld> tableMeldsFor(PlayerSeat seat) {
    return List.unmodifiable(_tableMelds[seat] ?? const []);
  }

  /// All table melds grouped by seat.
  Map<PlayerSeat, List<PlacedMeld>> get tableMelds {
    return Map<PlayerSeat, List<PlacedMeld>>.unmodifiable({
      for (final entry in _tableMelds.entries)
        entry.key: List<PlacedMeld>.unmodifiable(entry.value),
    });
  }

  /// Count of all melds currently on the table.
  int get tableMeldCount {
    return _tableMelds.values.fold<int>(0, (total, melds) {
      return total + melds.length;
    });
  }

  /// Seat eligible to claim Fifty during an open window, or null when no
  /// window is active.
  PlayerSeat? get fiftyClaimant => _fiftyWindow?.claimant;

  /// Clock reading stamped when the live Fifty window opened, or null when
  /// no window is active. Practice freezes its lesson clock relative to
  /// this instant so a teaching window can hold instead of expiring.
  DateTime? get fiftyWindowOpenedAt =>
      _fiftyWindow == null ? null : _fiftyWindowOpenedAt;

  /// Whether the current turn is a Fifty proof turn — the claimant took the
  /// thrown card and must lay the full finish down before the turn ends.
  bool get isFiftyProofTurn => _activeFiftyClaim != null;

  /// Physical id of the claimed card during a Fifty proof turn, or null.
  ///
  /// The claimed card must end the turn used in a meld or cover; discarding
  /// it is always refused.
  String? get fiftyProofClaimedCardId => _activeFiftyClaim?.claimedCardId;

  /// Seconds remaining in the Fifty claim window, or null when no window is
  /// open or the expired cue grace period has elapsed. Clamped to zero rather
  /// than going negative so the UI can render a stable timer ring during the
  /// moment of expiry.
  int? get fiftySecondsRemaining {
    final window = _fiftyWindow;
    if (window == null) {
      return null;
    }
    final elapsed = _fiftyElapsedSeconds();
    final remaining = setup.fiftyTimerSeconds - elapsed;
    if (remaining >= 0) {
      return remaining;
    }
    final graceElapsed = elapsed - setup.fiftyTimerSeconds;
    return graceElapsed <= _fiftyCueExpiryGraceSeconds ? 0 : null;
  }

  /// Snapshots the live game state for persistence.
  ClassicHareegMatchSnapshot toSnapshot({DateTime? savedAt}) {
    return _snapshot(savedAt: savedAt, exact: false);
  }

  /// Captures the visible position and reversible turn state together. Use for
  /// replay frames and recorded checkpoints; a rollback snapshot cannot be
  /// paired with a transcript that still contains the rolled-back actions.
  ClassicHareegMatchSnapshot toPositionSnapshot({DateTime? savedAt}) {
    return _snapshot(savedAt: savedAt, exact: true);
  }

  ClassicHareegMatchSnapshot _snapshot({
    DateTime? savedAt,
    required bool exact,
  }) {
    final effectiveSavedAt = savedAt ?? DateTime.now().toUtc();
    final resumeState = exact
        ? null
        : ClassicHareegTurnCheckpoint(
            currentSeat: _currentSeat,
            hands: _hands,
            tableMelds: _tableMelds,
            openingState: _openingState,
            pendingDiscard: _pendingDiscard,
            journalSnapshot: _turnJournal.toSnapshot(),
          ).toSnapshotState();
    return ClassicHareegMatchSnapshot(
      setup: setup,
      roundSeedAlgorithm: _roundSeedAlgorithm,
      hands:
          resumeState?.hands ??
          {
            for (final entry in _hands.entries)
              entry.key: List<HareegCard>.of(entry.value),
          },
      seed: _seed,
      stock: List<HareegCard>.of(_stock),
      discardPile: List<HareegCard>.of(_discardPile),
      tableMelds:
          resumeState?.tableMelds ??
          {
            for (final entry in _tableMelds.entries)
              entry.key: List<PlacedMeld>.of(entry.value),
          },
      starter: _starter,
      currentSeat: _currentSeat,
      turnPhase: _phase,
      pendingDiscard: exact ? _pendingDiscard : resumeState!.pendingDiscard,
      openingState: exact ? _openingState : resumeState!.openingState,
      turnJournal: exact ? _turnJournal.toSnapshot() : null,
      previousDiscardSeat: exact ? _previousDiscardSeat : null,
      discardNextSequence: exact ? _discardHistory.nextSequence : null,
      lastReturnedPendingDiscard: exact ? _lastReturnedPendingDiscard : null,
      // Persist the *displayed* scores (the round-result overlay folded in),
      // not the raw pre-round baseline. At round-over `_scores` still holds the
      // baseline and the round delta lives only in the `roundProgress` overlay;
      // saving the baseline would drop the just-scored round — e.g. a Fifty
      // bonus/penalty — on restore. `nextRoundSnapshot` already folds the same
      // progressed scores, so this keeps the two persistence paths in agreement.
      // Mid-round (no round result) `scoreView.currentScores` equals `_scores`.
      scores: Map<PlayerSeat, int>.of(scoreView.currentScores),
      activeSeats: List<PlayerSeat>.of(_activeSeats),
      roundNumber: _roundNumber,
      removedSeats: _removedSeats.toList(growable: false),
      fiftyWindowOpenedAt: _fiftyWindowOpenedAt,
      // Persist the open Fifty window's provenance verbatim so restore does
      // not have to geometrically guess the discarder (wrong once seats are
      // removed) or re-derive the first-dealt-round -1/-3 exception from the
      // round number (lost when roundNumber is absent on an old/partial save).
      fiftyWindowDiscarder: _fiftyWindow?.discarder,
      fiftyWindowIsFirstDealtRound: _fiftyWindow?.isFirstDealtRound,
      // Claim provenance survives both exact and rollback projections.
      // Only the exact board can retain the current proof suffix; attaching
      // it to a rolled-back hand would skip plays that still need applying.
      activeFiftyClaimCardId: _activeFiftyClaim?.claimedCardId,
      activeFiftyClaimDiscarder: _activeFiftyClaim?.discarder,
      activeFiftyClaimIsFirstDealtRound: _activeFiftyClaim?.isFirstDealtRound,
      activeFiftyProofActions: exact
          ? _activeFiftyClaim?.remainingActions
          : null,
      // A plain windowed take-discard mid-turn is persistent Fifty provenance:
      // the checkpoint reverts the turn's plays and the taken card lands back as
      // the pending discard, so these let restore re-tag the finish as a Fifty
      // (instead of a normal -1) when the resumed turn closes on that card.
      windowedTakeCardId: _windowedDiscardTake?.cardId,
      windowedTakeDiscarder: _windowedDiscardTake?.discarder,
      windowedTakeIsFirstDealtRound: _windowedDiscardTake?.isFirstDealtRound,
      savedAt: effectiveSavedAt,
      discardHistoryEvents: _discardHistory.events.toList(growable: false),
    );
  }

  /// Deals the next round snapshot after this round has produced progress.
  ClassicHareegMatchSnapshot? nextRoundSnapshot({DateTime? savedAt}) {
    return _matchFlow.nextRoundSnapshotFor(
      roundResult: _roundResult,
      savedAt: savedAt,
    );
  }

  ClassicHareegActionSurfacePlan _actionSurfacePlanFor(
    PlayerSeat seat,
    ClassicHareegActionSurfacePurpose purpose, {
    bool logSearches = false,
  }) {
    return ClassicHareegActionSurfacePlanner.evaluate(
      purpose: purpose,
      seat: seat,
      isRoundOver: _roundOutcome != null,
      isSeatTurn: seat == _currentSeat,
      isSeatActive: _roundActiveSeats.contains(seat),
      phase: _phase,
      pendingDiscardId: _pendingDiscard?.id,
      facts: logSearches
          ? _LoggingActionSurfaceFacts(_actionSurfaceFacts)
          : _actionSurfaceFacts,
    );
  }

  /// Returns the legal action ids for [seat] under the current state.
  ///
  /// Empty when the round has ended, when it is not the seat's turn, or when
  /// the seat has no legal action remaining (e.g. stock exhaustion that the
  /// controller has not yet converted to a [RoundOutcomeType.draw] outcome).
  List<String> legalActionIdsFor(PlayerSeat seat) {
    return _actionSurfacePlanFor(
      seat,
      ClassicHareegActionSurfacePurpose.full,
    ).actionIds;
  }

  /// Returns a bounded legal action surface for CPU turns.
  ///
  /// [legalActionIdsFor] intentionally exposes every legal table play for
  /// rules tests and rich UI affordances. CPU turns only need one candidate
  /// per high-value category, plus discard fallbacks. Keeping this list small
  /// avoids combinatorial meld/opening enumeration blocking the UI isolate.
  List<String> cpuActionIdsFor(PlayerSeat seat) {
    final totalWatch = Stopwatch()..start();
    _debugRulesLog(
      'cpuActionIdsFor start '
      'seat=${seat.name} phase=$_phase pending=${_pendingDiscard?.label} '
      'hand=${cardCountFor(seat)} stock=${_stock.length} '
      'discard=${_discardPile.length} tableMelds=$tableMeldCount',
    );

    List<String> finish(String reason, List<String> ids) {
      totalWatch.stop();
      _debugRulesLog(
        'cpuActionIdsFor end seat=${seat.name} reason=$reason '
        'elapsed=${totalWatch.elapsedMilliseconds}ms count=${ids.length} '
        'actions=${_debugActionSummary(ids)}',
      );
      return List.unmodifiable(ids);
    }

    // An active Fifty claim is proven by replaying the validated finish plan
    // step by step through the normal apply flow, so CPU claims play their
    // proof out visibly at normal pacing. Falls through to the regular
    // surface when no plan resolves (a wrong claim on a permissive tier —
    // the only exits there are tier-priced plain discards).
    final proofStep = _fiftyProofScriptActionFor(seat);
    if (proofStep != null) {
      return finish('fifty-proof', [proofStep]);
    }

    final plan = _actionSurfacePlanFor(
      seat,
      ClassicHareegActionSurfacePurpose.cpu,
      logSearches: true,
    );
    // Strip mistake-class action ids (`discard-blocked-cover:*`, plus the
    // joker discard prefix) when the strictness rules out CPU mistakes. The
    // discard eligibility planner advertises these for any tier where the
    // mistake `isAllowed` so humans can opt in to a paid mistake; for the
    // CPU surface that advertisement is a leak. Without this filter the
    // runner observes a `discard-blocked-cover:<card>` as legal, applies it,
    // the controller reverts the action (Strict tier: penalty applied, card
    // stays in hand, turn does NOT advance), then the runner re-polls the
    // same surface and the planner picks the same id again — burning the
    // safety cap on consecutive penalties. The same shape exists for any
    // future mistake-class id we add.
    var ids = plan.actionIds;
    var reason = plan.reason;

    if (!setup.tableStrictness.cpuMistakesAllowed) {
      final filtered = [
        for (final id in ids)
          if (!ClassicHareegActionIds.describe(id).isMistake) id,
      ];
      if (filtered.length != ids.length) {
        ids = filtered;
        reason = '$reason+nomistake';
      }
    }

    // A CPU must never be offered a Fifty claim it cannot validly finish. On
    // mistake-allowing tiers (Strict/Table) the claim is advertised so a human
    // can opt into a paid wrong-claim, but for the CPU it is a guaranteed
    // self-penalty — and on Table tier a self-removal. `claim-fifty` is not a
    // static mistake-class id (its mistake-ness depends on the hand), so the
    // filter above cannot catch it; resolve the actual claim and strip it
    // unless it backs a real finish.
    if (ids.contains(ClassicHareegActionIds.claimFifty) &&
        _fiftyClaimPlanFor(
              seat,
              purpose: ClassicHareegFiftyClaimPurpose.apply,
            ).finishPlan ==
            null) {
      ids = [
        for (final id in ids)
          if (id != ClassicHareegActionIds.claimFifty) id,
      ];
      reason = '$reason+nofiftymistake';
    }

    return finish(reason, ids);
  }

  /// Returns only the cheap table-control actions needed by the human UI.
  ///
  /// Meld, cover, and joker-replacement actions are validated from the current
  /// selection when the user invokes them, so the frame build does not need to
  /// enumerate every possible table play.
  List<String> controlActionIdsFor(PlayerSeat seat) {
    return _actionSurfacePlanFor(
      seat,
      ClassicHareegActionSurfacePurpose.control,
    ).actionIds;
  }

  /// Applies an action through the rules engine.
  ///
  /// Returns [ApplyActionResult.success] when the action was legal and applied.
  /// Returns [ApplyActionResult.failure] when the action id is unknown or the
  /// action is illegal under the current rule state.
  ApplyActionResult applyAction(String actionId) {
    final recorder = _recorder;
    if (recorder == null) {
      return _ClassicHareegActionApplication(this).apply(actionId);
    }

    // Capture the pre-action context so diagnostic events report the acting
    // seat/phase/round and so state transitions can be diffed after applying.
    final seat = _currentSeat;
    final phase = _phase;
    final round = _roundNumber;
    final scoresBefore = Map<PlayerSeat, int>.of(scores);
    final wasRoundOver = isRoundOver;
    final claimantBefore = fiftyClaimant;
    final removedBefore = Set<PlayerSeat>.of(_removedSeats);

    final result = _ClassicHareegActionApplication(this).apply(actionId);

    _recordDiagnostics(
      recorder: recorder,
      actionId: actionId,
      seat: seat,
      phase: phase,
      round: round,
      result: result,
      scoresBefore: scoresBefore,
      wasRoundOver: wasRoundOver,
      claimantBefore: claimantBefore,
      removedBefore: removedBefore,
    );

    if (result.isSuccess && !result.wasReverted) {
      recorder.recordAction(
        seat: seat,
        roundNumber: round,
        phase: phase,
        actionId: actionId,
      );
    }
    return result;
  }

  /// Validates selected hand cards as one meld, not as a full table-play
  /// partition. UI meld pickers use this so selected cards do not advertise
  /// additional opening bundles from the rest of the hand.
  MeldValidationResult singleMeldValidationFor(
    PlayerSeat seat,
    List<String> cardIds,
  ) {
    return _tablePlayPlanner.singleMeldValidationFor(seat, cardIds);
  }

  /// Returns the exact action id for selected cards as one meld, including
  /// an explicit represented identity when the selection contains an
  /// otherwise ambiguous joker.
  String? selectedMeldActionIdFor(PlayerSeat seat, List<String> cardIds) {
    return _tablePlayPlanner.selectedMeldActionIdFor(seat, cardIds);
  }

  /// Returns playable single-meld suggestions for a hand selection.
  ///
  /// UI pickers consume the returned list directly. The combinatorial subset
  /// enumeration lives inside the rules engine per ADR-0001 so the UI does
  /// not rediscover legal melds itself.
  List<ClassicHareegMeldSuggestion> meldSuggestionsForSelection(
    PlayerSeat seat,
    List<String> selectedCardIds, {
    int limit = 5,
  }) {
    return _tablePlayPlanner.meldSuggestionsForSelection(
      seat,
      selectedCardIds,
      limit: limit,
    );
  }

  /// Returns explicit represented-card choices needed for an ambiguous joker.
  List<CardIdentity> jokerRepresentationOptionsFor(
    PlayerSeat seat,
    List<String> cardIds,
  ) {
    return _tablePlayPlanner.jokerRepresentationOptionsFor(seat, cardIds);
  }

  /// Returns explicit represented-joker choices for selected meld cards.
  List<JokerMeldActionChoice> jokerMeldChoicesFor(
    PlayerSeat seat,
    List<String> cardIds,
  ) {
    return _tablePlayPlanner.jokerMeldChoicesFor(seat, cardIds);
  }

  /// Returns a legal cover action id for [cardIds], if they can extend a meld.
  String? coverActionIdFor(PlayerSeat seat, List<String> cardIds) {
    return _tablePlayPlanner.coverActionIdFor(seat, cardIds);
  }

  /// Returns a legal cover action id for a specific table meld target.
  String? coverActionIdForMeldTarget({
    required PlayerSeat seat,
    required List<String> cardIds,
    required PlayerSeat targetSeat,
    required int meldIndex,
    CoverPlacement? coverPlacement,
  }) {
    return _tablePlayPlanner.coverActionIdForMeldTarget(
      seat: seat,
      cardIds: cardIds,
      targetSeat: targetSeat,
      meldIndex: meldIndex,
      coverPlacement: coverPlacement,
    );
  }

  /// Returns a joker replacement action id for one selected real card.
  String? jokerReplacementActionIdFor(PlayerSeat seat, List<String> cardIds) {
    return _tablePlayPlanner.jokerReplacementActionIdFor(seat, cardIds);
  }

  /// Returns a legal joker replacement action id for a specific table meld.
  String? jokerReplacementActionIdForMeldTarget({
    required PlayerSeat seat,
    required List<String> cardIds,
    required PlayerSeat targetSeat,
    required int meldIndex,
  }) {
    return _tablePlayPlanner.jokerReplacementActionIdForMeldTarget(
      seat: seat,
      cardIds: cardIds,
      targetSeat: targetSeat,
      meldIndex: meldIndex,
    );
  }

  ApplyActionResult _applyDrawStock() {
    final next = ClassicHareegTurnFlowRules.drawStock(_turnFlowState());
    _applyTurnFlowState(next);
    _windowedDiscardTake = null;
    _fiftyWindow = null;
    _fiftyWindowOpenedAt = null;
    // Do NOT reset the turn journal here: the journal resets at turn exits
    // (discard advance, removal, round end), so any recorded plays belong to
    // THIS turn — a seat that placed table plays, returned its taken discard,
    // and now draws from stock keeps those plays reversible and
    // finish-eligible. Only the finish source changes.
    _turnJournal.setSource(FinishCardSource.stock);
    return const ApplyActionResult.success();
  }

  ApplyActionResult _applyTakePreviousDiscard() {
    final next = ClassicHareegTurnFlowRules.takePreviousDiscard(
      _turnFlowState(),
    );
    final takenCard = next.pendingDiscard?.card;
    _applyTurnFlowState(next);
    if (takenCard != null) {
      _roundMemory.onTakePreviousDiscard(_currentSeat, takenCard);
    }
    // If the seat took the windowed discard while the Fifty window was still
    // open, finishing on it this turn is a Fifty — record its provenance so the
    // final discard scores fiftyFinish (-3) instead of a normal -1. The window's
    // discardedCard is the pile top, which is exactly the card take-discard
    // lifts, so an open, unexpired window owned by this seat means the taken
    // card IS the windowed one.
    final window = _fiftyWindow;
    _windowedDiscardTake =
        window != null &&
            window.claimant == _currentSeat &&
            !window.isExpired(_fiftyElapsedSeconds())
        ? _WindowedDiscardTake(
            cardId: window.discardedCard.id,
            discarder: window.discarder,
            isFirstDealtRound: window.isFirstDealtRound,
          )
        : null;
    _fiftyWindow = null;
    _fiftyWindowOpenedAt = null;
    // See _applyDrawStock: the journal is turn-scoped and resets at turn
    // exits, not on draw decisions.
    _turnJournal.setSource(FinishCardSource.previousDiscard);
    return const ApplyActionResult.success();
  }

  ApplyActionResult _applyUsePendingDiscard() {
    return const ApplyActionResult.failure(
      'The picked up discard must be used in a meld or cover.',
    );
  }

  /// Whether the unused pending discard may be returned right now.
  ///
  /// Opened seats may return the unused taken card at any point of the turn,
  /// even after other committed plays. Unopened seats must take back staged
  /// opening melds first — those plays are not valid commitments yet, so the
  /// taken card cannot be returned around them.
  bool _canReturnPendingDiscard(PlayerSeat seat) {
    if (_pendingDiscard == null || seat != _currentSeat) {
      return false;
    }
    // During a Fifty proof turn, returning the claimed card is the explicit
    // "give up" gesture (priced by the tier's wrong-Fifty consequence), so it
    // stays available instead of being blocked — that block is what left a
    // doomed claimant stuck with a card they could neither prove nor return.
    if (_activeFiftyClaim != null &&
        !_mistakeConsequencePlanFor(MistakeType.wrongFiftyClaim).canApply) {
      return false;
    }
    // Same precondition on every tier, including a Fifty give-up: an unopened
    // seat must take staged opening melds back first so the return never
    // strands sub-requirement melds on the table (Table removal does not
    // clean them up).
    return _openingState.hasOpened(seat) || _turnOpeningMelds.isEmpty;
  }

  ApplyActionResult _applyReturnPendingDiscard() {
    final pending = _pendingDiscard;
    final returningSeat = _currentSeat;
    if (_activeFiftyClaim != null) {
      // Returning the claimed card during a Fifty proof turn is the explicit
      // "give up" gesture. It carries the tier's wrong-Fifty consequence —
      // Table: +17 and out of the round; Strict: +3 and the claim is called
      // off — so a claimant who picked up an unprovable Fifty always has a
      // discoverable exit instead of being stuck with a card they cannot
      // return. (Coaching/Standard block the wrong claim at claim time, so no
      // proof turn exists for them to give up.)
      return _giveUpFiftyProofByReturn(
        returningSeat: returningSeat,
        pending: pending,
      );
    }
    // An unopened seat's staged table plays are not valid commitments yet, so
    // the taken card cannot be returned around them — the staged melds must
    // be taken back first. Opened seats may return the unused taken card even
    // after other committed plays this turn (relaxed taken-discard rule).
    if (pending != null &&
        !_openingState.hasOpened(returningSeat) &&
        _turnOpeningMelds.isNotEmpty) {
      return const ApplyActionResult.failure(
        'Take back your staged melds before returning the taken card.',
      );
    }
    return _returnPendingDiscardToPile(
          returningSeat: returningSeat,
          pending: pending,
        ) ??
        const ApplyActionResult.success();
  }

  /// Hands the pending discard back to the pile and drops [returningSeat]
  /// into its draw decision. Returns a failure when the turn flow refuses the
  /// return, or null once the return has been applied.
  ApplyActionResult? _returnPendingDiscardToPile({
    required PlayerSeat returningSeat,
    required HareegCard? pending,
  }) {
    try {
      final next = ClassicHareegTurnFlowRules.returnPendingDiscard(
        _turnFlowState(),
      );
      _applyTurnFlowState(next);
    } on StateError catch (error) {
      return ApplyActionResult.failure(error.message);
    }
    if (pending != null) {
      _roundMemory.onReturnPendingDiscard(returningSeat, pending);
      _lastReturnedPendingDiscard = (seat: returningSeat, cardId: pending.id);
    }
    // The taken card went back to the pile, so it can no longer carry a Fifty.
    _windowedDiscardTake = null;
    _fiftyWindow = null;
    _fiftyWindowOpenedAt = null;
    // Keep the journal: plays committed earlier this turn stay reversible and
    // finish-eligible across the return → draw continuation of the same turn.
    // The returned card was never consumed, so only the source resets.
    _turnJournal
      ..clearConsumedPendingDiscard()
      ..setSource(FinishCardSource.stock);
    _evaluateRoundEnd();
    return null;
  }

  ApplyActionResult _applyPlayMeld(
    List<String> cardIds, {
    String? jokerId,
    CardIdentity? jokerIdentity,
    Map<String, CardIdentity>? jokerIdentities,
  }) {
    if (_phase != TurnPhase.action) {
      return const ApplyActionResult.failure('Draw before playing a meld.');
    }
    if (cardIds.length < 3) {
      return const ApplyActionResult.failure(
        'Select at least three cards for a meld.',
      );
    }

    final uniqueIds = <String>{};
    for (final id in cardIds) {
      if (!uniqueIds.add(id)) {
        return const ApplyActionResult.failure(
          'A meld cannot use the same card twice.',
        );
      }
    }

    final hand = _handFor(_currentSeat);
    final selectedCards = <HareegCard>[];
    for (final id in cardIds) {
      final index = hand.indexWhere((card) => card.id == id);
      if (index == -1) {
        return ApplyActionResult.failure('Card "$id" is not in the hand.');
      }
      selectedCards.add(hand[index]);
    }

    final pending = _pendingDiscard;

    final resolved = ClassicHareegTablePlayPlanner.resolveTablePlay(
      selectedCards,
      jokerId: jokerId,
      jokerIdentity: jokerIdentity,
      jokerIdentities: jokerIdentities,
    );
    if (!resolved.result.isValid) {
      return ApplyActionResult.failure(resolved.result.message);
    }

    final alreadyOpened = _openingState.hasOpened(_currentSeat);
    final eligibility = _meldPlayEligibilityFor(
      seat: _currentSeat,
      handCount: hand.length,
      playedCardIds: uniqueIds,
      melds: resolved.melds,
    );
    if (!eligibility.isAllowed) {
      return ApplyActionResult.failure(eligibility.message);
    }
    var message = eligibility.message;

    for (final id in uniqueIds) {
      hand.removeWhere((card) => card.id == id);
    }
    _tableMelds
        .putIfAbsent(_currentSeat, () => <PlacedMeld>[])
        .addAll(resolved.melds);
    _turnJournal.recordFinishMelds(resolved.melds);

    if (alreadyOpened) {
      final value = resolved.melds.fold<int>(
        0,
        (total, meld) => total + meld.valueSnapshot,
      );
      _turnJournal.recordTurnMelds([
        for (final meld in resolved.melds)
          _TurnMeldPlay(
            owner: _currentSeat,
            meld: meld,
            consumedPendingDiscard:
                pending != null &&
                    meld.cards.any((card) => card.id == pending.id)
                ? pending
                : null,
          ),
      ]);
      _openingState = ClassicHareegOpeningRules.recordBenchmarkContribution(
        state: _openingState,
        seat: _currentSeat,
        value: value,
      );
      _syncUnlockedBenchmarkWithTable();
    } else {
      _turnJournal.recordOpeningMelds(resolved.melds);
      if (eligibility.opensPlayer) {
        _openingState = ClassicHareegOpeningRules.applyOpening(
          state: _openingState,
          seat: _currentSeat,
          melds: _turnJournal.openingMeldsView,
        );
        _turnJournal.commitOpeningMelds();
        _syncUnlockedBenchmarkWithTable();
      }
    }

    // Relaxed taken-discard rule: the pending card is consumed only by the
    // play that actually uses it; unrelated melds leave it pending.
    if (pending != null && uniqueIds.contains(pending.id)) {
      _consumePendingDiscard();
      if (!alreadyOpened && !_openingState.hasOpened(_currentSeat)) {
        _turnJournal.recordConsumedPendingDiscard(pending);
      }
    }
    return ApplyActionResult.success(message);
  }

  /// Returns whether a specific placed meld is one of this turn's reversible
  /// table plays.
  bool canReturnTablePlayFromMeld(PlayerSeat owner, int meldIndex) {
    return _targetTablePlayRetractionPlan(
      ReturnTablePlayTarget(owner: owner, meldIndex: meldIndex),
    ).shouldAdvertise;
  }

  ApplyActionResult _applyPlaceCover(CoverActionTarget target) {
    if (_phase != TurnPhase.action) {
      return const ApplyActionResult.failure('Draw before placing a cover.');
    }
    if (target.cardIds.isEmpty) {
      return const ApplyActionResult.failure('Select a cover card.');
    }
    if (!ClassicHareegCoverRules.canPlayCover(
      playerOpened: _openingState.hasOpened(_currentSeat),
    )) {
      return const ApplyActionResult.failure(
        'Open before placing covers on table melds.',
      );
    }

    final selectedCards = _cardsFromHand(_currentSeat, target.cardIds);
    if (selectedCards == null) {
      return const ApplyActionResult.failure(
        'One or more selected cards are not in the hand.',
      );
    }
    final resolvedSelectedCards =
        ClassicHareegTablePlayPlanner.resolveCoverCardsWithJokerIdentities(
          cards: selectedCards,
          jokerIdentities: target.jokerIdentities,
        );
    if (resolvedSelectedCards == null) {
      return const ApplyActionResult.failure(
        'Selected joker identity does not match this cover.',
      );
    }

    // Relaxed taken-discard rule: covers that do not use the pending card are
    // legal; the pending card is consumed only by the cover that includes it.
    final pending = _pendingDiscard;
    final usesPending =
        pending != null && target.cardIds.toSet().contains(pending.id);

    final targetMelds = _tableMeldsAt(target.targetSeat, target.meldIndex);
    if (targetMelds == null) {
      return _meldNoLongerOnTable;
    }

    final targetMeld = targetMelds[target.meldIndex];
    final ordered = ClassicHareegCoverRules.orderedCoverCards(
      tableMeld: targetMeld.cards,
      candidates: resolvedSelectedCards,
    );
    if (ordered == null) {
      return const ApplyActionResult.failure(
        'Selected cards do not extend that meld.',
      );
    }
    if (_handFor(_currentSeat).length - ordered.length == 0) {
      return const ApplyActionResult.failure(
        'A finish needs one final discard.',
      );
    }

    final hand = _handFor(_currentSeat);
    final previousOpeningState = _openingState;
    final consumedPendingDiscard = usesPending ? pending : null;
    for (final card in ordered) {
      hand.removeWhere((candidate) => candidate.id == card.id);
    }
    targetMelds[target.meldIndex] = targetMeld.addCoverCards(ordered);
    final coverValue = ordered.fold<int>(0, (total, card) {
      return total + (card.effectiveIdentity?.rank.value ?? 0);
    });
    final coverMeld = PlacedMeld(
      cards: List.unmodifiable(ordered),
      valueSnapshot: coverValue,
    );
    _turnJournal.recordFinishMelds([coverMeld]);
    _openingState = ClassicHareegOpeningRules.recordBenchmarkContribution(
      state: _openingState,
      seat: _currentSeat,
      value: coverValue,
    );
    _syncUnlockedBenchmarkWithTable();
    _turnJournal.recordCoverPlay(
      _TurnCoverPlay(
        targetSeat: target.targetSeat,
        meldIndex: target.meldIndex,
        previousMeld: targetMeld,
        coverMeld: coverMeld,
        previousOpeningState: previousOpeningState,
        consumedPendingDiscard: consumedPendingDiscard,
      ),
    );
    if (usesPending) {
      _consumePendingDiscard();
      _turnJournal.clearConsumedPendingDiscard();
    }
    return const ApplyActionResult.success('Cover placed.');
  }

  void _syncUnlockedBenchmarkWithTable({bool allowLower = false}) {
    final synced = ClassicHareegTurnCheckpoint.openingStateSyncedWith(
      openingState: _openingState,
      tableMelds: _tableMelds,
      allowLower: allowLower,
    );
    if (identical(synced, _openingState)) {
      return;
    }
    _openingState = synced;
  }

  ApplyActionResult _applyReplaceJoker(JokerReplacementActionTarget target) {
    if (_phase != TurnPhase.action) {
      return const ApplyActionResult.failure('Draw before replacing a joker.');
    }

    final hand = _handFor(_currentSeat);
    final replacementIndex = hand.indexWhere(
      (card) => card.id == target.cardId,
    );
    if (replacementIndex == -1) {
      return const ApplyActionResult.failure(
        'Replacement card is not in the hand.',
      );
    }

    // Relaxed taken-discard rule: any hand card may replace a table joker;
    // the pending card is consumed only when it is the replacement itself.
    final pending = _pendingDiscard;
    final usesPending = pending != null && pending.id == target.cardId;

    final targetMelds = _tableMeldsAt(target.targetSeat, target.meldIndex);
    if (targetMelds == null) {
      return _meldNoLongerOnTable;
    }

    final replacementCard = hand[replacementIndex];
    final targetMeld = targetMelds[target.meldIndex];
    if (!ClassicHareegJokerRules.canReplaceJoker(
      playerOpened: _openingState.hasOpened(_currentSeat),
      tableCards: targetMeld.cards,
      replacementCard: replacementCard,
    )) {
      final mistake = _mistakeConsequencePlanFor(
        MistakeType.wrongJokerReplacement,
      );
      if (!mistake.canApply) {
        return const ApplyActionResult.failure(
          'That card cannot replace a table joker.',
        );
      }
      final removal = _applyMistake(mistake);
      return removal ?? ApplyActionResult.success(mistake.message);
    }

    final replacement = ClassicHareegJokerRules.replaceJoker(
      playerOpened: true,
      tableCards: targetMeld.cards,
      replacementCard: replacementCard,
    );
    hand.removeAt(replacementIndex);
    hand.add(replacement.freedJoker);
    targetMelds[target.meldIndex] = PlacedMeld(
      cards: replacement.tableCards,
      valueSnapshot: targetMeld.valueSnapshot,
      coverValue: targetMeld.coverValue,
    );
    if (usesPending) {
      _consumePendingDiscard();
      _turnJournal.clearConsumedPendingDiscard();
    }
    return const ApplyActionResult.success('Joker replaced.');
  }

  ApplyActionResult _applyDiscard(String cardId) {
    final hand = _handFor(_currentSeat);
    var index = hand.indexWhere((card) => card.id == cardId);
    if (index == -1) {
      return ApplyActionResult.failure('Card "$cardId" is not in the hand.');
    }

    final card = hand[index];
    final isFinalDiscard = hand.length == 1;

    final claim = _activeFiftyClaim;
    var fiftyProofComplete = false;
    var fiftyExitMessage = '';
    if (claim != null) {
      final exit = _applyFiftyProofExitGate(
        claim: claim,
        hand: hand,
        card: card,
        isFinalDiscard: isFinalDiscard,
      );
      switch (exit) {
        case _FiftyProofExitRefused(:final result):
          return result;
        case _FiftyProofExitRemoved(:final result):
          return result;
        case _FiftyProofExitPenalized(:final message):
          // Strict tier: the penalty is charged and the turn ends normally
          // with this discard. The gate may have returned the unused claimed
          // card to the pile, shifting hand indices.
          fiftyExitMessage = message;
          index = hand.indexWhere((candidate) => candidate.id == cardId);
        case _FiftyProofExitProven():
          fiftyProofComplete = true;
      }
    } else {
      // Relaxed taken-discard rule: the pending card may be used at any point
      // of the turn, but the turn cannot end while it sits unused — and the
      // taken card itself can never leave as the turn's closing discard.
      final pending = _pendingDiscard;
      if (pending != null) {
        if (card.id == pending.id) {
          return const ApplyActionResult.failure(
            'The taken card cannot be discarded — use it in a meld or cover.',
          );
        }
        return const ApplyActionResult.failure(
          'Use or return the taken card before ending the turn.',
        );
      }
    }

    final eligibility = _discardEligibilityFor(
      seat: _currentSeat,
      card: card,
      isFinalDiscard: isFinalDiscard,
    );
    if (!eligibility.isAllowed) {
      return ApplyActionResult.failure(eligibility.message);
    }
    final mistake = eligibility.mistakeResolution;
    var successMessage = fiftyExitMessage;
    if (mistake != null && mistake.isAllowed) {
      // Capture the penalty message so the feedback chip surfaces "+3 / +17"
      // when the cover discard goes through as a strict / table mistake.
      successMessage = mistake.message;
      final discardingSeat = _currentSeat;
      final removal = _applyMistake(_mistakeConsequencePlan(mistake));
      if (removal != null) {
        // Table tier removed the player. The card still has to land on the
        // discard pile — the seat is out but the card has left their hand.
        _landDiscardOfRemovedSeat(discardingSeat, card);
        return removal;
      }
      if (mistake.revertsAction) {
        // Strict tier: penalty applied to the score (via _applyMistake) but
        // the card stays in hand and the turn does NOT advance. The UI
        // shows the "+3" toast and flashes the offending card so the human
        // can pick a legal discard instead.
        return ApplyActionResult.reverted(
          message: successMessage,
          revertedCardId: card.id,
        );
      }
    }

    if (isFinalDiscard) {
      final finish = _validateTurnFinish(card);
      if (!finish.isValid) {
        return ApplyActionResult.failure(finish.message);
      }
    }

    hand.removeAt(index);
    _discardPile.add(card);
    _roundMemory.onDiscard(_currentSeat, card);
    _previousDiscardSeat = _currentSeat;
    _pendingDiscard = null;
    _turnJournal.clearConsumedPendingDiscard();
    // A new card now sits on top of the discard pile, so the previous
    // return-pending-discard memory no longer matters.
    _lastReturnedPendingDiscard = null;
    // A plain take-discard of the windowed card that now finishes the round is a
    // Fifty too — the rules score on whether the finishing card came from the
    // previous player's discard within the window, not on which button was used.
    // (The taken card can never be the closing discard, so reaching a valid
    // finish means it was melded; the explicit check guards the retract-then-
    // discard edge where it left the finishing melds.)
    final windowedTake = _windowedDiscardTake;
    final windowedFiftyFinish =
        fiftyProofComplete == false &&
        isFinalDiscard &&
        windowedTake != null &&
        _turnSource == FinishCardSource.previousDiscard &&
        _turnFinishPlays.any(
          (meld) => meld.cards.any((c) => c.id == windowedTake.cardId),
        );
    if (fiftyProofComplete || windowedFiftyFinish) {
      // Either the claimant proved a claimed Fifty, or a windowed take-discard
      // finished on the thrown card: both end the round as a Fifty.
      final fiftyDiscarder = claim?.discarder ?? windowedTake!.discarder;
      final firstRound =
          claim?.isFirstDealtRound ?? windowedTake!.isFirstDealtRound;
      if (fiftyProofComplete &&
          (_recorder?.hasRecordedFiftyClaim(_currentSeat, _roundNumber) ??
              false)) {
        _recorder?.recordFiftySuccess(_currentSeat);
      }
      _activeFiftyClaim = null;
      _windowedDiscardTake = null;
      _fiftyWindow = null;
      _fiftyWindowOpenedAt = null;
      _finishRound(
        type: RoundOutcomeType.fiftyFinish,
        winner: _currentSeat,
        fiftyDiscarder: fiftyDiscarder,
        firstRoundFiftyException: firstRound,
      );
      return ApplyActionResult.success(
        fiftyProofComplete ? 'Fifty proven.' : 'Fifty.',
      );
    }
    _activeFiftyClaim = null;
    _windowedDiscardTake = null;
    final exit = ClassicHareegTurnExitPlanner.afterDiscard(
      discarder: _currentSeat,
      discardedCard: card,
      isFinalDiscard: isFinalDiscard,
      activeSeats: _activeSeats,
      removedSeats: _removedSeats,
      roundNumber: _roundNumber,
      fiftyTimerSeconds: setup.fiftyTimerSeconds,
      remainingCardCounts: _remainingCardCounts(),
    );
    _fiftyWindow = exit.fiftyWindow;
    _fiftyWindowOpenedAt = _now();
    final result = exit.roundResult;
    if (result != null) {
      _completeRound(result);
    } else {
      _currentSeat = exit.nextSeat!;
      _phase = exit.nextPhase!;
      _turnJournal.resetForNewTurn();
      _evaluateRoundEnd();
    }
    return ApplyActionResult.success(successMessage);
  }

  /// Validates this turn's plays plus [finalDiscard] as the current seat's
  /// finish.
  FinishValidationResult _validateTurnFinish(HareegCard finalDiscard) {
    return ClassicHareegFinishRules.validateFinish(
      playedMelds: _turnFinishPlays,
      finalDiscard: finalDiscard,
      playerOpened: _openingState.hasOpened(_currentSeat),
      source: _turnSource,
      perfectHandAttempt: !_openingState.hasOpened(_currentSeat),
    );
  }

  /// Moves [card] from [seat]'s hand onto the discard pile after a Table-tier
  /// mistake removed [seat] — the seat is out, but the card has left its hand.
  void _landDiscardOfRemovedSeat(PlayerSeat seat, HareegCard card) {
    _handFor(seat).removeWhere((candidate) => candidate.id == card.id);
    _discardPile.add(card);
    _roundMemory.onDiscard(seat, card);
    _previousDiscardSeat = seat;
    _lastReturnedPendingDiscard = null;
  }

  List<HareegCard> _handFor(PlayerSeat seat) {
    return _hands.putIfAbsent(seat, () => <HareegCard>[]);
  }

  /// [owner]'s live table melds, or null when [meldIndex] no longer addresses
  /// one of them.
  List<PlacedMeld>? _tableMeldsAt(PlayerSeat owner, int meldIndex) {
    final melds = _tableMelds[owner];
    if (melds == null || meldIndex < 0 || meldIndex >= melds.length) {
      return null;
    }
    return melds;
  }

  /// Takes [cards] back from the table into the current seat's hand, clearing
  /// any joker's represented identity.
  void _returnCardsToHand(Iterable<HareegCard> cards) {
    final hand = _handFor(_currentSeat);
    for (final card in cards) {
      hand.add(card.isJoker ? card.withoutRepresentation() : card);
    }
  }

  ClassicTurnFlowState _turnFlowState() {
    final pending = _pendingDiscard;
    final previousDiscardSeat =
        _previousDiscardSeat ??
        (pending == null ? null : _currentSeat.previousAntiClockwise);
    return ClassicTurnFlowState(
      currentSeat: _currentSeat,
      phase: _classicTurnPhaseFrom(_phase),
      hand: List.unmodifiable(_handFor(_currentSeat)),
      stock: List.unmodifiable(_stock),
      discardPile: List.unmodifiable(_discardPile),
      previousDiscardSeat: previousDiscardSeat,
      pendingDiscard: pending == null
          ? null
          : PendingDiscard(card: pending, fromSeat: previousDiscardSeat!),
      activeSeats: List.unmodifiable(_activeSeats),
      removedSeats: Set.unmodifiable(_removedSeats),
    );
  }

  void _applyTurnFlowState(ClassicTurnFlowState state) {
    _hands[state.currentSeat] = List<HareegCard>.of(state.hand);
    _stock
      ..clear()
      ..addAll(state.stock);
    _discardPile
      ..clear()
      ..addAll(state.discardPile);
    _phase = _turnPhaseFrom(state.phase);
    _pendingDiscard = state.pendingDiscard?.card;
    _previousDiscardSeat = state.previousDiscardSeat;
  }

  void _consumePendingDiscard() {
    if (_pendingDiscard == null) {
      return;
    }
    _applyTurnFlowState(
      ClassicHareegTurnFlowRules.usePendingDiscard(_turnFlowState()),
    );
  }

  List<HareegCard>? _cardsFromHand(PlayerSeat seat, List<String> cardIds) {
    final uniqueIds = <String>{};
    for (final id in cardIds) {
      if (!uniqueIds.add(id)) {
        return null;
      }
    }

    final hand = _handFor(seat);
    final cards = <HareegCard>[];
    for (final id in cardIds) {
      final index = hand.indexWhere((card) => card.id == id);
      if (index == -1) {
        return null;
      }
      cards.add(hand[index]);
    }
    return cards;
  }

  ClassicHareegDrawDecisionPlan _drawDecisionPlanFor(PlayerSeat seat) {
    final isSeatTurn = seat == _currentSeat;
    final isSeatActive = _roundActiveSeats.contains(seat);
    final shouldResolveDrawFacts =
        _roundOutcome == null &&
        isSeatTurn &&
        isSeatActive &&
        _pendingDiscard == null &&
        _phase == TurnPhase.draw;
    final canTakePreviousDiscard = shouldResolveDrawFacts
        ? _canTakePreviousDiscard
        : false;
    final pickupWouldFinish =
        shouldResolveDrawFacts && _stock.isEmpty && canTakePreviousDiscard
        ? _canFinishWithPreviousDiscard(seat)
        : false;
    final fiftyClaimPlan = shouldResolveDrawFacts
        ? _fiftyClaimPlanFor(
            seat,
            purpose: ClassicHareegFiftyClaimPurpose.advertise,
          )
        : _blockedFiftyClaimPlan;

    return ClassicHareegDrawDecisionPlanner.evaluate(
      isRoundOver: _roundOutcome != null,
      isSeatTurn: isSeatTurn,
      isSeatActive: isSeatActive,
      phase: _phase,
      hasPendingDiscard: _pendingDiscard != null,
      stockIsEmpty: _stock.isEmpty,
      canTakePreviousDiscard: canTakePreviousDiscard,
      pickupWouldFinish: pickupWouldFinish,
      fiftyClaimPlan: fiftyClaimPlan,
    );
  }

  bool get _canTakePreviousDiscard {
    final base = ClassicHareegTurnExitPlanner.canTakePreviousDiscard(
      currentSeat: _currentSeat,
      phase: _phase,
      previousDiscardSeat: _previousDiscardSeat,
      discardPileIsNotEmpty: _discardPile.isNotEmpty,
      activeSeats: _activeSeats,
      removedSeats: _removedSeats,
    );
    if (!base) return false;
    final lastReturned = _lastReturnedPendingDiscard;
    if (lastReturned != null &&
        lastReturned.seat == _currentSeat &&
        _discardPile.isNotEmpty &&
        _discardPile.last.id == lastReturned.cardId) {
      return false;
    }
    return true;
  }

  List<PlayerSeat> get _roundActiveSeats {
    return ClassicHareegTurnExitPlanner.roundActiveSeats(
      activeSeats: _activeSeats,
      removedSeats: _removedSeats,
    );
  }

  List<List<HareegCard>> get _tableMeldCardLists {
    return [
      for (final melds in _tableMelds.values)
        for (final meld in melds) meld.cards,
    ];
  }

  ClassicHareegMeldPlayEligibility _meldPlayEligibilityFor({
    required PlayerSeat seat,
    required int handCount,
    required Set<String> playedCardIds,
    required List<PlacedMeld> melds,
  }) {
    return ClassicHareegMeldPlayEligibilityPlanner.evaluate(
      openingState: _openingState,
      seat: seat,
      stagedOpeningMelds: _turnOpeningMelds,
      playedMelds: melds,
      handCount: handCount,
      playedCardIds: playedCardIds,
    );
  }

  ClassicHareegDiscardEligibility _discardEligibilityFor({
    required PlayerSeat seat,
    required HareegCard card,
    required bool isFinalDiscard,
  }) {
    return ClassicHareegDiscardEligibilityPlanner.evaluate(
      strictness: setup.tableStrictness,
      tableMelds: _tableMeldCardLists,
      card: card,
      isFinalDiscard: isFinalDiscard,
      // Use the card-level predicate so the block applies even before the
      // seat has opened. _replacementActionIdForCardId only surfaces when
      // the seat can actually perform the replace action (post-open) and
      // would let a pre-opening seat silently throw a card that should be
      // forced into a joker swap.
      blocksJokerReplacement:
          !isFinalDiscard && _tablePlayPlanner.cardBlockedByTableJoker(card),
    );
  }
}

ClassicTurnPhase _classicTurnPhaseFrom(TurnPhase phase) {
  return switch (phase) {
    TurnPhase.draw => ClassicTurnPhase.draw,
    TurnPhase.action => ClassicTurnPhase.action,
  };
}

TurnPhase _turnPhaseFrom(ClassicTurnPhase phase) {
  return switch (phase) {
    ClassicTurnPhase.draw => TurnPhase.draw,
    ClassicTurnPhase.action => TurnPhase.action,
  };
}
