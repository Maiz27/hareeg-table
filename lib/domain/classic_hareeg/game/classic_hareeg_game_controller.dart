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

  /// Claim Fifty / Khamsin from the immediate previous discard.
  static const claimFifty = 'claim-fifty';

  /// Play selected cards as a meld. Card ids follow the prefix, comma-separated.
  static const playMeldPrefix = 'play-meld:';

  /// Play selected cards with an explicit represented identity for one joker.
  static const playMeldWithJokerPrefix = 'play-meld-joker:';

  /// Place selected cover cards on an existing meld.
  static const placeCoverPrefix = 'place-cover:';

  /// Replace a represented joker on the table with a matching real card.
  static const replaceJokerPrefix = 'replace-joker:';

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

  /// Creates a play-meld action id with an explicit joker representation.
  static String playMeldWithJokerIdentityActionId({
    required Iterable<String> cardIds,
    required String jokerId,
    required CardIdentity identity,
  }) {
    return '$playMeldWithJokerPrefix$jokerId:${identity.key}:${cardIds.join(',')}';
  }

  /// Parses an explicit joker-representation meld action id.
  static JokerMeldActionChoice? jokerMeldChoice(String actionId) {
    if (!actionId.startsWith(playMeldWithJokerPrefix)) {
      return null;
    }
    final payload = actionId.substring(playMeldWithJokerPrefix.length);
    final parts = payload.split(':');
    if (parts.length != 3) {
      return null;
    }
    final identity = _identityFromKey(parts[1]);
    if (identity == null) {
      return null;
    }
    final cardIds = parts[2]
        .split(',')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    return JokerMeldActionChoice(
      jokerId: parts[0],
      identity: identity,
      cardIds: cardIds,
    );
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

  /// Creates a joker replacement action id.
  static String replaceJokerActionId({
    required PlayerSeat targetSeat,
    required int meldIndex,
    required String cardId,
  }) {
    return '$replaceJokerPrefix${targetSeat.name}:$meldIndex:$cardId';
  }

  /// Parses a joker replacement action id.
  static JokerReplacementActionTarget? jokerReplacementTarget(String actionId) {
    if (!actionId.startsWith(replaceJokerPrefix)) {
      return null;
    }
    final payload = actionId.substring(replaceJokerPrefix.length);
    final parts = payload.split(':');
    if (parts.length != 3) {
      return null;
    }
    final seat = PlayerSeat.fromName(parts[0]);
    final meldIndex = int.tryParse(parts[1]);
    if (seat == null || meldIndex == null || parts[2].isEmpty) {
      return null;
    }
    return JokerReplacementActionTarget(
      targetSeat: seat,
      meldIndex: meldIndex,
      cardId: parts[2],
    );
  }
}

/// Explicit represented joker choice for a meld action.
class JokerMeldActionChoice {
  /// Creates a parsed joker meld choice.
  const JokerMeldActionChoice({
    required this.jokerId,
    required this.identity,
    required this.cardIds,
  });

  /// Physical joker id being assigned.
  final String jokerId;

  /// Represented identity selected for the joker.
  final CardIdentity identity;

  /// Physical card ids in the selected meld play.
  final List<String> cardIds;
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

/// Parsed target for replacing a represented table joker.
class JokerReplacementActionTarget {
  /// Creates a parsed joker replacement target.
  const JokerReplacementActionTarget({
    required this.targetSeat,
    required this.meldIndex,
    required this.cardId,
  });

  /// Seat that owns the meld containing the represented joker.
  final PlayerSeat targetSeat;

  /// Index of the meld in the owner's table area.
  final int meldIndex;

  /// Physical replacement card id from the current player's hand.
  final String cardId;
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
       _turnSource = FinishCardSource.stock {
    _evaluateRoundEnd();
  }

