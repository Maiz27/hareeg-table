import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../rules/finish_rules.dart';
import '../rules/opening_rules.dart';
import 'physical_card_match.dart';

/// Reversible table-play journal for the active turn.
///
/// The controller owns a single journal instance per round and records play
/// intents through the methods on this type rather than editing list fields.
///
/// The journal mutates its internal lists in place (`add`, `addAll`, `clear`,
/// `removeAt`) so the hot apply path never re-allocates wrapper lists on each
/// write. External readers receive `unmodifiable` views, never the live lists.
class ClassicHareegTurnJournal {
  /// Creates a fresh journal seeded with optional starting state.
  ClassicHareegTurnJournal({
    Iterable<PlacedMeld> finishMelds = const [],
    Iterable<PlacedMeld> openingMelds = const [],
    Iterable<ClassicHareegTurnMeldPlay> turnMelds = const [],
    Iterable<ClassicHareegTurnCoverPlay> coverPlays = const [],
    HareegCard? consumedPendingDiscard,
    FinishCardSource source = FinishCardSource.stock,
  }) : _finishMelds = List<PlacedMeld>.of(finishMelds),
       _openingMelds = List<PlacedMeld>.of(openingMelds),
       _turnMelds = List<ClassicHareegTurnMeldPlay>.of(turnMelds),
       _coverPlays = List<ClassicHareegTurnCoverPlay>.of(coverPlays),
       _consumedPendingDiscard = consumedPendingDiscard,
       _source = source;

  // Internal lists are growable and mutated in place. See class doc.
  final List<PlacedMeld> _finishMelds;
  final List<PlacedMeld> _openingMelds;
  final List<ClassicHareegTurnMeldPlay> _turnMelds;
  final List<ClassicHareegTurnCoverPlay> _coverPlays;
  HareegCard? _consumedPendingDiscard;
  FinishCardSource _source;

  /// Unmodifiable view of cards played this turn that may prove a finish.
  List<PlacedMeld> get finishMeldsView => List.unmodifiable(_finishMelds);

  /// Unmodifiable view of staged opening melds.
  List<PlacedMeld> get openingMeldsView => List.unmodifiable(_openingMelds);

  /// Unmodifiable view of regular meld plays made this turn.
  List<ClassicHareegTurnMeldPlay> get turnMeldsView {
    return List.unmodifiable(_turnMelds);
  }

  /// Unmodifiable view of cover plays made this turn.
  List<ClassicHareegTurnCoverPlay> get coverPlaysView {
    return List.unmodifiable(_coverPlays);
  }

  /// Pending discard already consumed by staged opening melds, if any.
  HareegCard? get consumedPendingDiscard => _consumedPendingDiscard;

  /// Source of the card that enabled this turn's possible finish.
  FinishCardSource get source => _source;

  /// Whether any reversible table play is staged this turn.
  bool get hasAnyReversible {
    return _openingMelds.isNotEmpty ||
        _turnMelds.isNotEmpty ||
        _coverPlays.isNotEmpty;
  }

  /// Returns true when [meldIndex] is a valid index into the staged opening
  /// meld stack.
  bool isValidStagedOpeningIndex(int meldIndex) {
    return meldIndex >= 0 && meldIndex < _openingMelds.length;
  }

  /// Reads the staged opening meld at [meldIndex] without removing it.
  PlacedMeld stagedOpeningMeldAt(int meldIndex) => _openingMelds[meldIndex];

  /// Records new finish-eligible melds (opening or regular). Appends in place.
  void recordFinishMelds(Iterable<PlacedMeld> melds) {
    _finishMelds.addAll(melds);
  }

  /// Records staged opening melds and optionally the pending discard they
  /// consumed.
  void recordOpeningMelds(
    Iterable<PlacedMeld> melds, {
    HareegCard? consumedPendingDiscard,
  }) {
    _openingMelds.addAll(melds);
    if (consumedPendingDiscard != null) {
      _consumedPendingDiscard = consumedPendingDiscard;
    }
  }

