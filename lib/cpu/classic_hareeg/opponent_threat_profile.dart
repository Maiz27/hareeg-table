part of 'expert_cpu_move_planner.dart';

/// Why an [OpponentThreat] fired.
enum OpponentThreatKind {
  /// The card slots directly onto the opponent's visible run on the table.
  runEnd,

  /// The opponent has been deliberately picking up matching cards from the
  /// discard pile (rank match, or same suit at adjacent rank).
  collecting,
}

/// One attributed discard threat: which opponent a card would help, and why.
/// Surfaced to the coaching advisor so it can narrate the exact signal the
/// Expert discard comparator weighs.
class OpponentThreat {
  /// Creates an attributed threat.
  const OpponentThreat({
    required this.opponent,
    required this.kind,
    this.rank,
    this.suit,
  });

  /// The opponent the card would help.
  final PlayerSeat opponent;

  /// Why the card is dangerous.
  final OpponentThreatKind kind;

  /// For [OpponentThreatKind.collecting] rank matches: the collected rank.
  final CardRank? rank;

  /// For [OpponentThreatKind.collecting] suit-adjacent matches: the suit.
  final CardSuit? suit;
}

/// Opponent-aware discard threat model shared by the Expert planner's discard
/// comparator and the coaching advisor (CPU-first: the coach narrates the same
/// signals the brain plays).
///
/// "Collecting" = what an opponent deliberately PICKED UP. A card they
/// DISCARDED is one they did not want, so it is safe (often safest) to throw —
/// counting discards here inverts the signal (the playtest "discard the 8,
/// keep the dead 3s" bug). The pickup tell is additionally:
/// - RECENT: only the last [_pickupWindow] pickups count; turn-2 tells must
///   not still steer turn 40.
/// - UNCONSUMED: a pickup whose identity has since appeared in that opponent's
///   table melds is spent — the card is visibly out of their hand.
/// - FROM A SEAT STILL BUILDING: an opened opponent down to fewer than
///   [_collectingHandFloor] cards has stopped collecting from the pile; its
///   stale tells are dropped (run-end fits from its table melds still count).
/// - NARROW ON SUIT: a same-suit pickup only marks ranks within
///   [_runDistance] (a plausible run neighbour). One clubs pickup must not
///   poison every club in the hand — the playtest "collecting fixation" bug.
class OpponentThreatProfile {
  const OpponentThreatProfile._(this._tells);

  static const _pickupWindow = 6;
  static const _collectingHandFloor = 4;
  static const _runDistance = 2;

  final List<_OpponentTells> _tells;

  /// Builds the profile from visible state and attributed pile history.
  factory OpponentThreatProfile.fromObservation(CpuObservation observation) {
    final tells = <_OpponentTells>[];
    for (final opponent in observation.opponents) {
      final score = observation.scoreFor(opponent);

      final runEnds = <String>{};
      // PHYSICAL card ids, not identity keys: with multi-deck twins the
      // opponent can meld one copy while still collecting around the other —
      // an identity match dropped that live tell. A pickup is consumed only
      // when the exact picked-up card is now visible on the table.
      final meldedCardIds = <String>{};
      for (final meld in observation.tableMeldsFor(opponent)) {
        for (final identity in _runEndCoverThreats(meld)) {
          runEnds.add(identity.key);
        }
        for (final card in meld.cards) {
          meldedCardIds.add(card.id);
        }
      }

      final pickups = <CardIdentity>[];
      final stoppedCollecting =
          observation.hasOpened(opponent) &&
          observation.handCountFor(opponent) < _collectingHandFloor;
      if (!stoppedCollecting) {
        for (final card in observation.discardHistory.lastPickupsBy(
          opponent,
          _pickupWindow,
        )) {
          final identity = card.effectiveIdentity;
          if (identity == null || meldedCardIds.contains(card.id)) {
            continue;
          }
          pickups.add(identity);
        }
      }

      if (pickups.isEmpty && runEnds.isEmpty && score == 0) {
        continue;
      }
      tells.add(
        _OpponentTells(
          opponent: opponent,
          nearScore: score >= ExpertCpuMovePlanner.highRiskScoreFloor,
          eliminationTarget:
              score >= ExpertCpuMovePlanner.eliminationTargetScoreFloor,
          pickups: pickups,
          runEndIdentities: runEnds,
        ),
      );
    }
    return OpponentThreatProfile._(tells);
  }

