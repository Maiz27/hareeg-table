import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/app_metadata.dart';
import '../../../../app/app_routes.dart';
import '../../../../app/app_orientation.dart';
import '../../../../cpu/classic_hareeg/coaching/classic_hareeg_coaching_advisor.dart';
import '../../../../cpu/classic_hareeg/coaching/coaching_insight.dart';
import '../../../../cpu/classic_hareeg/cpu_strategy.dart';
import '../../../../data/persistence/match_repository.dart';
import '../../../../data/persistence/preferences_repository.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_round.dart';
import '../../../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../domain/classic_hareeg/rules/match_progression_rules.dart';
import '../../../../domain/classic_hareeg/rules/opening_rules.dart'
    show PlacedMeld;
import '../../../../domain/classic_hareeg/reporting/classic_hareeg_match_report.dart';
import '../../../../domain/classic_hareeg/reporting/match_recorder.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_state.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/cards/card_view.dart';
import '../../../core/audio/table_audio.dart';
import '../../../core/feedback/lounge_toast.dart';
import '../../../core/haptics/table_haptics.dart';
import '../../../core/motion/motion_speed.dart';
import '../../../core/scopes/app_scopes.dart';
import '../../../core/strictness/strictness_ui_profile.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../animations/deal_choreography.dart';
import '../coach/coach_highlighting.dart';
import '../coach/coach_hint.dart';
import '../coach/coach_insight_flow.dart';
import '../cue/table_cue_choreographer.dart';
import '../meld_flight_controller.dart';
import '../table_action_presentation_planner.dart';
import '../table_card_flight_planner.dart';
import '../table_cpu_turn_presenter.dart';
import '../table_flight_anchors.dart';
import '../table_flight_geometry.dart';
import '../table_hand_interaction_state.dart';
import '../table_interaction_planner.dart';
import '../table_persistence_planner.dart';
import '../practice_table_run.dart';
import '../table_session_flow_planner.dart';
import '../../learning/practice/practice_lesson_script.dart';
import '../../learning/practice/practice_session.dart';
import '../../learning/widgets/practice_completion_overlay.dart';
import '../../learning/widgets/practice_missed_overlay.dart';
import '../../learning/widgets/practice_step_banner.dart';
import '../widgets/coach_overlay.dart';
import '../widgets/match_over_overlay.dart';
import '../widgets/meld_flight_overlay.dart';
import '../widgets/pause_overlay.dart';
import '../widgets/physical_table_playfield.dart';
import '../widgets/score_overlay.dart';
import '../widgets/table_background.dart';
import '../../match_reports/match_report_export_flow.dart';
import '../../match_reports/match_report_exporter.dart';

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
    this.practiceSession,
    this.onPracticeFinished,
    this.nextPracticeScript,
    this.reportExporter = const MatchReportExporter(),
  });

  /// Setup used to deal the round.
  final ClassicHareegSetup setup;

  /// Active match persistence.
  final MatchRepository matchRepository;

  /// Player preferences (motion, haptics, coaching tips, theme).
  final GamePreferences preferences;

  /// Called by the pause overlay when a preference is toggled mid-match.
  final ValueChanged<GamePreferences> onPreferencesChanged;

  /// Saved snapshot to resume (else deal a fresh round).
  final ClassicHareegMatchSnapshot? initialSnapshot;

  /// CPU strategy used for non-human seats.
  final CpuStrategy cpuStrategy;

  /// Report exporter used by the pause overlay diagnostic action.
  final MatchReportExporter reportExporter;

  /// Non-null when this table hosts a guided practice lesson.
  ///
  /// Practice mode adopts the session's deterministic controller, gates every
  /// affordance and applied action through the lesson step, suppresses CPU
  /// autonomy and match persistence, and swaps the match chrome for the step
  /// banner + completion overlay. Real legality and gestures are unchanged —
  /// the lesson plays on the exact surface a real match uses.
  final PracticeSession? practiceSession;

  /// Called when a practice lesson's final step is demonstrated, so the app
  /// shell can persist checklist completion. The table never touches learning
  /// progress itself; [String] is the finished lesson's id because the
  /// completion overlay can chain straight into the pack's next lesson.
  final Future<void> Function(String lessonId)? onPracticeFinished;

  /// Resolves the lesson that continues a finished lesson's practice pack,
  /// or null at a pack boundary. Owned by the shell so the table stays
  /// ignorant of the script registry; a non-null result powers the
  /// completion overlay's "next lesson" button.
  final PracticeLessonScript? Function(String lessonId)? nextPracticeScript;

  @override
  State<GameTableScreen> createState() => _GameTableScreenState();
}

