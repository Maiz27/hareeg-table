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

export 'classic_hareeg_action.dart';

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
  }) : _now = now ?? DateTime.now,
       setup = round.setup,
       rules = round.rules,
       _hands = {
         for (final entry in round.hands.entries)
           entry.key: List<HareegCard>.of(entry.value),
       },
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
  }

  /// Creates a controller restored from a persisted snapshot.
  factory ClassicHareegGameController.fromSnapshot(
    ClassicHareegMatchSnapshot snapshot, {
    ClassicHareegRules? rules,
    DateTime Function()? now,
  }) {
    return ClassicHareegGameController._fromRestoredMatch(
      ClassicHareegMatchRestoration.fromSnapshot(snapshot, rules: rules),
      now: now,
    );
  }

  ClassicHareegGameController._fromRestoredMatch(
    ClassicHareegRestoredMatchState restored, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       setup = restored.setup,
       rules = restored.rules,
       _hands = restored.hands,
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
    _syncUnlockedBenchmarkWithTable();
    _evaluateRoundEnd();
  }

  /// Setup values used to deal the active round.
  final ClassicHareegSetup setup;

  /// Rules active for this round.
  final ClassicHareegRules rules;

  final DateTime Function() _now;
  final Map<PlayerSeat, List<HareegCard>> _hands;
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

  /// Round number in which seats were eliminated during this controller's
  /// lifetime.
  Map<PlayerSeat, int> get seatEliminatedRound {
    return Map<PlayerSeat, int>.unmodifiable(_seatEliminatedRound);
  }

  /// Full round result once the round has ended.
  RoundProgressResult? get roundResult => _roundResult;

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
      turnLedger: _turnLedger,
    ).toSnapshotState();
    return ClassicHareegMatchSnapshot(
      setup: setup,
      hands: resumeState.hands,
      stock: List<HareegCard>.of(_stock),
      discardPile: List<HareegCard>.of(_discardPile),
      tableMelds: resumeState.tableMelds,
      starter: _starter,
      currentSeat: _currentSeat,
      turnPhase: _phase,
      pendingDiscard: resumeState.pendingDiscard,
      openingState: resumeState.openingState,
      scores: Map<PlayerSeat, int>.of(_scores),
      activeSeats: List<PlayerSeat>.of(_activeSeats),
      roundNumber: _roundNumber,
      removedSeats: _removedSeats.toList(growable: false),
      fiftyWindowOpenedAt: _fiftyWindowOpenedAt,
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
    if (!setup.tableStrictness.cpuMistakesAllowed) {
      final filtered = [
        for (final id in plan.actionIds)
          if (!ClassicHareegActionIds.describe(id).isMistake) id,
      ];
      if (filtered.length != plan.actionIds.length) {
        return finish('${plan.reason}+nomistake', filtered);
      }
    }
    return finish(plan.reason, plan.actionIds);
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
    if (_roundOutcome != null) {
      return const ApplyActionResult.failure('Round has ended.');
    }

    final action = ClassicHareegActionIds.describe(actionId);
    final route = ClassicHareegActionSurfacePlanner.applyRouteFor(action.kind);
    if (route == ClassicHareegActionApplyRoute.directValidation) {
      switch (action.kind) {
        case ClassicHareegActionKind.playMeldWithJoker:
          final jokerChoice = action.jokerMeldChoice!;
          return _applyPlayMeld(
            jokerChoice.cardIds,
            jokerIdentities: {
              for (final assignment in jokerChoice.assignments)
                assignment.jokerId: assignment.identity,
            },
          );
        case ClassicHareegActionKind.playMeld:
          return _applyPlayMeld(action.cardIds);
        case ClassicHareegActionKind.replaceJoker:
          return _applyReplaceJoker(action.jokerReplacementTarget!);
        case ClassicHareegActionKind.placeCover:
          return _applyPlaceCover(action.coverTarget!);
        case ClassicHareegActionKind.returnTablePlay:
          return _applyReturnTablePlay(action.returnTablePlayTarget!);
        case ClassicHareegActionKind.drawStock:
        case ClassicHareegActionKind.takeDiscard:
        case ClassicHareegActionKind.usePendingDiscard:
        case ClassicHareegActionKind.returnPendingDiscard:
        case ClassicHareegActionKind.returnOpeningMelds:
        case ClassicHareegActionKind.claimFifty:
        case ClassicHareegActionKind.discard:
        case ClassicHareegActionKind.discardBlockedCover:
        case ClassicHareegActionKind.discardJoker:
        case ClassicHareegActionKind.unknown:
          break;
      }
    }

    if (!_actionSurfacePlanFor(
      _currentSeat,
      ClassicHareegActionSurfacePurpose.control,
    ).allows(actionId)) {
      return ApplyActionResult.failure(
        'Action "$actionId" is not legal right now.',
      );
    }

    if (route == ClassicHareegActionApplyRoute.controlSurface) {
      switch (action.kind) {
        case ClassicHareegActionKind.drawStock:
          return _applyDrawStock();
        case ClassicHareegActionKind.takeDiscard:
          return _applyTakePreviousDiscard();
        case ClassicHareegActionKind.usePendingDiscard:
          return _applyUsePendingDiscard();
        case ClassicHareegActionKind.returnPendingDiscard:
          return _applyReturnPendingDiscard();
        case ClassicHareegActionKind.returnOpeningMelds:
          return _applyReturnOpeningMelds();
        case ClassicHareegActionKind.claimFifty:
          return _applyClaimFifty();
        case ClassicHareegActionKind.discard:
        case ClassicHareegActionKind.discardBlockedCover:
        case ClassicHareegActionKind.discardJoker:
          return _applyDiscard(action.cardId!);
        case ClassicHareegActionKind.playMeld:
        case ClassicHareegActionKind.playMeldWithJoker:
        case ClassicHareegActionKind.placeCover:
        case ClassicHareegActionKind.replaceJoker:
        case ClassicHareegActionKind.returnTablePlay:
        case ClassicHareegActionKind.unknown:
          break;
      }
    }

    return ApplyActionResult.failure('Unknown action "$actionId".');
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
    _fiftyWindow = null;
    _fiftyWindowOpenedAt = null;
    _turnJournal.resetForNewTurn();
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
    _fiftyWindow = null;
    _fiftyWindowOpenedAt = null;
    _turnJournal.resetForNewTurn(source: FinishCardSource.previousDiscard);
    return const ApplyActionResult.success();
  }

  ApplyActionResult _applyUsePendingDiscard() {
    return const ApplyActionResult.failure(
      'The picked up discard must be used in a meld or cover.',
    );
  }

  ApplyActionResult _applyReturnPendingDiscard() {
    final pending = _pendingDiscard;
    final returningSeat = _currentSeat;
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
    _fiftyWindow = null;
    _fiftyWindowOpenedAt = null;
    _turnJournal.resetForNewTurn();
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

    if (pending != null) {
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
          return _samePhysicalCards(meld.cards, staged.cards);
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
          return _samePhysicalCards(meld.cards, play.meld.cards);
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

    final pending = _pendingDiscard;
    if (pending != null && !target.cardIds.toSet().contains(pending.id)) {
      return const ApplyActionResult.failure(
        'The picked up discard must be used in a meld or returned first.',
      );
    }

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
    final consumedPendingDiscard = pending;
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
    if (pending != null) {
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

    final pending = _pendingDiscard;
    if (pending != null && pending.id != target.cardId) {
      return const ApplyActionResult.failure(
        'The picked up discard must be used before another card.',
      );
    }

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
    if (pending != null) {
      _consumePendingDiscard();
      _turnJournal.clearConsumedPendingDiscard();
    }
    return const ApplyActionResult.success('Joker replaced.');
  }

  ApplyActionResult _applyDiscard(String cardId) {
    final hand = _handFor(_currentSeat);
    final index = hand.indexWhere((card) => card.id == cardId);
    if (index == -1) {
      return ApplyActionResult.failure('Card "$cardId" is not in the hand.');
    }

    final card = hand[index];
    final isFinalDiscard = hand.length == 1;
    final eligibility = _discardEligibilityFor(
      seat: _currentSeat,
      card: card,
      isFinalDiscard: isFinalDiscard,
    );
    if (!eligibility.isAllowed) {
      return ApplyActionResult.failure(eligibility.message);
    }
    final mistake = eligibility.mistakeResolution;
    var successMessage = '';
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
    if (!plan.shouldEndRoundAsDraw) {
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
    final mistake = plan.mistakeResolution;
    if (mistake != null) {
      final removal = _applyMistake(_mistakeConsequencePlan(mistake));
      return removal ?? ApplyActionResult.success(plan.message);
    }

    final finishPlan = plan.finishPlan;
    final claim = plan.claimResult;
    final window = _fiftyWindow;
    if (finishPlan == null || claim == null || window == null) {
      return const ApplyActionResult.failure('No active Fifty discard.');
    }
    _discardPile.removeLast();
    _hands[_currentSeat] = const <HareegCard>[];
    _discardPile.add(finishPlan.finalDiscard);
    _pendingDiscard = null;
    _lastReturnedPendingDiscard = null;
    _finishRound(
      type: RoundOutcomeType.fiftyFinish,
      winner: _currentSeat,
      fiftyDiscarder: window.discarder,
      firstRoundFiftyException: claim.firstRoundException,
    );
    return const ApplyActionResult.success('Fifty claimed.');
  }

  bool _canFinishWithPreviousDiscard(PlayerSeat seat) {
    return _finishPlanWithPreviousDiscard(seat) != null;
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

    final cards = [..._handFor(seat), discarded];
    final planner = ClassicHareegFinishPlanner(cards);
    if (!planner.hasValidMeldContaining(discarded.id)) {
      _previousDiscardFinishCacheKey = cacheKey;
      _previousDiscardFinishCacheValue = false;
      _previousDiscardFinishPlanCacheValue = null;
      return null;
    }
    final plan = ClassicHareegFiftyClaimPlanner.finishPlanForClaim(
      hand: _handFor(seat),
      discarded: discarded,
      playerOpened: _openingState.hasOpened(seat),
      planner: planner,
    );
    _previousDiscardFinishCacheKey = cacheKey;
    _previousDiscardFinishCacheValue = plan != null;
    _previousDiscardFinishPlanCacheValue = plan;
    return plan;
  }

  String _previousDiscardFinishKey(PlayerSeat seat, HareegCard discarded) {
    final handIds = _handFor(seat).map(_cardCacheIdentity).toList()..sort();
    return [
      seat.name,
      _cardCacheIdentity(discarded),
      _phase.name,
      '${_stock.length}',
      '${_discardPile.length}',
      '${_openingState.hasOpened(seat)}',
      handIds.join(','),
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
      pendingDiscardId: seat == _currentSeat ? _pendingDiscard?.id : null,
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

bool _samePhysicalCards(List<HareegCard> left, List<HareegCard> right) {
  if (left.length != right.length) {
    return false;
  }
  final leftIds = left.map((card) => card.id).toList()..sort();
  final rightIds = right.map((card) => card.id).toList()..sort();
  for (var index = 0; index < leftIds.length; index += 1) {
    if (leftIds[index] != rightIds[index]) {
      return false;
    }
  }
  return true;
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
  ClassicHareegDrawDecisionPlan drawDecisionPlan(PlayerSeat seat) {
    return _inner.drawDecisionPlan(seat);
  }
}
