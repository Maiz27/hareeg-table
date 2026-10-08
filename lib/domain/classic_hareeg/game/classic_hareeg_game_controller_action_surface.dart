part of 'classic_hareeg_game_controller.dart';

/// Enumerates the meld, cover, joker-replacement and discard action ids the
/// action-surface planner advertises for the live state.
extension _ActionSurfaceSearch on ClassicHareegGameController {
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
    final uniqueOptions = _uniqueByCardSet(options);
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
        found = _combinationActionId(hand, usedIds, jokerAssignments);
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
    var resolved = ClassicHareegTablePlayPlanner.resolveMeldCards(group);
    var jokerAssignments = const <JokerMeldAssignment>[];
    if (!resolved.result.isValid) {
      final variants = ClassicHareegTablePlayPlanner.resolveMeldCardVariants(
        group,
        limit: 1,
      );
      if (variants.isNotEmpty) {
        resolved = variants.single;
        jokerAssignments = resolved.jokerAssignments;
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

    final uniqueOptions = _uniqueByCardSet(options);

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
        ids.add(_combinationActionId(hand, usedIds, jokerAssignments));
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

  List<String> _replaceJokerActionIds(
    PlayerSeat seat, {
    String? mustUseCardId,
  }) {
    return _tablePlayPlanner.replaceJokerActionIds(
      seat,
      mustUseCardId: mustUseCardId,
    );
  }

  List<String> _coverActionIds(PlayerSeat seat, {String? mustUseCardId}) {
    return _tablePlayPlanner.coverActionIds(seat, mustUseCardId: mustUseCardId);
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

/// Drops options that cover the same physical card set as an earlier one.
List<_MeldActionOption> _uniqueByCardSet(List<_MeldActionOption> options) {
  final uniqueOptions = <_MeldActionOption>[];
  final seenCardSets = <String>{};
  for (final option in options) {
    final key = (option.cardIds.toList()..sort()).join('|');
    if (seenCardSets.add(key)) {
      uniqueOptions.add(option);
    }
  }
  return uniqueOptions;
}

/// Play-meld action id for a multi-meld opening that uses [usedIds], with the
/// cards kept in hand order.
String _combinationActionId(
  List<HareegCard> hand,
  Set<String> usedIds,
  List<JokerMeldAssignment> jokerAssignments,
) {
  return _playMeldActionIdFor([
    for (final card in hand)
      if (usedIds.contains(card.id)) card.id,
  ], jokerAssignments);
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
