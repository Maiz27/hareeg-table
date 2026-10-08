part of 'classic_hareeg_game_controller.dart';

/// Takes this turn's reversible table plays (staged openings, turn melds and
/// covers) back into the current seat's hand.
extension _TablePlayRetraction on ClassicHareegGameController {
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

    for (final meld in stagedMelds) {
      _returnCardsToHand(meld.cards);
      _turnJournal.removeFinishMeldMatching(meld);
    }
    for (final play in turnMeldPlays) {
      _returnCardsToHand(play.meld.cards);
      _turnJournal.removeFinishMeldMatching(play.meld);
    }

    HareegCard? restoredPending = _turnJournal.consumedPendingDiscard;
    for (final play in turnMeldPlays.reversed) {
      restoredPending = play.consumedPendingDiscard ?? restoredPending;
    }
    for (final play in coverPlays.reversed) {
      final targetMelds = _tableMeldsAt(play.targetSeat, play.meldIndex);
      if (targetMelds != null) {
        targetMelds[play.meldIndex] = play.previousMeld;
      }
      _turnJournal.removeFinishMeldMatching(play.coverMeld);
      _openingState = play.previousOpeningState;
      restoredPending = play.consumedPendingDiscard ?? restoredPending;
    }

    for (final play in coverPlays) {
      _returnCardsToHand(play.coverMeld.cards);
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
    final tableMelds = _tableMeldsAt(target.owner, target.meldIndex);
    if (tableMelds == null) {
      return _meldNoLongerOnTable;
    }

    tableMelds.removeAt(target.meldIndex);
    _turnJournal.rebaseCoverPlaysAfterMeldRemoval(
      targetSeat: target.owner,
      removedIndex: target.meldIndex,
    );
    _returnCardsToHand(play.meld.cards);
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
    final tableMelds = _tableMeldsAt(target.owner, target.meldIndex);
    if (tableMelds == null) {
      return _meldNoLongerOnTable;
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
    _returnCardsToHand(staged.cards);
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
    final targetMelds = _tableMeldsAt(target.owner, target.meldIndex);
    if (targetMelds == null) {
      return _meldNoLongerOnTable;
    }

    targetMelds[target.meldIndex] = coverPlays.first.previousMeld;
    HareegCard? restoredPending;
    for (final play in coverPlays.reversed) {
      _turnJournal.removeFinishMeldMatching(play.coverMeld);
      restoredPending = play.consumedPendingDiscard ?? restoredPending;
    }
    for (final play in coverPlays) {
      _returnCardsToHand(play.coverMeld.cards);
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
}
