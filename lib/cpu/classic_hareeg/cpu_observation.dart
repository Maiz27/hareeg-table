import '../../domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import '../../domain/classic_hareeg/game/classic_hareeg_discard_history.dart';
import '../../domain/classic_hareeg/game/classic_hareeg_round.dart';
import '../../domain/classic_hareeg/game/classic_hareeg_score_ledger.dart';
import '../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../domain/classic_hareeg/models/player_seat.dart';
import '../../domain/classic_hareeg/models/playing_card.dart';
import '../../domain/classic_hareeg/rules/meld_partition.dart';
import '../../domain/classic_hareeg/rules/meld_partition_enumerator.dart';
import '../../domain/classic_hareeg/rules/opening_rules.dart';
import 'cpu_difficulty_profile.dart';

export '../../domain/classic_hareeg/game/classic_hareeg_discard_history.dart'
    show DiscardHistoryView, EmptyDiscardHistoryView;
export '../../domain/classic_hareeg/rules/meld_partition.dart'
    show MeldPartition;
export '../../domain/classic_hareeg/rules/meld_partition_enumerator.dart'
    show MeldPartitionEnumerator, MeldPartitionRankers;

/// Read-only state visible to a Classic Hareeg CPU decision.
///
/// This is the CPU/rules seam for deeper table-aware strategies. It exposes
/// visible game state and legal action ids, but no mutation APIs and no private
/// controller fields.
abstract interface class CpuObservation {
  /// Seat controlled by this CPU decision.
  PlayerSeat get seat;

  /// Difficulty profile selected for this match.
  CpuDifficulty get difficulty;

  /// Read-only identifiers for actions the rules engine has deemed legal.
  List<String> get legalActionIds;

  /// Current turn phase.
  TurnPhase get turnPhase;

  /// Pending discard awaiting a use-or-return decision, if any.
  HareegCard? get pendingDiscard;

  /// CPU seat's own visible hand.
  List<HareegCard> get ownHand;

  /// Number of cards held by [seat].
  int handCountFor(PlayerSeat seat);

  /// Table melds owned by [seat].
  List<PlacedMeld> tableMeldsFor(PlayerSeat seat);

  /// All table melds grouped by owner.
  Map<PlayerSeat, List<PlacedMeld>> get tableMelds;

  /// Total number of table melds.
  int get tableMeldCount;

  /// Number of cards left in stock.
  int get stockCount;

  /// Top discard-pile card, if any.
  HareegCard? get topDiscard;

  /// Number of cards in the discard pile.
  int get discardCount;

  /// Opening benchmark state for this round.
  OpeningState get openingState;

  /// Whether [seat] has opened.
  bool hasOpened(PlayerSeat seat);

  /// Whether the CPU seat has opened.
  bool ownHasOpened();

  /// Seat currently owning the opening benchmark, if any.
  PlayerSeat? get benchmarkOwner;

  /// Current opening requirement after benchmark pressure.
  int get currentOpeningRequirement;

  /// Current score view.
  ClassicHareegScoreView get scoreView;

  /// Visible score for [seat].
  int scoreFor(PlayerSeat seat);

  /// Visible score for the CPU seat.
  int get ownScore;

  /// Score at which a seat is eliminated.
  int get eliminationThreshold;

  /// Seats still active in the match.
  List<PlayerSeat> get activeSeats;

  /// Seat whose turn is active.
  PlayerSeat get currentSeat;

  /// Active seats other than [seat], in turn order.
  List<PlayerSeat> get opponents;

  /// Seat eligible to claim Fifty during an open window, if any.
  PlayerSeat? get fiftyClaimant;

  /// Seconds remaining in the Fifty window, or null when no window is visible.
  int? get fiftySecondsRemaining;

  /// Whether the CPU seat is the current Fifty claimant.
  bool get ownIsFiftyClaimant;

  /// Round-scoped discard memory view.
  DiscardHistoryView get discardHistory;

  /// Lazy meld-partition view for the CPU hand.
  MeldPartitionView get partitions;

  /// Convenience view of the best short single-meld partition, when available.
  MeldPartition? shortestSingleMeld();

  /// Convenience view of a hand-finishing partition, when available.
  MeldPartition? finishingPartition();

  /// Difficulty timing and miss-chance profile.
  CpuDifficultyProfile get difficultyProfile;
}