class _GameTableScreenState extends State<GameTableScreen>
    with TickerProviderStateMixin {
  static const _cpuActionLimit = 64;

  /// Pause before a lesson's scripted intro starts, so the player reads the
  /// fresh board before the other seat moves.
  static const _practiceIntroLeadIn = Duration(milliseconds: 1400);
  static const _successFeedbackDuration = Duration(milliseconds: 1400);
  static const _errorFeedbackDuration = Duration(milliseconds: 2400);
  static const _roundResultDisplayDuration = Duration(milliseconds: 2400);
  static const _matchEndOverlayDwell = Duration(milliseconds: 1400);
  static const _jokerDeclarationFeedbackDuration = Duration(seconds: 3);
  static const _fastJokerDeclarationFeedbackDuration = Duration(
    milliseconds: 1500,
  );

  late ClassicHareegGameController _controller;

  /// Records the diagnostic event log + replayable action transcript for the
  /// active match so they can be embedded in an exported report. Null for
  /// practice runs, which never export reports. The same recorder is handed to
  /// each round's controller so it spans the whole match.
  MatchRecorder? _recorder;
  final _handInteraction = ClassicHareegHandInteractionState();
  bool _isCpuRunning = false;
  // Set while the Table-tier fast-forward button is ripping through the
  // remaining CPU turns without animations or audio. Locks the chrome
  // button against double-taps and is cleared in finally.
  bool _isFastForwardingRound = false;
  // Set while a human action's pre-apply flight/sound is in flight and the
  // controller hasn't applied the move yet. Used to lock the UI so a second
  // tap doesn't queue a parallel action against the same controller state.
  bool _isHumanActionPending = false;
  // Counts consecutive humanRemoved auto-restarts of the CPU loop after it hit
  // the per-run safety cap without the round ending. The engine now terminates
  // a stock-exhausted dead round as a draw, so a healthy run reaches round-over
  // and resets this. The bound is a backstop: if some future state still failed
  // to progress, an unbounded `scheduleMicrotask(_runCpuTurns)` would spin the
  // table forever (the original freeze). Reset on any round-over / new round.
  int _cpuAutoRestarts = 0;
  static const _maxCpuAutoRestarts = 12;
  bool _scoreOpen = false;
  bool _pauseOpen = false;
  Set<String>? _placedJokerSnapshot;
  // Single owner of every "schedule a cue, then rebuild" mechanism the
  // screen used to manage inline (feedback chip, revert flash, fifty
  // ticker, fifty pulse, round-advance, joker cue FIFO). The widget
  // listens to it once and rebuilds whenever any cue changes; the queue
  // / timer mechanics live in the choreographer so they're unit-testable
  // without spinning up Flutter.
  late final TableCueChoreographer _cues = TableCueChoreographer(
    jokerDwellFor: (_) => _scaledDelay(_activeJokerChipDuration),
    onJokerCueStart: (cue) =>
        _onJokerCueStart(cue as ({PlayerSeat seat, CardIdentity identity})),
    onJokerCueEnd: (cue) =>
        _onJokerCueEnd(cue as ({PlayerSeat seat, CardIdentity identity})),
    isMounted: () => mounted,
  );
  final List<_CardFlight> _activeFlights = [];
  late final MeldFlightController _meldFlight;
  DealChoreography? _dealChoreography;
  bool _pendingDealBuild = false;
  HareegCard? _inspectedCard;
  static const _revertFlashDuration = Duration(milliseconds: 1100);
  ClassicHareegRoundResultPresentation? _roundResultPresentation;
  // Non-null while the dedicated match-over overlay is shown. The match ends
  // in place on the landscape table (no route change, no rotation); the
  // rematch restarts the controller without leaving the screen.
  ClassicHareegRoundResultPresentation? _matchOverPresentation;
  final Map<PlayerSeat, int> _matchEliminatedRoundBySeat = {};
  int _flightSerial = 0;

  // Coaching-tier advisor memoization. Re-running the partition enumerator on
  // every cue/flight tick would be wasteful, so the insight list is cached
  // against a cheap signature of the human's situation and only recomputed
  // when that signature changes.
  String? _coachInsightCacheKey;
  List<CoachingInsight> _coachInsights = const [];

  // Cross-turn coach surfacing policy: stage banners show once per round each.
  // Match-lifetime state (keys embed the round number, so no reset is needed).
  final CoachInsightFlow _coachInsightFlow = CoachInsightFlow();

  // Synthetic turn marker for the insight flow (the controller has no turn
  // counter): bumped whenever the seat on turn changes. Plain fields mutated
  // during build — no setState, no listeners.
  PlayerSeat? _coachTurnSeat;
  int _coachTurnCounter = 0;

  // State-owned so replay / next-lesson swap sessions in place. A route swap
  // would build the replacement table (landscape) and then dispose this one,
  // whose dispose() restores portrait — flipping the live lesson upright.
  PracticeTableRun? _practiceRun;

  PracticeSession? get _practiceSession => _practiceRun?.session;

  bool get _isPractice => _practiceRun != null;

  bool get _practiceComplete => _practiceRun?.isComplete ?? false;

  bool get _practiceScoreReveal => _practiceRun?.isScoreReveal ?? false;

  /// Whether the active lesson run can no longer demonstrate its step (a
  /// Fifty window expired before the claim). Suppressed while the scripted
  /// intro still owns the turn — the step's predicate is meaningless before
  /// the board reaches the player. Drives the missed-lesson overlay.
  bool get _practiceDeadEnd {
    return _practiceRun?.isDeadEnd(scriptedIntroRunning: _isCpuRunning) ??
        false;
  }

  @override
  void initState() {
    super.initState();
    AppOrientation.useLandscape();
    _practiceRun = widget.practiceSession == null
        ? null
        : PracticeTableRun(widget.practiceSession!);
    final practice = _practiceRun;
    final snapshot = widget.initialSnapshot;
    // Practice never exports reports, so it skips the recorder entirely.
    final recorder = practice != null ? null : MatchRecorder();
    _recorder = recorder;
    _controller = practice != null
        ? practice.controller
        : snapshot != null
        ? ClassicHareegGameController.fromSnapshot(snapshot, recorder: recorder)
        : ClassicHareegGameController.fromRound(
            ClassicHareegRound.deal(setup: widget.setup),
            recorder: recorder,
          );
    if (recorder != null) {
      recorder.recordPersistence(
        type: snapshot != null ? 'resumed' : 'dealt',
        roundNumber: _controller.roundNumber,
        data: {'stage': snapshot != null ? 'restore' : 'fresh-deal'},
      );
    }
    _meldFlight = MeldFlightController(
      handLookup: _cardInHand,
      existingMeldCardCounts: (seat) => [
        for (final meld in _controller.tableMeldsFor(seat)) meld.cards.length,
      ],
      isMounted: () => mounted,
    )..addListener(_handleCueOrFlightChange);
    _cues.addListener(_handleCueOrFlightChange);
    _resetHandInteraction();
    if (snapshot == null && practice == null) {
      _pendingDealBuild = true;
    }
    _debugTableLog(
      'init snapshot=${snapshot != null} current=${_controller.currentSeat.name} '
      'phase=${_controller.turnPhase} stock=${_controller.stockCount} '
      'discard=${_controller.discardPile.length} '
      'counts=${_debugSeatCounts(_controller)}',
    );
    _ensureFiftyTicker();
    // Practice never runs the opening deal, autonomous CPU turns, or the
    // persistence the turn-flow planner orchestrates; the lesson waits on
    // the player after its scripted intro (if any) plays out. The intro
    // kicks off post-frame: its pacing reads MotionScope, an inherited
    // lookup that is not safe here.
    if (!_isPractice) {
      _scheduleTurnFlow();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_runPracticeIntro());
        }
      });
    }
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
    _cues.removeListener(_handleCueOrFlightChange);
    _cues.dispose();
    _dealChoreography?.dispose();
    _dealChoreography = null;
    _meldFlight.removeListener(_handleCueOrFlightChange);
    _meldFlight.dispose();
    AppOrientation.usePortrait();
    super.dispose();
  }

  /// Single rebuild signal for both the cue choreographer (feedback /
  /// revert flash / fifty ticker / fifty pulse / round-advance / joker
  /// cues) and the meld-flight controller. The screen no longer scatters
  /// per-cue setState wires across the state class.
  void _handleCueOrFlightChange() {
    if (!mounted) return;
    setState(() {});
  }

  void _returnToMainMenu() {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
  }

  Future<void> _exportActiveMatchReport() async {
    final choice = await showMatchReportConfirmation(
      context,
      highContrast: widget.preferences.highContrastCards,
    );
    if (!mounted || choice == null) {
      return;
    }
    final ClassicHareegMatchReport report;
    try {
      final generatedAt = DateTime.now().toUtc();
      report = ClassicHareegMatchReport.active(
        app: HareegAppMetadata.reportMetadata,
        platform: currentMatchReportPlatform(),
        generatedAt: generatedAt,
        snapshot: _controller.toSnapshot(savedAt: generatedAt),
        diagnostics: _recorder?.diagnostics,
        transcript: _recorder?.transcript,
      );
    } on Object catch (error, stackTrace) {
      debugPrint('[hareeg:reports] Failed to generate match report: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        showLoungeToast(
          context,
          message: context.strings.matchReportGenerationFailed,
          icon: Icons.error_outline,
          isError: true,
        );
      }
      return;
    }
    switch (choice) {
      case MatchReportExportChoice.share:
        await _shareOrOfferCopy(report);
      case MatchReportExportChoice.copy:
        await _copyMatchReport(report);
    }
  }

  Future<void> _shareOrOfferCopy(ClassicHareegMatchReport report) async {
    final strings = context.strings;
    final attempt = await widget.reportExporter.share(report);
    if (!mounted) {
      return;
    }
    if (attempt.shared) {
      showLoungeToast(
        context,
        message: strings.matchReportShareReady,
        actionLabel: strings.copyReport,
        onActionPressed: () {
          unawaited(_copyMatchReport(report));
        },
      );
      return;
    }
    showLoungeToast(
      context,
      message: strings.matchReportCopyFallback,
      icon: Icons.error_outline,
      isError: true,
      actionLabel: strings.copyReport,
      onActionPressed: () {
        unawaited(_copyMatchReport(report));
      },
    );
  }

  Future<void> _copyMatchReport(ClassicHareegMatchReport report) async {
    final strings = context.strings;
    try {
      await widget.reportExporter.copy(report);
      if (!mounted) {
        return;
      }
      showLoungeToast(context, message: strings.matchReportCopied);
    } on Object {
      if (!mounted) {
        return;
      }
      showLoungeToast(
        context,
        message: strings.matchReportCopyFailed,
        icon: Icons.error_outline,
        isError: true,
      );
    }
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
    if (fiftyVisible && !_cues.isFiftyTickerActive) {
      _cues.startFiftyTicker(
        period: const Duration(milliseconds: 500),
        onTick: () {
          if (_controller.fiftySecondsRemaining == null) {
            _cues.stopFiftyTicker();
          }
        },
      );
    } else if (!fiftyVisible && _cues.isFiftyTickerActive) {
      _cues.stopFiftyTicker();
    }
  }

  void _scheduleTurnFlow() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final afterFramePlan = ClassicHareegTableSessionFlowPlanner.afterFrame(
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
          ClassicHareegTableSessionFlowPlanner.afterOpeningDeal(
            isMounted: mounted,
            isCpuRunning: _isCpuRunning,
            isOpeningDealRunning: _isOpeningDealRunning,
            isRoundOver: _controller.isRoundOver,
            isHumanTurn: _controller.currentSeat == PlayerSeat.south,
          );
      if (afterOpeningDealPlan.action ==
          ClassicHareegTableTurnFlowAction.runCpuTurns) {
        final didPersistOrNavigate = await _runCpuTurns();
        final afterCpuPlan = ClassicHareegTableSessionFlowPlanner.afterCpuTurns(
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

  bool get _canAcceptHumanInput {
    return ClassicHareegTableSessionFlowPlanner.canAcceptHumanInput(
      isCpuRunning: _isCpuRunning,
      isOpeningDealRunning: _isOpeningDealRunning,
      isHumanActionPending: _isHumanActionPending,
    );
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
        _controller.currentSeat == humanSeat && _canAcceptHumanInput;
    final actionGate = _tableActionGate(isHumanTurn: isHumanTurn);
    final baseControlActions = isHumanTurn
        ? _controller.controlActionIdsFor(humanSeat)
        : const <String>[];
    final controlActions = [
      for (final id in baseControlActions)
        if (actionGate.allows(id)) id,
    ];
    final pending = _controller.pendingDiscard;
    final theme = CardThemeScope.of(context);
    final strictness = _controller.setup.tableStrictness;
    final jokerDisplay = strictness.jokerDisplay;
    final southHand = _southHandInteraction();
    final southCards = southHand.orderedCards;
    final openingDealFrame = _openingDealFrame(southCards);
    final southIsRemoved = _controller.removedSeats.contains(PlayerSeat.south);
    final visibleSouthCards =
        openingDealFrame?.southCards ??
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
    final tableInteraction = _tableInteraction(
      southHand,
      actionGate: actionGate,
    );
    final meldSuggestions = _meldSuggestions(tableInteraction);
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

    // Coaching tier: surface one prioritized hint when the player is on turn,
    // the toggle is on, and nothing is mid-animation or covering the table.
    // Practice replaces the advisor coach with the step banner.
    //
    // Two gates with different semantics: [coachComputes] folds the PERSISTENT
    // conditions (tier, toggle, practice, turn ownership) — when any is false
    // the advisor (a full Expert plan + partition enumeration) must not run at
    // all; standard/strict/table tables and CPU turns pay nothing. The
    // remaining TRANSIENT conditions (overlays, in-flight motion) only hide
    // the *display* while still computing, so the cached insights track every
    // controller-state change and never go stale across an animation (the
    // playtest "discard the card you just melded" bug).
    final coachComputes =
        !_isPractice &&
        strictness.showsProactiveHints &&
        widget.preferences.coachingTipsEnabled &&
        isHumanTurn;
    final coachActive =
        coachComputes &&
        !_pauseOpen &&
        !_scoreOpen &&
        _inspectedCard == null &&
        _roundResultPresentation == null &&
        _dealChoreography == null &&
        _activeFlights.isEmpty &&
        _meldFlight.activeFlights.isEmpty &&
        // While a selection is producing meld suggestions, that rack is the
        // active guidance; stepping aside avoids two stacked bottom callouts.
        meldSuggestions.isEmpty;
    final coachHints = coachComputes
        ? _buildCoachHints(strings, humanSeat, gate: coachActive)
        : null;
    final coachHint = coachHints?.primary;
    final coachHighlighting = _isPractice
        ? _practiceStepHighlighting(isHumanTurn: isHumanTurn)
        : CoachHighlighting.fromHint(coachHint);
    final practiceBanner = _practiceRun?.bannerState(
      blockedByOverlay: _pauseOpen || _inspectedCard != null,
      scriptedIntroRunning: _isCpuRunning,
    );
    final nextPracticeScript = _practiceRun?.nextScript(
      widget.nextPracticeScript,
    );

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
              canPlayCardOnMeld: tableInteraction.canDropCardToMeldTarget,
              canRetractMeld: (owner, meldIndex) =>
                  controlActions.contains(
                    ClassicHareegActionIds.returnOpeningMelds,
                  ) &&
                  _controller.canReturnTablePlayFromMeld(owner, meldIndex),
              onDiscardCard: (card) => unawaited(_dropCardToDiscard(card)),
              onPlayCardOnTable: (card) => unawaited(_dropCardToTable(card)),
              onPlayCardOnMeld: (card, target) =>
                  unawaited(_dropCardToMeld(card, target)),
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
              onReturnDiscard: () => unawaited(_returnPendingDiscard()),
              onClaimFifty: () => unawaited(_claimFifty()),
              onReturnOpeningMelds: () => unawaited(
                _runHumanAction(ClassicHareegActionIds.returnOpeningMelds),
              ),
              fiftySecondsRemaining: _controller.fiftySecondsRemaining,
              fiftyTotalSeconds: _controller.setup.fiftyTimerSeconds,
              fiftyPulse: _cues.fiftyPulse,
              meldRequirement: _controller.openingState.currentRequirement,
              meldSelectionValue: meldCtaValue,
              meldSelectionValid: canPlayMeld,
              meldSelectionHasOpened: hasOpened,
              onPlaySelectedMeld: primaryMeldAction == null
                  ? null
                  : () => unawaited(_playSelectedMeld(primaryMeldAction)),
              meldSuggestions: meldSuggestions,
              showMeldSuggestions: true,
              onMeldSuggestion: (actionId) {
                unawaited(_runHumanAction(actionId));
              },
              isHumanTurn: isHumanTurn,
              isCpuRunning: _isCpuRunning,
              currentSeat: _controller.currentSeat,
              activeSeats: _controller.roundActiveSeats.toSet(),
              southFlashCardId: _cues.revertFlashCardId,
              coachHighlighting: coachHighlighting,
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
                // Side safe-insets are deliberately ignored: in landscape the
                // OS pads an entire short edge for a punch-hole that actually
                // sits vertically centered (and for system bars hidden by
                // immersive mode), which pushed the corner buttons visibly
                // off the edges while the stock pile and open-need pill sat
                // flush. The top corners are clear on side-cutout devices, so
                // the chrome matches the rest of the table: cosmetic inset
                // only.
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Practice swaps the score shortcut for an exit back to
                    // the hub; lesson boards have no match score to inspect.
                    Positioned(
                      top: safe.top + edgeInset,
                      left: edgeInset,
                      child: _isPractice
                          ? _TableChromeButton(
                              key: const ValueKey('practice-exit'),
                              tooltip: strings.practiceBackToList,
                              icon: Icons.close_rounded,
                              diameter: buttonSize,
                              iconSize: iconSize,
                              onPressed: () => Navigator.of(context).pop(),
                            )
                          : _TableChromeButton(
                              tooltip: strings.scores,
                              icon: Icons.bar_chart_rounded,
                              diameter: buttonSize,
                              iconSize: iconSize,
                              onPressed: () =>
                                  setState(() => _scoreOpen = true),
                            ),
                    ),
                    Positioned(
                      top: safe.top + edgeInset,
                      right: edgeInset,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!_isPractice && _canShowFastForwardRound()) ...[
                            _TableChromeButton(
                              key: const ValueKey('table-chrome-fast-forward'),
                              tooltip: strings.skipToNextRound,
                              icon: Icons.fast_forward_rounded,
                              diameter: buttonSize,
                              iconSize: iconSize,
                              onPressed: _isFastForwardingRound
                                  ? () {}
                                  : () => unawaited(_fastForwardRound()),
                            ),
                            SizedBox(width: edgeInset * 0.6),
                          ],
                          // Guided practice has no match to pause (and its own
                          // close button exits to the hub), so the pause
                          // control is hidden during a lesson.
                          if (!_isPractice)
                            _TableChromeButton(
                              tooltip: strings.pauseTable,
                              icon: Icons.pause_rounded,
                              diameter: buttonSize,
                              iconSize: iconSize,
                              onPressed: () =>
                                  setState(() => _pauseOpen = true),
                            ),
                        ],
                      ),
                    ),
                    if (_cues.feedback != null)
                      Positioned(
                        top:
                            safe.top +
                            edgeInset +
                            math.max(0.0, (buttonSize - 34) / 2),
                        left: edgeInset + buttonSize + 14,
                        right: edgeInset + buttonSize + 14,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: IgnorePointer(
                            child: _FeedbackChip(
                              message: _cues.feedback!.text,
                              isError: _cues.feedback!.isError,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            if (coachHint != null)
              CoachOverlay(
                key: const ValueKey('coach-overlay'),
                hint: coachHint,
                stageHint: coachHints?.stageNote,
                highContrast: widget.preferences.highContrastCards,
              ),
            // Practice step prompt: persistent through the player's own card
            // flights (unlike the coach), hidden only under blocking overlays
            // and while a scripted intro still owns the turn — the prompt
            // narrates the player's move, not the seat they are watching. A
            // dead-ended run hands narration to the missed-lesson overlay.
            if (practiceBanner != null)
              _buildPracticeStepBanner(strings, practiceBanner),
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
                child: MeldFlightOverlay(flight: meld, theme: theme),
              ),
          ],
        ),
      ),
    );

    return PopScope(
      // Practice rides a pushed route under the hub; the system back simply
      // pops to it. A real match owns the root stack and exits to home.
      canPop: _isPractice,
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
                onClose: () => setState(() {
                  _scoreOpen = false;
                  // A scoring lesson's reveal hands off to the completion
                  // overlay once the sheet is read.
                  if (_practiceScoreReveal) {
                    _practiceRun?.finishScoreReveal();
                  }
                }),
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
                showCoachingTips: strictness.showsProactiveHints,
                coachingTipsEnabled: widget.preferences.coachingTipsEnabled,
                onCoachingTipsChanged: (v) => widget.onPreferencesChanged(
                  widget.preferences.copyWith(coachingTipsEnabled: v),
                ),
                onResume: () => setState(() => _pauseOpen = false),
                onReportTableIssue: () {
                  setState(() => _pauseOpen = false);
                  unawaited(_exportActiveMatchReport());
                },
                onLeave: _isPractice
                    ? () => Navigator.of(context).pop()
                    : _returnToMainMenu,
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
              visible: _practiceComplete,
              overlayKey: 'practice-completion-overlay-slot',
              duration: _scaledDelay(const Duration(milliseconds: 220)),
              child: !_practiceComplete
                  ? const SizedBox.shrink()
                  : PracticeCompletionOverlay(
                      note: _practiceRun!.completionNote(strings),
                      onReplay: () =>
                          _startPracticeLesson(_practiceRun!.script),
                      onNext: nextPracticeScript == null
                          ? null
                          : () => _startPracticeLesson(nextPracticeScript),
                      onDone: () => Navigator.of(context).pop(),
                    ),
            ),
            _AnimatedOverlaySlot(
              visible: _practiceDeadEnd,
              overlayKey: 'practice-missed-overlay-slot',
              duration: _scaledDelay(const Duration(milliseconds: 220)),
              child: !_practiceDeadEnd
                  ? const SizedBox.shrink()
                  : PracticeMissedOverlay(
                      note: _practiceRun!.missedNote(
                        strings,
                        fallback: strings.practiceFiftyMissed,
                      ),
                      onRestart: () =>
                          _startPracticeLesson(_practiceRun!.script),
                      onDone: () => Navigator.of(context).pop(),
                    ),
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
            _AnimatedOverlaySlot(
              visible: _matchOverPresentation != null,
              overlayKey: 'match-over-overlay-slot',
              duration: _scaledDelay(const Duration(milliseconds: 240)),
              child: _matchOverPresentation == null
                  ? const SizedBox.shrink()
                  : MatchOverOverlay(
                      result: _matchOverPresentation!.result,
                      progress: _matchOverPresentation!.progress,
                      roundsPlayed: _controller.roundNumber,
                      eliminatedRound: Map<PlayerSeat, int>.unmodifiable(
                        _matchEliminatedRoundBySeat,
                      ),
                      highContrast: widget.preferences.highContrastCards,
                      onRematch: _restartMatchSameSetup,
                      onReturnToMenu: _returnToMainMenu,
                      onExportReport: () => unawaited(
                        _exportCompletedMatchReport(_matchOverPresentation!),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the persistent step prompt for the active practice lesson.
  Widget _buildPracticeStepBanner(
    AppStrings strings,
    PracticeTableBannerState banner,
  ) {
    return PracticeStepBanner(
      key: const ValueKey('practice-step-banner'),
      stepIndex: banner.stepIndex,
      stepCount: banner.stepCount,
      prompt: banner.prompt(strings),
      hint: banner.hint?.call(strings),
      reaction: banner.reaction?.call(strings),
      highContrast: widget.preferences.highContrastCards,
    );
  }

  /// Starts [script] on a fresh board without leaving the route — the same
  /// in-place controller swap [_advanceToNextRound] uses, minus the deal
  /// choreography. Serves both replay (same script) and the completion
  /// overlay's next-lesson continuation; swapping routes instead would let
  /// the replaced table's dispose() flip a live landscape lesson to portrait.
  void _startPracticeLesson(PracticeLessonScript script) {
    final run = _practiceRun;
    if (run == null) {
      return;
    }
    run.restart(script);
    // Drain every cue timer + the fifty ticker before swapping controllers
    // so no stale dwell can fire against the fresh lesson board.
    _cues.resetAll();
    _cues.stopFiftyTicker();
    setState(() {
      _controller = run.controller;
      _coachInsightCacheKey = null;
      _coachInsights = const [];
      _resetHandInteraction();
      _isCpuRunning = false;
      _scoreOpen = false;
      _pauseOpen = false;
      _placedJokerSnapshot = null;
      _activeFlights.clear();
      _meldFlight.clear();
      _inspectedCard = null;
      _roundResultPresentation = null;
    });
    _ensureFiftyTicker();
    unawaited(_runPracticeIntro());
  }

  /// Projects the active practice step onto the coach's highlight language,
  /// so lessons and the live coaching tier guide with one visual vocabulary:
  /// the step's named cards ring in the hand, and the draw or take affordance
  /// the step allows rings its pile. Steps that deliberately leave the choice
  /// open (pick any discard) ring nothing.
  CoachHighlighting _practiceStepHighlighting({required bool isHumanTurn}) {
    return _practiceRun?.highlighting(
          isHumanTurn: isHumanTurn,
          topDiscard: _controller.topDiscard,
        ) ??
        CoachHighlighting.none;
  }

  /// Builds the coaching hints to surface this frame — the actionable PRIMARY
  /// hint plus an optional once-per-round STAGE note — or null when nothing
  /// should show. The caller folds the persistent conditions (tier, toggle,
  /// turn ownership) into whether this runs at all; [gate] carries the
  /// transient ones (blocking overlays, in-flight motion).
  ({CoachHint? primary, CoachHint? stageNote})? _buildCoachHints(
    AppStrings strings,
    PlayerSeat seat, {
    required bool gate,
  }) {
    // Always recompute while the coach is live (cheap — memoized by the
    // situation signature) so the cached insights track every controller-state
    // change. The [gate] only hides the *display* while something is
    // mid-animation; it must NOT freeze the *data*, or a hint computed before
    // a draw/cover landed survives stale once the gate reopens (the playtest
    // "discard the card you just melded" bug). Compute first, then gate the
    // display.
    final insights = _coachInsightsFor(seat);
    if (!gate || insights.isEmpty) {
      return null;
    }
    if (_controller.currentSeat != _coachTurnSeat) {
      _coachTurnSeat = _controller.currentSeat;
      _coachTurnCounter += 1;
    }
    final selection = _coachInsightFlow.select(
      insights: insights,
      roundNumber: _controller.roundNumber,
      turnKey: '${_controller.roundNumber}:$_coachTurnCounter',
    );
    CoachHint? presentOf(CoachingInsight? insight) => insight == null
        ? null
        : CoachHintPresenter.present(
            insight: insight,
            strings: strings,
            identityForCardId: _identityForCardId,
            topDiscardIdentity: _controller.topDiscard?.effectiveIdentity,
          );
    final primary = presentOf(selection.primary);
    final stageNote = presentOf(selection.stageNote);
    if (primary == null) {
      // Nothing actionable this frame (rare edge: only banner insights). Let
      // the stage note carry the callout rather than going dark.
      return (primary: stageNote, stageNote: null);
    }
    return (primary: primary, stageNote: stageNote);
  }

  /// Memoized advisor call. Recomputes only when the cheap situation signature
  /// (turn, turn phase, opened state, top discard, pending, Fifty claimant, hand
  /// ids, own meld ids) changes, so the fifty ticker and card flights don't
  /// trigger re-analysis. The turn phase is part of the key because a draw flips
  /// draw→action with the same seat: without it a draw that completes a meld
  /// could reuse the pre-draw insight (the stale-discard playtest bug). The Fifty
  /// claimant is included because the Fifty hint depends on whether a claim
  /// window is open for this seat, and a window can open or expire without the
  /// top discard changing. The claim-LIVENESS bit (timer still running) is also
  /// keyed — it flips exactly once per window, letting the hint hand over from
  /// "Claim the Fifty" to "take it and finish" when the timer lapses — but the
  /// raw seconds remaining are deliberately NOT keyed (that would re-analyse
  /// every tick).
  List<CoachingInsight> _coachInsightsFor(PlayerSeat seat) {
    final hand = _controller.handFor(seat);
    final ownMelds = _controller.tableMeldsFor(seat);
    final key = StringBuffer()
      ..write(_controller.currentSeat.name)
      ..write('#')
      ..write(_controller.turnPhase.name)
      ..write(_controller.openingState.hasOpened(seat) ? '#1' : '#0')
      ..write('#')
      ..write(_controller.topDiscard?.id ?? '-')
      ..write('#')
      ..write(_controller.pendingDiscard?.id ?? '-')
      ..write('#f:')
      ..write(_controller.fiftyClaimant?.name ?? '-')
      ..write((_controller.fiftySecondsRemaining ?? 0) > 0 ? '+' : '-')
      ..write('#h:');
    for (final card in hand) {
      key
        ..write(card.id)
        ..write(',');
    }
    key.write('#m:');
    for (final meld in ownMelds) {
      for (final card in meld.cards) {
        key
          ..write(card.id)
          ..write(',');
      }
      key.write('|');
    }
    final keyStr = key.toString();
    if (keyStr != _coachInsightCacheKey) {
      _coachInsightCacheKey = keyStr;
      _coachInsights = ClassicHareegCoachingAdvisor.adviseFor(
        _controller,
        seat,
      );
      final leadInsight = _coachInsights.isEmpty ? null : _coachInsights.first;
      if (leadInsight != null) {
        _recorder?.recordCoachHint(
          roundNumber: _controller.roundNumber,
          hintId: leadInsight.category.name,
          seat: seat,
          phase: _controller.turnPhase,
          data: {'count': _coachInsights.length},
        );
      }
    }
    return _coachInsights;
  }

  /// Resolves a card id referenced by a coaching insight to its identity for
  /// hint copy. Insights only point at the human hand, the top discard, or the
  /// human's own table melds.
  CardIdentity? _identityForCardId(String cardId) {
    for (final card in _controller.handFor(PlayerSeat.south)) {
      if (card.id == cardId) {
        return card.effectiveIdentity;
      }
    }
    final top = _controller.topDiscard;
    if (top != null && top.id == cardId) {
      return top.effectiveIdentity;
    }
    for (final meld in _controller.tableMeldsFor(PlayerSeat.south)) {
      for (final card in meld.cards) {
        if (card.id == cardId) {
          return card.effectiveIdentity;
        }
      }
    }
    return null;
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

  ClassicHareegTableInteractionPlanner _tableInteraction(
    TableHandInteractionSnapshot? southHand, {
    TableInteractionActionGate? actionGate,
  }) {
    final hand = southHand ?? _southHandInteraction();
    final controllerReader = ClassicHareegControllerTableInteractionReader(
      _controller,
    );
    final isHumanTurn =
        _controller.currentSeat == PlayerSeat.south && _canAcceptHumanInput;
    return ClassicHareegTableInteractionPlanner(
      // Practice narrows every gesture affordance to the step being taught;
      // a finished lesson locks the board under the completion overlay.
      reader: controllerReader,
      seat: PlayerSeat.south,
      selectedCardIds: hand.selectedCardIds,
      handCards: hand.orderedCards,
      inputLocked: !_canAcceptHumanInput || _practiceComplete,
      actionGate: actionGate ?? _tableActionGate(isHumanTurn: isHumanTurn),
    );
  }

  TableInteractionActionGate _tableActionGate({required bool isHumanTurn}) {
    return _practiceRun?.actionGate(isHumanTurn: isHumanTurn) ??
        const AllowAllTableInteractionActionGate();
  }

  Future<void> _dropCardToDiscard(HareegCard card) async {
    if (!_canAcceptHumanInput) return;
    await _runTableInteraction(_tableInteraction(null).resolveDiscard(card));
  }

  Future<void> _dropCardToTable(HareegCard card) async {
    if (!_canAcceptHumanInput) return;
    await _runTableInteraction(_tableInteraction(null).resolveTableDrop(card));
  }

  Future<void> _dropCardToMeld(
    HareegCard card,
    TableMeldDropTarget target,
  ) async {
    if (!_canAcceptHumanInput) return;
    await _runTableInteraction(
      _tableInteraction(null).resolveMeldDropTarget(card, target),
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
    final jokerChoices = _tableInteraction(
      null,
    ).jokerChoicesForCardIds(cardIds);
    if (jokerChoices.length > 1) {
      final choice = await _showJokerChoiceDialog(jokerChoices);
      if (!mounted || choice == null) return;
      await _runHumanAction(choice.actionId);
      return;
    }

    await _runHumanAction(fallbackActionId);
  }

  /// Returns the picked-up card. During a Fifty proof turn this is the
  /// explicit "give up" gesture and carries the tier penalty, so it asks for
  /// confirmation first — a stray tap should never silently cost +17 and the
  /// round.
  Future<void> _returnPendingDiscard() async {
    if (_controller.isFiftyProofTurn) {
      final confirmed = await _confirmGiveUpFifty();
      // The dialog is an async gap; bail if the table was disposed while it
      // was open rather than running an action that would setState().
      if (!mounted || confirmed != true) {
        return;
      }
    }
    await _runHumanAction(ClassicHareegActionIds.returnPendingDiscard);
  }

  Future<bool?> _confirmGiveUpFifty() {
    final strings = context.strings;
    final body = _controller.setup.tableStrictness == TableStrictness.table
        ? strings.giveUpFiftyBodyTable
        : strings.giveUpFiftyBodyPenalty;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final dialogStrings = dialogContext.strings;
        return AlertDialog(
          key: const ValueKey('give-up-fifty-dialog'),
          title: Text(dialogStrings.giveUpFiftyTitle),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogStrings.keepTrying),
            ),
            FilledButton(
              key: const ValueKey('give-up-fifty-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(dialogStrings.giveUpFiftyConfirm),
            ),
          ],
        );
      },
    );
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
    ClassicHareegTableInteractionPlanner tableInteraction,
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

  /// Pulses the offending card during a Strict-tier +3 reject. The "+N"
  /// toast itself is driven by the flow planner and `_replaceHumanFeedback`;
  /// this only manages the brief invalid-state flash on the south hand.
  /// Delegates to [_cues] so the timer + clear semantics live in one place.
  void _scheduleRevertFlash(String? revertedCardId) {
    _cues.scheduleRevertFlash(
      revertedCardId,
      dwell: _scaledDelay(_revertFlashDuration),
    );
  }

  void _replaceHumanFeedback(String? message, {required bool isError}) {
    final nextText = message == null || message.isEmpty
        ? null
        : context.strings.gameMessage(message);
    final next = nextText == null
        ? null
        : TableFeedbackMessage(text: nextText, isError: isError);
    final duration = next == null
        ? Duration.zero
        : _scaledDelay(
            isError ? _errorFeedbackDuration : _successFeedbackDuration,
          );
    _cues.replaceFeedback(next, autoDismissAfter: duration);
  }

  void _showInvalidFeedback(String message) {
    unawaited(_haptics.fire(TableHapticEvent.illegalAction));
    unawaited(_audio.play(TableSoundEvent.invalidAction));
    _replaceHumanFeedback(message, isError: true);
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
  /// other. The [needsSetState] flag is preserved for symmetry with the
  /// pre-refactor signature; the choreographer notifies on each pump so the
  /// caller no longer needs to wrap.
  void _emitFeedbackForFirstNewJoker({required bool needsSetState}) {
    // Lessons narrate declarations through the step banner and its notes;
    // the table's own "joker declared" cue would talk over the teaching
    // voice (both for the scripted intro and the player's taught meld).
    if (_isPractice) return;
    final newJokers = _consumeJokerPlacements();
    if (newJokers.isEmpty) return;
    if (needsSetState && !mounted) return;
    _cues.enqueueJokerCues(newJokers);
  }

  void _onJokerCueStart(({PlayerSeat seat, CardIdentity identity}) cue) {
    if (!mounted) return;
    final strings = context.strings;
    final text = cue.seat == PlayerSeat.south
        ? strings.youDeclaredJoker(cue.identity)
        : strings.jokerDeclaredBySeat(cue.seat, cue.identity);
    unawaited(_audio.play(TableSoundEvent.jokerDeclared));
    // The choreographer pumps this for both the first cue (synchronously
    // from enqueueAll) and every subsequent cue (synchronously from the
    // dwell timer); calling setFeedbackUnmanaged keeps both paths consistent
    // and notifies listeners exactly once per pump.
    _cues.setFeedbackUnmanaged(
      TableFeedbackMessage(text: text, isError: false),
    );
  }

  void _onJokerCueEnd(({PlayerSeat seat, CardIdentity identity}) cue) {
    if (!mounted) return;
    final strings = context.strings;
    final text = cue.seat == PlayerSeat.south
        ? strings.youDeclaredJoker(cue.identity)
        : strings.jokerDeclaredBySeat(cue.seat, cue.identity);
    // Withdraw this cue's message only if it still owns the feedback line;
    // the next cue's start callback (if any) fires immediately after this
    // and will publish its own message via setFeedbackUnmanaged.
    _cues.withdrawFeedbackIf(TableFeedbackMessage(text: text, isError: false));
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

    // Carry the target lane's meld card counts so a cover/replacement flight
    // lands on the meld it targets rather than the lane centre (the same
    // arrangement the lane renders from).
    final endMeldSlot = realization.endMeldSlot;
    return _CardFlight(
      serial: serial,
      card: card,
      faceDown: realization.faceDown,
      begin: _flightBegin(presentation),
      end: _flightEnd(presentation),
      duration: duration,
      beginHandSlot: realization.beginHandSlot,
      endHandSlot: realization.endHandSlot,
      endMeldSlot: endMeldSlot == null
          ? null
          : TableMeldFlightSlot(
              seat: endMeldSlot.seat,
              index: endMeldSlot.index,
              laneMeldCardCounts: [
                for (final meld in _controller.tableMeldsFor(endMeldSlot.seat))
                  meld.cards.length,
              ],
            ),
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
      TableActionFlightSource.handCard => TableFlightAnchors.seatHand(
        plan.seat,
      ),
    };
  }

  Alignment _flightEnd(TableActionFlightPlan plan) {
    return switch (plan.destination) {
      TableActionFlightDestination.seatHand => TableFlightAnchors.seatHand(
        plan.seat,
      ),
      TableActionFlightDestination.discardPile => TableFlightAnchors.discard,
      TableActionFlightDestination.tableMeld => TableFlightAnchors.seatHand(
        plan.seat,
      ),
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
    unawaited(_haptics.fire(TableHapticEvent.fiftyClaim));
    _cues.scheduleFiftyPulse(dwell: _scaledDelay(TableMotion.fiftyHeatPulse));
  }

  Future<void> _runHumanAction(
    String actionId, {
    bool playFlight = true,
  }) async {
    final startPlan = ClassicHareegTableSessionFlowPlanner.startHumanAction(
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
      final applyGate = ClassicHareegTableSessionFlowPlanner.afterHumanPreApply(
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
    // Practice routes the apply through the session so the lesson step gates
    // and observes the same engine mutation the table would make directly.
    final practice = _practiceRun;
    final practiceSubmission = practice?.submitTableAction(actionId);
    if (practiceSubmission?.isOffScript ?? false) {
      // Legal engine action, but off-script for this step. Affordance gating
      // makes this near-unreachable; keep a gentle nudge as the backstop.
      _placedJokerSnapshot = null;
      setState(() {
        _replaceHumanFeedback(
          context.strings.practiceFollowStep,
          isError: false,
        );
      });
      return;
    }
    final result = practiceSubmission == null
        ? _controller.applyAction(actionId)
        : practiceSubmission.tableResult;
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
    final flowPlan = ClassicHareegTableSessionFlowPlanner.afterHumanApply(
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
      _replaceHumanFeedback(
        flowPlan.feedbackMessage,
        isError: flowPlan.feedbackIsError,
      );
      if (result.wasReverted) {
        // Strict +3: planner surfaced the "+N" chip above; flash the
        // offending card so the human sees which discard was rejected.
        _scheduleRevertFlash(result.revertedCardId);
      } else if (result.isSuccess) {
        // Multi-joker melds report only the leftmost declaration.
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
    if (practiceSubmission != null) {
      // Lesson flow replaces the match pipeline: no persistence, no CPU
      // turns, no round-result overlay.
      _handlePracticeProgress(practiceSubmission);
      return;
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

  /// Advances the lesson presentation after a successfully applied practice
  /// action: surfaces the completed step's confirmation on the feedback chip
  /// and raises the completion overlay when the final step lands.
  void _handlePracticeProgress(PracticeTableActionSubmission submission) {
    final run = _practiceRun;
    if (run == null) {
      return;
    }
    final result = submission.result;
    final effect = run.applyProgress(result, submission.completedStep);
    if (effect.shouldPersistCompletion) {
      final lessonId = effect.lessonId;
      if (lessonId != null) {
        // Persistence stays non-blocking so the completion overlay raises
        // immediately; the catchError guard keeps a throwing handler from
        // stranding an unhandled async error (the shell's own handler logs
        // its failures, this covers any other callback).
        unawaited(
          widget.onPracticeFinished?.call(lessonId).catchError((
            Object error,
            StackTrace stackTrace,
          ) {
            debugPrint('Failed to record practice completion: $error');
            debugPrintStack(stackTrace: stackTrace);
          }),
        );
      }
    }
    if (!effect.shouldRebuild) {
      return;
    }
    setState(() {
      if (result.status == PracticeSubmitStatus.lessonCompleted) {
        _pauseOpen = false;
        _inspectedCard = null;
        // A scoring lesson shows its consequence on the real score sheet
        // first; the completion overlay waits for the sheet to close.
        if (effect.shouldOpenScoreReveal) {
          _scoreOpen = true;
        } else {
          _scoreOpen = false;
        }
      }
    });
  }

  /// Whether the Table-tier "skip to next round" chrome button should show.
  ///
  /// Visibility is intentionally narrow:
  /// 1. `strictness == TableStrictness.table` — the +17/removal penalty is
  ///    the only flow that puts the human out of an in-flight round.
  /// 2. South is currently in `removedSeats` — the human has actually been
  ///    kicked from this round and is locked out of acting on it.
  /// 3. The round is not over yet — there is still CPU play to skip.
  ///
  /// While the fast-forward is already running we still return true so the
  /// button keeps its slot (it just no-ops on tap via the disabled handler).
  bool _canShowFastForwardRound() {
    return ClassicHareegTableSessionFlowPlanner.canFastForwardRound(
      strictness: _controller.setup.tableStrictness,
      removedSeats: _controller.removedSeats,
      isRoundOver: _controller.isRoundOver,
    );
  }

  /// Rips the remaining CPU turns to the end of the round with no animations,
  /// no audio cues, and no per-action persistence. The CPU planner is reused
  /// so scoring stays honest (the round outcome is exactly what would happen
  /// if the player watched it play out) but the spectating beats are skipped.
  /// Once the round ends we hand off to the normal persistence + round-result
  /// pipeline, which then schedules the next round (or short-circuits to
  /// MatchOver when south has dropped under the elimination score).
  Future<void> _fastForwardRound() async {
    if (_isFastForwardingRound) return;
    if (_controller.isRoundOver) return;
    if (!_canShowFastForwardRound()) return;

    setState(() {
      _isFastForwardingRound = true;
      _isCpuRunning = true;
      // Hide pending feedback chips and drain every cue mechanism so they
      // don't linger across the rip.
      _cues.resetAll();
      _activeFlights.clear();
      _meldFlight.clear();
    });
    try {
      await _cpuTurnPresenter().fastForwardUntilRoundOver();
    } finally {
      if (mounted) {
        setState(() {
          _isFastForwardingRound = false;
          _isCpuRunning = false;
        });
      } else {
        _isFastForwardingRound = false;
        _isCpuRunning = false;
      }
    }
    if (!mounted) return;
    await _persistAndMaybeFinish();
  }

  ClassicHareegTableCpuTurnPresenter _cpuTurnPresenter({
    CpuStrategy? strategy,
    int? actionLimit,
    bool Function()? isMounted,
  }) {
    return ClassicHareegTableCpuTurnPresenter(
      controller: _controller,
      strategy: strategy ?? widget.cpuStrategy,
      actionLimit: actionLimit ?? _cpuActionLimit,
      readPause: _cpuReadPause,
      hooks: ClassicHareegTableCpuTurnPresenterHooks(
        isMounted: isMounted ?? () => mounted,
        hasRoundResultPresentation: () => _roundResultPresentation != null,
        log: _debugTableLog,
        playFlightForCpuAction: _playFlightForCpuAction,
        capturePlacedJokersForAction: _capturePlacedJokersForAction,
        emitJokerFeedback: () =>
            _emitFeedbackForFirstNewJoker(needsSetState: true),
        clearPlacedJokerSnapshot: () {
          _placedJokerSnapshot = null;
        },
        dropPendingSettledFor: _meldFlight.dropPendingSettledFor,
        ensureFiftyTicker: _ensureFiftyTicker,
        persistAndMaybeFinish: _persistAndMaybeFinish,
        postActionDwell: _postActionDwell,
      ),
    );
  }

  void _capturePlacedJokersForAction(String actionId) {
    final descriptor = ClassicHareegActionIds.describe(actionId);
    _placedJokerSnapshot = descriptor.canPlaceJoker
        ? _capturePlacedJokerIds()
        : null;
  }

  /// Plays the lesson's scripted intro — the turns other seats take before
  /// the player's first step (west throwing the card the lesson teaches, or
  /// visibly opening its melds) — through the same presenter live CPU turns
  /// use, so the flights, pacing, and sounds match a real match. No-ops for
  /// lessons whose board already starts on the player's turn.
  Future<void> _runPracticeIntro() async {
    final practice = _practiceRun;
    final session = practice?.session;
    if (practice == null ||
        session == null ||
        !practice.shouldRunScriptedIntro(isCpuRunning: _isCpuRunning)) {
      return;
    }
    final intro = practice.introActionIds;
    setState(() => _isCpuRunning = true);
    // Resolve the lead-in before the first await: MotionScope is an
    // inherited read that needs a live context.
    final leadIn = _scaledDelay(_practiceIntroLeadIn);
    bool stillThisLesson() => mounted && identical(_practiceSession, session);
    try {
      // Let the player read the fresh board before the first scripted move.
      await Future<void>.delayed(leadIn);
      if (!stillThisLesson()) {
        return;
      }
      await _cpuTurnPresenter(
        strategy: PracticeIntroStrategy(intro),
        actionLimit: intro.length + 1,
        isMounted: stillThisLesson,
      ).runVisible();
    } catch (error, stackTrace) {
      _debugTableLog('practice intro failed error=$error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (identical(_practiceSession, session)) {
        if (mounted) {
          setState(() => _isCpuRunning = false);
        } else {
          _isCpuRunning = false;
        }
      }
    }
  }

  Future<bool> _runCpuTurns() async {
    // Practice lessons have no CPU autonomy beyond the scripted intro: the
    // board waits on the player's next step even when the turn passes to
    // another seat.
    if (_isPractice) {
      return false;
    }
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
      final result = await _cpuTurnPresenter().runVisible();
      if (!mounted) {
        return result.didApplyAction;
      }
      _prewarmHumanDrawControls();
      final hitCpuSafetyLimit = result.reachedSafetyLimit;
      // When the human is out of the round we cannot let the CPU loop pause
      // on the safety cap — there is no human to take over, so the round
      // would deadlock waiting for input. Re-enter the loop instead; the
      // round will end naturally on stock exhaustion or a CPU finish.
      final humanRemoved = _controller.removedSeats.contains(PlayerSeat.south);
      // Bound the auto-restart so a non-progressing round can never spin the
      // table forever. The engine draws a dead stock-exhausted round, so a real
      // game stops re-entering well before this cap; exceeding it means progress
      // has genuinely stalled and we stop rather than freeze.
      if (!hitCpuSafetyLimit || _controller.isRoundOver) {
        _cpuAutoRestarts = 0;
      }
      final shouldAutoRestart = hitCpuSafetyLimit &&
          humanRemoved &&
          _cpuAutoRestarts < _maxCpuAutoRestarts;
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
        _cpuAutoRestarts += 1;
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
    // Practice never touches the active-match store and never enters the
    // round-result / next-round pipeline; lesson completion has its own
    // overlay driven by the session.
    if (_isPractice) {
      return true;
    }
    final totalWatch = Stopwatch()..start();
    final isRoundOver = _controller.isRoundOver;
    final scoreView = _controller.scoreView;
    // Once the human is eliminated the match is over for them: don't deal a
    // CPU-only next round (which would also persist as a resumable spectator
    // match). A null next-round snapshot makes the persistence plan abandon the
    // match and the round-advance plan open match-over.
    final shouldDealNextRound = isRoundOver && !_controller.isHumanEliminated;
    final persistencePlan = ClassicHareegTablePersistencePlanner.plan(
      isRoundOver: isRoundOver,
      activeSnapshot: isRoundOver ? null : _controller.toSnapshot(),
      nextRoundSnapshot:
          shouldDealNextRound ? _controller.nextRoundSnapshot() : null,
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
          _recorder?.recordPersistence(
            type: 'saved',
            roundNumber: _controller.roundNumber,
            data: {'roundOver': isRoundOver},
          );
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
    final advancePlan = ClassicHareegRoundAdvancePlanner.afterRoundResultShown(
      presentation: presentation,
      isHumanEliminated: _controller.isHumanEliminated,
      nextRoundDelay: _roundResultDisplayDuration,
      matchEndDelay: _scaledDelay(_matchEndOverlayDwell),
    );
    _scheduleRoundAdvance(advancePlan, presentation);
  }

  void _rememberEliminatedRoundsFromController() {
    _matchEliminatedRoundBySeat.addAll(_controller.seatEliminatedRound);
  }

  void _scheduleRoundAdvance(
    ClassicHareegRoundAdvancePlan plan,
    ClassicHareegRoundResultPresentation presentation,
  ) {
    if (!plan.shouldSchedule) {
      return;
    }
    _cues.scheduleRoundAdvance(plan.delay, () {
      if (!mounted) return;
      switch (plan.action) {
        case ClassicHareegRoundAdvanceAction.none:
          return;
        case ClassicHareegRoundAdvanceAction.openMatchOver:
          _openMatchOver(presentation);
        case ClassicHareegRoundAdvanceAction.advanceToNextRound:
          _advanceToNextRound(plan.nextSnapshot!);
      }
    });
  }

  void _openMatchOver(ClassicHareegRoundResultPresentation presentation) {
    _rememberEliminatedRoundsFromController();
    _cues.resetAll();
    _cues.stopFiftyTicker();
    _dealChoreography?.dispose();
    _dealChoreography = null;
    // Show the dedicated match-over overlay in place instead of pushing a
    // separate (portrait) route — the table stays landscape and the rematch
    // restarts without a rotation round-trip.
    setState(() {
      _roundResultPresentation = null;
      _matchOverPresentation = presentation;
    });
  }

  /// Starts a fresh match with the same setup without leaving the table.
  void _restartMatchSameSetup() {
    // Settings may have been retuned mid-match via the pause overlay; mirror
    // what just played, exactly like the old route-based rematch did.
    final setup = _controller.setup;
    _cues.resetAll();
    _cues.stopFiftyTicker();
    _dealChoreography?.dispose();
    _dealChoreography = null;
    _matchEliminatedRoundBySeat.clear();
    final recorder = _isPractice ? null : MatchRecorder();
    _recorder = recorder;
    setState(() {
      _controller = ClassicHareegGameController.fromRound(
        ClassicHareegRound.deal(setup: setup),
        recorder: recorder,
      );
      _coachInsightCacheKey = null;
      _coachInsights = const [];
      _resetHandInteraction();
      _dealChoreography = _buildDealChoreography();
      _isCpuRunning = false;
      _scoreOpen = false;
      _pauseOpen = false;
      _placedJokerSnapshot = null;
      _activeFlights.clear();
      _meldFlight.clear();
      _inspectedCard = null;
      _roundResultPresentation = null;
      _matchOverPresentation = null;
    });
    if (recorder != null) {
      recorder.recordPersistence(
        type: 'dealt',
        roundNumber: _controller.roundNumber,
        data: const {'stage': 'rematch'},
      );
    }
    _ensureFiftyTicker();
    _scheduleTurnFlow();
  }

  Future<void> _exportCompletedMatchReport(
    ClassicHareegRoundResultPresentation presentation,
  ) async {
    final choice = await showMatchReportConfirmation(
      context,
      highContrast: widget.preferences.highContrastCards,
    );
    if (!mounted || choice == null) {
      return;
    }
    final ClassicHareegMatchReport report;
    try {
      final generatedAt = DateTime.now().toUtc();
      report = ClassicHareegMatchReport.completed(
        app: HareegAppMetadata.reportMetadata,
        platform: currentMatchReportPlatform(),
        generatedAt: generatedAt,
        snapshot: _controller.toSnapshot(savedAt: generatedAt),
        roundResult: presentation.result,
        matchProgress: presentation.progress,
        diagnostics: _recorder?.diagnostics,
        transcript: _recorder?.transcript,
      );
    } on Object catch (error, stackTrace) {
      debugPrint('[hareeg:reports] Failed to generate match report: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        showLoungeToast(
          context,
          message: context.strings.matchReportGenerationFailed,
          icon: Icons.error_outline,
          isError: true,
        );
      }
      return;
    }
    switch (choice) {
      case MatchReportExportChoice.share:
        await _shareOrOfferCopy(report);
      case MatchReportExportChoice.copy:
        await _copyMatchReport(report);
    }
  }

  void _advanceToNextRound(ClassicHareegMatchSnapshot snapshot) {
    _rememberEliminatedRoundsFromController();
    // Drain every cue timer + the fifty ticker before swapping controllers
    // so no stale dwell can fire against the freshly dealt hand.
    _cues.resetAll();
    _cues.stopFiftyTicker();
    _dealChoreography?.dispose();
    _dealChoreography = null;
    setState(() {
      _controller = ClassicHareegGameController.fromSnapshot(
        snapshot,
        recorder: _recorder,
      );
      // The coach memo is tied to the previous controller instance; drop it so
      // the new round computes fresh insights instead of risking a stale cache
      // hit on a matching situation signature.
      _coachInsightCacheKey = null;
      _coachInsights = const [];
      _resetHandInteraction();
      _dealChoreography = _buildDealChoreography();
      _isCpuRunning = false;
      _scoreOpen = false;
      _pauseOpen = false;
      _placedJokerSnapshot = null;
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
    super.key,
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
