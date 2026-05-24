import '../models/playing_card.dart';
import 'joker_meld_assignment.dart';
import 'opening_rules.dart';

/// One legal way to commit a subset of a hand as one or more melds.
final class MeldPartition {
  /// Creates an immutable meld partition snapshot.
  MeldPartition({
    required Iterable<PlacedMeld> melds,
    required Iterable<HareegCard> cardsUsed,
    required Iterable<HareegCard> cardsRemaining,
    required Iterable<JokerMeldAssignment> jokerAssignments,
  }) : melds = List.unmodifiable(melds),
       cardsUsed = List.unmodifiable(cardsUsed),
       cardsRemaining = List.unmodifiable(cardsRemaining),
       jokerAssignments = List.unmodifiable(jokerAssignments);

  /// Melds placed by this partition.
  final List<PlacedMeld> melds;

  /// Cards consumed by [melds], with represented joker identities applied.
  final List<HareegCard> cardsUsed;

  /// Original physical cards left in hand after this partition.
  final List<HareegCard> cardsRemaining;

  /// Explicit represented identities selected for physical jokers.
  final List<JokerMeldAssignment> jokerAssignments;

  /// Combined original value of all placed melds.
  late final int totalValue = melds.fold<int>(
    0,
    (total, meld) => total + meld.valueSnapshot,
  );

  /// Number of melds in this partition.
  int get meldCount => melds.length;

  /// Average physical meld length.
  double get meanMeldLength {
    if (melds.isEmpty) {
      return 0;
    }
    return cardsUsed.length / melds.length;
  }

  /// Number of physical jokers consumed by this partition.
  late final int jokerCount = cardsUsed.where((card) => card.isJoker).length;

  /// Physical ids consumed by this partition.
  late final Set<String> usedCardIds = Set.unmodifiable(
    cardsUsed.map((card) => card.id),
  );

  /// Whether this partition consumes the physical card [cardId].
  bool usesCardId(String cardId) => usedCardIds.contains(cardId);
}
