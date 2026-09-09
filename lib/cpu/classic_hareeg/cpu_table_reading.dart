import '../../domain/classic_hareeg/analysis/table_reading_analysis.dart';
import '../../domain/classic_hareeg/game/round_seed_algorithm.dart';
import '../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../domain/classic_hareeg/models/player_seat.dart';
import '../../domain/classic_hareeg/models/playing_card.dart';
import 'cpu_move_plan_pipeline.dart';
import 'cpu_observation.dart';

export '../../domain/classic_hareeg/analysis/table_reading_analysis.dart'
    show FeedEvidenceKind, FeedRiskAssessment, TableReadingAnalysis;

/// How much of the shared table reading one difficulty tier is allowed to use.
///
/// This is the whole of the tier ladder for the new signals, expressed as four
/// pure values. Planners go through [CpuTableReading], which reads this policy;
/// no planner reads the underlying analysis directly, so a tier cannot quietly
/// route around its own gating.
///
/// Difficulty changes *attention*, never the computed facts. The arithmetic in
/// [TableReadingAnalysis] and [FeedRiskAnalysis] is identical for Beginner and
/// Expert; what differs is whether the answer is looked at, how far back the
/// pickup memory reaches, and — for Casual — whether this particular position
/// is one of the ones it happens to notice.
class TableReadingPolicy {
  const TableReadingPolicy._({
    required this.difficulty,
    required this.attendsMaterialSignal,
    required this.attendsFeedRisk,
    required this.pickupMemoryDepth,
    required this.materialAttentionPercent,
  });

  /// Ignores both signals and remembers nothing.
  static const beginner = TableReadingPolicy._(
    difficulty: CpuDifficulty.beginner,
    attendsMaterialSignal: false,
    attendsFeedRisk: false,
    pickupMemoryDepth: 0,
    materialAttentionPercent: 0,
  );

  /// Notices the material signal on a stable 40% of positions, never the feed
  /// signal, and remembers one pickup.
  static const casual = TableReadingPolicy._(
    difficulty: CpuDifficulty.casual,
    attendsMaterialSignal: true,
    attendsFeedRisk: false,
    pickupMemoryDepth: 1,
    materialAttentionPercent: 40,
  );

  /// Always applies the material signal, never the feed signal, and remembers
  /// three pickups. Skilled keeps its own long-standing all-opponent hot-rank
  /// tiebreak; the next-seat feed signal belongs to Expert.
  static const skilled = TableReadingPolicy._(
    difficulty: CpuDifficulty.skilled,
    attendsMaterialSignal: true,
    attendsFeedRisk: false,
    pickupMemoryDepth: 3,
    materialAttentionPercent: 100,
  );

  /// Always applies both signals and remembers six pickups.
  static const expert = TableReadingPolicy._(
    difficulty: CpuDifficulty.expert,
    attendsMaterialSignal: true,
    attendsFeedRisk: true,
    pickupMemoryDepth: 6,
    materialAttentionPercent: 100,
  );

  /// The policy for [difficulty].
  static TableReadingPolicy forDifficulty(CpuDifficulty difficulty) {
    return switch (difficulty) {
      CpuDifficulty.beginner => beginner,
      CpuDifficulty.casual => casual,
      CpuDifficulty.skilled => skilled,
      CpuDifficulty.expert => expert,
    };
  }

  /// Tier this policy belongs to.
  final CpuDifficulty difficulty;

  /// Whether the tier consumes card-death / development liveness at all.
  final bool attendsMaterialSignal;

  /// Whether the tier consumes next-seat feed risk at all.
  final bool attendsFeedRisk;

  /// How many of the target seat's pile pickups stay in memory.
  ///
  /// Ages the recent-pickup evidence class only. Visible melds are current
  /// table state rather than memory and are never aged out.
  final int pickupMemoryDepth;

  /// Percentage of decision positions where the material signal is noticed.
  final int materialAttentionPercent;

  /// Whether attention is sampled rather than constant.
  bool get samplesMaterialAttention =>
      attendsMaterialSignal && materialAttentionPercent < 100;

  /// Whether the material signal is applied at this decision position.
  ///
  /// The answer is a property of the *position*, not of any candidate card, so
  /// every candidate weighed inside one decision gets the same answer. Sampling
  /// candidates instead would let one comparison mix an attentive and an
  /// inattentive card, which is not a mistake a human makes.
  bool appliesMaterialSignalAt(CpuObservation observation) {
    if (!attendsMaterialSignal) {
      return false;
    }
    if (materialAttentionPercent >= 100) {
      return true;
    }
    if (materialAttentionPercent <= 0) {
      return false;
    }
    return positionBucket(observation) < materialAttentionPercent;
  }

  /// Whether the feed-risk signal is applied at this decision position.
  bool appliesFeedRiskAt(CpuObservation observation) => attendsFeedRisk;

