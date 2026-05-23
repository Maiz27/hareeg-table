import '../models/classic_hareeg_setup.dart';
import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../rules/opening_rules.dart';
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
  });

  /// Restores a saved match from JSON-compatible data, dispatching to the
  /// decoder for the schema version embedded in [json].
  factory ClassicHareegMatchSnapshot.fromJson(Map<String, Object?> json) {
    return decodeMatchSnapshotV1(json);
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

  /// Time the snapshot was saved.
  final DateTime savedAt;

  /// Converts the snapshot to JSON-compatible data in the current schema.
  Map<String, Object?> toJson() => encodeMatchSnapshotV1(this);
}
