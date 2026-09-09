import '../game/classic_hareeg_action.dart';
import '../game/classic_hareeg_discard_history.dart';
import '../game/classic_hareeg_round.dart' show TurnPhase;
import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../models/table_strictness.dart';
import '../reporting/match_action_transcript.dart';
import '../rules/opening_rules.dart' show PlacedMeld;
import 'replay_reconstruction.dart';

/// The seat a replay is reviewed from.
///
/// The human always sits South, so a review is always that seat's point of
/// view. Named once here rather than repeated as a literal at every call site
/// that has to decide what "your hand" means.
const PlayerSeat reviewPerspectiveSeat = PlayerSeat.south;

/// An open Fifty window, as anyone at the table could see it.
class ReviewFiftyWindow {
  /// Creates a window view.
  const ReviewFiftyWindow({
    required this.discarder,
    required this.cardId,
    required this.secondsRemaining,
  });

  /// Seat whose discard opened the window.
  final PlayerSeat? discarder;

  /// The card on offer.
  final String? cardId;

  /// Seconds left, never negative.
  final int secondsRemaining;

  @override
  String toString() =>
      'fifty(${discarder?.name ?? "-"},${cardId ?? "-"},$secondsRemaining)';
}

/// One applied action, as the reviewer sees it.
///
/// Kept separate from [ReviewObservation] because the evidence contract is
/// stated over the pair: the same observation plus the same action must always
/// produce the same insight.
class ReviewedAction {
  /// Creates a reviewed action.
  ReviewedAction({required this.actingSeat, required this.descriptor});

  /// Builds a reviewed action from a transcript entry.
  factory ReviewedAction.fromEntry(MatchActionTranscriptEntry entry) {
    return ReviewedAction(
      actingSeat: entry.seat,
      descriptor: ClassicHareegActionIds.describe(entry.actionId),
    );
  }

  /// Seat the action is attributed to.
  ///
  /// This is the match's current seat immediately before the action, which is
  /// what the recorder stores. For an out-of-turn claim that is the seat whose
  /// turn it was rather than the physical claimant. The evidence boundary is
  /// unaffected: when this names South, citing South's own hand is legitimate
  /// however the claim was made.
  final PlayerSeat actingSeat;

  /// Parsed meaning of the applied action.
  final ClassicHareegActionDescriptor descriptor;

  /// Whether this action was taken by the reviewing seat.
  bool get isPerspectiveAction => actingSeat == reviewPerspectiveSeat;

  /// Stable identity for equality and signatures.
  String get signature => '${actingSeat.name}:${descriptor.id}';
}

/// Everything about a position that the reviewing seat could actually see.
///
/// This type is the evidence boundary. It has no field capable of holding
/// another seat's hand, the stock's contents or order, the deal seed, or any
/// future action — so an analysis built from it cannot leak hidden information
/// even by accident. That is a stronger guarantee than a reviewer promising not
/// to look.
///
/// The reviewing seat's *own* hand is present, because it is observable to that
/// seat. The rule is "no other seat's hand", not "no hand at all".
class ReviewObservation {
  /// Creates an observation.
  ReviewObservation({
    required this.perspective,
    required this.actingSeat,
    required this.roundNumber,
    required this.currentSeat,
    required this.turnPhase,
    required List<HareegCard> perspectiveHand,
    required List<HareegCard> discardPile,
    required Map<PlayerSeat, List<PlacedMeld>> visibleMelds,
    required Map<PlayerSeat, int> handCounts,
    required this.stockCount,
    required Map<PlayerSeat, int> scores,
    required List<PlayerSeat> activeSeats,
    required List<PlayerSeat> removedSeats,
    required Set<PlayerSeat> openedSeats,
    required this.pendingDiscard,
    required this.fiftyWindow,
    required List<DiscardEvent> discardHistoryEvents,
    required this.deckCopyCount,
    required this.tableStrictness,
    required this.openingRequirement,
  }) : perspectiveHand = List.unmodifiable(perspectiveHand),
       discardPile = List.unmodifiable(discardPile),
       visibleMelds = Map.unmodifiable(visibleMelds),
       handCounts = Map.unmodifiable(handCounts),
       scores = Map.unmodifiable(scores),
       activeSeats = List.unmodifiable(activeSeats),
       removedSeats = List.unmodifiable(removedSeats),
       openedSeats = Set.unmodifiable(openedSeats),
       discardHistoryEvents = List.unmodifiable(discardHistoryEvents);

