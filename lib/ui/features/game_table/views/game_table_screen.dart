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
import '../../../../domain/classic_hareeg/rules/opening_rules.dart' show PlacedMeld;
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_state.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/cards/card_view.dart';
import '../../../core/audio/table_audio.dart';
import '../../../core/haptics/table_haptics.dart';
import '../../../core/motion/motion_speed.dart';
import '../../../core/scopes/app_scopes.dart';
import '../../../core/strictness/strictness_ui_profile.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../animations/deal_choreography.dart';
import '../meld_flight_controller.dart';
import '../table_action_presentation_planner.dart';
import '../table_card_flight_planner.dart';
import '../table_flight_anchors.dart';
import '../table_flight_geometry.dart';
import '../table_hand_interaction_state.dart';
import '../table_human_action_flow_planner.dart';
import '../table_human_action_start_planner.dart';
import '../table_interaction_adapter.dart';
import '../table_persistence_planner.dart';
import '../table_turn_flow_planner.dart';
import '../widgets/meld_flight_overlay.dart';
import '../widgets/pause_overlay.dart';
import '../widgets/physical_table_playfield.dart';
import '../widgets/score_overlay.dart';
import '../widgets/table_background.dart';
import '../../match_over/views/match_over_screen.dart';

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
  static const _matchEndOverlayDwell = Duration(milliseconds: 1400);
  static const _jokerDeclarationFeedbackDuration = Duration(seconds: 3);
  static const _fastJokerDeclarationFeedbackDuration = Duration(
    milliseconds: 1500,
  );

  late ClassicHareegGameController _controller;
  final _handInteraction = ClassicHareegHandInteractionState();
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
  Set<String>? _placedJokerSnapshot;
  // FIFO of joker declaration cues waiting to display. Used when more than
  // one joker is placed in quick succession (e.g. CPU plays two meld sets
  // back-to-back, each with a joker) so each cue gets its own dwell instead
  // of being clobbered by the next one.
  final List<({PlayerSeat seat, CardIdentity identity})> _jokerCueQueue = [];
  bool _isJokerCueActive = false;
  final List<_CardFlight> _activeFlights = [];
  late final MeldFlightController _meldFlight;
  DealChoreography? _dealChoreography;
  bool _pendingDealBuild = false;
  HareegCard? _inspectedCard;
  // Card id of the most recently rejected Strict-tier discard. While set, the
  // south hand renders a brief flash on this card so the human can see which
  // discard the +3 penalty refers to.
  String? _revertFlashCardId;
  Timer? _revertFlashTimer;
  static const _revertFlashDuration = Duration(milliseconds: 1100);
  ClassicHareegRoundResultPresentation? _roundResultPresentation;
  final Map<PlayerSeat, int> _matchEliminatedRoundBySeat = {};
  int _flightSerial = 0;

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
    _meldFlight = MeldFlightController(
      handLookup: _cardInHand,
      baseMeldIndexLookup: (seat) => _controller.tableMeldsFor(seat).length,
      isMounted: () => mounted,
    )..addListener(_handleMeldFlightChange);
    _resetHandInteraction();
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
    _revertFlashTimer?.cancel();
    _revertFlashTimer = null;
    _roundAdvanceTimer?.cancel();
    _roundAdvanceTimer = null;
    _dealChoreography?.dispose();
    _dealChoreography = null;
    _meldFlight.removeListener(_handleMeldFlightChange);
    _meldFlight.dispose();
    AppOrientation.usePortrait();
    super.dispose();
  }

  void _handleMeldFlightChange() {
    if (!mounted) return;
    setState(() {});
  }

  void _returnToMainMenu() {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
  }

  void _resetHandInteraction() {
    final initialHand = _controller.handFor(PlayerSeat.south);
    _handInteraction.resetFromHand(
      initialHand,
      widget.preferences.handSortMode,
    );
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
      final afterFramePlan = ClassicHareegTableTurnFlowPlanner.afterFrame(
        isMounted: mounted,
        hasOpeningDealToPlay: _hasOpeningDealToPlay,
        isCpuRunning: _isCpuRunning,
        isOpeningDealRunning: _isOpeningDealRunning,
        isRoundOver: _controller.isRoundOver,
        isHumanTurn: _controller.currentSeat == PlayerSeat.south,
      );
      if (afterFramePlan.action ==
          ClassicHareegTableTurnFlowAction.playOpeningDeal) {
        await _playOpeningDealIfNeeded();
      } else if (afterFramePlan.shouldStop) {
        return;
      }

      final afterOpeningDealPlan =
          ClassicHareegTableTurnFlowPlanner.afterOpeningDeal(
            isMounted: mounted,
            isCpuRunning: _isCpuRunning,
            isOpeningDealRunning: _isOpeningDealRunning,
            isRoundOver: _controller.isRoundOver,
            isHumanTurn: _controller.currentSeat == PlayerSeat.south,
          );
      if (afterOpeningDealPlan.action ==
          ClassicHareegTableTurnFlowAction.runCpuTurns) {
        final didPersistOrNavigate = await _runCpuTurns();
        final afterCpuPlan = ClassicHareegTableTurnFlowPlanner.afterCpuTurns(
          isMounted: mounted,
          didCpuPersistOrNavigate: didPersistOrNavigate,
        );
        if (afterCpuPlan.action ==
            ClassicHareegTableTurnFlowAction.persistTable) {
          await _persistAndMaybeFinish();
        }
        return;
      }
      if (afterOpeningDealPlan.action ==
          ClassicHareegTableTurnFlowAction.persistTable) {
        await _persistAndMaybeFinish();
      }
    });
  }

  bool get _hasOpeningDealToPlay {
    final choreography = _dealChoreography;
    return choreography != null && choreography.sequence.steps.isNotEmpty;
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
    if (choreography == null ||
        choreography.sequence.steps.isEmpty ||
        !mounted) {
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

  Duration get _cpuPostMeldDwell => widget.preferences.fastCpuTurns
      ? _scaledDelay(TableMotion.fastCpuPostMeldDwell)
      : _scaledDelay(TableMotion.cpuPostMeldDwell);

  /// Duration of the multi-card meld flight (fan travel from hand to meld
  /// zone). Used for both CPU and human south melds so the player sees a
  /// consistent "set leaving the hand for the table" beat regardless of seat.
  Duration get _meldFlightDuration => widget.preferences.fastCpuTurns
      ? _scaledDelay(TableMotion.meldFlightFast)
      : _scaledDelay(TableMotion.meldFlightNormal);

  // Joker cue duration shared between the in-card memoryReveal animation and
  // the feedback chip lifetime. Fast-cpu mode shortens both so the cue doesn't
  // outlive the surrounding CPU pacing.
  Duration get _activeJokerChipDuration => widget.preferences.fastCpuTurns
      ? _fastJokerDeclarationFeedbackDuration
      : _jokerDeclarationFeedbackDuration;

  Duration? _activeJokerVisualCueDuration(TableStrictness strictness) {
    final base = strictness.jokerCueDuration;
    if (base == null) return null;
    return widget.preferences.fastCpuTurns
        ? Duration(milliseconds: base.inMilliseconds ~/ 2)
        : base;
  }

  // Actions that materially change the table side need a longer beat before
  // the next CPU action fires; the joker-declaration chip and meld arrival
  // would otherwise stack on top of the immediately-following discard.
  Duration _postActionDwell(String actionId) {
    final kind = ClassicHareegActionIds.describe(actionId).kind;
    switch (kind) {
      case ClassicHareegActionKind.playMeld:
      case ClassicHareegActionKind.playMeldWithJoker:
      case ClassicHareegActionKind.placeCover:
      case ClassicHareegActionKind.replaceJoker:
        return _cpuPostMeldDwell;
      default:
        return _cpuBetweenActionPause;
    }
  }

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
    final strictness = _controller.setup.tableStrictness;
    final jokerDisplay = strictness.jokerDisplay;
    final southHand = _southHandInteraction();
    final southCards = southHand.orderedCards;
    final openingDealFrame = _openingDealFrame(southCards);
    final southIsRemoved = _controller.removedSeats.contains(PlayerSeat.south);
    final visibleSouthCards = openingDealFrame?.southCards ??
        (southIsRemoved ? const <HareegCard>[] : southCards);
    final removedSeats = _controller.removedSeats;
    final visibleCardCounts =
        openingDealFrame?.cardCounts ??
        {
          for (final seat in PlayerSeat.values)
            // Removed seats (Table tier +17) are out of the round; clear
            // their visible hand so the table reflects the round state.
            seat: removedSeats.contains(seat)
                ? 0
                : _controller.cardCountFor(seat),
        };
    final visibleStockCount =
        openingDealFrame?.stockCount ?? _controller.stockCount;
    final tableInteraction = _tableInteraction(southHand);
    final meldSuggestions = strictness.showsMeldPicker
        ? _meldSuggestions(tableInteraction)
        : const <TableMeldSuggestion>[];
    final meldValidation = isHumanTurn && southHand.hasSelection
        ? _controller.singleMeldValidationFor(
            humanSeat,
            southHand.selectedCardIds,
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
        cueDuration: _activeJokerVisualCueDuration(strictness),
        child: Stack(
          children: [
            PhysicalTablePlayfield(
              theme: theme,
              stockCount: visibleStockCount,
              discardPile: _controller.discardPile,
              topDiscard: _controller.topDiscard,
              pendingDiscard: pending,
              cardCounts: visibleCardCounts,
              tableMelds: _tableMeldsForBuild(),
              southCards: visibleSouthCards,
              selectedIds: southHand.selectedIds,
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
              showMeldSuggestions: strictness.showsMeldPicker,
              onMeldSuggestion: (actionId) {
                unawaited(_runHumanAction(actionId));
              },
              isHumanTurn: isHumanTurn,
              isCpuRunning: _isCpuRunning,
              currentSeat: _controller.currentSeat,
              activeSeats: _controller.roundActiveSeats.toSet(),
              southFlashCardId: _revertFlashCardId,
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
            for (final flight in _activeFlights)
              Positioned.fill(
                key: ValueKey('flight-${flight.serial}'),
                child: _CardFlightOverlay(
                  flight: flight,
                  theme: theme,
                  duration: flight.duration,
                ),
              ),
            for (final meld in _meldFlight.activeFlights)
              Positioned.fill(
                key: ValueKey('meld-flight-${meld.serial}'),
                child: MeldFlightOverlay(
                  flight: meld,
                  theme: theme,
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
                motionSpeed: widget.preferences.motionSpeed,
                fastCpuTurns: widget.preferences.fastCpuTurns,
                hapticsEnabled: widget.preferences.hapticsEnabled,
                soundEnabled: widget.preferences.soundEnabled,
                highContrastCards: widget.preferences.highContrastCards,
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
                strictness: strictness,
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

  /// Returns reconciled hand ordering and selected-card state.
  TableHandInteractionSnapshot _southHandInteraction() {
    return _handInteraction.reconcile(_controller.handFor(PlayerSeat.south));
  }

  /// Returns the human hand in the player's chosen display order.
  List<HareegCard> _orderedSouthHand() {
    return _southHandInteraction().orderedCards;
  }

  void _reorderHand(HareegCard card, int targetIndex) {
    if (!_handInteraction.reorder(card, targetIndex)) return;
    setState(() {});
  }

  ClassicHareegTableInteractionAdapter _tableInteraction([
    TableHandInteractionSnapshot? southHand,
  ]) {
    final hand = southHand ?? _southHandInteraction();
    return ClassicHareegTableInteractionAdapter(
      reader: ClassicHareegControllerTableInteractionReader(_controller),
      seat: PlayerSeat.south,
      selectedCardIds: hand.selectedCardIds,
      handCards: hand.orderedCards,
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
    final cardIds = _southHandInteraction().selectedCardIds;
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
      _handInteraction.toggleSelection(card);
    });
  }

  void _showCardInspect(HareegCard card) {
    unawaited(_haptics.fire(TableHapticEvent.cardTap));
    setState(() => _inspectedCard = card);
  }

  /// Surfaces the Strict-tier +3 toast and pulses the offending card so the
  /// human can see which discard was rejected. Caller already wrapped this
  /// in a `setState`.
  void _emitMistakeRevertFeedback({
    required String message,
    String? revertedCardId,
  }) {
    _replaceHumanFeedback(message, isError: true);
    _revertFlashTimer?.cancel();
    _revertFlashCardId = revertedCardId;
    if (revertedCardId != null) {
      _revertFlashTimer = Timer(_scaledDelay(_revertFlashDuration), () {
        if (!mounted) return;
        setState(() {
          if (_revertFlashCardId == revertedCardId) {
            _revertFlashCardId = null;
          }
        });
      });
    }
  }

  void _replaceHumanFeedback(String? message, {required bool isError}) {
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
    // Any non-joker feedback (errors, hints, success messages) supersedes
    // pending joker cues — drop the queue so we don't pop them on top.
    _jokerCueQueue.clear();
    _isJokerCueActive = false;
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

  Set<String> _capturePlacedJokerIds() {
    final ids = <String>{};
    for (final seat in PlayerSeat.values) {
      for (final meld in _controller.tableMeldsFor(seat)) {
        for (final card in meld.cards) {
          if (card.isJoker && card.representedIdentity != null) {
            ids.add(card.id);
          }
        }
      }
    }
    return ids;
  }

  List<({PlayerSeat seat, CardIdentity identity})> _consumeJokerPlacements() {
    final before = _placedJokerSnapshot;
    _placedJokerSnapshot = null;
    if (before == null) return const [];
    final placements = <({PlayerSeat seat, CardIdentity identity})>[];
    for (final seat in PlayerSeat.values) {
      for (final meld in _controller.tableMeldsFor(seat)) {
        for (final card in meld.cards) {
          if (!card.isJoker) continue;
          final represented = card.representedIdentity;
          if (represented == null) continue;
          if (before.contains(card.id)) continue;
          placements.add((seat: seat, identity: represented));
        }
      }
    }
    return placements;
  }

  /// Drains the post-apply joker snapshot diff and enqueues every new joker
  /// for a sequential cue. Each cue gets a full dwell — when several jokers
  /// land back-to-back the chips show in order rather than clobbering each
  /// other. Caller controls whether the enqueue happens inside its own
  /// `setState` (human path) or needs one (CPU path).
  void _emitFeedbackForFirstNewJoker({required bool needsSetState}) {
    final newJokers = _consumeJokerPlacements();
    if (newJokers.isEmpty) return;
    void run() {
      _jokerCueQueue.addAll(newJokers);
      _processNextJokerCue();
    }

    if (needsSetState) {
      if (!mounted) return;
      setState(run);
    } else {
      run();
    }
  }

  void _processNextJokerCue() {
    if (_isJokerCueActive) return;
    if (_jokerCueQueue.isEmpty) return;
    final next = _jokerCueQueue.removeAt(0);
    _isJokerCueActive = true;
    _emitJokerDeclarationFeedback(seat: next.seat, identity: next.identity);
  }

  void _emitJokerDeclarationFeedback({
    required PlayerSeat seat,
    required CardIdentity identity,
  }) {
    final strings = context.strings;
    final message = seat == PlayerSeat.south
        ? strings.youDeclaredJoker(identity)
        : strings.jokerDeclaredBySeat(seat, identity);
    unawaited(_audio.play(TableSoundEvent.jokerDeclared));
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
    _humanFeedback = message;
    _humanFeedbackIsError = false;
    final duration = _scaledDelay(_activeJokerChipDuration);
    _feedbackTimer = Timer(duration, () {
      if (!mounted) {
        _isJokerCueActive = false;
        return;
      }
      setState(() {
        if (_humanFeedback == message && !_humanFeedbackIsError) {
          _humanFeedback = null;
        }
        _isJokerCueActive = false;
      });
      // Pump the queue so the next pending cue gets its own dwell window.
      _processNextJokerCue();
    });
  }

  /// Plays a stock→seat / discard→seat / seat→discard card-flight for a CPU
  /// action so the human can see which seat acted and where the card went.
  Future<void> _playFlightForCpuAction(PlayerSeat seat, String actionId) async {
    final descriptor = ClassicHareegActionIds.describe(actionId);
    if (descriptor.isMeldPlay) {
      await _playMeldFlight(seat: seat, actionId: actionId);
      return;
    }
    final plan = ClassicHareegActionPresentationPlanner.forCpuAction(
      seat: seat,
      actionId: actionId,
    );
    final flight = _flightForPlan(plan.flight, duration: _cpuFlightDuration);
    if (flight == null) {
      unawaited(_playSound(plan.sound));
      return;
    }
    unawaited(_playSound(plan.sound));
    setState(() => _activeFlights.add(flight));
    await Future<void>.delayed(_cpuFlightDuration);
    if (!mounted) return;
    setState(() => _activeFlights.remove(flight));
  }

  Future<bool> _playFlightForHumanAction(
    TableActionPresentationPlan presentation, {
    required String actionId,
  }) async {
    final descriptor = ClassicHareegActionIds.describe(actionId);
    if (descriptor.isMeldPlay) {
      return _playMeldFlight(
        seat: PlayerSeat.south,
        actionId: actionId,
        sound: presentation.sound,
      );
    }
    final humanFlightDuration = _scaledDelay(const Duration(milliseconds: 230));
    final flight = _flightForPlan(
      presentation.flight,
      duration: humanFlightDuration,
    );
    if (flight == null) return false;
    unawaited(_playSound(presentation.sound));
    setState(() => _activeFlights.add(flight));
    await Future<void>.delayed(humanFlightDuration);
    if (!mounted) return true;
    setState(() => _activeFlights.remove(flight));
    return true;
  }

  _CardFlight? _flightForPlan(
    TableActionFlightPlan? plan, {
    required Duration duration,
  }) {
    final serial = _flightSerial + 1;
    final realization = TableCardFlightPlanner.realize(
      presentation: plan,
      stockBack: _backSeed(serial),
      topDiscard: _controller.topDiscard,
      pendingDiscard: _controller.pendingDiscard,
      handCardFor: _cardInHand,
      southHandCardSlotFor: _southHandCardSlot,
      appendHandSlotFor: _appendHandSlotForSeat,
      lastHandSlotFor: _lastHandSlotForSeat,
    );
    final card = realization.card;
    final presentation = realization.presentation;
    if (!realization.canRender || card == null || presentation == null) {
      return null;
    }
    _flightSerial = serial;

    return _CardFlight(
      serial: serial,
      card: card,
      faceDown: realization.faceDown,
      begin: _flightBegin(presentation),
      end: _flightEnd(presentation),
      duration: duration,
      beginHandSlot: realization.beginHandSlot,
      endHandSlot: realization.endHandSlot,
      endMeldSlot: realization.endMeldSlot,
    );
  }

  /// Animates a `play-meld` action via [MeldFlightController]. The
  /// orchestrator owns the per-set decomposition and inter-set sequencing;
  /// the screen just supplies durations and the sound hook.
  Future<bool> _playMeldFlight({
    required PlayerSeat seat,
    required String actionId,
    TableSoundEvent? sound,
  }) {
    return _meldFlight.playMeld(
      seat: seat,
      actionId: actionId,
      flightDuration: _meldFlightDuration,
      interSetDelay: _meldInterSetDelay,
      onSoundPlay: () =>
          unawaited(_playSound(sound ?? TableSoundEvent.meldPlace)),
    );
  }

  Duration get _meldInterSetDelay => widget.preferences.fastCpuTurns
      ? _scaledDelay(TableMotion.meldInterSetDelayFast)
      : _scaledDelay(TableMotion.meldInterSetDelayNormal);

  Alignment _flightBegin(TableActionFlightPlan plan) {
    return switch (plan.source) {
      TableActionFlightSource.stockBack => TableFlightAnchors.stock,
      TableActionFlightSource.topDiscard => TableFlightAnchors.discard,
      TableActionFlightSource.pendingDiscard ||
      TableActionFlightSource.handCard => TableFlightAnchors.seatHand(plan.seat),
    };
  }

  Alignment _flightEnd(TableActionFlightPlan plan) {
    return switch (plan.destination) {
      TableActionFlightDestination.seatHand =>
        TableFlightAnchors.seatHand(plan.seat),
      TableActionFlightDestination.discardPile => TableFlightAnchors.discard,
      TableActionFlightDestination.tableMeld =>
        TableFlightAnchors.seatHand(plan.seat),
    };
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

  HareegCard? _cardInHand(PlayerSeat seat, String id) {
    for (final card in _controller.handFor(seat)) {
      if (card.id == id) return card;
    }
    return null;
  }

  /// Builds the `tableMelds` map handed to the playfield. When no flight has
  /// landed a ghost meld yet, reuses the controller's lists directly so the
  /// common case avoids 4 list concatenations per frame.
  Map<PlayerSeat, List<PlacedMeld>> _tableMeldsForBuild() {
    if (!_meldFlight.hasPendingSettled) {
      return {
        for (final seat in PlayerSeat.values)
          seat: _controller.tableMeldsFor(seat),
      };
    }
    return {
      for (final seat in PlayerSeat.values)
        seat: [
          ..._controller.tableMeldsFor(seat),
          ...?_meldFlight.pendingFor(seat),
        ],
    };
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
    final startPlan = ClassicHareegHumanActionStartPlanner.start(
      actionId: actionId,
      playFlight: playFlight,
      isCpuRunning: _isCpuRunning,
      isOpeningDealRunning: _isOpeningDealRunning,
      isHumanActionPending: _isHumanActionPending,
    );
    if (!startPlan.shouldStart) return;
    _isHumanActionPending = startPlan.shouldLockInput;
    // Rebuild so south controls/playfield pick up the pending-lock immediately.
    setState(() {});
    final totalWatch = Stopwatch()..start();
    _debugTableLog(
      'human action start action=$actionId current=${_controller.currentSeat.name} '
      'phase=${_controller.turnPhase} pending=${_controller.pendingDiscard?.label}',
    );
    try {
      var flightPlayed = false;
      final presentation = startPlan.presentation;
      if (startPlan.shouldPlayFlight && presentation != null) {
        flightPlayed = await _playFlightForHumanAction(
          presentation,
          actionId: actionId,
        );
      }
      final applyGate = ClassicHareegHumanActionStartPlanner.afterPreApply(
        isMounted: mounted,
        plannedFlight: startPlan.shouldPlayFlight,
        flightPlayed: flightPlayed,
      );
      if (!applyGate.shouldApply) return;
      await _completeHumanAction(
        actionId,
        soundPlayedWithFlight: applyGate.soundPlayedWithFlight,
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
    // Only meld / cover / joker-replacement actions can introduce a newly
    // declared joker, so skip the seat × meld × card snapshot scan for the
    // many draw/discard actions that can't.
    final descriptor = ClassicHareegActionIds.describe(actionId);
    _placedJokerSnapshot = descriptor.canPlaceJoker
        ? _capturePlacedJokerIds()
        : null;
    final applyWatch = Stopwatch()..start();
    final result = _controller.applyAction(actionId);
    applyWatch.stop();
    if (!result.isSuccess) {
      _placedJokerSnapshot = null;
    }
    _debugTableLog(
      'human action applied action=$actionId success=${result.isSuccess} '
      'applyElapsed=${applyWatch.elapsedMilliseconds}ms '
      'totalElapsed=${totalWatch.elapsedMilliseconds}ms '
      'current=${_controller.currentSeat.name} phase=${_controller.turnPhase}',
    );
    final flowPlan = ClassicHareegHumanActionFlowPlanner.afterApply(
      actionId: actionId,
      isSuccess: result.isSuccess,
      message: result.message,
      soundPlayedWithFlight: soundPlayedWithFlight,
      wasReverted: result.wasReverted,
    );

    final haptic = flowPlan.haptic;
    if (haptic != null) {
      unawaited(_haptics.fire(haptic));
    }
    final sound = flowPlan.sound;
    if (sound != null) {
      unawaited(_playSound(sound));
    }
    setState(() {
      if (result.wasReverted) {
        // Strict +3: surface the penalty toast and flash the offending card
        // so the human sees which discard was rejected. Don't use the
        // generic feedback line — the reverted card id needs to flow into
        // the south-hand visual cue.
        _emitMistakeRevertFeedback(
          message: result.message,
          revertedCardId: result.revertedCardId,
        );
      } else {
        _replaceHumanFeedback(
          flowPlan.feedbackMessage,
          isError: flowPlan.feedbackIsError,
        );
      }
      // Multi-joker melds report only the leftmost declaration.
      if (result.isSuccess && !result.wasReverted) {
        _emitFeedbackForFirstNewJoker(needsSetState: false);
      }
      // Controller now owns the real melds; drop UI-only ghosts published
      // by the per-set flight so we don't double-render.
      _meldFlight.dropPendingSettledFor(PlayerSeat.south);
      if (flowPlan.shouldClearSelection) {
        _handInteraction.clearSelection();
      }
    });
    if (!flowPlan.didApplyAction) {
      return;
    }
    if (flowPlan.shouldEnsureFiftyTicker) {
      _ensureFiftyTicker();
    }
    if (flowPlan.shouldPersist) {
      await _persistAndMaybeFinish();
    }
    if (!mounted) return;
    if (flowPlan.shouldRunCpuAfterPersist) {
      await _runCpuTurns();
    }
    totalWatch.stop();
    _debugTableLog(
      'human action end action=$actionId '
      'elapsed=${totalWatch.elapsedMilliseconds}ms '
      'current=${_controller.currentSeat.name} phase=${_controller.turnPhase}',
    );
  }

  Future<void> _playSound(TableSoundEvent? event) async {
    if (event == null) return;
    await _audio.play(event);
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
            final descriptor = ClassicHareegActionIds.describe(decision.actionId);
            _placedJokerSnapshot = descriptor.canPlaceJoker
                ? _capturePlacedJokerIds()
                : null;
            return mounted;
          },
          afterApply: (decision, result) async {
            _debugTableLog(
              'cpu step ${decision.step.index} applied '
              'action=${decision.actionId} success=${result.isSuccess} '
              'current=${_controller.currentSeat.name} '
              'phase=${_controller.turnPhase}',
            );
            if (result.isSuccess) {
              _emitFeedbackForFirstNewJoker(needsSetState: true);
            } else {
              _placedJokerSnapshot = null;
            }
            // Controller has the real melds now; drop UI-only ghosts from
            // the per-set flight.
            _meldFlight.dropPendingSettledFor(decision.seat);
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
          beforeNextAction: (previous) async {
            final dwell = _postActionDwell(previous.actionId);
            if (dwell > Duration.zero) {
              await Future<void>.delayed(dwell);
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
      // When the human is out of the round we cannot let the CPU loop pause
      // on the safety cap — there is no human to take over, so the round
      // would deadlock waiting for input. Re-enter the loop instead; the
      // round will end naturally on stock exhaustion or a CPU finish.
      final humanRemoved =
          _controller.removedSeats.contains(PlayerSeat.south);
      final shouldAutoRestart = hitCpuSafetyLimit && humanRemoved;
      setState(() {
        _isCpuRunning = false;
        _activeFlights.clear();
        _meldFlight.clear();
        if (hitCpuSafetyLimit && !shouldAutoRestart) {
          _replaceHumanFeedback(
            context.strings.cpuTurnSafetyCapReached(
              _cpuActionLimit,
              _controller.currentSeat,
            ),
            isError: true,
          );
        }
      });
      if (shouldAutoRestart && mounted) {
        // Defer to the next microtask so the surrounding setState commits
        // before the recursive call grabs the running flag again.
        scheduleMicrotask(() {
          if (!mounted) return;
          unawaited(_runCpuTurns());
        });
      }
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
          _activeFlights.clear();
          _meldFlight.clear();
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
    final isRoundOver = _controller.isRoundOver;
    final scoreView = _controller.scoreView;
    final persistencePlan = ClassicHareegTablePersistencePlanner.plan(
      isRoundOver: isRoundOver,
      activeSnapshot: isRoundOver ? null : _controller.toSnapshot(),
      nextRoundSnapshot: isRoundOver ? _controller.nextRoundSnapshot() : null,
      roundResult: _controller.roundResult,
      scoreView: scoreView,
    );
    _debugTableLog(
      'persist start roundOver=$isRoundOver '
      'current=${_controller.currentSeat.name} phase=${_controller.turnPhase} '
      'stock=${_controller.stockCount} discard=${_controller.discardPile.length} '
      'counts=${_debugSeatCounts(_controller)}',
    );
    var persistenceSucceeded = true;
    final persistencePath = persistencePlan.logPath;
    try {
      switch (persistencePlan.action) {
        case ClassicHareegTablePersistenceAction.saveActiveMatch:
        case ClassicHareegTablePersistenceAction.saveNextRound:
          final snapshot = persistencePlan.snapshotToSave;
          if (snapshot == null) {
            throw StateError('Persistence plan is missing a snapshot.');
          }
          await widget.matchRepository.saveActiveMatch(snapshot);
        case ClassicHareegTablePersistenceAction.abandonActiveMatch:
          await widget.matchRepository.abandonActiveMatch();
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
    final resultPresentation = persistencePlan.roundResultPresentation;
    if (persistenceSucceeded && resultPresentation != null) {
      _debugTableLog('round result overlay requested');
      _showRoundResultOverlay(resultPresentation);
    }
    return persistenceSucceeded;
  }

  void _showRoundResultOverlay(
    ClassicHareegRoundResultPresentation presentation,
  ) {
    if (_roundResultPresentation != null) {
      return;
    }
    _rememberEliminatedRoundsFromController();
    unawaited(_haptics.fire(TableHapticEvent.roundEnd));
    unawaited(_audio.play(TableSoundEvent.roundEnd));
    setState(() {
      _scoreOpen = false;
      _pauseOpen = false;
      _inspectedCard = null;
      _roundResultPresentation = presentation;
    });
    final nextSnapshot = presentation.nextSnapshot;
    if (nextSnapshot == null) {
      _roundAdvanceTimer?.cancel();
      _roundAdvanceTimer = Timer(_scaledDelay(_matchEndOverlayDwell), () {
        if (!mounted) return;
        _openMatchOver(presentation);
      });
      return;
    }
    _roundAdvanceTimer?.cancel();
    _roundAdvanceTimer = Timer(_roundResultDisplayDuration, () {
      if (!mounted) return;
      _advanceToNextRound(nextSnapshot);
    });
  }

  void _rememberEliminatedRoundsFromController() {
    _matchEliminatedRoundBySeat.addAll(_controller.seatEliminatedRound);
  }

  void _openMatchOver(ClassicHareegRoundResultPresentation presentation) {
    _rememberEliminatedRoundsFromController();
    _roundAdvanceTimer?.cancel();
    _roundAdvanceTimer = null;
    _fiftyTicker?.cancel();
    _fiftyTicker = null;
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
    _dealChoreography?.dispose();
    _dealChoreography = null;
    Navigator.of(context).pushReplacementNamed(
      AppRoutes.matchOver,
      arguments: MatchOverArguments(
        result: presentation.result,
        progress: presentation.progress,
        previousScores: presentation.previousScores,
        roundsPlayed: _controller.roundNumber,
        setup: widget.setup,
        eliminatedRound: Map<PlayerSeat, int>.unmodifiable(
          _matchEliminatedRoundBySeat,
        ),
      ),
    );
  }

  void _advanceToNextRound(ClassicHareegMatchSnapshot snapshot) {
    _rememberEliminatedRoundsFromController();
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
      _resetHandInteraction();
      _dealChoreography = _buildDealChoreography();
      _isCpuRunning = false;
      _scoreOpen = false;
      _pauseOpen = false;
      _fiftyPulse = false;
      _humanFeedback = null;
      _humanFeedbackIsError = false;
      _activeFlights.clear();
      _meldFlight.clear();
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

class _RoundResultOverlay extends StatelessWidget {
  const _RoundResultOverlay({
    required this.presentation,
    required this.onContinueNow,
    required this.onReturnToMenu,
    required this.onDismiss,
  });

  final ClassicHareegRoundResultPresentation presentation;
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
  final ClassicHareegRoundResultPresentation presentation;
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

String _roundDetail(
  ClassicHareegRoundResultPresentation presentation,
  AppStrings strings,
) {
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
    required this.strictness,
    required this.onClose,
  });

  final HareegCard card;
  final HareegCardTheme theme;
  final TableStrictness strictness;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final highContrast = CardContrastScope.enabledOf(context);
    final revealsRepresented = strictness.longPressRevealsRepresented;
    final title = _inspectTitle(
      card,
      strings,
      revealsRepresented: revealsRepresented,
    );
    final body = _inspectBody(card, strictness, strings: strings);
    final inspectJokerDisplay = revealsRepresented
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
    required this.duration,
    this.faceDown = false,
    this.beginHandSlot,
    this.endHandSlot,
    this.endMeldSlot,
  });

  final int serial;
  final HareegCard card;
  final Alignment begin;
  final Alignment end;
  final Duration duration;
  final bool faceDown;
  final SeatHandFlightSlot? beginHandSlot;
  final SeatHandFlightSlot? endHandSlot;
  final TableMeldFlightSlot? endMeldSlot;
}

class _CardFlightOverlay extends StatelessWidget {
  const _CardFlightOverlay({
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
          final begin = resolveFlightAnchor(
            flight.begin,
            size,
            cardSize,
            handSlot: flight.beginHandSlot,
          );
          final end = resolveFlightAnchor(
            flight.end,
            size,
            cardSize,
            handSlot: flight.endHandSlot,
            meldSlot: flight.endMeldSlot,
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
    final begin = resolveFlightAnchor(
      TableFlightAnchors.stock,
      viewportSize,
      cardSize,
    );
    final end = resolveFlightAnchor(
      TableFlightAnchors.seatLane(step.seat),
      viewportSize,
      cardSize,
      handSlot: step.endHandSlot,
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

String _inspectTitle(
  HareegCard card,
  AppStrings strings, {
  required bool revealsRepresented,
}) {
  final identity = card.identity;
  if (identity != null) {
    return strings.cardName(identity);
  }

  if (!revealsRepresented) {
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
  TableStrictness strictness, {
  required AppStrings strings,
}) {
  if (card.isJoker && !strictness.longPressRevealsRepresented) {
    return null;
  }

  final isCoaching = strictness.inspectVerbosity == InspectVerbosity.coaching;
  final identity = card.effectiveIdentity;
  if (identity == null) {
    return isCoaching ? strings.unassignedJokerGuided : strings.unassignedJoker;
  }

  final value = identity.rank.value;
  if (card.isJoker) {
    return isCoaching
        ? strings.representedJokerGuided(strings.cardName(identity))
        : '${strings.representedJoker(strings.cardName(identity))} '
              '${strings.cardValue(value)}';
  }

  if (isCoaching) {
    return strings.cardValueGuided(value);
  }
  return strings.cardValueWithSuit(value, strings.suitWord(identity.suit));
}
