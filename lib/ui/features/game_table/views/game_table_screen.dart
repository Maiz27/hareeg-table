import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/app_routes.dart';
import '../../../../app/app_orientation.dart';
import '../../../../cpu/classic_hareeg/classic_hareeg_cpu_turn_runner.dart';
import '../../../../cpu/classic_hareeg/cpu_strategy.dart';
import '../../../../data/persistence/match_repository.dart';
import '../../../../data/persistence/preferences_repository.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_round.dart';
import '../../../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../domain/classic_hareeg/rules/match_progression_rules.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_state.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/cards/card_view.dart';
import '../../../core/audio/table_audio.dart';
import '../../../core/aids/table_aids.dart';
import '../../../core/haptics/table_haptics.dart';
import '../../../core/motion/motion_speed.dart';
import '../../../core/scopes/app_scopes.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../animations/deal_choreography.dart';
import '../table_interaction_adapter.dart';
import '../widgets/pause_overlay.dart';
import '../widgets/physical_table_playfield.dart';
import '../widgets/score_overlay.dart';
import '../widgets/south_seat.dart';
import '../widgets/table_background.dart';

/// Live Classic Hareeg table.
///
/// Owns the [ClassicHareegGameController] and orchestrates every player /
/// CPU action through it. Visual / motion / aid / theme / haptics
/// preferences flow in via [preferences] from the app shell so the same
/// surface keeps responding to settings changes made from the pause overlay.
class GameTableScreen extends StatefulWidget {
  /// Creates a live table.
  const GameTableScreen({
    super.key,
    required this.setup,
    required this.matchRepository,
    required this.preferences,
    required this.onPreferencesChanged,
    this.initialSnapshot,
    this.cpuStrategy = const ClassicHareegCpuStrategy(),
  });

  /// Setup used to deal the round.
  final ClassicHareegSetup setup;

  /// Active match persistence.
  final MatchRepository matchRepository;

  /// Player preferences (motion, haptics, aids, theme).
  final GamePreferences preferences;

  /// Called by the pause overlay when a preference is toggled mid-match.
  final ValueChanged<GamePreferences> onPreferencesChanged;

  /// Saved snapshot to resume (else deal a fresh round).
  final ClassicHareegMatchSnapshot? initialSnapshot;

  /// CPU strategy used for non-human seats.
  final CpuStrategy cpuStrategy;

  @override
  State<GameTableScreen> createState() => _GameTableScreenState();
}

