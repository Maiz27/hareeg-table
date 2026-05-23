import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../rules/finish_rules.dart';
import '../rules/opening_rules.dart';

/// Mutable record of reversible table plays for the active turn.
///
/// The controller owns a single ledger instance per round and mutates it in
/// place across the turn. The fields are intentionally directly accessible so
/// apply paths can `add`, `addAll`, or `clear` without re-allocating wrapper
/// lists on each write.
class ClassicHareegTurnLedger {
  /// Creates a turn ledger seeded with the given plays.
  ClassicHareegTurnLedger({
    Iterable<PlacedMeld> finishPlays = const [],
    Iterable<PlacedMeld> openingMelds = const [],
    Iterable<ClassicHareegTurnMeldPlay> meldPlays = const [],
    Iterable<ClassicHareegTurnCoverPlay> coverPlays = const [],
    this.consumedPendingDiscard,
    this.source = FinishCardSource.stock,
  }) : finishPlays = List.of(finishPlays),
       openingMelds = List.of(openingMelds),
       meldPlays = List.of(meldPlays),
       coverPlays = List.of(coverPlays);

  /// Cards played this turn that may prove a finish.
  final List<PlacedMeld> finishPlays;

  /// Uncommitted opening melds staged this turn.
  final List<PlacedMeld> openingMelds;

  /// Regular melds played this turn after opening.
  final List<ClassicHareegTurnMeldPlay> meldPlays;

  /// Cover plays made this turn.
  final List<ClassicHareegTurnCoverPlay> coverPlays;

  /// Pending discard already consumed by staged opening melds, if any.
  HareegCard? consumedPendingDiscard;

  /// Source of the card that enabled this turn's possible finish.
  FinishCardSource source;

  /// Clears all turn records and resets [source] for the next turn.
  void resetForNewTurn({FinishCardSource source = FinishCardSource.stock}) {
    finishPlays.clear();
    openingMelds.clear();
    meldPlays.clear();
    coverPlays.clear();
    consumedPendingDiscard = null;
    this.source = source;
  }
}

/// A regular meld played during the current turn.
class ClassicHareegTurnMeldPlay {
  /// Creates a current-turn meld play record.
  const ClassicHareegTurnMeldPlay({
    required this.owner,
    required this.meld,
    this.consumedPendingDiscard,
  });

  /// Seat that owns the table meld.
  final PlayerSeat owner;

  /// Meld placed on the table.
  final PlacedMeld meld;

  /// Pending discard consumed by this meld, if any.
  final HareegCard? consumedPendingDiscard;
}

/// A cover play made during the current turn.
class ClassicHareegTurnCoverPlay {
  /// Creates a current-turn cover play record.
  const ClassicHareegTurnCoverPlay({
    required this.targetSeat,
    required this.meldIndex,
    required this.previousMeld,
    required this.coverMeld,
    required this.previousOpeningState,
    this.consumedPendingDiscard,
  });

  /// Seat that owns the covered meld.
  final PlayerSeat targetSeat;

  /// Covered meld index at the time of play.
  final int meldIndex;

  /// Meld snapshot before the cover was applied.
  final PlacedMeld previousMeld;

  /// Cover cards as a placed-meld-like value snapshot.
  final PlacedMeld coverMeld;

  /// Opening benchmark before the cover was applied.
  final OpeningState previousOpeningState;

  /// Pending discard consumed by this cover, if any.
  final HareegCard? consumedPendingDiscard;
}
