import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../rules/opening_rules.dart';
import 'classic_hareeg_turn_journal.dart';

/// Snapshot-ready state after reversible active-turn table plays are rolled
/// back to a replayable checkpoint.
class ClassicHareegTurnCheckpointState {
  /// Creates checkpoint state for persistence.
  const ClassicHareegTurnCheckpointState({
    required this.hands,
    required this.tableMelds,
    required this.openingState,
    required this.pendingDiscard,
  });

  /// Hands to persist, grouped by seat.
  final Map<PlayerSeat, List<HareegCard>> hands;

  /// Table melds to persist, grouped by owner.
  final Map<PlayerSeat, List<PlacedMeld>> tableMelds;

  /// Opening benchmark state consistent with [tableMelds].
  final OpeningState openingState;

  /// Pending discard to persist, if the active turn is still resolving one.
  final HareegCard? pendingDiscard;
}

/// Deep module for the active-turn persistence checkpoint.
///
/// The live controller records reversible table play in
/// [ClassicHareegTurnJournal] and hands this projector a value snapshot of it.
/// This module owns how that snapshot is projected into a saved match
/// snapshot: covers are peeled back, current-turn melds are removed, pending
/// discard ownership is restored, represented jokers return to hand as
/// physical jokers, and the unlocked opening benchmark is reconciled with the
/// resulting table.
class ClassicHareegTurnCheckpoint {
  /// Creates a checkpoint projector from live controller facts.
  const ClassicHareegTurnCheckpoint({
    required this.currentSeat,
    required this.hands,
    required this.tableMelds,
    required this.openingState,
    required this.pendingDiscard,
    required this.journalSnapshot,
  });

  /// Seat whose active turn may have reversible table plays.
  final PlayerSeat currentSeat;

  /// Live hands grouped by seat.
  final Map<PlayerSeat, List<HareegCard>> hands;

  /// Live table melds grouped by owner.
  final Map<PlayerSeat, List<PlacedMeld>> tableMelds;

  /// Live opening benchmark state.
  final OpeningState openingState;

  /// Live pending discard.
  final HareegCard? pendingDiscard;

  /// Active-turn reversible play snapshot from the journal.
  final ClassicHareegTurnJournalSnapshot journalSnapshot;

  /// Produces the resume-safe state used by match snapshots.
  ClassicHareegTurnCheckpointState toSnapshotState() {
    final checkpointHands = {
      for (final entry in hands.entries)
        entry.key: List<HareegCard>.of(entry.value),
    };
    final checkpointTableMelds = {
      for (final entry in tableMelds.entries)
        entry.key: List<PlacedMeld>.of(entry.value),
    };
    var checkpointOpeningState = openingState;
    var checkpointPendingDiscard = pendingDiscard;
    final returnedCards = <HareegCard>[];

    void returnCards(Iterable<HareegCard> cards) {
      returnedCards.insertAll(0, [
        for (final card in cards)
          card.isJoker ? card.withoutRepresentation() : card,
      ]);
    }

    for (final play in journalSnapshot.coverPlays.reversed) {
      final targetMelds = checkpointTableMelds[play.targetSeat];
      if (targetMelds != null &&
          play.meldIndex >= 0 &&
          play.meldIndex < targetMelds.length) {
        targetMelds[play.meldIndex] = play.previousMeld;
      }
      returnCards(play.coverMeld.cards);
      checkpointOpeningState = play.previousOpeningState;
      checkpointPendingDiscard =
          play.consumedPendingDiscard ?? checkpointPendingDiscard;
    }

    for (final play in journalSnapshot.turnMelds.reversed) {
      final ownerMelds = checkpointTableMelds[play.owner];
      if (ownerMelds != null) {
        final index = ownerMelds.lastIndexWhere((meld) {
          return _samePhysicalCards(meld.cards, play.meld.cards);
        });
        if (index != -1) {
          ownerMelds.removeAt(index);
        }
      }
      returnCards(play.meld.cards);
      checkpointPendingDiscard =
          play.consumedPendingDiscard ?? checkpointPendingDiscard;
    }

    if (journalSnapshot.openingMelds.isNotEmpty) {
      final ownerMelds = checkpointTableMelds[currentSeat];
      if (ownerMelds != null) {
        for (final meld in journalSnapshot.openingMelds.reversed) {
          final index = ownerMelds.lastIndexWhere((candidate) {
            return _samePhysicalCards(candidate.cards, meld.cards);
          });
          if (index != -1) {
            ownerMelds.removeAt(index);
          }
        }
      }
      for (final meld in journalSnapshot.openingMelds.reversed) {
        returnCards(meld.cards);
      }
    }

    checkpointPendingDiscard =
        journalSnapshot.consumedPendingDiscard ?? checkpointPendingDiscard;
    if (returnedCards.isNotEmpty) {
      checkpointHands[currentSeat] = [
        ...returnedCards,
        ...?checkpointHands[currentSeat],
      ];
    }

    checkpointOpeningState = openingStateSyncedWith(
      openingState: checkpointOpeningState,
      tableMelds: checkpointTableMelds,
    );

    return ClassicHareegTurnCheckpointState(
      hands: {
        for (final entry in checkpointHands.entries)
          entry.key: List.of(entry.value),
      },
      tableMelds: {
        for (final entry in checkpointTableMelds.entries)
          entry.key: List.of(entry.value),
      },
      openingState: checkpointOpeningState,
      pendingDiscard: checkpointPendingDiscard,
    );
  }

  /// Returns an opening state whose unlocked benchmark agrees with [tableMelds].
  static OpeningState openingStateSyncedWith({
    required OpeningState openingState,
    required Map<PlayerSeat, List<PlacedMeld>> tableMelds,
    bool allowLower = true,
  }) {
    final owner = openingState.benchmarkOwner;
    if (owner == null || openingState.isLocked) {
      return openingState;
    }

    final ownerTableTotal = (tableMelds[owner] ?? const <PlacedMeld>[])
        .fold<int>(0, (total, meld) => total + meld.totalValue);
    final tableRequirement = ownerTableTotal > openingState.baseRequirement
        ? ownerTableTotal
        : openingState.baseRequirement;
    if (tableRequirement == openingState.currentRequirement ||
        (!allowLower && tableRequirement < openingState.currentRequirement)) {
      return openingState;
    }

    return OpeningState(
      baseRequirement: openingState.baseRequirement,
      currentRequirement: tableRequirement,
      benchmarkOwner: openingState.benchmarkOwner,
      openedSeats: openingState.openedSeats,
    );
  }
}

bool _samePhysicalCards(List<HareegCard> left, List<HareegCard> right) {
  if (left.length != right.length) {
    return false;
  }
  final leftIds = left.map((card) => card.id).toList()..sort();
  final rightIds = right.map((card) => card.id).toList()..sort();
  for (var i = 0; i < leftIds.length; i++) {
    if (leftIds[i] != rightIds[i]) {
      return false;
    }
  }
  return true;
}
