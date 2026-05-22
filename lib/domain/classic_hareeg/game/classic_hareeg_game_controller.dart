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
import '../rules/meld_validator.dart';
import '../rules/mistake_preset_rules.dart';
import '../rules/opening_rules.dart';
import 'classic_hareeg_action.dart';
import 'classic_hareeg_finish_planner.dart';
import 'classic_hareeg_match_flow.dart';
import 'classic_hareeg_match_restoration.dart';
import 'classic_hareeg_match_snapshot.dart';
import 'classic_hareeg_round.dart';
import 'classic_hareeg_table_play_planner.dart';

export 'classic_hareeg_action.dart';

/// Outcome of applying an action through the controller.
class ApplyActionResult {
  /// Creates an apply-action result.
  const ApplyActionResult({required this.isSuccess, required this.message});

  /// Successful result.
  const ApplyActionResult.success([this.message = '']) : isSuccess = true;

  /// Failed result with a player-facing explanation.
  const ApplyActionResult.failure(this.message) : isSuccess = false;

  /// Whether the action was accepted and applied.
  final bool isSuccess;

  /// Player-facing explanation for blocked or rejected actions.
  final String message;
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
       _starter = round.starter,
       _currentSeat = round.currentSeat,
       _phase = round.turnPhase,
       _pendingDiscard = null,
       _previousDiscardSeat = null,
       _fiftyWindow = null,
       _fiftyWindowOpenedAt = null,
       _roundOutcome = null,
       _roundResult = null,
       _turnFinishPlays = <PlacedMeld>[],
       _turnOpeningMelds = <PlacedMeld>[],
       _turnMeldPlays = <_TurnMeldPlay>[],
       _turnCoverPlays = <_TurnCoverPlay>[],
       _turnConsumedPendingDiscard = null,
       _turnSource = FinishCardSource.stock {
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
       _starter = restored.starter,
       _currentSeat = restored.currentSeat,
       _phase = restored.turnPhase,
       _pendingDiscard = restored.pendingDiscard,
       _previousDiscardSeat = restored.previousDiscardSeat,
       _fiftyWindow = restored.fiftyWindow,
       _fiftyWindowOpenedAt = restored.fiftyWindowOpenedAt,
       _roundOutcome = null,
       _roundResult = null,
       _turnFinishPlays = <PlacedMeld>[],
       _turnOpeningMelds = <PlacedMeld>[],
       _turnMeldPlays = <_TurnMeldPlay>[],
       _turnCoverPlays = <_TurnCoverPlay>[],
       _turnConsumedPendingDiscard = null,
       _turnSource = restored.turnSource {
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
  final PlayerSeat _starter;
  PlayerSeat _currentSeat;
  TurnPhase _phase;
  HareegCard? _pendingDiscard;
  PlayerSeat? _previousDiscardSeat;
  FiftyClaimWindow? _fiftyWindow;
  DateTime? _fiftyWindowOpenedAt;
  RoundOutcomeType? _roundOutcome;
  RoundProgressResult? _roundResult;
  List<PlacedMeld> _turnFinishPlays;
  List<PlacedMeld> _turnOpeningMelds;
  List<_TurnMeldPlay> _turnMeldPlays;
  List<_TurnCoverPlay> _turnCoverPlays;
  HareegCard? _turnConsumedPendingDiscard;
  FinishCardSource _turnSource;
  String? _previousDiscardFinishCacheKey;
  bool? _previousDiscardFinishCacheValue;

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

  /// Match scores before the current round result is applied.
  Map<PlayerSeat, int> get scores => Map.unmodifiable(_scores);

  /// Seats still active in the match.
  List<PlayerSeat> get activeSeats => List.unmodifiable(_activeSeats);

  /// Opening benchmark state for the active round.
  OpeningState get openingState => _openingState;

  /// One-based dealt round number.
  int get roundNumber => _roundNumber;

  /// Full round result once the round has ended.
  RoundProgressResult? get roundResult => _roundResult;

  /// Match progress produced by the completed round, if any.
  MatchProgressState? get roundProgress => _matchFlow.progressFor(_roundResult);

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
    return ClassicHareegMatchSnapshot(
      setup: setup,
      hands: {
        for (final entry in _hands.entries)
          entry.key: List<HareegCard>.of(entry.value),
      },
      stock: List<HareegCard>.of(_stock),
      discardPile: List<HareegCard>.of(_discardPile),
      tableMelds: {
        for (final entry in _tableMelds.entries)
          entry.key: List<PlacedMeld>.of(entry.value),
      },
      starter: _starter,
      currentSeat: _currentSeat,
      turnPhase: _phase,
      pendingDiscard: _pendingDiscard,
      openingState: _openingState,
      scores: Map<PlayerSeat, int>.of(_scores),
      activeSeats: List<PlayerSeat>.of(_activeSeats),
      roundNumber: _roundNumber,
      removedSeats: _removedSeats.toList(growable: false),
      fiftyWindowOpenedAt: _fiftyWindowOpenedAt,
      savedAt: effectiveSavedAt,
    );
  }

  /// Deals the next round snapshot after this round has produced progress.
  ClassicHareegMatchSnapshot? nextRoundSnapshot({DateTime? savedAt}) {
    return _matchFlow.nextRoundSnapshotFor(
      roundResult: _roundResult,
      savedAt: savedAt,
    );
  }

  /// Returns the legal action ids for [seat] under the current state.
  ///
  /// Empty when the round has ended, when it is not the seat's turn, or when
  /// the seat has no legal action remaining (e.g. stock exhaustion that the
  /// controller has not yet converted to a [RoundOutcomeType.draw] outcome).
  List<String> legalActionIdsFor(PlayerSeat seat) {
    if (_roundOutcome != null ||
        seat != _currentSeat ||
        !_roundActiveSeats.contains(seat)) {
      return const [];
    }

    if (_pendingDiscard != null) {
      final ids = <String>[
        ..._playMeldActionIds(seat, mustUseCardId: _pendingDiscard!.id),
        ..._replaceJokerActionIds(seat, mustUseCardId: _pendingDiscard!.id),
        ..._coverActionIds(seat, mustUseCardId: _pendingDiscard!.id),
        ClassicHareegActionIds.returnPendingDiscard,
      ];
      return List.unmodifiable(ids);
    }

    if (_phase == TurnPhase.action) {
      return List.unmodifiable([
        if (_canReturnOpeningMelds(seat))
          ClassicHareegActionIds.returnOpeningMelds,
        ..._playMeldActionIds(seat),
        ..._replaceJokerActionIds(seat),
        ..._coverActionIds(seat),
        ..._discardActionIds(seat),
      ]);
    }

    final ids = <String>[];
    if (_canClaimFifty(seat)) {
      ids.add(ClassicHareegActionIds.claimFifty);
    }
    if (_stock.isNotEmpty) {
      ids.add(ClassicHareegActionIds.drawStock);
    }
    if (_canTakePreviousDiscard &&
        (_stock.isNotEmpty || _canFinishWithPreviousDiscard(seat))) {
      ids.add(ClassicHareegActionIds.takeDiscard);
    }
    return List.unmodifiable(ids);
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

    if (_roundOutcome != null ||
        seat != _currentSeat ||
        !_roundActiveSeats.contains(seat)) {
      return finish('inactive', const []);
    }

    if (_pendingDiscard != null) {
      final meldWatch = Stopwatch()..start();
      final playMeld = _firstPlayMeldActionId(
        seat,
        mustUseCardId: _pendingDiscard!.id,
      );
      _debugRulesLog(
        'cpuActionIdsFor pending meld-search seat=${seat.name} '
        'elapsed=${meldWatch.elapsedMilliseconds}ms hit=${playMeld != null}',
      );
      if (playMeld != null) {
        return finish('pending-meld', [playMeld]);
      }

      final replaceWatch = Stopwatch()..start();
      final replace = _replaceJokerActionIds(
        seat,
        mustUseCardId: _pendingDiscard!.id,
      );
      _debugRulesLog(
        'cpuActionIdsFor pending replace-search seat=${seat.name} '
        'elapsed=${replaceWatch.elapsedMilliseconds}ms count=${replace.length}',
      );
      if (replace.isNotEmpty) {
        return finish('pending-replace', [replace.first]);
      }

      final coverWatch = Stopwatch()..start();
      final cover = _coverActionIds(seat, mustUseCardId: _pendingDiscard!.id);
      _debugRulesLog(
        'cpuActionIdsFor pending cover-search seat=${seat.name} '
        'elapsed=${coverWatch.elapsedMilliseconds}ms count=${cover.length}',
      );
      if (cover.isNotEmpty) {
        return finish('pending-cover', [cover.first]);
      }

      return finish('pending-return', [
        ClassicHareegActionIds.returnPendingDiscard,
      ]);
    }

    if (_phase == TurnPhase.action) {
      final ids = <String>[];
      final meldWatch = Stopwatch()..start();
      final playMeld = _firstPlayMeldActionId(seat);
      _debugRulesLog(
        'cpuActionIdsFor action meld-search seat=${seat.name} '
        'elapsed=${meldWatch.elapsedMilliseconds}ms hit=${playMeld != null}',
      );
      if (playMeld != null) {
        ids.add(playMeld);
      }
      final replaceWatch = Stopwatch()..start();
      final replace = _replaceJokerActionIds(seat);
      _debugRulesLog(
        'cpuActionIdsFor action replace-search seat=${seat.name} '
        'elapsed=${replaceWatch.elapsedMilliseconds}ms count=${replace.length}',
      );
      if (replace.isNotEmpty) {
        ids.add(replace.first);
      }
      final coverWatch = Stopwatch()..start();
      final cover = _coverActionIds(seat);
      _debugRulesLog(
        'cpuActionIdsFor action cover-search seat=${seat.name} '
        'elapsed=${coverWatch.elapsedMilliseconds}ms count=${cover.length}',
      );
      if (cover.isNotEmpty) {
        ids.add(cover.first);
      }
      final discardWatch = Stopwatch()..start();
      ids.addAll(_discardActionIds(seat));
      _debugRulesLog(
        'cpuActionIdsFor action discard-search seat=${seat.name} '
        'elapsed=${discardWatch.elapsedMilliseconds}ms total=${ids.length}',
      );
      return finish('action', ids);
    }

    final ids = <String>[];
    if (_canClaimFifty(seat)) {
      ids.add(ClassicHareegActionIds.claimFifty);
    }
    if (_stock.isNotEmpty) {
      ids.add(ClassicHareegActionIds.drawStock);
    }
    if (_canTakePreviousDiscard &&
        (_stock.isNotEmpty || _canFinishWithPreviousDiscard(seat))) {
      ids.add(ClassicHareegActionIds.takeDiscard);
    }
    return finish('draw', ids);
  }

  /// Returns only the cheap table-control actions needed by the human UI.
  ///
  /// Meld, cover, and joker-replacement actions are validated from the current
  /// selection when the user invokes them, so the frame build does not need to
  /// enumerate every possible table play.
  List<String> controlActionIdsFor(PlayerSeat seat) {
    if (_roundOutcome != null ||
        seat != _currentSeat ||
        !_roundActiveSeats.contains(seat)) {
      return const [];
    }

    if (_pendingDiscard != null) {
      return List.unmodifiable([ClassicHareegActionIds.returnPendingDiscard]);
    }

    if (_phase == TurnPhase.action) {
      return List.unmodifiable([
        if (_canReturnOpeningMelds(seat))
          ClassicHareegActionIds.returnOpeningMelds,
        ..._discardActionIds(seat),
      ]);
    }

    final ids = <String>[];
    if (_canClaimFifty(seat)) {
      ids.add(ClassicHareegActionIds.claimFifty);
    }
    if (_stock.isNotEmpty) {
      ids.add(ClassicHareegActionIds.drawStock);
    }
    if (_canTakePreviousDiscard &&
        (_stock.isNotEmpty || _canFinishWithPreviousDiscard(seat))) {
      ids.add(ClassicHareegActionIds.takeDiscard);
    }
    return List.unmodifiable(ids);
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

    final jokerChoice = ClassicHareegActionIds.jokerMeldChoice(actionId);
    if (jokerChoice != null) {
      return _applyPlayMeld(
        jokerChoice.cardIds,
        jokerIdentities: {
          for (final assignment in jokerChoice.assignments)
            assignment.jokerId: assignment.identity,
        },
      );
    }

    final meldCardIds = ClassicHareegActionIds.meldCardIds(actionId);
    if (meldCardIds != null) {
      return _applyPlayMeld(meldCardIds);
    }

    final jokerReplacement = ClassicHareegActionIds.jokerReplacementTarget(
      actionId,
    );
    if (jokerReplacement != null) {
      return _applyReplaceJoker(jokerReplacement);
    }

    final coverTarget = ClassicHareegActionIds.coverActionTarget(actionId);
    if (coverTarget != null) {
      return _applyPlaceCover(coverTarget);
    }

    final returnTarget = ClassicHareegActionIds.returnTablePlayTarget(actionId);
    if (returnTarget != null) {
      return _applyReturnTablePlay(returnTarget);
    }

    if (!controlActionIdsFor(_currentSeat).contains(actionId)) {
      return ApplyActionResult.failure(
        'Action "$actionId" is not legal right now.',
      );
    }

    switch (actionId) {
      case ClassicHareegActionIds.drawStock:
        return _applyDrawStock();
      case ClassicHareegActionIds.takeDiscard:
        return _applyTakePreviousDiscard();
      case ClassicHareegActionIds.usePendingDiscard:
        return _applyUsePendingDiscard();
      case ClassicHareegActionIds.returnPendingDiscard:
        return _applyReturnPendingDiscard();
      case ClassicHareegActionIds.returnOpeningMelds:
        return _applyReturnOpeningMelds();
      case ClassicHareegActionIds.claimFifty:
        return _applyClaimFifty();
    }

    final discardCardId = ClassicHareegActionIds.discardCardId(actionId);
    if (discardCardId != null) {
      return _applyDiscard(discardCardId);
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
  }) {
    return _tablePlayPlanner.coverActionIdForMeldTarget(
      seat: seat,
      cardIds: cardIds,
      targetSeat: targetSeat,
      meldIndex: meldIndex,
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
    final drawn = _stock.removeLast();
    _handFor(_currentSeat).add(drawn);
    _phase = TurnPhase.action;
    _pendingDiscard = null;
    _fiftyWindow = null;
    _fiftyWindowOpenedAt = null;
    _turnFinishPlays = <PlacedMeld>[];
    _turnOpeningMelds = <PlacedMeld>[];
    _turnMeldPlays = <_TurnMeldPlay>[];
    _turnCoverPlays = <_TurnCoverPlay>[];
    _turnConsumedPendingDiscard = null;
    _turnSource = FinishCardSource.stock;
    return const ApplyActionResult.success();
  }

  ApplyActionResult _applyTakePreviousDiscard() {
    final card = _discardPile.removeLast();
    _handFor(_currentSeat).add(card);
    _pendingDiscard = card;
    _phase = TurnPhase.action;
    _fiftyWindow = null;
    _fiftyWindowOpenedAt = null;
    _turnFinishPlays = <PlacedMeld>[];
    _turnOpeningMelds = <PlacedMeld>[];
    _turnMeldPlays = <_TurnMeldPlay>[];
    _turnCoverPlays = <_TurnCoverPlay>[];
    _turnConsumedPendingDiscard = null;
    _turnSource = FinishCardSource.previousDiscard;
    return const ApplyActionResult.success();
  }

  ApplyActionResult _applyUsePendingDiscard() {
    return const ApplyActionResult.failure(
      'The picked up discard must be used in a meld or cover.',
    );
  }

  ApplyActionResult _applyReturnPendingDiscard() {
    final pending = _pendingDiscard!;
    final hand = _handFor(_currentSeat);
    final pendingIndex = hand.indexWhere((card) => card.id == pending.id);
    if (pendingIndex == -1) {
      return const ApplyActionResult.failure(
        'Pending discard is not in the player hand.',
      );
    }
    hand.removeAt(pendingIndex);
    _discardPile.add(pending);
    _pendingDiscard = null;
    _phase = TurnPhase.draw;
    _fiftyWindow = null;
    _fiftyWindowOpenedAt = null;
    _turnFinishPlays = <PlacedMeld>[];
    _turnOpeningMelds = <PlacedMeld>[];
    _turnMeldPlays = <_TurnMeldPlay>[];
    _turnCoverPlays = <_TurnCoverPlay>[];
    _turnConsumedPendingDiscard = null;
    _turnSource = FinishCardSource.stock;
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
    if (pending != null && !uniqueIds.contains(pending.id)) {
      return const ApplyActionResult.failure(
        'The picked up discard must be used in a meld or returned first.',
      );
    }

    final resolved = _resolveTablePlay(
      selectedCards,
      jokerId: jokerId,
      jokerIdentity: jokerIdentity,
      jokerIdentities: jokerIdentities,
    );
    if (!resolved.result.isValid) {
      return ApplyActionResult.failure(resolved.result.message);
    }

    final projectedHandCount = hand.length - uniqueIds.length;
    if (projectedHandCount == 0) {
      return const ApplyActionResult.failure(
        'A finish needs one final discard.',
      );
    }
    final alreadyOpened = _openingState.hasOpened(_currentSeat);
    var message = 'Meld played.';

    for (final id in uniqueIds) {
      hand.removeWhere((card) => card.id == id);
    }
    _tableMelds
        .putIfAbsent(_currentSeat, () => <PlacedMeld>[])
        .addAll(resolved.melds);
    _turnFinishPlays = [..._turnFinishPlays, ...resolved.melds];

    if (alreadyOpened) {
      final value = resolved.melds.fold<int>(
        0,
        (total, meld) => total + meld.valueSnapshot,
      );
      _turnMeldPlays = [
        ..._turnMeldPlays,
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
      ];
      _openingState = ClassicHareegOpeningRules.recordBenchmarkContribution(
        state: _openingState,
        seat: _currentSeat,
        value: value,
      );
      _syncUnlockedBenchmarkWithTable();
    } else {
      _turnOpeningMelds = [..._turnOpeningMelds, ...resolved.melds];
      final opening = ClassicHareegOpeningRules.validateOpening(
        state: _openingState,
        seat: _currentSeat,
        melds: _turnOpeningMelds,
      );
      if (opening.isValid) {
        _openingState = ClassicHareegOpeningRules.applyOpening(
          state: _openingState,
          seat: _currentSeat,
          melds: _turnOpeningMelds,
        );
        _turnOpeningMelds = <PlacedMeld>[];
        _turnConsumedPendingDiscard = null;
        _syncUnlockedBenchmarkWithTable();
        message = 'Opened at ${opening.value}. Select one card to discard.';
      } else {
        message =
            'Opening ${opening.value}/${_openingState.currentRequirement}. '
            'Add more melds.';
        if (projectedHandCount == 1) {
          message =
              'Opening ${opening.value}/'
              '${_openingState.currentRequirement}. Discard to finish.';
        }
      }
    }

    if (pending != null) {
      _pendingDiscard = null;
      if (!alreadyOpened && !_openingState.hasOpened(_currentSeat)) {
        _turnConsumedPendingDiscard = pending;
      }
    }
    return ApplyActionResult.success(message);
  }

  bool _canReturnOpeningMelds(PlayerSeat seat) {
    if (seat != _currentSeat || _phase != TurnPhase.action) {
      return false;
    }
    if (!_openingState.hasOpened(seat) && _turnOpeningMelds.isNotEmpty) {
      return true;
    }
    return _canReturnTurnMelds(seat) || _canReturnTurnCovers(seat);
  }

  bool _canReturnTurnMelds(PlayerSeat seat) {
    return seat == _currentSeat &&
        _phase == TurnPhase.action &&
        setup.rulePreset != RulePreset.hardTable17 &&
        _turnMeldPlays.isNotEmpty;
  }

  bool _canReturnTurnCovers(PlayerSeat seat) {
    return seat == _currentSeat &&
        _phase == TurnPhase.action &&
        setup.rulePreset != RulePreset.hardTable17 &&
        _turnCoverPlays.isNotEmpty;
  }

  /// Returns whether a specific placed meld is one of this turn's reversible
  /// table plays.
  bool canReturnTablePlayFromMeld(PlayerSeat owner, int meldIndex) {
    if (!_canReturnOpeningMelds(_currentSeat)) {
      return false;
    }

    if (_canReturnTurnCovers(_currentSeat) &&
        _turnCoverPlays.any(
          (play) => play.targetSeat == owner && play.meldIndex == meldIndex,
        )) {
      return true;
    }

    final melds = _tableMelds[owner] ?? const <PlacedMeld>[];
    if (meldIndex < 0 || meldIndex >= melds.length) {
      return false;
    }
    final meld = melds[meldIndex];
    if (_canReturnTurnMelds(_currentSeat) &&
        owner == _currentSeat &&
        _turnMeldPlays.any(
          (play) => _samePhysicalCards(play.meld.cards, meld.cards),
        )) {
      return true;
    }

    if (_openingState.hasOpened(_currentSeat) ||
        owner != _currentSeat ||
        _turnOpeningMelds.isEmpty) {
      return false;
    }
    return _turnOpeningMelds.any((staged) {
      return _samePhysicalCards(meld.cards, staged.cards);
    });
  }

  ApplyActionResult _applyReturnOpeningMelds() {
    if (!_canReturnOpeningMelds(_currentSeat)) {
      return const ApplyActionResult.failure(
        'There are no uncommitted table plays to take back.',
      );
    }

    final stagedMelds = List<PlacedMeld>.of(_turnOpeningMelds);
    final turnMeldPlays = List<_TurnMeldPlay>.of(_turnMeldPlays);
    final coverPlays = List<_TurnCoverPlay>.of(_turnCoverPlays);
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
      _removeTurnFinishPlay(meld);
    }
    for (final play in turnMeldPlays) {
      for (final card in play.meld.cards) {
        hand.add(card.isJoker ? card.withoutRepresentation() : card);
      }
      _removeTurnFinishPlay(play.meld);
    }

    HareegCard? restoredPending = _turnConsumedPendingDiscard;
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
      _removeTurnFinishPlay(play.coverMeld);
      _openingState = play.previousOpeningState;
      restoredPending = play.consumedPendingDiscard ?? restoredPending;
    }

    for (final play in coverPlays) {
      for (final card in play.coverMeld.cards) {
        hand.add(card.isJoker ? card.withoutRepresentation() : card);
      }
    }

    _turnOpeningMelds = <PlacedMeld>[];
    _turnMeldPlays = <_TurnMeldPlay>[];
    _turnCoverPlays = <_TurnCoverPlay>[];
    _syncUnlockedBenchmarkWithTable(allowLower: true);
    _pendingDiscard = restoredPending;
    _turnConsumedPendingDiscard = null;
    _turnSource = _pendingDiscard == null
        ? FinishCardSource.stock
        : FinishCardSource.previousDiscard;
    final meldsReturned = stagedMelds.isNotEmpty || turnMeldPlays.isNotEmpty;
    final message = meldsReturned && coverPlays.isNotEmpty
        ? 'Table plays returned to your hand.'
        : coverPlays.isNotEmpty
        ? 'Covers returned to your hand.'
        : turnMeldPlays.isNotEmpty
        ? 'Melds returned to your hand.'
        : 'Opening melds returned to your hand.';
    return ApplyActionResult.success(message);
  }

