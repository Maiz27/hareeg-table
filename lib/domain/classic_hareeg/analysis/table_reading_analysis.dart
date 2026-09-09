import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../rules/cover_rules.dart';
import '../rules/joker_rules.dart';
import '../rules/opening_rules.dart';
import 'partial_hand_groups.dart';

/// Observable table-reading signals computed from one seat's perspective.
///
/// Pure, and deliberately narrow: the constructor takes explicit values rather
/// than a live observation, so the same computation serves a CPU planner now
/// and a replay coach reconstructing a past position later.
///
/// The signature is also the architectural exclusion. There is no parameter for
/// opponent hands, hidden stock identities, historical pickups, or future
/// actions, so none of them can reach the arithmetic. That the *planners* also
/// cannot leak them is proven separately, at the seam where hidden state
/// actually exists.
class TableReadingAnalysis {
  /// Computes the signals for one perspective.
  TableReadingAnalysis({
    required List<HareegCard> perspectiveHand,
    required List<HareegCard> discardPile,
    required Map<PlayerSeat, List<PlacedMeld>> visibleMelds,
    required this.deckCopyCount,
    required int Function(HareegCard card, List<HareegCard> hand) soloValue,
  }) : _soloValue = soloValue,
       perspectiveHand = List.unmodifiable(perspectiveHand),
       discardPile = List.unmodifiable(discardPile),
       visibleMelds = Map.unmodifiable(visibleMelds) {
    if (deckCopyCount < 1) {
      // Rejected rather than tolerated: with a zero denominator every identity
      // would report dead, and a signal that says "everything is dead" is
      // indistinguishable from one that is switched off.
      throw ArgumentError.value(
        deckCopyCount,
        'deckCopyCount',
        'A deck must contain at least one copy of each identity.',
      );
    }
  }

  /// The seat's own hand.
  final List<HareegCard> perspectiveHand;

  /// The current discard pile, complete and ordered.
  final List<HareegCard> discardPile;

  /// Table melds by owning seat.
  final Map<PlayerSeat, List<PlacedMeld>> visibleMelds;

  /// Copies of each standard identity in the deck.
  final int deckCopyCount;

  /// Counts physical copies of [identity] that are accounted for.
  ///
  /// Exactly three places count, and they are all public or the seat's own:
  /// the perspective hand, the current discard pile, and visible table melds.
  ///
  /// **Physical standard cards only.** A joker sitting in a meld and
  /// representing this identity does not count, because the real card is still
  /// somewhere in play. That is the opposite of how a represented identity is
  /// treated for feed risk, where the meld's public *shape* is what matters.
  int accountedCopies(CardIdentity identity) {
    var seen = 0;
    for (final card in perspectiveHand) {
      if (_isPhysically(card, identity)) {
        seen += 1;
      }
    }
    for (final card in discardPile) {
      if (_isPhysically(card, identity)) {
        seen += 1;
      }
    }
    for (final melds in visibleMelds.values) {
      for (final meld in melds) {
        for (final card in meld.cards) {
          if (_isPhysically(card, identity)) {
            seen += 1;
          }
        }
      }
    }
    return seen;
  }

  /// Whether every copy of [identity] is accounted for.
  bool isDead(CardIdentity identity) =>
      accountedCopies(identity) >= deckCopyCount;

  /// The perspective hand's disjoint partial groups.
  ///
  /// Grouped over the leftovers of the hand's best complete-meld partition —
  /// the same set the keep-score model uses, derived in one shared place — so
  /// a card already sitting in a finished meld is never reported as part of a
  /// developing pair.
  late final List<PartialHandGroup> partialGroups = selectPartialGroups(
    cards: splitForPartialGroups(perspectiveHand).leftovers,
    hand: perspectiveHand,
    soloValue: _soloValue,
  );

  /// Identities that would complete a developing group into a legal meld.
  late final Set<CardIdentity> neededIdentities = {
    for (final group in partialGroups)
      if (group.isDeveloping) ...completionsFor(group),
  };