  /// Creates a controller restored from a persisted snapshot.
  ClassicHareegGameController.fromSnapshot(
    ClassicHareegMatchSnapshot snapshot, {
    ClassicHareegRules? rules,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       setup = snapshot.setup,
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
       _scores = {
         for (final seat in PlayerSeat.values) seat: snapshot.scores[seat] ?? 0,
       },
       _activeSeats = List<PlayerSeat>.of(snapshot.activeSeats),
       _openingState =
           snapshot.openingState ??
           OpeningState.initial(snapshot.setup.openingRequirement),
       _roundNumber = snapshot.roundNumber,
       _removedSeats = snapshot.removedSeats.toSet(),
       _starter = snapshot.starter,
       _currentSeat = snapshot.currentSeat,
       _phase = snapshot.turnPhase,
       _pendingDiscard = snapshot.pendingDiscard,
       _previousDiscardSeat = snapshot.discardPile.isEmpty
           ? null
           : snapshot.currentSeat.previousAntiClockwise,
       _fiftyWindow =
           snapshot.discardPile.isEmpty || snapshot.turnPhase != TurnPhase.draw
           ? null
           : ClassicHareegFiftyRules.openWindow(
               discarder: snapshot.currentSeat.previousAntiClockwise,
               claimant: snapshot.currentSeat,
               discardedCard: snapshot.discardPile.last,
               durationSeconds: snapshot.setup.fiftyTimerSeconds,
               isFirstDealtRound: snapshot.roundNumber == 1,
             ),
       _fiftyWindowOpenedAt =
           snapshot.discardPile.isEmpty || snapshot.turnPhase != TurnPhase.draw
           ? null
           : (now ?? DateTime.now)(),
       _roundOutcome = null,
       _roundResult = null,
       _turnFinishPlays = <PlacedMeld>[],
       _turnOpeningMelds = <PlacedMeld>[],
       _turnSource = snapshot.pendingDiscard == null
           ? FinishCardSource.stock
           : FinishCardSource.previousDiscard {
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
  FinishCardSource _turnSource;

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
  MatchProgressState? get roundProgress {
    final result = _roundResult;
    if (result == null) {
      return null;
    }

    return ClassicHareegMatchProgressionRules.applyRoundResult(
      scores: _scores,
      activeSeats: _activeSeats,
      currentStarter: _starter,
      result: result,
      eliminationScore: rules.eliminationScore,
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
      openingState: _openingState,
      scores: Map<PlayerSeat, int>.of(_scores),
      activeSeats: List<PlayerSeat>.of(_activeSeats),
      roundNumber: _roundNumber,
      removedSeats: _removedSeats.toList(growable: false),
      savedAt: savedAt ?? DateTime.now().toUtc(),
    );
  }

  /// Deals the next round snapshot after this round has produced progress.
  ClassicHareegMatchSnapshot? nextRoundSnapshot({DateTime? savedAt}) {
    final progress = roundProgress;
    if (progress == null || progress.matchWinner != null) {
      return null;
    }

    final round = ClassicHareegRound.deal(
      setup: setup,
      rules: rules,
      activeSeats: progress.activeSeats,
      starterOverride: progress.nextStarter,
    );
    return ClassicHareegMatchSnapshot(
      setup: setup,
      hands: round.hands,
      stock: round.stock,
      discardPile: round.discardPile,
      tableMelds: {
        for (final seat in PlayerSeat.values) seat: const <PlacedMeld>[],
      },
      starter: round.starter,
      currentSeat: round.currentSeat,
      turnPhase: round.turnPhase,
      openingState: OpeningState.initial(setup.openingRequirement),
      scores: progress.scores,
      activeSeats: progress.activeSeats,
      roundNumber: _roundNumber + 1,
      savedAt: savedAt ?? DateTime.now().toUtc(),
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
        if (_stock.isNotEmpty) ClassicHareegActionIds.returnPendingDiscard,
      ];
      return List.unmodifiable(ids);
    }

    if (_phase == TurnPhase.action) {
      return List.unmodifiable([
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
        jokerId: jokerChoice.jokerId,
        jokerIdentity: jokerChoice.identity,
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
    final cards = _cardsFromHand(seat, cardIds);
    if (cards == null) {
      return const MeldValidationResult.invalid(
        'Selected cards are not all in hand.',
      );
    }
    return _resolveTablePlay(cards).result;
  }

  /// Returns explicit represented-card choices needed for an ambiguous joker.
  List<CardIdentity> jokerRepresentationOptionsFor(
    PlayerSeat seat,
    List<String> cardIds,
  ) {
    final cards = _cardsFromHand(seat, cardIds);
    if (cards == null) {
      return const [];
    }
    final unresolvedJokers = cards
        .where((card) => card.isJoker && card.representedIdentity == null)
        .toList(growable: false);
    if (unresolvedJokers.length != 1) {
      return const [];
    }

    final options = ClassicHareegJokerRules.representationOptionsForMeld(
      cards: cards,
      joker: unresolvedJokers.single,
    );
    return options.length > 1 ? options : const [];
  }

  /// Returns a legal cover action id for [cardIds], if they can extend a meld.
  String? coverActionIdFor(PlayerSeat seat, List<String> cardIds) {
    if (seat != _currentSeat ||
        _phase != TurnPhase.action ||
        cardIds.isEmpty ||
        !ClassicHareegCoverRules.canPlayCover(
          playerOpened: _openingState.hasOpened(seat),
        )) {
      return null;
    }
    final cards = _cardsFromHand(seat, cardIds);
    if (cards == null) {
      return null;
    }
    if ((_hands[seat]?.length ?? 0) - cards.length == 0) {
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

  /// Returns a joker replacement action id for one selected real card.
  String? jokerReplacementActionIdFor(PlayerSeat seat, List<String> cardIds) {
    if (seat != _currentSeat || cardIds.length != 1) {
      return null;
    }
    return _replacementActionIdForCardId(seat, cardIds.single);
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
    hand.add(_stock.removeLast());
    _discardPile.add(pending);
    _pendingDiscard = null;
    _phase = TurnPhase.action;
    _fiftyWindow = null;
    _fiftyWindowOpenedAt = null;
    _turnFinishPlays = <PlacedMeld>[];
    _turnOpeningMelds = <PlacedMeld>[];
    _turnSource = FinishCardSource.stock;
    return const ApplyActionResult.success();
  }

  ApplyActionResult _applyPlayMeld(
    List<String> cardIds, {
    String? jokerId,
    CardIdentity? jokerIdentity,
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
      _openingState = ClassicHareegOpeningRules.recordBenchmarkContribution(
        state: _openingState,
        seat: _currentSeat,
        value: value,
      );
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
    }
    return ApplyActionResult.success(message);
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
    for (final card in ordered) {
      hand.removeWhere((candidate) => candidate.id == card.id);
    }
    targetMelds[target.meldIndex] = targetMeld.addCoverCards(ordered);
    final coverValue = ordered.fold<int>(0, (total, card) {
      return total + (card.effectiveIdentity?.rank.value ?? 0);
    });
    _turnFinishPlays = [
      ..._turnFinishPlays,
      PlacedMeld(cards: List.unmodifiable(ordered), valueSnapshot: coverValue),
    ];
    _openingState = ClassicHareegOpeningRules.recordBenchmarkContribution(
      state: _openingState,
      seat: _currentSeat,
      value: coverValue,
    );
    if (pending != null) {
      _pendingDiscard = null;
    }
    return const ApplyActionResult.success('Cover placed.');
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
    final cards = [..._handFor(seat), discarded];
    if (!_hasValidMeldContaining(cards, discarded.id)) {
      return false;
    }
    return _finishPlanForCards(
          cards,
          requiredPlayedCardId: discarded.id,
          source: FinishCardSource.previousDiscard,
          perfectHandAttempt: true,
        ) !=
        null;
  }

  bool _hasValidMeldContaining(List<HareegCard> cards, String cardId) {
    for (final group in _candidateGroups(cards, minSize: 3, maxSize: 5)) {
      if (!group.any((card) => card.id == cardId)) {
        continue;
      }
      if (_resolveMeldCards(group).result.isValid) {
        return true;
      }
    }
    return false;
  }

  _FinishPlan? _finishPlanForCards(
    List<HareegCard> cards, {
    String? requiredPlayedCardId,
    required FinishCardSource source,
    required bool perfectHandAttempt,
  }) {
    for (final finalDiscard in cards) {
      if (finalDiscard.id == requiredPlayedCardId) {
        continue;
      }
      final remaining = cards
          .where((card) => card.id != finalDiscard.id)
          .toList(growable: false);
      final melds = _partitionIntoMelds(
        remaining,
        <String, List<PlacedMeld>?>{},
      );
      if (melds == null) {
        continue;
      }
      if (requiredPlayedCardId != null &&
          !melds.any(
            (meld) => meld.cards.any((card) => card.id == requiredPlayedCardId),
          )) {
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
        return _FinishPlan(melds: melds, finalDiscard: finalDiscard);
      }
    }
    return null;
  }

  List<String> _playMeldActionIds(PlayerSeat seat, {String? mustUseCardId}) {
    if (_phase != TurnPhase.action) {
      return const [];
    }

    final hand = _hands[seat] ?? const <HareegCard>[];
    final ids = <String>{};
    for (final group in _candidateGroups(hand, minSize: 3, maxSize: 5)) {
      if (hand.length - group.length == 0) {
        continue;
      }
      if (mustUseCardId != null &&
          !group.any((card) => card.id == mustUseCardId)) {
        continue;
      }
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
        continue;
      }
      final meld = PlacedMeld.fromCards(resolved.cards);
      if (!_openingState.hasOpened(seat)) {
        final opening = ClassicHareegOpeningRules.validateOpening(
          state: _openingState,
          seat: seat,
          melds: [..._turnOpeningMelds, meld],
        );
        final leavesFinalDiscard = hand.length - group.length == 1;
        if (!opening.isValid && !leavesFinalDiscard) {
          continue;
        }
      }
      ids.add(
        jokerId == null || jokerIdentity == null
            ? ClassicHareegActionIds.playMeldActionId(
                group.map((card) => card.id),
              )
            : ClassicHareegActionIds.playMeldWithJokerIdentityActionId(
                cardIds: group.map((card) => card.id),
                jokerId: jokerId,
                identity: jokerIdentity,
              ),
      );
      break;
    }
    return List.unmodifiable(ids);
  }

  List<String> _replaceJokerActionIds(
    PlayerSeat seat, {
    String? mustUseCardId,
  }) {
    if (_phase != TurnPhase.action ||
        !ClassicHareegCoverRules.canPlayCover(
          playerOpened: _openingState.hasOpened(seat),
        )) {
      return const [];
    }

    final hand = _hands[seat] ?? const <HareegCard>[];
    for (final card in hand) {
      if (mustUseCardId != null && card.id != mustUseCardId) {
        continue;
      }
      final actionId = _replacementActionIdForCardId(seat, card.id);
      if (actionId != null) {
        return [actionId];
      }
    }
    return const [];
  }

  String? _replacementActionIdForCardId(PlayerSeat seat, String cardId) {
    if (!_openingState.hasOpened(seat)) {
      return null;
    }
    final hand = _hands[seat] ?? const <HareegCard>[];
    final cardIndex = hand.indexWhere((candidate) => candidate.id == cardId);
    if (cardIndex == -1) {
      return null;
    }
    final card = hand[cardIndex];

    for (final owner in PlayerSeat.values) {
      final melds = _tableMelds[owner] ?? const <PlacedMeld>[];
      for (var index = 0; index < melds.length; index += 1) {
        if (ClassicHareegJokerRules.canReplaceJoker(
          playerOpened: true,
          tableCards: melds[index].cards,
          replacementCard: card,
        )) {
          return ClassicHareegActionIds.replaceJokerActionId(
            targetSeat: owner,
            meldIndex: index,
            cardId: card.id,
          );
        }
      }
    }
    return null;
  }

  List<String> _coverActionIds(PlayerSeat seat, {String? mustUseCardId}) {
    if (_phase != TurnPhase.action ||
        !ClassicHareegCoverRules.canPlayCover(
          playerOpened: _openingState.hasOpened(seat),
        )) {
      return const [];
    }

    final hand = _hands[seat] ?? const <HareegCard>[];
    final ids = <String>{};
    for (final group in _candidateGroups(hand, minSize: 1, maxSize: 3)) {
      if (hand.length - group.length == 0) {
        continue;
      }
      if (mustUseCardId != null &&
          !group.any((card) => card.id == mustUseCardId)) {
        continue;
      }
      for (final owner in PlayerSeat.values) {
        final melds = _tableMelds[owner] ?? const <PlacedMeld>[];
        for (var index = 0; index < melds.length; index += 1) {
          final ordered = _orderedCoverCards(
            tableMeld: melds[index].cards,
            candidates: group,
          );
          if (ordered != null) {
            ids.add(
              ClassicHareegActionIds.placeCoverActionId(
                targetSeat: owner,
                meldIndex: index,
                cardIds: group.map((card) => card.id),
              ),
            );
            return List.unmodifiable(ids);
          }
        }
      }
    }
    return List.unmodifiable(ids);
  }

  _ResolvedTablePlay _resolveTablePlay(
    List<HareegCard> cards, {
    String? jokerId,
    CardIdentity? jokerIdentity,
  }) {
    final single = _resolveMeldCards(
      cards,
      jokerId: jokerId,
      jokerIdentity: jokerIdentity,
    );
    if (single.result.isValid) {
      return _ResolvedTablePlay(
        melds: [PlacedMeld.fromCards(single.cards)],
        result: single.result,
      );
    }

    final melds = _partitionIntoMelds(
      cards,
      <String, List<PlacedMeld>?>{},
      jokerId: jokerId,
      jokerIdentity: jokerIdentity,
    );
    if (melds == null) {
      return _ResolvedTablePlay(melds: const [], result: single.result);
    }

    final value = melds.fold<int>(
      0,
      (total, meld) => total + meld.valueSnapshot,
    );
    return _ResolvedTablePlay(
      melds: melds,
      result: MeldValidationResult.valid(
        type: MeldType.set,
        value: value,
        message: 'Valid table play.',
      ),
    );
  }

  List<PlacedMeld>? _partitionIntoMelds(
    List<HareegCard> cards,
    Map<String, List<PlacedMeld>?> memo, {
    String? jokerId,
    CardIdentity? jokerIdentity,
  }) {
    if (cards.isEmpty) {
      return const [];
    }
    if (cards.length < 3) {
      return null;
    }

    final key = (cards.map((card) => card.id).toList()..sort()).join('|');
    if (memo.containsKey(key)) {
      return memo[key];
    }

    final first = cards.first;
    for (final group in _candidateGroupsContainingFirst(cards, first)) {
      final resolved = _resolveMeldCards(
        group,
        jokerId: jokerId,
        jokerIdentity: jokerIdentity,
      );
      if (!resolved.result.isValid) {
        continue;
      }
      final groupIds = group.map((card) => card.id).toSet();
      final remaining = cards
          .where((card) => !groupIds.contains(card.id))
          .toList(growable: false);
      final rest = _partitionIntoMelds(
        remaining,
        memo,
        jokerId: jokerId,
        jokerIdentity: jokerIdentity,
      );
      if (rest != null) {
        final result = [PlacedMeld.fromCards(resolved.cards), ...rest];
        memo[key] = result;
        return result;
      }
    }
    memo[key] = null;
    return null;
  }

  Iterable<List<HareegCard>> _candidateGroupsContainingFirst(
    List<HareegCard> cards,
    HareegCard first,
  ) sync* {
    final rest = cards.where((card) => card.id != first.id).toList();
    final maxMask = 1 << rest.length;
    for (var mask = 0; mask < maxMask; mask += 1) {
      final group = <HareegCard>[first];
      for (var index = 0; index < rest.length; index += 1) {
        if ((mask & (1 << index)) != 0) {
          group.add(rest[index]);
        }
      }
      if (group.length >= 3) {
        yield group;
      }
    }
  }

  Iterable<List<HareegCard>> _candidateGroups(
    List<HareegCard> cards, {
    required int minSize,
    int? maxSize,
  }) sync* {
    final count = cards.length;
    if (count == 0 || count > 20) {
      return;
    }
    final effectiveMaxSize = maxSize ?? count;

    final maxMask = 1 << count;
    for (var mask = 1; mask < maxMask; mask += 1) {
      final group = <HareegCard>[];
      for (var index = 0; index < count; index += 1) {
        if ((mask & (1 << index)) != 0) {
          group.add(cards[index]);
        }
      }
      if (group.length >= minSize && group.length <= effectiveMaxSize) {
        yield group;
      }
    }
  }

  _ResolvedMeldCards _resolveMeldCards(
    List<HareegCard> cards, {
    String? jokerId,
    CardIdentity? jokerIdentity,
  }) {
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

    CardIdentity? identity;
    if (jokerId != null || jokerIdentity != null) {
      if (jokerId != joker.id || jokerIdentity == null) {
        return _ResolvedMeldCards(
          cards: cards,
          result: const MeldValidationResult.invalid(
            'Selected joker identity does not match this meld.',
          ),
        );
      }
      if (!options.contains(jokerIdentity)) {
        return _ResolvedMeldCards(
          cards: cards,
          result: MeldValidationResult.invalid(
            'Joker cannot represent ${jokerIdentity.label} here.',
          ),
        );
      }
      identity = jokerIdentity;
    } else if (options.length == 1) {
      identity = options.single;
    } else {
      return _ResolvedMeldCards(
        cards: cards,
        result: const MeldValidationResult.invalid(
          'Choose what the joker represents.',
        ),
      );
    }

    final CardIdentity chosenIdentity = identity;
    final resolvedCards = cards
        .map((card) {
          if (card.id == joker.id) {
            return joker.asRepresenting(chosenIdentity);
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
        message: '${resolved.message} Joker as ${chosenIdentity.label}.',
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
      final resolvedCandidate = _resolveCoverCandidate(
        tableMeld: tableMeld,
        candidate: candidate,
      );
      if (resolvedCandidate == null) {
        continue;
      }
      final remaining = [
        ...candidates.take(index),
        ...candidates.skip(index + 1),
      ];
      final next = _orderedCoverCards(
        tableMeld: [...tableMeld, resolvedCandidate],
        candidates: remaining,
      );
      if (next != null) {
        return [resolvedCandidate, ...next];
      }
    }
    return null;
  }

  HareegCard? _resolveCoverCandidate({
    required List<HareegCard> tableMeld,
    required HareegCard candidate,
  }) {
    if (ClassicHareegCoverRules.isCover(
      tableMeld: tableMeld,
      candidate: candidate,
    )) {
      return candidate;
    }
    if (!candidate.isJoker || candidate.representedIdentity != null) {
      return null;
    }

    final options = <CardIdentity>[];
    for (final suit in CardSuit.values) {
      for (final rank in CardRank.values) {
        final identity = CardIdentity(rank: rank, suit: suit);
        if (ClassicHareegCoverRules.isCover(
          tableMeld: tableMeld,
          candidate: candidate.asRepresenting(identity),
        )) {
          options.add(identity);
        }
      }
    }
    if (options.isEmpty) {
      return null;
    }
    options.sort((left, right) {
      final suitCompare = left.suit.index.compareTo(right.suit.index);
      if (suitCompare != 0) {
        return suitCompare;
      }
      return left.rank.order.compareTo(right.rank.order);
    });
    return candidate.asRepresenting(options.first);
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
      if (!coverResult.canDiscard && setup.rulePreset == RulePreset.assisted) {
        continue;
      }
      final prefix = !coverResult.canDiscard
          ? ClassicHareegActionIds.discardBlockedCoverPrefix
          : ClassicHareegActionIds.discardPrefix;
      ids.add('$prefix${card.id}');
    }
    return List.unmodifiable(ids);
  }
}

CardIdentity? _identityFromKey(String key) {
  final parts = key.split('-');
  if (parts.length != 2) {
    return null;
  }
  final rank = CardRank.fromName(parts[0]);
  final suit = CardSuit.fromName(parts[1]);
  if (rank == null || suit == null) {
    return null;
  }
  return CardIdentity(rank: rank, suit: suit);
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

class _ResolvedTablePlay {
  const _ResolvedTablePlay({required this.melds, required this.result});

  final List<PlacedMeld> melds;
  final MeldValidationResult result;
}

class _FinishPlan {
  const _FinishPlan({required this.melds, required this.finalDiscard});

  final List<PlacedMeld> melds;
  final HareegCard finalDiscard;
}
