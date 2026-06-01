import '../models/classic_hareeg_setup.dart';
import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../rules/classic_hareeg_rules.dart';
import '../rules/fifty_rules.dart';
import '../rules/finish_rules.dart';
import '../rules/opening_rules.dart';
import 'classic_hareeg_discard_history.dart';
import 'classic_hareeg_match_snapshot.dart';
import 'classic_hareeg_round.dart';

/// Hydrates persisted Classic Hareeg snapshots into live match state.
///
/// The restored collections are detached and mutable because the game
/// controller owns them as live round state after construction.
abstract final class ClassicHareegMatchRestoration {
  /// Restores live match state from [snapshot].
  static ClassicHareegRestoredMatchState fromSnapshot(
    ClassicHareegMatchSnapshot snapshot, {
    ClassicHareegRules? rules,
  }) {
    final activeRules = rules ?? ClassicHareegRules.defaults();
    // Prefer the discarder the snapshot recorded verbatim. Older saves
    // (field absent) fall back to the legacy geometric guess, which can
    // mis-attribute the Fifty penalty once a seat has been removed from the
    // round.
    final previousDiscardSeat = snapshot.discardPile.isEmpty
        ? null
        : snapshot.fiftyWindowDiscarder ??
              snapshot.currentSeat.previousAntiClockwise;
    final shouldRestoreFiftyWindow =
        snapshot.discardPile.isNotEmpty && snapshot.turnPhase == TurnPhase.draw;

    final discardHistory = DiscardHistory();
    for (final event in snapshot.discardHistoryEvents) {
      switch (event.kind) {
        case DiscardEventKind.discard:
          discardHistory.recordDiscard(event.seat, event.card);
        case DiscardEventKind.pickup:
          discardHistory.recordPickup(event.seat, event.card);
      }
    }

    return ClassicHareegRestoredMatchState(
      setup: snapshot.setup,
      rules: activeRules,
      hands: {
        for (final entry in snapshot.hands.entries)
          entry.key: List<HareegCard>.of(entry.value),
      },
      stock: List<HareegCard>.of(snapshot.stock),
      discardPile: List<HareegCard>.of(snapshot.discardPile),
      tableMelds: {
        for (final seat in PlayerSeat.values)
          seat: List<PlacedMeld>.of(snapshot.tableMelds[seat] ?? const []),
      },
      scores: {
        for (final seat in PlayerSeat.values) seat: snapshot.scores[seat] ?? 0,
      },
      activeSeats: List<PlayerSeat>.of(snapshot.activeSeats),
      openingState:
          snapshot.openingState ??
          OpeningState.initial(snapshot.setup.openingRequirement),
      roundNumber: snapshot.roundNumber,
      removedSeats: snapshot.removedSeats.toSet(),
      starter: snapshot.starter,
      currentSeat: snapshot.currentSeat,
      turnPhase: snapshot.turnPhase,
      pendingDiscard: snapshot.pendingDiscard,
      previousDiscardSeat: previousDiscardSeat,
      fiftyWindow: shouldRestoreFiftyWindow
          ? ClassicHareegFiftyRules.openWindow(
              discarder: previousDiscardSeat!,
              claimant: snapshot.currentSeat,
              discardedCard: snapshot.discardPile.last,
              durationSeconds: snapshot.setup.fiftyTimerSeconds,
              // Prefer the verbatim flag; older saves (field absent) fall
              // back to the legacy `roundNumber == 1` derivation.
              isFirstDealtRound:
                  snapshot.fiftyWindowIsFirstDealtRound ??
                  (snapshot.roundNumber == 1),
            )
          : null,
      fiftyWindowOpenedAt: shouldRestoreFiftyWindow
          ? snapshot.fiftyWindowOpenedAt ?? snapshot.savedAt
          : null,
      turnSource: snapshot.pendingDiscard == null
          ? FinishCardSource.stock
          : FinishCardSource.previousDiscard,
      discardHistory: discardHistory,
    );
  }
}

/// Live state restored from a persisted Classic Hareeg match snapshot.
class ClassicHareegRestoredMatchState {
  /// Creates restored match state.
  ClassicHareegRestoredMatchState({
    required this.setup,
    required this.rules,
    required this.hands,
    required this.stock,
    required this.discardPile,
    required this.tableMelds,
    required this.scores,
    required this.activeSeats,
    required this.openingState,
    required this.roundNumber,
    required this.removedSeats,
    required this.starter,
    required this.currentSeat,
    required this.turnPhase,
    required this.turnSource,
    DiscardHistory? discardHistory,
    this.pendingDiscard,
    this.previousDiscardSeat,
    this.fiftyWindow,
    this.fiftyWindowOpenedAt,
  }) : discardHistory = discardHistory ?? DiscardHistory();

  /// Restored setup.
  final ClassicHareegSetup setup;

  /// Restored rules.
  final ClassicHareegRules rules;

  /// Detached live hands.
  final Map<PlayerSeat, List<HareegCard>> hands;

  /// Detached live stock.
  final List<HareegCard> stock;

  /// Detached live discard pile.
  final List<HareegCard> discardPile;

  /// Detached live table melds.
  final Map<PlayerSeat, List<PlacedMeld>> tableMelds;

  /// Restored match scores.
  final Map<PlayerSeat, int> scores;

  /// Restored active match seats.
  final List<PlayerSeat> activeSeats;

  /// Restored opening benchmark state.
  final OpeningState openingState;

  /// Restored one-based round number.
  final int roundNumber;

  /// Seats already removed from the current round.
  final Set<PlayerSeat> removedSeats;

  /// Starter of the restored round.
  final PlayerSeat starter;

  /// Seat whose turn is restored.
  final PlayerSeat currentSeat;

  /// Restored turn phase.
  final TurnPhase turnPhase;

  /// Restored pending discard, if any.
  final HareegCard? pendingDiscard;

  /// Inferred seat that produced the current top discard.
  final PlayerSeat? previousDiscardSeat;

  /// Restored Fifty claim window, if one can be active.
  final FiftyClaimWindow? fiftyWindow;

  /// Restored opening time for the Fifty claim window.
  final DateTime? fiftyWindowOpenedAt;

  /// Source of the turn card for finish validation.
  final FinishCardSource turnSource;

  /// Restored per-round discard memory (live, mutable). Pre-populated from
  /// the snapshot when the saved match carried `discardHistoryEvents`;
  /// empty otherwise.
  final DiscardHistory discardHistory;
}

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