  ApplyActionResult _applyReturnTablePlay(ReturnTablePlayTarget target) {
    if (!canReturnTablePlayFromMeld(target.owner, target.meldIndex)) {
      return const ApplyActionResult.failure(
        'That table play cannot be taken back right now.',
      );
    }

    final coverPlays = _turnCoverPlays
        .where(
          (play) =>
              play.targetSeat == target.owner &&
              play.meldIndex == target.meldIndex,
        )
        .toList(growable: false);
    if (coverPlays.isNotEmpty) {
      return _applyReturnCoverPlays(target, coverPlays);
    }

    final turnMeldPlay = _turnMeldPlayForTarget(target);
    if (turnMeldPlay != null) {
      return _applyReturnTurnMeld(target, turnMeldPlay);
    }

    return _applyReturnOpeningMeld(target);
  }

  _TurnMeldPlay? _turnMeldPlayForTarget(ReturnTablePlayTarget target) {
    if (!_canReturnTurnMelds(_currentSeat) || target.owner != _currentSeat) {
      return null;
    }
    final tableMelds = _tableMelds[target.owner];
    if (tableMelds == null ||
        target.meldIndex < 0 ||
        target.meldIndex >= tableMelds.length) {
      return null;
    }
    final tableMeld = tableMelds[target.meldIndex];
    for (final play in _turnMeldPlays) {
      if (play.owner == target.owner &&
          _samePhysicalCards(play.meld.cards, tableMeld.cards)) {
        return play;
      }
    }
    return null;
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
    _removeTurnFinishPlay(play.meld);
    _turnMeldPlays = _turnMeldPlays
        .where((candidate) => !identical(candidate, play))
        .toList(growable: false);
    _syncUnlockedBenchmarkWithTable(allowLower: true);
    final consumed = play.consumedPendingDiscard;
    if (consumed != null) {
      _pendingDiscard = consumed;
      _turnSource = FinishCardSource.previousDiscard;
    }
    return const ApplyActionResult.success('Melds returned to your hand.');
  }

