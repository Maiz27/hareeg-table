import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../app/app_routes.dart';
import '../../../../cpu/classic_hareeg/cpu_strategy.dart';
import '../../../../data/persistence/match_repository.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_round.dart';
import '../../../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../domain/classic_hareeg/rules/match_progression_rules.dart';
import '../../../../domain/classic_hareeg/rules/meld_validator.dart';
import '../../../../l10n/app_strings.dart';
import '../../round_summary/views/round_summary_screen.dart';

/// First playable Classic Hareeg table slice.
///
/// All gameplay state is owned by [ClassicHareegGameController]. Human and CPU
/// moves are routed through `controller.applyAction` so the rules engine
/// remains the single point of legality enforcement.
class GameTableScreen extends StatefulWidget {
  /// Creates a table screen from setup values.
  const GameTableScreen({
    required this.setup,
    required this.matchRepository,
    this.initialSnapshot,
    this.cpuStrategy = const ClassicHareegCpuStrategy(),
    super.key,
  });

  /// Setup values used to deal the round.
  final ClassicHareegSetup setup;

  /// Active match persistence.
  final MatchRepository matchRepository;

  /// Saved match state to resume instead of dealing.
  final ClassicHareegMatchSnapshot? initialSnapshot;

  /// CPU strategy used for non-human seats. Injected for tests.
  final CpuStrategy cpuStrategy;

  @override
  State<GameTableScreen> createState() => _GameTableScreenState();
}

class _GameTableScreenState extends State<GameTableScreen> {
  /// Safety bound for CPU action loops to prevent UI hangs from a strategy
  /// that returns the same action repeatedly. A real CPU turn sequence is at
  /// most ~3 actions per seat (take + use + discard); 64 covers all CPU
  /// seats with generous headroom.
  static const _cpuActionLimit = 64;

  late ClassicHareegGameController _controller;
  final _selectedCardIds = <String>{};
  String? _humanFeedback;

