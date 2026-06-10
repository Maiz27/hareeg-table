import '../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../domain/classic_hareeg/models/playing_card.dart';
import 'animations/deal_choreography.dart';
import 'table_action_presentation_planner.dart';

/// Looks up a visible card in a seat's hand.
typedef TableCardFlightHandLookup =
    HareegCard? Function(PlayerSeat seat, String cardId);

/// Resolves a visible south-hand card into its current flight slot.
typedef TableCardFlightSouthSlotLookup =
    SeatHandFlightSlot? Function(String cardId);

/// Resolves an append landing slot for a seat hand.
typedef TableCardFlightAppendSlotLookup =
    SeatHandFlightSlot Function(PlayerSeat seat);

/// Resolves the last currently occupied hand slot for a seat.
typedef TableCardFlightLastSlotLookup =
    SeatHandFlightSlot? Function(PlayerSeat seat);

/// Why a table action flight could or could not be realized.
enum TableCardFlightScenario {
  /// There was no presentation flight request.
  noPresentationFlight,

  /// A stock draw uses a face-down stock card.
  stockBack,

  /// A top discard was visible and can fly.
  visibleTopDiscard,

  /// A top discard flight was requested while no top discard exists.
  missingTopDiscard,

  /// A pending discard was visible and can fly.
  visiblePendingDiscard,

  /// A pending discard flight was requested while none exists.
  missingPendingDiscard,

  /// The requested hand source had no card id.
  missingHandCardId,

  /// The requested hand source was visible and can fly.
  visibleHandCard,

  /// The requested hand source was hidden, so a face-down stand-in can fly.
  faceDownHandFallback,

  /// The requested hand source was not visible and no fallback was allowed.
  missingHandCard,
}

/// Target slot for a table-meld card flight.
class TableMeldFlightSlot {
  /// Creates a table-meld slot reference.
  const TableMeldFlightSlot({
    required this.seat,
    this.index = 0,
    this.laneMeldCardCounts = const [],
  });

  /// Meld owner.
  final PlayerSeat seat;

  /// Zero-based meld lane index for the owner.
  final int index;

  /// Card count of every meld present in the owner's lane when this flight
  /// lands, in placement order (including the meld at [index] itself). Lets
  /// the flight geometry reproduce the lane's arrangement and aim at the
  /// exact resting slot instead of the lane centre. Empty falls back to the
  /// lane-centre anchor.
  final List<int> laneMeldCardCounts;
}

/// Realized table card flight, independent of widget geometry.
class TableCardFlightRealization {
  const TableCardFlightRealization._({
    required this.scenario,
    required this.presentation,
    required this.card,
    required this.faceDown,
    required this.beginHandSlot,
    required this.endHandSlot,
    required this.endMeldSlot,
  });

  /// Why this realization took its shape.
  final TableCardFlightScenario scenario;

  /// The original presentation request.
  final TableActionFlightPlan? presentation;

  /// Card to render, when the flight can render.
  final HareegCard? card;

  /// Whether [card] should be rendered face-down.
  final bool faceDown;

  /// Specific source hand slot, when the flight starts in a hand.
  final SeatHandFlightSlot? beginHandSlot;

  /// Specific destination hand slot, when the flight lands in a hand.
  final SeatHandFlightSlot? endHandSlot;

  /// Specific destination meld slot, when the flight lands on the table.
  final TableMeldFlightSlot? endMeldSlot;

  /// Whether the widget has enough information to render this flight.
  bool get canRender => presentation != null && card != null;
}

/// Resolves presentation-level card flights into renderable flight data.
abstract final class TableCardFlightPlanner {
  /// Realizes a card flight request against current table facts.
  static TableCardFlightRealization realize({
    required TableActionFlightPlan? presentation,
    required HareegCard stockBack,
    required HareegCard? topDiscard,
    required HareegCard? pendingDiscard,
    required TableCardFlightHandLookup handCardFor,
    required TableCardFlightSouthSlotLookup southHandCardSlotFor,
    required TableCardFlightAppendSlotLookup appendHandSlotFor,
    required TableCardFlightLastSlotLookup lastHandSlotFor,
  }) {
    if (presentation == null) {
      return const TableCardFlightRealization._(
        scenario: TableCardFlightScenario.noPresentationFlight,
        presentation: null,
        card: null,
        faceDown: false,
        beginHandSlot: null,
        endHandSlot: null,
        endMeldSlot: null,
      );
    }

    final source = _sourceCard(
      presentation: presentation,
      stockBack: stockBack,
      topDiscard: topDiscard,
      pendingDiscard: pendingDiscard,
      handCardFor: handCardFor,
    );
    final card = source.card;
    if (card == null) {
      return TableCardFlightRealization._(
        scenario: source.scenario,
        presentation: presentation,
        card: null,
        faceDown: false,
        beginHandSlot: null,
        endHandSlot: null,
        endMeldSlot: null,
      );
    }

    return TableCardFlightRealization._(
      scenario: source.scenario,
      presentation: presentation,
      card: card,
      faceDown: source.faceDown,
      beginHandSlot: _beginHandSlot(
        presentation: presentation,
        card: card,
        southHandCardSlotFor: southHandCardSlotFor,
        lastHandSlotFor: lastHandSlotFor,
      ),
      endHandSlot: _endHandSlot(
        presentation: presentation,
        appendHandSlotFor: appendHandSlotFor,
      ),
      endMeldSlot: _endMeldSlot(presentation),
    );
  }