  ApplyActionResult _applyReturnOpeningMeld(ReturnTablePlayTarget target) {
    if (_openingState.hasOpened(_currentSeat) ||
        target.owner != _currentSeat ||
        _turnOpeningMelds.isEmpty) {
      return const ApplyActionResult.failure(
        'That opening meld cannot be taken back right now.',
      );
    }

    final tableMelds = _tableMelds[target.owner];
    if (tableMelds == null ||
        target.meldIndex < 0 ||
        target.meldIndex >= tableMelds.length) {
      return const ApplyActionResult.failure(
        'That meld is no longer on table.',
      );
    }

    final tableMeld = tableMelds[target.meldIndex];
    final stagedIndex = _turnOpeningMelds.indexWhere((staged) {
      return _samePhysicalCards(staged.cards, tableMeld.cards);
    });
    if (stagedIndex == -1) {
      return const ApplyActionResult.failure(
        'That opening meld cannot be taken back right now.',
      );
    }

    final staged = _turnOpeningMelds[stagedIndex];
    tableMelds.removeAt(target.meldIndex);
    final hand = _handFor(_currentSeat);
    for (final card in staged.cards) {
      hand.add(card.isJoker ? card.withoutRepresentation() : card);
    }
    _removeTurnFinishPlay(staged);
    _turnOpeningMelds = [
      ..._turnOpeningMelds.take(stagedIndex),
      ..._turnOpeningMelds.skip(stagedIndex + 1),
    ];

    final consumed = _turnConsumedPendingDiscard;
    if (consumed != null &&
        staged.cards.any((card) => card.id == consumed.id)) {
      _pendingDiscard = consumed;
      _turnConsumedPendingDiscard = null;
      _turnSource = FinishCardSource.previousDiscard;
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
      _removeTurnFinishPlay(play.coverMeld);
      restoredPending = play.consumedPendingDiscard ?? restoredPending;
    }
    for (final play in coverPlays) {
      for (final card in play.coverMeld.cards) {
        hand.add(card.isJoker ? card.withoutRepresentation() : card);
      }
    }

    _turnCoverPlays = _turnCoverPlays
        .where(
          (play) =>
              play.targetSeat != target.owner ||
              play.meldIndex != target.meldIndex,
        )
        .toList(growable: false);
    _syncUnlockedBenchmarkWithTable(allowLower: true);
    if (restoredPending != null) {
      _pendingDiscard = restoredPending;
      _turnSource = FinishCardSource.previousDiscard;
    }
    return const ApplyActionResult.success('Covers returned to your hand.');
  }