  /// Needed identities with no copies left in play.
  late final Set<CardIdentity> deadNeededIdentities = {
    for (final identity in neededIdentities)
      if (isDead(identity)) identity,
  };

  /// Whether every completion of [group] is dead.
  bool isGroupStarved(PartialHandGroup group) {
    if (!group.isDeveloping) {
      return false;
    }
    final completions = completionsFor(group);
    if (completions.isEmpty) {
      return false;
    }
    return completions.every(isDead);
  }

  final int Function(HareegCard, List<HareegCard>) _soloValue;

  static bool _isPhysically(HareegCard card, CardIdentity identity) {
    // `identity` is the physical face. `effectiveIdentity` would fold in a
    // joker's representation, which is exactly what must not count here.
    final physical = card.identity;
    return physical != null && physical == identity;
  }

  /// The one-card completions of a developing [group].
  ///
  /// A pair completes with its rank in the suits it does not already hold. A
  /// run at distance one completes at either end; a run with a gap completes
  /// only in the gap. Ace is handled at both ends: a Queen–King pair completes
  /// with Jack **or** Ace, and Ace–Two completes with Three.
  static Set<CardIdentity> completionsFor(PartialHandGroup group) {
    if (group.cards.length != 2) {
      return const {};
    }
    final a = group.cards[0].identity;
    final b = group.cards[1].identity;
    if (a == null || b == null) {
      return const {};
    }

    if (group.kind == PartialGroupKind.pair) {
      return {
        for (final suit in CardSuit.values)
          if (suit != a.suit && suit != b.suit)
            CardIdentity(rank: a.rank, suit: suit),
      };
    }

    final suit = a.suit;
    final low = a.rank.order <= b.rank.order ? a.rank : b.rank;
    final high = a.rank.order <= b.rank.order ? b.rank : a.rank;
    final distance = high.order - low.order;

    if (distance == 2) {
      final gap = _rankAtOrder(low.order + 1);
      return gap == null ? const {} : {CardIdentity(rank: gap, suit: suit)};
    }

    if (distance != 1) {
      return const {};
    }

    final completions = <CardIdentity>{};
    final below = _rankAtOrder(low.order - 1);
    if (below != null) {
      completions.add(CardIdentity(rank: below, suit: suit));
    }
    final above = _rankAtOrder(high.order + 1);
    if (above != null) {
      completions.add(CardIdentity(rank: above, suit: suit));
    }
    // High-ace seam: the validator accepts Q-K-A, but Ace sorts at order 1, so
    // walking the low ordering alone would silently drop it from a Queen-King
    // partial.
    if (high == CardRank.king) {
      completions.add(CardIdentity(rank: CardRank.ace, suit: suit));
    }
    return completions;
  }

  static CardRank? _rankAtOrder(int order) {
    for (final rank in CardRank.values) {
      if (rank.order == order) {
        return rank;
      }
    }
    return null;
  }
}

/// Why a candidate discard would help the next seat.
enum FeedEvidenceKind {
  /// The target recently took a related card from the discard pile.
  recentPickup,

  /// The candidate would legally cover one of the target's visible melds.
  coverExtension,

  /// The candidate would replace a joker in a target meld and free it.
  jokerReplacement,
}

/// The risk of handing [candidate] to the next active seat.
class FeedRiskAssessment {
  /// Creates an assessment.
  FeedRiskAssessment({
    required this.candidate,
    required this.target,
    required Set<FeedEvidenceKind> evidence,
  }) : evidence = Set.unmodifiable(evidence);

  /// A silent assessment, used when there is no target at all.
  FeedRiskAssessment.noTarget(this.candidate)
    : target = null,
      evidence = const {};

  /// The card under consideration.
  final HareegCard candidate;

  /// The seat that would receive it, or null when nobody would.
  final PlayerSeat? target;

  /// Which evidence classes fired. Carried rather than collapsed to a bool so
  /// the later coach can cite the reason instead of asserting a verdict.
  final Set<FeedEvidenceKind> evidence;

  /// Whether any evidence fired.
  bool get isRisky => evidence.isNotEmpty;
}

