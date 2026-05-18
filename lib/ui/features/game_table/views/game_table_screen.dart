import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../data/persistence/match_repository.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_round.dart';
import '../../../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../domain/classic_hareeg/rules/meld_validator.dart';
import '../../../../l10n/app_strings.dart';

/// First playable Classic Hareeg table slice.
class GameTableScreen extends StatefulWidget {
  /// Creates a table screen from setup values.
  const GameTableScreen({
    required this.setup,
    required this.matchRepository,
    this.initialSnapshot,
    super.key,
  });

  /// Setup values used to deal the round.
  final ClassicHareegSetup setup;

  /// Active match persistence.
  final MatchRepository matchRepository;

  /// Saved match state to resume instead of dealing.
  final ClassicHareegMatchSnapshot? initialSnapshot;

  @override
  State<GameTableScreen> createState() => _GameTableScreenState();
}

class _GameTableScreenState extends State<GameTableScreen> {
  late Map<PlayerSeat, List<HareegCard>> _hands;
  late List<HareegCard> _stock;
  late List<HareegCard> _discardPile;
  late PlayerSeat _starter;
  late PlayerSeat _currentSeat;
  late TurnPhase _turnPhase;
  final _selectedCards = <HareegCard>[];
  HareegCard? _pendingDiscard;

  @override
  void initState() {
    super.initState();
    AppOrientation.useLandscape();
    final snapshot = widget.initialSnapshot;
    if (snapshot == null) {
      _deal();
    } else {
      _restoreSnapshot(snapshot);
    }
    _advanceCpuTurnsToHuman();
    _saveMatch();
  }

