import '../models/classic_hareeg_setup.dart';
import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../rules/classic_hareeg_rules.dart';
import '../rules/cover_rules.dart';
import '../rules/finish_rules.dart';
import '../rules/joker_rules.dart';
import '../rules/match_progression_rules.dart';
import '../rules/meld_validator.dart';
import '../rules/opening_rules.dart';
import 'classic_hareeg_match_snapshot.dart';
import 'classic_hareeg_round.dart';

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

/// Action ids used by [ClassicHareegGameController].
///
/// Discard action ids embed the physical card id after a colon. The prefix
/// segment carries the CPU-relevant tags `discard-blocked-cover:` or
/// `discard-joker:` when the discard is only legal under non-assisted presets,
/// matching the convention consumed by `ClassicHareegCpuStrategy`.
abstract final class ClassicHareegActionIds {
  /// Draw one card from stock.
  static const drawStock = 'draw-stock';

  /// Take the previous player's discard into pending state.
  static const takeDiscard = 'take-discard';

  /// Commit a pending discard as used (advances to discard phase).
  static const usePendingDiscard = 'use-pending-discard';

  /// Return a pending discard and draw from stock instead.
  static const returnPendingDiscard = 'return-pending-discard';

  /// Play selected cards as a meld. Card ids follow the prefix, comma-separated.
  static const playMeldPrefix = 'play-meld:';

  /// Place selected cover cards on an existing meld.
  static const placeCoverPrefix = 'place-cover:';

  /// Discard action id prefix for plain legal discards.
  static const discardPrefix = 'discard:';

  /// Discard action id prefix for cards that are covers (only legal as final
  /// discard, or under presets that allow cover discards with a penalty).
  static const discardBlockedCoverPrefix = 'discard-blocked-cover:';

  /// Discard action id prefix for jokers (only legal as final discard, or under
  /// presets that allow joker discards with a penalty).
  static const discardJokerPrefix = 'discard-joker:';

  /// Returns the card id encoded in a discard action id, if present.
  static String? discardCardId(String actionId) {
    for (final prefix in const [
      discardPrefix,
      discardBlockedCoverPrefix,
      discardJokerPrefix,
    ]) {
      if (actionId.startsWith(prefix)) {
        return actionId.substring(prefix.length);
      }
    }
    return null;
  }

  /// Creates a play-meld action id for selected physical card ids.
  static String playMeldActionId(Iterable<String> cardIds) {
    return '$playMeldPrefix${cardIds.join(',')}';
  }

  /// Returns the card ids encoded in a play-meld action id, if present.
  static List<String>? meldCardIds(String actionId) {
    if (!actionId.startsWith(playMeldPrefix)) {
      return null;
    }
    return actionId
        .substring(playMeldPrefix.length)
        .split(',')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  /// Creates a place-cover action id.
  static String placeCoverActionId({
    required PlayerSeat targetSeat,
    required int meldIndex,
    required Iterable<String> cardIds,
  }) {
    return '$placeCoverPrefix${targetSeat.name}:$meldIndex:${cardIds.join(',')}';
  }

  /// Parses a place-cover action id.
  static CoverActionTarget? coverActionTarget(String actionId) {
    if (!actionId.startsWith(placeCoverPrefix)) {
      return null;
    }
    final payload = actionId.substring(placeCoverPrefix.length);
    final parts = payload.split(':');
    if (parts.length != 3) {
      return null;
    }
    final seat = PlayerSeat.fromName(parts[0]);
    final meldIndex = int.tryParse(parts[1]);
    if (seat == null || meldIndex == null) {
      return null;
    }
    final cardIds = parts[2]
        .split(',')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    return CoverActionTarget(
      targetSeat: seat,
      meldIndex: meldIndex,
      cardIds: cardIds,
    );
  }
}

/// Parsed target for placing covers on an existing meld.
class CoverActionTarget {
  /// Creates a parsed cover action target.
  const CoverActionTarget({
    required this.targetSeat,
    required this.meldIndex,
    required this.cardIds,
  });

  /// Seat that owns the meld being extended.
  final PlayerSeat targetSeat;

  /// Index of the meld in the owner's table area.
  final int meldIndex;

