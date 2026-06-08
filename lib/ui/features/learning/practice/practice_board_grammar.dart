import '../../../../domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../domain/classic_hareeg/rules/meld_partition_enumerator.dart';
import '../../../../domain/classic_hareeg/rules/opening_rules.dart';

/// Executable board-design rules for guided practice lessons.
///
/// Practice boards are deterministic teaching positions, but they still need
/// to read like real Hareeg deals: visible openings total what they imply, and
/// a seat's hand plus own table cards should account for one deal unless the
/// lesson deliberately uses a mini hand.
abstract final class PracticeBoardGrammar {
  /// Default dealt hand size in Classic Hareeg.
  static const dealtHandSize = 14;

  /// Total table value for [seat].
  static int tableValueForController(
    ClassicHareegGameController controller,
    PlayerSeat seat,
  ) {
    return tableValue(controller.tableMeldsFor(seat));
  }

  /// Number of table cards owned by [seat].
  static int tableCardCountForController(
    ClassicHareegGameController controller,
    PlayerSeat seat,
  ) {
    return tableCardCount(controller.tableMeldsFor(seat));
  }

  /// Total value of [melds].
  static int tableValue(Iterable<PlacedMeld> melds) {
    return melds.fold<int>(0, (sum, meld) => sum + meld.totalValue);
  }

  /// Total card count of [melds].
  static int tableCardCount(Iterable<PlacedMeld> melds) {
    return melds.fold<int>(0, (sum, meld) => sum + meld.cards.length);
  }

  /// Whether [seat]'s hand and table cards read as one dealt hand.
  static bool handAndTableReadAsOneDeal(
    ClassicHareegMatchSnapshot snapshot,
    PlayerSeat seat, {
    int dealtCards = dealtHandSize,
    int extraCardsInHand = 0,
  }) {
    final handCount = snapshot.hands[seat]?.length ?? 0;
    final tableCount = tableCardCount(snapshot.tableMelds[seat] ?? const []);
    return handCount + tableCount == dealtCards + extraCardsInHand;
  }

  /// Id set for [cards].
  static Set<String> idsOf(Iterable<HareegCard> cards) {
    return {for (final card in cards) card.id};
  }

  /// Audits [snapshot] against declared board-design rules.
  ///
  /// When [taughtMelds] is non-null, the audit also proves the lesson hand is
  /// clean: every card in [compositionSeat]'s hand that is not part of a
  /// declared teaching group must leave no unintended meld behind. This is the
  /// executable form of the per-lesson "Fillers: no meld" comment discipline.
  /// A null [taughtMelds] skips the composition check (the lesson makes no
  /// hand-cleanliness claim).
  static PracticeBoardAuditResult auditSnapshot(
    ClassicHareegMatchSnapshot snapshot,
    PracticeBoardAuditSpec spec, {
    PlayerSeat compositionSeat = PlayerSeat.south,
    List<Set<String>>? taughtMelds,
  }) {
    final failures = <String>[];

    for (final entry in spec.expectedTableValues.entries) {
      final actual = tableValue(snapshot.tableMelds[entry.key] ?? const []);
      if (actual != entry.value) {
        failures.add(
          '${entry.key.name} table value is $actual; expected ${entry.value}.',
        );
      }
    }

    for (final seat in spec.handAndTableSeats) {
      final extra = spec.extraCardsInHand[seat] ?? 0;
      if (!handAndTableReadAsOneDeal(
        snapshot,
        seat,
        dealtCards: spec.dealtCards,
        extraCardsInHand: extra,
      )) {
        final handCount = snapshot.hands[seat]?.length ?? 0;
        final tableCount = tableCardCount(
          snapshot.tableMelds[seat] ?? const [],
        );
        failures.add(
          '${seat.name} hand + table is ${handCount + tableCount}; '
          'expected ${spec.dealtCards + extra}.',
        );
      }
    }

    for (final seat in spec.fullHandSeats) {
      final actual = snapshot.hands[seat]?.length ?? 0;
      if (actual != spec.dealtCards) {
        failures.add(
          '${seat.name} hand has $actual cards; expected ${spec.dealtCards}.',
        );
      }
    }

    final minPile = spec.minimumDiscardPileSize;
    if (minPile != null && snapshot.discardPile.length < minPile) {
      failures.add(
        'discard pile has ${snapshot.discardPile.length} cards; '
        'expected at least $minPile.',
      );
    }

    if (taughtMelds != null) {
      failures.addAll(
        _handCompositionFailures(snapshot, compositionSeat, taughtMelds),
      );
    }

    return PracticeBoardAuditResult._(failures);
  }

  /// Cards in [seat]'s hand that are not part of any declared teaching group.
  static List<HareegCard> fillerCards(
    ClassicHareegMatchSnapshot snapshot,
    PlayerSeat seat,
    List<Set<String>> taughtMelds,
  ) {
    final taught = {for (final meld in taughtMelds) ...meld};
    final hand = snapshot.hands[seat] ?? const <HareegCard>[];
    return [
      for (final card in hand)
        if (!taught.contains(card.id)) card,
    ];
  }

  /// Proves [seat]'s filler cards (hand minus the declared teaching groups)
  /// form no unintended meld, by asking the real meld enumerator. A lesson
  /// hand that holds a stray meld would light an affordance the prompt never
  /// describes — `firstMeld`'s open step, for one, allows any `playMeld`.
  static List<String> _handCompositionFailures(
    ClassicHareegMatchSnapshot snapshot,
    PlayerSeat seat,
    List<Set<String>> taughtMelds,
  ) {
    final fillers = fillerCards(snapshot, seat, taughtMelds);
    final stray = MeldPartitionEnumerator.partitionsOf(
      fillers,
      maxMelds: 1,
    ).take(1).toList();
    if (stray.isEmpty) {
      return const [];
    }
    final ids = (stray.first.usedCardIds.toList()..sort()).join(', ');
    return [
      '${seat.name} filler cards form an unintended meld ($ids); a lesson '
      'hand must hold no meld beyond its declared teaching cards.',
    ];
  }
}

/// Declared board-design rules for one lesson board audit.
class PracticeBoardAuditSpec {
  /// Creates an audit spec.
  const PracticeBoardAuditSpec({
    this.dealtCards = PracticeBoardGrammar.dealtHandSize,
    this.handAndTableSeats = const {},
    this.extraCardsInHand = const {},
    this.expectedTableValues = const {},
    this.fullHandSeats = const {},
    this.minimumDiscardPileSize,
  });

  /// Expected dealt hand size for seats under audit.
  final int dealtCards;

  /// Seats whose hand plus own table cards must account for one deal.
  final Set<PlayerSeat> handAndTableSeats;

  /// Extra cards expected in hand for mid-turn boards after a draw.
  final Map<PlayerSeat, int> extraCardsInHand;

  /// Expected visible table value by seat.
  final Map<PlayerSeat, int> expectedTableValues;

  /// Seats expected to still hold a full unopened hand.
  final Set<PlayerSeat> fullHandSeats;

  /// Minimum discard-pile depth required by a dressed late-round board.
  final int? minimumDiscardPileSize;
}

/// Result of a practice board audit.
class PracticeBoardAuditResult {
  PracticeBoardAuditResult._(List<String> failures)
    : failures = List.unmodifiable(failures);

  /// Human-readable audit failures.
  final List<String> failures;

  /// Whether every declared rule passed.
  bool get passed => failures.isEmpty;
}