  static ({TableCardFlightScenario scenario, HareegCard? card, bool faceDown})
  _sourceCard({
    required TableActionFlightPlan presentation,
    required HareegCard stockBack,
    required HareegCard? topDiscard,
    required HareegCard? pendingDiscard,
    required TableCardFlightHandLookup handCardFor,
  }) {
    return switch (presentation.source) {
      TableActionFlightSource.stockBack => (
        scenario: TableCardFlightScenario.stockBack,
        card: stockBack,
        faceDown: true,
      ),
      TableActionFlightSource.topDiscard => (
        scenario: topDiscard == null
            ? TableCardFlightScenario.missingTopDiscard
            : TableCardFlightScenario.visibleTopDiscard,
        card: topDiscard,
        faceDown: false,
      ),
      TableActionFlightSource.pendingDiscard => (
        scenario: pendingDiscard == null
            ? TableCardFlightScenario.missingPendingDiscard
            : TableCardFlightScenario.visiblePendingDiscard,
        card: pendingDiscard,
        faceDown: false,
      ),
      TableActionFlightSource.handCard => _handSourceCard(
        presentation: presentation,
        stockBack: stockBack,
        handCardFor: handCardFor,
      ),
    };
  }

  static ({TableCardFlightScenario scenario, HareegCard? card, bool faceDown})
  _handSourceCard({
    required TableActionFlightPlan presentation,
    required HareegCard stockBack,
    required TableCardFlightHandLookup handCardFor,
  }) {
    final cardId = presentation.cardId;
    if (cardId == null) {
      return (
        scenario: TableCardFlightScenario.missingHandCardId,
        card: null,
        faceDown: false,
      );
    }

    final card = handCardFor(presentation.seat, cardId);
    if (card != null) {
      return (
        scenario: TableCardFlightScenario.visibleHandCard,
        card: card,
        faceDown: false,
      );
    }
    if (!presentation.allowFaceDownFallback) {
      return (
        scenario: TableCardFlightScenario.missingHandCard,
        card: null,
        faceDown: false,
      );
    }
    return (
      scenario: TableCardFlightScenario.faceDownHandFallback,
      card: stockBack,
      faceDown: true,
    );
  }

  static SeatHandFlightSlot? _beginHandSlot({
    required TableActionFlightPlan presentation,
    required HareegCard card,
    required TableCardFlightSouthSlotLookup southHandCardSlotFor,
    required TableCardFlightLastSlotLookup lastHandSlotFor,
  }) {
    return switch (presentation.source) {
      TableActionFlightSource.pendingDiscard ||
      TableActionFlightSource.handCard =>
        presentation.seat == PlayerSeat.south
            ? southHandCardSlotFor(card.id)
            : lastHandSlotFor(presentation.seat),
      TableActionFlightSource.stockBack ||
      TableActionFlightSource.topDiscard => null,
    };
  }

  static SeatHandFlightSlot? _endHandSlot({
    required TableActionFlightPlan presentation,
    required TableCardFlightAppendSlotLookup appendHandSlotFor,
  }) {
    if (presentation.destination != TableActionFlightDestination.seatHand) {
      return null;
    }
    return appendHandSlotFor(presentation.seat);
  }

  static TableMeldFlightSlot? _endMeldSlot(TableActionFlightPlan presentation) {
    if (presentation.destination != TableActionFlightDestination.tableMeld) {
      return null;
    }
    final targetSeat = presentation.targetSeat;
    if (targetSeat == null) return null;
    return TableMeldFlightSlot(
      seat: targetSeat,
      index: presentation.targetMeldIndex,
    );
  }
}