  /// Physical cover card ids to place.
  final List<String> cardIds;
}

/// Live Classic Hareeg game state controller.
///
/// Owns the dealt round + turn-flow state and exposes the rules-engine seam
/// described in [ADR 0001](../../../docs/adr/0001-rules-engine-boundary.md).
/// The Flutter UI and CPU strategy both interact with the game exclusively
/// through [legalActionIdsFor] and [applyAction]; this is the single point at
/// which moves are validated against the rules engine.
class ClassicHareegGameController {
  /// Creates a controller from a dealt round.
  ClassicHareegGameController.fromRound(ClassicHareegRound round)
    : setup = round.setup,
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
      _starter = round.starter,
      _currentSeat = round.currentSeat,
      _phase = round.turnPhase,
      _pendingDiscard = null,
      _previousDiscardSeat = null,
      _roundOutcome = null {
    _evaluateRoundEnd();
  }

  /// Creates a controller restored from a persisted snapshot.
  ClassicHareegGameController.fromSnapshot(
    ClassicHareegMatchSnapshot snapshot, {
    ClassicHareegRules? rules,
  }) : setup = snapshot.setup,
       rules = rules ?? ClassicHareegRules.defaults(),
       _hands = {
         for (final entry in snapshot.hands.entries)
           entry.key: List<HareegCard>.of(entry.value),
       },
       _stock = List<HareegCard>.of(snapshot.stock),
       _discardPile = List<HareegCard>.of(snapshot.discardPile),
       _tableMelds = {
         for (final seat in PlayerSeat.values)
           seat: List<PlacedMeld>.of(snapshot.tableMelds[seat] ?? const []),
       },
       _starter = snapshot.starter,
       _currentSeat = snapshot.currentSeat,
       _phase = snapshot.turnPhase,
       _pendingDiscard = snapshot.pendingDiscard,
       _previousDiscardSeat = snapshot.discardPile.isEmpty
           ? null
           : snapshot.currentSeat.previousAntiClockwise,
       _roundOutcome = null {
    _evaluateRoundEnd();
  }

  /// Setup values used to deal the active round.
  final ClassicHareegSetup setup;

  /// Rules active for this round.
  final ClassicHareegRules rules;

  final Map<PlayerSeat, List<HareegCard>> _hands;
  final List<HareegCard> _stock;
  final List<HareegCard> _discardPile;
  final Map<PlayerSeat, List<PlacedMeld>> _tableMelds;
  final PlayerSeat _starter;
  PlayerSeat _currentSeat;
  TurnPhase _phase;
  HareegCard? _pendingDiscard;
  PlayerSeat? _previousDiscardSeat;
  RoundOutcomeType? _roundOutcome;

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

  /// Snapshots the live game state for persistence.
  ClassicHareegMatchSnapshot toSnapshot({DateTime? savedAt}) {
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
      savedAt: savedAt ?? DateTime.now().toUtc(),
    );
  }

