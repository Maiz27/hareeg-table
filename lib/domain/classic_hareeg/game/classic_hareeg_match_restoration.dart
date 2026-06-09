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
      seed: snapshot.seed,
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
      // Resume a Fifty proof turn when one was active at save time. The
      // proof is untimed, so unlike windows it restores without any clock
      // guard; the claimed card already sits in the hand (pending discard)
      // because the checkpoint reverted the proof's table plays. The three
      // fields restore as a unit: a partial save never leaks a dangling
      // discarder or exception flag without its claim.
      activeFiftyClaimCardId: _resumesFiftyClaim(snapshot)
          ? snapshot.activeFiftyClaimCardId
          : null,
      activeFiftyClaimDiscarder: _resumesFiftyClaim(snapshot)
          ? snapshot.activeFiftyClaimDiscarder
          : null,
      activeFiftyClaimIsFirstDealtRound:
          _resumesFiftyClaim(snapshot) &&
          (snapshot.activeFiftyClaimIsFirstDealtRound ??
              (snapshot.roundNumber == 1)),
      // Resume a windowed take-discard's Fifty provenance. Like the proof, the
      // taken card sits back in the hand as the pending discard after the
      // checkpoint reverts the turn's table plays, so finishing on it again
      // scores the Fifty rather than a normal -1. The three fields restore as a
      // unit so a partial save never leaks a discarder/exception without its id.
      windowedTakeCardId: _resumesWindowedTake(snapshot)
          ? snapshot.windowedTakeCardId
          : null,
      windowedTakeDiscarder: _resumesWindowedTake(snapshot)
          ? snapshot.windowedTakeDiscarder
          : null,
      windowedTakeIsFirstDealtRound:
          _resumesWindowedTake(snapshot) &&
          (snapshot.windowedTakeIsFirstDealtRound ??
              (snapshot.roundNumber == 1)),
      turnSource: snapshot.pendingDiscard == null
          ? FinishCardSource.stock
          : FinishCardSource.previousDiscard,
      discardHistory: discardHistory,
    );
  }
}

/// Whether [snapshot] carries a resumable windowed take-discard: the take
/// provenance is complete and the saved turn is mid-action (the take always
/// leaves the seat in action phase with the card pending).
bool _resumesWindowedTake(ClassicHareegMatchSnapshot snapshot) {
  return snapshot.turnPhase == TurnPhase.action &&
      snapshot.windowedTakeCardId != null &&
      snapshot.windowedTakeDiscarder != null;
}

/// Whether [snapshot] carries a resumable mid-proof Fifty claim: the claim
/// fields are complete and the saved turn is mid-action (a proof turn can
/// only exist in action phase).
bool _resumesFiftyClaim(ClassicHareegMatchSnapshot snapshot) {
  return snapshot.turnPhase == TurnPhase.action &&
      snapshot.activeFiftyClaimCardId != null &&
      snapshot.activeFiftyClaimDiscarder != null;
}

/// Live state restored from a persisted Classic Hareeg match snapshot.
class ClassicHareegRestoredMatchState {
  /// Creates restored match state.
  ClassicHareegRestoredMatchState({
    required this.setup,
    required this.rules,
    required this.hands,
    required this.seed,
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
    this.activeFiftyClaimCardId,
    this.activeFiftyClaimDiscarder,
    this.activeFiftyClaimIsFirstDealtRound = false,
    this.windowedTakeCardId,
    this.windowedTakeDiscarder,
    this.windowedTakeIsFirstDealtRound = false,
  }) : discardHistory = discardHistory ?? DiscardHistory();

  /// Restored setup.
  final ClassicHareegSetup setup;

  /// Restored rules.
  final ClassicHareegRules rules;

  /// Detached live hands.
  final Map<PlayerSeat, List<HareegCard>> hands;

  /// Seed used to shuffle the restored round, when known.
  final int? seed;

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

  /// Claimed-card id of a Fifty proof turn active at save time, or null.
  final String? activeFiftyClaimCardId;

  /// Discarder charged when the restored proof completes, if a claim resumes.
  final PlayerSeat? activeFiftyClaimDiscarder;

  /// Whether the restored proof claim carries the first-dealt-round
  /// exception.
  final bool activeFiftyClaimIsFirstDealtRound;

  /// Physical id of a windowed discard taken via plain take-discard during an
  /// open window at save time, or null. Lets the resumed turn's finish score as
  /// a Fifty even though claim-fifty was never pressed.
  final String? windowedTakeCardId;

  /// Discarder charged when a resumed windowed take-discard turn finishes.
  final PlayerSeat? windowedTakeDiscarder;

  /// Whether the resumed windowed take carries the first-dealt-round exception.
  final bool windowedTakeIsFirstDealtRound;

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