/// Narrow read-only view over candidate meld partitions.
abstract interface class MeldPartitionView {
  /// Lazily enumerates candidate partitions for the CPU hand.
  Iterable<MeldPartition> enumerate({
    bool includePendingDiscard = true,
    int maxPartitions = 32,
    int minMelds = 1,
    int maxMelds = 5,
    String? mustUseCardId,
    int? minTotalValue,
  });
}

/// Empty meld-partition view used by tests and ad-hoc observation fakes.
final class EmptyMeldPartitionView implements MeldPartitionView {
  /// Creates an empty meld-partition view.
  const EmptyMeldPartitionView();

  @override
  Iterable<MeldPartition> enumerate({
    bool includePendingDiscard = true,
    int maxPartitions = 32,
    int minMelds = 1,
    int maxMelds = 5,
    String? mustUseCardId,
    int? minTotalValue,
  }) {
    return const [];
  }
}

/// Value-backed CPU observation for planner tests and synthetic scenarios.
///
/// Production code should use [LiveCpuObservation]. Planner tests use this
/// adapter to configure only the decision facts under test while sharing the
/// same derived helpers as the live adapter.
final class CpuObservationFacts implements CpuObservation {
  /// Creates a configured CPU observation.
  CpuObservationFacts({
    this.seat = PlayerSeat.east,
    this.difficulty = CpuDifficulty.skilled,
    Iterable<String> legalActionIds = const [],
    this.turnPhase = TurnPhase.action,
    this.pendingDiscard,
    Iterable<HareegCard> ownHand = const [],
    Map<PlayerSeat, int> handCounts = const {},
    Map<PlayerSeat, List<PlacedMeld>> tableMelds = const {},
    this.stockCount = 0,
    this.topDiscard,
    this.discardCount = 0,
    this.openingState = const OpeningState(
      baseRequirement: 30,
      currentRequirement: 30,
      openedSeats: {PlayerSeat.east},
    ),
    int ownScore = 0,
    Map<PlayerSeat, int> opponentScores = const {},
    Map<PlayerSeat, int> scores = const {},
    Map<PlayerSeat, int> previousScores = const {},
    this.eliminationThreshold = 31,
    Iterable<PlayerSeat> activeSeats = const [
      PlayerSeat.south,
      PlayerSeat.east,
      PlayerSeat.north,
      PlayerSeat.west,
    ],
    PlayerSeat? currentSeat,
    Iterable<PlayerSeat>? opponents,
    this.fiftyClaimant,
    this.fiftySecondsRemaining,
    this.discardHistory = const EmptyDiscardHistoryView(),
    this.partitions = const EmptyMeldPartitionView(),
    MeldPartition? shortestSingleMeld,
    MeldPartition? finishingPartition,
  }) : legalActionIds = List.unmodifiable(legalActionIds),
       ownHand = List.unmodifiable(ownHand),
       _handCounts = Map.unmodifiable(handCounts),
       _tableMelds = _copyTableMelds(tableMelds),
       _scores = Map.unmodifiable({
         ...scores,
         ...opponentScores,
         seat: ownScore,
       }),
       _previousScores = Map.unmodifiable({
         ...previousScores,
         ...opponentScores,
         seat: previousScores[seat] ?? ownScore,
       }),
       activeSeats = List.unmodifiable(activeSeats),
       currentSeat = currentSeat ?? seat,
       _opponents = opponents == null ? null : List.unmodifiable(opponents),
       _shortestSingleMeld = shortestSingleMeld,
       _finishingPartition = finishingPartition;

  @override
  final PlayerSeat seat;

  @override
  final CpuDifficulty difficulty;

  @override
  final List<String> legalActionIds;

  @override
  final TurnPhase turnPhase;

  @override
  final HareegCard? pendingDiscard;

  @override
  final List<HareegCard> ownHand;

  final Map<PlayerSeat, int> _handCounts;
  final Map<PlayerSeat, List<PlacedMeld>> _tableMelds;

  @override
  final int stockCount;

  @override
  final HareegCard? topDiscard;

  @override
  final int discardCount;

  @override
  final OpeningState openingState;

  final Map<PlayerSeat, int> _scores;
  final Map<PlayerSeat, int> _previousScores;

  @override
  final int eliminationThreshold;

  @override
  final List<PlayerSeat> activeSeats;

