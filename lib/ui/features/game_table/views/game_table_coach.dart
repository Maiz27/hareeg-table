part of 'game_table_screen.dart';

/// The live coach: memoized advisor insights and the hints presented from
/// them.
extension _TableCoach on _GameTableScreenState {
  /// Builds the coaching hints to surface this frame — the actionable PRIMARY
  /// hint plus an optional once-per-round STAGE note — or null when nothing
  /// should show. The caller folds the persistent conditions (tier, toggle,
  /// turn ownership) into whether this runs at all; [gate] carries the
  /// transient ones (blocking overlays, in-flight motion).
  ({CoachHint? primary, CoachHint? stageNote})? _buildCoachHints(
    AppStrings strings,
    PlayerSeat seat, {
    required bool gate,
  }) {
    // Always recompute while the coach is live (cheap — memoized by the
    // situation signature) so the cached insights track every controller-state
    // change. The [gate] only hides the *display* while something is
    // mid-animation; it must NOT freeze the *data*, or a hint computed before
    // a draw/cover landed survives stale once the gate reopens (the playtest
    // "discard the card you just melded" bug). Compute first, then gate the
    // display.
    final insights = _coachInsightsFor(seat);
    if (!gate || insights.isEmpty) {
      return null;
    }
    final selection = _coachInsightFlow.select(
      insights: insights,
      roundNumber: _controller.roundNumber,
      turnKey: '${_controller.roundNumber}:$_coachTurnCounter',
    );
    CoachHint? presentOf(CoachingInsight? insight) => insight == null
        ? null
        : CoachHintPresenter.present(
            insight: insight,
            strings: strings,
            identityForCardId: _identityForCardId,
            topDiscardIdentity: _controller.topDiscard?.effectiveIdentity,
          );
    final primary = presentOf(selection.primary);
    final stageNote = presentOf(selection.stageNote);
    if (primary == null) {
      // Nothing actionable this frame (rare edge: only banner insights). Let
      // the stage note carry the callout rather than going dark.
      return (primary: stageNote, stageNote: null);
    }
    return (primary: primary, stageNote: stageNote);
  }

  /// Memoized advisor call. Recomputes only when the cheap situation signature
  /// (turn, turn phase, opened state, top discard, pending, Fifty claimant, hand
  /// ids, own meld ids, and an opponent digest — hand counts, opened bits, table
  /// meld ids — since the advisor's hold-back/bait/threat logic reads opponent
  /// state too) changes, so the fifty ticker and card flights don't
  /// trigger re-analysis. The turn phase is part of the key because a draw flips
  /// draw→action with the same seat: without it a draw that completes a meld
  /// could reuse the pre-draw insight (the stale-discard playtest bug). The Fifty
  /// claimant is included because the Fifty hint depends on whether a claim
  /// window is open for this seat, and a window can open or expire without the
  /// top discard changing. The claim-LIVENESS bit (timer still running) is also
  /// keyed — it flips exactly once per window, letting the hint hand over from
  /// "Claim the Fifty" to "take it and finish" when the timer lapses — but the
  /// raw seconds remaining are deliberately NOT keyed (that would re-analyse
  /// every tick).
  List<CoachingInsight> _coachInsightsFor(PlayerSeat seat) {
    final hand = _controller.handFor(seat);
    final ownMelds = _controller.tableMeldsFor(seat);
    final key = StringBuffer()
      ..write(_controller.currentSeat.name)
      ..write('#')
      ..write(_controller.turnPhase.name)
      ..write(_controller.openingState.hasOpened(seat) ? '#1' : '#0')
      ..write('#')
      ..write(_controller.topDiscard?.id ?? '-')
      ..write('#')
      ..write(_controller.pendingDiscard?.id ?? '-')
      ..write('#f:')
      ..write(_controller.fiftyClaimant?.name ?? '-')
      ..write((_controller.fiftySecondsRemaining ?? 0) > 0 ? '+' : '-')
      ..write('#h:');
    for (final card in hand) {
      key
        ..write(card.id)
        ..write(',');
    }
    key.write('#m:');
    for (final meld in ownMelds) {
      for (final card in meld.cards) {
        key
          ..write(card.id)
          ..write(',');
      }
      key.write('|');
    }
    // Opponent digest. The advisor's hold-back / bait / threat logic reads
    // opponent state too — their table melds, hand counts and opened state.
    // Today an opponent-state change always rides a currentSeat flip that
    // already busts the key, but that is emergent, not enforced; key the
    // opponent state explicitly. Walk opponents in the advisor's stable
    // anti-clockwise order over the active seats, so an eliminated seat simply
    // drops out (the same way it does in _opponentsOf).
    key.write('#o:');
    final activeSeats = _controller.activeSeats;
    var opponent = seat.nextAntiClockwise;
    while (opponent != seat) {
      if (activeSeats.contains(opponent)) {
        key
          ..write(opponent.name)
          ..write(_controller.openingState.hasOpened(opponent) ? '1' : '0')
          ..write('c')
          ..write(_controller.handFor(opponent).length)
          ..write('m:');
        for (final meld in _controller.tableMeldsFor(opponent)) {
          for (final card in meld.cards) {
            key
              ..write(card.id)
              ..write(',');
          }
          key.write('|');
        }
        key.write(';');
      }
      opponent = opponent.nextAntiClockwise;
    }
    final keyStr = key.toString();
    if (keyStr != _coachInsightCacheKey) {
      _coachInsightCacheKey = keyStr;
      _coachInsights = ClassicHareegCoachingAdvisor.adviseFor(
        _controller,
        seat,
      );
      final leadInsight = _coachInsights.isEmpty ? null : _coachInsights.first;
      if (leadInsight != null) {
        _recorder?.recordCoachHint(
          roundNumber: _controller.roundNumber,
          hintId: leadInsight.category.name,
          seat: seat,
          phase: _controller.turnPhase,
          data: {'count': _coachInsights.length},
        );
      }
    }
    return _coachInsights;
  }

  /// Resolves a card id referenced by a coaching insight to its identity for
  /// hint copy. Insights only point at the human hand, the top discard, or the
  /// human's own table melds.
  CardIdentity? _identityForCardId(String cardId) {
    for (final card in _controller.handFor(PlayerSeat.south)) {
      if (card.id == cardId) {
        return card.effectiveIdentity;
      }
    }
    final top = _controller.topDiscard;
    if (top != null && top.id == cardId) {
      return top.effectiveIdentity;
    }
    for (final meld in _controller.tableMeldsFor(PlayerSeat.south)) {
      for (final card in meld.cards) {
        if (card.id == cardId) {
          return card.effectiveIdentity;
        }
      }
    }
    return null;
  }
}
