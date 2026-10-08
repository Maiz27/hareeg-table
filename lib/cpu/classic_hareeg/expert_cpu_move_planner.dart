import '../../domain/classic_hareeg/models/player_seat.dart';
import '../../domain/classic_hareeg/models/playing_card.dart';
import '../../domain/classic_hareeg/rules/opening_rules.dart';
import 'cpu_move_plan.dart';
import 'cpu_move_plan_pipeline.dart';
import 'cpu_observation.dart';
import 'cpu_table_reading.dart';
import 'skilled_cpu_move_planner.dart';

part 'opponent_threat_profile.dart';

/// Why Expert holds a legal cover in hand instead of playing it.
///
/// Returned by [ExpertCpuMovePlanner.coverHoldReasonFor] so the coaching
/// advisor can narrate the brain's hold instead of staying silent about a
/// visibly coverable card.
enum CoverHoldReason {
  /// The cover card is a joker: never burn the strongest finish/Fifty asset
  /// on a non-finishing cover.
  jokerGuard,

  /// Endgame Fifty-hold posture: few cards, deep stock, and the remaining
  /// hand still develops toward a meld — shedding into covers throws the
  /// Fifty away.
  fiftyDevelopment,

  /// The card extends the seat's OWN table run at an end: keep developing the
  /// run rather than burning the card early.
  ownRunExtension,
}

/// Expert CPU planner with offensive Fifty posture and opponent-aware defence.
///
/// This tier is a thin adapter — every stage of `plan()` runs in
/// [CpuMovePlanPipeline]; this class only supplies the per-stage scoring weights
/// for Expert's posture (opening-band push, interior-joker preference,
/// opponent-threat discard model, finish-gated joker replacement).
class ExpertCpuMovePlanner implements CpuMovePlanner {
  /// Creates an expert CPU move planner.
  const ExpertCpuMovePlanner();

  static const _partitionLimit = 256;
  static const _fiftyHoldStockFloor = 8;
  static const _fiftyHoldHandValueFloor = 25;

  /// Stock size at or below which Expert switches to its endgame posture
  /// (shed pips into the table, deny pickups). Public so the coaching advisor
  /// can teach the same stage shift it plays.
  static const thinStockCount = 8;

  /// Score at or above which a seat is "near" elimination and Expert tightens
  /// its play. Public for the coaching advisor's score-posture teaching.
  static const highRiskScoreFloor = 25;

  /// Score at or above which an opponent becomes an elimination target.
  /// Public for the coaching advisor's score-posture teaching.
  static const eliminationTargetScoreFloor = 28;

  /// Whether Expert would HOLD a normal finish to chase a Fifty instead:
  /// a finishing partition exists, the stock is deep enough to keep drawing,
  /// the hand is heavy enough to pay for the gamble, and the Fifty has a
  /// worthwhile payoff. Public so the coaching advisor can narrate the same
  /// posture the brain plays instead of contradicting it with a bare "you can
  /// finish" hint.
  ///
  /// Payoff check: a Fifty's +3 can only land on the seat whose discard the
  /// claimant takes — the active seat immediately BEFORE it in turn order
  /// ([fiftyPunishTarget]). A high score elsewhere at the table is
  /// unreachable, so it does not justify the gamble: the hold pays when the
  /// claimant itself is at high risk (the −3 buys real breathing room) or the
  /// punishable seat is (the +3 may eliminate them).
  static bool holdsNormalFinishForFifty(CpuObservation observation) {
    if (observation.finishingPartition() == null ||
        observation.stockCount < _fiftyHoldStockFloor ||
        handPipValue(observation.ownHand) <= _fiftyHoldHandValueFloor) {
      return false;
    }

    if (observation.ownScore >= highRiskScoreFloor) {
      return true;
    }
    final target = fiftyPunishTarget(observation);
    return target != null && observation.scoreFor(target) >= highRiskScoreFloor;
  }

  /// The only seat a Fifty claimed by [observation]'s seat can punish: the
  /// active seat immediately before it in turn order, whose discard the claim
  /// would take. Null in the degenerate no-opponents state.
  static PlayerSeat? fiftyPunishTarget(CpuObservation observation) {
    final opponents = observation.opponents;
    return opponents.isEmpty ? null : opponents.last;
  }