  /// The serialized decision-position key that attention sampling hashes.
  ///
  /// Every field is reachable through [CpuObservation] and is a scalar, so no
  /// collection iteration order participates and the key is identical for two
  /// observations that describe the same position with their cards in a
  /// different order.
  ///
  /// The candidate card is deliberately absent: including it would sample
  /// *cards* rather than positions.
  static String positionKey(CpuObservation observation) {
    return <String>[
      observation.seat.name,
      'r${observation.roundNumber}',
      observation.turnPhase.name,
      's${observation.stockCount}',
      'd${observation.discardCount}',
      'm${observation.tableMeldCount}',
      'h${observation.ownHand.length}',
    ].join('|');
  }

  /// The 0–99 attention bucket for [observation]'s position.
  static int positionBucket(CpuObservation observation) {
    return fnv1a32(positionKey(observation)) % 100;
  }

  /// FNV-1a, 32-bit, written out here on purpose.
  ///
  /// `String.hashCode`, `Object.hash`, and `Object.hashAll` are all unsuitable:
  /// none of them is contracted to return the same value in another process or
  /// under another SDK, and a sampling rule that shifts between runs is not
  /// reproducible — replays and tests would drift for reasons that have nothing
  /// to do with the game. This arithmetic is fixed by the algorithm, so the
  /// same key always yields the same bucket everywhere.
  static int fnv1a32(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = fnvMultiply32(hash);
    }
    return hash;
  }
}

/// One tier's view of the shared table reading for one decision position.
///
/// Built once per plan. The signals are computed the same way for every tier;
/// the `applied*` members are the ones a planner is allowed to act on, and the
/// `available*` members are what the raw computation offers before attention is
/// applied. Keeping both visible is what lets the device probe report
/// *consumption* per tier instead of mere firing counts.
class CpuTableReading {
  /// Builds the reading for [observation] under its own difficulty's policy.
  CpuTableReading.forObservation(this.observation)
    : policy = TableReadingPolicy.forDifficulty(observation.difficulty);

  /// The position being read.
  final CpuObservation observation;

  /// The attention policy for this observation's tier.
  final TableReadingPolicy policy;

  /// The shared, tier-independent analysis of this position.
  late final TableReadingAnalysis analysis = TableReadingAnalysis(
    perspectiveHand: observation.ownHand,
    discardPile: observation.discardPile,
    visibleMelds: observation.tableMelds,
    deckCopyCount: observation.deckCopyCount,
    // The analysis lives under `lib/domain/` and must not reach into the CPU
    // layer, so the keep-score model is handed to it as a plain function.
    soloValue: partialSoloValue,
  );

  /// Whether the material signal is applied at this position.
  late final bool materialApplied = policy.appliesMaterialSignalAt(observation);

  /// Ids of hand cards sitting in a developing group whose every completion is
  /// dead — the group cannot become a meld, so the cards are holding the hand
  /// back rather than building it.
  ///
  /// This is the raw availability, before attention.
  late final Set<String> availableStarvedCardIds = {
    for (final group in analysis.partialGroups)
      if (analysis.isGroupStarved(group))
        for (final card in group.cards) card.id,
  };

  /// [availableStarvedCardIds] after the tier's attention is applied.
  late final Set<String> starvedCardIds = materialApplied
      ? availableStarvedCardIds
      : const <String>{};

  /// Whether [card] is one this tier should shed early on material grounds.
  bool isStarved(HareegCard card) => starvedCardIds.contains(card.id);

  /// The seat that would receive a discard, or null when there is none.
  late final PlayerSeat? feedTarget = FeedRiskAnalysis.nextActiveSeat(
    from: observation.seat,
    activeSeats: observation.activeSeats,
  );

  /// The target seat's pile pickups, already truncated to this tier's memory.
  late final List<HareegCard> _rememberedPickups = () {
    final target = feedTarget;
    if (target == null || policy.pickupMemoryDepth <= 0) {
      return const <HareegCard>[];
    }
    return List<HareegCard>.unmodifiable(
      observation.discardHistory.lastPickupsBy(
        target,
        policy.pickupMemoryDepth,
      ),
    );
  }();

  /// Feed risk for [candidate] before attention — what the signal can see.
  FeedRiskAssessment availableFeedRiskFor(HareegCard candidate) {
    final target = feedTarget;
    if (target == null) {
      return FeedRiskAssessment.noTarget(candidate);
    }
    return FeedRiskAnalysis.assess(
      candidate: candidate,
      perspective: observation.seat,
      activeSeats: observation.activeSeats,
      recentPickups: _rememberedPickups,
      targetMelds: observation.tableMeldsFor(target),
      targetHasOpened: observation.hasOpened(target),
    );
  }

  /// Feed risk for [candidate] as this tier is allowed to use it, or null when
  /// the tier does not consume the signal.
  FeedRiskAssessment? appliedFeedRiskFor(HareegCard candidate) {
    if (!policy.appliesFeedRiskAt(observation)) {
      return null;
    }
    return availableFeedRiskFor(candidate);
  }

  /// Whether feeding [candidate] is a risk this tier acts on.
  bool isFeedRisk(HareegCard candidate) {
    return appliedFeedRiskFor(candidate)?.isRisky ?? false;
  }
}