  @override
  void initState() {
    super.initState();
    AppOrientation.useLandscape();
    final snapshot = widget.initialSnapshot;
    _controller = snapshot != null
        ? ClassicHareegGameController.fromSnapshot(snapshot)
        : ClassicHareegGameController.fromRound(
            ClassicHareegRound.deal(setup: widget.setup),
          );
    _runCpuTurns();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _persistAndMaybeFinish();
    });
  }

  @override
  void dispose() {
    AppOrientation.usePortrait();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final humanSeat = PlayerSeat.south;
    final isHumanTurn = _controller.currentSeat == humanSeat;
    final legalActions = isHumanTurn
        ? _controller.legalActionIdsFor(humanSeat)
        : const <String>[];
    final pending = _controller.pendingDiscard;
    final canDraw = legalActions.contains(ClassicHareegActionIds.drawStock);
    final canTakeDiscard = legalActions.contains(
      ClassicHareegActionIds.takeDiscard,
    );
    final canReturnDiscard = legalActions.contains(
      ClassicHareegActionIds.returnPendingDiscard,
    );
    final selectedCards = _selectedCards();
    final selectedCardId = selectedCards.length == 1
        ? selectedCards.single.id
        : null;
    final discardActionId = selectedCardId == null
        ? null
        : '${ClassicHareegActionIds.discardPrefix}$selectedCardId';
    final canDiscard =
        discardActionId != null && legalActions.contains(discardActionId);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final metrics = _TableLayoutMetrics.from(constraints);

          return SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: EdgeInsets.all(metrics.padding),
              child: Column(
                children: [
                  SizedBox(
                    height: metrics.headerHeight,
                    child: _TableHeader(
                      height: metrics.headerHeight,
                      setup: widget.setup,
                      starter: _controller.starter,
                      currentSeat: _controller.currentSeat,
                      turnPhase: _controller.turnPhase,
                      onLeave: () => Navigator.of(context).pop(),
                    ),
                  ),
                  SizedBox(height: metrics.gap),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SeatPanel(
                          seat: PlayerSeat.west,
                          count: _controller.cardCountFor(PlayerSeat.west),
                          width: metrics.sideSeatWidth,
                        ),
                        SizedBox(width: metrics.gap),
                        Expanded(
                          child: Column(
                            children: [
                              _SeatPanel(
                                seat: PlayerSeat.north,
                                count: _controller.cardCountFor(
                                  PlayerSeat.north,
                                ),
                                horizontal: true,
                                height: metrics.topSeatHeight,
                              ),
                              SizedBox(height: metrics.gap),
                              Expanded(
                                child: _TableStage(
                                  metrics: metrics,
                                  stockCount: _controller.stockCount,
                                  topDiscard: _controller.topDiscard,
                                  pendingDiscard: pending,
                                  selectedCards: selectedCards,
                                  openingRequirement:
                                      widget.setup.openingRequirement,
                                  humanFeedback: _humanFeedback,
                                  canDraw: canDraw,
                                  canTakeDiscard: canTakeDiscard,
                                  canDiscard: canDiscard,
                                  canReturnDiscard: canReturnDiscard,
                                  onDraw: () => _runHumanAction(
                                    ClassicHareegActionIds.drawStock,
                                  ),
                                  onTakeDiscard: () => _runHumanAction(
                                    ClassicHareegActionIds.takeDiscard,
                                  ),
                                  onReturnDiscard: () => _runHumanAction(
                                    ClassicHareegActionIds.returnPendingDiscard,
                                  ),
                                  onDiscard: discardActionId == null
                                      ? null
                                      : () => _runHumanAction(discardActionId),
                                  onAutoSort: _sortHumanHand,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: metrics.gap),
                        _SeatPanel(
                          seat: PlayerSeat.east,
                          count: _controller.cardCountFor(PlayerSeat.east),
                          width: metrics.sideSeatWidth,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: metrics.gap),
                  SizedBox(
                    height: metrics.handHeaderHeight,
                    child: _HumanHandHeader(
                      count: _controller.cardCountFor(PlayerSeat.south),
                    ),
                  ),
                  SizedBox(height: metrics.handGap),
                  _HumanHand(
                    height: metrics.handListHeight,
                    cardWidth: metrics.handCardWidth,
                    cardHeight: metrics.handCardHeight,
                    cards: _controller.handFor(PlayerSeat.south),
                    selectedIds: _selectedCardIds,
                    onSelected: _toggleSelectedCard,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _toggleSelectedCard(HareegCard card) {
    setState(() {
      if (_selectedCardIds.contains(card.id)) {
        _selectedCardIds.remove(card.id);
      } else {
        _selectedCardIds.add(card.id);
      }
    });
  }

  List<HareegCard> _selectedCards() {
    if (_selectedCardIds.isEmpty) {
      return const [];
    }

    final hand = _controller.handFor(PlayerSeat.south);
    final byId = {for (final card in hand) card.id: card};
    return [
      for (final id in _selectedCardIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  Future<void> _sortHumanHand() async {
    setState(() {
      _controller.sortHandFor(PlayerSeat.south);
    });
    await _persistAndMaybeFinish();
  }

  Future<void> _runHumanAction(String actionId) async {
    final result = _controller.applyAction(actionId);
    if (!result.isSuccess) {
      setState(() {
        _humanFeedback = result.message;
      });
      return;
    }

    setState(() {
      _humanFeedback = null;
      if (actionId.startsWith(ClassicHareegActionIds.discardPrefix) ||
          actionId == ClassicHareegActionIds.returnPendingDiscard) {
        _selectedCardIds.clear();
      }
      _runCpuTurns();
    });
    await _persistAndMaybeFinish();
  }

  void _runCpuTurns() {
    var safety = 0;
    while (!_controller.isRoundOver &&
        _controller.currentSeat != PlayerSeat.south &&
        safety < _cpuActionLimit) {
      final seat = _controller.currentSeat;
      final legal = _controller.legalActionIdsFor(seat);
      if (legal.isEmpty) {
        break;
      }
      final intent = widget.cpuStrategy.chooseMove(
        CpuTurnSnapshot(
          seat: seat,
          legalActionIds: legal,
          difficulty: widget.setup.cpuDifficulty,
        ),
      );
      final result = _controller.applyAction(intent.actionId);
      if (!result.isSuccess) {
        throw StateError(
          'CPU strategy returned illegal action ${intent.actionId}: '
          '${result.message}',
        );
      }
      safety += 1;
    }
    _selectedCardIds.clear();
  }

  Future<void> _persistAndMaybeFinish() async {
    if (_controller.isRoundOver) {
      await widget.matchRepository.abandonActiveMatch();
    } else {
      await widget.matchRepository.saveActiveMatch(_controller.toSnapshot());
    }
    if (!mounted) {
      return;
    }
    if (_controller.isRoundOver) {
      _navigateToRoundSummary();
    }
  }

  void _navigateToRoundSummary() {
    final outcome = _controller.roundOutcome;
    if (outcome == null) {
      return;
    }

    final remainingCardCounts = <PlayerSeat, int>{
      for (final seat in PlayerSeat.values)
        seat: _controller.cardCountFor(seat),
    };
    final result = RoundProgressResult(
      type: outcome,
      remainingCardCounts: remainingCardCounts,
    );
    final activeSeats = PlayerSeat.values.toList();
    final previousScores = <PlayerSeat, int>{
      for (final seat in PlayerSeat.values) seat: 0,
    };
    final progress = ClassicHareegMatchProgressionRules.applyRoundResult(
      scores: previousScores,
      activeSeats: activeSeats,
      currentStarter: _controller.starter,
      result: result,
    );

    Navigator.of(context).pushReplacementNamed(
      AppRoutes.roundSummary,
      arguments: RoundSummaryArguments(
        result: result,
        progress: progress,
        previousScores: previousScores,
      ),
    );
  }
}

class _TableLayoutMetrics {
  const _TableLayoutMetrics({
    required this.compact,
    required this.padding,
    required this.gap,
    required this.handGap,
    required this.headerHeight,
    required this.sideSeatWidth,
    required this.topSeatHeight,
    required this.actionDockWidth,
    required this.handHeaderHeight,
    required this.handListHeight,
    required this.handCardWidth,
    required this.handCardHeight,
  });

  final bool compact;
  final double padding;
  final double gap;
  final double handGap;
  final double headerHeight;
  final double sideSeatWidth;
  final double topSeatHeight;
  final double actionDockWidth;
  final double handHeaderHeight;
  final double handListHeight;
  final double handCardWidth;
  final double handCardHeight;

  factory _TableLayoutMetrics.from(BoxConstraints constraints) {
    final compact = constraints.maxHeight < 430 || constraints.maxWidth < 700;
    final padding = compact ? 6.0 : 12.0;
    final gap = compact ? 4.0 : 8.0;
    final sideSeatWidth = (constraints.maxWidth * 0.12)
        .clamp(compact ? 64.0 : 84.0, compact ? 86.0 : 104.0)
        .toDouble();
    final handCardHeight = (constraints.maxHeight * 0.16)
        .clamp(compact ? 52.0 : 64.0, 76.0)
        .toDouble();

    return _TableLayoutMetrics(
      compact: compact,
      padding: padding,
      gap: gap,
      handGap: compact ? 3.0 : 6.0,
      headerHeight: compact ? 44.0 : 48.0,
      sideSeatWidth: sideSeatWidth,
      topSeatHeight: (constraints.maxHeight * 0.15)
          .clamp(compact ? 46.0 : 56.0, compact ? 58.0 : 68.0)
          .toDouble(),
      actionDockWidth: (constraints.maxWidth * 0.26)
          .clamp(compact ? 186.0 : 200.0, compact ? 210.0 : 240.0)
          .toDouble(),
      handHeaderHeight: compact ? 18.0 : 22.0,
      handListHeight: handCardHeight + (compact ? 8.0 : 16.0),
      handCardWidth: (handCardHeight * 0.68).clamp(36.0, 52.0).toDouble(),
      handCardHeight: handCardHeight,
    );
  }
}

class _TableStage extends StatelessWidget {
  const _TableStage({
    required this.metrics,
    required this.stockCount,
    required this.topDiscard,
    required this.pendingDiscard,
    required this.selectedCards,
    required this.openingRequirement,
    required this.humanFeedback,
    required this.canDraw,
    required this.canTakeDiscard,
    required this.canDiscard,
    required this.canReturnDiscard,
    required this.onDraw,
    required this.onTakeDiscard,
    required this.onReturnDiscard,
    required this.onDiscard,
    required this.onAutoSort,
  });

  final _TableLayoutMetrics metrics;
  final int stockCount;
  final HareegCard? topDiscard;
  final HareegCard? pendingDiscard;
  final List<HareegCard> selectedCards;
  final int openingRequirement;
  final String? humanFeedback;
  final bool canDraw;
  final bool canTakeDiscard;
  final bool canDiscard;
  final bool canReturnDiscard;
  final VoidCallback onDraw;
  final VoidCallback onTakeDiscard;
  final VoidCallback onReturnDiscard;
  final VoidCallback? onDiscard;
  final VoidCallback onAutoSort;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSideDock = constraints.maxWidth >= 420;
        final actionDock = _ActionDock(
          metrics: metrics,
          pendingDiscard: pendingDiscard,
          selectedCards: selectedCards,
          openingRequirement: openingRequirement,
          humanFeedback: humanFeedback,
          canDraw: canDraw,
          canTakeDiscard: canTakeDiscard,
          canDiscard: canDiscard,
          canReturnDiscard: canReturnDiscard,
          onDraw: onDraw,
          onTakeDiscard: onTakeDiscard,
          onReturnDiscard: onReturnDiscard,
          onDiscard: onDiscard,
          onAutoSort: onAutoSort,
        );

        if (!useSideDock) {
          final preferredDockHeight = (constraints.maxHeight * 0.42)
              .clamp(56.0, 150.0)
              .toDouble();
          final maxDockHeight = constraints.maxHeight > metrics.gap
              ? constraints.maxHeight - metrics.gap
              : 0.0;
          final dockHeight = preferredDockHeight > maxDockHeight
              ? maxDockHeight
              : preferredDockHeight;

          return Column(
            children: [
              Expanded(
                child: _TableCenter(
                  compact: true,
                  stockCount: stockCount,
                  topDiscard: topDiscard,
                ),
              ),
              SizedBox(height: metrics.gap),
              SizedBox(height: dockHeight, child: actionDock),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _TableCenter(
                compact: metrics.compact,
                stockCount: stockCount,
                topDiscard: topDiscard,
              ),
            ),
            SizedBox(width: metrics.gap),
            SizedBox(width: metrics.actionDockWidth, child: actionDock),
          ],
        );
      },
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({
    required this.height,
    required this.setup,
    required this.starter,
    required this.currentSeat,
    required this.turnPhase,
    required this.onLeave,
  });

  final double height;
  final ClassicHareegSetup setup;
  final PlayerSeat starter;
  final PlayerSeat currentSeat;
  final TurnPhase turnPhase;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Leave table',
            onPressed: onLeave,
            constraints: BoxConstraints.tightFor(width: height, height: height),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 180,
            child: Text(
              AppStrings.tableTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _HeaderFact(label: 'Starter', value: _seatLabel(starter)),
                  const SizedBox(width: 8),
                  _HeaderFact(label: 'Turn', value: _seatLabel(currentSeat)),
                  const SizedBox(width: 8),
                  _HeaderFact(label: 'Phase', value: turnPhase.name),
                  const SizedBox(width: 8),
                  _HeaderFact(
                    label: 'Opening',
                    value: '${setup.openingRequirement}',
                  ),
                  const SizedBox(width: 8),
                  _HeaderFact(
                    label: 'Fifty',
                    value: '${setup.fiftyTimerSeconds}s',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderFact extends StatelessWidget {
  const _HeaderFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label $value'));
  }
}

class _SeatPanel extends StatelessWidget {
  const _SeatPanel({
    required this.seat,
    required this.count,
    this.horizontal = false,
    this.width = 104,
    this.height = 68,
  });

  final PlayerSeat seat;
  final int count;
  final bool horizontal;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final child = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(seat == PlayerSeat.south ? Icons.person : Icons.smart_toy),
        const SizedBox(height: 4),
        Text(_seatLabel(seat)),
        Text('$count cards', style: Theme.of(context).textTheme.bodySmall),
      ],
    );

    return Card(
      margin: EdgeInsets.zero,
      child: SizedBox(
        width: horizontal ? double.infinity : width,
        height: horizontal ? height : double.infinity,
        child: Center(
          child: FittedBox(fit: BoxFit.scaleDown, child: child),
        ),
      ),
    );
  }
}

class _TableCenter extends StatelessWidget {
  const _TableCenter({
    required this.compact,
    required this.stockCount,
    required this.topDiscard,
  });

  final bool compact;
  final int stockCount;
  final HareegCard? topDiscard;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(compact ? 8 : 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: _Pile(
                compact: compact,
                label: AppStrings.stock,
                value: '$stockCount',
              ),
            ),
            SizedBox(width: compact ? 4 : 8),
            Expanded(
              child: _Pile(
                compact: compact,
                label: AppStrings.meldZone,
                value: 'Empty',
              ),
            ),
            SizedBox(width: compact ? 4 : 8),
            Expanded(
              child: _Pile(
                compact: compact,
                label: AppStrings.discard,
                value: topDiscard?.label ?? 'Empty',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pile extends StatelessWidget {
  const _Pile({
    required this.compact,
    required this.label,
    required this.value,
  });

  final bool compact;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SizedBox(height: compact ? 3 : 4),
        Flexible(
          child: Container(
            width: compact ? 64 : 72,
            height: compact ? 38 : 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.secondary,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, textAlign: TextAlign.center),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionDock extends StatelessWidget {
  const _ActionDock({
    required this.metrics,
    required this.pendingDiscard,
    required this.selectedCards,
    required this.openingRequirement,
    required this.humanFeedback,
    required this.canDraw,
    required this.canTakeDiscard,
    required this.canDiscard,
    required this.canReturnDiscard,
    required this.onDraw,
    required this.onTakeDiscard,
    required this.onReturnDiscard,
    required this.onDiscard,
    required this.onAutoSort,
  });

  final _TableLayoutMetrics metrics;
  final HareegCard? pendingDiscard;
  final List<HareegCard> selectedCards;
  final int openingRequirement;
  final String? humanFeedback;
  final bool canDraw;
  final bool canTakeDiscard;
  final bool canDiscard;
  final bool canReturnDiscard;
  final VoidCallback onDraw;
  final VoidCallback onTakeDiscard;
  final VoidCallback onReturnDiscard;
  final VoidCallback? onDiscard;
  final VoidCallback onAutoSort;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(metrics.compact ? 6 : 8),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PendingDiscardBanner(card: pendingDiscard),
              if (pendingDiscard != null) SizedBox(height: metrics.gap),
              _SelectedMeldFeedback(
                cards: selectedCards,
                openingRequirement: openingRequirement,
                humanFeedback: humanFeedback,
              ),
              SizedBox(height: metrics.gap),
              _ActionBar(
                canDraw: canDraw,
                canTakeDiscard: canTakeDiscard,
                canDiscard: canDiscard,
                canReturnDiscard: canReturnDiscard,
                onDraw: onDraw,
                onTakeDiscard: onTakeDiscard,
                onReturnDiscard: onReturnDiscard,
                onDiscard: onDiscard,
                onAutoSort: onAutoSort,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.canDraw,
    required this.canTakeDiscard,
    required this.canDiscard,
    required this.canReturnDiscard,
    required this.onDraw,
    required this.onTakeDiscard,
    required this.onReturnDiscard,
    required this.onDiscard,
    required this.onAutoSort,
  });

  final bool canDraw;
  final bool canTakeDiscard;
  final bool canDiscard;
  final bool canReturnDiscard;
  final VoidCallback onDraw;
  final VoidCallback onTakeDiscard;
  final VoidCallback onReturnDiscard;
  final VoidCallback? onDiscard;
  final VoidCallback onAutoSort;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: canDraw ? onDraw : null,
          icon: const Icon(Icons.add),
          label: const Text(AppStrings.drawStock),
        ),
        FilledButton.tonalIcon(
          onPressed: canTakeDiscard ? onTakeDiscard : null,
          icon: const Icon(Icons.move_down_outlined),
          label: const Text(AppStrings.takeDiscard),
        ),
        FilledButton.icon(
          onPressed: canReturnDiscard ? onReturnDiscard : null,
          icon: const Icon(Icons.undo),
          label: const Text(AppStrings.returnDiscard),
        ),
        FilledButton.icon(
          onPressed: canDiscard ? onDiscard : null,
          icon: const Icon(Icons.remove_circle_outline),
          label: const Text(AppStrings.discardCard),
        ),
        OutlinedButton.icon(
          onPressed: onAutoSort,
          icon: const Icon(Icons.sort),
          label: const Text(AppStrings.autoSort),
        ),
      ],
    );
  }
}

class _PendingDiscardBanner extends StatelessWidget {
  const _PendingDiscardBanner({required this.card});

  final HareegCard? card;

  @override
  Widget build(BuildContext context) {
    final pending = card;
    if (pending == null) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 34,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.priority_high, size: 18),
              const SizedBox(width: 8),
              Text('${AppStrings.pendingDiscard}: ${pending.label}'),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedMeldFeedback extends StatelessWidget {
  const _SelectedMeldFeedback({
    required this.cards,
    required this.openingRequirement,
    required this.humanFeedback,
  });

  final List<HareegCard> cards;
  final int openingRequirement;
  final String? humanFeedback;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (humanFeedback != null) {
      return SizedBox(
        height: 44,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colors.error),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 18, color: colors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    humanFeedback!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final result = ClassicHareegMeldValidator.validate(cards);
    final openingText = result.value >= openingRequirement
        ? 'opening ready'
        : 'needs $openingRequirement to open';

    return SizedBox(
      height: 44,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: result.isValid ? colors.primary : colors.outline,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                result.isValid
                    ? Icons.check_circle_outline
                    : Icons.info_outline,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.isValid
                      ? '${result.message} Value ${result.value}, $openingText.'
                      : result.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HumanHand extends StatelessWidget {
  const _HumanHand({
    required this.height,
    required this.cardWidth,
    required this.cardHeight,
    required this.cards,
    required this.selectedIds,
    required this.onSelected,
  });

  final double height;
  final double cardWidth;
  final double cardHeight;
  final List<HareegCard> cards;
  final Set<String> selectedIds;
  final ValueChanged<HareegCard> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final card = cards[index];
          return _HandCard(
            width: cardWidth,
            height: cardHeight,
            card: card,
            selected: selectedIds.contains(card.id),
            onTap: () => onSelected(card),
          );
        },
      ),
    );
  }
}

class _HumanHandHeader extends StatelessWidget {
  const _HumanHandHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.person, size: 18),
        const SizedBox(width: 6),
        const Text(AppStrings.humanSeat),
        const SizedBox(width: 8),
        Text('$count cards', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _HandCard extends StatelessWidget {
  const _HandCard({
    required this.width,
    required this.height,
    required this.card,
    required this.selected,
    required this.onTap,
  });

  final double width;
  final double height;
  final HareegCard card;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF8F0DD),
          border: Border.all(
            color: selected ? colors.primary : const Color(0xFFD7BD83),
            width: selected ? 3 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          card.label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF15110E),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

String _seatLabel(PlayerSeat seat) {
  return switch (seat) {
    PlayerSeat.south => AppStrings.humanSeat,
    PlayerSeat.east => 'CPU East',
    PlayerSeat.north => 'CPU North',
    PlayerSeat.west => 'CPU West',
  };
}