  /// Why Expert would HOLD [cover] in hand instead of playing it, or null when
  /// it plays the cover. Public so the coaching advisor narrates the same hold
  /// the brain plays (the policy's boolean hook delegates to the same check).
  static CoverHoldReason? coverHoldReasonFor(
    CpuObservation observation,
    CpuLegalAction cover,
  ) {
    return const _ExpertCpuPlanPolicy().coverHoldReasonFor(observation, cover);
  }

  // Endgame Fifty-hold cover posture: an opened seat with at most this many
  // cards is close enough to a finish that shedding a developing card into a
  // cover throws away its Fifty chances. (Owner's "few cards" ~ <= 4-5.)
  static const _fiftyHoldCoverHandMax = 5;
  static const _freshStockCount = 30;
  static const _benchmarkTarget = 75;
  static const _benchmarkFloor = 70;
  static const _benchmarkCeiling = 80;

  @override
  ClassicHareegCpuMovePlan plan(CpuObservation observation) {
    // Expert uses a larger partition fan-out cap than the pipeline default.
    return const CpuMovePlanPipeline(
      _ExpertCpuPlanPolicy(),
      partitionLimit: _partitionLimit,
    ).plan(observation);
  }
}

class _ExpertCpuPlanPolicy implements CpuPlanPolicy {
  const _ExpertCpuPlanPolicy();

  @override
  bool shouldClaimFifty(CpuObservation observation) {
    return shouldAttemptFiftyClaimFor(observation);
  }

  @override
  int comparePartitions(
    CpuObservation observation,
    MeldPartition left,
    MeldPartition right,
  ) {
    if (!observation.ownHasOpened()) {
      return _compareOpeningPartitions(observation, left, right);
    }

    final leftFinishes = left.cardsRemaining.length == 1;
    final rightFinishes = right.cardsRemaining.length == 1;
    final finishCompare = boolDesc(leftFinishes, rightFinishes);
    if (finishCompare != 0) {
      return finishCompare;
    }

    if (observation.stockCount <= ExpertCpuMovePlanner.thinStockCount) {
      final remainingCompare = _remainingPips(
        left,
      ).compareTo(_remainingPips(right));
      if (remainingCompare != 0) {
        return remainingCompare;
      }
    }

    final surfaceCompare = right.meldCount.compareTo(left.meldCount);
    if (surfaceCompare != 0) {
      return surfaceCompare;
    }

    final interiorCompare = _interiorJokerScore(
      right,
    ).compareTo(_interiorJokerScore(left));
    if (interiorCompare != 0) {
      return interiorCompare;
    }

    final jokerCompare = left.jokerCount.compareTo(right.jokerCount);
    if (jokerCompare != 0) {
      return jokerCompare;
    }

    final pipCompare = _remainingPips(left).compareTo(_remainingPips(right));
    if (pipCompare != 0) {
      return pipCompare;
    }

    final valueCompare = right.totalValue.compareTo(left.totalValue);
    if (valueCompare != 0) {
      return valueCompare;
    }

    return _partitionKey(left).compareTo(_partitionKey(right));
  }

  @override
  List<HareegCard> selectMeldCards(
    CpuObservation observation,
    MeldPartition partition,
  ) {
    return CpuMovePlanPipeline.cardsInHandOrder(
      observation,
      partition.cardsUsed,
    );
  }

  @override
  bool shouldTakeDiscard(CpuObservation observation) {
    // Call the shared predicate directly instead of recursing through
    // Skilled's full plan — that path re-enumerates partitions and rebuilds
    // threat profiles just to read this boolean.
    if (shouldTakeDiscardForObservationCore(observation)) {
      return true;
    }
    // Defensive thin-stock pickup only makes sense if the seat has already
    // opened (or the pickup itself can satisfy opening). Picking up an
    // unusable discard pre-opening forces the rules engine to return it,
    // and the next draw choice will face the same discard top → loop.
    if (observation.stockCount > ExpertCpuMovePlanner.thinStockCount ||
        observation.topDiscard == null) {
      return false;
    }
    // The taken card still has to be played this turn: denying it to the
    // next seat is only worth it when it can go straight onto a table meld.
    // An unplayable pickup is handed back and the seat draws anyway.
    return canCoverWithTakenDiscard(observation);
  }

