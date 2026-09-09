import '../models/playing_card.dart';
import '../rules/meld_partition.dart';
import '../rules/meld_partition_enumerator.dart';

/// Partition cap for the complete-meld pass that produces the leftover set.
///
/// Matches the Expert planner's fan-out. The hand is enumerated once per
/// decision, so the larger cap is cheap.
const int completeMeldPartitionCap = 256;

/// A hand split into the complete melds it already holds and what is left.
class HandPartialSplit {
  /// Creates a split.
  const HandPartialSplit({required this.partition, required this.leftovers});

  /// The chosen complete-meld partition, or null when the hand has none.
  final MeldPartition? partition;

  /// The cards the partial grouping runs over.
  final List<HareegCard> leftovers;
}

/// Splits [hand] into its best complete-meld partition and the leftovers.
///
/// This is the one place the leftover set is derived. Both the keep-score model
/// and the development-liveness signal read it, so a card already committed to
/// a complete meld is never also counted as a developing pair — which would
/// have let a seat holding a finished set of sevens be told its sevens are a
/// dead draw.
HandPartialSplit splitForPartialGroups(List<HareegCard> hand) {
  if (hand.length >= 3) {
    final best = MeldPartitionEnumerator.topPartitions(
      hand,
      comparator: MeldPartitionRankers.byTotalValueDesc,
      take: 1,
      safetyCap: completeMeldPartitionCap,
    );
    if (best.isNotEmpty) {
      return HandPartialSplit(
        partition: best.first,
        leftovers: best.first.cardsRemaining,
      );
    }
  }
  return HandPartialSplit(partition: null, leftovers: hand);
}

/// What a selected partial group is built around.
enum PartialGroupKind {
  /// Two cards of the same rank in different suits.
  pair,

  /// Two cards of the same suit within two ranks of each other.
  run,

  /// A card that joined nothing.
  solo,
}

/// One selected disjoint group over a hand's leftover cards.
///
/// "Leftover" means what remains after the best complete-meld partition has
/// been removed — this type never re-derives that partition, it is handed the
/// remainder.
class PartialHandGroup {
  /// Creates a group.
  PartialHandGroup({
    required this.kind,
    required Iterable<HareegCard> cards,
    required this.value,
  }) : cards = List.unmodifiable(cards);

  /// What the group is built around.
  final PartialGroupKind kind;

  /// Member cards, in the order they were selected.
  final List<HareegCard> cards;

  /// The group's keep value, shared by every member.
  final int value;

  /// Whether this group is a developing pair or run rather than a lone card.
  bool get isDeveloping => kind != PartialGroupKind.solo;
}

/// True when [a] and [b] can still combine into the same meld — a SET (same
/// rank, distinct suits) or a RUN (same suit, within two ranks so a one-card gap
/// can still be filled).
///
/// A true duplicate (same rank AND suit) returns false: it can neither join a
/// set (which needs distinct suits) nor run with itself, so it is genuinely
/// isolated.
///
/// Distance is measured in the **low-Ace** ordering, where Ace is 1. That is
/// deliberate and load-bearing: it is the ordering the shipped keep-score model
/// has always used, so a same-suit King–Ace pair is *not* recognised as a
/// developing group. Changing it would move every keep score in the game.
/// Completion enumeration handles the high-Ace sequence separately.
bool cardsCanMeldTogether(CardIdentity a, CardIdentity b) {
  if (a.rank == b.rank) {
    return a.suit != b.suit; // set: distinct suits only
  }
  if (a.suit == b.suit) {
    final distance = (a.rank.order - b.rank.order).abs();
    return distance >= 1 && distance <= 2; // run within two ranks
  }
  return false;
}

/// Selects the best disjoint pair / two-run / solo grouping over [cards].
///
/// Maximises total group value, preferring a group over leaving a card solo on
/// ties, so developing pairs and runs are recognised rather than dissolved.
///
/// ## The tie rule is order-sensitive, on purpose
///
/// On equal totals a group beats solo, but **between two competing groups the
/// first one found wins**, and the search walks [cards] in the order given. So
/// same-suit leftovers `5,6,8` select `5-6` from `[5, 6, 8]` and `8-6` from
/// `[8, 6, 5]`, producing different per-card values.
///
/// That is the shipped behaviour and it is preserved verbatim here. A canonical
/// order-independent variant would change keep scores across the game, so it is
/// deliberately out of scope: do not "fix" this into a sorted pass.
List<PartialHandGroup> selectPartialGroups({
  required List<HareegCard> cards,
  required List<HareegCard> hand,
  required int Function(HareegCard card, List<HareegCard> hand) soloValue,
}) {
  return _best(cards, hand, soloValue, <String, List<PartialHandGroup>>{});
}

List<PartialHandGroup> _best(
  List<HareegCard> cards,
  List<HareegCard> hand,
  int Function(HareegCard, List<HareegCard>) soloValue,
  Map<String, List<PartialHandGroup>> memo,
) {
  if (cards.isEmpty) {
    return const [];
  }
  final key = (cards.map((card) => card.id).toList()..sort()).join('|');
  final cached = memo[key];
  if (cached != null) {
    return cached;
  }

  final anchor = cards.first;
  final rest = cards.sublist(1);

  // Candidate: anchor stays solo. Solo is the fallback (rank 0); a tying group
  // is preferred (rank 1) so a developing pair/run is not dissolved.
  final solo = soloValue(anchor, hand);
  final soloSub = _best(rest, hand, soloValue, memo);
  var bestTotal = solo + _totalOf(soloSub);
  var bestRank = 0;
  var bestGroups = <PartialHandGroup>[
    PartialHandGroup(kind: PartialGroupKind.solo, cards: [anchor], value: solo),
    ...soloSub,
  ];

  final anchorIdentity = anchor.effectiveIdentity;
  if (anchorIdentity != null && !anchor.isJoker) {
    for (var index = 0; index < rest.length; index += 1) {
      final other = rest[index];
      final otherIdentity = other.effectiveIdentity;
      if (otherIdentity == null || other.isJoker) {
        continue;
      }
      if (!cardsCanMeldTogether(anchorIdentity, otherIdentity)) {
        continue;
      }
      // Developing set (pair, distinct suits) scores value × 2; developing run
      // (same suit within two ranks) scores the pip sum.
      final isPair = anchorIdentity.rank == otherIdentity.rank;
      final groupValue = isPair
          ? anchorIdentity.rank.value * 2
          : anchorIdentity.rank.value + otherIdentity.rank.value;
      final remaining = [
        for (var position = 0; position < rest.length; position += 1)
          if (position != index) rest[position],
      ];
      final sub = _best(remaining, hand, soloValue, memo);
      final total = groupValue + _totalOf(sub);
      if (total > bestTotal || (total == bestTotal && bestRank == 0)) {
        bestTotal = total;
        bestRank = 1;
        bestGroups = <PartialHandGroup>[
          PartialHandGroup(
            kind: isPair ? PartialGroupKind.pair : PartialGroupKind.run,
            cards: [anchor, other],
            value: groupValue,
          ),
          ...sub,
        ];
      }
    }
  }

  memo[key] = bestGroups;
  return bestGroups;
}

int _totalOf(List<PartialHandGroup> groups) {
  var total = 0;
  for (final group in groups) {
    total += group.value;
  }
  return total;
}