  /// Builds the observation for the action applied at [applied].
  ///
  /// Reads the pre-action state from [previous] and the action from [applied].
  /// The Fifty remaining time is measured at the *effective* pre-action clock:
  /// when the machine had to expire a window before the action would apply, the
  /// previous frame's clock predates that jump and would report a window that
  /// was, from the action's point of view, already gone.
  factory ReviewObservation.fromFrames({
    required ReplayFrame previous,
    required ReplayFrame applied,
    PlayerSeat perspective = reviewPerspectiveSeat,
  }) {
    final entry = applied.appliedEntry;
    if (entry == null) {
      throw ArgumentError.value(
        applied.kind,
        'applied',
        'Only an action-applied frame can be reviewed.',
      );
    }

    final snapshot = previous.snapshot;
    final reference = applied.effectivePreActionClock ?? previous.clock;
    final remaining = previous.fiftySecondsRemainingAt(reference);

    return ReviewObservation(
      perspective: perspective,
      actingSeat: entry.seat,
      roundNumber: snapshot.roundNumber,
      currentSeat: snapshot.currentSeat,
      turnPhase: snapshot.turnPhase,
      perspectiveHand: snapshot.hands[perspective] ?? const [],
      discardPile: snapshot.discardPile,
      visibleMelds: {
        for (final seat in PlayerSeat.values)
          seat: snapshot.tableMelds[seat] ?? const [],
      },
      // Counts only. The contents of these hands are exactly what must not
      // cross this boundary.
      handCounts: {
        for (final seat in PlayerSeat.values)
          seat: (snapshot.hands[seat] ?? const []).length,
      },
      stockCount: snapshot.stock.length,
      scores: {
        for (final seat in PlayerSeat.values) seat: snapshot.scores[seat] ?? 0,
      },
      activeSeats: snapshot.activeSeats,
      removedSeats: snapshot.removedSeats,
      openedSeats: snapshot.openingState?.openedSeats ?? const {},
      pendingDiscard: snapshot.pendingDiscard,
      fiftyWindow: remaining == null
          ? null
          : ReviewFiftyWindow(
              discarder: snapshot.fiftyWindowDiscarder,
              cardId: snapshot.discardPile.isEmpty
                  ? null
                  : snapshot.discardPile.last.id,
              secondsRemaining: remaining,
            ),
      discardHistoryEvents: snapshot.discardHistoryEvents,
      deckCopyCount: snapshot.setup.deckCount,
      tableStrictness: snapshot.setup.tableStrictness,
      openingRequirement: snapshot.openingState?.currentRequirement ?? 0,
    );
  }

  /// Seat this observation is taken from.
  final PlayerSeat perspective;

  /// Seat the reviewed action is attributed to.
  final PlayerSeat actingSeat;

  /// One-based dealt round.
  final int roundNumber;

  /// Seat whose turn it was.
  final PlayerSeat currentSeat;

  /// Phase of that turn.
  final TurnPhase turnPhase;

  /// The reviewing seat's own hand — observable to that seat.
  final List<HareegCard> perspectiveHand;

  /// Face-up discard pile, oldest first.
  final List<HareegCard> discardPile;

  /// Melds on the table, by owner. All face up.
  final Map<PlayerSeat, List<PlacedMeld>> visibleMelds;

  /// How many cards each seat holds. Counts only, never contents.
  final Map<PlayerSeat, int> handCounts;

  /// How many cards remain in stock. A count, never the identities.
  final int stockCount;

  /// Match scores.
  final Map<PlayerSeat, int> scores;

  /// Seats still in the match.
  final List<PlayerSeat> activeSeats;

