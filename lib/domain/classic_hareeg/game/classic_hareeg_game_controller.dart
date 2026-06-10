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

typedef _TurnMeldPlay = ClassicHareegTurnMeldPlay;
typedef _TurnCoverPlay = ClassicHareegTurnCoverPlay;

const _blockedFiftyClaimPlan = ClassicHareegFiftyClaimPlan(
  scenario: ClassicHareegFiftyClaimScenario.noWindow,
  shouldAdvertise: false,
  canApply: false,
  message: 'Only the immediate next player can claim Fifty.',
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
    return ClassicHareegGameController._fromRestoredMatch(
      ClassicHareegMatchRestoration.fromSnapshot(snapshot, rules: rules),
      now: now,
      recorder: recorder,
    );
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
       _fiftyWindow = restored.fiftyWindow,
       _fiftyWindowOpenedAt = restored.fiftyWindowOpenedAt,
       _roundOutcome = null,
       _roundResult = null,
       _discardHistory = restored.discardHistory,
       _turnJournal = ClassicHareegTurnJournal(source: restored.turnSource) {
    final claimCardId = restored.activeFiftyClaimCardId;
    final claimDiscarder = restored.activeFiftyClaimDiscarder;
    if (claimCardId != null && claimDiscarder != null) {
      // Resume the saved Fifty proof turn. The CPU script rebuilds lazily
      // from the restored hand + table when the surface is next polled.
      _activeFiftyClaim = _ActiveFiftyClaim(
        claimedCardId: claimCardId,
        discarder: claimDiscarder,
        isFirstDealtRound: restored.activeFiftyClaimIsFirstDealtRound,
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
  String? _previousDiscardFinishCacheKey;
  bool? _previousDiscardFinishCacheValue;
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
    final effectiveSavedAt = savedAt ?? DateTime.now().toUtc();
    final resumeState = ClassicHareegTurnCheckpoint(
      currentSeat: _currentSeat,
      hands: _hands,
      tableMelds: _tableMelds,
      openingState: _openingState,
      pendingDiscard: _pendingDiscard,
      journalSnapshot: _turnJournal.toSnapshot(),
    ).toSnapshotState();
    return ClassicHareegMatchSnapshot(
      setup: setup,
      hands: resumeState.hands,
      seed: _seed,
      stock: List<HareegCard>.of(_stock),
      discardPile: List<HareegCard>.of(_discardPile),
      tableMelds: resumeState.tableMelds,
      starter: _starter,
      currentSeat: _currentSeat,
      turnPhase: _phase,
      pendingDiscard: resumeState.pendingDiscard,
      openingState: resumeState.openingState,
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
      // A mid-proof Fifty claim is persistent turn state: the checkpoint
      // reverts the proof's table plays (the claimed card lands back in the
      // hand as the pending discard) and these fields let restore resume the
      // proof turn — never a live window, which stays restore-gated to draw
      // phase with its ancient-stamp fallback.
      activeFiftyClaimCardId: _activeFiftyClaim?.claimedCardId,
      activeFiftyClaimDiscarder: _activeFiftyClaim?.discarder,
      activeFiftyClaimIsFirstDealtRound: _activeFiftyClaim?.isFirstDealtRound,
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

  /// Emits the notable diagnostic events for one applied action.
  ///
  /// Only meaningful transitions are logged — illegal actions, penalty reverts,
  /// scoring changes, Fifty window/claim transitions, round finishes, and
  /// notable CPU decisions — so the capped log stays focused on the context
  /// around a reported problem rather than every routine draw and discard
  /// (those live in the full transcript instead).
  void _recordDiagnostics({
    required MatchRecorder recorder,
    required String actionId,
    required PlayerSeat seat,
    required TurnPhase phase,
    required int round,
    required ApplyActionResult result,
    required Map<PlayerSeat, int> scoresBefore,
    required bool wasRoundOver,
    required PlayerSeat? claimantBefore,
    required Set<PlayerSeat> removedBefore,
  }) {
    final log = recorder.diagnostics;
    final descriptor = ClassicHareegActionIds.describe(actionId);
    final isCpu = seat != PlayerSeat.south;

    if (!result.isSuccess) {
      log.record(
        category: MatchDiagnosticCategory.rules,
        type: 'invalidAction',
        roundNumber: round,
        seat: seat,
        phase: phase,
        data: {
          'actionId': actionId,
          'kind': descriptor.kind.name,
          'message': result.message,
        },
      );
      return;
    }

    if (result.wasReverted) {
      log.record(
        category: MatchDiagnosticCategory.rules,
        type: 'penaltyReverted',
        roundNumber: round,
        seat: seat,
        phase: phase,
        data: {
          'actionId': actionId,
          'kind': descriptor.kind.name,
          if (result.revertedCardId != null)
            'revertedCardId': result.revertedCardId,
          'message': result.message,
        },
      );
    }

    final scoresAfter = scores;
    if (!_scoresEqual(scoresBefore, scoresAfter)) {
      log.record(
        category: MatchDiagnosticCategory.scoring,
        type: 'scoresChanged',
        roundNumber: round,
        seat: seat,
        phase: phase,
        data: {
          'before': {
            for (final entry in scoresBefore.entries) entry.key.name: entry.value,
          },
          'after': {
            for (final entry in scoresAfter.entries) entry.key.name: entry.value,
          },
        },
      );
    }

    final newlyRemoved = _removedSeats.difference(removedBefore);
    if (newlyRemoved.isNotEmpty) {
      log.record(
        category: MatchDiagnosticCategory.rules,
        type: 'seatRemoved',
        roundNumber: round,
        seat: seat,
        phase: phase,
        data: {
          'removed': [for (final s in newlyRemoved) s.name],
        },
      );
    }

    final claimantAfter = fiftyClaimant;
    if (claimantBefore != claimantAfter) {
      log.record(
        category: MatchDiagnosticCategory.fifty,
        type: claimantAfter != null ? 'fiftyWindowOpened' : 'fiftyWindowClosed',
        roundNumber: round,
        seat: seat,
        phase: phase,
        data: {
          if (claimantAfter != null) 'claimant': claimantAfter.name,
        },
      );
    }

    if (descriptor.kind == ClassicHareegActionKind.claimFifty) {
      log.record(
        category: MatchDiagnosticCategory.fifty,
        type: 'fiftyClaimed',
        roundNumber: round,
        seat: seat,
        phase: phase,
      );
    }

    final roundJustEnded = !wasRoundOver && isRoundOver;
    if (roundJustEnded) {
      final outcome = _roundResult;
      log.record(
        category: MatchDiagnosticCategory.finish,
        type: 'roundEnded',
        roundNumber: round,
        seat: seat,
        phase: phase,
        data: {
          if (roundOutcome != null) 'outcome': roundOutcome!.name,
          if (outcome?.winner != null) 'winner': outcome!.winner!.name,
        },
      );
    }

    if (isCpu &&
        (descriptor.kind == ClassicHareegActionKind.claimFifty ||
            roundJustEnded)) {
      log.record(
        category: MatchDiagnosticCategory.ai,
        type: 'cpuDecision',
        roundNumber: round,
        seat: seat,
        phase: phase,
        data: {
          'actionId': actionId,
          'kind': descriptor.kind.name,
          'difficulty': setup.cpuDifficulty.name,
        },
      );
    }
  }

  static bool _scoresEqual(Map<PlayerSeat, int> a, Map<PlayerSeat, int> b) {
    for (final seat in PlayerSeat.values) {
      if ((a[seat] ?? 0) != (b[seat] ?? 0)) {
        return false;
      }
    }
    return true;
  }

  /// Plays [cardIds] from [seat]'s hand as one validated table meld.
  ApplyActionResult playMeldFor(PlayerSeat seat, List<String> cardIds) {
    if (seat != _currentSeat) {
      return const ApplyActionResult.failure('It is not this seat\'s turn.');
    }
    return _applyPlayMeld(cardIds);
  }

  /// Validates selected hand cards as a playable meld, resolving an obvious
  /// single-joker representation when only one identity makes the meld legal.
  MeldValidationResult meldValidationFor(
    PlayerSeat seat,
    List<String> cardIds,
  ) {
    return _tablePlayPlanner.meldValidationFor(seat, cardIds);
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

  /// Sorts the seat's hand by suit and rank. Pure UI ergonomics; does not
  /// affect any rule decision.
  void sortHandFor(PlayerSeat seat) {
    final hand = _hands[seat];
    if (hand == null) {
      return;
    }
    hand.sort(_compareCards);
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
    // A claimed Fifty card cannot be returned: the claimant is committed to
    // the proof, and abandoning it is priced at the turn exit instead.
    if (_activeFiftyClaim != null) {
      return false;
    }
    return _openingState.hasOpened(seat) || _turnOpeningMelds.isEmpty;
  }

  ApplyActionResult _applyReturnPendingDiscard() {
    final pending = _pendingDiscard;
    final returningSeat = _currentSeat;
    if (_activeFiftyClaim != null) {
      return const ApplyActionResult.failure(
        'The claimed card cannot be returned — prove the Fifty or end the '
        'turn.',
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
    return const ApplyActionResult.success();
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

    final resolved = _resolveTablePlay(
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

  ClassicHareegTablePlayRetractionPlan _tablePlayRetractionPlanFor(
    PlayerSeat seat,
  ) {
    return ClassicHareegTablePlayRetractionPlanner.evaluateAll(
      seat: seat,
      currentSeat: _currentSeat,
      phase: _phase,
      strictness: setup.tableStrictness,
      openingState: _openingState,
      journal: _turnJournal,
    );
  }

  ClassicHareegTablePlayRetractionPlan _targetTablePlayRetractionPlan(
    ReturnTablePlayTarget target,
  ) {
    return ClassicHareegTablePlayRetractionPlanner.evaluateTarget(
      seat: _currentSeat,
      currentSeat: _currentSeat,
      phase: _phase,
      strictness: setup.tableStrictness,
      openingState: _openingState,
      journal: _turnJournal,
      tableMelds: _tableMelds,
      target: target,
    );
  }

  ApplyActionResult _applyReturnOpeningMelds() {
    final plan = _tablePlayRetractionPlanFor(_currentSeat);
    if (!plan.isAllowed) {
      return ApplyActionResult.failure(plan.message);
    }

    final stagedMelds = List<PlacedMeld>.of(plan.openingMelds);
    final turnMeldPlays = List<_TurnMeldPlay>.of(plan.meldPlays);
    final coverPlays = List<_TurnCoverPlay>.of(plan.coverPlays);
    if (stagedMelds.isNotEmpty) {
      final tableMelds = _tableMelds[_currentSeat] ?? <PlacedMeld>[];
      for (final staged in stagedMelds.reversed) {
        final index = tableMelds.lastIndexWhere((meld) {
          return samePhysicalCards(meld.cards, staged.cards);
        });
        if (index != -1) {
          tableMelds.removeAt(index);
        }
      }
    }
    if (turnMeldPlays.isNotEmpty) {
      final tableMelds = _tableMelds[_currentSeat] ?? <PlacedMeld>[];
      for (final play in turnMeldPlays.reversed) {
        final index = tableMelds.lastIndexWhere((meld) {
          return samePhysicalCards(meld.cards, play.meld.cards);
        });
        if (index != -1) {
          tableMelds.removeAt(index);
        }
      }
    }

    final hand = _handFor(_currentSeat);
    for (final meld in stagedMelds) {
      for (final card in meld.cards) {
        hand.add(card.isJoker ? card.withoutRepresentation() : card);
      }
      _turnJournal.removeFinishMeldMatching(meld);
    }
    for (final play in turnMeldPlays) {
      for (final card in play.meld.cards) {
        hand.add(card.isJoker ? card.withoutRepresentation() : card);
      }
      _turnJournal.removeFinishMeldMatching(play.meld);
    }

    HareegCard? restoredPending = _turnJournal.consumedPendingDiscard;
    for (final play in turnMeldPlays.reversed) {
      restoredPending = play.consumedPendingDiscard ?? restoredPending;
    }
    for (final play in coverPlays.reversed) {
      final targetMelds = _tableMelds[play.targetSeat];
      if (targetMelds != null &&
          play.meldIndex >= 0 &&
          play.meldIndex < targetMelds.length) {
        targetMelds[play.meldIndex] = play.previousMeld;
      }
      _turnJournal.removeFinishMeldMatching(play.coverMeld);
      _openingState = play.previousOpeningState;
      restoredPending = play.consumedPendingDiscard ?? restoredPending;
    }

    for (final play in coverPlays) {
      for (final card in play.coverMeld.cards) {
        hand.add(card.isJoker ? card.withoutRepresentation() : card);
      }
    }

    _turnJournal
      ..drainOpeningMelds()
      ..drainTurnMelds()
      ..drainCoverPlays()
      ..clearConsumedPendingDiscard();
    _syncUnlockedBenchmarkWithTable(allowLower: true);
    _pendingDiscard = restoredPending;
    _turnJournal.setSource(
      _pendingDiscard == null
          ? FinishCardSource.stock
          : FinishCardSource.previousDiscard,
    );
    return ApplyActionResult.success(plan.message);
  }

  ApplyActionResult _applyReturnTablePlay(ReturnTablePlayTarget target) {
    final plan = _targetTablePlayRetractionPlan(target);
    if (!plan.isAllowed) {
      return ApplyActionResult.failure(plan.message);
    }

    return switch (plan.scenario) {
      ClassicHareegTablePlayRetractionScenario.specificCoverStack =>
        _applyReturnCoverPlays(target, plan.coverPlays),
      ClassicHareegTablePlayRetractionScenario.specificTurnMeld =>
        _applyReturnTurnMeld(target, plan.meldPlays.single),
      ClassicHareegTablePlayRetractionScenario.specificOpeningMeld =>
        _applyReturnOpeningMeld(target, plan.stagedOpeningIndex!),
      _ => ApplyActionResult.failure(plan.message),
    };
  }

  ApplyActionResult _applyReturnTurnMeld(
    ReturnTablePlayTarget target,
    _TurnMeldPlay play,
  ) {
    final tableMelds = _tableMelds[target.owner];
    if (tableMelds == null ||
        target.meldIndex < 0 ||
        target.meldIndex >= tableMelds.length) {
      return const ApplyActionResult.failure(
        'That meld is no longer on table.',
      );
    }

    tableMelds.removeAt(target.meldIndex);
    _turnJournal.rebaseCoverPlaysAfterMeldRemoval(
      targetSeat: target.owner,
      removedIndex: target.meldIndex,
    );
    final hand = _handFor(_currentSeat);
    for (final card in play.meld.cards) {
      hand.add(card.isJoker ? card.withoutRepresentation() : card);
    }
    _turnJournal
      ..removeFinishMeldMatching(play.meld)
      ..removeTurnMeld(play);
    _syncUnlockedBenchmarkWithTable(allowLower: true);
    final consumed = play.consumedPendingDiscard;
    if (consumed != null) {
      _pendingDiscard = consumed;
      _turnJournal.setSource(FinishCardSource.previousDiscard);
    }
    return const ApplyActionResult.success('Melds returned to your hand.');
  }

  ApplyActionResult _applyReturnOpeningMeld(
    ReturnTablePlayTarget target,
    int stagedIndex,
  ) {
    final tableMelds = _tableMelds[target.owner];
    if (tableMelds == null ||
        target.meldIndex < 0 ||
        target.meldIndex >= tableMelds.length) {
      return const ApplyActionResult.failure(
        'That meld is no longer on table.',
      );
    }

    if (!_turnJournal.isValidStagedOpeningIndex(stagedIndex)) {
      return const ApplyActionResult.failure(
        'That opening meld cannot be taken back right now.',
      );
    }

    final staged = _turnJournal.removeStagedOpeningAt(stagedIndex)!;
    tableMelds.removeAt(target.meldIndex);
    _turnJournal.rebaseCoverPlaysAfterMeldRemoval(
      targetSeat: target.owner,
      removedIndex: target.meldIndex,
    );
    final hand = _handFor(_currentSeat);
    for (final card in staged.cards) {
      hand.add(card.isJoker ? card.withoutRepresentation() : card);
    }
    _turnJournal.removeFinishMeldMatching(staged);

    final consumed = _turnJournal.consumedPendingDiscard;
    if (consumed != null &&
        staged.cards.any((card) => card.id == consumed.id)) {
      _pendingDiscard = consumed;
      _turnJournal
        ..clearConsumedPendingDiscard()
        ..setSource(FinishCardSource.previousDiscard);
    }
    return const ApplyActionResult.success(
      'Opening melds returned to your hand.',
    );
  }

  ApplyActionResult _applyReturnCoverPlays(
    ReturnTablePlayTarget target,
    List<_TurnCoverPlay> coverPlays,
  ) {
    final targetMelds = _tableMelds[target.owner];
    if (targetMelds == null ||
        target.meldIndex < 0 ||
        target.meldIndex >= targetMelds.length) {
      return const ApplyActionResult.failure(
        'That meld is no longer on table.',
      );
    }

    targetMelds[target.meldIndex] = coverPlays.first.previousMeld;
    final hand = _handFor(_currentSeat);
    HareegCard? restoredPending;
    for (final play in coverPlays.reversed) {
      _turnJournal.removeFinishMeldMatching(play.coverMeld);
      restoredPending = play.consumedPendingDiscard ?? restoredPending;
    }
    for (final play in coverPlays) {
      for (final card in play.coverMeld.cards) {
        hand.add(card.isJoker ? card.withoutRepresentation() : card);
      }
    }

    _turnJournal.removeCoverPlaysFor(
      targetSeat: target.owner,
      meldIndex: target.meldIndex,
    );
    _syncUnlockedBenchmarkWithTable(allowLower: true);
    if (restoredPending != null) {
      _pendingDiscard = restoredPending;
      _turnJournal.setSource(FinishCardSource.previousDiscard);
    }
    return const ApplyActionResult.success('Covers returned to your hand.');
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

    final targetMelds = _tableMelds[target.targetSeat];
    if (targetMelds == null ||
        target.meldIndex < 0 ||
        target.meldIndex >= targetMelds.length) {
      return const ApplyActionResult.failure(
        'That meld is no longer on table.',
      );
    }

    final targetMeld = targetMelds[target.meldIndex];
    final ordered = _orderedCoverCards(
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

    final targetMelds = _tableMelds[target.targetSeat];
    if (targetMelds == null ||
        target.meldIndex < 0 ||
        target.meldIndex >= targetMelds.length) {
      return const ApplyActionResult.failure(
        'That meld is no longer on table.',
      );
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
        hand.removeAt(index);
        _discardPile.add(card);
        _roundMemory.onDiscard(discardingSeat, card);
        _previousDiscardSeat = discardingSeat;
        _lastReturnedPendingDiscard = null;
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
      final finish = ClassicHareegFinishRules.validateFinish(
        playedMelds: _turnFinishPlays,
        finalDiscard: card,
        playerOpened: _openingState.hasOpened(_currentSeat),
        source: _turnSource,
        perfectHandAttempt: !_openingState.hasOpened(_currentSeat),
      );
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

  /// Whether discarding [finalDiscard] right now completes a valid finish —
  /// the single proof-completion condition shared by the apply gate and the
  /// proof-turn discard surface, so they can never disagree.
  bool _provesFiftyFinish(HareegCard finalDiscard) {
    return ClassicHareegFinishRules.validateFinish(
      playedMelds: _turnFinishPlays,
      finalDiscard: finalDiscard,
      playerOpened: _openingState.hasOpened(_currentSeat),
      source: _turnSource,
      perfectHandAttempt: !_openingState.hasOpened(_currentSeat),
    ).isValid;
  }

  /// Resolves how a discard attempt exits an active Fifty proof turn.
  ///
  /// The claimed card can never be the discard. A final discard with the
  /// claimed card used and a valid finish proves the claim. Anything else is
  /// an unproven exit: blocked outright on Coaching/Standard (the claim was
  /// pre-validated, so the proof is always reachable), +3 with a normal turn
  /// end on Strict, and removal on Table.
  _FiftyProofExit _applyFiftyProofExitGate({
    required _ActiveFiftyClaim claim,
    required List<HareegCard> hand,
    required HareegCard card,
    required bool isFinalDiscard,
  }) {
    if (card.id == claim.claimedCardId) {
      return const _FiftyProofExitRefused(
        ApplyActionResult.failure(
          'The claimed card must be used in a meld or cover, never discarded.',
        ),
      );
    }

    final claimedCardUsed = _pendingDiscard == null;
    if (isFinalDiscard && claimedCardUsed && _provesFiftyFinish(card)) {
      return const _FiftyProofExitProven();
    }

    // The exit is unproven. It must ride a plain discard — blocked cards keep
    // their own restrictions and a failing last card cannot leave the hand.
    if (isFinalDiscard) {
      return const _FiftyProofExitRefused(
        ApplyActionResult.failure('That last card does not prove the Fifty.'),
      );
    }
    final eligibility = _discardEligibilityFor(
      seat: _currentSeat,
      card: card,
      isFinalDiscard: false,
    );
    if (eligibility.scenario != ClassicHareegDiscardScenario.normal) {
      return const _FiftyProofExitRefused(
        ApplyActionResult.failure(
          'That card cannot end the proof turn — pick a plain discard.',
        ),
      );
    }

    final mistake = _mistakeConsequencePlanFor(MistakeType.wrongFiftyClaim);
    if (!mistake.canApply) {
      return const _FiftyProofExitRefused(
        ApplyActionResult.failure('Prove the Fifty before ending the turn.'),
      );
    }
    // The priced exit hands the unused claimed card back to the pile, so an
    // exit that would empty the hand (claimed + exit are the last two cards)
    // cannot end the turn — the claimant must prove or take plays back.
    if (_pendingDiscard != null &&
        !setup.tableStrictness.removesPlayerOnMistake &&
        hand.length <= 2) {
      return const _FiftyProofExitRefused(
        ApplyActionResult.failure(
          'This exit would empty your hand — prove the Fifty or take plays '
          'back.',
        ),
      );
    }
    final discardingSeat = _currentSeat;
    final removal = _applyMistake(mistake);
    _activeFiftyClaim = null;
    if (removal != null) {
      // Table tier removed the claimant. The attempted discard still lands on
      // the pile (the unproven claimed card was already moved there by the
      // mistake plan when it sat unused).
      hand.removeWhere((candidate) => candidate.id == card.id);
      _discardPile.add(card);
      _roundMemory.onDiscard(discardingSeat, card);
      _previousDiscardSeat = discardingSeat;
      _lastReturnedPendingDiscard = null;
      return _FiftyProofExitRemoved(removal);
    }
    // Strict: the claim was called off, so the unused claimed card goes back
    // to the pile (owner-confirmed). It lands now, and the normal discard
    // flow drops the exit card on top of it.
    final unusedClaimedCard = _pendingDiscard;
    if (unusedClaimedCard != null) {
      hand.removeWhere((candidate) => candidate.id == unusedClaimedCard.id);
      _discardPile.add(unusedClaimedCard);
      _roundMemory.onReturnPendingDiscard(discardingSeat, unusedClaimedCard);
      _pendingDiscard = null;
      _turnJournal.clearConsumedPendingDiscard();
    }
    return _FiftyProofExitPenalized(mistake.message);
  }

  List<HareegCard> _handFor(PlayerSeat seat) {
    return _hands.putIfAbsent(seat, () => <HareegCard>[]);
  }

  ClassicTurnFlowState _turnFlowState() {
    final pending = _pendingDiscard;
    final previousDiscardSeat =
        _previousDiscardSeat ??
        (pending == null ? null : _previousAntiClockwise(_currentSeat));
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

  void _evaluateRoundEnd() {
    if (_roundOutcome != null || _phase != TurnPhase.draw) {
      return;
    }

    final plan = _drawDecisionPlanFor(_currentSeat);
    if (!plan.stockIsEmpty) {
      // Stock still has cards: liveness can't stall, so clear any accrued
      // no-progress accounting and skip the empty-stock checks entirely.
      _stockExhaustionHandTotalBaseline = null;
      _stockExhaustionNoProgressTurns = 0;
      return;
    }

    var shouldDraw = plan.shouldEndRoundAsDraw;
    if (!shouldDraw) {
      // A hopeless (invalid) Fifty claim is advertised for the human's optional
      // paid-mistake flow, which keeps `shouldEndRoundAsDraw` false. It has no
      // strategic value, so once stock is exhausted and neither a valid Fifty
      // finish nor a pickup finish remains, the round is a draw — otherwise a
      // CPU claimant would be stranded (no stock to draw, only a self-penalty
      // claim on offer).
      final hasValidFiftyFinish =
          _fiftyClaimPlanFor(
            _currentSeat,
            purpose: ClassicHareegFiftyClaimPurpose.apply,
          ).finishPlan !=
          null;
      final pickupFinish =
          plan.canTakePreviousDiscard && plan.pickupWouldFinish;
      shouldDraw = !hasValidFiftyFinish && !pickupFinish;
    }

    if (!shouldDraw && _stockExhaustionLivelockReached()) {
      // Liveness backstop: a seat the finish detector believes can finish (an
      // optimistic pickup/Fifty finish) but that never actually completes will
      // take and re-discard the open window forever. A full rotation of active
      // seats has now passed with no reduction in total hand cards, so the
      // round can never progress toward a finish — draw it directly. The normal
      // stock-exhaustion planner would decline here (it sees a pickup finish),
      // so the draw is forced rather than routed through it.
      _roundEndedByLivelockBackstop = true;
      _completeRound(
        ClassicHareegTurnExitPlanner.roundResult(
          type: RoundOutcomeType.draw,
          remainingCardCounts: _remainingCardCounts(),
        ),
      );
      return;
    }

    if (!shouldDraw) {
      return;
    }

    final result = ClassicHareegTurnExitPlanner.stockExhaustionRoundResult(
      stockIsEmpty: plan.stockIsEmpty,
      previousDiscardCanFinish: plan.canTakePreviousDiscard,
      pickupWouldFinish: plan.pickupWouldFinish,
      remainingCardCounts: _remainingCardCounts(),
    );
    if (result != null) {
      _completeRound(result);
    }
  }

  /// Concludes an open round when the human ([PlayerSeat.south]) is out of the
  /// match by score (>= the elimination threshold).
  ///
  /// A mid-round Table penalty can push the human past the threshold. Per the
  /// rules the remaining seats would keep playing the round out, but the human
  /// is eliminated from the match — and the table short-circuits to match-over
  /// once the human is eliminated rather than make them watch the CPUs finish
  /// (see [isHumanEliminated]). That short-circuit only runs off a produced
  /// round result, so the round is concluded here as a draw, which leaves the
  /// standings exactly as scoring left them; match progression then drops the
  /// human and the table opens match-over. Invoked from the action seam and the
  /// constructors, so resuming a match already saved in this stuck state
  /// recovers to match-over instead of a frozen table.
  void _concludeRoundIfHumanEliminated() {
    if (_roundOutcome != null) {
      return;
    }
    // Only short-circuit while the human is still a match participant whose
    // score just crossed the threshold mid-round. Once a prior round has
    // already pruned them, a freshly dealt CPU-only round legitimately omits
    // them from [_activeSeats] — concluding those would loop the headless match
    // driver (which drives every seat) on a round that should play out.
    if (!_activeSeats.contains(PlayerSeat.south)) {
      return;
    }
    if ((_scores[PlayerSeat.south] ?? 0) < rules.eliminationScore) {
      return;
    }
    _completeRound(
      ClassicHareegTurnExitPlanner.roundResult(
        type: RoundOutcomeType.draw,
        remainingCardCounts: _remainingCardCounts(),
      ),
    );
  }

  /// Tracks per-turn progress while stock is empty and reports whether a full
  /// rotation of active seats has now elapsed with no progress (no card melded
  /// or covered out of any hand). See [_stockExhaustionHandTotalBaseline].
  bool _stockExhaustionLivelockReached() {
    final handTotal = _activeHandCardTotal();
    final baseline = _stockExhaustionHandTotalBaseline;
    if (baseline == null || handTotal < baseline) {
      // First empty-stock turn, or real progress since the last check: a card
      // left a hand onto the table. Restart the no-progress count from here.
      _stockExhaustionHandTotalBaseline = handTotal;
      _stockExhaustionNoProgressTurns = 1;
      return false;
    }
    _stockExhaustionNoProgressTurns += 1;
    // One turn per active seat without progress is a complete dead rotation.
    return _stockExhaustionNoProgressTurns > _roundActiveSeats.length;
  }

  /// Total cards held across every seat still active in the round.
  int _activeHandCardTotal() {
    var total = 0;
    for (final seat in _roundActiveSeats) {
      total += cardCountFor(seat);
    }
    return total;
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

  List<PlayerSeat> get _roundScoringSeats {
    return ClassicHareegTurnExitPlanner.roundActiveSeats(
      activeSeats: _activeSeats,
      removedSeats: _removedSeats,
    );
  }

  ClassicHareegMistakeConsequencePlan _mistakeConsequencePlanFor(
    MistakeType mistake,
  ) {
    return ClassicHareegMistakeConsequencePlanner.evaluate(
      strictness: setup.tableStrictness,
      mistake: mistake,
      seat: _currentSeat,
      scores: _scores,
      activeSeats: _activeSeats,
      removedSeats: _removedSeats,
      hasPendingDiscard: _pendingDiscard != null,
      remainingCardCounts: _remainingCardCounts(),
    );
  }

  ClassicHareegMistakeConsequencePlan _mistakeConsequencePlan(
    MistakeResolution resolution,
  ) {
    return ClassicHareegMistakeConsequencePlanner.fromResolution(
      resolution: resolution,
      seat: _currentSeat,
      scores: _scores,
      activeSeats: _activeSeats,
      removedSeats: _removedSeats,
      hasPendingDiscard: _pendingDiscard != null,
      remainingCardCounts: _remainingCardCounts(),
    );
  }

  ApplyActionResult? _applyMistake(ClassicHareegMistakeConsequencePlan plan) {
    if (!plan.canApply) {
      return ApplyActionResult.failure(plan.message);
    }

    _scores
      ..clear()
      ..addAll(plan.scoresAfterPenalty);
    if (!plan.removesPlayer) {
      return null;
    }

    // Removal always takes the current seat out of the round; a Fifty proof
    // in progress (if any) is abandoned with it.
    _activeFiftyClaim = null;
    final removedSeat = plan.removedSeat!;
    final pending = _pendingDiscard;
    if (pending != null && plan.shouldMovePendingDiscardToDiscardPile) {
      _handFor(removedSeat).removeWhere((card) => card.id == pending.id);
      _discardPile.add(pending);
      // Treat the forced return as a discard by the removed seat so the
      // CPU threat model (DiscardHistory) and any takeDiscard predicates
      // gated on _previousDiscardSeat see a consistent attribution.
      _previousDiscardSeat = removedSeat;
      _roundMemory.onDiscard(removedSeat, pending);
      _lastReturnedPendingDiscard = null;
    }
    _pendingDiscard = null;
    if (plan.shouldClearFiftyWindow) {
      _fiftyWindow = null;
      _fiftyWindowOpenedAt = null;
    }
    if (plan.shouldResetTurnState) {
      _turnJournal.resetForNewTurn();
    }
    _removedSeats
      ..clear()
      ..addAll(plan.removedSeatsAfterMistake);

    final result = plan.roundResult;
    if (result != null) {
      _completeRound(result);
    } else if (plan.nextSeat != null && plan.nextPhase != null) {
      _currentSeat = plan.nextSeat!;
      _phase = plan.nextPhase!;
      _evaluateRoundEnd();
    }
    // A Table penalty can push the human past the elimination threshold. If so
    // the round must conclude so the table surfaces match-over instead of
    // playing on without them (see [_concludeRoundIfHumanEliminated]).
    _concludeRoundIfHumanEliminated();

    return ApplyActionResult.success(plan.message);
  }

  Map<PlayerSeat, int> _remainingCardCounts({Set<PlayerSeat>? removedSeats}) {
    final seats = removedSeats == null
        ? _roundScoringSeats
        : ClassicHareegTurnExitPlanner.roundActiveSeats(
            activeSeats: _activeSeats,
            removedSeats: removedSeats,
          );
    return {for (final seat in seats) seat: cardCountFor(seat)};
  }

  void _completeRound(RoundProgressResult result) {
    _roundOutcome = result.type;
    _roundResult = result;
    _activeFiftyClaim = null;
    // The round is over: the winning turn's plays are permanently committed, so
    // there is no in-progress turn to resume. Clear the reversible turn journal
    // so a round-over `toSnapshot` reflects the true final state instead of
    // reverting the winner's finishing plays back into their hand. Without this,
    // a card placed and then replaced this turn (e.g. a joker covered onto a meld
    // then swapped out for a real card and discarded) is re-materialised by the
    // stale revert and duplicated. Every caller reads the journal (finish
    // validation, remaining-card counts) before reaching here, and no action is
    // legal once the round has ended, so clearing now is safe.
    _turnJournal.resetForNewTurn();
    final progress = _matchFlow.progressFor(result);
    if (progress == null) {
      return;
    }
    for (final seat in _activeSeats) {
      if (progress.activeSeats.contains(seat) || seat == progress.matchWinner) {
        continue;
      }
      _seatEliminatedRound.putIfAbsent(seat, () => _roundNumber);
    }
  }

  void _finishRound({
    required RoundOutcomeType type,
    PlayerSeat? winner,
    PlayerSeat? fiftyDiscarder,
    bool firstRoundFiftyException = false,
  }) {
    _completeRound(
      ClassicHareegTurnExitPlanner.roundResult(
        type: type,
        winner: winner,
        fiftyDiscarder: fiftyDiscarder,
        firstRoundFiftyException: firstRoundFiftyException,
        remainingCardCounts: _remainingCardCounts(),
      ),
    );
  }

  List<List<HareegCard>> get _tableMeldCardLists {
    return [
      for (final melds in _tableMelds.values)
        for (final meld in melds) meld.cards,
    ];
  }

  int _fiftyElapsedSeconds() {
    final openedAt = _fiftyWindowOpenedAt;
    if (openedAt == null) {
      return 0;
    }
    final elapsed = _now().difference(openedAt);
    if (elapsed.isNegative) {
      return 0;
    }
    return elapsed.inSeconds;
  }

  ApplyActionResult _applyClaimFifty() {
    final plan = _fiftyClaimPlanFor(
      _currentSeat,
      purpose: ClassicHareegFiftyClaimPurpose.apply,
    );
    if (!plan.canApply) {
      return ApplyActionResult.failure(plan.message);
    }
    final window = _fiftyWindow;
    if (window == null || _discardPile.isEmpty) {
      return const ApplyActionResult.failure('No active Fifty discard.');
    }

    // Prove-it flow: claiming takes the thrown card into the hand and the
    // claimant lays the proof down manually through the normal play surface.
    // The play-out is untimed — the timer only races the call itself, so the
    // window is consumed here. Blocking tiers reach this point only with a
    // pre-validated finish plan; permissive tiers accept unproven claims and
    // charge the tier consequence if the turn ends unproven.
    final claimed = _discardPile.removeLast();
    _handFor(_currentSeat).add(claimed);
    _roundMemory.onTakePreviousDiscard(_currentSeat, claimed);
    _pendingDiscard = claimed;
    _previousDiscardSeat = window.discarder;
    _phase = TurnPhase.action;
    // The explicit claim owns the Fifty provenance from here; drop any plain
    // take marker so the two paths cannot both fire at the finish.
    _windowedDiscardTake = null;
    _fiftyWindow = null;
    _fiftyWindowOpenedAt = null;
    _lastReturnedPendingDiscard = null;
    _turnJournal.setSource(FinishCardSource.previousDiscard);
    final finishPlan = plan.finishPlan;
    _activeFiftyClaim = _ActiveFiftyClaim(
      claimedCardId: claimed.id,
      discarder: window.discarder,
      isFirstDealtRound: window.isFirstDealtRound,
      script: finishPlan == null ? null : _fiftyProofScript(finishPlan),
    );
    return ApplyActionResult.success(plan.message);
  }

  /// Builds the ordered proof action ids for a validated finish plan: fresh
  /// melds first, then cover placements, then the final discard. CPU claims
  /// replay this script through the normal apply flow so the proof plays out
  /// visibly at normal pacing.
  List<String> _fiftyProofScript(ClassicHareegFinishPlan plan) {
    return List.unmodifiable([
      for (final meld in plan.melds)
        _playMeldActionIdFor(meld.cards.map((card) => card.id), [
          for (final card in meld.cards)
            if (card.isJoker && card.representedIdentity != null)
              JokerMeldAssignment(
                jokerId: card.id,
                identity: card.representedIdentity!,
              ),
        ]),
      for (final cover in plan.covers)
        ClassicHareegActionIds.placeCoverActionId(
          targetSeat: cover.targetSeat,
          meldIndex: cover.meldIndex,
          cardIds: cover.cards.map((card) => card.id),
          jokerIdentities: {
            for (final card in cover.cards)
              if (card.isJoker && card.representedIdentity != null)
                card.id: card.representedIdentity!,
          },
        ),
      '${ClassicHareegActionIds.discardPrefix}${plan.finalDiscard.id}',
    ]);
  }

  /// Next CPU proof step during an active Fifty claim, or null when no claim
  /// is active (or no finish plan resolves — the surface then falls back to
  /// the normal action ids, whose only exits are tier-priced).
  String? _fiftyProofScriptActionFor(PlayerSeat seat) {
    final claim = _activeFiftyClaim;
    if (claim == null || seat != _currentSeat || _roundOutcome != null) {
      return null;
    }
    var script = claim.script;
    if (script == null || claim.scriptIndex >= script.length) {
      final plan = _fiftyProofPlanForCurrentState(seat, claim);
      if (plan == null) {
        return null;
      }
      script = _fiftyProofScript(plan);
      claim.script = script;
      claim.scriptIndex = 0;
    }
    return script[claim.scriptIndex];
  }

  /// Resolves a finish plan for the proof turn from the LIVE state — used to
  /// (re)build the CPU script lazily, e.g. after a snapshot restore.
  ClassicHareegFinishPlan? _fiftyProofPlanForCurrentState(
    PlayerSeat seat,
    _ActiveFiftyClaim claim,
  ) {
    final hand = _handFor(seat);
    final opened = _openingState.hasOpened(seat);
    final claimedIndex = hand.indexWhere(
      (card) => card.id == claim.claimedCardId,
    );
    if (claimedIndex != -1) {
      final claimed = hand[claimedIndex];
      return ClassicHareegFiftyClaimPlanner.finishPlanForClaim(
        hand: [
          for (final card in hand)
            if (card.id != claimed.id) card,
        ],
        discarded: claimed,
        playerOpened: opened,
        coverTargets: _finishCoverTargets(),
        openingRequirement: _openingState.currentRequirement,
      );
    }
    // The claimed card is already used; any full finish of the remaining
    // hand completes the proof.
    final planner = ClassicHareegFinishPlanner(
      hand,
      coverTargets: _finishCoverTargets(),
      coverPlanMinimumMeldValue: opened
          ? null
          : _openingState.currentRequirement,
    );
    for (final candidate in hand) {
      final parts = planner.planWithout(candidate);
      if (parts != null) {
        return ClassicHareegFinishPlan(
          melds: parts.melds,
          covers: parts.covers,
          finalDiscard: candidate,
        );
      }
    }
    return null;
  }

  /// Advances the active proof script when its head action just applied; any
  /// off-script action invalidates the script so the next poll re-plans from
  /// the live state (the proof stays completable — every prefix of plays
  /// leaves a plannable remainder, and retracts restore the planned shape).
  void _onActionApplied(String actionId) {
    final claim = _activeFiftyClaim;
    final script = claim?.script;
    if (claim == null || script == null) {
      return;
    }
    if (claim.scriptIndex < script.length &&
        script[claim.scriptIndex] == actionId) {
      claim.scriptIndex += 1;
      return;
    }
    claim
      ..script = null
      ..scriptIndex = 0;
  }

  /// Whether [seat] could finish *by taking* the previous discard right now.
  ///
  /// This drives the stock-exhaustion liveness decision: an empty-stock round is
  /// kept alive only while a seat can still finish on the pile. The check must
  /// therefore report a finish the pickup flow can actually play out — otherwise
  /// the seat takes the card, fails to finish, re-discards, and the round
  /// livelocks (the liveness backstop then has to force a draw).
  ///
  /// The pickup flow takes the discard as a pending card that must be used
  /// immediately: the relaxed taken-discard surface offers only plays that use
  /// it, and an unopened seat cannot place a cover until it has opened. So a
  /// cover-routed taken discard is unplayable for an unopened seat — it can only
  /// be returned. The Fifty *claim* path is exempt (its proof script opens
  /// before covering), which is why this realizability constraint lives on the
  /// pickup predicate and not on [_finishPlanWithPreviousDiscard] itself. For an
  /// unopened seat we re-check with the taken discard barred from covers, so a
  /// finish is reported only when the discard genuinely lands in a fresh meld.
  bool _canFinishWithPreviousDiscard(PlayerSeat seat) {
    if (_finishPlanWithPreviousDiscard(seat) == null) {
      return false;
    }
    if (_openingState.hasOpened(seat)) {
      return true;
    }
    final discarded = topDiscard;
    if (discarded == null) {
      return false;
    }
    final planner = ClassicHareegFinishPlanner(
      [..._handFor(seat), discarded],
      coverTargets: _finishCoverTargets(),
      coverPlanMinimumMeldValue: _openingState.currentRequirement,
      coverDisallowedCardIds: {discarded.id},
    );
    if (!planner.hasValidMeldContaining(discarded.id)) {
      return false;
    }
    return ClassicHareegFiftyClaimPlanner.finishPlanForClaim(
          hand: _handFor(seat),
          discarded: discarded,
          playerOpened: false,
          planner: planner,
        ) !=
        null;
  }

  ClassicHareegFiftyClaimPlan _fiftyClaimPlanFor(
    PlayerSeat seat, {
    required ClassicHareegFiftyClaimPurpose purpose,
  }) {
    return ClassicHareegFiftyClaimPlanner.evaluate(
      purpose: purpose,
      strictness: setup.tableStrictness,
      window: _fiftyWindow,
      claimant: seat,
      phase: _phase,
      elapsedSeconds: _fiftyElapsedSeconds(),
      topDiscard: topDiscard,
      finishPlanResolver: () => _finishPlanWithPreviousDiscard(seat),
    );
  }

  ClassicHareegFinishPlan? _finishPlanWithPreviousDiscard(PlayerSeat seat) {
    final discarded = topDiscard;
    if (discarded == null) {
      return null;
    }
    final cacheKey = _previousDiscardFinishKey(seat, discarded);
    if (_previousDiscardFinishCacheKey == cacheKey) {
      if (_previousDiscardFinishCacheValue == false) {
        return null;
      }
      final cachedPlan = _previousDiscardFinishPlanCacheValue;
      if (cachedPlan != null) {
        return cachedPlan;
      }
    }

    final playerOpened = _openingState.hasOpened(seat);
    final cards = [..._handFor(seat), discarded];
    final planner = ClassicHareegFinishPlanner(
      cards,
      coverTargets: _finishCoverTargets(),
      coverPlanMinimumMeldValue: playerOpened
          ? null
          : _openingState.currentRequirement,
    );
    if (!planner.hasFinishUseContaining(discarded.id)) {
      _previousDiscardFinishCacheKey = cacheKey;
      _previousDiscardFinishCacheValue = false;
      _previousDiscardFinishPlanCacheValue = null;
      return null;
    }
    final plan = ClassicHareegFiftyClaimPlanner.finishPlanForClaim(
      hand: _handFor(seat),
      discarded: discarded,
      playerOpened: playerOpened,
      planner: planner,
    );
    _previousDiscardFinishCacheKey = cacheKey;
    _previousDiscardFinishCacheValue = plan != null;
    _previousDiscardFinishPlanCacheValue = plan;
    return plan;
  }

  /// Every table meld as a cover target for cover-aware finish planning.
  List<ClassicHareegFinishCoverTarget> _finishCoverTargets() {
    return ClassicHareegFinishCoverTarget.allFrom(_tableMelds);
  }

  String _previousDiscardFinishKey(PlayerSeat seat, HareegCard discarded) {
    final handIds = _handFor(seat).map(_cardCacheIdentity).toList()..sort();
    // Cover-aware plans depend on the table state, so the cache key carries a
    // table-melds signature — a cover target appearing or growing must
    // invalidate a cached "no finish" verdict.
    final tableSignature = StringBuffer();
    for (final entry in _tableMelds.entries) {
      for (final meld in entry.value) {
        tableSignature
          ..write(entry.key.name)
          ..write(':');
        for (final card in meld.cards) {
          tableSignature
            ..write(_cardCacheIdentity(card))
            ..write(',');
        }
        tableSignature.write(';');
      }
    }
    return [
      seat.name,
      _cardCacheIdentity(discarded),
      _phase.name,
      '${_stock.length}',
      '${_discardPile.length}',
      '${_openingState.hasOpened(seat)}',
      '${_openingState.currentRequirement}',
      handIds.join(','),
      tableSignature.toString(),
    ].join('|');
  }

  String _cardCacheIdentity(HareegCard card) {
    return '${card.id}:${card.representedIdentity?.key ?? ''}';
  }

  List<String> _playMeldActionIds(PlayerSeat seat, {String? mustUseCardId}) {
    if (_phase != TurnPhase.action) {
      return const [];
    }

    final hand = _hands[seat] ?? const <HareegCard>[];
    final ids = <String>{};
    final meldOptions = <_MeldActionOption>[];
    for (final group in _candidateMeldGroups(
      hand,
      preferredCardId: mustUseCardId,
    )) {
      if (hand.length - group.length == 0) {
        continue;
      }

      final option = _resolveMeldActionOption(group);
      if (option == null) {
        continue;
      }
      meldOptions.add(option);
      if ((mustUseCardId == null || option.cardIds.contains(mustUseCardId)) &&
          _canAdvertiseMeldPlay(
            seat: seat,
            handCount: hand.length,
            playedCardIds: option.cardIds.toSet(),
            melds: [option.meld],
          )) {
        ids.add(option.actionId);
      }
    }
    _addOpeningCombinationActionIds(
      ids: ids,
      seat: seat,
      hand: hand,
      options: meldOptions,
      mustUseCardId: mustUseCardId,
    );
    return List.unmodifiable(ids);
  }

  String? _firstPlayMeldActionId(PlayerSeat seat, {String? mustUseCardId}) {
    if (_phase != TurnPhase.action) {
      return null;
    }

    final totalWatch = Stopwatch()..start();
    final hand = _hands[seat] ?? const <HareegCard>[];
    _debugRulesLog(
      'firstPlayMeld start seat=${seat.name} hand=${hand.length} '
      'opened=${_openingState.hasOpened(seat)} mustUse=$mustUseCardId',
    );
    final openingOptions = <_MeldActionOption>[];
    final groupWatch = Stopwatch()..start();
    final groups = _candidateMeldGroups(hand, preferredCardId: mustUseCardId);
    groupWatch.stop();
    _debugRulesLog(
      'firstPlayMeld groups seat=${seat.name} '
      'elapsed=${groupWatch.elapsedMilliseconds}ms count=${groups.length}',
    );
    var considered = 0;
    var resolved = 0;
    for (final group in groups) {
      considered += 1;
      if (considered % _debugMeldProgressInterval == 0 &&
          totalWatch.elapsedMilliseconds >= _debugSlowRuleSearchMs) {
        _debugRulesLog(
          'firstPlayMeld progress seat=${seat.name} considered=$considered '
          'resolved=$resolved openingOptions=${openingOptions.length} '
          'elapsed=${totalWatch.elapsedMilliseconds}ms',
        );
      }
      if (hand.length - group.length == 0) {
        continue;
      }

      final option = _resolveMeldActionOption(group);
      if (option == null) {
        continue;
      }
      resolved += 1;
      if ((mustUseCardId == null || option.cardIds.contains(mustUseCardId)) &&
          _canAdvertiseMeldPlay(
            seat: seat,
            handCount: hand.length,
            playedCardIds: option.cardIds.toSet(),
            melds: [option.meld],
          )) {
        totalWatch.stop();
        _debugRulesLog(
          'firstPlayMeld direct hit seat=${seat.name} '
          'elapsed=${totalWatch.elapsedMilliseconds}ms '
          'considered=$considered resolved=$resolved action=${option.actionId}',
        );
        return option.actionId;
      }

      if (!_openingState.hasOpened(seat) &&
          openingOptions.length < _maxCpuOpeningMeldOptions) {
        openingOptions.add(option);
      }
    }

    if (_openingState.hasOpened(seat) || openingOptions.length < 2) {
      totalWatch.stop();
      _debugRulesLog(
        'firstPlayMeld none seat=${seat.name} '
        'elapsed=${totalWatch.elapsedMilliseconds}ms considered=$considered '
        'resolved=$resolved openingOptions=${openingOptions.length}',
      );
      return null;
    }

    final combo = _firstOpeningCombinationActionId(
      seat: seat,
      hand: hand,
      options: openingOptions,
      mustUseCardId: mustUseCardId,
    );
    totalWatch.stop();
    _debugRulesLog(
      'firstPlayMeld combination seat=${seat.name} '
      'elapsed=${totalWatch.elapsedMilliseconds}ms considered=$considered '
      'resolved=$resolved openingOptions=${openingOptions.length} '
      'hit=${combo != null}',
    );
    return combo;
  }

  String? _firstOpeningCombinationActionId({
    required PlayerSeat seat,
    required List<HareegCard> hand,
    required List<_MeldActionOption> options,
    String? mustUseCardId,
  }) {
    final totalWatch = Stopwatch()..start();
    final uniqueOptions = <_MeldActionOption>[];
    final seenCardSets = <String>{};
    for (final option in options) {
      final key = (option.cardIds.toList()..sort()).join('|');
      if (seenCardSets.add(key)) {
        uniqueOptions.add(option);
      }
    }
    _debugRulesLog(
      'openingCombination start seat=${seat.name} hand=${hand.length} '
      'options=${options.length} unique=${uniqueOptions.length} '
      'mustUse=$mustUseCardId',
    );

    String? found;
    var visited = 0;
    void search({
      required int start,
      required Set<String> usedIds,
      required List<PlacedMeld> melds,
      required int meldCount,
      required List<JokerMeldAssignment> jokerAssignments,
    }) {
      visited += 1;
      if (visited % _debugOpeningProgressInterval == 0 &&
          totalWatch.elapsedMilliseconds >= _debugSlowRuleSearchMs) {
        _debugRulesLog(
          'openingCombination progress seat=${seat.name} visited=$visited '
          'start=$start meldCount=$meldCount used=${usedIds.length} '
          'elapsed=${totalWatch.elapsedMilliseconds}ms',
        );
      }
      if (found != null) {
        return;
      }
      if (meldCount >= 2 &&
          usedIds.length < hand.length &&
          (mustUseCardId == null || usedIds.contains(mustUseCardId)) &&
          _canAdvertiseMeldPlay(
            seat: seat,
            handCount: hand.length,
            playedCardIds: usedIds,
            melds: melds,
          )) {
        final orderedCards = hand
            .where((card) => usedIds.contains(card.id))
            .toList(growable: false);
        found = _playMeldActionIdFor(
          orderedCards.map((card) => card.id),
          jokerAssignments,
        );
        return;
      }
      if (meldCount >= _maxCpuOpeningCombinationMelds) {
        return;
      }

      for (var index = start; index < uniqueOptions.length; index += 1) {
        final option = uniqueOptions[index];
        if (option.cardIds.any(usedIds.contains)) {
          continue;
        }
        final nextUsedIds = {...usedIds, ...option.cardIds};
        if (nextUsedIds.length >= hand.length) {
          continue;
        }
        search(
          start: index + 1,
          usedIds: nextUsedIds,
          melds: [...melds, option.meld],
          meldCount: meldCount + 1,
          jokerAssignments: [...jokerAssignments, ...option.jokerAssignments],
        );
      }
    }

    search(
      start: 0,
      usedIds: <String>{},
      melds: const <PlacedMeld>[],
      meldCount: 0,
      jokerAssignments: const <JokerMeldAssignment>[],
    );
    totalWatch.stop();
    _debugRulesLog(
      'openingCombination end seat=${seat.name} '
      'elapsed=${totalWatch.elapsedMilliseconds}ms visited=$visited '
      'found=${found != null}',
    );
    return found;
  }

  List<List<HareegCard>> _candidateMeldGroups(
    List<HareegCard> hand, {
    String? preferredCardId,
  }) {
    final totalWatch = Stopwatch()..start();
    final groups = ClassicHareegMeldCandidateSearch.candidateMeldGroups(
      hand,
      preferredCardId: preferredCardId,
      maxPhysicalVariants: _maxPhysicalMeldVariants,
    );

    totalWatch.stop();
    if (totalWatch.elapsedMilliseconds >= _debugSlowRuleSearchMs ||
        groups.length >= _debugLargeGroupCount) {
      _debugRulesLog(
        'candidateMeldGroups end hand=${hand.length} '
        'preferred=$preferredCardId '
        'elapsed=${totalWatch.elapsedMilliseconds}ms groups=${groups.length}',
      );
    }
    return groups;
  }

  _MeldActionOption? _resolveMeldActionOption(List<HareegCard> group) {
    var resolved = _resolveMeldCards(group);
    var jokerAssignments = const <JokerMeldAssignment>[];
    if (!resolved.result.isValid) {
      final variants = ClassicHareegTablePlayPlanner.resolveMeldCardVariants(
        group,
        limit: 1,
      );
      if (variants.isNotEmpty) {
        final variant = variants.single;
        resolved = _ResolvedMeldCards(
          cards: variant.cards,
          result: variant.result,
        );
        jokerAssignments = variant.jokerAssignments;
      }
    }
    if (!resolved.result.isValid) {
      return null;
    }

    final cardIds = group.map((card) => card.id).toList(growable: false);
    return _MeldActionOption(
      cards: List.unmodifiable(group),
      meld: PlacedMeld.fromCards(resolved.cards),
      actionId: _playMeldActionIdFor(cardIds, jokerAssignments),
      jokerAssignments: jokerAssignments,
    );
  }

  void _addOpeningCombinationActionIds({
    required Set<String> ids,
    required PlayerSeat seat,
    required List<HareegCard> hand,
    required List<_MeldActionOption> options,
    String? mustUseCardId,
  }) {
    if (_openingState.hasOpened(seat) || options.length < 2) {
      return;
    }

    final uniqueOptions = <_MeldActionOption>[];
    final seenCardSets = <String>{};
    for (final option in options) {
      final key = (option.cardIds.toList()..sort()).join('|');
      if (seenCardSets.add(key)) {
        uniqueOptions.add(option);
      }
    }

    void search({
      required int start,
      required Set<String> usedIds,
      required List<PlacedMeld> melds,
      required int meldCount,
      required List<JokerMeldAssignment> jokerAssignments,
    }) {
      if (meldCount >= 2 &&
          usedIds.length < hand.length &&
          (mustUseCardId == null || usedIds.contains(mustUseCardId)) &&
          _canAdvertiseMeldPlay(
            seat: seat,
            handCount: hand.length,
            playedCardIds: usedIds,
            melds: melds,
          )) {
        final orderedCards = hand
            .where((card) => usedIds.contains(card.id))
            .toList(growable: false);
        ids.add(
          _playMeldActionIdFor(
            orderedCards.map((card) => card.id),
            jokerAssignments,
          ),
        );
      }

      for (var index = start; index < uniqueOptions.length; index += 1) {
        final option = uniqueOptions[index];
        if (option.cardIds.any(usedIds.contains)) {
          continue;
        }
        final nextUsedIds = {...usedIds, ...option.cardIds};
        if (nextUsedIds.length >= hand.length) {
          continue;
        }
        search(
          start: index + 1,
          usedIds: nextUsedIds,
          melds: [...melds, option.meld],
          meldCount: meldCount + 1,
          jokerAssignments: [...jokerAssignments, ...option.jokerAssignments],
        );
      }
    }

    search(
      start: 0,
      usedIds: <String>{},
      melds: const <PlacedMeld>[],
      meldCount: 0,
      jokerAssignments: const <JokerMeldAssignment>[],
    );
  }

  bool _canAdvertiseMeldPlay({
    required PlayerSeat seat,
    required int handCount,
    required Set<String> playedCardIds,
    required List<PlacedMeld> melds,
  }) {
    return _meldPlayEligibilityFor(
      seat: seat,
      handCount: handCount,
      playedCardIds: playedCardIds,
      melds: melds,
    ).shouldAdvertise;
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

  List<String> _replaceJokerActionIds(
    PlayerSeat seat, {
    String? mustUseCardId,
  }) {
    return _tablePlayPlanner.replaceJokerActionIds(
      seat,
      mustUseCardId: mustUseCardId,
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

  List<String> _coverActionIds(PlayerSeat seat, {String? mustUseCardId}) {
    return _tablePlayPlanner.coverActionIds(seat, mustUseCardId: mustUseCardId);
  }

  _ResolvedTablePlay _resolveTablePlay(
    List<HareegCard> cards, {
    String? jokerId,
    CardIdentity? jokerIdentity,
    Map<String, CardIdentity>? jokerIdentities,
  }) {
    final resolved = ClassicHareegTablePlayPlanner.resolveTablePlay(
      cards,
      jokerId: jokerId,
      jokerIdentity: jokerIdentity,
      jokerIdentities: jokerIdentities,
    );
    return _ResolvedTablePlay(melds: resolved.melds, result: resolved.result);
  }

  _ResolvedMeldCards _resolveMeldCards(
    List<HareegCard> cards, {
    String? jokerId,
    CardIdentity? jokerIdentity,
    Map<String, CardIdentity>? jokerIdentities,
  }) {
    final resolved = ClassicHareegTablePlayPlanner.resolveMeldCards(
      cards,
      jokerId: jokerId,
      jokerIdentity: jokerIdentity,
      jokerIdentities: jokerIdentities,
    );
    return _ResolvedMeldCards(cards: resolved.cards, result: resolved.result);
  }

  List<HareegCard>? _orderedCoverCards({
    required List<HareegCard> tableMeld,
    required List<HareegCard> candidates,
  }) {
    return ClassicHareegTablePlayPlanner.orderedCoverCards(
      tableMeld: tableMeld,
      candidates: candidates,
    );
  }

  List<String> _discardActionIds(PlayerSeat seat) {
    final hand = _hands[seat] ?? const <HareegCard>[];
    final isFinalDiscard = hand.length == 1;
    if (!isFinalDiscard &&
        !_openingState.hasOpened(seat) &&
        _turnOpeningMelds.isNotEmpty) {
      return const [];
    }
    if (seat == _currentSeat) {
      final claim = _activeFiftyClaim;
      if (claim != null) {
        return _fiftyProofDiscardActionIds(
          claim: claim,
          hand: hand,
          isFinalDiscard: isFinalDiscard,
        );
      }
      if (_pendingDiscard != null) {
        // Relaxed taken-discard rule: the turn cannot end while the taken
        // card sits unused, so no discard is on the surface.
        return const [];
      }
    }

    final ids = <String>[];
    for (final card in hand) {
      final eligibility = _discardEligibilityFor(
        seat: seat,
        card: card,
        isFinalDiscard: isFinalDiscard,
      );
      if (!eligibility.shouldAdvertise) {
        continue;
      }
      ids.add(eligibility.actionId);
    }
    return List.unmodifiable(ids);
  }

  /// Discard ids advertised during a Fifty proof turn.
  ///
  /// The only winning exit is the final discard of a completed proof. On the
  /// mistake-allowing tiers, plain discards stay on the surface as the priced
  /// unproven exit; blocking tiers advertise nothing until the proof closes.
  List<String> _fiftyProofDiscardActionIds({
    required _ActiveFiftyClaim claim,
    required List<HareegCard> hand,
    required bool isFinalDiscard,
  }) {
    final claimedCardUsed = _pendingDiscard == null;
    if (isFinalDiscard && claimedCardUsed) {
      final card = hand.single;
      if (card.id != claim.claimedCardId && _provesFiftyFinish(card)) {
        return List.unmodifiable([
          '${ClassicHareegActionIds.discardPrefix}${card.id}',
        ]);
      }
      return const [];
    }
    if (isFinalDiscard || setup.tableStrictness.blocksIllegalMoves) {
      return const [];
    }
    // The Strict priced exit returns the unused claimed card to the pile, so
    // it is off the surface when that return would empty the hand.
    if (!claimedCardUsed &&
        !setup.tableStrictness.removesPlayerOnMistake &&
        hand.length <= 2) {
      return const [];
    }
    return List.unmodifiable([
      for (final card in hand)
        if (card.id != claim.claimedCardId &&
            _discardEligibilityFor(
                  seat: _currentSeat,
                  card: card,
                  isFinalDiscard: false,
                ).scenario ==
                ClassicHareegDiscardScenario.normal)
          '${ClassicHareegActionIds.discardPrefix}${card.id}',
    ]);
  }
}

// Global cap on physical meld candidate groups returned from the search.
// Was 8 when the search applied this as a per-branch limit; raised once the
// search switched to a single global cap so sets, sequences, and high-ace
// sequences still each get room to emit their layouts on rich hands.
const _maxPhysicalMeldVariants = 64;
const _maxCpuOpeningMeldOptions = 24;
const _maxCpuOpeningCombinationMelds = 3;
const _debugSlowRuleSearchMs = 120;
const _debugMeldProgressInterval = 64;
const _debugOpeningProgressInterval = 128;
const _debugLargeGroupCount = 48;

void _debugRulesLog(String message) {
  assert(() {
    developer.log(message, name: 'hareeg.rules');
    return true;
  }());
}

String _debugActionSummary(Iterable<String> actionIds) {
  final ids = actionIds.toList(growable: false);
  if (ids.isEmpty) {
    return '[]';
  }
  const maxShown = 5;
  final shown = ids.take(maxShown).join(', ');
  if (ids.length <= maxShown) {
    return '[$shown]';
  }
  return '[$shown, +${ids.length - maxShown} more]';
}

String _playMeldActionIdFor(
  Iterable<String> cardIds,
  List<JokerMeldAssignment> jokerAssignments,
) {
  if (jokerAssignments.isEmpty) {
    return ClassicHareegActionIds.playMeldActionId(cardIds);
  }
  return ClassicHareegActionIds.playMeldWithJokerIdentitiesActionId(
    cardIds: cardIds,
    assignments: jokerAssignments,
  );
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

PlayerSeat _previousAntiClockwise(PlayerSeat seat) {
  return switch (seat) {
    PlayerSeat.south => PlayerSeat.west,
    PlayerSeat.east => PlayerSeat.south,
    PlayerSeat.north => PlayerSeat.east,
    PlayerSeat.west => PlayerSeat.north,
  };
}

/// Sorts a hand by suit + rank with jokers last via null-identity sort.
int _compareCards(HareegCard left, HareegCard right) {
  final leftIdentity = left.effectiveIdentity;
  final rightIdentity = right.effectiveIdentity;
  if (leftIdentity == null && rightIdentity == null) {
    return left.id.compareTo(right.id);
  }
  if (leftIdentity == null) {
    return 1;
  }
  if (rightIdentity == null) {
    return -1;
  }

  final suitCompare = leftIdentity.suit.index.compareTo(
    rightIdentity.suit.index,
  );
  if (suitCompare != 0) {
    return suitCompare;
  }
  return leftIdentity.rank.order.compareTo(rightIdentity.rank.order);
}

/// How a discard attempt exits an active Fifty proof turn.
sealed class _FiftyProofExit {
  const _FiftyProofExit();
}

/// The exit is refused outright; no state changed.
class _FiftyProofExitRefused extends _FiftyProofExit {
  const _FiftyProofExitRefused(this.result);

  /// Failure to surface to the caller.
  final ApplyActionResult result;
}

/// Table tier removed the claimant; the result is final.
class _FiftyProofExitRemoved extends _FiftyProofExit {
  const _FiftyProofExitRemoved(this.result);

  /// Removal result to surface to the caller.
  final ApplyActionResult result;
}

/// Strict tier charged the penalty; the discard proceeds normally.
class _FiftyProofExitPenalized extends _FiftyProofExit {
  const _FiftyProofExitPenalized(this.message);

  /// Penalty toast carried into the discard success message.
  final String message;
}

/// The discard completes a valid proof; the round ends as a Fifty finish.
class _FiftyProofExitProven extends _FiftyProofExit {
  const _FiftyProofExitProven();
}

/// Live state of a Fifty claim being proven by the claimant.
class _ActiveFiftyClaim {
  _ActiveFiftyClaim({
    required this.claimedCardId,
    required this.discarder,
    required this.isFirstDealtRound,
    this.script,
  });

  /// Physical id of the claimed card. It must end the turn used in a meld or
  /// cover and can never leave as the turn's discard.
  final String claimedCardId;

  /// Seat whose discard was claimed — charged the Fifty penalty on success.
  final PlayerSeat discarder;

  /// Whether the claim window carried the first-dealt-round -1 exception.
  final bool isFirstDealtRound;

  /// Ordered proof action ids for CPU play-out. Null until resolved; rebuilt
  /// lazily from the live state (e.g. after a snapshot restore).
  List<String>? script;

  /// Index of the next unplayed script step.
  int scriptIndex = 0;
}

/// Provenance of a windowed discard taken via plain `take-discard` during an
/// open Fifty window. Lets the turn's finish be scored as a Fifty even though
/// the player never pressed `claim-fifty`.
class _WindowedDiscardTake {
  const _WindowedDiscardTake({
    required this.cardId,
    required this.discarder,
    required this.isFirstDealtRound,
  });

  /// Physical id of the taken windowed card. The finish counts as a Fifty only
  /// when this card is actually used in one of the finishing melds.
  final String cardId;

  /// Seat that discarded the windowed card — charged the Fifty penalty.
  final PlayerSeat discarder;

  /// Whether the window carried the first-dealt-round -1 exception.
  final bool isFirstDealtRound;
}

class _ResolvedMeldCards {
  const _ResolvedMeldCards({required this.cards, required this.result});

  final List<HareegCard> cards;
  final MeldValidationResult result;
}

class _ResolvedTablePlay {
  const _ResolvedTablePlay({required this.melds, required this.result});

  final List<PlacedMeld> melds;
  final MeldValidationResult result;
}

class _MeldActionOption {
  const _MeldActionOption({
    required this.cards,
    required this.meld,
    required this.actionId,
    this.jokerAssignments = const [],
  });

  final List<HareegCard> cards;
  final PlacedMeld meld;
  final String actionId;
  final List<JokerMeldAssignment> jokerAssignments;

  Set<String> get cardIds => cards.map((card) => card.id).toSet();
}

/// Live action-surface facts backed by the controller's current state.
class _LiveActionSurfaceFacts implements ClassicHareegActionSurfaceFacts {
  _LiveActionSurfaceFacts(this._controller);

  final ClassicHareegGameController _controller;

  @override
  List<String> playMeldActionIds(PlayerSeat seat, {String? mustUseCardId}) {
    return _controller._playMeldActionIds(seat, mustUseCardId: mustUseCardId);
  }

  @override
  String? firstPlayMeldActionId(PlayerSeat seat, {String? mustUseCardId}) {
    return _controller._firstPlayMeldActionId(
      seat,
      mustUseCardId: mustUseCardId,
    );
  }

  @override
  List<String> replaceJokerActionIds(PlayerSeat seat, {String? mustUseCardId}) {
    return _controller._replaceJokerActionIds(
      seat,
      mustUseCardId: mustUseCardId,
    );
  }

  @override
  List<String> coverActionIds(PlayerSeat seat, {String? mustUseCardId}) {
    return _controller._coverActionIds(seat, mustUseCardId: mustUseCardId);
  }

  @override
  List<String> discardActionIds(PlayerSeat seat) {
    return _controller._discardActionIds(seat);
  }

  @override
  bool canReturnOpeningMelds(PlayerSeat seat) {
    return _controller._tablePlayRetractionPlanFor(seat).shouldAdvertise;
  }

  @override
  bool canReturnPendingDiscard(PlayerSeat seat) {
    return _controller._canReturnPendingDiscard(seat);
  }

  @override
  ClassicHareegDrawDecisionPlan drawDecisionPlan(PlayerSeat seat) {
    return _controller._drawDecisionPlanFor(seat);
  }
}

/// Wraps a facts implementation with per-call stopwatch logging for CPU turns.
class _LoggingActionSurfaceFacts implements ClassicHareegActionSurfaceFacts {
  _LoggingActionSurfaceFacts(this._inner);

  final ClassicHareegActionSurfaceFacts _inner;

  String _label(String category, String? mustUseCardId) {
    return '${mustUseCardId == null ? 'action' : 'pending'} $category';
  }

  List<String> _timeList(
    PlayerSeat seat,
    String label,
    List<String> Function() resolve,
  ) {
    final watch = Stopwatch()..start();
    final ids = resolve();
    _debugRulesLog(
      'cpuActionIdsFor $label seat=${seat.name} '
      'elapsed=${watch.elapsedMilliseconds}ms count=${ids.length}',
    );
    return ids;
  }

  String? _timeFirst(
    PlayerSeat seat,
    String label,
    String? Function() resolve,
  ) {
    final watch = Stopwatch()..start();
    final id = resolve();
    _debugRulesLog(
      'cpuActionIdsFor $label seat=${seat.name} '
      'elapsed=${watch.elapsedMilliseconds}ms hit=${id != null}',
    );
    return id;
  }

  @override
  List<String> playMeldActionIds(PlayerSeat seat, {String? mustUseCardId}) {
    return _timeList(seat, _label('meld-search', mustUseCardId), () {
      return _inner.playMeldActionIds(seat, mustUseCardId: mustUseCardId);
    });
  }

  @override
  String? firstPlayMeldActionId(PlayerSeat seat, {String? mustUseCardId}) {
    return _timeFirst(seat, _label('meld-search', mustUseCardId), () {
      return _inner.firstPlayMeldActionId(seat, mustUseCardId: mustUseCardId);
    });
  }

  @override
  List<String> replaceJokerActionIds(PlayerSeat seat, {String? mustUseCardId}) {
    return _timeList(seat, _label('replace-search', mustUseCardId), () {
      return _inner.replaceJokerActionIds(seat, mustUseCardId: mustUseCardId);
    });
  }

  @override
  List<String> coverActionIds(PlayerSeat seat, {String? mustUseCardId}) {
    return _timeList(seat, _label('cover-search', mustUseCardId), () {
      return _inner.coverActionIds(seat, mustUseCardId: mustUseCardId);
    });
  }

  @override
  List<String> discardActionIds(PlayerSeat seat) {
    return _timeList(seat, 'action discard-search', () {
      return _inner.discardActionIds(seat);
    });
  }

  @override
  bool canReturnOpeningMelds(PlayerSeat seat) {
    return _inner.canReturnOpeningMelds(seat);
  }

  @override
  bool canReturnPendingDiscard(PlayerSeat seat) {
    return _inner.canReturnPendingDiscard(seat);
  }

  @override
  ClassicHareegDrawDecisionPlan drawDecisionPlan(PlayerSeat seat) {
    return _inner.drawDecisionPlan(seat);
  }
}