  /// Clears staged opening melds and any associated consumed pending discard
  /// once the player has opened.
  void commitOpeningMelds() {
    _openingMelds.clear();
    _consumedPendingDiscard = null;
  }

  /// Records a regular meld play.
  void recordTurnMeld(ClassicHareegTurnMeldPlay play) {
    _turnMelds.add(play);
  }

  /// Records several regular meld plays in one batch.
  void recordTurnMelds(Iterable<ClassicHareegTurnMeldPlay> plays) {
    _turnMelds.addAll(plays);
  }

  /// Records a cover play.
  void recordCoverPlay(ClassicHareegTurnCoverPlay play) {
    _coverPlays.add(play);
  }

  /// Clears the active turn's consumed-pending-discard record.
  void clearConsumedPendingDiscard() {
    _consumedPendingDiscard = null;
  }

  /// Records that the pending discard was consumed by an in-flight opening
  /// attempt (without recording any new opening meld).
  void recordConsumedPendingDiscard(HareegCard card) {
    _consumedPendingDiscard = card;
  }

  /// Sets the source of the card that may enable a finish this turn.
  void setSource(FinishCardSource source) {
    _source = source;
  }

  /// Removes the last finish play whose card-ids match [meld] (physically) —
  /// retraction undoes the most recent matching record. No-op when no match
  /// exists.
  void removeFinishMeldMatching(PlacedMeld meld) {
    final index = _lastIndexOfPhysicalMatch(_finishMelds, meld.cards);
    if (index != -1) {
      _finishMelds.removeAt(index);
    }
  }

  /// Removes the recorded turn meld play, returning whether it was found.
  bool removeTurnMeld(ClassicHareegTurnMeldPlay play) {
    for (var i = _turnMelds.length - 1; i >= 0; i -= 1) {
      if (identical(_turnMelds[i], play)) {
        _turnMelds.removeAt(i);
        return true;
      }
    }
    return false;
  }

  /// Removes every cover play recorded against a specific table meld.
  void removeCoverPlaysFor({
    required PlayerSeat targetSeat,
    required int meldIndex,
  }) {
    _coverPlays.removeWhere((play) {
      return play.targetSeat == targetSeat && play.meldIndex == meldIndex;
    });
  }

  /// Pops the staged opening meld at [stagedIndex]. Returns null when the
  /// index is out of bounds.
  PlacedMeld? removeStagedOpeningAt(int stagedIndex) {
    if (!isValidStagedOpeningIndex(stagedIndex)) {
      return null;
    }
    final removed = _openingMelds.removeAt(stagedIndex);
    return removed;
  }

  /// Clears all staged opening melds and reports the snapshot that was
  /// cleared. Used by the bulk-retract path.
  List<PlacedMeld> drainOpeningMelds() {
    if (_openingMelds.isEmpty) {
      return const <PlacedMeld>[];
    }
    final drained = List<PlacedMeld>.of(_openingMelds);
    _openingMelds.clear();
    return drained;
  }

  /// Clears every recorded regular meld play and reports them.
  List<ClassicHareegTurnMeldPlay> drainTurnMelds() {
    if (_turnMelds.isEmpty) {
      return const <ClassicHareegTurnMeldPlay>[];
    }
    final drained = List<ClassicHareegTurnMeldPlay>.of(_turnMelds);
    _turnMelds.clear();
    return drained;
  }

  /// Clears every recorded cover play and reports them.
  List<ClassicHareegTurnCoverPlay> drainCoverPlays() {
    if (_coverPlays.isEmpty) {
      return const <ClassicHareegTurnCoverPlay>[];
    }
    final drained = List<ClassicHareegTurnCoverPlay>.of(_coverPlays);
    _coverPlays.clear();
    return drained;
  }

