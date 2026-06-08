import '../../../../domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import 'practice_board_grammar.dart';

/// Shared authoring helpers for guided-practice lesson scripts.
///
/// The pack modules (`CoreTurnPracticePack`, `TableMechanicsPracticePack`,
/// `FinishFiftyPracticePack`) each own their lesson content; the recurring
/// board-grammar specs and step-filter shapes they all reach for live here so
/// a board rule or step predicate is defined once and reused across packs.
abstract final class PracticeScriptAuthoring {
  /// CPU seats keep a full unopened hand; only the player's board is staged.
  static const cpuHandsStayFull = PracticeBoardAuditSpec(
    fullHandSeats: {PlayerSeat.east, PlayerSeat.north, PlayerSeat.west},
  );

  /// Every seat still holds a full dealt hand — nothing is opened yet.
  static const allHandsStayFull = PracticeBoardAuditSpec(
    fullHandSeats: {
      PlayerSeat.south,
      PlayerSeat.east,
      PlayerSeat.north,
      PlayerSeat.west,
    },
  );

  /// South opened at exactly 51; hand + own table cards read as one deal.
  static const southOpened51OneDeal = PracticeBoardAuditSpec(
    handAndTableSeats: {PlayerSeat.south},
    expectedTableValues: {PlayerSeat.south: 51},
  );

  /// South opened at 51, mid-turn after a draw, with a dressed discard pile.
  static const southOpened51MidTurn = PracticeBoardAuditSpec(
    handAndTableSeats: {PlayerSeat.south},
    extraCardsInHand: {PlayerSeat.south: 1},
    expectedTableValues: {PlayerSeat.south: 51},
    fullHandSeats: {PlayerSeat.east, PlayerSeat.north, PlayerSeat.west},
    minimumDiscardPileSize: 5,
  );

  /// South opened at 51, mid-turn after a draw, without a pile-depth rule.
  static const southOpened51MidTurnNoPileMinimum = PracticeBoardAuditSpec(
    handAndTableSeats: {PlayerSeat.south},
    extraCardsInHand: {PlayerSeat.south: 1},
    expectedTableValues: {PlayerSeat.south: 51},
    fullHandSeats: {PlayerSeat.east, PlayerSeat.north, PlayerSeat.west},
  );

  /// South still unopened, mid-turn after a draw, with a dressed pile — the
  /// perfect-hand finish lays the whole hand without ever opening, so there
  /// is no visible table value to assert.
  static const southUnopenedMidTurn = PracticeBoardAuditSpec(
    handAndTableSeats: {PlayerSeat.south},
    extraCardsInHand: {PlayerSeat.south: 1},
    fullHandSeats: {PlayerSeat.east, PlayerSeat.north, PlayerSeat.west},
    minimumDiscardPileSize: 5,
  );

  /// South opened mid-turn after a draw, with a dressed pile but no fixed
  /// table-value claim — for endgame boards whose prior melds need not total
  /// an exact benchmark.
  static const southOpenedMidTurnNoValue = PracticeBoardAuditSpec(
    handAndTableSeats: {PlayerSeat.south},
    extraCardsInHand: {PlayerSeat.south: 1},
    fullHandSeats: {PlayerSeat.east, PlayerSeat.north, PlayerSeat.west},
    minimumDiscardPileSize: 5,
  );

  /// South opened at 51 at turn start, with a dressed late-round pile.
  static const southOpened51LateTurnStart = PracticeBoardAuditSpec(
    handAndTableSeats: {PlayerSeat.south},
    expectedTableValues: {PlayerSeat.south: 51},
    fullHandSeats: {PlayerSeat.east, PlayerSeat.north, PlayerSeat.west},
    minimumDiscardPileSize: 5,
  );

  /// Allows only a play-meld of exactly [cardIds] — for staging lessons
  /// whose copy and rings teach one specific meld per step, so an
  /// out-of-order set cannot silently complete a step its prompt is not
  /// describing.
  static bool Function(ClassicHareegActionDescriptor action) playsExactly(
    Set<String> cardIds,
  ) {
    return (action) =>
        action.kind == ClassicHareegActionKind.playMeld &&
        action.cardIds.length == cardIds.length &&
        cardIds.containsAll(action.cardIds);
  }

  /// Allows only a represented-joker meld of exactly [cardIds], leaving the
  /// identity declaration open — a joker completes almost any selection, so
  /// a kind-only gate would light selections the prompt never described.
  static bool Function(ClassicHareegActionDescriptor action)
  playsJokerMeldExactly(Set<String> cardIds) {
    return (action) =>
        action.kind == ClassicHareegActionKind.playMeldWithJoker &&
        action.cardIds.length == cardIds.length &&
        cardIds.containsAll(action.cardIds);
  }

  /// Board-state proof that some meld on [seat]'s table holds every card in
  /// [cardIds] — superset, not equality, so a meld that later grows a cover
  /// still counts as demonstrated. The take-back regression and forward
  /// auto-skip both re-check steps through this.
  static bool Function(ClassicHareegGameController controller) tableHolds(
    PlayerSeat seat,
    Set<String> cardIds,
  ) {
    return (controller) {
      for (final meld in controller.tableMeldsFor(seat)) {
        final ids = {for (final card in meld.cards) card.id};
        if (ids.containsAll(cardIds)) {
          return true;
        }
      }
      return false;
    };
  }
}