  /// Seats removed from the table.
  final List<PlayerSeat> removedSeats;

  /// Seats that have opened.
  final Set<PlayerSeat> openedSeats;

  /// Pending discard on the table, if any.
  final HareegCard? pendingDiscard;

  /// Open Fifty window, if any.
  final ReviewFiftyWindow? fiftyWindow;

  /// Attributed discard and pickup history — what everyone at the table saw.
  final List<DiscardEvent> discardHistoryEvents;

  /// Copies of each standard identity in the deck.
  final int deckCopyCount;

  /// Strictness tier in force.
  final TableStrictness tableStrictness;

  /// Current opening requirement.
  final int openingRequirement;

  /// Card identities the table has publicly seen pass through the pile.
  ///
  /// A card an opponent picked up has left the pile but was seen by everyone,
  /// so a tell may name it. Kept separate from [discardPile] because provenance
  /// rules distinguish "on the table now" from "publicly seen".
  Set<String> get publiclySeenCardIds => {
    for (final event in discardHistoryEvents) event.card.id,
  };

  /// Whether [seat] has opened.
  bool hasOpened(PlayerSeat seat) => openedSeats.contains(seat);

  /// Pickups [seat] took from the pile, oldest first.
  List<HareegCard> pickupsBy(PlayerSeat seat) => [
    for (final event in discardHistoryEvents)
      if (event.seat == seat && event.kind == DiscardEventKind.pickup)
        event.card,
  ];

  /// Canonical, order-stable identity of everything observable here.
  ///
  /// Equality is defined in terms of this string so the two can never disagree
  /// about what "the same observation" means.
  late final String signature = _buildSignature();

  String _buildSignature() {
    final buffer = StringBuffer()
      ..write('p=${perspective.name};')
      ..write('a=${actingSeat.name};')
      ..write('r=$roundNumber;')
      ..write('cur=${currentSeat.name};')
      ..write('ph=${turnPhase.name};')
      ..write('hand=${_ids(perspectiveHand)};')
      ..write('pile=${discardPile.map((c) => c.id).join(",")};')
      ..write('melds=${_meldSignature()};')
      ..write('counts=${_seatMap(handCounts)};')
      ..write('stock=$stockCount;')
      ..write('scores=${_seatMap(scores)};')
      ..write('active=${activeSeats.map((s) => s.name).join(",")};')
      ..write(
        'removed=${(removedSeats.map((s) => s.name).toList()..sort()).join(",")};',
      )
      ..write(
        'opened=${(openedSeats.map((s) => s.name).toList()..sort()).join(",")};',
      )
      ..write('pending=${pendingDiscard?.id ?? "-"};')
      ..write('fifty=${fiftyWindow ?? "-"};')
      ..write('seen=${_history()};')
      ..write('deck=$deckCopyCount;')
      ..write('strict=${tableStrictness.name};')
      ..write('req=$openingRequirement');
    return buffer.toString();
  }

  // The hand is sorted because display order is not an observable difference:
  // two identical positions must not read as different observations because a
  // player rearranged their fan.
  String _ids(List<HareegCard> cards) =>
      (cards.map((c) => c.id).toList()..sort()).join(',');

  String _meldSignature() {
    final parts = <String>[];
    for (final seat in PlayerSeat.values) {
      final melds = visibleMelds[seat] ?? const [];
      parts.add(
        '${seat.name}[${melds.map((m) => m.cards.map((c) => c.id).join("+")).join("|")}]',
      );
    }
    return parts.join('/');
  }

  String _seatMap(Map<PlayerSeat, int> values) => [
    for (final seat in PlayerSeat.values) '${seat.name}:${values[seat] ?? 0}',
  ].join(',');

  String _history() => [
    for (final event in discardHistoryEvents)
      '${event.sequence}${event.kind.name[0]}${event.seat.name[0]}${event.card.id}',
  ].join(',');

  @override
  bool operator ==(Object other) =>
      other is ReviewObservation && other.signature == signature;

  @override
  int get hashCode => signature.hashCode;
}