  @override
  final PlayerSeat currentSeat;

  final List<PlayerSeat>? _opponents;

  @override
  final PlayerSeat? fiftyClaimant;

  @override
  final int? fiftySecondsRemaining;

  @override
  final DiscardHistoryView discardHistory;

  @override
  final MeldPartitionView partitions;

  final MeldPartition? _shortestSingleMeld;
  final MeldPartition? _finishingPartition;

  @override
  int handCountFor(PlayerSeat seat) {
    if (seat == this.seat) {
      return ownHand.length;
    }
    return _handCounts[seat] ?? 0;
  }

  @override
  List<PlacedMeld> tableMeldsFor(PlayerSeat seat) {
    return _tableMelds[seat] ?? const [];
  }

  @override
  Map<PlayerSeat, List<PlacedMeld>> get tableMelds => _tableMelds;

  @override
  int get tableMeldCount {
    return _tableMelds.values.fold<int>(
      0,
      (total, melds) => total + melds.length,
    );
  }

  @override
  bool hasOpened(PlayerSeat seat) => openingState.hasOpened(seat);

  @override
  bool ownHasOpened() => hasOpened(seat);

  @override
  PlayerSeat? get benchmarkOwner => openingState.benchmarkOwner;

  @override
  int get currentOpeningRequirement => openingState.currentRequirement;

  @override
  ClassicHareegScoreView get scoreView {
    return ClassicHareegScoreView(
      previousScores: _previousScores,
      currentScores: _scores,
    );
  }

  @override
  int scoreFor(PlayerSeat seat) => scoreView.currentScores[seat] ?? 0;

  @override
  int get ownScore => scoreFor(seat);

  @override
  List<PlayerSeat> get opponents {
    final configured = _opponents;
    if (configured != null) {
      return configured;
    }
    final result = <PlayerSeat>[];
    var cursor = seat.nextAntiClockwise;
    while (cursor != seat) {
      if (activeSeats.contains(cursor)) {
        result.add(cursor);
      }
      cursor = cursor.nextAntiClockwise;
    }
    return List.unmodifiable(result);
  }

  @override
  bool get ownIsFiftyClaimant => fiftyClaimant == seat;

  @override
  MeldPartition? shortestSingleMeld() {
    final configured = _shortestSingleMeld;
    if (configured != null) {
      return configured;
    }
    final candidates =
        partitions
            .enumerate(maxPartitions: 128, minMelds: 1, maxMelds: 1)
            .toList()
          ..sort(MeldPartitionRankers.byMeanMeldLengthAsc);
    if (candidates.isEmpty) {
      return null;
    }
    return candidates.first;
  }

  @override
  MeldPartition? finishingPartition() {
    final configured = _finishingPartition;
    if (configured != null) {
      return configured;
    }
    for (final partition in partitions.enumerate(maxPartitions: 128)) {
      if (partition.cardsRemaining.length <= 1) {
        return partition;
      }
    }
    return null;
  }

  @override
  CpuDifficultyProfile get difficultyProfile {
    return CpuDifficultyProfile.forDifficulty(difficulty);
  }

  static Map<PlayerSeat, List<PlacedMeld>> _copyTableMelds(
    Map<PlayerSeat, List<PlacedMeld>> source,
  ) {
    return Map.unmodifiable({
      for (final entry in source.entries)
        entry.key: List<PlacedMeld>.unmodifiable(entry.value),
    });
  }
}

/// Live meld-partition view backed by the current controller hand.
final class LiveMeldPartitionView implements MeldPartitionView {
  /// Creates a live partition view for [seat].
  const LiveMeldPartitionView({required this.controller, required this.seat});

  /// Controller that owns the hand being enumerated.
  final ClassicHareegGameController controller;

  /// Seat whose hand is visible to the CPU.
  final PlayerSeat seat;

  @override
  Iterable<MeldPartition> enumerate({
    bool includePendingDiscard = true,
    int maxPartitions = 32,
    int minMelds = 1,
    int maxMelds = 5,
    String? mustUseCardId,
    int? minTotalValue,
  }) {
    if (maxPartitions <= 0) {
      return const [];
    }

    final pending = controller.pendingDiscard;
    final hand = controller.handFor(seat);
    final cards = !includePendingDiscard && pending != null
        ? [
            for (final card in hand)
              if (card.id != pending.id) card,
          ]
        : hand;

    return MeldPartitionEnumerator.partitionsOf(
      cards,
      minMelds: minMelds,
      maxMelds: maxMelds,
      mustUseCardId: mustUseCardId,
      minTotalValue: minTotalValue,
      safetyCap: maxPartitions,
    );
  }
}