class _GameTableScreenState extends State<GameTableScreen>
    with TickerProviderStateMixin {
  static const _cpuActionLimit = 64;
  static const _successFeedbackDuration = Duration(milliseconds: 1400);
  static const _errorFeedbackDuration = Duration(milliseconds: 2400);
  static const _roundResultDisplayDuration = Duration(milliseconds: 2400);

  late ClassicHareegGameController _controller;
  final _selectedCardIds = <String>{};
  bool _isCpuRunning = false;
  // Set while a human action's pre-apply flight/sound is in flight and the
  // controller hasn't applied the move yet. Used to lock the UI so a second
  // tap doesn't queue a parallel action against the same controller state.
  bool _isHumanActionPending = false;
  bool _scoreOpen = false;
  bool _pauseOpen = false;
  bool _fiftyPulse = false;
  String? _humanFeedback;
  bool _humanFeedbackIsError = false;
  Timer? _fiftyTicker;
  Timer? _feedbackTimer;
  Timer? _roundAdvanceTimer;
  _CardFlight? _cardFlight;
  DealChoreography? _dealChoreography;
  bool _pendingDealBuild = false;
  HareegCard? _inspectedCard;
  _RoundResultPresentation? _roundResultPresentation;
  int _flightSerial = 0;

  /// Stable display order for the south hand, indexed by card id. The engine
  /// hand list reorders freely as cards leave/enter; the player's visual
  /// order persists so freshly-drawn cards always land at the right end
  /// (regardless of the Settings `autoSort` preset, which only sorts on
  /// initial deal).
  late List<String> _displayOrder;

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
    _resetDisplayOrder();
    if (snapshot == null) {
      _pendingDealBuild = true;
    }
    _debugTableLog(
      'init snapshot=${snapshot != null} current=${_controller.currentSeat.name} '
      'phase=${_controller.turnPhase} stock=${_controller.stockCount} '
      'discard=${_controller.discardPile.length} '
      'counts=${_debugSeatCounts(_controller)}',
    );
    _ensureFiftyTicker();
    _scheduleTurnFlow();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // [DealChoreography] reads [MotionScope] and [AudioScope], which are
    // inherited widgets — those reads aren't safe in [initState]. Build the
    // first deal here, the first time dependencies are available.
    if (_pendingDealBuild && _dealChoreography == null) {
      _pendingDealBuild = false;
      _dealChoreography = _buildDealChoreography();
    }
  }

  @override
  void dispose() {
    _fiftyTicker?.cancel();
    _fiftyTicker = null;
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
    _roundAdvanceTimer?.cancel();
    _roundAdvanceTimer = null;
    _dealChoreography?.dispose();
    _dealChoreography = null;
    AppOrientation.usePortrait();
    super.dispose();
  }

  void _returnToMainMenu() {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
  }

  void _resetDisplayOrder() {
    final initialHand = _controller.handFor(PlayerSeat.south);
    final initialSort = widget.preferences.autoSort
        ? HandSortMode.byRank
        : HandSortMode.manual;
    _displayOrder = HandSorting.sort(
      initialHand,
      initialSort,
    ).map((card) => card.id).toList();
  }

  void _ensureFiftyTicker() {
    final fiftyVisible = _controller.fiftySecondsRemaining != null;
    if (fiftyVisible && _fiftyTicker == null) {
      _fiftyTicker = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted) return;
        if (_controller.fiftySecondsRemaining == null) {
          _fiftyTicker?.cancel();
          _fiftyTicker = null;
          setState(() {});
          return;
        }
        setState(() {});
      });
    } else if (!fiftyVisible && _fiftyTicker != null) {
      _fiftyTicker?.cancel();
      _fiftyTicker = null;
    }
  }

  void _scheduleTurnFlow() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _playOpeningDealIfNeeded();
      if (!mounted) return;
      final didPersistOrNavigate = await _runCpuTurns();
      if (!didPersistOrNavigate && mounted) {
        await _persistAndMaybeFinish();
      }
    });
  }

  DealSequence _buildDealSequence() {
    final orderedSouth = _orderedSouthHand();
    final southByIndex = {
      for (var i = 0; i < orderedSouth.length; i++) i: orderedSouth[i],
    };
    final activeSeats = _controller.activeSeats;
    final dealOrder = _dealOrderForOpening(activeSeats);
    final finalCounts = {
      for (final seat in PlayerSeat.values)
        seat: _controller.cardCountFor(seat),
    };
    final dealtBySeat = {for (final seat in PlayerSeat.values) seat: 0};
    final steps = <DealStep>[];
    final maxCount = finalCounts.values.fold<int>(
      0,
      (max, count) => math.max(max, count),
    );

    for (var slot = 0; slot < maxCount; slot += 1) {
      for (final seat in dealOrder) {
        final targetCount = finalCounts[seat] ?? 0;
        if (slot >= targetCount) {
          continue;
        }
        final seatIndex = dealtBySeat[seat]!;
        final card = seat == PlayerSeat.south
            ? southByIndex[seatIndex] ?? _backSeed(steps.length)
            : _backSeed(steps.length);
        steps.add(
          DealStep(
            orderIndex: steps.length,
            seat: seat,
            card: card,
            faceDown: seat != PlayerSeat.south,
            endHandSlot: SeatHandFlightSlot(
              seat: seat,
              index: seatIndex,
              count: seatIndex + 1,
            ),
          ),
        );
        dealtBySeat[seat] = seatIndex + 1;
      }
    }

    return DealSequence(
      steps: steps,
      finalStockCount: _controller.stockCount,
      orderedSouthCards: orderedSouth,
    );
  }

  DealChoreography _buildDealChoreography() {
    return DealChoreography(
      vsync: this,
      audio: _audio,
      motion: MotionScope.of(context),
      sequence: _buildDealSequence(),
    );
  }

  List<PlayerSeat> _dealOrderForOpening(List<PlayerSeat> activeSeats) {
    if (activeSeats.isEmpty) {
      return const [];
    }
    final order = <PlayerSeat>[];
    var seat = _controller.starter;
    do {
      if (activeSeats.contains(seat)) {
        order.add(seat);
      }
      seat = seat.nextAntiClockwise;
    } while (seat != _controller.starter);
    return order;
  }

  Future<void> _playOpeningDealIfNeeded() async {
    final choreography = _dealChoreography;
    if (choreography == null || choreography.sequence.steps.isEmpty || !mounted) {
      return;
    }
    choreography.progress.addListener(_onDealProgress);
    setState(() {});
    try {
      await choreography.play();
    } finally {
      choreography.progress.removeListener(_onDealProgress);
    }
    if (!mounted || !identical(_dealChoreography, choreography)) {
      return;
    }
    choreography.dispose();
    setState(() {
      _dealChoreography = null;
    });
  }

  void _onDealProgress() {
    if (mounted) {
      setState(() {});
    }
  }

  DealFrame? _openingDealFrame(List<HareegCard> fallbackSouthCards) {
    final choreography = _dealChoreography;
    if (choreography == null) {
      return null;
    }
    return choreography.frameAt(
      fallbackCounts: {
        for (final seat in PlayerSeat.values)
          seat: _controller.cardCountFor(seat),
      },
      fallbackSouthCards: fallbackSouthCards,
    );
  }

  TableHaptics get _haptics => HapticsScope.of(context);

  TableAudio get _audio => AudioScope.of(context);

  bool get _isOpeningDealRunning => _dealChoreography != null;

  Duration _scaledDelay(Duration base) => MotionScope.of(context).scale(base);

  Duration get _cpuReadPause => widget.preferences.fastCpuTurns
      ? _scaledDelay(TableMotion.fastCpuReadPause)
      : _scaledDelay(TableMotion.cpuReadPause);

  Duration get _cpuBetweenActionPause => widget.preferences.fastCpuTurns
      ? _scaledDelay(TableMotion.fastCpuActionGap)
      : _scaledDelay(TableMotion.cpuMove);

  Duration get _cpuFlightDuration => widget.preferences.fastCpuTurns
      ? _scaledDelay(TableMotion.fastCpuFlight)
      : _scaledDelay(TableMotion.cpuFlight);

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final humanSeat = PlayerSeat.south;
    final isHumanTurn =
        _controller.currentSeat == humanSeat &&
        !_isCpuRunning &&
        !_isOpeningDealRunning &&
        !_isHumanActionPending;
    final controlActions = isHumanTurn
        ? _controller.controlActionIdsFor(humanSeat)
        : const <String>[];
    final pending = _controller.pendingDiscard;
    final theme = CardThemeScope.of(context);
    final aids = AidsScope.of(context);
    final jokerAidsEnabled = _jokerAidsEnabledFor(_controller.setup);
    final jokerDisplay = !jokerAidsEnabled
        ? JokerDisplay.unassigned
        : widget.preferences.memoryJokerDisplay
        ? JokerDisplay.memoryReveal
        : JokerDisplay.assisted;
    final southCards = _orderedSouthHand();
    final openingDealFrame = _openingDealFrame(southCards);
    final visibleSouthCards = openingDealFrame?.southCards ?? southCards;
    final visibleCardCounts =
        openingDealFrame?.cardCounts ??
        {
          for (final seat in PlayerSeat.values)
            seat: _controller.cardCountFor(seat),
        };
    final visibleStockCount =
        openingDealFrame?.stockCount ?? _controller.stockCount;
    final tableInteraction = _tableInteraction(southCards);
    final meldSuggestions = aids.showsMeldPicker
        ? _meldSuggestions(tableInteraction)
        : const <TableMeldSuggestion>[];
    final meldValidation = isHumanTurn && _selectedCardIds.isNotEmpty
        ? _controller.singleMeldValidationFor(
            humanSeat,
            _selectedCardIds.toList(),
          )
        : null;
    final primaryMeldAction = isHumanTurn
        ? tableInteraction.selectedMeldActionId()
        : null;
    final canPlayMeld = primaryMeldAction != null;
    final hasOpened = _controller.openingState.hasOpened(humanSeat);
    final meldCtaValue = canPlayMeld && meldValidation?.isValid == true
        ? meldValidation?.value
        : null;

    final body = TableBackground(
      surface: widget.preferences.tableSurfaceTheme,
      child: JokerDisplayScope(
        display: jokerDisplay,
        child: Stack(
          children: [
            PhysicalTablePlayfield(
              theme: theme,
              stockCount: visibleStockCount,
              discardPile: _controller.discardPile,
              topDiscard: _controller.topDiscard,
              pendingDiscard: pending,
              cardCounts: visibleCardCounts,
              tableMelds: {
                for (final seat in PlayerSeat.values)
                  seat: _controller.tableMeldsFor(seat),
              },
              southCards: visibleSouthCards,
              selectedIds: _selectedCardIds,
              onCardTap: _toggleSelectedCard,
              onCardLongPress: _showCardInspect,
              onReorderHand: _reorderHand,
              canDiscardCard: tableInteraction.canDropCardToDiscard,
              canPlayCardOnTable: tableInteraction.canDropCardToTable,
              canPlaceMeldOnTable: tableInteraction.canPlaceNewMeldOnTable,
              canPlayCardOnMeld: tableInteraction.canDropCardToMeld,
              canRetractMeld: (owner, meldIndex) =>
                  controlActions.contains(
                    ClassicHareegActionIds.returnOpeningMelds,
                  ) &&
                  _controller.canReturnTablePlayFromMeld(owner, meldIndex),
              onDiscardCard: (card) => unawaited(_dropCardToDiscard(card)),
              onPlayCardOnTable: (card) => unawaited(_dropCardToTable(card)),
              onPlayCardOnMeld: (card, owner, meldIndex) =>
                  unawaited(_dropCardToMeld(card, owner, meldIndex)),
              onRetractMeld: (owner, meldIndex) => unawaited(
                _runHumanAction(
                  ClassicHareegActionIds.returnTablePlayActionId(
                    owner: owner,
                    meldIndex: meldIndex,
                  ),
                ),
              ),
              canDrawStock: controlActions.contains(
                ClassicHareegActionIds.drawStock,
              ),
              canTakeDiscard: controlActions.contains(
                ClassicHareegActionIds.takeDiscard,
              ),
              canReturnDiscard: controlActions.contains(
                ClassicHareegActionIds.returnPendingDiscard,
              ),
              canClaimFifty: controlActions.contains(
                ClassicHareegActionIds.claimFifty,
              ),
              canReturnOpeningMelds: controlActions.contains(
                ClassicHareegActionIds.returnOpeningMelds,
              ),
              onDrawStock: () =>
                  unawaited(_runHumanAction(ClassicHareegActionIds.drawStock)),
              onTakeDiscard: () => unawaited(
                _runHumanAction(ClassicHareegActionIds.takeDiscard),
              ),
              onReturnDiscard: () => unawaited(
                _runHumanAction(ClassicHareegActionIds.returnPendingDiscard),
              ),
              onClaimFifty: () => unawaited(_claimFifty()),
              onReturnOpeningMelds: () => unawaited(
                _runHumanAction(ClassicHareegActionIds.returnOpeningMelds),
              ),
              fiftySecondsRemaining: _controller.fiftySecondsRemaining,
              fiftyTotalSeconds: _controller.setup.fiftyTimerSeconds,
              fiftyPulse: _fiftyPulse,
              meldRequirement: _controller.openingState.currentRequirement,
              meldSelectionValue: meldCtaValue,
              meldSelectionValid: canPlayMeld,
              meldSelectionHasOpened: hasOpened,
              onPlaySelectedMeld: primaryMeldAction == null
                  ? null
                  : () => unawaited(_playSelectedMeld(primaryMeldAction)),
              meldSuggestions: meldSuggestions,
              showMeldSuggestions: aids.showsMeldPicker,
              onMeldSuggestion: (actionId) {
                unawaited(_runHumanAction(actionId));
              },
              isHumanTurn: isHumanTurn,
              isCpuRunning: _isCpuRunning,
              currentSeat: _controller.currentSeat,
              activeSeats: _controller.activeSeats.toSet(),
            ),
            if (_dealChoreography != null)
              Positioned.fill(
                // Isolate the deal overlay's per-frame repaints (57 flight
                // cards rebuilding on every controller tick) from the rest
                // of the table so unrelated widgets don't end up in the
                // overlay's dirty rect.
                child: RepaintBoundary(
                  child: _OpeningDealOverlay(
                    sequence: _dealChoreography!.sequence,
                    progress: _dealChoreography!.progress.value,
                    theme: theme,
                    flightDuration: _dealChoreography!.flightDuration,
                    stagger: _dealChoreography!.stagger,
                  ),
                ),
              ),
            LayoutBuilder(
              builder: (context, viewport) {
                // Score / pause sit just inside the safe-area corners with a
                // small breathing margin so they don't graze the screen edge.
                // Sizes scale with viewport width so tablets don't end up
                // with tiny phone-sized controls.
                final safe = MediaQuery.paddingOf(context);
                final isLarge = viewport.maxWidth >= 900;
                final isTablet = viewport.maxWidth >= 720;
                final buttonSize = isLarge
                    ? 44.0
                    : isTablet
                    ? 38.0
                    : 30.0;
                final iconSize = isLarge
                    ? 24.0
                    : isTablet
                    ? 21.0
                    : 17.0;
                final edgeInset = isLarge
                    ? 18.0
                    : isTablet
                    ? 14.0
                    : 10.0;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: safe.top + edgeInset,
                      left: safe.left + edgeInset,
                      child: _TableChromeButton(
                        tooltip: strings.scores,
                        icon: Icons.bar_chart_rounded,
                        diameter: buttonSize,
                        iconSize: iconSize,
                        onPressed: () => setState(() => _scoreOpen = true),
                      ),
                    ),
                    Positioned(
                      top: safe.top + edgeInset,
                      right: safe.right + edgeInset,
                      child: _TableChromeButton(
                        tooltip: strings.pauseTable,
                        icon: Icons.pause_rounded,
                        diameter: buttonSize,
                        iconSize: iconSize,
                        onPressed: () => setState(() => _pauseOpen = true),
                      ),
                    ),
                    if (_humanFeedback != null)
                      Positioned(
                        top:
                            safe.top +
                            edgeInset +
                            math.max(0.0, (buttonSize - 34) / 2),
                        left: safe.left + edgeInset + buttonSize + 14,
                        right: safe.right + edgeInset + buttonSize + 14,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: IgnorePointer(
                            child: _FeedbackChip(
                              message: _humanFeedback!,
                              isError: _humanFeedbackIsError,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            if (_cardFlight != null)
              Positioned.fill(
                child: _CardFlightOverlay(
                  key: ValueKey(_cardFlight!.serial),
                  flight: _cardFlight!,
                  theme: theme,
                  duration: _scaledDelay(const Duration(milliseconds: 230)),
                ),
              ),
          ],
        ),
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _returnToMainMenu();
      },
      child: Scaffold(
        body: Stack(
          children: [
            body,
            _AnimatedOverlaySlot(
              visible: _scoreOpen,
              overlayKey: 'score-overlay',
              duration: _scaledDelay(const Duration(milliseconds: 180)),
              child: ScoreOverlay(
                scores: _controller.scores,
                activeSeats: _controller.activeSeats,
                starter: _controller.starter,
                currentSeat: _controller.currentSeat,
                roundNumber: _controller.roundNumber,
                onClose: () => setState(() => _scoreOpen = false),
              ),
            ),
            _AnimatedOverlaySlot(
              visible: _pauseOpen,
              overlayKey: 'pause-overlay',
              duration: _scaledDelay(const Duration(milliseconds: 180)),
              child: PauseOverlay(
                aids: widget.preferences.tableAids,
                motionSpeed: widget.preferences.motionSpeed,
                fastCpuTurns: widget.preferences.fastCpuTurns,
                hapticsEnabled: widget.preferences.hapticsEnabled,
                soundEnabled: widget.preferences.soundEnabled,
                highContrastCards: widget.preferences.highContrastCards,
                onAidsChanged: (v) => widget.onPreferencesChanged(
                  widget.preferences.copyWith(tableAids: v),
                ),
                onMotionSpeedChanged: (v) => widget.onPreferencesChanged(
                  widget.preferences.copyWith(motionSpeed: v),
                ),
                onFastCpuTurnsChanged: (v) => widget.onPreferencesChanged(
                  widget.preferences.copyWith(fastCpuTurns: v),
                ),
                onHapticsChanged: (v) => widget.onPreferencesChanged(
                  widget.preferences.copyWith(hapticsEnabled: v),
                ),
                onSoundChanged: (v) => widget.onPreferencesChanged(
                  widget.preferences.copyWith(soundEnabled: v),
                ),
                onHighContrastCardsChanged: (v) => widget.onPreferencesChanged(
                  widget.preferences.copyWith(highContrastCards: v),
                ),
                onResume: () => setState(() => _pauseOpen = false),
                onLeave: _returnToMainMenu,
              ),
            ),
            if (_inspectedCard != null)
              _CardInspectOverlay(
                card: _inspectedCard!,
                theme: theme,
                aids: aids,
                jokerAidsEnabled: jokerAidsEnabled,
                onClose: () => setState(() => _inspectedCard = null),
              ),
            _AnimatedOverlaySlot(
              visible: _roundResultPresentation != null,
              overlayKey: 'round-result-overlay-slot',
              duration: _scaledDelay(const Duration(milliseconds: 220)),
              child: _roundResultPresentation == null
                  ? const SizedBox.shrink()
                  : _RoundResultOverlay(
                      presentation: _roundResultPresentation!,
                      onContinueNow:
                          _roundResultPresentation!.nextSnapshot == null
                          ? null
                          : () => _advanceToNextRound(
                              _roundResultPresentation!.nextSnapshot!,
                            ),
                      onReturnToMenu:
                          _roundResultPresentation!.progress.matchWinner == null
                          ? null
                          : _returnToMainMenu,
                      onDismiss: () {
                        setState(() => _roundResultPresentation = null);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns the human hand in the player's chosen display order.
  ///
  /// Reconciles `_displayOrder` against the controller's hand each build:
  /// cards no longer in hand drop off, freshly-drawn cards are appended to
  /// the right end so the player can see their newest card. Players may
  /// drag-reorder freely after that — sort never reasserts mid-round.
  List<HareegCard> _orderedSouthHand() {
    final hand = _controller.handFor(PlayerSeat.south);
    final byId = {for (final card in hand) card.id: card};
    final ordered = <HareegCard>[];
    final seen = <String>{};
    // Keep existing ordering for cards still in the hand.
    final keptOrder = <String>[];
    for (final id in _displayOrder) {
      if (byId.containsKey(id) && seen.add(id)) {
        keptOrder.add(id);
        ordered.add(byId[id]!);
      }
    }
    // Append any new cards (e.g., just drawn) at the right end.
    for (final card in hand) {
      if (!seen.contains(card.id)) {
        keptOrder.add(card.id);
        ordered.add(card);
      }
    }
    if (!_displayOrderMatches(keptOrder)) {
      _displayOrder = keptOrder;
    }
    return ordered;
  }

  bool _displayOrderMatches(List<String> other) {
    if (other.length != _displayOrder.length) return false;
    for (var i = 0; i < other.length; i++) {
      if (other[i] != _displayOrder[i]) return false;
    }
    return true;
  }

  void _reorderHand(HareegCard card, int targetIndex) {
    final src = _displayOrder.indexOf(card.id);
    if (src < 0 || src == targetIndex) return;
    setState(() {
      _displayOrder.removeAt(src);
      final insertAt = targetIndex > src ? targetIndex - 1 : targetIndex;
      _displayOrder.insert(
        insertAt.clamp(0, _displayOrder.length).toInt(),
        card.id,
      );
    });
  }

  ClassicHareegTableInteractionAdapter _tableInteraction([
    List<HareegCard>? southCards,
  ]) {
    return ClassicHareegTableInteractionAdapter(
      reader: ClassicHareegControllerTableInteractionReader(_controller),
      seat: PlayerSeat.south,
      selectedCardIds: _selectedCardIds,
      handCards: southCards ?? _orderedSouthHand(),
      inputLocked:
          _isCpuRunning || _isOpeningDealRunning || _isHumanActionPending,
    );
  }

  Future<void> _dropCardToDiscard(HareegCard card) async {
    if (_isCpuRunning || _isOpeningDealRunning || _isHumanActionPending) return;
    await _runTableInteraction(_tableInteraction().resolveDiscard(card));
  }

  Future<void> _dropCardToTable(HareegCard card) async {
    if (_isCpuRunning || _isOpeningDealRunning || _isHumanActionPending) return;
    await _runTableInteraction(_tableInteraction().resolveTableDrop(card));
  }

  Future<void> _dropCardToMeld(
    HareegCard card,
    PlayerSeat owner,
    int meldIndex,
  ) async {
    if (_isCpuRunning || _isOpeningDealRunning || _isHumanActionPending) return;
    await _runTableInteraction(
      _tableInteraction().resolveMeldDrop(card, owner, meldIndex),
    );
  }

  Future<void> _runTableInteraction(
    TableInteractionResolution resolution,
  ) async {
    final actionId = resolution.actionId;
    if (actionId != null) {
      await _runHumanAction(actionId, playFlight: false);
      return;
    }
    _showInvalidFeedback(
      resolution.failureMessage ?? 'That move is not legal.',
    );
  }

  Future<void> _playSelectedMeld(String fallbackActionId) async {
    final cardIds = _selectedCardIds.toList(growable: false);
    final jokerChoices = _tableInteraction().jokerChoicesForCardIds(cardIds);
    if (jokerChoices.length > 1) {
      final choice = await _showJokerChoiceDialog(jokerChoices);
      if (!mounted || choice == null) return;
      await _runHumanAction(choice.actionId);
      return;
    }

    await _runHumanAction(fallbackActionId);
  }

  Future<TableInteractionJokerChoice?> _showJokerChoiceDialog(
    List<TableInteractionJokerChoice> choices,
  ) {
    final theme = CardThemeScope.of(context);
    return showDialog<TableInteractionJokerChoice>(
      context: context,
      builder: (dialogContext) {
        final strings = dialogContext.strings;
        return AlertDialog(
          key: const ValueKey('joker-choice-dialog'),
          title: const Text('Choose joker identity'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final choice in choices)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: OutlinedButton(
                        key: ValueKey('joker-choice-${choice.identity.key}'),
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(choice),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(strings.jokerAs(choice.identity)),
                              const SizedBox(height: 8),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  for (final card in choice.cards)
                                    HareegCardView(
                                      theme: theme,
                                      card: card,
                                      jokerDisplay: JokerDisplay.assisted,
                                      size: const Size(30, 42),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<TableMeldSuggestion> _meldSuggestions(
    ClassicHareegTableInteractionAdapter tableInteraction,
  ) {
    return [
      for (final suggestion in tableInteraction.meldSuggestions())
        TableMeldSuggestion(
          actionId: suggestion.actionId,
          cards: suggestion.cards,
        ),
    ];
  }

  void _toggleSelectedCard(HareegCard card) {
    if (_isOpeningDealRunning) return;
    unawaited(_haptics.fire(TableHapticEvent.cardTap));
    setState(() {
      if (_selectedCardIds.contains(card.id)) {
        _selectedCardIds.remove(card.id);
      } else {
        _selectedCardIds.add(card.id);
      }
    });
  }

  void _showCardInspect(HareegCard card) {
    unawaited(_haptics.fire(TableHapticEvent.cardTap));
    setState(() => _inspectedCard = card);
  }

  void _replaceHumanFeedback(String? message, {required bool isError}) {
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
    final nextMessage = message == null || message.isEmpty
        ? null
        : context.strings.gameMessage(message);
    _humanFeedback = nextMessage;
    _humanFeedbackIsError = isError;
    if (nextMessage == null) return;

    final duration = _scaledDelay(
      isError ? _errorFeedbackDuration : _successFeedbackDuration,
    );
    _feedbackTimer = Timer(duration, () {
      if (!mounted) return;
      setState(() {
        if (_humanFeedback == nextMessage && _humanFeedbackIsError == isError) {
          _humanFeedback = null;
        }
      });
    });
  }

  void _showInvalidFeedback(String message) {
    unawaited(_haptics.fire(TableHapticEvent.illegalAction));
    unawaited(_audio.play(TableSoundEvent.invalidAction));
    setState(() {
      _replaceHumanFeedback(message, isError: true);
    });
  }

  /// Plays a stock→seat / discard→seat / seat→discard card-flight for a CPU
  /// action so the human can see which seat acted and where the card went.
  Future<void> _playFlightForCpuAction(PlayerSeat seat, String actionId) async {
    final flight = _flightForCpuAction(seat, actionId);
    if (flight == null) {
      unawaited(_playSoundForAction(actionId));
      return;
    }
    unawaited(_playSoundForAction(actionId));
    setState(() => _cardFlight = flight);
    await Future<void>.delayed(_cpuFlightDuration);
    if (mounted && identical(_cardFlight, flight)) {
      setState(() => _cardFlight = null);
    }
  }

  _CardFlight? _flightForCpuAction(PlayerSeat seat, String actionId) {
    final seatAnchor = _alignmentForSeat(seat);
    final action = ClassicHareegActionIds.describe(actionId);
    if (action.kind == ClassicHareegActionKind.drawStock) {
      final handSlot = _appendHandSlotForSeat(seat);
      return _CardFlight(
        serial: ++_flightSerial,
        card: _backSeed(_flightSerial),
        faceDown: true,
        begin: _FlightAnchor.stock.alignment,
        end: seatAnchor,
        endHandSlot: handSlot,
      );
    }
    if (action.kind == ClassicHareegActionKind.takeDiscard) {
      final card = _controller.topDiscard;
      if (card == null) return null;
      final handSlot = _appendHandSlotForSeat(seat);
      return _CardFlight(
        serial: ++_flightSerial,
        card: card,
        begin: _FlightAnchor.discard.alignment,
        end: seatAnchor,
        endHandSlot: handSlot,
      );
    }
    if (action.kind == ClassicHareegActionKind.returnPendingDiscard) {
      final card = _controller.pendingDiscard;
      if (card == null) return null;
      return _CardFlight(
        serial: ++_flightSerial,
        card: card,
        begin: seatAnchor,
        end: _FlightAnchor.discard.alignment,
        beginHandSlot: _lastHandSlotForSeat(seat),
      );
    }
    final discardCardId = action.isDiscard ? action.cardId : null;
    if (discardCardId != null) {
      final card = _cardInHand(seat, discardCardId);
      return _CardFlight(
        serial: ++_flightSerial,
        card: card ?? _backSeed(_flightSerial),
        faceDown: card == null,
        begin: seatAnchor,
        end: _FlightAnchor.discard.alignment,
        beginHandSlot: _lastHandSlotForSeat(seat),
      );
    }
    return null;
  }

  Future<bool> _playFlightForAction(String actionId) async {
    final flight = _flightForAction(actionId);
    if (flight == null) return false;
    unawaited(_playSoundForAction(actionId));
    setState(() => _cardFlight = flight);
    await Future<void>.delayed(_scaledDelay(const Duration(milliseconds: 230)));
    if (mounted && identical(_cardFlight, flight)) {
      setState(() => _cardFlight = null);
    }
    return true;
  }

  _CardFlight? _flightForAction(String actionId) {
    final action = ClassicHareegActionIds.describe(actionId);
    if (action.kind == ClassicHareegActionKind.drawStock) {
      final handSlot = _southHandAppendSlot();
      return _CardFlight(
        serial: ++_flightSerial,
        card: _backSeed(_flightSerial),
        faceDown: true,
        begin: _FlightAnchor.stock.alignment,
        end: _FlightAnchor.hand.alignment,
        endHandSlot: handSlot,
      );
    }

    if (action.kind == ClassicHareegActionKind.takeDiscard) {
      final card = _controller.topDiscard;
      if (card == null) return null;
      final handSlot = _southHandAppendSlot();
      return _CardFlight(
        serial: ++_flightSerial,
        card: card,
        begin: _FlightAnchor.discard.alignment,
        end: _FlightAnchor.hand.alignment,
        endHandSlot: handSlot,
      );
    }

    if (action.kind == ClassicHareegActionKind.returnPendingDiscard) {
      final card = _controller.pendingDiscard;
      if (card == null) return null;
      return _CardFlight(
        serial: ++_flightSerial,
        card: card,
        begin: _FlightAnchor.hand.alignment,
        end: _FlightAnchor.discard.alignment,
        beginHandSlot: _southHandCardSlot(card.id),
      );
    }

    final discardCardId = action.isDiscard ? action.cardId : null;
    if (discardCardId != null) {
      final card = _cardInSouthHand(discardCardId);
      if (card == null) return null;
      return _CardFlight(
        serial: ++_flightSerial,
        card: card,
        begin: _FlightAnchor.hand.alignment,
        end: _FlightAnchor.discard.alignment,
        beginHandSlot: _southHandCardSlot(card.id),
      );
    }

    final cover = action.coverTarget;
    if (cover != null && cover.cardIds.isNotEmpty) {
      final card = _cardInSouthHand(cover.cardIds.first);
      if (card == null) return null;
      return _CardFlight(
        serial: ++_flightSerial,
        card: card,
        begin: _FlightAnchor.hand.alignment,
        end: _FlightAnchor.hand.alignment,
        beginHandSlot: _southHandCardSlot(card.id),
        endMeldSlot: _TableMeldFlightSlot(
          seat: cover.targetSeat,
          index: cover.meldIndex,
        ),
      );
    }

    final replacement = action.jokerReplacementTarget;
    if (replacement != null) {
      final card = _cardInSouthHand(replacement.cardId);
      if (card == null) return null;
      return _CardFlight(
        serial: ++_flightSerial,
        card: card,
        begin: _FlightAnchor.hand.alignment,
        end: _FlightAnchor.hand.alignment,
        beginHandSlot: _southHandCardSlot(card.id),
        endMeldSlot: _TableMeldFlightSlot(
          seat: replacement.targetSeat,
          index: replacement.meldIndex,
        ),
      );
    }

    final meldIds = action.isMeldPlay ? action.cardIds : null;
    if (meldIds != null && meldIds.isNotEmpty) {
      final card = _cardInSouthHand(meldIds.first);
      if (card == null) return null;
      return _CardFlight(
        serial: ++_flightSerial,
        card: card,
        begin: _FlightAnchor.hand.alignment,
        end: _FlightAnchor.hand.alignment,
        beginHandSlot: _southHandCardSlot(card.id),
        endMeldSlot: const _TableMeldFlightSlot(seat: PlayerSeat.south),
      );
    }

    return null;
  }

  SeatHandFlightSlot _southHandAppendSlot() {
    final count = _controller.handFor(PlayerSeat.south).length + 1;
    return SeatHandFlightSlot(
      seat: PlayerSeat.south,
      index: count - 1,
      count: count,
    );
  }

  SeatHandFlightSlot? _southHandCardSlot(String cardId) {
    final cards = _orderedSouthHand();
    final index = cards.indexWhere((card) => card.id == cardId);
    if (index == -1) {
      return null;
    }
    return SeatHandFlightSlot(
      seat: PlayerSeat.south,
      index: index,
      count: cards.length,
    );
  }

  SeatHandFlightSlot _appendHandSlotForSeat(PlayerSeat seat) {
    if (seat == PlayerSeat.south) {
      return _southHandAppendSlot();
    }
    final count = _controller.cardCountFor(seat) + 1;
    return SeatHandFlightSlot(seat: seat, index: count - 1, count: count);
  }

  SeatHandFlightSlot? _lastHandSlotForSeat(PlayerSeat seat) {
    if (seat == PlayerSeat.south) {
      final cards = _orderedSouthHand();
      if (cards.isEmpty) return null;
      return SeatHandFlightSlot(
        seat: PlayerSeat.south,
        index: cards.length - 1,
        count: cards.length,
      );
    }
    final count = _controller.cardCountFor(seat);
    if (count <= 0) return null;
    return SeatHandFlightSlot(seat: seat, index: count - 1, count: count);
  }

  HareegCard? _cardInSouthHand(String id) {
    return _cardInHand(PlayerSeat.south, id);
  }

  HareegCard? _cardInHand(PlayerSeat seat, String id) {
    for (final card in _controller.handFor(seat)) {
      if (card.id == id) return card;
    }
    return null;
  }

  Future<void> _claimFifty() async {
    await _runHumanAction(ClassicHareegActionIds.claimFifty);
    if (!mounted) return;
    setState(() => _fiftyPulse = true);
    unawaited(_haptics.fire(TableHapticEvent.fiftyClaim));
    Future.delayed(_scaledDelay(TableMotion.fiftyHeatPulse), () {
      if (mounted) setState(() => _fiftyPulse = false);
    });
  }

  Future<void> _runHumanAction(
    String actionId, {
    bool playFlight = true,
  }) async {
    if (_isCpuRunning || _isOpeningDealRunning || _isHumanActionPending) return;
    _isHumanActionPending = true;
    // Rebuild so south controls/playfield pick up the pending-lock immediately.
    setState(() {});
    final totalWatch = Stopwatch()..start();
    _debugTableLog(
      'human action start action=$actionId current=${_controller.currentSeat.name} '
      'phase=${_controller.turnPhase} pending=${_controller.pendingDiscard?.label}',
    );
    try {
      var soundPlayedWithFlight = false;
      if (playFlight) {
        soundPlayedWithFlight = await _playFlightForAction(actionId);
      }
      if (!mounted) return;
      await _completeHumanAction(
        actionId,
        soundPlayedWithFlight: soundPlayedWithFlight,
        totalWatch: totalWatch,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isHumanActionPending = false;
        });
      } else {
        _isHumanActionPending = false;
      }
    }
  }

  Future<void> _completeHumanAction(
    String actionId, {
    required bool soundPlayedWithFlight,
    required Stopwatch totalWatch,
  }) async {
    final applyWatch = Stopwatch()..start();
    final result = _controller.applyAction(actionId);
    applyWatch.stop();
    _debugTableLog(
      'human action applied action=$actionId success=${result.isSuccess} '
      'applyElapsed=${applyWatch.elapsedMilliseconds}ms '
      'totalElapsed=${totalWatch.elapsedMilliseconds}ms '
      'current=${_controller.currentSeat.name} phase=${_controller.turnPhase}',
    );
    if (!result.isSuccess) {
      unawaited(_haptics.fire(TableHapticEvent.illegalAction));
      unawaited(_audio.play(TableSoundEvent.invalidAction));
      setState(() {
        _replaceHumanFeedback(result.message, isError: true);
      });
      return;
    }
    unawaited(_haptics.fire(_hapticForAction(actionId)));
    if (!soundPlayedWithFlight) {
      unawaited(_playSoundForAction(actionId));
    }
    setState(() {
      _replaceHumanFeedback(result.message, isError: false);
      if (_clearsSelection(actionId)) {
        _selectedCardIds.clear();
      }
    });
    _ensureFiftyTicker();
    await _persistAndMaybeFinish();
    if (!mounted) return;
    await _runCpuTurns();
    totalWatch.stop();
    _debugTableLog(
      'human action end action=$actionId '
      'elapsed=${totalWatch.elapsedMilliseconds}ms '
      'current=${_controller.currentSeat.name} phase=${_controller.turnPhase}',
    );
  }

  TableHapticEvent _hapticForAction(String actionId) {
    return switch (ClassicHareegActionIds.describe(actionId).kind) {
      ClassicHareegActionKind.drawStock => TableHapticEvent.drawCard,
      ClassicHareegActionKind.returnPendingDiscard =>
        TableHapticEvent.pendingReturn,
      ClassicHareegActionKind.claimFifty => TableHapticEvent.fiftyClaim,
      _ => TableHapticEvent.buttonTap,
    };
  }

  Future<void> _playSoundForAction(String actionId) async {
    final event = switch (ClassicHareegActionIds.describe(actionId).kind) {
      ClassicHareegActionKind.drawStock => TableSoundEvent.drawStock,
      ClassicHareegActionKind.takeDiscard => TableSoundEvent.takeDiscard,
      ClassicHareegActionKind.returnPendingDiscard ||
      ClassicHareegActionKind.returnOpeningMelds ||
      ClassicHareegActionKind.returnTablePlay => TableSoundEvent.cardReturn,
      ClassicHareegActionKind.claimFifty => TableSoundEvent.fiftyClaim,
      ClassicHareegActionKind.playMeld ||
      ClassicHareegActionKind.playMeldWithJoker ||
      ClassicHareegActionKind.placeCover ||
      ClassicHareegActionKind.replaceJoker => TableSoundEvent.meldPlace,
      ClassicHareegActionKind.discard ||
      ClassicHareegActionKind.discardBlockedCover ||
      ClassicHareegActionKind.discardJoker => TableSoundEvent.discardCard,
      ClassicHareegActionKind.usePendingDiscard ||
      ClassicHareegActionKind.unknown => null,
    };
    if (event == null) return;
    await _audio.play(event);
  }

  bool _clearsSelection(String actionId) {
    return ClassicHareegActionIds.describe(actionId).clearsSelection;
  }

  Future<bool> _runCpuTurns() async {
    if (_isCpuRunning ||
        _isOpeningDealRunning ||
        _controller.isRoundOver ||
        _controller.currentSeat == PlayerSeat.south) {
      _debugTableLog(
        'cpu loop skip running=$_isCpuRunning roundOver=${_controller.isRoundOver} '
        'current=${_controller.currentSeat.name} phase=${_controller.turnPhase}',
      );
      return false;
    }

    final totalWatch = Stopwatch()..start();
    _debugTableLog(
      'cpu loop start current=${_controller.currentSeat.name} '
      'phase=${_controller.turnPhase} stock=${_controller.stockCount} '
      'discard=${_controller.discardPile.length} '
      'counts=${_debugSeatCounts(_controller)}',
    );
    setState(() {
      _isCpuRunning = true;
    });
    try {
      final runner = ClassicHareegCpuTurnRunner(
        controller: _controller,
        strategy: widget.cpuStrategy,
        actionLimit: _cpuActionLimit,
        hooks: ClassicHareegCpuTurnHooks(
          beforeDecision: (step) async {
            _debugTableLog(
              'cpu step ${step.index} start seat=${step.seat.name} '
              'phase=${step.phase} pending=${step.pendingDiscard?.label} '
              'stock=${step.stockCount} discard=${step.discardCount}',
            );
            if (_cpuReadPause > Duration.zero) {
              await Future<void>.delayed(_cpuReadPause);
            }
            return mounted;
          },
          onLegalActions: (step, legal) {
            _debugTableLog(
              'cpu step ${step.index} legal seat=${step.seat.name} '
              'count=${legal.length} actions=${_debugActionSummary(legal)}',
            );
            if (legal.isEmpty) {
              _debugTableLog('cpu step ${step.index} break no legal actions');
            }
          },
          onActionChosen: (decision) {
            _debugTableLog(
              'cpu step ${decision.step.index} chose '
              'action=${decision.actionId}',
            );
          },
          beforeApply: (decision) async {
            final flightWatch = Stopwatch()..start();
            await _playFlightForCpuAction(decision.seat, decision.actionId);
            flightWatch.stop();
            _debugTableLog(
              'cpu step ${decision.step.index} flight '
              'action=${decision.actionId} '
              'elapsed=${flightWatch.elapsedMilliseconds}ms',
            );
            return mounted;
          },
          afterApply: (decision, result) async {
            _debugTableLog(
              'cpu step ${decision.step.index} applied '
              'action=${decision.actionId} success=${result.isSuccess} '
              'current=${_controller.currentSeat.name} '
              'phase=${_controller.turnPhase}',
            );
            _ensureFiftyTicker();
            final persistWatch = Stopwatch()..start();
            await _persistAndMaybeFinish();
            persistWatch.stop();
            _debugTableLog(
              'cpu step ${decision.step.index} persist returned '
              'elapsed=${persistWatch.elapsedMilliseconds}ms '
              'roundOver=${_controller.isRoundOver}',
            );
            if (!mounted) return false;
            return !_controller.isRoundOver && _roundResultPresentation == null;
          },
          beforeNextAction: (_) async {
            if (_cpuBetweenActionPause > Duration.zero) {
              await Future<void>.delayed(_cpuBetweenActionPause);
            }
            return mounted;
          },
        ),
      );

      final result = await runner.run();
      if (!mounted) {
        return result.didApplyAction;
      }
      _prewarmHumanDrawControls();
      final hitCpuSafetyLimit = result.reachedSafetyLimit;
      setState(() {
        _isCpuRunning = false;
        _cardFlight = null;
        if (hitCpuSafetyLimit) {
          _replaceHumanFeedback(
            context.strings.cpuTurnSafetyCapReached(
              _cpuActionLimit,
              _controller.currentSeat,
            ),
            isError: true,
          );
        }
      });
      totalWatch.stop();
      _debugTableLog(
        'cpu loop end elapsed=${totalWatch.elapsedMilliseconds}ms '
        'steps=${result.appliedActionCount} '
        'reason=${result.stopReason.name} '
        'hitSafety=$hitCpuSafetyLimit '
        'didPersist=${result.didApplyAction} current=${_controller.currentSeat.name} '
        'phase=${_controller.turnPhase} roundOver=${_controller.isRoundOver}',
      );
      return result.didApplyAction;
    } catch (error, stackTrace) {
      totalWatch.stop();
      _debugTableLog(
        'cpu loop failed elapsed=${totalWatch.elapsedMilliseconds}ms '
        'current=${_controller.currentSeat.name} '
        'phase=${_controller.turnPhase} error=$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _isCpuRunning = false;
          _cardFlight = null;
          _replaceHumanFeedback(
            context.strings.cpuTurnPaused(_controller.currentSeat),
            isError: true,
          );
        });
      }
      return false;
    }
  }

  void _prewarmHumanDrawControls() {
    if (_controller.isRoundOver ||
        _controller.currentSeat != PlayerSeat.south ||
        _controller.turnPhase != TurnPhase.draw) {
      return;
    }

    final watch = Stopwatch()..start();
    _controller.controlActionIdsFor(PlayerSeat.south);
    watch.stop();
    if (watch.elapsedMilliseconds >= 16) {
      _debugTableLog(
        'human draw controls prewarm elapsed=${watch.elapsedMilliseconds}ms',
      );
    }
  }

  Future<bool> _persistAndMaybeFinish() async {
    final totalWatch = Stopwatch()..start();
    var persistencePath = 'active';
    final roundResult = _controller.roundResult;
    final roundProgress = _controller.roundProgress;
    final previousScores = _controller.scores;
    final nextSnapshot = _controller.isRoundOver
        ? _controller.nextRoundSnapshot()
        : null;
    _debugTableLog(
      'persist start roundOver=${_controller.isRoundOver} '
      'current=${_controller.currentSeat.name} phase=${_controller.turnPhase} '
      'stock=${_controller.stockCount} discard=${_controller.discardPile.length} '
      'counts=${_debugSeatCounts(_controller)}',
    );
    var persistenceSucceeded = true;
    try {
      if (_controller.isRoundOver) {
        if (nextSnapshot == null) {
          persistencePath = 'abandon';
          await widget.matchRepository.abandonActiveMatch();
        } else {
          persistencePath = 'next-round';
          await widget.matchRepository.saveActiveMatch(nextSnapshot);
        }
      } else {
        persistencePath = 'active';
        await widget.matchRepository.saveActiveMatch(_controller.toSnapshot());
      }
    } catch (error, stackTrace) {
      persistenceSucceeded = false;
      _debugTableLog('persist failed path=$persistencePath error=$error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.couldNotSaveTable)),
        );
      }
    }
    totalWatch.stop();
    _debugTableLog(
      'persist end success=$persistenceSucceeded path=$persistencePath '
      'elapsed=${totalWatch.elapsedMilliseconds}ms roundOver=${_controller.isRoundOver}',
    );
    if (!mounted) return persistenceSucceeded;
    if (_controller.isRoundOver &&
        persistenceSucceeded &&
        roundResult != null &&
        roundProgress != null) {
      _debugTableLog('round result overlay requested');
      _showRoundResultOverlay(
        result: roundResult,
        progress: roundProgress,
        previousScores: previousScores,
        nextSnapshot: nextSnapshot,
      );
    }
    return persistenceSucceeded;
  }

  void _showRoundResultOverlay({
    required RoundProgressResult result,
    required MatchProgressState progress,
    required Map<PlayerSeat, int> previousScores,
    required ClassicHareegMatchSnapshot? nextSnapshot,
  }) {
    if (_roundResultPresentation != null) {
      return;
    }
    unawaited(_haptics.fire(TableHapticEvent.roundEnd));
    unawaited(_audio.play(TableSoundEvent.roundEnd));
    setState(() {
      _scoreOpen = false;
      _pauseOpen = false;
      _inspectedCard = null;
      _roundResultPresentation = _RoundResultPresentation(
        result: result,
        progress: progress,
        previousScores: previousScores,
        nextSnapshot: nextSnapshot,
      );
    });
    if (nextSnapshot == null) {
      return;
    }
    _roundAdvanceTimer?.cancel();
    _roundAdvanceTimer = Timer(_roundResultDisplayDuration, () {
      if (!mounted) return;
      _advanceToNextRound(nextSnapshot);
    });
  }

  void _advanceToNextRound(ClassicHareegMatchSnapshot snapshot) {
    _roundAdvanceTimer?.cancel();
    _roundAdvanceTimer = null;
    _fiftyTicker?.cancel();
    _fiftyTicker = null;
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
    _dealChoreography?.dispose();
    _dealChoreography = null;
    setState(() {
      _controller = ClassicHareegGameController.fromSnapshot(snapshot);
      _resetDisplayOrder();
      _dealChoreography = _buildDealChoreography();
      _selectedCardIds.clear();
      _isCpuRunning = false;
      _scoreOpen = false;
      _pauseOpen = false;
      _fiftyPulse = false;
      _humanFeedback = null;
      _humanFeedbackIsError = false;
      _cardFlight = null;
      _inspectedCard = null;
      _roundResultPresentation = null;
    });
    _ensureFiftyTicker();
    _scheduleTurnFlow();
  }
}

/// Softly-rounded chrome button used for the score / pause shortcuts in the
/// table's top corners. Matches the open-need pill's surface treatment
/// (charcoal fill, hairline border, soft shadow) so the corner controls read
/// as part of the same chrome family across every table theme rather than
/// floating dark blobs.
class _TableChromeButton extends StatelessWidget {
  const _TableChromeButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.diameter = 40,
    this.iconSize = 22,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final double diameter;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(diameter * 0.32);
    final shape = RoundedRectangleBorder(
      borderRadius: radius,
      side: BorderSide(color: Colors.white.withValues(alpha: 0.10), width: 1),
    );
    return Tooltip(
      message: tooltip,
      child: Material(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.92),
        shape: shape,
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.38),
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: SizedBox.square(
            dimension: diameter,
            child: Icon(icon, color: LoungeTokens.offWhiteText, size: iconSize),
          ),
        ),
      ),
    );
  }
}

class _AnimatedOverlaySlot extends StatelessWidget {
  const _AnimatedOverlaySlot({
    required this.visible,
    required this.overlayKey,
    required this.duration,
    required this.child,
  });

  final bool visible;
  final String overlayKey;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedSwitcher(
        duration: duration,
        reverseDuration: duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
              child: child,
            ),
          );
        },
        child: visible
            ? KeyedSubtree(key: ValueKey(overlayKey), child: child)
            : const SizedBox.shrink(key: ValueKey('overlay-empty')),
      ),
    );
  }
}

class _RoundResultPresentation {
  const _RoundResultPresentation({
    required this.result,
    required this.progress,
    required this.previousScores,
    required this.nextSnapshot,
  });

  final RoundProgressResult result;
  final MatchProgressState progress;
  final Map<PlayerSeat, int> previousScores;
  final ClassicHareegMatchSnapshot? nextSnapshot;
}

class _RoundResultOverlay extends StatelessWidget {
  const _RoundResultOverlay({
    required this.presentation,
    required this.onContinueNow,
    required this.onReturnToMenu,
    required this.onDismiss,
  });

  final _RoundResultPresentation presentation;
  final VoidCallback? onContinueNow;
  final VoidCallback? onReturnToMenu;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final highContrast = CardContrastScope.enabledOf(context);
    final seats = PlayerSeat.values.toList();
    final compact = MediaQuery.sizeOf(context).height < 390;
    final winner = presentation.progress.matchWinner;
    return GestureDetector(
      key: const ValueKey('round-result-overlay'),
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: highContrast ? 0.72 : 0.50),
        child: SafeArea(
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 14 : 22,
                  vertical: compact ? 10 : 18,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: compact ? 620 : 700,
                    maxHeight: MediaQuery.sizeOf(context).height - 24,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: highContrast
                          ? Colors.black.withValues(alpha: 0.98)
                          : LoungeTokens.coffeeCharcoal.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: highContrast
                            ? const Color(0xFFFFD400)
                            : LoungeTokens.goldAccent.withValues(alpha: 0.34),
                        width: highContrast ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.36),
                          blurRadius: 28,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 12 : 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _RoundResultHeader(
                            headline: _roundHeadline(
                              presentation.result,
                              strings,
                            ),
                            detail: _roundDetail(presentation, strings),
                            compact: compact,
                          ),
                          SizedBox(height: compact ? 10 : 14),
                          Flexible(
                            child: SingleChildScrollView(
                              child: _RoundScoreBreakdown(
                                seats: seats,
                                presentation: presentation,
                                compact: compact,
                              ),
                            ),
                          ),
                          SizedBox(height: compact ? 10 : 14),
                          if (winner == null)
                            _RoundAdvanceLine(
                              nextStarter: presentation.progress.nextStarter,
                              onContinueNow: onContinueNow,
                              compact: compact,
                            )
                          else
                            _MatchWinnerLine(
                              winner: winner,
                              onReturnToMenu: onReturnToMenu,
                              compact: compact,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundResultHeader extends StatelessWidget {
  const _RoundResultHeader({
    required this.headline,
    required this.detail,
    required this.compact,
  });

  final String headline;
  final String detail;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.scoreboard_outlined,
          color: LoungeTokens.goldAccent,
          size: compact ? 20 : 24,
        ),
        SizedBox(width: compact ? 8 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.strings.roundScore,
                style: TextStyle(
                  color: LoungeTokens.goldAccent,
                  fontSize: compact ? 10 : 12,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                headline,
                style: TextStyle(
                  color: LoungeTokens.offWhiteText,
                  fontSize: compact ? 17 : 22,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: TextStyle(
                  color: LoungeTokens.offWhiteText.withValues(alpha: 0.74),
                  fontSize: compact ? 11 : 13,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoundScoreBreakdown extends StatelessWidget {
  const _RoundScoreBreakdown({
    required this.seats,
    required this.presentation,
    required this.compact,
  });

  final List<PlayerSeat> seats;
  final _RoundResultPresentation presentation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LoungeTokens.feltGreen.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.20),
        ),
      ),
      child: Column(
        children: [
          for (var index = 0; index < seats.length; index++) ...[
            _RoundScoreRow(
              seat: seats[index],
              before: presentation.previousScores[seats[index]] ?? 0,
              after: presentation.progress.scores[seats[index]] ?? 0,
              cards: presentation.result.remainingCardCounts[seats[index]],
              eliminated: !presentation.progress.activeSeats.contains(
                seats[index],
              ),
              compact: compact,
            ),
            if (index < seats.length - 1)
              Divider(
                height: 1,
                color: LoungeTokens.sandLine.withValues(alpha: 0.16),
              ),
          ],
        ],
      ),
    );
  }
}

class _RoundScoreRow extends StatelessWidget {
  const _RoundScoreRow({
    required this.seat,
    required this.before,
    required this.after,
    required this.cards,
    required this.eliminated,
    required this.compact,
  });

  final PlayerSeat seat;
  final int before;
  final int after;
  final int? cards;
  final bool eliminated;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final delta = after - before;
    final deltaText = delta > 0 ? '+$delta' : '$delta';
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 7 : 10,
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  strings.seatLabel(seat),
                  style: TextStyle(
                    color: eliminated
                        ? LoungeTokens.mutedText
                        : LoungeTokens.offWhiteText,
                    fontSize: compact ? 12 : 14,
                    fontWeight: FontWeight.w800,
                    decoration: eliminated ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (cards != null)
                  _MiniResultTag(
                    label: strings.cardsCountTag(cards!),
                    compact: compact,
                  ),
                if (eliminated)
                  _MiniResultTag(label: strings.out, compact: compact),
              ],
            ),
          ),
          Text('$before', style: _scoreNumberStyle(compact)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Text(
              delta == 0 ? '+0' : deltaText,
              style: TextStyle(
                color: delta <= 0
                    ? LoungeTokens.goldAccent
                    : LoungeTokens.fiftyFlame,
                fontSize: compact ? 12 : 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            '$after',
            style: _scoreNumberStyle(compact).copyWith(
              color: eliminated
                  ? LoungeTokens.mutedText
                  : LoungeTokens.goldAccent,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniResultTag extends StatelessWidget {
  const _MiniResultTag({required this.label, required this.compact});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.18),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 7, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            color: LoungeTokens.offWhiteText.withValues(alpha: 0.72),
            fontSize: compact ? 9 : 10,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _RoundAdvanceLine extends StatelessWidget {
  const _RoundAdvanceLine({
    required this.nextStarter,
    required this.onContinueNow,
    required this.compact,
  });

  final PlayerSeat nextStarter;
  final VoidCallback? onContinueNow;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Row(
      children: [
        Expanded(
          child: Text(
            strings.nextRoundStartsWith(nextStarter),
            style: TextStyle(
              color: LoungeTokens.offWhiteText.withValues(alpha: 0.76),
              fontSize: compact ? 11 : 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(
          onPressed: onContinueNow,
          style: _roundResultActionStyle(compact),
          child: Text(strings.nextNow),
        ),
      ],
    );
  }
}

class _MatchWinnerLine extends StatelessWidget {
  const _MatchWinnerLine({
    required this.winner,
    required this.onReturnToMenu,
    required this.compact,
  });

  final PlayerSeat winner;
  final VoidCallback? onReturnToMenu;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Row(
      children: [
        Expanded(
          child: Text(
            strings.playerWinsMatch(winner),
            style: TextStyle(
              color: LoungeTokens.goldAccent,
              fontSize: compact ? 12 : 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        TextButton(
          onPressed: onReturnToMenu,
          style: _roundResultActionStyle(compact),
          child: Text(strings.menu),
        ),
      ],
    );
  }
}

ButtonStyle _roundResultActionStyle(bool compact) {
  return TextButton.styleFrom(
    fixedSize: Size(compact ? 92 : 108, compact ? 34 : 40),
    minimumSize: Size.zero,
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
  );
}

TextStyle _scoreNumberStyle(bool compact) {
  return TextStyle(
    color: LoungeTokens.offWhiteText,
    fontSize: compact ? 14 : 17,
    fontWeight: FontWeight.w900,
  );
}

String _roundHeadline(RoundProgressResult result, AppStrings strings) {
  return switch (result.type) {
    RoundOutcomeType.normalFinish => strings.playerFinished(result.winner!),
    RoundOutcomeType.fiftyFinish => strings.playerHitFifty(result.winner!),
    RoundOutcomeType.draw => strings.roundDrawn,
  };
}

String _roundDetail(_RoundResultPresentation presentation, AppStrings strings) {
  final result = presentation.result;
  return switch (result.type) {
    RoundOutcomeType.normalFinish => strings.roundResultDetailNormal(),
    RoundOutcomeType.fiftyFinish => strings.roundResultDetailFifty(
      firstRoundException: result.firstRoundFiftyException,
    ),
    RoundOutcomeType.draw => strings.roundResultDetailDraw(),
  };
}

class _CardInspectOverlay extends StatelessWidget {
  const _CardInspectOverlay({
    required this.card,
    required this.theme,
    required this.aids,
    required this.jokerAidsEnabled,
    required this.onClose,
  });

  final HareegCard card;
  final HareegCardTheme theme;
  final TableAids aids;
  final bool jokerAidsEnabled;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final highContrast = CardContrastScope.enabledOf(context);
    final title = _inspectTitle(
      card,
      strings,
      jokerAidsEnabled: jokerAidsEnabled,
    );
    final body = _inspectBody(
      card,
      aids,
      strings: strings,
      jokerAidsEnabled: jokerAidsEnabled,
    );
    final inspectJokerDisplay = jokerAidsEnabled
        ? JokerDisplay.assisted
        : JokerDisplay.unassigned;
    return Positioned.fill(
      key: const ValueKey('card-inspect-overlay'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: Material(
          color: Colors.black.withValues(alpha: highContrast ? 0.68 : 0.48),
          child: SafeArea(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact =
                      constraints.maxWidth < 560 || constraints.maxHeight < 390;
                  final cardSize = compact
                      ? const Size(88, 124)
                      : const Size(128, 180);
                  final details = Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: compact
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        key: const ValueKey('card-inspect-title'),
                        textAlign: compact ? TextAlign.center : TextAlign.start,
                        style: TextStyle(
                          color: LoungeTokens.offWhiteText,
                          fontSize: compact ? 17 : 20,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                      if (body != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          body,
                          key: const ValueKey('card-inspect-body'),
                          textAlign: compact
                              ? TextAlign.center
                              : TextAlign.start,
                          style: TextStyle(
                            color: LoungeTokens.offWhiteText.withValues(
                              alpha: 0.82,
                            ),
                            fontSize: compact ? 12 : 13,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  );

                  final content = compact
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            HareegCardView(
                              theme: theme,
                              card: card,
                              size: cardSize,
                              jokerDisplay: inspectJokerDisplay,
                            ),
                            const SizedBox(height: 12),
                            details,
                          ],
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            HareegCardView(
                              theme: theme,
                              card: card,
                              size: cardSize,
                              jokerDisplay: inspectJokerDisplay,
                            ),
                            const SizedBox(width: 18),
                            Flexible(child: details),
                          ],
                        );

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: math.max(
                          0.0,
                          math.min(constraints.maxWidth - 28, 520.0),
                        ),
                        maxHeight: math.max(0.0, constraints.maxHeight - 28),
                      ),
                      margin: const EdgeInsets.all(14),
                      padding: EdgeInsets.fromLTRB(
                        compact ? 14 : 18,
                        compact ? 14 : 18,
                        compact ? 14 : 18,
                        compact ? 16 : 18,
                      ),
                      decoration: BoxDecoration(
                        color: highContrast
                            ? Colors.black.withValues(alpha: 0.98)
                            : LoungeTokens.coffeeCharcoal.withValues(
                                alpha: 0.96,
                              ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: highContrast
                              ? const Color(0xFFFFD400)
                              : LoungeTokens.goldAccent.withValues(alpha: 0.36),
                          width: highContrast ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.34),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          SingleChildScrollView(
                            child: Padding(
                              padding: EdgeInsets.only(right: compact ? 0 : 28),
                              child: content,
                            ),
                          ),
                          Positioned(
                            top: -8,
                            right: -8,
                            child: Tooltip(
                              message: strings.close,
                              child: IconButton(
                                key: const ValueKey('card-inspect-close'),
                                onPressed: onClose,
                                icon: const Icon(Icons.close_rounded),
                                color: LoungeTokens.offWhiteText,
                                iconSize: 20,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _FlightAnchor {
  stock(Alignment(-0.86, 0.56)),
  discard(Alignment(0, 0)),
  hand(Alignment(0, 0.82));

  const _FlightAnchor(this.alignment);

  final Alignment alignment;
}

Alignment _alignmentForSeat(PlayerSeat seat) {
  return switch (seat) {
    PlayerSeat.south => const Alignment(0, 0.48),
    PlayerSeat.north => const Alignment(0, -0.48),
    PlayerSeat.east => const Alignment(0.68, 0),
    PlayerSeat.west => const Alignment(-0.68, 0),
  };
}

HareegCard _backSeed(int index) {
  return HareegCard.standard(
    rank: CardRank.ace,
    suit: CardSuit.spades,
    deckIndex: 700 + index,
  );
}

class _CardFlight {
  const _CardFlight({
    required this.serial,
    required this.card,
    required this.begin,
    required this.end,
    this.faceDown = false,
    this.beginHandSlot,
    this.endHandSlot,
    this.endMeldSlot,
  });

  final int serial;
  final HareegCard card;
  final Alignment begin;
  final Alignment end;
  final bool faceDown;
  final SeatHandFlightSlot? beginHandSlot;
  final SeatHandFlightSlot? endHandSlot;
  final _TableMeldFlightSlot? endMeldSlot;
}

class _TableMeldFlightSlot {
  const _TableMeldFlightSlot({required this.seat, this.index = 0});

  final PlayerSeat seat;
  final int index;
}

/// Shared seat-hand geometry used by both [_CardFlightOverlay] and
/// [_OpeningDealFlightCard]. Both surfaces target the exact same hand strip
/// layout, so resolving the slot position lives in one place. The geometry
/// has no widget-state dependency — it's pure math on the inputs.
Offset _resolveSeatHandSlot(
  SeatHandFlightSlot slot,
  Size size,
  Size flightCardSize,
) {
  return switch (slot.seat) {
    PlayerSeat.south => _resolveSouthHandSlot(slot, size, flightCardSize),
    PlayerSeat.north => _resolveNorthHandSlot(slot, size, flightCardSize),
    PlayerSeat.west ||
    PlayerSeat.east => _resolveSideHandSlot(slot, size, flightCardSize),
  };
}

Offset _resolveSouthHandSlot(
  SeatHandFlightSlot slot,
  Size size,
  Size flightCardSize,
) {
  final compact = size.height <= 390 || size.width <= 700;
  final handCardSize = compact ? const Size(36, 50) : const Size(48, 68);
  final controlWidth = compact ? 60.0 : 72.0;
  final bottomHandHeight = handCardSize.height + (compact ? 12 : 18);
  final edgeInset = (size.width * 0.026)
      .clamp(compact ? 14.0 : 20.0, compact ? 30.0 : 52.0)
      .toDouble();
  final handRightInset = controlWidth + edgeInset + (compact ? 10.0 : 16.0);
  final handHorizontalInset = math.max(handRightInset, compact ? 70.0 : 96.0);
  final handBottom = compact ? 0.0 : 2.0;
  final handWidth = math.max(0.0, size.width - handHorizontalInset * 2);
  final count = math.max(1, slot.count);
  final index = slot.index.clamp(0, count - 1).toInt();
  final minGap = handCardSize.width * 0.42;
  final preferredGap = handCardSize.width * 0.78;
  final available = math.max(0.0, handWidth - 8);
  final fittedGap = count <= 1
      ? 0.0
      : ((available - handCardSize.width) / (count - 1))
            .clamp(minGap, preferredGap)
            .toDouble();
  final stripWidth = handCardSize.width + math.max(0, count - 1) * fittedGap;
  final canvasWidth = math.max(stripWidth, available);
  final start = math.max(0.0, (canvasWidth - stripWidth) / 2);
  final handTop = size.height - handBottom - bottomHandHeight;
  final centerX =
      handHorizontalInset +
      start +
      index * fittedGap +
      handCardSize.width / 2;
  final centerY = handTop + bottomHandHeight - 2 - handCardSize.height / 2;
  return _centeredFlightOffset(centerX, centerY, flightCardSize);
}

Offset _resolveNorthHandSlot(
  SeatHandFlightSlot slot,
  Size size,
  Size flightCardSize,
) {
  final compact = size.height <= 390 || size.width <= 700;
  final cardSize = compact ? const Size(26, 36) : const Size(32, 44);
  final topInset = (size.height * 0.032)
      .clamp(compact ? 8.0 : 12.0, compact ? 16.0 : 28.0)
      .toDouble();
  final visibleCount = compact ? 9 : 12;
  final shown = math.min(math.max(1, slot.count), visibleCount);
  final index = slot.index.clamp(0, shown - 1).toInt();
  final gap = cardSize.width * 0.38;
  final stackWidth = cardSize.width + (shown - 1) * gap;
  final left = (size.width - stackWidth) / 2;
  final top = topInset + (compact ? 6.0 : 8.0);
  final centerX = left + index * gap + cardSize.width / 2;
  final centerY = top + cardSize.height / 2;
  return _centeredFlightOffset(centerX, centerY, flightCardSize);
}

Offset _resolveSideHandSlot(
  SeatHandFlightSlot slot,
  Size size,
  Size flightCardSize,
) {
  final compact = size.height <= 390 || size.width <= 700;
  final cardSize = compact ? const Size(26, 36) : const Size(32, 44);
  final sideRailWidth = compact ? 46.0 : 56.0;
  final edgeInset = (size.width * 0.026)
      .clamp(compact ? 14.0 : 20.0, compact ? 30.0 : 52.0)
      .toDouble();
  final topInset = (size.height * 0.032)
      .clamp(compact ? 8.0 : 12.0, compact ? 16.0 : 28.0)
      .toDouble();
  final sideRailVisibleCount = compact ? 5 : 6;
  final sideRailHeight = cardSize.height + (sideRailVisibleCount - 1) * 14.0;
  final sideRailTop = topInset + cardSize.height + 12;
  final visibleCount = compact ? 8 : 11;
  final shown = math.min(math.max(1, slot.count), visibleCount);
  final index = slot.index.clamp(0, shown - 1).toInt();
  final gap = 16.0;
  final stackHeight = cardSize.height + (shown - 1) * gap;
  final top = sideRailTop + (sideRailHeight - stackHeight) / 2;
  final left = switch (slot.seat) {
    PlayerSeat.west => edgeInset,
    PlayerSeat.east =>
      size.width - edgeInset - sideRailWidth + sideRailWidth - cardSize.width,
    PlayerSeat.north || PlayerSeat.south => 0.0,
  };
  final centerX = left + cardSize.width / 2;
  final centerY = top + index * gap + cardSize.height / 2;
  return _centeredFlightOffset(centerX, centerY, flightCardSize);
}

Offset _centeredFlightOffset(double centerX, double centerY, Size cardSize) {
  return Offset(centerX - cardSize.width / 2, centerY - cardSize.height / 2);
}

class _CardFlightOverlay extends StatelessWidget {
  const _CardFlightOverlay({
    super.key,
    required this.flight,
    required this.theme,
    required this.duration,
  });

  final _CardFlight flight;
  final HareegCardTheme theme;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final cardSize = constraints.maxHeight <= 390
              ? const Size(44, 62)
              : const Size(58, 82);
          final begin = _resolveFlightPoint(
            flight.begin,
            size,
            cardSize,
            flight.beginHandSlot,
            null,
          );
          final end = _resolveFlightPoint(
            flight.end,
            size,
            cardSize,
            flight.endHandSlot,
            flight.endMeldSlot,
          );
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: duration,
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              final lifted = math.sin(value * math.pi) * 24;
              final offset = Offset.lerp(begin, end, value)!;
              return Stack(
                children: [
                  Positioned(
                    left: offset.dx,
                    top: offset.dy - lifted,
                    child: Transform.rotate(
                      angle: (1 - value) * -0.10,
                      child: Opacity(
                        opacity: (1 - (value * 0.18))
                            .clamp(0.0, 1.0)
                            .toDouble(),
                        child: child,
                      ),
                    ),
                  ),
                ],
              );
            },
            child: Material(
              color: Colors.transparent,
              elevation: 14,
              borderRadius: BorderRadius.circular(LoungeTokens.radiusCard),
              child: HareegCardView(
                theme: theme,
                card: flight.card,
                size: cardSize,
                faceDown: flight.faceDown,
                visualState: CardVisualState.selected,
              ),
            ),
          );
        },
      ),
    );
  }

  Offset _resolveFlightPoint(
    Alignment alignment,
    Size size,
    Size cardSize,
    SeatHandFlightSlot? handSlot,
    _TableMeldFlightSlot? meldSlot,
  ) {
    if (handSlot != null) {
      return _resolveSeatHandSlot(handSlot, size, cardSize);
    }
    if (meldSlot != null) {
      return _resolveTableMeldSlot(meldSlot, size, cardSize);
    }
    return Offset(
      ((alignment.x + 1) / 2 * size.width) - cardSize.width / 2,
      ((alignment.y + 1) / 2 * size.height) - cardSize.height / 2,
    );
  }

  Offset _resolveTableMeldSlot(
    _TableMeldFlightSlot slot,
    Size size,
    Size flightCardSize,
  ) {
    final compact = size.height <= 390 || size.width <= 700;
    final handCardSize = compact ? const Size(36, 50) : const Size(48, 68);
    final opponentCardSize = compact ? const Size(26, 36) : const Size(32, 44);
    final sideMeldCardSize = compact ? const Size(28, 40) : const Size(34, 48);
    final sideRailWidth = compact ? 46.0 : 56.0;
    final edgeInset = (size.width * 0.026)
        .clamp(compact ? 14.0 : 20.0, compact ? 30.0 : 52.0)
        .toDouble();
    final topInset = (size.height * 0.032)
        .clamp(compact ? 8.0 : 12.0, compact ? 16.0 : 28.0)
        .toDouble();
    final southMeldBottom = handCardSize.height + (compact ? 2.0 : 6.0);
    final southMeldHeight = compact ? 50.0 : 60.0;
    final sideMeldTop = topInset + (compact ? 2.0 : 4.0);
    final sideMeldBottomSafe = size.height - (compact ? 12.0 : 16.0);
    final sideMeldHeight = math.max(0.0, sideMeldBottomSafe - sideMeldTop);
    final sideMeldWidth = sideMeldCardSize.height + (compact ? 20.0 : 22.0);
    final sideMeldGap = compact ? 6.0 : 10.0;
    final horizontalMeldInset = (size.width * 0.25)
        .clamp(compact ? 126.0 : 210.0, compact ? 180.0 : 390.0)
        .toDouble();

    final (centerX, centerY) = switch (slot.seat) {
      PlayerSeat.south => (
        size.width * 0.5,
        size.height - southMeldBottom - southMeldHeight * 0.5,
      ),
      PlayerSeat.north => (
        size.width * 0.5,
        topInset +
            opponentCardSize.height +
            (compact ? 18.0 : 24.0) +
            (compact ? 58.0 : 70.0) * 0.5,
      ),
      PlayerSeat.west => (
        edgeInset + sideRailWidth + sideMeldGap + sideMeldWidth * 0.5,
        sideMeldTop + sideMeldHeight * 0.5,
      ),
      PlayerSeat.east => (
        size.width -
            edgeInset -
            sideRailWidth -
            sideMeldGap -
            sideMeldWidth * 0.5,
        sideMeldTop + sideMeldHeight * 0.5,
      ),
    };

    final laneInset = switch (slot.seat) {
      PlayerSeat.south || PlayerSeat.north => horizontalMeldInset,
      PlayerSeat.east || PlayerSeat.west => 0.0,
    };
    final clampedCenterX = centerX.clamp(
      laneInset + flightCardSize.width * 0.5,
      size.width - laneInset - flightCardSize.width * 0.5,
    );
    return _centeredFlightOffset(
      clampedCenterX.toDouble(),
      centerY,
      flightCardSize,
    );
  }
}

class _OpeningDealOverlay extends StatelessWidget {
  const _OpeningDealOverlay({
    required this.sequence,
    required this.progress,
    required this.theme,
    required this.flightDuration,
    required this.stagger,
  });

  final DealSequence sequence;
  final double progress;
  final HareegCardTheme theme;
  final Duration flightDuration;
  final Duration stagger;

  @override
  Widget build(BuildContext context) {
    final curve = MotionScope.of(context).curve(Curves.easeOutCubic);
    final elapsed = sequence.elapsedAt(
      progress: progress,
      flightDuration: flightDuration,
      stagger: stagger,
    );
    return IgnorePointer(
      key: const ValueKey('opening-deal-overlay'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final cardSize = constraints.maxHeight <= 390
              ? const Size(44, 62)
              : const Size(58, 82);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (final step in sequence.steps)
                if (dealStepProgress(
                      elapsed: elapsed,
                      step: step,
                      flightDuration: flightDuration,
                      stagger: stagger,
                    )
                    case final localProgress?)
                  _OpeningDealFlightCard(
                    key: ValueKey('opening-deal-flight-${step.orderIndex}'),
                    step: step,
                    progress: curve.transform(localProgress),
                    theme: theme,
                    viewportSize: size,
                    cardSize: cardSize,
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _OpeningDealFlightCard extends StatelessWidget {
  const _OpeningDealFlightCard({
    super.key,
    required this.step,
    required this.progress,
    required this.theme,
    required this.viewportSize,
    required this.cardSize,
  });

  final DealStep step;
  final double progress;
  final HareegCardTheme theme;
  final Size viewportSize;
  final Size cardSize;

  @override
  Widget build(BuildContext context) {
    final begin = _resolveFlightPoint(
      _FlightAnchor.stock.alignment,
      viewportSize,
      cardSize,
      null,
    );
    final end = _resolveFlightPoint(
      _alignmentForSeat(step.seat),
      viewportSize,
      cardSize,
      step.endHandSlot,
    );
    final value = progress.clamp(0.0, 1.0).toDouble();
    final dx = end.dx - begin.dx;
    final dy = end.dy - begin.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    // Throw height tracks distance so cross-table deals look airborne and
    // self-deals only get a small hop. Clamped so very long flights stay
    // grounded enough to read.
    final arcHeight = (distance * 0.16).clamp(28.0, 84.0).toDouble();
    final lifted = math.sin(value * math.pi) * arcHeight;
    final offset = Offset.lerp(begin, end, value)!;
    // Landing settle: a tiny scale punch in the last sliver of flight so
    // cards feel like they actually meet the felt.
    final double landingScale;
    if (value < 0.86) {
      landingScale = 1.0;
    } else if (value < 0.93) {
      landingScale = 1.0 + (value - 0.86) / 0.07 * 0.045;
    } else {
      landingScale = 1.045 - (value - 0.93) / 0.07 * 0.045;
    }
    // Shadow tapers as the card settles, so it collapses onto the table at
    // touchdown. Drawn as a [BoxShadow] rather than `Material(elevation: ...)`
    // — Material's per-frame elevation recompute multiplied across ~57
    // simultaneous flight cards was a measurable hit on lower-end devices.
    final shadowBlur = 10 + (1 - value) * 8;
    final shadowOffset = Offset(0, 4 + (1 - value) * 4);
    return Positioned(
      left: offset.dx,
      top: offset.dy - lifted,
      child: Transform.rotate(
        angle: (1 - value) * -0.10,
        child: Transform.scale(
          scale: landingScale,
          child: Opacity(
            opacity: (1 - (value * 0.18)).clamp(0.0, 1.0).toDouble(),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(LoungeTokens.radiusCard),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x66000000),
                    blurRadius: shadowBlur,
                    offset: shadowOffset,
                  ),
                ],
              ),
              child: HareegCardView(
                theme: theme,
                card: step.card,
                size: cardSize,
                faceDown: step.faceDown,
                visualState: CardVisualState.selected,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Offset _resolveFlightPoint(
    Alignment alignment,
    Size size,
    Size cardSize,
    SeatHandFlightSlot? handSlot,
  ) {
    if (handSlot != null) {
      return _resolveSeatHandSlot(handSlot, size, cardSize);
    }
    return Offset(
      ((alignment.x + 1) / 2 * size.width) - cardSize.width / 2,
      ((alignment.y + 1) / 2 * size.height) - cardSize.height / 2,
    );
  }

}

class _FeedbackChip extends StatelessWidget {
  const _FeedbackChip({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? LoungeTokens.deepRed : LoungeTokens.goldAccent;
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(
        horizontal: LoungeTokens.space3,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              message,
              style: LoungeTokens.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

void _debugTableLog(String message) {
  assert(() {
    debugPrint('[hareeg:table] $message');
    return true;
  }());
}

String _debugSeatCounts(ClassicHareegGameController controller) {
  return PlayerSeat.values
      .map((seat) => '${seat.name}:${controller.cardCountFor(seat)}')
      .join(',');
}

String _debugActionSummary(Iterable<String> actionIds) {
  final ids = actionIds.toList(growable: false);
  if (ids.isEmpty) {
    return '[]';
  }
  const maxShown = 5;
  final shown = ids.take(maxShown).join(', ');
  if (ids.length <= maxShown) {
    return '[$shown]';
  }
  return '[$shown, +${ids.length - maxShown} more]';
}

bool _jokerAidsEnabledFor(ClassicHareegSetup setup) {
  return setup.rulePreset != RulePreset.hardTable17;
}

String _inspectTitle(
  HareegCard card,
  AppStrings strings, {
  required bool jokerAidsEnabled,
}) {
  final identity = card.identity;
  if (identity != null) {
    return strings.cardName(identity);
  }

  if (!jokerAidsEnabled) {
    return strings.joker;
  }

  final represented = card.representedIdentity;
  if (represented != null) {
    return strings.jokerAs(represented);
  }

  return strings.joker;
}

String? _inspectBody(
  HareegCard card,
  TableAids aids, {
  required AppStrings strings,
  required bool jokerAidsEnabled,
}) {
  if (aids == TableAids.tableMode) {
    return null;
  }

  if (card.isJoker && !jokerAidsEnabled) {
    return null;
  }

  final identity = card.effectiveIdentity;
  if (identity == null) {
    return aids == TableAids.guided
        ? strings.unassignedJokerGuided
        : strings.unassignedJoker;
  }

  final value = identity.rank.value;
  if (card.isJoker) {
    return aids == TableAids.guided
        ? strings.representedJokerGuided(strings.cardName(identity))
        : '${strings.representedJoker(strings.cardName(identity))} '
              '${strings.cardValue(value)}';
  }

  if (aids == TableAids.guided) {
    return strings.cardValueGuided(value);
  }
  return strings.cardValueWithSuit(value, strings.suitWord(identity.suit));
}