  @override
  void dispose() {
    AppOrientation.usePortrait();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canAct = _currentSeat == PlayerSeat.south;
    final needsDraw = _turnPhase == TurnPhase.draw;
    final canDiscard =
        canAct &&
        _turnPhase == TurnPhase.action &&
        _selectedCards.length == 1 &&
        _pendingDiscard == null;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              _TableHeader(
                setup: widget.setup,
                starter: _starter,
                currentSeat: _currentSeat,
                turnPhase: _turnPhase,
                onLeave: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  children: [
                    _SeatPanel(
                      seat: PlayerSeat.west,
                      count: _count(PlayerSeat.west),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        children: [
                          _SeatPanel(
                            seat: PlayerSeat.north,
                            count: _count(PlayerSeat.north),
                            horizontal: true,
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _TableCenter(
                              stockCount: _stock.length,
                              topDiscard: _discardPile.isEmpty
                                  ? null
                                  : _discardPile.last,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _PendingDiscardBanner(card: _pendingDiscard),
                          const SizedBox(height: 8),
                          _SelectedMeldFeedback(
                            cards: _selectedCards,
                            openingRequirement: widget.setup.openingRequirement,
                          ),
                          const SizedBox(height: 8),
                          _ActionBar(
                            canDraw:
                                canAct &&
                                needsDraw &&
                                _stock.isNotEmpty &&
                                _pendingDiscard == null,
                            canTakeDiscard:
                                canAct &&
                                needsDraw &&
                                _discardPile.isNotEmpty &&
                                _pendingDiscard == null,
                            canDiscard: canDiscard,
                            canReturnDiscard:
                                canAct &&
                                _pendingDiscard != null &&
                                _stock.isNotEmpty,
                            onDraw: _drawStock,
                            onTakeDiscard: _takeDiscard,
                            onReturnDiscard: _returnPendingDiscardAndDraw,
                            onDiscard: _discardSelected,
                            onAutoSort: _sortHumanHand,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SeatPanel(
                      seat: PlayerSeat.east,
                      count: _count(PlayerSeat.east),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _HumanHandHeader(count: _count(PlayerSeat.south)),
              const SizedBox(height: 6),
              _HumanHand(
                cards: _hands[PlayerSeat.south] ?? const [],
                selected: _selectedCards,
                onSelected: (card) {
                  setState(() {
                    if (_selectedCards.contains(card)) {
                      _selectedCards.remove(card);
                    } else {
                      _selectedCards.add(card);
                    }
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _deal() {
    final round = ClassicHareegRound.deal(setup: widget.setup);
    _hands = {
      for (final entry in round.hands.entries)
        entry.key: List<HareegCard>.of(entry.value),
    };
    _stock = List<HareegCard>.of(round.stock);
    _discardPile = List<HareegCard>.of(round.discardPile);
    _starter = round.starter;
    _currentSeat = round.currentSeat;
    _turnPhase = round.turnPhase;
    _pendingDiscard = null;
  }

  void _restoreSnapshot(ClassicHareegMatchSnapshot snapshot) {
    _hands = {
      for (final entry in snapshot.hands.entries)
        entry.key: List<HareegCard>.of(entry.value),
    };
    _stock = List<HareegCard>.of(snapshot.stock);
    _discardPile = List<HareegCard>.of(snapshot.discardPile);
    _starter = snapshot.starter;
    _currentSeat = snapshot.currentSeat;
    _turnPhase = snapshot.turnPhase;
    _pendingDiscard = snapshot.pendingDiscard;
    _selectedCards.clear();
    if (_pendingDiscard != null) {
      _selectedCards.add(_pendingDiscard!);
    }
  }

  int _count(PlayerSeat seat) {
    return _hands[seat]?.length ?? 0;
  }

  void _drawStock() {
    if (_stock.isEmpty) {
      return;
    }
    setState(() {
      final card = _stock.removeLast();
      _hands[_currentSeat] = [...?_hands[_currentSeat], card];
      _turnPhase = TurnPhase.action;
    });
    _saveMatch();
  }

  void _takeDiscard() {
    if (_discardPile.isEmpty) {
      return;
    }
    setState(() {
      final card = _discardPile.removeLast();
      _hands[_currentSeat] = [...?_hands[_currentSeat], card];
      _turnPhase = TurnPhase.action;
      _pendingDiscard = card;
      _selectedCards
        ..clear()
        ..add(card);
    });
    _saveMatch();
  }

  void _returnPendingDiscardAndDraw() {
    final pending = _pendingDiscard;
    if (pending == null || _stock.isEmpty) {
      return;
    }

    setState(() {
      final hand = List<HareegCard>.of(_hands[_currentSeat] ?? const [])
        ..removeWhere((card) => card.id == pending.id);
      final drawn = _stock.removeLast();
      _hands[_currentSeat] = [...hand, drawn];
      _discardPile.add(pending);
      _pendingDiscard = null;
      _selectedCards.clear();
      _turnPhase = TurnPhase.action;
    });
    _saveMatch();
  }

  void _discardSelected() {
    if (_selectedCards.length != 1) {
      return;
    }

    final selected = _selectedCards.single;
    setState(() {
      final hand = List<HareegCard>.of(_hands[PlayerSeat.south] ?? const []);
      hand.removeWhere((card) => card.id == selected.id);
      _hands[PlayerSeat.south] = hand;
      _discardPile.add(selected);
      _selectedCards.clear();
      _pendingDiscard = null;
      _currentSeat = _currentSeat.nextAntiClockwise;
      _turnPhase = TurnPhase.draw;
      _advanceCpuTurnsToHuman();
    });
    _saveMatch();
  }

  void _sortHumanHand() {
    setState(() {
      final hand = List<HareegCard>.of(_hands[PlayerSeat.south] ?? const []);
      hand.sort(_compareCards);
      _hands[PlayerSeat.south] = hand;
    });
    _saveMatch();
  }

  ClassicHareegMatchSnapshot _snapshot() {
    return ClassicHareegMatchSnapshot(
      setup: widget.setup,
      hands: {
        for (final entry in _hands.entries)
          entry.key: List<HareegCard>.of(entry.value),
      },
      stock: List<HareegCard>.of(_stock),
      discardPile: List<HareegCard>.of(_discardPile),
      starter: _starter,
      currentSeat: _currentSeat,
      turnPhase: _turnPhase,
      pendingDiscard: _pendingDiscard,
      savedAt: DateTime.now().toUtc(),
    );
  }

  void _saveMatch() {
    widget.matchRepository.saveActiveMatch(_snapshot());
  }

  void _advanceCpuTurnsToHuman() {
    var guard = 0;
    while (_currentSeat != PlayerSeat.south &&
        guard < PlayerSeat.values.length) {
      _playCpuTurn();
      guard += 1;
    }
    _selectedCards.clear();
    _pendingDiscard = null;
  }

  void _playCpuTurn() {
    if (_turnPhase == TurnPhase.draw) {
      if (_stock.isNotEmpty) {
        _hands[_currentSeat] = [...?_hands[_currentSeat], _stock.removeLast()];
      } else if (_discardPile.isNotEmpty) {
        _hands[_currentSeat] = [
          ...?_hands[_currentSeat],
          _discardPile.removeLast(),
        ];
      }
      _turnPhase = TurnPhase.action;
    }

    final hand = List<HareegCard>.of(_hands[_currentSeat] ?? const []);
    if (hand.isEmpty) {
      _currentSeat = _currentSeat.nextAntiClockwise;
      _turnPhase = TurnPhase.draw;
      return;
    }

    final discardIndex = hand.lastIndexWhere((card) => !card.isJoker);
    final selectedIndex = discardIndex == -1 ? hand.length - 1 : discardIndex;
    final discarded = hand.removeAt(selectedIndex);
    _hands[_currentSeat] = hand;
    _discardPile.add(discarded);
    _currentSeat = _currentSeat.nextAntiClockwise;
    _turnPhase = TurnPhase.draw;
  }

  int _compareCards(HareegCard left, HareegCard right) {
    final leftIdentity = left.effectiveIdentity;
    final rightIdentity = right.effectiveIdentity;
    if (leftIdentity == null && rightIdentity == null) {
      return left.id.compareTo(right.id);
    }
    if (leftIdentity == null) {
      return 1;
    }
    if (rightIdentity == null) {
      return -1;
    }

    final suitCompare = leftIdentity.suit.index.compareTo(
      rightIdentity.suit.index,
    );
    if (suitCompare != 0) {
      return suitCompare;
    }
    return leftIdentity.rank.order.compareTo(rightIdentity.rank.order);
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({
    required this.setup,
    required this.starter,
    required this.currentSeat,
    required this.turnPhase,
    required this.onLeave,
  });

  final ClassicHareegSetup setup;
  final PlayerSeat starter;
  final PlayerSeat currentSeat;
  final TurnPhase turnPhase;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Leave table',
            onPressed: onLeave,
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
  });

  final PlayerSeat seat;
  final int count;
  final bool horizontal;

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
      child: SizedBox(
        width: horizontal ? double.infinity : 104,
        height: horizontal ? 68 : double.infinity,
        child: Center(
          child: FittedBox(fit: BoxFit.scaleDown, child: child),
        ),
      ),
    );
  }
}

class _TableCenter extends StatelessWidget {
  const _TableCenter({required this.stockCount, required this.topDiscard});

  final int stockCount;
  final HareegCard? topDiscard;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _Pile(label: AppStrings.stock, value: '$stockCount'),
            const _Pile(label: AppStrings.meldZone, value: 'Empty'),
            _Pile(
              label: AppStrings.discard,
              value: topDiscard?.label ?? 'Empty',
            ),
          ],
        ),
      ),
    );
  }
}

class _Pile extends StatelessWidget {
  const _Pile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Container(
          width: 72,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.secondary),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(value, textAlign: TextAlign.center),
        ),
      ],
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
  final VoidCallback onDiscard;
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
  });

  final List<HareegCard> cards;
  final int openingRequirement;

  @override
  Widget build(BuildContext context) {
    final result = ClassicHareegMeldValidator.validate(cards);
    final openingText = result.value >= openingRequirement
        ? 'opening ready'
        : 'needs $openingRequirement to open';
    final colors = Theme.of(context).colorScheme;

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
    required this.cards,
    required this.selected,
    required this.onSelected,
  });

  final List<HareegCard> cards;
  final List<HareegCard> selected;
  final ValueChanged<HareegCard> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final card = cards[index];
          return _HandCard(
            card: card,
            selected: selected.contains(card),
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
    required this.card,
    required this.selected,
    required this.onTap,
  });

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
        width: 52,
        height: 76,
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