  /// Returns the legal action ids for [seat] under the current state.
  ///
  /// Empty when the round has ended, when it is not the seat's turn, or when
  /// the seat has no legal action remaining (e.g. stock exhaustion that the
  /// controller has not yet converted to a [RoundOutcomeType.draw] outcome).
  List<String> legalActionIdsFor(PlayerSeat seat) {
    if (_roundOutcome != null || seat != _currentSeat) {
      return const [];
    }

    if (_pendingDiscard != null) {
      return List.unmodifiable([
        ClassicHareegActionIds.usePendingDiscard,
        if (_stock.isNotEmpty) ClassicHareegActionIds.returnPendingDiscard,
      ]);
    }

    if (_phase == TurnPhase.action) {
      return _discardActionIds(seat);
    }

    final ids = <String>[];
    if (_stock.isNotEmpty) {
      ids.add(ClassicHareegActionIds.drawStock);
    }
    if (_canTakePreviousDiscard) {
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

    final meldCardIds = ClassicHareegActionIds.meldCardIds(actionId);
    if (meldCardIds != null) {
      return _applyPlayMeld(meldCardIds);
    }

    final coverTarget = ClassicHareegActionIds.coverActionTarget(actionId);
    if (coverTarget != null) {
      return _applyPlaceCover(coverTarget);
    }

    if (!legalActionIdsFor(_currentSeat).contains(actionId)) {
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
    final cards = _cardsFromHand(seat, cardIds);
    if (cards == null) {
      return const MeldValidationResult.invalid(
        'Selected cards are not all in hand.',
      );
    }
    return _resolveMeldCards(cards).result;
  }

  /// Returns a legal cover action id for [cardIds], if they can extend a meld.
  String? coverActionIdFor(PlayerSeat seat, List<String> cardIds) {
    if (seat != _currentSeat || _phase != TurnPhase.action || cardIds.isEmpty) {
      return null;
    }
    final cards = _cardsFromHand(seat, cardIds);
    if (cards == null) {
      return null;
    }

    for (final owner in PlayerSeat.values) {
      final melds = _tableMelds[owner] ?? const <PlacedMeld>[];
      for (var index = 0; index < melds.length; index += 1) {
        final ordered = _orderedCoverCards(
          tableMeld: melds[index].cards,
          candidates: cards,
        );
        if (ordered != null) {
          return ClassicHareegActionIds.placeCoverActionId(
            targetSeat: owner,
            meldIndex: index,
            cardIds: cardIds,
          );
        }
      }
    }
    return null;
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
    return const ApplyActionResult.success();
  }

  ApplyActionResult _applyTakePreviousDiscard() {
    final card = _discardPile.removeLast();
    _handFor(_currentSeat).add(card);
    _pendingDiscard = card;
    _phase = TurnPhase.action;
    return const ApplyActionResult.success();
  }

  ApplyActionResult _applyUsePendingDiscard() {
    _pendingDiscard = null;
    _phase = TurnPhase.action;
    return const ApplyActionResult.success();
  }

  ApplyActionResult _applyReturnPendingDiscard() {
    final pending = _pendingDiscard!;
    final hand = _handFor(_currentSeat);
    hand.removeWhere((card) => card.id == pending.id);
    hand.add(_stock.removeLast());
    _discardPile.add(pending);
    _pendingDiscard = null;
    _phase = TurnPhase.action;
    return const ApplyActionResult.success();
  }

  ApplyActionResult _applyPlayMeld(List<String> cardIds) {
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

    final resolved = _resolveMeldCards(selectedCards);
    if (!resolved.result.isValid) {
      return ApplyActionResult.failure(resolved.result.message);
    }

    final meld = PlacedMeld.fromCards(resolved.cards);
    for (final id in uniqueIds) {
      hand.removeWhere((card) => card.id == id);
    }
    _tableMelds.putIfAbsent(_currentSeat, () => <PlacedMeld>[]).add(meld);
    if (pending != null) {
      _pendingDiscard = null;
    }
    return const ApplyActionResult.success('Meld played.');
  }

  ApplyActionResult _applyPlaceCover(CoverActionTarget target) {
    if (_phase != TurnPhase.action) {
      return const ApplyActionResult.failure('Draw before placing a cover.');
    }
    if (target.cardIds.isEmpty) {
      return const ApplyActionResult.failure('Select a cover card.');
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

    final hand = _handFor(_currentSeat);
    for (final card in ordered) {
      hand.removeWhere((candidate) => candidate.id == card.id);
    }
    targetMelds[target.meldIndex] = targetMeld.addCoverCards(ordered);
    if (pending != null) {
      _pendingDiscard = null;
    }
    return const ApplyActionResult.success('Cover placed.');
  }

  ApplyActionResult _applyDiscard(String cardId) {
    final hand = _handFor(_currentSeat);
    final index = hand.indexWhere((card) => card.id == cardId);
    if (index == -1) {
      return ApplyActionResult.failure('Card "$cardId" is not in the hand.');
    }

    final card = hand[index];
    if (!ClassicHareegJokerRules.canDiscard(card, isFinalDiscard: false)) {
      return const ApplyActionResult.failure(
        'Jokers cannot be discarded during normal play.',
      );
    }

    final coverResult = ClassicHareegCoverRules.canDiscard(
      tableMelds: _tableMeldCardLists,
      candidate: card,
      isFinalDiscard: false,
    );
    if (!coverResult.canDiscard) {
      return ApplyActionResult.failure(coverResult.message);
    }

    hand.removeAt(index);
    _discardPile.add(card);
    _previousDiscardSeat = _currentSeat;
    _pendingDiscard = null;
    _currentSeat = _currentSeat.nextAntiClockwise;
    _phase = TurnPhase.draw;
    _evaluateRoundEnd();
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

    final exhaustion = ClassicHareegFinishRules.evaluateStockExhaustion(
      stockIsEmpty: _stock.isEmpty,
      previousDiscardCanFinish: false,
      pickupWouldFinish: false,
    );
    if (exhaustion.decision == StockExhaustionDecision.roundDraw) {
      _roundOutcome = RoundOutcomeType.draw;
    }
  }

  bool get _canTakePreviousDiscard {
    final previousSeat = _previousDiscardSeat;
    return _phase == TurnPhase.draw &&
        previousSeat != null &&
        _discardPile.isNotEmpty &&
        previousSeat.nextAntiClockwise == _currentSeat;
  }

  List<List<HareegCard>> get _tableMeldCardLists {
    return [
      for (final melds in _tableMelds.values)
        for (final meld in melds) meld.cards,
    ];
  }

  _ResolvedMeldCards _resolveMeldCards(List<HareegCard> cards) {
    final direct = ClassicHareegMeldValidator.validate(cards);
    if (direct.isValid) {
      return _ResolvedMeldCards(cards: cards, result: direct);
    }

    final unresolvedJokers = cards
        .where((card) => card.isJoker && card.representedIdentity == null)
        .toList(growable: false);
    if (unresolvedJokers.length != 1) {
      return _ResolvedMeldCards(cards: cards, result: direct);
    }

    final joker = unresolvedJokers.single;
    final options = ClassicHareegJokerRules.representationOptionsForMeld(
      cards: cards,
      joker: joker,
    );
    if (options.isEmpty) {
      return _ResolvedMeldCards(cards: cards, result: direct);
    }
    if (options.length > 1) {
      return _ResolvedMeldCards(
        cards: cards,
        result: const MeldValidationResult.invalid(
          'Choose what the joker represents.',
        ),
      );
    }

    final identity = options.single;
    final resolvedCards = cards
        .map((card) {
          if (card.id == joker.id) {
            return joker.asRepresenting(identity);
          }
          return card;
        })
        .toList(growable: false);
    final resolved = ClassicHareegMeldValidator.validate(resolvedCards);
    if (!resolved.isValid) {
      return _ResolvedMeldCards(cards: cards, result: resolved);
    }

    return _ResolvedMeldCards(
      cards: resolvedCards,
      result: MeldValidationResult.valid(
        type: resolved.type!,
        value: resolved.value,
        message: '${resolved.message} Joker as ${identity.label}.',
      ),
    );
  }

  List<HareegCard>? _orderedCoverCards({
    required List<HareegCard> tableMeld,
    required List<HareegCard> candidates,
  }) {
    if (candidates.isEmpty) {
      return const [];
    }

    for (var index = 0; index < candidates.length; index += 1) {
      final candidate = candidates[index];
      if (!ClassicHareegCoverRules.isCover(
        tableMeld: tableMeld,
        candidate: candidate,
      )) {
        continue;
      }
      final remaining = [
        ...candidates.take(index),
        ...candidates.skip(index + 1),
      ];
      final next = _orderedCoverCards(
        tableMeld: [...tableMeld, candidate],
        candidates: remaining,
      );
      if (next != null) {
        return [candidate, ...next];
      }
    }
    return null;
  }

  List<String> _discardActionIds(PlayerSeat seat) {
    final hand = _hands[seat] ?? const <HareegCard>[];
    final ids = <String>[];
    for (final card in hand) {
      final jokerCanDiscard = ClassicHareegJokerRules.canDiscard(
        card,
        isFinalDiscard: false,
      );
      final coverResult = ClassicHareegCoverRules.canDiscard(
        tableMelds: _tableMeldCardLists,
        candidate: card,
        isFinalDiscard: false,
      );
      final prefix = !jokerCanDiscard
          ? ClassicHareegActionIds.discardJokerPrefix
          : !coverResult.canDiscard
          ? ClassicHareegActionIds.discardBlockedCoverPrefix
          : ClassicHareegActionIds.discardPrefix;
      ids.add('$prefix${card.id}');
    }
    return List.unmodifiable(ids);
  }
}

/// Inverse of [PlayerSeat.nextAntiClockwise] used when restoring discard state
/// from a snapshot that doesn't record the discarding seat.
extension on PlayerSeat {
  PlayerSeat get previousAntiClockwise {
    return switch (this) {
      PlayerSeat.south => PlayerSeat.west,
      PlayerSeat.east => PlayerSeat.south,
      PlayerSeat.north => PlayerSeat.east,
      PlayerSeat.west => PlayerSeat.north,
    };
  }
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