  /// Picks the staged opening index whose physical cards match [targetCards],
  /// or -1 when no staged meld matches.
  int findStagedOpeningIndexByPhysicalCards(List<HareegCard> targetCards) {
    return _openingMelds.indexWhere((staged) {
      return samePhysicalCards(staged.cards, targetCards);
    });
  }

  /// Picks the first turn meld whose owner and physical cards match
  /// [targetMeld], or null.
  ClassicHareegTurnMeldPlay? findTurnMeldFor({
    required PlayerSeat owner,
    required PlacedMeld targetMeld,
  }) {
    for (final play in _turnMelds) {
      if (play.owner == owner &&
          samePhysicalCards(play.meld.cards, targetMeld.cards)) {
        return play;
      }
    }
    return null;
  }

  /// Cover plays recorded against a specific table meld, in record order.
  List<ClassicHareegTurnCoverPlay> coverPlaysFor({
    required PlayerSeat owner,
    required int meldIndex,
  }) {
    return _coverPlays
        .where((play) {
          return play.targetSeat == owner && play.meldIndex == meldIndex;
        })
        .toList(growable: false);
  }

  /// Captures the journal as an immutable snapshot value the controller can
  /// hand off without exposing internal lists.
  ClassicHareegTurnJournalSnapshot toSnapshot() {
    return ClassicHareegTurnJournalSnapshot(
      finishMelds: List<PlacedMeld>.unmodifiable(_finishMelds),
      openingMelds: List<PlacedMeld>.unmodifiable(_openingMelds),
      turnMelds: List<ClassicHareegTurnMeldPlay>.unmodifiable(_turnMelds),
      coverPlays: List<ClassicHareegTurnCoverPlay>.unmodifiable(_coverPlays),
      consumedPendingDiscard: _consumedPendingDiscard,
      source: _source,
    );
  }

  /// Clears all recorded plays and resets [source] for the next turn.
  void resetForNewTurn({FinishCardSource source = FinishCardSource.stock}) {
    _finishMelds.clear();
    _openingMelds.clear();
    _turnMelds.clear();
    _coverPlays.clear();
    _consumedPendingDiscard = null;
    _source = source;
  }

  static int _lastIndexOfPhysicalMatch(
    List<PlacedMeld> melds,
    List<HareegCard> targetCards,
  ) {
    for (var i = melds.length - 1; i >= 0; i -= 1) {
      if (samePhysicalCards(melds[i].cards, targetCards)) {
        return i;
      }
    }
    return -1;
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

/// Immutable snapshot of the journal at one point in the turn.
///
/// The journal projects a checkpoint instead of letting the controller reach
/// into its lists; consumers (e.g. resume-after-quit, debug overlays) read
/// values, never the live state.
class ClassicHareegTurnJournalSnapshot {
  /// Creates a checkpoint.
  const ClassicHareegTurnJournalSnapshot({
    required this.finishMelds,
    required this.openingMelds,
    required this.turnMelds,
    required this.coverPlays,
    required this.consumedPendingDiscard,
    required this.source,
  });

  /// Empty starter checkpoint with default source.
  const ClassicHareegTurnJournalSnapshot.empty({
    this.source = FinishCardSource.stock,
  }) : finishMelds = const <PlacedMeld>[],
       openingMelds = const <PlacedMeld>[],
       turnMelds = const <ClassicHareegTurnMeldPlay>[],
       coverPlays = const <ClassicHareegTurnCoverPlay>[],
       consumedPendingDiscard = null;

  /// Cards played this turn that may prove a finish.
  final List<PlacedMeld> finishMelds;

  /// Uncommitted opening melds staged this turn.
  final List<PlacedMeld> openingMelds;

  /// Regular melds played this turn after opening.
  final List<ClassicHareegTurnMeldPlay> turnMelds;

  /// Cover plays made this turn.
  final List<ClassicHareegTurnCoverPlay> coverPlays;

  /// Pending discard already consumed by staged opening melds, if any.
  final HareegCard? consumedPendingDiscard;

  /// Source of the card that enabled this turn's possible finish.
  final FinishCardSource source;
}

