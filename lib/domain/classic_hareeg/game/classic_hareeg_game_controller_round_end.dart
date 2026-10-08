part of 'classic_hareeg_game_controller.dart';

/// Mistake consequences, seat removal and round conclusion (finishes, draws
/// and the stock-exhaustion liveness backstop).
extension _RoundEnd on ClassicHareegGameController {
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

  Map<PlayerSeat, int> _remainingCardCounts() {
    return {for (final seat in _roundActiveSeats) seat: cardCountFor(seat)};
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
}