  /// Relative danger of discarding [card]: how much it would help any
  /// opponent. Weights preserve the established ladder — run-end fit (120) >
  /// near-score identity/rank/suit (90/45/20) > plain identity/rank/suit
  /// (35/15/5) — applied to the refined tells.
  int dangerScore(HareegCard card) {
    final identity = card.effectiveIdentity;
    if (identity == null) {
      return 40;
    }
    var runEnd = false;
    var nearIdentity = false, nearRank = false, nearSuit = false;
    var hotIdentity = false, hotRank = false, hotSuit = false;
    for (final tell in _tells) {
      if (tell.runEndIdentities.contains(identity.key)) {
        runEnd = true;
      }
      if (tell.matchesIdentity(identity)) {
        hotIdentity = true;
        nearIdentity = nearIdentity || tell.nearScore;
      }
      if (tell.matchesRank(identity)) {
        hotRank = true;
        nearRank = nearRank || tell.nearScore;
      }
      if (tell.matchesSuitAdjacent(identity)) {
        hotSuit = true;
        nearSuit = nearSuit || tell.nearScore;
      }
    }
    var score = 0;
    if (runEnd) {
      score += 120;
    }
    if (nearIdentity) {
      score += 90;
    }
    if (nearRank) {
      score += 45;
    }
    if (nearSuit) {
      score += 20;
    }
    if (hotIdentity) {
      score += 35;
    }
    if (hotRank) {
      score += 15;
    }
    if (hotSuit) {
      score += 5;
    }
    return score;
  }

  /// How dangerous it is to FEED [card] to a high-score opponent that is
  /// collecting its identity — a defensive avoid-feeding tie-break, NOT an
  /// offensive Fifty setup. (A Fifty's +3 lands only on [fiftyPunishTarget],
  /// so this any-opponent scan cannot encode Fifty-setup intent.) The discard
  /// comparator sheds the LOWER-scoring card, so a card a near-score /
  /// elimination opponent is collecting scores higher and is KEPT, denying
  /// that seat the pickup. Weighted hardest against an elimination target.
  int avoidFeedingScore(HareegCard card) {
    final identity = card.effectiveIdentity;
    if (identity == null) {
      return 0;
    }
    var best = 0;
    for (final tell in _tells) {
      if (!tell.matchesIdentity(identity)) {
        continue;
      }
      final score = tell.eliminationTarget ? 3 : (tell.nearScore ? 2 : 1);
      if (score > best) {
        best = score;
      }
    }
    return best;
  }

  /// The strongest attributed threat against discarding [card], or null when
  /// none. A visible run-end fit outranks a collecting tell — it is the
  /// concrete, on-the-table danger. Used by the coaching advisor to explain a
  /// hold-back warning ("it slots onto East's run" / "East is collecting").
  OpponentThreat? primaryThreatFor(HareegCard card) {
    final identity = card.effectiveIdentity;
    if (card.isJoker || identity == null) {
      return null;
    }
    // Tier order is deliberate and matches dangerScore (run-end's flat 120 tops
    // every collecting weight): a concrete run-end fit outranks a soft
    // collecting tell. Within a tier, attribute to the MOST DANGEROUS opponent
    // (elimination > near-score > plain) instead of the first in seat order —
    // when two seats both match, the coach must name the one that matters.
    final runEndTell = _mostDangerousTell(
      (tell) => tell.runEndIdentities.contains(identity.key),
    );
    if (runEndTell != null) {
      return OpponentThreat(
        opponent: runEndTell.opponent,
        kind: OpponentThreatKind.runEnd,
      );
    }
    final rankTell = _mostDangerousTell((tell) => tell.matchesRank(identity));
    if (rankTell != null) {
      return OpponentThreat(
        opponent: rankTell.opponent,
        kind: OpponentThreatKind.collecting,
        rank: identity.rank,
      );
    }
    final suitTell = _mostDangerousTell(
      (tell) => tell.matchesSuitAdjacent(identity),
    );
    if (suitTell != null) {
      return OpponentThreat(
        opponent: suitTell.opponent,
        kind: OpponentThreatKind.collecting,
        suit: identity.suit,
      );
    }
    return null;
  }