/// Computes feed risk from public evidence only.
///
/// Every input is something any seat at the table can see: the target's visible
/// melds and the pickups it took from the discard pile. Hidden hands never
/// participate, which is why the parameter list has no room for one.
abstract final class FeedRiskAnalysis {
  /// The first active seat anti-clockwise of [from], or null when there is
  /// none.
  ///
  /// A seat is never its own target: with nobody else active there is no seat
  /// to feed, so the signal stays silent rather than pointing home.
  static PlayerSeat? nextActiveSeat({
    required PlayerSeat from,
    required List<PlayerSeat> activeSeats,
  }) {
    var cursor = from.nextAntiClockwise;
    while (cursor != from) {
      if (activeSeats.contains(cursor)) {
        return cursor;
      }
      cursor = cursor.nextAntiClockwise;
    }
    return null;
  }

  /// Assesses [candidate] against what the target seat is publicly collecting.
  ///
  /// [recentPickups] must already be truncated to the observing tier's memory
  /// depth — aging is an attention rule, and it applies to pickups only.
  /// [targetMelds] is current table state and is never aged out.
  static FeedRiskAssessment assess({
    required HareegCard candidate,
    required PlayerSeat perspective,
    required List<PlayerSeat> activeSeats,
    required List<HareegCard> recentPickups,
    required List<PlacedMeld> targetMelds,
    required bool targetHasOpened,
  }) {
    final target = nextActiveSeat(from: perspective, activeSeats: activeSeats);
    if (target == null) {
      return FeedRiskAssessment.noTarget(candidate);
    }

    final evidence = <FeedEvidenceKind>{};
    final identity = candidate.identity;

    if (identity != null && _pickupRelated(identity, recentPickups)) {
      evidence.add(FeedEvidenceKind.recentPickup);
    }

    // Visible-meld evidence is decided by the real rules rather than a
    // re-implemented adjacency guess. A natural four-card set cannot accept
    // another card and a duplicate suit cannot extend a three-card set, so
    // "the target has a set of this rank" would fire on positions where the
    // card is worthless to them.
    final meldCards = [for (final meld in targetMelds) meld.cards];
    if (ClassicHareegCoverRules.isAnyCover(
      tableMelds: meldCards,
      candidate: candidate,
    )) {
      evidence.add(FeedEvidenceKind.coverExtension);
    }

    for (final cards in meldCards) {
      if (ClassicHareegJokerRules.canReplaceJoker(
        playerOpened: targetHasOpened,
        tableCards: cards,
        replacementCard: candidate,
      )) {
        evidence.add(FeedEvidenceKind.jokerReplacement);
        break;
      }
    }

    return FeedRiskAssessment(
      candidate: candidate,
      target: target,
      evidence: evidence,
    );
  }

  /// Whether [identity] plausibly serves a seat that took one of [pickups].
  ///
  /// Same rank feeds a set. Same suit within two ranks feeds a run, measured
  /// along a *legal* sequence: the low-Ace ordering, plus the high-Ace seam so
  /// a King or Queen pickup relates to an Ace. Ranks never wrap — King and Two
  /// are not neighbours.
  static bool _pickupRelated(CardIdentity identity, List<HareegCard> pickups) {
    for (final pickup in pickups) {
      final taken = pickup.identity;
      if (taken == null) {
        continue;
      }
      if (taken.rank == identity.rank) {
        return true;
      }
      if (taken.suit != identity.suit) {
        continue;
      }
      if (_sequenceDistance(taken.rank, identity.rank) <= 2) {
        return true;
      }
    }
    return false;
  }

  /// Distance along a legal sequence, or a large number when there is none.
  static int _sequenceDistance(CardRank a, CardRank b) {
    final low = (a.order - b.order).abs();
    // High-ace seam: Ace also sits above King, so an Ace is one from a King
    // and two from a Queen. Everything else keeps the low ordering.
    if (a == CardRank.ace || b == CardRank.ace) {
      final other = a == CardRank.ace ? b : a;
      final high = (14 - other.order).abs();
      return low < high ? low : high;
    }
    return low;
  }
}
