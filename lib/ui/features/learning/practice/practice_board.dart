import '../../../../domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_round.dart';
import '../../../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../domain/classic_hareeg/rules/opening_rules.dart';

/// Builds deterministic mini-hand boards for guided practice lessons.
///
/// Every board starts from a seeded full deal so card conservation holds (each
/// physical card exists exactly once), then moves the lesson's named cards
/// into place: the player's exact teaching hand, an optional top discard, and
/// optional pre-placed table melds. Everything else stays in stock or the
/// untouched CPU hands — practice never runs CPU turns, so those hands only
/// exist to keep the board physically consistent.
abstract final class PracticeBoard {
  /// Fixed savedAt for practice snapshots; the value is never shown and never
  /// persisted to the active-match store, it only satisfies the model.
  static final DateTime _savedAt = DateTime.utc(2026, 1, 1);

  /// Builds a deterministic lesson snapshot.
  ///
  /// [southHand] is the exact teaching hand. [topDiscard] (if given) becomes
  /// the only discard-pile card. [tableMelds] are pre-placed melds keyed by
  /// owner seat. [openingState] defaults to a fresh benchmark at the setup's
  /// opening requirement. The lesson seat is always [PlayerSeat.south].
  static ClassicHareegMatchSnapshot build({
    required List<HareegCard> southHand,
    HareegCard? topDiscard,
    Map<PlayerSeat, List<PlacedMeld>> tableMelds = const {},
    OpeningState? openingState,
    TurnPhase turnPhase = TurnPhase.draw,
    ClassicHareegSetup? setup,
    int seed = 404,
  }) {
    final effectiveSetup = setup ?? ClassicHareegSetup.defaults();
    final base = ClassicHareegRound.deal(
      setup: effectiveSetup,
      seed: seed,
      // South never starts: lessons that teach the draw phase need a seat
      // that begins its turn by drawing.
      starterOverride: PlayerSeat.east,
    );

    // Cards claimed by the lesson setup, by physical id.
    final claimedIds = <String>{
      for (final card in southHand) card.id,
      if (topDiscard != null) topDiscard.id,
      for (final melds in tableMelds.values)
        for (final meld in melds)
          for (final card in meld.cards) card.id,
    };

    // Pool every dealt card, then keep only the unclaimed ones for the CPU
    // hands and stock so each physical card appears exactly once.
    final pool = <HareegCard>[
      for (final hand in base.hands.values) ...hand,
      ...base.stock,
      ...base.discardPile,
    ];
    final unclaimed = [
      for (final card in pool)
        if (!claimedIds.contains(card.id)) card,
    ];

    if (pool.length - unclaimed.length != claimedIds.length) {
      throw StateError(
        'Practice board claims cards missing from the dealt pool: '
        '$claimedIds',
      );
    }

    // Small dummy CPU hands keep seat counts plausible without mattering to
    // the lesson; the rest becomes stock.
    const cpuHandSize = 5;
    final hands = <PlayerSeat, List<HareegCard>>{
      PlayerSeat.south: List.unmodifiable(southHand),
    };
    var cursor = 0;
    for (final seat in const [
      PlayerSeat.east,
      PlayerSeat.north,
      PlayerSeat.west,
    ]) {
      hands[seat] = List.unmodifiable(
        unclaimed.sublist(cursor, cursor + cpuHandSize),
      );
      cursor += cpuHandSize;
    }
    final stock = List<HareegCard>.unmodifiable(unclaimed.sublist(cursor));

    return ClassicHareegMatchSnapshot(
      setup: effectiveSetup,
      hands: hands,
      stock: stock,
      discardPile: [?topDiscard],
      tableMelds: tableMelds,
      starter: PlayerSeat.east,
      currentSeat: PlayerSeat.south,
      turnPhase: turnPhase,
      openingState: openingState,
      savedAt: _savedAt,
    );
  }

  /// Standard non-joker physical card shorthand for lesson scripts.
  static HareegCard card(CardRank rank, CardSuit suit, {int deckIndex = 0}) {
    return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
  }

  /// Physical joker shorthand matching the deal's joker numbering, so a
  /// claimed joker lines up with the dealt pool by id.
  static HareegCard joker({int jokerIndex = 0}) {
    return HareegCard.joker(deckIndex: jokerIndex ~/ 2, jokerIndex: jokerIndex);
  }

  /// Opening state with [seat] already opened so table plays do not stage
  /// behind the opening benchmark.
  static OpeningState openedFor(PlayerSeat seat, {int requirement = 51}) {
    return OpeningState(
      baseRequirement: requirement,
      currentRequirement: requirement,
      openedSeats: {seat},
    );
  }

  /// Opening state with several seats already opened (e.g. a lesson where a
  /// CPU seat owns table melds and the player covers them).
  static OpeningState openedSeats(
    Set<PlayerSeat> seats, {
    int requirement = 51,
  }) {
    return OpeningState(
      baseRequirement: requirement,
      currentRequirement: requirement,
      openedSeats: seats,
    );
  }

  /// Opening state where [opener] already opened high, raising the live
  /// benchmark above its base for everyone still unopened.
  static OpeningState raisedBenchmark({
    required PlayerSeat opener,
    required int currentRequirement,
    int baseRequirement = 51,
  }) {
    return OpeningState(
      baseRequirement: baseRequirement,
      currentRequirement: currentRequirement,
      openedSeats: {opener},
    );
  }
}
