import '../models/classic_hareeg_setup.dart';
import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../persistence/persistence_codec.dart';
import '../rules/opening_rules.dart';
import 'classic_hareeg_discard_history.dart';
import 'classic_hareeg_match_snapshot_v1.dart';
import 'classic_hareeg_round.dart';

/// Serializable active Classic Hareeg match state.
///
/// Lives in the domain layer so the rules-engine seam can describe full game
/// state in a JSON-friendly form without depending on the data/persistence
/// layer.
///
/// The wire format lives in a sibling file (`classic_hareeg_match_snapshot_v1
/// .dart`) so the model stays focused on shape and a future schema version
/// can be added without touching this file beyond the dispatcher.
///
/// ## Schema evolution
///
/// The `version` field on the wire format stays at v1; new optional fields
/// are added with backward-compatible defaults so existing installs keep
/// resuming through an app update. The current additions are:
///
/// - `discardHistory` — per-round CPU discard memory. Missing field falls
///   back to an empty history; older saves replay as if CPU memory just
///   reset for the round (the prior behaviour). When the wire format
///   needs an incompatible change instead, bump to a `v2.dart` sibling and
///   register it on the dispatcher.
class ClassicHareegMatchSnapshot {
  /// Creates a saved match snapshot.
  const ClassicHareegMatchSnapshot({
    required this.setup,
    required this.hands,
    required this.stock,
    required this.discardPile,
    required this.starter,
    required this.currentSeat,
    required this.turnPhase,
    required this.savedAt,
    this.tableMelds = const {},
    this.pendingDiscard,
    this.openingState,
    this.scores = const {},
    this.activeSeats = const [
      PlayerSeat.south,
      PlayerSeat.east,
      PlayerSeat.north,
      PlayerSeat.west,
    ],
    this.roundNumber = 1,
    this.removedSeats = const [],
    this.fiftyWindowOpenedAt,
    this.fiftyWindowDiscarder,
    this.fiftyWindowIsFirstDealtRound,
    this.activeFiftyClaimCardId,
    this.activeFiftyClaimDiscarder,
    this.activeFiftyClaimIsFirstDealtRound,
    this.discardHistoryEvents = const [],
  });

  /// Restores a saved match from JSON-compatible data, dispatching to the
  /// decoder for the schema version embedded in [json].
  ///
  /// Routing goes through [decodeWithSchemaVersion] so future versions can
  /// register additional decoders without changing call sites.
  factory ClassicHareegMatchSnapshot.fromJson(Map<String, Object?> json) {
    return decodeWithSchemaVersion<ClassicHareegMatchSnapshot>(
      json,
      decoders: {matchSnapshotV1Version: decodeMatchSnapshotV1},
      fallbackVersion: matchSnapshotV1Version,
    );
  }

  /// Setup values active for the saved match.
  final ClassicHareegSetup setup;

  /// Cards held by each seat.
  final Map<PlayerSeat, List<HareegCard>> hands;

  /// Face-down stock cards.
  final List<HareegCard> stock;

  /// Face-up discard pile.
  final List<HareegCard> discardPile;

  /// Melds already played onto the table by each seat.
  final Map<PlayerSeat, List<PlacedMeld>> tableMelds;

  /// Seat that started the current round.
  final PlayerSeat starter;

  /// Seat whose turn is active.
  final PlayerSeat currentSeat;

  /// Current turn phase.
  final TurnPhase turnPhase;

  /// Pending discard card that must be used or returned.
  final HareegCard? pendingDiscard;

  /// Opening benchmark state for the active round.
  final OpeningState? openingState;

  /// Match scores before the active round result is applied.
  final Map<PlayerSeat, int> scores;

  /// Seats still active in the match.
  final List<PlayerSeat> activeSeats;

  /// One-based dealt round number for first-round Fifty rules.
  final int roundNumber;

  /// Seats removed from the current round by hard-table mistakes.
  final List<PlayerSeat> removedSeats;

  /// Time the current Fifty claim window opened, if a window is active.
  final DateTime? fiftyWindowOpenedAt;

  /// True discarder of the open Fifty window's card, persisted verbatim.
  ///
  /// Restore prefers this over geometrically guessing the discarder from
  /// seating order, which mis-attributes the Fifty penalty once seats have
  /// been removed from the round. Older saves without this field fall back
  /// to the legacy geometric guess for backward compatibility.
  final PlayerSeat? fiftyWindowDiscarder;

  /// Whether the open Fifty window belongs to the first dealt round, persisted
  /// verbatim so the -1 (vs -3) scoring exception survives a save/restore
  /// instead of being re-derived from [roundNumber]. Older saves without this
  /// field fall back to the legacy `roundNumber == 1` derivation.
  final bool? fiftyWindowIsFirstDealtRound;

  /// Physical id of the claimed card when a Fifty proof turn was active at
  /// save time, or null. The checkpoint reverts the proof's table plays, so
  /// the claimed card sits back in the claimant's hand as the pending
  /// discard; restore resumes the proof turn from its start. v1-additive —
  /// absent in older saves (no claim was ever mid-proof there).
  final String? activeFiftyClaimCardId;

  /// Seat whose discard was claimed during the active proof turn, or null.
  final PlayerSeat? activeFiftyClaimDiscarder;

  /// Whether the active proof claim carried the first-dealt-round exception.
  final bool? activeFiftyClaimIsFirstDealtRound;

  /// Time the snapshot was saved.
  final DateTime savedAt;

  /// Per-round CPU discard memory captured at save time.
  ///
  /// Stored as the chronological [DiscardEvent] stream so restore can replay
  /// each event through the live `recordDiscard` / `recordPickup` paths and
  /// rebuild derived indices without the wire format duplicating them.
  final List<DiscardEvent> discardHistoryEvents;

  /// Converts the snapshot to JSON-compatible data in the current schema.
  Map<String, Object?> toJson() => encodeMatchSnapshotV1(this);
}