  /// The most dangerous tell satisfying [matches] (elimination > near-score >
  /// plain), or null when none match. Ties keep the first in the stable
  /// anti-clockwise seat order [_tells] is built in.
  _OpponentTells? _mostDangerousTell(bool Function(_OpponentTells) matches) {
    _OpponentTells? best;
    var bestWeight = -1;
    for (final tell in _tells) {
      if (!matches(tell)) {
        continue;
      }
      final weight = tell.eliminationTarget ? 2 : (tell.nearScore ? 1 : 0);
      if (weight > bestWeight) {
        bestWeight = weight;
        best = tell;
      }
    }
    return best;
  }

  static List<CardIdentity> _runEndCoverThreats(PlacedMeld meld) {
    // [_sequenceOrders] is high-ace aware (it reads Q-K-A as 12-13-14), so
    // ace-high table runs produce their run-end threats too — raw rank
    // orders read only ace-low and silently dropped them (no J threat below
    // Q-K-A, no A threat above 10-J-Q-K).
    final orders = _sequenceOrders(meld);
    if (orders == null) {
      return const [];
    }
    final suit = meld.cards.first.effectiveIdentity?.suit;
    if (suit == null) {
      return const [];
    }

    final threats = <CardIdentity>[];
    final lower = _rankByOrder(orders.first - 1);
    if (lower != null) {
      threats.add(CardIdentity(rank: lower, suit: suit));
    }
    final upper = _rankByOrder(orders.last + 1);
    if (upper != null) {
      threats.add(CardIdentity(rank: upper, suit: suit));
    }
    return threats;
  }

  static CardRank? _rankByOrder(int order) {
    // 14 is the high-ace order [_sequenceOrders] emits; no [CardRank.order]
    // carries it, so map it back to the ace explicitly (an ace tops a
    // 10-J-Q-K run as a legal cover).
    if (order == 14) {
      return CardRank.ace;
    }
    for (final rank in CardRank.values) {
      if (rank.order == order) {
        return rank;
      }
    }
    return null;
  }
}

/// One opponent's refined tells: filtered pile pickups, run-end fits from its
/// visible melds, and its score posture.
class _OpponentTells {
  const _OpponentTells({
    required this.opponent,
    required this.nearScore,
    required this.eliminationTarget,
    required this.pickups,
    required this.runEndIdentities,
  });

  final PlayerSeat opponent;
  final bool nearScore;
  final bool eliminationTarget;
  final List<CardIdentity> pickups;
  final Set<String> runEndIdentities;

  bool matchesIdentity(CardIdentity identity) {
    return pickups.any((pickup) => pickup.key == identity.key);
  }

  bool matchesRank(CardIdentity identity) {
    return pickups.any((pickup) => pickup.rank == identity.rank);
  }

  bool matchesSuitAdjacent(CardIdentity identity) {
    // Strictly adjacent: zero distance is the SAME identity, which the
    // identity/rank tells already score — letting it through here double
    // counted an exact-match pickup into the suit signal too.
    return pickups.any((pickup) {
      if (pickup.suit != identity.suit) {
        return false;
      }
      // Dual ace reading: an ace reads order 1 (low) OR 14 (high), so a pickup
      // or candidate ace must test BOTH so a K/Q neighbour of an ace-HIGH run
      // (A-K-Q) gets adjacency heat — raw orders read ace as 1 and flagged 2/3
      // instead. Adjacent under EITHER reading is adjacent; the zero-distance
      // guard still excludes the same identity (an ace-vs-ace pickup is
      // distance 0 under both readings and stays out).
      return _suitAdjacent(pickup.rank, identity.rank);
    });
  }

  static bool _suitAdjacent(CardRank pickupRank, CardRank identityRank) {
    final pickupOrders = _aceReadings(pickupRank);
    final identityOrders = _aceReadings(identityRank);
    for (final pickupOrder in pickupOrders) {
      for (final identityOrder in identityOrders) {
        final distance = (pickupOrder - identityOrder).abs();
        if (distance > 0 && distance <= OpponentThreatProfile._runDistance) {
          return true;
        }
      }
    }
    return false;
  }

  static List<int> _aceReadings(CardRank rank) {
    return rank == CardRank.ace ? const [1, 14] : [rank.order];
  }
}
