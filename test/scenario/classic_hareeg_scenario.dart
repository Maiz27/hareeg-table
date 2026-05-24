import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

/// Thin builder over [ClassicHareegGameController] that lets a test read like
/// a game narrative. The DSL is intentionally not an abstraction layer over
/// the controller — it is one place for "build a state, do a thing, ask a
/// thing" so the mechanical snapshot wiring stays out of test bodies.
///
/// Typical use:
///
/// ```dart
/// final s = ClassicHareegScenario.deal(
///   setup: ClassicHareegSetup.defaults()
///       .copyWith(tableStrictness: TableStrictness.table),
///   seed: 11,
///   southHand: [eightD, nineD, tenD, ...],
///   openingState: openedFor(PlayerSeat.south),
/// );
/// s.south.playMeld([eightD, nineD, tenD]);
/// s.south.discard(twoS);
/// expect(s.controller.handFor(PlayerSeat.south), hasLength(originalLen - 4));
/// ```
class ClassicHareegScenario {
  ClassicHareegScenario._(this.controller);

  /// Live controller the scenario drives. Tests use this for the post-action
  /// assertions (`controller.topDiscard`, `controller.removedSeats`,
  /// `controller.legalActionIdsFor(seat)`, ...).
  final ClassicHareegGameController controller;

  /// South seat scope.
  SeatScope get south => SeatScope._(controller, PlayerSeat.south);

  /// East seat scope.
  SeatScope get east => SeatScope._(controller, PlayerSeat.east);

  /// North seat scope.
  SeatScope get north => SeatScope._(controller, PlayerSeat.north);

  /// West seat scope.
  SeatScope get west => SeatScope._(controller, PlayerSeat.west);

  /// Returns the seat scope for [seat].
  SeatScope seat(PlayerSeat seat) => SeatScope._(controller, seat);

  /// Builds a scenario from a fresh deal plus optional per-seat hand
  /// overrides. Anything not overridden comes from the seeded deal so we keep
  /// a deterministic, fully populated stock + discard pile.
  ///
  /// The DSL leans on the snapshot factory (rather than [ClassicHareegRound]
  /// directly) so callers can also start mid-round — set [currentSeat],
  /// [turnPhase], [pendingDiscard], [openingState], [discardPile], or [stock]
  /// to position the controller exactly where the regression starts.
  factory ClassicHareegScenario.deal({
    ClassicHareegSetup? setup,
    int seed = 7,
    Map<PlayerSeat, List<HareegCard>>? hands,
    List<HareegCard>? southHand,
    List<HareegCard>? eastHand,
    List<HareegCard>? northHand,
    List<HareegCard>? westHand,
    List<HareegCard>? discardPile,
    List<HareegCard>? stock,
    HareegCard? pendingDiscard,
    Map<PlayerSeat, List<PlacedMeld>>? tableMelds,
    OpeningState? openingState,
    PlayerSeat? currentSeat,
    TurnPhase turnPhase = TurnPhase.action,
    List<PlayerSeat>? activeSeats,
    Map<PlayerSeat, int>? scores,
    int roundNumber = 1,
    DateTime? savedAt,
    DateTime? fiftyWindowOpenedAt,
    DateTime Function()? now,
  }) {
    final effectiveSetup = setup ?? ClassicHareegSetup.defaults();
    final base = ClassicHareegRound.deal(setup: effectiveSetup, seed: seed);

    final mergedHands = <PlayerSeat, List<HareegCard>>{
      for (final entry in base.hands.entries)
        entry.key: List<HareegCard>.of(entry.value),
    };
    if (hands != null) {
      for (final entry in hands.entries) {
        mergedHands[entry.key] = List<HareegCard>.of(entry.value);
      }
    }
    if (southHand != null) {
      mergedHands[PlayerSeat.south] = List<HareegCard>.of(southHand);
    }
    if (eastHand != null) {
      mergedHands[PlayerSeat.east] = List<HareegCard>.of(eastHand);
    }
    if (northHand != null) {
      mergedHands[PlayerSeat.north] = List<HareegCard>.of(northHand);
    }
    if (westHand != null) {
      mergedHands[PlayerSeat.west] = List<HareegCard>.of(westHand);
    }

    final snapshot = ClassicHareegMatchSnapshot(
      setup: effectiveSetup,
      hands: mergedHands,
      stock: stock ?? base.stock,
      discardPile: discardPile ?? base.discardPile,
      tableMelds: tableMelds ?? const {},
      starter: base.starter,
      currentSeat: currentSeat ?? base.starter,
      turnPhase: turnPhase,
      pendingDiscard: pendingDiscard,
      openingState: openingState,
      scores: scores ?? const {},
      activeSeats: activeSeats ?? const [
        PlayerSeat.south,
        PlayerSeat.east,
        PlayerSeat.north,
        PlayerSeat.west,
      ],
      roundNumber: roundNumber,
      fiftyWindowOpenedAt: fiftyWindowOpenedAt,
      savedAt: savedAt ?? DateTime.utc(2026, 5, 24),
    );

    return ClassicHareegScenario._(
      ClassicHareegGameController.fromSnapshot(snapshot, now: now),
    );
  }

