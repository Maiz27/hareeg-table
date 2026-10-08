part of 'classic_hareeg_game_controller.dart';

/// Fifty claims, proof turns and previous-discard finish detection.
extension _FiftyFlow on ClassicHareegGameController {
  /// Resolves "return the claimed card" during a Fifty proof turn as the
  /// give-up gesture, applying the tier's wrong-Fifty consequence.
  ///
  /// Table tier removes the claimant (+17, claimed card back on the pile, turn
  /// passes) via the same [_applyMistake] path the discard-exit uses. Strict
  /// charges the score penalty (+3), calls off the claim, and hands the claimed
  /// card back to the pile, dropping the seat into its draw decision — the same
  /// shape as a plain pending return.
  ApplyActionResult _giveUpFiftyProofByReturn({
    required PlayerSeat returningSeat,
    required HareegCard? pending,
  }) {
    final mistake = _mistakeConsequencePlanFor(MistakeType.wrongFiftyClaim);
    if (!mistake.canApply) {
      return const ApplyActionResult.failure(
        'The claimed card cannot be returned — prove the Fifty or end the '
        'turn.',
      );
    }
    // On every tier the staged opening melds must be taken back first (exactly
    // like a plain return), checked BEFORE any penalty is charged. Without this
    // a Table give-up would remove the claimant while their sub-requirement
    // melds stayed stranded on the table; the Strict give-up would also leave a
    // phantom +3 if it later failed.
    if (pending != null &&
        !_openingState.hasOpened(returningSeat) &&
        _turnOpeningMelds.isNotEmpty) {
      return const ApplyActionResult.failure(
        'Take back your staged melds before giving up the Fifty.',
      );
    }

    final removal = _applyMistake(mistake);
    if (removal != null) {
      // Table tier: the seat is removed, the claimed card was returned to the
      // pile by the mistake plan, and the turn has already advanced.
      return removal;
    }

    // Strict tier: the penalty is on the score; call off the claim and return
    // the claimed card to the pile like a plain pending return.
    _activeFiftyClaim = null;
    return _returnPendingDiscardToPile(
          returningSeat: returningSeat,
          pending: pending,
        ) ??
        ApplyActionResult.success(mistake.message);
  }

  /// Whether discarding [finalDiscard] right now completes a valid finish —
  /// the single proof-completion condition shared by the apply gate and the
  /// proof-turn discard surface, so they can never disagree.
  bool _provesFiftyFinish(HareegCard finalDiscard) {
    return _validateTurnFinish(finalDiscard).isValid;
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
      _landDiscardOfRemovedSeat(discardingSeat, card);
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
    // Claim application just installed this plan. The claim itself is not a
    // proof step; treating it as an off-script play would discard the plan
    // before the first save or replay frame can capture it.
    if (actionId == ClassicHareegActionIds.claimFifty) return;
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
      return _previousDiscardFinishPlanCacheValue;
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
    final plan = planner.hasFinishUseContaining(discarded.id)
        ? ClassicHareegFiftyClaimPlanner.finishPlanForClaim(
            hand: _handFor(seat),
            discarded: discarded,
            playerOpened: playerOpened,
            planner: planner,
          )
        : null;
    _previousDiscardFinishCacheKey = cacheKey;
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

  /// Ordered proof action ids for CPU play-out. Exact saves retain the
  /// unplayed suffix; legacy saves and off-script plays rebuild lazily.
  List<String>? script;

  /// Index of the next unplayed script step.
  int scriptIndex = 0;

  /// Detached suffix: advancing the live script cannot alter a saved frame.
  List<String>? get remainingActions {
    final actions = script;
    if (actions == null || scriptIndex >= actions.length) return null;
    return List.unmodifiable(actions.skip(scriptIndex));
  }
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