  void _removeTurnFinishPlay(PlacedMeld play) {
    final index = _turnFinishPlays.lastIndexWhere((meld) {
      return _samePhysicalCards(meld.cards, play.cards);
    });
    if (index != -1) {
      _turnFinishPlays.removeAt(index);
    }
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
      candidates: selectedCards,
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
    _turnFinishPlays = [..._turnFinishPlays, coverMeld];
    _openingState = ClassicHareegOpeningRules.recordBenchmarkContribution(
      state: _openingState,
      seat: _currentSeat,
      value: coverValue,
    );
    _syncUnlockedBenchmarkWithTable();
    _turnCoverPlays = [
      ..._turnCoverPlays,
      _TurnCoverPlay(
        targetSeat: target.targetSeat,
        meldIndex: target.meldIndex,
        previousMeld: targetMeld,
        coverMeld: coverMeld,
        previousOpeningState: previousOpeningState,
        consumedPendingDiscard: consumedPendingDiscard,
      ),
    ];
    if (pending != null) {
      _pendingDiscard = null;
      _turnConsumedPendingDiscard = null;
    }
    return const ApplyActionResult.success('Cover placed.');
  }

  void _syncUnlockedBenchmarkWithTable({bool allowLower = false}) {
    final owner = _openingState.benchmarkOwner;
    if (owner == null || _openingState.isLocked) {
      return;
    }

    final ownerTableTotal = (_tableMelds[owner] ?? const <PlacedMeld>[])
        .fold<int>(0, (total, meld) => total + meld.totalValue);
    final tableRequirement = ownerTableTotal > _openingState.baseRequirement
        ? ownerTableTotal
        : _openingState.baseRequirement;
    if (tableRequirement == _openingState.currentRequirement ||
        (!allowLower && tableRequirement < _openingState.currentRequirement)) {
      return;
    }

    _openingState = OpeningState(
      baseRequirement: _openingState.baseRequirement,
      currentRequirement: tableRequirement,
      benchmarkOwner: owner,
      openedSeats: _openingState.openedSeats,
    );
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
      final mistake = _resolveMistake(MistakeType.wrongJokerReplacement);
      if (mistake == null) {
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
      _pendingDiscard = null;
      _turnConsumedPendingDiscard = null;
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
    if (!ClassicHareegJokerRules.canDiscard(
      card,
      isFinalDiscard: isFinalDiscard,
    )) {
      return const ApplyActionResult.failure(
        'Jokers cannot be discarded during normal play.',
      );
    }

    final coverResult = ClassicHareegCoverRules.canDiscard(
      tableMelds: _tableMeldCardLists,
      candidate: card,
      isFinalDiscard: isFinalDiscard,
    );
    if (!coverResult.canDiscard) {
      final mistake = _resolveMistake(MistakeType.illegalCoverDiscard);
      if (mistake == null) {
        return ApplyActionResult.failure(coverResult.message);
      }
      final removal = _applyMistake(mistake);
      if (removal != null) {
        return removal;
      }
    }

    final blocksJokerReplacement =
        !isFinalDiscard &&
        _replacementActionIdForCardId(_currentSeat, card.id) != null;
    if (blocksJokerReplacement) {
      final mistake = _resolveMistake(MistakeType.illegalCoverDiscard);
      if (mistake == null) {
        return const ApplyActionResult.failure(
          'This card can replace a table joker and cannot be discarded normally.',
        );
      }
      final removal = _applyMistake(mistake);
      if (removal != null) {
        return removal;
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
    _previousDiscardSeat = _currentSeat;
    _pendingDiscard = null;
    _turnConsumedPendingDiscard = null;
    _fiftyWindow = ClassicHareegFiftyRules.openWindow(
      discarder: _currentSeat,
      claimant: isFinalDiscard ? null : _nextActiveSeat(_currentSeat),
      discardedCard: card,
      durationSeconds: setup.fiftyTimerSeconds,
      isFirstDealtRound: _roundNumber == 1,
    );
    _fiftyWindowOpenedAt = _now();
    if (isFinalDiscard) {
      _finishRound(type: RoundOutcomeType.normalFinish, winner: _currentSeat);
    } else {
      _currentSeat = _nextActiveSeat(_currentSeat);
      _phase = TurnPhase.draw;
      _turnFinishPlays = <PlacedMeld>[];
      _turnOpeningMelds = <PlacedMeld>[];
      _turnMeldPlays = <_TurnMeldPlay>[];
      _turnCoverPlays = <_TurnCoverPlay>[];
      _turnConsumedPendingDiscard = null;
      _turnSource = FinishCardSource.stock;
      _evaluateRoundEnd();
    }
    return const ApplyActionResult.success();
  }

  List<HareegCard> _handFor(PlayerSeat seat) {
    return _hands.putIfAbsent(seat, () => <HareegCard>[]);
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

    final previousDiscardCanFinish = _stock.isEmpty && _canTakePreviousDiscard;
    final pickupWouldFinish =
        previousDiscardCanFinish && _canFinishWithPreviousDiscard(_currentSeat);
    final exhaustion = ClassicHareegFinishRules.evaluateStockExhaustion(
      stockIsEmpty: _stock.isEmpty,
      previousDiscardCanFinish: previousDiscardCanFinish,
      pickupWouldFinish: pickupWouldFinish,
    );
    if (exhaustion.decision == StockExhaustionDecision.roundDraw) {
      _finishRound(type: RoundOutcomeType.draw);
    }
  }

  bool get _canTakePreviousDiscard {
    final previousSeat = _previousDiscardSeat;
    return _phase == TurnPhase.draw &&
        previousSeat != null &&
        _discardPile.isNotEmpty &&
        _nextActiveSeat(previousSeat) == _currentSeat;
  }

  List<PlayerSeat> get _roundActiveSeats {
    return [
      for (final seat in _activeSeats)
        if (!_removedSeats.contains(seat)) seat,
    ];
  }

  List<PlayerSeat> get _roundScoringSeats => [
    for (final seat in _activeSeats)
      if (!_removedSeats.contains(seat)) seat,
  ];

  PlayerSeat _nextActiveSeat(PlayerSeat seat) {
    final seats = _roundActiveSeats;
    if (seats.isEmpty) {
      return seat.nextAntiClockwise;
    }

    var next = seat.nextAntiClockwise;
    while (next != seat) {
      if (seats.contains(next)) {
        return next;
      }
      next = next.nextAntiClockwise;
    }
    return seat;
  }

  MistakeResolution? _resolveMistake(MistakeType mistake) {
    final resolution = ClassicHareegMistakePresetRules.resolve(
      preset: setup.rulePreset,
      mistake: mistake,
    );
    return resolution.isAllowed ? resolution : null;
  }

  ApplyActionResult? _applyMistake(MistakeResolution resolution) {
    _scores[_currentSeat] =
        (_scores[_currentSeat] ?? 0) + resolution.penaltyPoints;
    if (!resolution.removeFromRound) {
      return null;
    }

    final removedSeat = _currentSeat;
    final pending = _pendingDiscard;
    if (pending != null) {
      _handFor(removedSeat).removeWhere((card) => card.id == pending.id);
      _discardPile.add(pending);
    }
    _pendingDiscard = null;
    _fiftyWindow = null;
    _fiftyWindowOpenedAt = null;
    _turnFinishPlays = <PlacedMeld>[];
    _turnOpeningMelds = <PlacedMeld>[];
    _turnMeldPlays = <_TurnMeldPlay>[];
    _turnCoverPlays = <_TurnCoverPlay>[];
    _turnSource = FinishCardSource.stock;
    _removedSeats.add(removedSeat);

    final remaining = _roundActiveSeats;
    if (remaining.length == 1) {
      _finishRound(
        type: RoundOutcomeType.normalFinish,
        winner: remaining.single,
      );
    } else if (remaining.isNotEmpty) {
      _currentSeat = _nextActiveSeat(removedSeat);
      _phase = TurnPhase.draw;
      _evaluateRoundEnd();
    }

    return ApplyActionResult.success(resolution.message);
  }

  void _finishRound({
    required RoundOutcomeType type,
    PlayerSeat? winner,
    PlayerSeat? fiftyDiscarder,
    bool firstRoundFiftyException = false,
  }) {
    final remainingCardCounts = <PlayerSeat, int>{
      for (final seat in _roundScoringSeats) seat: cardCountFor(seat),
    };
    _roundOutcome = type;
    _roundResult = RoundProgressResult(
      type: type,
      winner: winner,
      fiftyDiscarder: fiftyDiscarder,
      firstRoundFiftyException: firstRoundFiftyException,
      remainingCardCounts: remainingCardCounts,
    );
  }

  List<List<HareegCard>> get _tableMeldCardLists {
    return [
      for (final melds in _tableMelds.values)
        for (final meld in melds) meld.cards,
    ];
  }

  bool _canClaimFifty(PlayerSeat seat) {
    final window = _fiftyWindow;
    if (window == null || window.claimant != seat || _phase != TurnPhase.draw) {
      return false;
    }
    if (window.isExpired(_fiftyElapsedSeconds())) {
      return false;
    }
    if (setup.rulePreset == RulePreset.assisted) {
      return _canFinishWithPreviousDiscard(seat);
    }
    return true;
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
    final window = _fiftyWindow;
    if (window == null || window.claimant != _currentSeat) {
      return const ApplyActionResult.failure(
        'Only the immediate next player can claim Fifty.',
      );
    }

    final discarded = topDiscard;
    if (discarded == null || discarded.id != window.discardedCard.id) {
      return const ApplyActionResult.failure('No active Fifty discard.');
    }

    final plan = _finishPlanForCards(
      [..._handFor(_currentSeat), discarded],
      requiredPlayedCardId: discarded.id,
      source: FinishCardSource.previousDiscard,
      perfectHandAttempt: true,
    );
    if (plan == null) {
      final mistake = _resolveMistake(MistakeType.wrongFiftyClaim);
      if (mistake == null) {
        return const ApplyActionResult.failure(
          'That discard does not complete a valid Fifty.',
        );
      }
      final removal = _applyMistake(mistake);
      return removal ?? ApplyActionResult.success(mistake.message);
    }

    final claim = ClassicHareegFiftyRules.validateClaim(
      window: window,
      claimant: _currentSeat,
      elapsedSeconds: _fiftyElapsedSeconds(),
      finishingMelds: plan.melds,
      finalDiscard: plan.finalDiscard,
    );
    if (!claim.isValid) {
      final mistake = _resolveMistake(MistakeType.wrongFiftyClaim);
      if (mistake == null) {
        return ApplyActionResult.failure(claim.message);
      }
      final removal = _applyMistake(mistake);
      return removal ?? ApplyActionResult.success(mistake.message);
    }

    _discardPile.removeLast();
    _hands[_currentSeat] = const <HareegCard>[];
    _discardPile.add(plan.finalDiscard);
    _pendingDiscard = null;
    _finishRound(
      type: RoundOutcomeType.fiftyFinish,
      winner: _currentSeat,
      fiftyDiscarder: window.discarder,
      firstRoundFiftyException: claim.firstRoundException,
    );
    return const ApplyActionResult.success('Fifty claimed.');
  }

  bool _canFinishWithPreviousDiscard(PlayerSeat seat) {
    final discarded = topDiscard;
    if (discarded == null) {
      return false;
    }
    final cacheKey = _previousDiscardFinishKey(seat, discarded);
    if (_previousDiscardFinishCacheKey == cacheKey) {
      return _previousDiscardFinishCacheValue ?? false;
    }

    final cards = [..._handFor(seat), discarded];
    final planner = ClassicHareegFinishPlanner(cards);
    if (!planner.hasValidMeldContaining(discarded.id)) {
      _previousDiscardFinishCacheKey = cacheKey;
      _previousDiscardFinishCacheValue = false;
      return false;
    }
    final canFinish =
        _finishPlanForCards(
          cards,
          requiredPlayedCardId: discarded.id,
          source: FinishCardSource.previousDiscard,
          perfectHandAttempt: true,
          planner: planner,
        ) !=
        null;
    _previousDiscardFinishCacheKey = cacheKey;
    _previousDiscardFinishCacheValue = canFinish;
    return canFinish;
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

  _FinishPlan? _finishPlanForCards(
    List<HareegCard> cards, {
    String? requiredPlayedCardId,
    required FinishCardSource source,
    required bool perfectHandAttempt,
    ClassicHareegFinishPlanner? planner,
  }) {
    final totalWatch = Stopwatch()..start();
    var attempts = 0;
    final finishPlanner = planner ?? ClassicHareegFinishPlanner(cards);
    _debugRulesLog(
      'finishPlan start cards=${cards.length} required=$requiredPlayedCardId '
      'source=$source perfect=$perfectHandAttempt opened='
      '${_openingState.hasOpened(_currentSeat)}',
    );
    for (final finalDiscard in cards) {
      if (finalDiscard.id == requiredPlayedCardId) {
        continue;
      }
      attempts += 1;
      final remaining = cards
          .where((card) => card.id != finalDiscard.id)
          .toList(growable: false);
      final partitionWatch = Stopwatch()..start();
      final melds = finishPlanner.partitionWithout(finalDiscard);
      partitionWatch.stop();
      if (partitionWatch.elapsedMilliseconds >= _debugSlowPartitionMs) {
        _debugRulesLog(
          'finishPlan slow partition discard=${finalDiscard.label} '
          'remaining=${remaining.length} '
          'elapsed=${partitionWatch.elapsedMilliseconds}ms',
        );
      }
      if (melds == null) {
        continue;
      }

      final finish = ClassicHareegFinishRules.validateFinish(
        playedMelds: melds,
        finalDiscard: finalDiscard,
        playerOpened: _openingState.hasOpened(_currentSeat),
        source: source,
        perfectHandAttempt: perfectHandAttempt,
      );
      if (finish.isValid) {
        totalWatch.stop();
        _debugRulesLog(
          'finishPlan found elapsed=${totalWatch.elapsedMilliseconds}ms '
          'attempts=$attempts discard=${finalDiscard.label} '
          'melds=${melds.length}',
        );
        return _FinishPlan(melds: melds, finalDiscard: finalDiscard);
      }
    }
    totalWatch.stop();
    _debugRulesLog(
      'finishPlan none elapsed=${totalWatch.elapsedMilliseconds}ms '
      'attempts=$attempts cards=${cards.length}',
    );
    return null;
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
            playedCount: group.length,
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
            playedCount: group.length,
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
      String? jokerId,
      CardIdentity? jokerIdentity,
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
            playedCount: usedIds.length,
            melds: melds,
          )) {
        final orderedCards = hand
            .where((card) => usedIds.contains(card.id))
            .toList(growable: false);
        found = jokerId == null || jokerIdentity == null
            ? ClassicHareegActionIds.playMeldActionId(
                orderedCards.map((card) => card.id),
              )
            : ClassicHareegActionIds.playMeldWithJokerIdentityActionId(
                cardIds: orderedCards.map((card) => card.id),
                jokerId: jokerId,
                identity: jokerIdentity,
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
        if (option.jokerId != null && jokerId != null) {
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
          jokerId: option.jokerId ?? jokerId,
          jokerIdentity: option.jokerIdentity ?? jokerIdentity,
        );
      }
    }

    search(
      start: 0,
      usedIds: <String>{},
      melds: const <PlacedMeld>[],
      meldCount: 0,
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
    final groups = <List<HareegCard>>[];
    final seen = <String>{};
    final cardsByIdentity = <String, List<HareegCard>>{};
    final unresolvedJokers = <HareegCard>[];

    for (final card in hand) {
      final identity = card.effectiveIdentity;
      if (identity == null) {
        if (card.isJoker) {
          unresolvedJokers.add(card);
        }
        continue;
      }
      cardsByIdentity.putIfAbsent(identity.key, () => <HareegCard>[]).add(card);
    }

    final joker = _preferredJoker(unresolvedJokers, preferredCardId);

    void addGroup(List<HareegCard> cards) {
      if (cards.length < 3) {
        return;
      }
      final ids = cards.map((card) => card.id).toList();
      if (ids.toSet().length != ids.length) {
        return;
      }
      final key = (ids..sort()).join('|');
      if (seen.add(key)) {
        groups.add(List.unmodifiable(cards));
      }
    }

    for (final rank in CardRank.values) {
      final availableSuits = <CardSuit>[];
      for (final suit in CardSuit.values) {
        final identity = CardIdentity(rank: rank, suit: suit);
        if (_cardForIdentity(cardsByIdentity, identity, preferredCardId) !=
            null) {
          availableSuits.add(suit);
        }
      }

      for (var size = 3; size <= 4; size += 1) {
        if (availableSuits.length >= size) {
          for (final suits in _combinations(availableSuits, size)) {
            _addMeldGroupVariants(
              addGroup: addGroup,
              choices: [
                for (final suit in suits)
                  _cardsForIdentity(
                    cardsByIdentity,
                    CardIdentity(rank: rank, suit: suit),
                    preferredCardId,
                  ),
              ],
            );
          }
        }

        final standardCardCount = size - 1;
        if (joker != null && availableSuits.length >= standardCardCount) {
          for (final suits in _combinations(
            availableSuits,
            standardCardCount,
          )) {
            _addMeldGroupVariants(
              addGroup: addGroup,
              choices: [
                for (final suit in suits)
                  _cardsForIdentity(
                    cardsByIdentity,
                    CardIdentity(rank: rank, suit: suit),
                    preferredCardId,
                  ),
                [joker],
              ],
            );
          }
        }
      }
    }

    for (final suit in CardSuit.values) {
      _addSequenceCandidateGroups(
        addGroup: addGroup,
        cardsByIdentity: cardsByIdentity,
        ranks: CardRank.values,
        suit: suit,
        joker: joker,
        preferredCardId: preferredCardId,
      );
      _addHighAceSequenceCandidateGroups(
        addGroup: addGroup,
        cardsByIdentity: cardsByIdentity,
        suit: suit,
        joker: joker,
        preferredCardId: preferredCardId,
      );
    }

    totalWatch.stop();
    if (totalWatch.elapsedMilliseconds >= _debugSlowRuleSearchMs ||
        groups.length >= _debugLargeGroupCount) {
      _debugRulesLog(
        'candidateMeldGroups end hand=${hand.length} '
        'preferred=$preferredCardId jokers=${unresolvedJokers.length} '
        'elapsed=${totalWatch.elapsedMilliseconds}ms groups=${groups.length}',
      );
    }
    return groups;
  }

  void _addMeldGroupVariants({
    required void Function(List<HareegCard> cards) addGroup,
    required List<List<HareegCard>> choices,
  }) {
    if (choices.any((cards) => cards.isEmpty)) {
      return;
    }

    var emitted = 0;
    void build(int index, List<HareegCard> selected) {
      if (emitted >= _maxPhysicalMeldVariants) {
        return;
      }
      if (index == choices.length) {
        emitted += 1;
        addGroup(List.unmodifiable(selected));
        return;
      }
      for (final card in choices[index]) {
        build(index + 1, [...selected, card]);
      }
    }

    build(0, const <HareegCard>[]);
  }

  void _addSequenceCandidateGroups({
    required void Function(List<HareegCard> cards) addGroup,
    required Map<String, List<HareegCard>> cardsByIdentity,
    required List<CardRank> ranks,
    required CardSuit suit,
    required HareegCard? joker,
    required String? preferredCardId,
  }) {
    for (var start = 0; start <= ranks.length - 3; start += 1) {
      for (var end = start + 3; end <= ranks.length; end += 1) {
        _addSequenceCandidateGroup(
          addGroup: addGroup,
          cardsByIdentity: cardsByIdentity,
          ranks: ranks.sublist(start, end),
          suit: suit,
          joker: joker,
          preferredCardId: preferredCardId,
        );
      }
    }
  }

  void _addHighAceSequenceCandidateGroups({
    required void Function(List<HareegCard> cards) addGroup,
    required Map<String, List<HareegCard>> cardsByIdentity,
    required CardSuit suit,
    required HareegCard? joker,
    required String? preferredCardId,
  }) {
    final ranks = [
      for (final rank in CardRank.values)
        if (rank != CardRank.ace) rank,
      CardRank.ace,
    ];
    for (var start = 0; start <= ranks.length - 3; start += 1) {
      _addSequenceCandidateGroup(
        addGroup: addGroup,
        cardsByIdentity: cardsByIdentity,
        ranks: ranks.sublist(start),
        suit: suit,
        joker: joker,
        preferredCardId: preferredCardId,
      );
    }
  }

  void _addSequenceCandidateGroup({
    required void Function(List<HareegCard> cards) addGroup,
    required Map<String, List<HareegCard>> cardsByIdentity,
    required List<CardRank> ranks,
    required CardSuit suit,
    required HareegCard? joker,
    required String? preferredCardId,
  }) {
    var missing = 0;
    final choices = <List<HareegCard>>[];
    for (final rank in ranks) {
      final cards = _cardsForIdentity(
        cardsByIdentity,
        CardIdentity(rank: rank, suit: suit),
        preferredCardId,
      );
      if (cards.isEmpty) {
        missing += 1;
        if (joker == null || missing > 1) {
          return;
        }
        choices.add([joker]);
      } else {
        choices.add(cards);
      }
    }
    _addMeldGroupVariants(addGroup: addGroup, choices: choices);
  }

  _MeldActionOption? _resolveMeldActionOption(List<HareegCard> group) {
    var resolved = _resolveMeldCards(group);
    String? jokerId;
    CardIdentity? jokerIdentity;
    if (!resolved.result.isValid) {
      final unresolvedJokers = group
          .where((card) => card.isJoker && card.representedIdentity == null)
          .toList(growable: false);
      if (unresolvedJokers.length == 1) {
        final identity = ClassicHareegJokerRules.deterministicCpuIdentity(
          cards: group,
          joker: unresolvedJokers.single,
        );
        if (identity != null) {
          jokerId = unresolvedJokers.single.id;
          jokerIdentity = identity;
          resolved = _resolveMeldCards(
            group,
            jokerId: jokerId,
            jokerIdentity: jokerIdentity,
          );
        }
      }
    }
    if (!resolved.result.isValid) {
      return null;
    }

    return _MeldActionOption(
      cards: List.unmodifiable(group),
      meld: PlacedMeld.fromCards(resolved.cards),
      actionId: jokerId == null || jokerIdentity == null
          ? ClassicHareegActionIds.playMeldActionId(
              group.map((card) => card.id),
            )
          : ClassicHareegActionIds.playMeldWithJokerIdentityActionId(
              cardIds: group.map((card) => card.id),
              jokerId: jokerId,
              identity: jokerIdentity,
            ),
      jokerId: jokerId,
      jokerIdentity: jokerIdentity,
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
      String? jokerId,
      CardIdentity? jokerIdentity,
    }) {
      if (meldCount >= 2 &&
          usedIds.length < hand.length &&
          (mustUseCardId == null || usedIds.contains(mustUseCardId)) &&
          _canAdvertiseMeldPlay(
            seat: seat,
            handCount: hand.length,
            playedCount: usedIds.length,
            melds: melds,
          )) {
        final orderedCards = hand
            .where((card) => usedIds.contains(card.id))
            .toList(growable: false);
        ids.add(
          jokerId == null || jokerIdentity == null
              ? ClassicHareegActionIds.playMeldActionId(
                  orderedCards.map((card) => card.id),
                )
              : ClassicHareegActionIds.playMeldWithJokerIdentityActionId(
                  cardIds: orderedCards.map((card) => card.id),
                  jokerId: jokerId,
                  identity: jokerIdentity,
                ),
        );
      }

      for (var index = start; index < uniqueOptions.length; index += 1) {
        final option = uniqueOptions[index];
        if (option.cardIds.any(usedIds.contains)) {
          continue;
        }
        if (option.jokerId != null && jokerId != null) {
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
          jokerId: option.jokerId ?? jokerId,
          jokerIdentity: option.jokerIdentity ?? jokerIdentity,
        );
      }
    }

    search(
      start: 0,
      usedIds: <String>{},
      melds: const <PlacedMeld>[],
      meldCount: 0,
    );
  }

  bool _canAdvertiseMeldPlay({
    required PlayerSeat seat,
    required int handCount,
    required int playedCount,
    required List<PlacedMeld> melds,
  }) {
    if (_openingState.hasOpened(seat)) {
      return true;
    }

    final opening = ClassicHareegOpeningRules.validateOpening(
      state: _openingState,
      seat: seat,
      melds: [..._turnOpeningMelds, ...melds],
    );
    final leavesFinalDiscard = handCount - playedCount == 1;
    return opening.isValid || leavesFinalDiscard;
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

  String? _replacementActionIdForCardId(PlayerSeat seat, String cardId) {
    return _tablePlayPlanner.replacementActionIdForCardId(seat, cardId);
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
      final jokerCanDiscard = ClassicHareegJokerRules.canDiscard(
        card,
        isFinalDiscard: isFinalDiscard,
      );
      if (!jokerCanDiscard) {
        continue;
      }
      final coverResult = ClassicHareegCoverRules.canDiscard(
        tableMelds: _tableMeldCardLists,
        candidate: card,
        isFinalDiscard: isFinalDiscard,
      );
      final blocksJokerReplacement =
          !isFinalDiscard &&
          _replacementActionIdForCardId(seat, card.id) != null;
      if ((!coverResult.canDiscard || blocksJokerReplacement) &&
          setup.rulePreset == RulePreset.assisted) {
        continue;
      }
      final prefix = !coverResult.canDiscard || blocksJokerReplacement
          ? ClassicHareegActionIds.discardBlockedCoverPrefix
          : ClassicHareegActionIds.discardPrefix;
      ids.add('$prefix${card.id}');
    }
    return List.unmodifiable(ids);
  }
}

class _TurnCoverPlay {
  const _TurnCoverPlay({
    required this.targetSeat,
    required this.meldIndex,
    required this.previousMeld,
    required this.coverMeld,
    required this.previousOpeningState,
    this.consumedPendingDiscard,
  });

  final PlayerSeat targetSeat;
  final int meldIndex;
  final PlacedMeld previousMeld;
  final PlacedMeld coverMeld;
  final OpeningState previousOpeningState;
  final HareegCard? consumedPendingDiscard;
}

class _TurnMeldPlay {
  const _TurnMeldPlay({
    required this.owner,
    required this.meld,
    this.consumedPendingDiscard,
  });

  final PlayerSeat owner;
  final PlacedMeld meld;
  final HareegCard? consumedPendingDiscard;
}

const _maxPhysicalMeldVariants = 8;
const _maxCpuOpeningMeldOptions = 24;
const _maxCpuOpeningCombinationMelds = 3;
const _debugSlowRuleSearchMs = 120;
const _debugSlowPartitionMs = 80;
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

HareegCard? _preferredJoker(List<HareegCard> jokers, String? preferredCardId) {
  if (jokers.isEmpty) {
    return null;
  }
  if (preferredCardId != null) {
    for (final joker in jokers) {
      if (joker.id == preferredCardId) {
        return joker;
      }
    }
  }
  return jokers.first;
}

List<HareegCard> _cardsForIdentity(
  Map<String, List<HareegCard>> cardsByIdentity,
  CardIdentity identity,
  String? preferredCardId,
) {
  final cards = cardsByIdentity[identity.key];
  if (cards == null || cards.isEmpty) {
    return const [];
  }
  final ordered = List<HareegCard>.of(cards);
  if (preferredCardId != null) {
    final preferredIndex = ordered.indexWhere(
      (card) => card.id == preferredCardId,
    );
    if (preferredIndex > 0) {
      final preferred = ordered.removeAt(preferredIndex);
      ordered.insert(0, preferred);
    }
  }
  return List.unmodifiable(ordered);
}

HareegCard? _cardForIdentity(
  Map<String, List<HareegCard>> cardsByIdentity,
  CardIdentity identity,
  String? preferredCardId,
) {
  final cards = cardsByIdentity[identity.key];
  if (cards == null || cards.isEmpty) {
    return null;
  }
  if (preferredCardId != null) {
    for (final card in cards) {
      if (card.id == preferredCardId) {
        return card;
      }
    }
  }
  return cards.first;
}

Iterable<List<T>> _combinations<T>(List<T> items, int size) sync* {
  if (size < 0 || size > items.length) {
    return;
  }
  if (size == 0) {
    yield <T>[];
    return;
  }

  Iterable<List<T>> build(int start, int remaining) sync* {
    if (remaining == 0) {
      yield <T>[];
      return;
    }
    for (var index = start; index <= items.length - remaining; index += 1) {
      for (final suffix in build(index + 1, remaining - 1)) {
        yield [items[index], ...suffix];
      }
    }
  }

  yield* build(0, size);
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
    this.jokerId,
    this.jokerIdentity,
  });

  final List<HareegCard> cards;
  final PlacedMeld meld;
  final String actionId;
  final String? jokerId;
  final CardIdentity? jokerIdentity;

  Set<String> get cardIds => cards.map((card) => card.id).toSet();
}

class _FinishPlan {
  const _FinishPlan({required this.melds, required this.finalDiscard});

  final List<PlacedMeld> melds;
  final HareegCard finalDiscard;
}
