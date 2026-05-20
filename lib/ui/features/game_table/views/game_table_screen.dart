import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../cpu/classic_hareeg/cpu_strategy.dart';
import '../../../../data/persistence/match_repository.dart';
import '../../../../data/persistence/preferences_repository.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_round.dart';
import '../../../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../domain/classic_hareeg/rules/match_progression_rules.dart';
import '../../../../domain/classic_hareeg/rules/meld_validator.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_state.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/cards/card_view.dart';
import '../../../core/aids/table_aids.dart';
import '../../../core/haptics/table_haptics.dart';
import '../../../core/motion/motion_speed.dart';
import '../../../core/scopes/app_scopes.dart';
import '../../../core/theme/lounge_tokens.dart';
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

class _GameTableScreenState extends State<GameTableScreen> {
  static const _cpuActionLimit = 64;
  static const _successFeedbackDuration = Duration(milliseconds: 1400);
  static const _errorFeedbackDuration = Duration(milliseconds: 2400);
  static const _roundResultDisplayDuration = Duration(milliseconds: 2400);

  late ClassicHareegGameController _controller;
  final _selectedCardIds = <String>{};
  bool _isCpuRunning = false;
  bool _scoreOpen = false;
  bool _pauseOpen = false;
  bool _fiftyPulse = false;
  String? _humanFeedback;
  bool _humanFeedbackIsError = false;
  Timer? _fiftyTicker;
  Timer? _feedbackTimer;
  Timer? _roundAdvanceTimer;
  _CardFlight? _cardFlight;
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
    _debugTableLog(
      'init snapshot=${snapshot != null} current=${_controller.currentSeat.name} '
      'phase=${_controller.turnPhase} stock=${_controller.stockCount} '
      'discard=${_controller.discardPile.length} '
      'counts=${_debugSeatCounts(_controller)}',
    );
    _ensureFiftyTicker();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final didPersistOrNavigate = await _runCpuTurns();
      if (!didPersistOrNavigate && mounted) {
        await _persistAndMaybeFinish();
      }
    });
  }

  @override
  void dispose() {
    _fiftyTicker?.cancel();
    _fiftyTicker = null;
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
    _roundAdvanceTimer?.cancel();
    _roundAdvanceTimer = null;
    AppOrientation.usePortrait();
    super.dispose();
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
    final fiftyOpen =
        _controller.fiftySecondsRemaining != null &&
        _controller.fiftySecondsRemaining! > 0;
    if (fiftyOpen && _fiftyTicker == null) {
      _fiftyTicker = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted) return;
        if (_controller.fiftySecondsRemaining == null) {
          _fiftyTicker?.cancel();
          _fiftyTicker = null;
          return;
        }
        setState(() {});
      });
    } else if (!fiftyOpen && _fiftyTicker != null) {
      _fiftyTicker?.cancel();
      _fiftyTicker = null;
    }
  }

  TableHaptics get _haptics => HapticsScope.of(context);

  Duration _scaledDelay(Duration base) => MotionScope.of(context).scale(base);

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final humanSeat = PlayerSeat.south;
    final isHumanTurn = _controller.currentSeat == humanSeat && !_isCpuRunning;
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
    final meldSuggestions = aids.showsMeldPicker
        ? _meldSuggestions(southCards)
        : const <TableMeldSuggestion>[];
    final meldValidation = isHumanTurn && _selectedCardIds.isNotEmpty
        ? _controller.singleMeldValidationFor(
            humanSeat,
            _selectedCardIds.toList(),
          )
        : null;
    final primaryMeldAction = isHumanTurn
        ? _selectedMeldAction(meldValidation)
        : null;
    final canPlayMeld = primaryMeldAction != null;
    final hasOpened = _controller.openingState.hasOpened(humanSeat);
    final meldCtaValue = canPlayMeld ? (meldValidation?.value ?? 0) : null;

    final body = TableBackground(
      surface: widget.preferences.tableSurfaceTheme,
      child: JokerDisplayScope(
        display: jokerDisplay,
        child: Stack(
          children: [
            PhysicalTablePlayfield(
              theme: theme,
              stockCount: _controller.stockCount,
              discardPile: _controller.discardPile,
              topDiscard: _controller.topDiscard,
              pendingDiscard: pending,
              cardCounts: {
                for (final seat in PlayerSeat.values)
                  seat: _controller.cardCountFor(seat),
              },
              tableMelds: {
                for (final seat in PlayerSeat.values)
                  seat: _controller.tableMeldsFor(seat),
              },
              southCards: southCards,
              selectedIds: _selectedCardIds,
              onCardTap: _toggleSelectedCard,
              onCardLongPress: _showCardInspect,
              onReorderHand: _reorderHand,
              canDiscardCard: _canDropCardToDiscard,
              canPlayCardOnTable: _canDropCardToTable,
              canPlaceMeldOnTable: _canPlaceNewMeldOnTable,
              canPlayCardOnMeld: _canDropCardToMeld,
              canRetractMeld: (owner, meldIndex) =>
                  controlActions.contains(
                    ClassicHareegActionIds.returnOpeningMelds,
                  ) &&
                  _controller.canReturnTablePlayFromMeld(owner, meldIndex),
              onDiscardCard: (card) => unawaited(_dropCardToDiscard(card)),
              onPlayCardOnTable: (card) => unawaited(_dropCardToTable(card)),
              onPlayCardOnMeld: (card, owner, meldIndex) =>
                  unawaited(_dropCardToMeld(card, owner, meldIndex)),
              onRetractMeld: (_, _) => unawaited(
                _runHumanAction(ClassicHareegActionIds.returnOpeningMelds),
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
                  : () => unawaited(_runHumanAction(primaryMeldAction)),
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
            LayoutBuilder(
              builder: (context, viewport) {
                // Score / pause snap to the true safe-area corners. We pull
                // them OUTSIDE the SafeArea wrapper and add the safe-area
                // padding ourselves so the buttons can hug the literal edge
                // (the table's border ornament is decorative — buttons go on
                // top of it). Sizes scale with viewport width so tablets
                // don't end up with tiny phone-sized controls.
                final safe = MediaQuery.paddingOf(context);
                final isLarge = viewport.maxWidth >= 900;
                final isTablet = viewport.maxWidth >= 720;
                final buttonSize = isLarge
                    ? 56.0
                    : isTablet
                    ? 48.0
                    : 38.0;
                final iconSize = isLarge
                    ? 30.0
                    : isTablet
                    ? 26.0
                    : 20.0;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: safe.top,
                      left: safe.left,
                      child: _RoundTableButton(
                        tooltip: strings.scores,
                        icon: Icons.bar_chart_rounded,
                        diameter: buttonSize,
                        iconSize: iconSize,
                        onPressed: () => setState(() => _scoreOpen = true),
                      ),
                    ),
                    Positioned(
                      top: safe.top,
                      right: safe.right,
                      child: _RoundTableButton(
                        tooltip: strings.pauseTable,
                        icon: Icons.pause_rounded,
                        diameter: buttonSize,
                        iconSize: iconSize,
                        onPressed: () => setState(() => _pauseOpen = true),
                      ),
                    ),
                    if (_humanFeedback != null)
                      Positioned(
                        top: safe.top + math.max(0.0, (buttonSize - 34) / 2),
                        left: safe.left + buttonSize + 20,
                        right: safe.right + buttonSize + 20,
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

    return Scaffold(
      body: Stack(
        children: [
          body,
          if (_scoreOpen)
            ScoreOverlay(
              scores: _controller.scores,
              activeSeats: _controller.activeSeats,
              starter: _controller.starter,
              currentSeat: _controller.currentSeat,
              roundNumber: _controller.roundNumber,
              onClose: () => setState(() => _scoreOpen = false),
            ),
          if (_pauseOpen)
            PauseOverlay(
              aids: widget.preferences.tableAids,
              motionSpeed: widget.preferences.motionSpeed,
              hapticsEnabled: widget.preferences.hapticsEnabled,
              soundEnabled: widget.preferences.soundEnabled,
              onAidsChanged: (v) => widget.onPreferencesChanged(
                widget.preferences.copyWith(tableAids: v),
              ),
              onMotionSpeedChanged: (v) => widget.onPreferencesChanged(
                widget.preferences.copyWith(motionSpeed: v),
              ),
              onHapticsChanged: (v) => widget.onPreferencesChanged(
                widget.preferences.copyWith(hapticsEnabled: v),
              ),
              onSoundChanged: (v) => widget.onPreferencesChanged(
                widget.preferences.copyWith(soundEnabled: v),
              ),
              onResume: () => setState(() => _pauseOpen = false),
              onLeave: () {
                Navigator.of(context).pop();
              },
            ),
          if (_inspectedCard != null)
            _CardInspectOverlay(
              card: _inspectedCard!,
              theme: theme,
              aids: aids,
              jokerAidsEnabled: jokerAidsEnabled,
              onClose: () => setState(() => _inspectedCard = null),
            ),
          if (_roundResultPresentation != null)
            _RoundResultOverlay(
              presentation: _roundResultPresentation!,
              onContinueNow: _roundResultPresentation!.nextSnapshot == null
                  ? null
                  : () => _advanceToNextRound(
                      _roundResultPresentation!.nextSnapshot!,
                    ),
              onReturnToMenu:
                  _roundResultPresentation!.progress.matchWinner == null
                  ? null
                  : () => Navigator.of(context).pop(),
            ),
        ],
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

  String? _findDiscardActionId(List<String> legal, String? selectedId) {
    if (selectedId == null) return null;
    for (final id in legal) {
      if (ClassicHareegActionIds.discardCardId(id) == selectedId) {
        return id;
      }
    }
    return null;
  }

  bool _canDropCardToDiscard(HareegCard card) {
    if (_controller.currentSeat != PlayerSeat.south || _isCpuRunning) {
      return false;
    }
    final legal = _controller.controlActionIdsFor(PlayerSeat.south);
    if (_controller.pendingDiscard?.id == card.id) {
      return legal.contains(ClassicHareegActionIds.returnPendingDiscard);
    }
    return _findDiscardActionId(legal, card.id) != null;
  }

  Future<void> _dropCardToDiscard(HareegCard card) async {
    if (_isCpuRunning) return;
    final legal = _controller.controlActionIdsFor(PlayerSeat.south);
    if (_controller.pendingDiscard?.id == card.id &&
        legal.contains(ClassicHareegActionIds.returnPendingDiscard)) {
      await _runHumanAction(ClassicHareegActionIds.returnPendingDiscard);
      return;
    }

    final discardActionId = _findDiscardActionId(legal, card.id);
    if (discardActionId != null) {
      await _runHumanAction(discardActionId);
      return;
    }

    _showInvalidFeedback('That card cannot be discarded now.');
  }

  bool _canDropCardToTable(HareegCard card) {
    if (_controller.currentSeat != PlayerSeat.south || _isCpuRunning) {
      return false;
    }
    return _tableActionIdForCardIds(_dropCardIds(card)) != null;
  }

  /// Stricter variant used by the south meld lane's wide drop target. Only
  /// returns true when dropping the dragged card(s) would place a *new*
  /// meld — covers and joker replacements have their own per-meld targets
  /// so the wide lane does not light up for them.
  bool _canPlaceNewMeldOnTable(HareegCard card) {
    if (_controller.currentSeat != PlayerSeat.south || _isCpuRunning) {
      return false;
    }
    final ids = _dropCardIds(card);
    if (ids.isEmpty) return false;
    final pending = _controller.pendingDiscard;
    if (pending != null && !ids.contains(pending.id)) return false;
    return _legalMeldActionForCardIds(ids) != null;
  }

  bool _canDropCardToMeld(HareegCard card, PlayerSeat owner, int meldIndex) {
    if (_controller.currentSeat != PlayerSeat.south || _isCpuRunning) {
      return false;
    }
    for (final cardIds in _dropCardIdCandidatesForMeld(card)) {
      if (_tableActionIdForMeldTarget(cardIds, owner, meldIndex) != null) {
        return true;
      }
    }
    return false;
  }

  Future<void> _dropCardToTable(HareegCard card) async {
    if (_isCpuRunning) return;
    final actionId = _tableActionIdForCardIds(_dropCardIds(card));
    if (actionId == null) {
      _showInvalidFeedback('Drop a valid meld, cover, or joker replacement.');
      return;
    }
    await _runHumanAction(actionId);
  }

  Future<void> _dropCardToMeld(
    HareegCard card,
    PlayerSeat owner,
    int meldIndex,
  ) async {
    if (_isCpuRunning) return;
    for (final cardIds in _dropCardIdCandidatesForMeld(card)) {
      final actionId = _tableActionIdForMeldTarget(cardIds, owner, meldIndex);
      if (actionId != null) {
        await _runHumanAction(actionId);
        return;
      }
    }
    _showInvalidFeedback('That card does not fit this meld.');
  }

  List<String> _dropCardIds(HareegCard card) {
    if (_selectedCardIds.contains(card.id) && _selectedCardIds.length > 1) {
      return _selectedCardIds.toList(growable: false);
    }
    return [card.id];
  }

  String? _tableActionIdForCardIds(List<String> cardIds) {
    if (cardIds.isEmpty) return null;
    final pending = _controller.pendingDiscard;
    if (pending != null && !cardIds.contains(pending.id)) {
      return null;
    }

    final coverActionId = _controller.coverActionIdFor(
      PlayerSeat.south,
      cardIds,
    );
    if (coverActionId != null) return coverActionId;

    final replaceActionId = _controller.jokerReplacementActionIdFor(
      PlayerSeat.south,
      cardIds,
    );
    if (replaceActionId != null) return replaceActionId;

    return _legalMeldActionForCardIds(cardIds);
  }

  String? _tableActionIdForMeldTarget(
    List<String> cardIds,
    PlayerSeat owner,
    int meldIndex,
  ) {
    if (cardIds.isEmpty) return null;
    final pending = _controller.pendingDiscard;
    if (pending != null && !cardIds.contains(pending.id)) {
      return null;
    }

    final coverActionId = _controller.coverActionIdForMeldTarget(
      seat: PlayerSeat.south,
      cardIds: cardIds,
      targetSeat: owner,
      meldIndex: meldIndex,
    );
    if (coverActionId != null) {
      return coverActionId;
    }

    final replacementActionId = _controller
        .jokerReplacementActionIdForMeldTarget(
          seat: PlayerSeat.south,
          cardIds: cardIds,
          targetSeat: owner,
          meldIndex: meldIndex,
        );
    if (replacementActionId != null) return replacementActionId;

    return null;
  }

  String? _legalMeldActionForCardIds(Iterable<String> cardIds) {
    return _meldActionForCardIds(cardIds.toList(growable: false));
  }

  List<String>? _meldActionCardIds(String actionId) {
    final plain = ClassicHareegActionIds.meldCardIds(actionId);
    if (plain != null) return plain;
    final joker = ClassicHareegActionIds.jokerMeldChoice(actionId);
    return joker?.cardIds;
  }

  Iterable<List<String>> _dropCardIdCandidatesForMeld(HareegCard card) sync* {
    if (_selectedCardIds.contains(card.id) && _selectedCardIds.length > 1) {
      yield _selectedCardIds.toList(growable: false);
    }
    yield [card.id];
  }

  /// Returns a play action for the exact selected single meld. This bypasses
  /// controller-wide opening-combination enumeration so the picker never pulls
  /// unselected cards from the rest of the hand.
  String? _selectedMeldAction(MeldValidationResult? validation) {
    if (_selectedCardIds.length < 3 || validation?.isValid != true) {
      return null;
    }
    return _meldActionForCardIds(_selectedCardIds.toList(growable: false));
  }

  String? _meldActionForCardIds(List<String> cardIds) {
    if (cardIds.length < 3 || cardIds.toSet().length != cardIds.length) {
      return null;
    }
    final pending = _controller.pendingDiscard;
    if (pending != null && !cardIds.contains(pending.id)) {
      return null;
    }
    final handCount = _controller.handFor(PlayerSeat.south).length;
    if (handCount - cardIds.length == 0) {
      return null;
    }

    final validation = _controller.singleMeldValidationFor(
      PlayerSeat.south,
      cardIds,
    );
    if (!validation.isValid) {
      return null;
    }

    final jokerChoices = _controller.jokerRepresentationOptionsFor(
      PlayerSeat.south,
      cardIds,
    );
    if (jokerChoices.isNotEmpty) {
      return null;
    }

    return ClassicHareegActionIds.playMeldActionId(cardIds);
  }

  List<TableMeldSuggestion> _meldSuggestions(List<HareegCard> handCards) {
    // The GitHub PRD is explicit: the picker reflects selected cards only.
    // Opening bundles from the rest of the hand are deliberately excluded.
    if (_selectedCardIds.length < 3) return const [];
    final seen = <String>{};
    final suggestions = <TableMeldSuggestion>[];
    final selectedCards = [
      for (final card in handCards)
        if (_selectedCardIds.contains(card.id)) card,
    ];

    for (final group in _selectedMeldCandidateGroups(selectedCards)) {
      final ids = group.map((card) => card.id).toList(growable: false);
      final actionId = _meldActionForCardIds(ids);
      if (actionId == null) continue;
      final key = (List<String>.of(ids)..sort()).join('|');
      if (!seen.add(key)) continue;
      suggestions.add(TableMeldSuggestion(actionId: actionId, cards: group));
      if (suggestions.length == 5) {
        break;
      }
    }
    return suggestions;
  }

  Iterable<List<HareegCard>> _selectedMeldCandidateGroups(
    List<HareegCard> selectedCards,
  ) sync* {
    if (selectedCards.length < 3) {
      return;
    }
    if (selectedCards.length > 10) {
      yield selectedCards;
      return;
    }
    for (var size = selectedCards.length; size >= 3; size -= 1) {
      yield* _cardCombinations(selectedCards, size);
    }
  }

  Iterable<List<HareegCard>> _cardCombinations(
    List<HareegCard> cards,
    int size,
  ) sync* {
    if (size == 0) {
      yield const <HareegCard>[];
      return;
    }
    if (cards.length < size) {
      return;
    }
    for (var index = 0; index <= cards.length - size; index += 1) {
      final head = cards[index];
      final remaining = cards.sublist(index + 1);
      for (final tail in _cardCombinations(remaining, size - 1)) {
        yield [head, ...tail];
      }
    }
  }

  void _toggleSelectedCard(HareegCard card) {
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
    setState(() {
      _replaceHumanFeedback(message, isError: true);
    });
  }

  /// Plays a stock→seat / discard→seat / seat→discard card-flight for a CPU
  /// action so the human can see which seat acted and where the card went.
  Future<void> _playFlightForCpuAction(PlayerSeat seat, String actionId) async {
    final flight = _flightForCpuAction(seat, actionId);
    if (flight == null) return;
    setState(() => _cardFlight = flight);
    await Future<void>.delayed(_scaledDelay(const Duration(milliseconds: 200)));
    if (mounted && identical(_cardFlight, flight)) {
      setState(() => _cardFlight = null);
    }
  }

  _CardFlight? _flightForCpuAction(PlayerSeat seat, String actionId) {
    final seatAnchor = _alignmentForSeat(seat);
    if (actionId == ClassicHareegActionIds.drawStock) {
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
    if (actionId == ClassicHareegActionIds.takeDiscard) {
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
    if (actionId == ClassicHareegActionIds.returnPendingDiscard) {
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
    final discardCardId = ClassicHareegActionIds.discardCardId(actionId);
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

  Future<void> _playFlightForAction(String actionId) async {
    final flight = _flightForAction(actionId);
    if (flight == null) return;
    setState(() => _cardFlight = flight);
    await Future<void>.delayed(_scaledDelay(const Duration(milliseconds: 230)));
    if (mounted && identical(_cardFlight, flight)) {
      setState(() => _cardFlight = null);
    }
  }

  _CardFlight? _flightForAction(String actionId) {
    if (actionId == ClassicHareegActionIds.drawStock) {
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

    if (actionId == ClassicHareegActionIds.takeDiscard) {
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

    if (actionId == ClassicHareegActionIds.returnPendingDiscard) {
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

    final discardCardId = ClassicHareegActionIds.discardCardId(actionId);
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

    final cover = ClassicHareegActionIds.coverActionTarget(actionId);
    if (cover != null && cover.cardIds.isNotEmpty) {
      final card = _cardInSouthHand(cover.cardIds.first);
      if (card == null) return null;
      return _CardFlight(
        serial: ++_flightSerial,
        card: card,
        begin: _FlightAnchor.hand.alignment,
        end: _alignmentForSeat(cover.targetSeat),
        beginHandSlot: _southHandCardSlot(card.id),
      );
    }

    final replacement = ClassicHareegActionIds.jokerReplacementTarget(actionId);
    if (replacement != null) {
      final card = _cardInSouthHand(replacement.cardId);
      if (card == null) return null;
      return _CardFlight(
        serial: ++_flightSerial,
        card: card,
        begin: _FlightAnchor.hand.alignment,
        end: _alignmentForSeat(replacement.targetSeat),
        beginHandSlot: _southHandCardSlot(card.id),
      );
    }

    final meldIds = _meldActionCardIds(actionId);
    if (meldIds != null && meldIds.isNotEmpty) {
      final card = _cardInSouthHand(meldIds.first);
      if (card == null) return null;
      return _CardFlight(
        serial: ++_flightSerial,
        card: card,
        begin: _FlightAnchor.hand.alignment,
        end: _FlightAnchor.southMeld.alignment,
        beginHandSlot: _southHandCardSlot(card.id),
      );
    }

    return null;
  }

  _SeatHandFlightSlot _southHandAppendSlot() {
    final count = _controller.handFor(PlayerSeat.south).length + 1;
    return _SeatHandFlightSlot(
      seat: PlayerSeat.south,
      index: count - 1,
      count: count,
    );
  }

  _SeatHandFlightSlot? _southHandCardSlot(String cardId) {
    final cards = _orderedSouthHand();
    final index = cards.indexWhere((card) => card.id == cardId);
    if (index == -1) {
      return null;
    }
    return _SeatHandFlightSlot(
      seat: PlayerSeat.south,
      index: index,
      count: cards.length,
    );
  }

  _SeatHandFlightSlot _appendHandSlotForSeat(PlayerSeat seat) {
    if (seat == PlayerSeat.south) {
      return _southHandAppendSlot();
    }
    final count = _controller.cardCountFor(seat) + 1;
    return _SeatHandFlightSlot(seat: seat, index: count - 1, count: count);
  }

  _SeatHandFlightSlot? _lastHandSlotForSeat(PlayerSeat seat) {
    if (seat == PlayerSeat.south) {
      final cards = _orderedSouthHand();
      if (cards.isEmpty) return null;
      return _SeatHandFlightSlot(
        seat: PlayerSeat.south,
        index: cards.length - 1,
        count: cards.length,
      );
    }
    final count = _controller.cardCountFor(seat);
    if (count <= 0) return null;
    return _SeatHandFlightSlot(seat: seat, index: count - 1, count: count);
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

  Future<void> _runHumanAction(String actionId) async {
    if (_isCpuRunning) return;
    final totalWatch = Stopwatch()..start();
    _debugTableLog(
      'human action start action=$actionId current=${_controller.currentSeat.name} '
      'phase=${_controller.turnPhase} pending=${_controller.pendingDiscard?.label}',
    );
    await _playFlightForAction(actionId);
    if (!mounted) return;
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
      setState(() {
        _replaceHumanFeedback(result.message, isError: true);
      });
      return;
    }
    unawaited(_haptics.fire(_hapticForAction(actionId)));
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
    if (actionId == ClassicHareegActionIds.drawStock) {
      return TableHapticEvent.drawCard;
    }
    if (actionId == ClassicHareegActionIds.takeDiscard) {
      return TableHapticEvent.buttonTap;
    }
    if (actionId == ClassicHareegActionIds.returnPendingDiscard) {
      return TableHapticEvent.pendingReturn;
    }
    if (actionId == ClassicHareegActionIds.claimFifty) {
      return TableHapticEvent.fiftyClaim;
    }
    return TableHapticEvent.buttonTap;
  }

  bool _clearsSelection(String actionId) {
    return ClassicHareegActionIds.discardCardId(actionId) != null ||
        actionId.startsWith(ClassicHareegActionIds.playMeldPrefix) ||
        actionId.startsWith(ClassicHareegActionIds.playMeldWithJokerPrefix) ||
        actionId.startsWith(ClassicHareegActionIds.placeCoverPrefix) ||
        actionId.startsWith(ClassicHareegActionIds.replaceJokerPrefix) ||
        actionId == ClassicHareegActionIds.returnOpeningMelds ||
        actionId == ClassicHareegActionIds.returnPendingDiscard;
  }

  Future<bool> _runCpuTurns() async {
    if (_isCpuRunning ||
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
    var safety = 0;
    var didPersistOrNavigate = false;
    try {
      while (mounted &&
          !_controller.isRoundOver &&
          _controller.currentSeat != PlayerSeat.south &&
          safety < _cpuActionLimit) {
        final seat = _controller.currentSeat;
        _debugTableLog(
          'cpu step ${safety + 1} start seat=${seat.name} '
          'phase=${_controller.turnPhase} pending=${_controller.pendingDiscard?.label} '
          'stock=${_controller.stockCount} discard=${_controller.discardPile.length}',
        );
        await Future<void>.delayed(_scaledDelay(TableMotion.cpuReadPause));
        if (!mounted) return didPersistOrNavigate;
        final legalWatch = Stopwatch()..start();
        final legal = _controller.cpuActionIdsFor(seat);
        legalWatch.stop();
        _debugTableLog(
          'cpu step ${safety + 1} legal seat=${seat.name} '
          'elapsed=${legalWatch.elapsedMilliseconds}ms count=${legal.length} '
          'actions=${_debugActionSummary(legal)}',
        );
        if (legal.isEmpty) {
          _debugTableLog('cpu step ${safety + 1} break no legal actions');
          break;
        }
        final chooseWatch = Stopwatch()..start();
        final intent = widget.cpuStrategy.chooseMove(
          CpuTurnSnapshot(
            seat: seat,
            legalActionIds: legal,
            difficulty: _controller.setup.cpuDifficulty,
          ),
        );
        chooseWatch.stop();
        _debugTableLog(
          'cpu step ${safety + 1} chose action=${intent.actionId} '
          'elapsed=${chooseWatch.elapsedMilliseconds}ms',
        );
        final flightWatch = Stopwatch()..start();
        await _playFlightForCpuAction(seat, intent.actionId);
        flightWatch.stop();
        _debugTableLog(
          'cpu step ${safety + 1} flight action=${intent.actionId} '
          'elapsed=${flightWatch.elapsedMilliseconds}ms',
        );
        if (!mounted) return didPersistOrNavigate;
        final applyWatch = Stopwatch()..start();
        final result = _controller.applyAction(intent.actionId);
        applyWatch.stop();
        _debugTableLog(
          'cpu step ${safety + 1} applied action=${intent.actionId} '
          'success=${result.isSuccess} elapsed=${applyWatch.elapsedMilliseconds}ms '
          'current=${_controller.currentSeat.name} phase=${_controller.turnPhase}',
        );
        if (!result.isSuccess) {
          throw StateError(
            'CPU strategy returned illegal action ${intent.actionId}: '
            '${result.message}',
          );
        }
        didPersistOrNavigate = true;
        _ensureFiftyTicker();
        final persistWatch = Stopwatch()..start();
        await _persistAndMaybeFinish();
        persistWatch.stop();
        _debugTableLog(
          'cpu step ${safety + 1} persist returned '
          'elapsed=${persistWatch.elapsedMilliseconds}ms '
          'roundOver=${_controller.isRoundOver}',
        );
        if (!mounted) return didPersistOrNavigate;
        if (_controller.isRoundOver || _roundResultPresentation != null) {
          return didPersistOrNavigate;
        }
        await Future<void>.delayed(_scaledDelay(TableMotion.cpuMove));
        safety += 1;
      }
      if (!mounted) return didPersistOrNavigate;
      final hitCpuSafetyLimit =
          safety >= _cpuActionLimit &&
          !_controller.isRoundOver &&
          _controller.currentSeat != PlayerSeat.south;
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
        'steps=$safety hitSafety=$hitCpuSafetyLimit '
        'didPersist=$didPersistOrNavigate current=${_controller.currentSeat.name} '
        'phase=${_controller.turnPhase} roundOver=${_controller.isRoundOver}',
      );
      return didPersistOrNavigate;
    } catch (error, stackTrace) {
      totalWatch.stop();
      _debugTableLog(
        'cpu loop failed elapsed=${totalWatch.elapsedMilliseconds}ms '
        'steps=$safety current=${_controller.currentSeat.name} '
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
      return didPersistOrNavigate;
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
    setState(() {
      _controller = ClassicHareegGameController.fromSnapshot(snapshot);
      _resetDisplayOrder();
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final didPersistOrNavigate = await _runCpuTurns();
      if (!didPersistOrNavigate && mounted) {
        await _persistAndMaybeFinish();
      }
    });
  }
}

class _RoundTableButton extends StatelessWidget {
  const _RoundTableButton({
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
    return Tooltip(
      message: tooltip,
      child: Material(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.88),
        shape: const CircleBorder(),
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        child: InkWell(
          customBorder: const CircleBorder(),
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
  });

  final _RoundResultPresentation presentation;
  final VoidCallback? onContinueNow;
  final VoidCallback? onReturnToMenu;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final seats = PlayerSeat.values.toList();
    final compact = MediaQuery.sizeOf(context).height < 390;
    final winner = presentation.progress.matchWinner;
    return Positioned.fill(
      key: const ValueKey('round-result-overlay'),
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.50),
        child: SafeArea(
          child: Center(
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
                    color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: LoungeTokens.goldAccent.withValues(alpha: 0.34),
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
      child: Material(
        color: Colors.black.withValues(alpha: 0.48),
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
                        textAlign: compact ? TextAlign.center : TextAlign.start,
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

                return Container(
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
                    color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: LoungeTokens.goldAccent.withValues(alpha: 0.36),
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
                );
              },
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
  hand(Alignment(0, 0.82)),
  southMeld(Alignment(0, 0.48));

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
  });

  final int serial;
  final HareegCard card;
  final Alignment begin;
  final Alignment end;
  final bool faceDown;
  final _SeatHandFlightSlot? beginHandSlot;
  final _SeatHandFlightSlot? endHandSlot;
}

class _SeatHandFlightSlot {
  const _SeatHandFlightSlot({
    required this.seat,
    required this.index,
    required this.count,
  });

  final PlayerSeat seat;
  final int index;
  final int count;
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
          );
          final end = _resolveFlightPoint(
            flight.end,
            size,
            cardSize,
            flight.endHandSlot,
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
    _SeatHandFlightSlot? handSlot,
  ) {
    if (handSlot != null) {
      return _resolveSeatHandSlot(handSlot, size, cardSize);
    }
    return Offset(
      ((alignment.x + 1) / 2 * size.width) - cardSize.width / 2,
      ((alignment.y + 1) / 2 * size.height) - cardSize.height / 2,
    );
  }

  Offset _resolveSeatHandSlot(
    _SeatHandFlightSlot slot,
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
    _SeatHandFlightSlot slot,
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
    final handLeft = compact ? 70.0 : 96.0;
    final handBottom = compact ? 0.0 : 2.0;
    final handWidth = math.max(0.0, size.width - handLeft - handRightInset);
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
        handLeft + start + index * fittedGap + handCardSize.width / 2;
    final centerY = handTop + bottomHandHeight - 2 - handCardSize.height / 2;
    return _centeredFlightOffset(centerX, centerY, flightCardSize);
  }

  Offset _resolveNorthHandSlot(
    _SeatHandFlightSlot slot,
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
    _SeatHandFlightSlot slot,
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