/// Live read-only adapter over [ClassicHareegGameController].
final class LiveCpuObservation implements CpuObservation {
  /// Creates a live CPU observation.
  LiveCpuObservation({
    required this.controller,
    required this.seat,
    required Iterable<String> legalActionIds,
    required this.difficulty,
    MeldPartitionView? partitions,
    DiscardHistoryView? discardHistory,
  }) : legalActionIds = List.unmodifiable(legalActionIds),
       discardHistory = discardHistory ?? controller.discardHistory,
       partitions =
           partitions ??
           LiveMeldPartitionView(controller: controller, seat: seat);

  /// Controller that owns the live game state.
  final ClassicHareegGameController controller;

  @override
  final PlayerSeat seat;

  @override
  final List<String> legalActionIds;

  @override
  final CpuDifficulty difficulty;

  @override
  final DiscardHistoryView discardHistory;

  @override
  final MeldPartitionView partitions;

  @override
  TurnPhase get turnPhase => controller.turnPhase;

  @override
  HareegCard? get pendingDiscard => controller.pendingDiscard;

  @override
  List<HareegCard> get ownHand => controller.handFor(seat);

  @override
  int handCountFor(PlayerSeat seat) => controller.cardCountFor(seat);

  @override
  List<PlacedMeld> tableMeldsFor(PlayerSeat seat) {
    return controller.tableMeldsFor(seat);
  }

  @override
  Map<PlayerSeat, List<PlacedMeld>> get tableMelds => controller.tableMelds;

  @override
  int get tableMeldCount => controller.tableMeldCount;

  @override
  int get stockCount => controller.stockCount;

  @override
  HareegCard? get topDiscard => controller.topDiscard;

  @override
  int get discardCount => controller.discardPile.length;

  @override
  OpeningState get openingState => controller.openingState;

  @override
  bool hasOpened(PlayerSeat seat) => openingState.hasOpened(seat);

  @override
  bool ownHasOpened() => hasOpened(seat);

  @override
  PlayerSeat? get benchmarkOwner => openingState.benchmarkOwner;

  @override
  int get currentOpeningRequirement => openingState.currentRequirement;

  @override
  ClassicHareegScoreView get scoreView => controller.scoreView;

  @override
  int scoreFor(PlayerSeat seat) => scoreView.currentScores[seat] ?? 0;

  @override
  int get ownScore => scoreFor(seat);

  @override
  int get eliminationThreshold => controller.rules.eliminationScore;

  @override
  List<PlayerSeat> get activeSeats => controller.activeSeats;

  @override
  PlayerSeat get currentSeat => controller.currentSeat;

  @override
  List<PlayerSeat> get opponents {
    final opponents = <PlayerSeat>[];
    var cursor = seat.nextAntiClockwise;
    while (cursor != seat) {
      if (activeSeats.contains(cursor)) {
        opponents.add(cursor);
      }
      cursor = cursor.nextAntiClockwise;
    }
    return List.unmodifiable(opponents);
  }

  @override
  PlayerSeat? get fiftyClaimant => controller.fiftyClaimant;

  @override
  int? get fiftySecondsRemaining => controller.fiftySecondsRemaining;

  @override
  bool get ownIsFiftyClaimant => fiftyClaimant == seat;

  @override
  MeldPartition? shortestSingleMeld() {
    final candidates =
        partitions
            .enumerate(maxPartitions: 128, minMelds: 1, maxMelds: 1)
            .toList()
          ..sort(MeldPartitionRankers.byMeanMeldLengthAsc);
    if (candidates.isEmpty) {
      return null;
    }
    return candidates.first;
  }

  @override
  MeldPartition? finishingPartition() {
    for (final partition in partitions.enumerate(maxPartitions: 128)) {
      if (partition.cardsRemaining.length <= 1) {
        return partition;
      }
    }
    return null;
  }

  @override
  CpuDifficultyProfile get difficultyProfile {
    return CpuDifficultyProfile.forDifficulty(difficulty);
  }
}
