import '../../../../domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_round.dart';
import '../../../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../domain/classic_hareeg/rules/classic_hareeg_rules.dart';
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
  /// opening requirement. [cpuSeedCards] pins named cards into a CPU seat's
  /// hand for scripted intro turns (the rest of that hand pads with dummies).
  /// [currentSeat] defaults to the south lesson seat; boards with a scripted
  /// intro start on the acting CPU seat instead.
  static ClassicHareegMatchSnapshot build({
    required List<HareegCard> southHand,
    HareegCard? topDiscard,
    Map<PlayerSeat, List<PlacedMeld>> tableMelds = const {},
    Map<PlayerSeat, List<HareegCard>> cpuSeedCards = const {},
    OpeningState? openingState,
    PlayerSeat currentSeat = PlayerSeat.south,
    TurnPhase turnPhase = TurnPhase.draw,
    ClassicHareegSetup? setup,
    int seed = 404,
  }) {
    final effectiveSetup = setup ?? ClassicHareegSetup.defaults();
    // One ruleset feeds both the deal and the CPU hand padding below, so
    // the pad size can never drift from the dealt hand size.
    final rules = ClassicHareegRules.defaults();
    final base = ClassicHareegRound.deal(
      setup: effectiveSetup,
      rules: rules,
      seed: seed,
      // South never starts: lessons that teach the draw phase need a seat
      // that begins its turn by drawing.
      starterOverride: PlayerSeat.east,
    );

    // Cards claimed by the lesson setup, by physical id. A duplicate claim
    // (the same physical card named in two places) would silently shrink
    // the set and slip past the pool-count guard below, materialising the
    // card twice on the board — fail fast with the offending ids instead.
    final claimedIds = <String>{};
    final duplicateIds = <String>{};
    void claim(HareegCard card) {
      if (!claimedIds.add(card.id)) {
        duplicateIds.add(card.id);
      }
    }

    southHand.forEach(claim);
    if (topDiscard != null) {
      claim(topDiscard);
    }
    for (final melds in tableMelds.values) {
      for (final meld in melds) {
        meld.cards.forEach(claim);
      }
    }
    // The lesson seat's hand comes from [southHand] alone; a south entry
    // here would claim cards out of the pool that no hand ever
    // materialises, silently dropping them from the board.
    if (cpuSeedCards.containsKey(PlayerSeat.south)) {
      throw ArgumentError(
        'cpuSeedCards must not seed the lesson seat — '
        'southHand is the sole source for south.',
      );
    }
    for (final seeds in cpuSeedCards.values) {
      seeds.forEach(claim);
    }
    if (duplicateIds.isNotEmpty) {
      throw ArgumentError(
        'Practice board claims the same physical card more than once: '
        '$duplicateIds',
      );
    }

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

    // CPU hands deal the real hand size so the table reads like a live
    // match; seeded cards for scripted intro turns come first, dummies pad
    // the rest, and everything left over becomes stock.
    final cpuHandSize = rules.cardsPerPlayer;
    final hands = <PlayerSeat, List<HareegCard>>{
      PlayerSeat.south: List.unmodifiable(southHand),
    };
    var cursor = 0;
    for (final seat in const [
      PlayerSeat.east,
      PlayerSeat.north,
      PlayerSeat.west,
    ]) {
      final seeds = cpuSeedCards[seat] ?? const <HareegCard>[];
      final padCount = cpuHandSize - seeds.length;
      if (padCount < 0) {
        throw ArgumentError(
          'Practice board seeds ${seeds.length} cards for ${seat.name}, '
          'past the $cpuHandSize-card hand.',
        );
      }
      hands[seat] = List.unmodifiable([
        ...seeds,
        ...unclaimed.sublist(cursor, cursor + padCount),
      ]);
      cursor += padCount;
    }
    final stock = List<HareegCard>.unmodifiable(unclaimed.sublist(cursor));

    return ClassicHareegMatchSnapshot(
      setup: effectiveSetup,
      hands: hands,
      stock: stock,
      discardPile: [?topDiscard],
      tableMelds: tableMelds,
      starter: PlayerSeat.east,
      currentSeat: currentSeat,
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
}