  @override
  bool shouldHoldNormalFinishForFifty(CpuObservation observation) {
    return ExpertCpuMovePlanner.holdsNormalFinishForFifty(observation);
  }

  @override
  bool gateJokerReplacement(CpuObservation observation) {
    // Eager: a valid swap is a free upgrade — the natural card moves onto the
    // table in the joker's spot, the freed joker (the strongest finish/Fifty
    // asset) comes to hand, scoring is card-COUNT so holding it costs
    // nothing, and with multi-deck twins any opponent holding the other copy
    // can steal the swap first. The old "delay until a finish is visible"
    // posture lost the swap whenever the natural card got consumed by a meld
    // or discard in the meantime (playtest: three natural 8s were melded,
    // burning the 8♣ that could have reclaimed a table joker).
    return true;
  }

  @override
  bool shouldHoldCover(CpuObservation observation, CpuLegalAction cover) {
    return coverHoldReasonFor(observation, cover) != null;
  }

  /// Why Expert would hold [cover] in hand instead of playing it, or null when
  /// the cover should be played. The boolean policy hook ([shouldHoldCover])
  /// delegates here; the coaching advisor reads the reason so it can NARRATE
  /// the hold the brain plays ("the drawn card fits that meld, but hold it
  /// because…") instead of going silent about a visibly coverable card.
  CoverHoldReason? coverHoldReasonFor(
    CpuObservation observation,
    CpuLegalAction cover,
  ) {
    final cardIds = cover.descriptor.cardIds;
    if (cardIds.length != 1) {
      // Multi-card covers are not reasoned about here; preserve the prior
      // behaviour of always playing them.
      return null;
    }
    final card = handCardById(observation.ownHand, cardIds.single);
    if (card == null) {
      return null;
    }

    // A cover that empties the hand wins the round outright — never hold a
    // finish, for a Fifty or anything else.
    if (observation.ownHand.length == cardIds.length) {
      return null;
    }

    // Never burn a joker on a non-finishing cover. A held joker is the single
    // strongest finish/Fifty asset (it fits almost any incomplete meld later),
    // so playing it onto a cover is almost always a mistake — the playtest
    // "joker pushed onto a cover" bug.
    if (card.isJoker) {
      return CoverHoldReason.jokerGuard;
    }

    // Endgame Fifty-hold posture (opened seats only). Hold a non-finishing
    // cover when the seat is down to a few cards, the stock is not near-empty
    // (deep stock only HELPS — more draws means more Fifty chances, so there is
    // no upper stock bound), and the remaining hand is still developing toward a
    // meld (or holds a joker). In that shape, shedding cards into covers throws
    // the Fifty away instead of building it.
    if (observation.ownHasOpened() &&
        observation.ownHand.length <=
            ExpertCpuMovePlanner._fiftyHoldCoverHandMax &&
        observation.stockCount >= ExpertCpuMovePlanner._fiftyHoldStockFloor &&
        _remainingHandDevelops(observation.ownHand, card.id)) {
      return CoverHoldReason.fiftyDevelopment;
    }

    // Existing posture: hold a cover that extends the seat's OWN run at an end,
    // to keep developing the run rather than burning the card early.
    final target = cover.descriptor.coverTarget;
    if (target == null || target.targetSeat != observation.seat) {
      return null;
    }
    final identity = card.effectiveIdentity;
    if (identity == null) {
      return null;
    }
    final ownMelds = observation.tableMeldsFor(observation.seat);
    if (target.meldIndex < 0 || target.meldIndex >= ownMelds.length) {
      return null;
    }
    final orders = _sequenceOrders(ownMelds[target.meldIndex]);
    if (orders == null) {
      return null;
    }
    // An ace covers EITHER end: it extends below a low-ace run (order 1, under
    // [orders.first]) or tops a King-high run (order 14, above orders.last ==
    // 13). [_sequenceOrders] reads the EXISTING run shape, so a King-high run
    // carries no order-14 yet; promote the ace cover to its high reading when
    // it sits above the King. Other ranks keep their single reading.
    final order = _rankOrder(identity.rank, highAce: orders.last == 13);
    return order == orders.first - 1 || order == orders.last + 1
        ? CoverHoldReason.ownRunExtension
        : null;
  }

