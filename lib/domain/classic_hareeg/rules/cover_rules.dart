import '../models/playing_card.dart';
import 'meld_card_ordering.dart';
import 'meld_validator.dart';

/// Result of checking discard legality for a cover card.
class CoverDiscardResult {
  /// Creates a cover discard result.
  const CoverDiscardResult({required this.canDiscard, required this.message});

  /// Whether the card may be discarded in the current context.
  final bool canDiscard;

  /// Player-facing explanation.
  final String message;
}

/// One legal cover card plus the meld shape after applying it.
class CoverExtension {
  /// Creates a resolved cover extension.
  const CoverExtension({
    required this.card,
    required this.extendedMeld,
    required this.placement,
  });

  /// Physical cover card, with joker representation assigned when needed.
  final HareegCard card;

  /// Table meld after [card] has been appended.
  final List<HareegCard> extendedMeld;

  /// Display end where the cover lands.
  final CoverPlacement placement;
}

/// Position where a cover card extends a target meld.
enum CoverPlacement {
  /// Cover lands before the first sequence card.
  lowEnd,

  /// Cover lands after the last sequence card.
  highEnd,

  /// Cover fills a same-rank set rather than a sequence end.
  set,
}

/// Classic Hareeg cover detection and discard restriction rules.
abstract final class ClassicHareegCoverRules {
  /// Whether a card can legally extend a table meld right now.
  static bool isCover({
    required List<HareegCard> tableMeld,
    required HareegCard candidate,
  }) {
    return resolveCoverExtension(
          tableMeld: tableMeld,
          candidate: candidate,
          resolveJoker: false,
        ) !=
        null;
  }

  /// Returns whether any table meld can receive this card as a cover.
  static bool isAnyCover({
    required Iterable<List<HareegCard>> tableMelds,
    required HareegCard candidate,
  }) {
    return tableMelds.any((meld) {
      return isCover(tableMeld: meld, candidate: candidate);
    });
  }

  /// Opened players may place covers; unopened players are trapped with them.
  static bool canPlayCover({required bool playerOpened}) {
    return playerOpened;
  }

  /// Places a cover and returns the extended meld.
  static List<HareegCard> placeCover({
    required bool playerOpened,
    required List<HareegCard> tableMeld,
    required HareegCard candidate,
  }) {
    if (!playerOpened) {
      throw StateError('Unopened players cannot play covers yet.');
    }
    if (!isCover(tableMeld: tableMeld, candidate: candidate)) {
      throw StateError('Card is not a current cover for this meld.');
    }

    return List.unmodifiable([...tableMeld, candidate]);
  }

  /// Returns cover cards in legal application order, if possible.
  static List<HareegCard>? orderedCoverCards({
    required List<HareegCard> tableMeld,
    required List<HareegCard> candidates,
  }) {
    if (candidates.isEmpty) {
      return const [];
    }

    for (var index = 0; index < candidates.length; index += 1) {
      final candidate = candidates[index];
      final extension = resolveCoverExtension(
        tableMeld: tableMeld,
        candidate: candidate,
      );
      if (extension == null) {
        continue;
      }
      final remaining = [
        ...candidates.take(index),
        ...candidates.skip(index + 1),
      ];
      final next = orderedCoverCards(
        tableMeld: extension.extendedMeld,
        candidates: remaining,
      );
      if (next != null) {
        return [extension.card, ...next];
      }
    }
    return null;
  }

  /// Resolves one cover candidate, including joker cover identity if needed.
  static HareegCard? resolveCoverCandidate({
    required List<HareegCard> tableMeld,
    required HareegCard candidate,
  }) {
    return resolveCoverExtension(
      tableMeld: tableMeld,
      candidate: candidate,
    )?.card;
  }

  /// Resolves the exact cover extension produced by [candidate].
  static CoverExtension? resolveCoverExtension({
    required List<HareegCard> tableMeld,
    required HareegCard candidate,
    bool resolveJoker = true,
  }) {
    final options = coverExtensions(
      tableMeld: tableMeld,
      candidate: candidate,
      resolveJoker: resolveJoker,
    );
    return options.isEmpty ? null : options.first;
  }

  /// Resolves every legal cover extension produced by [candidate].
  static List<CoverExtension> coverExtensions({
    required List<HareegCard> tableMeld,
    required HareegCard candidate,
    bool resolveJoker = true,
  }) {
    final direct = _directCoverExtension(
      tableMeld: tableMeld,
      candidate: candidate,
    );
    if (direct != null) {
      return [direct];
    }
    if (!resolveJoker) {
      return const [];
    }
    if (!candidate.isJoker || candidate.representedIdentity != null) {
      return const [];
    }

    final options = <CoverExtension>[];
    for (final suit in CardSuit.values) {
      for (final rank in CardRank.values) {
        final extension = _directCoverExtension(
          tableMeld: tableMeld,
          candidate: candidate.asRepresenting(
            CardIdentity(rank: rank, suit: suit),
          ),
        );
        if (extension != null) {
          options.add(extension);
        }
      }
    }
    if (options.isEmpty) {
      return const [];
    }
    options.sort((left, right) {
      final leftIdentity = left.card.effectiveIdentity!;
      final rightIdentity = right.card.effectiveIdentity!;
      final suitCompare = leftIdentity.suit.index.compareTo(
        rightIdentity.suit.index,
      );
      if (suitCompare != 0) {
        return suitCompare;
      }
      return leftIdentity.rank.order.compareTo(rightIdentity.rank.order);
    });
    return List.unmodifiable(options);
  }

  /// Checks normal cover discard restriction.
  static CoverDiscardResult canDiscard({
    required Iterable<List<HareegCard>> tableMelds,
    required HareegCard candidate,
    required bool isFinalDiscard,
  }) {
    if (isFinalDiscard) {
      return const CoverDiscardResult(
        canDiscard: true,
        message: 'Final discard may use a cover.',
      );
    }

    if (isAnyCover(tableMelds: tableMelds, candidate: candidate)) {
      return const CoverDiscardResult(
        canDiscard: false,
        message: 'This card is a cover and cannot be discarded normally.',
      );
    }

    return const CoverDiscardResult(
      canDiscard: true,
      message: 'Card can be discarded.',
    );
  }

  static CoverExtension? _directCoverExtension({
    required List<HareegCard> tableMeld,
    required HareegCard candidate,
  }) {
    if (candidate.effectiveIdentity == null || tableMeld.length < 3) {
      return null;
    }

    final current = ClassicHareegMeldValidator.validate(tableMeld);
    if (!current.isValid || current.type == null) {
      return null;
    }

    final extendedMeld = List<HareegCard>.unmodifiable([
      ...tableMeld,
      candidate,
    ]);
    final extended = ClassicHareegMeldValidator.validate(extendedMeld);
    if (!extended.isValid || extended.type != current.type) {
      return null;
    }

    return CoverExtension(
      card: candidate,
      extendedMeld: extendedMeld,
      placement: _coverPlacement(
        extendedMeld: extendedMeld,
        candidate: candidate,
        type: extended.type!,
      ),
    );
  }
}

CoverPlacement _coverPlacement({
  required List<HareegCard> extendedMeld,
  required HareegCard candidate,
  required MeldType type,
}) {
  if (type == MeldType.set) {
    return CoverPlacement.set;
  }

  final ordered = MeldCardOrdering.forCards(extendedMeld);
  final candidateIndex = ordered.indexWhere((card) => card.id == candidate.id);
  if (candidateIndex == 0) {
    return CoverPlacement.lowEnd;
  }
  return CoverPlacement.highEnd;
}