  /// Wraps an already-constructed controller (e.g. one restored from a custom
  /// snapshot) so tests can mix snapshot prep with DSL-driven moves.
  factory ClassicHareegScenario.fromController(
    ClassicHareegGameController controller,
  ) {
    return ClassicHareegScenario._(controller);
  }
}

/// Convenience helpers shared with tests for constructing card fixtures.
abstract final class ScenarioCards {
  /// Standard non-joker physical card.
  static HareegCard card(CardRank rank, CardSuit suit, {int deckIndex = 0}) {
    return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
  }

  /// Opening state with one seat already opened, so meld plays do not stage
  /// behind the opening benchmark.
  static OpeningState openedFor(
    PlayerSeat seat, {
    int requirement = 51,
  }) {
    return OpeningState(
      baseRequirement: requirement,
      currentRequirement: requirement,
      openedSeats: {seat},
    );
  }
}

/// Per-seat action surface for [ClassicHareegScenario]. Each method is a thin
/// wrapper around [ClassicHareegGameController.applyAction] that builds the
/// action id from domain objects so tests stay readable.
class SeatScope {
  SeatScope._(this._controller, this.seat);

  final ClassicHareegGameController _controller;

  /// Seat this scope drives.
  final PlayerSeat seat;

  /// Live read-only hand for this seat.
  List<HareegCard> get hand => _controller.handFor(seat);

  /// Live table melds for this seat.
  List<PlacedMeld> get tableMelds => _controller.tableMeldsFor(seat);

  /// Legal action ids advertised for this seat right now.
  List<String> get legalActionIds => _controller.legalActionIdsFor(seat);

  /// Draws one card from stock.
  ApplyActionResult drawStock() {
    return _controller.applyAction(ClassicHareegActionIds.drawStock);
  }

  /// Takes the top discard into pending state.
  ApplyActionResult takeDiscard() {
    return _controller.applyAction(ClassicHareegActionIds.takeDiscard);
  }

  /// Returns a pending discard back to the discard pile (and draws from stock
  /// instead).
  ApplyActionResult returnPendingDiscard() {
    return _controller.applyAction(
      ClassicHareegActionIds.returnPendingDiscard,
    );
  }

  /// Takes back all uncommitted opening melds.
  ApplyActionResult returnOpeningMelds() {
    return _controller.applyAction(
      ClassicHareegActionIds.returnOpeningMelds,
    );
  }

  /// Claims Fifty / Khamsin.
  ApplyActionResult claimFifty() {
    return _controller.applyAction(ClassicHareegActionIds.claimFifty);
  }

  /// Plays [cards] from this seat's hand as one meld.
  ApplyActionResult playMeld(Iterable<HareegCard> cards) {
    return _controller.applyAction(
      ClassicHareegActionIds.playMeldActionId(cards.map((c) => c.id)),
    );
  }

  /// Discards a plain legal [card].
  ApplyActionResult discard(HareegCard card) {
    return _controller.applyAction(
      '${ClassicHareegActionIds.discardPrefix}${card.id}',
    );
  }

  /// Discards a cover [card] via the penalty-capable cover-discard surface.
  /// Under Strict/Table tiers this goes through as a penalised mistake; under
  /// Coaching/Standard tiers the controller rejects the action.
  ApplyActionResult discardBlockedCover(HareegCard card) {
    return _controller.applyAction(
      '${ClassicHareegActionIds.discardBlockedCoverPrefix}${card.id}',
    );
  }
}