  // True when the hand minus [excludeCardId] still has a developing meld — two
  // cards that can combine into a set or run (via the shared
  // [cardsCanMeldTogether] signal), or a joker. Used by the Fifty-hold cover
  // posture to decide whether holding builds toward a finish.
  bool _remainingHandDevelops(List<HareegCard> hand, String excludeCardId) {
    final rest = [
      for (final card in hand)
        if (card.id != excludeCardId) card,
    ];
    for (final card in rest) {
      if (card.isJoker) {
        return true;
      }
    }
    for (var i = 0; i < rest.length; i += 1) {
      final a = rest[i].effectiveIdentity;
      if (a == null) {
        continue;
      }
      for (var j = i + 1; j < rest.length; j += 1) {
        final b = rest[j].effectiveIdentity;
        if (b == null) {
          continue;
        }
        if (cardsCanMeldTogether(a, b)) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  Comparator<CpuDiscardCandidate> discardComparator(
    CpuObservation observation,
  ) {
    final profile = OpponentThreatProfile.fromObservation(observation);
    final holdForFifty = shouldHoldNormalFinishForFifty(observation);
    // The shared table reading is a second, sharper defensive lens, not a
    // replacement for the profile above. The profile scans every opponent for
    // soft tells; the reading answers one exact question about the one seat
    // that actually receives this card next, decided by the real cover and
    // joker-replacement rules. Both run, and the profile's weights are
    // untouched.
    final reading = CpuTableReading.forObservation(observation);
    final hand = observation.ownHand;
    // Keep scores come from the shared disjoint best-grouping model
    // ([handKeepScores]): every card is scored by the value of the single meld /
    // group it lands in. A card committed to a meld scores that meld's value (so
    // it cannot inflate a loose neighbour — an A♥ locked in the aces set is not
    // borrowed as a heart-run partner for a loose 2♥/3♥), and a redundant
    // duplicate falls to a 0 solo. Because the grouping is disjoint this holds
    // for opened and unopened hands alike, replacing the old unopened-only
    // keep-partition exclusion with one root model.
    final keepScores = handKeepScores(hand);
    int keepScore(HareegCard card) => keepScores[card.id] ?? 0;

    return (left, right) {
      final leftCard = left.card;
      final rightCard = right.card;
      final leftDanger = profile.dangerScore(leftCard);
      final rightDanger = profile.dangerScore(rightCard);
      final dangerCompare = leftDanger.compareTo(rightDanger);
      if (dangerCompare != 0) {
        return dangerCompare;
      }

      // Next-seat feed risk: among cards the all-opponent profile rates the
      // same, keep the one the seat about to play would actually be handed a
      // gift by. This is the signal Skilled does not get.
      final feedCompare = boolAsc(
        reading.isFeedRisk(leftCard),
        reading.isFeedRisk(rightCard),
      );
      if (feedCompare != 0) {
        return feedCompare;
      }

      // Material signal: a group that can never complete is not worth the
      // keep score its shape earns it, so it is checked before that score.
      final starvedCompare = boolDesc(
        reading.isStarved(leftCard),
        reading.isStarved(rightCard),
      );
      if (starvedCompare != 0) {
        return starvedCompare;
      }

      // Potential-weighted: among equally (un)dangerous cards, shed the one
      // building the least. Keeps a developing high pair over a low complete
      // set and protects run/set anchors, instead of blindly dumping low pips.
      final keepCompare = keepScore(leftCard).compareTo(keepScore(rightCard));
      if (keepCompare != 0) {
        return keepCompare;
      }

      final leftTarget = profile.avoidFeedingScore(leftCard);
      final rightTarget = profile.avoidFeedingScore(rightCard);
      final targetCompare = leftTarget.compareTo(rightTarget);
      if (targetCompare != 0) {
        return targetCompare;
      }

      final leftValue = cardPipValue(leftCard);
      final rightValue = cardPipValue(rightCard);
      return holdForFifty
          ? rightValue.compareTo(leftValue)
          : leftValue.compareTo(rightValue);
    };
  }

  @override
  bool allowAnyLegalMeldFallback(CpuObservation observation) => false;

  @override
  ClassicHareegCpuMovePlan fallback(CpuObservation observation) {
    return const SkilledCpuMovePlanner().plan(observation);
  }

  int _compareOpeningPartitions(
    CpuObservation observation,
    MeldPartition left,
    MeldPartition right,
  ) {
    if (observation.benchmarkOwner == null &&
        observation.stockCount >= ExpertCpuMovePlanner._freshStockCount) {
      final leftBand = _benchmarkBandScore(left.totalValue);
      final rightBand = _benchmarkBandScore(right.totalValue);
      final bandCompare = rightBand.compareTo(leftBand);
      if (bandCompare != 0) {
        return bandCompare;
      }

      final targetCompare =
          (left.totalValue - ExpertCpuMovePlanner._benchmarkTarget)
              .abs()
              .compareTo(
                (right.totalValue - ExpertCpuMovePlanner._benchmarkTarget)
                    .abs(),
              );
      if (targetCompare != 0) {
        return targetCompare;
      }

      final valueCompare = right.totalValue.compareTo(left.totalValue);
      if (valueCompare != 0) {
        return valueCompare;
      }
    }

    final requirement = observation.currentOpeningRequirement;
    final overCompare = (left.totalValue - requirement).compareTo(
      right.totalValue - requirement,
    );
    if (overCompare != 0) {
      return overCompare;
    }
    return _partitionKey(left).compareTo(_partitionKey(right));
  }

  int _benchmarkBandScore(int value) {
    if (value >= ExpertCpuMovePlanner._benchmarkFloor &&
        value <= ExpertCpuMovePlanner._benchmarkCeiling) {
      return 2;
    }
    if (value > ExpertCpuMovePlanner._benchmarkCeiling) {
      return 1;
    }
    return 0;
  }

  int _interiorJokerScore(MeldPartition partition) {
    var score = 0;
    for (final meld in partition.melds) {
      final orders = _sequenceOrders(meld);
      if (orders == null || orders.length < 3) {
        continue;
      }
      final minOrder = orders.reduce(
        (left, right) => left < right ? left : right,
      );
      final maxOrder = orders.reduce(
        (left, right) => left > right ? left : right,
      );
      for (final card in meld.cards) {
        if (!card.isJoker) {
          continue;
        }
        final identity = card.effectiveIdentity;
        if (identity == null) {
          continue;
        }
        final order = _rankOrder(identity.rank, highAce: maxOrder == 14);
        if (order > minOrder && order < maxOrder) {
          score += 1;
        }
      }
    }
    return score;
  }

  int _remainingPips(MeldPartition partition) {
    return handPipValue(partition.cardsRemaining);
  }

  String _partitionKey(MeldPartition partition) {
    final meldKeys =
        partition.melds
            .map(
              (meld) => meld.cards
                  .map(
                    (card) => '${card.id}:${card.effectiveIdentity?.key ?? ''}',
                  )
                  .join(','),
            )
            .toList()
          ..sort();
    return meldKeys.join('/');
  }
}

List<int>? _sequenceOrders(PlacedMeld meld) {
  final identities = meld.cards
      .map((card) => card.effectiveIdentity)
      .whereType<CardIdentity>()
      .toList(growable: false);
  if (identities.length != meld.cards.length || identities.length < 3) {
    return null;
  }
  final suit = identities.first.suit;
  if (identities.any((identity) => identity.suit != suit)) {
    return null;
  }

  final lowOrders = identities.map((identity) => identity.rank.order).toList()
    ..sort();
  if (_isConsecutive(lowOrders)) {
    return lowOrders;
  }

  final highOrders =
      identities
          .map((identity) => _rankOrder(identity.rank, highAce: true))
          .toList()
        ..sort();
  if (_isConsecutive(highOrders)) {
    return highOrders;
  }
  return null;
}

bool _isConsecutive(List<int> orders) {
  for (var index = 1; index < orders.length; index += 1) {
    if (orders[index] != orders[index - 1] + 1) {
      return false;
    }
  }
  return true;
}

int _rankOrder(CardRank rank, {required bool highAce}) {
  if (highAce && rank == CardRank.ace) {
    return 14;
  }
  return rank.order;
}
