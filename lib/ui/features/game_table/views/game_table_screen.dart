import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../../../../data/persistence/match_history_repository.dart';
import '../../../../domain/classic_hareeg/history/match_history_outcomes.dart';
import '../../../../domain/classic_hareeg/history/match_id.dart';
import '../../../../domain/classic_hareeg/history/match_terminal_facts.dart';
import '../../../../domain/classic_hareeg/reporting/match_recorder.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_state.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/cards/card_view.dart';
import '../../../core/audio/table_audio.dart';
import '../../../core/feedback/lounge_toast.dart';
import '../../../core/haptics/table_haptics.dart';
import '../../../core/motion/motion_speed.dart';
import '../../../core/panels/lounge_panel.dart';
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
import '../table_mode.dart';
import '../table_persistence_planner.dart';
import '../table_session_config.dart';
import '../practice_table_run.dart';
import '../table_session_flow_planner.dart';
import '../../learning/practice/practice_lesson_script.dart';
import '../../learning/practice/practice_session.dart';
import '../../learning/widgets/practice_completion_overlay.dart';
import '../../learning/widgets/practice_missed_overlay.dart';
import '../../learning/widgets/practice_step_banner.dart';
import '../table_view_scale.dart';
import '../widgets/coach_overlay.dart';
import '../widgets/leave_match_confirmation.dart';
import '../widgets/match_over_overlay.dart';
import '../widgets/meld_flight_overlay.dart';
import '../widgets/pause_overlay.dart';
import '../widgets/physical_table_playfield.dart';
import '../../../core/motion/celebration.dart';
import '../widgets/score_overlay.dart';
import '../widgets/table_background.dart';
import '../../match_reports/match_report_export_flow.dart';
import '../../match_reports/match_report_exporter.dart';

part 'game_table_branch_overlays.dart';
part 'game_table_card_inspect.dart';
part 'game_table_chrome.dart';
part 'game_table_coach.dart';
part 'game_table_dialogs.dart';
part 'game_table_flights.dart';
part 'game_table_report_export.dart';
part 'game_table_round_result.dart';

/// One action that actually applied at a table, observed at the moment it
/// succeeded.
///
/// Carries what the contract's applied-action transcript has to contain: who
/// acted, the exact action id, whether it applied, and the **complete**
/// resulting state — not a sampled digest of it. CPU actions additionally
/// carry the tier that chose and the sorted legal set it was offered; a human
/// action has neither, and says so with nulls rather than with a fabricated
/// value.
class TableAppliedAction {
  /// Creates an applied-action record.
  TableAppliedAction({
    required this.seat,
    required this.isHuman,
    required this.actionId,
    required this.succeeded,
    required this.snapshot,
    this.cpuTier,
    Iterable<String>? legalActionIds,
  }) : legalActionIds = legalActionIds == null
           ? null
           : List.unmodifiable(legalActionIds.toList()..sort());

  /// Seat that acted.
  final PlayerSeat seat;

  /// Whether the human seat acted, as opposed to a CPU.
  final bool isHuman;

  /// Exact action id submitted to the controller.
  final String actionId;

  /// Whether the controller accepted it.
  final bool succeeded;

  /// Complete table state after the action applied.
  final ClassicHareegMatchSnapshot snapshot;

  /// Tier that chose, for a CPU action; null for a human one.
  final CpuDifficulty? cpuTier;

  /// Sorted legal set offered, for a CPU action; null for a human one.
  final List<String>? legalActionIds;
}

/// Live Classic Hareeg table.
///
/// Owns the [ClassicHareegGameController] and orchestrates every player /
/// CPU action through it. Visual / motion / aid / theme / haptics
/// preferences flow in via [preferences] from the app shell so the same
/// surface keeps responding to settings changes made from the pause overlay.
///
/// **What this surface is, and where its writes go, arrive together** in
/// [session]. The two used to be independent parameters — a mode derived from
/// "is there a practice session?" plus two repositories handed in regardless —
/// so a caller could pair any mode with any storage and the only thing
/// stopping a lesson from saving over a real match was a behavioural guard at
/// the write site. [TableSessionConfig] derives both from one closed set of
/// factories, so the branch sandbox reaches no repository because it holds
/// none.
class GameTableScreen extends StatefulWidget {
  /// Creates a table for [session].
  const GameTableScreen({
    super.key,
    required this.setup,
    required this.session,
    required this.preferences,
    required this.onPreferencesChanged,
    this.initialSnapshot,
    this.initialCheckpoint,
    this.cpuStrategy = const ClassicHareegCpuStrategy(),
    this.onPracticeFinished,
    this.nextPracticeScript,
    this.clock,
    this.onSandboxActionApplied,
    this.onSandboxExit,
    this.onSandboxRestart,
    this.sandboxCoachEnabled = false,
    this.onSandboxCoachToggled,
  });

  /// Setup used to deal the round.
  final ClassicHareegSetup setup;

  /// What this surface is and where — if anywhere — its writes go.
  final TableSessionConfig session;

  /// Player preferences (motion, haptics, coaching tips, theme).
  final GamePreferences preferences;

  /// Called by the pause overlay when a preference is toggled mid-match.
  final ValueChanged<GamePreferences> onPreferencesChanged;

  /// Saved snapshot to resume (else deal a fresh round).
  final ClassicHareegMatchSnapshot? initialSnapshot;

  /// Durable checkpoint this match resumes from, when it is a resumed match.
  ///
  /// Carries the identity, recorder state, Fifty counters, match-wide
  /// eliminations, and coach history that a bare snapshot cannot.
  final MatchCheckpoint? initialCheckpoint;

  /// CPU strategy used for non-human seats.
  final CpuStrategy cpuStrategy;

  /// Clock the rules engine reads, or null for the wall clock.
  ///
  /// A branch sandbox rebases a historical Fifty window onto its own start
  /// instant, so the seconds it has left are only assertable when the clock
  /// can be advanced by hand instead of slept through.
  final DateTime Function()? clock;

  /// Called after every action this sandbox actually applies, CPU or South.
  ///
  /// Applied actions, not pointer activity: this is what arms divergence, and
  /// a player who opened a sandbox and looked at it has changed nothing.
  final ValueChanged<TableAppliedAction>? onSandboxActionApplied;

  /// Called when the player asks to leave a sandbox, by any route.
  ///
  /// Pause-leave, the in-app exit control, Android system Back and browser
  /// Back all arrive here, so the confirm-after-divergence policy exists once
  /// rather than four times.
  final VoidCallback? onSandboxExit;

  /// Called when the player asks to replay this sandbox from its branch point.
  final VoidCallback? onSandboxRestart;

  /// Whether the sandbox's session-only live coach is currently on.
  final bool sandboxCoachEnabled;

  /// Called when the sandbox coach is toggled. Null when the archived match
  /// had no coaching, which is what makes the toggle absent rather than off.
  final ValueChanged<bool>? onSandboxCoachToggled;

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

  /// Bumped for every Fifty strike; drives the strike overlay and the
  /// table's impact shake.
  int _fiftyStrikeSerial = 0;
  bool _fiftyStrikeVisible = false;

  void _triggerFiftyStrike() {
    if (!mounted) return;
    setState(() {
      _fiftyStrikeSerial++;
      _fiftyStrikeVisible = true;
    });
  }

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

  /// Seat whose revealed hand is expanded, in study mode only.
  PlayerSeat? _expandedStudySeat;
  static const _revertFlashDuration = Duration(milliseconds: 1100);
  ClassicHareegRoundResultPresentation? _roundResultPresentation;
  // Non-null while the dedicated match-over overlay is shown. The match ends
  // in place on the landscape table (no route change, no rotation); the
  // rematch restarts the controller without leaving the screen.
  ClassicHareegRoundResultPresentation? _matchOverPresentation;
  bool _archiveSaveFailed = false;
  bool _retryingArchive = false;
  final Map<PlayerSeat, int> _matchEliminatedRoundBySeat = {};

  /// Durable checkpoint for this match, carried across saves.
  MatchCheckpoint? _checkpoint;

  final MatchIdMinter _idMinter = MatchIdMinter();

  /// Id of the match this screen was opened resuming, consumed once.
  ///
  /// Cleared by a rematch: only the match the screen opened with may keep the
  /// saved identity.
  late String? _resumedMatchId = widget.initialCheckpoint?.matchId;

  /// Identity for this match, resolved once and reused for every save.
  String? _matchId;

  /// Resolves this match's id, reserving a fresh one on first use.
  ///
  /// A resumed match keeps the id it was already saved under; only a genuinely
  /// new match mints one, and that one is checked against stored history and
  /// replay files so it cannot collide with — and later overwrite — a match
  /// already on the device.
  ///
  /// [history] is passed in rather than read off the widget: the only caller
  /// is inside the durable arm of the persistence dispatch, and taking it as
  /// an argument is what keeps a repository out of scope everywhere else.
  Future<String> _ensureMatchId(MatchHistoryRepository history) async {
    final existing = _matchId;
    if (existing != null) {
      return existing;
    }

    // Only the match this screen was opened with may claim the resumed id.
    // `widget.initialCheckpoint` never changes, so consulting it after a
    // rematch would hand the new match the finished one's identity again.
    final resumed = _resumedMatchId;
    if (resumed != null) {
      return _matchId = resumed;
    }

    return _matchId = await _idMinter.reserve(isTaken: history.isMatchIdTaken);
  }

  /// Whether coaching was available and enabled at any point this match.
  ///
  /// Sticky by design: the summary records whether the player had help, so
  /// switching the coach off later does not erase having used it.
  bool _coachWasEnabled = false;
  int _flightSerial = 0;

  // Coaching-tier advisor memoization. Re-running the partition enumerator on
  // every cue/flight tick would be wasteful, so the insight list is cached
  // against a cheap signature of the human's situation and only recomputed
  // when that signature changes.
  String? _coachInsightCacheKey;
  List<CoachingInsight> _coachInsights = const [];

  // Cross-turn coach surfacing policy: stage banners show once per round each.
  // Match-lifetime state (keys embed the round number, so no reset is needed).
  // Reassigned on rematch: the flow's once-per-round keys embed the round
  // number, and a rematch restarts at round 1 — reusing the old instance
  // would collide with the previous match's seen-banner history.
  CoachInsightFlow _coachInsightFlow = CoachInsightFlow();

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

  /// Which kind of table surface this is.
  ///
  /// Read straight off the session rather than inferred from "is a practice
  /// run present?". The old inference meant the mode and the storage handed in
  /// were two independent facts that could disagree; now one closed set of
  /// factories derives both, so they cannot.
  TableMode get _mode => widget.session.mode;

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
    final practiceSession = widget.session.practiceSession;
    _practiceRun = practiceSession == null
        ? null
        : PracticeTableRun(practiceSession);
    final practice = _practiceRun;
    // A branch sandbox starts from its seed's rebased snapshot. Taking it from
    // the seed rather than from a separately-passed `initialSnapshot` keeps one
    // owner: the host cannot hand the table a state the seed does not describe.
    final snapshot =
        widget.session.branchSeed?.snapshot ?? widget.initialSnapshot;
    // Practice never exports reports, so it skips the recorder entirely.
    //
    // A resumed match restores its recorder instead of building a fresh one.
    // Building a fresh one is exactly the bug this sprint fixes: the new
    // recorder would capture the resumed round as its base and the whole
    // earlier match would vanish from the transcript.
    final restoredState = widget.initialCheckpoint?.recorderState;
    final recorder = practice != null
        ? null
        : restoredState != null
        ? MatchRecorder.restore(restoredState)
        : MatchRecorder();
    _recorder = recorder;
    final resumed = widget.initialCheckpoint;
    if (resumed != null) {
      _checkpoint = resumed;
      _matchEliminatedRoundBySeat.addAll(resumed.eliminationRounds);
      _coachWasEnabled = resumed.coachWasEnabled;
    }
    _controller = practice != null
        ? practice.controller
        : snapshot != null
        ? ClassicHareegGameController.fromSnapshot(
            snapshot,
            recorder: recorder,
            now: widget.clock,
          )
        : ClassicHareegGameController.fromRound(
            ClassicHareegRound.deal(setup: widget.setup),
            recorder: recorder,
            now: widget.clock,
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
    if (!_mode.isPractice) {
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
    // A sandbox is the one table pushed over a surface that is *also*
    // landscape. Restoring portrait on the way out drops the replay viewer
    // underneath into its docked layout, so the player leaves a sandbox and
    // finds the reviewer rearranged. Every other table is pushed from a
    // portrait surface and still restores it.
    if (!_mode.isBranch) {
      AppOrientation.usePortrait();
    }
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

  /// Opponent hands to draw face up.
  ///
  /// Gated on the mode capability alone, so "which surfaces reveal hands" is
  /// answered in the mode table rather than re-decided here. Every other
  /// surface gets an empty map and the identities never enter the widget tree.
  Map<PlayerSeat, List<HareegCard>> _revealedHands() {
    if (!_mode.capabilities.revealsAllHands) {
      return const <PlayerSeat, List<HareegCard>>{};
    }
    return {
      for (final seat in PlayerSeat.values)
        if (seat != PlayerSeat.south &&
            !_controller.removedSeats.contains(seat))
          seat: _controller.handFor(seat),
    };
  }

  /// Tells the host an action actually applied in this sandbox.
  ///
  /// The snapshot is taken here, at the success boundary, so the record is the
  /// state the action produced rather than whatever the board settles into a
  /// few frames later.
  void _notifySandboxAction({
    required PlayerSeat seat,
    required bool isHuman,
    required String actionId,
    required bool succeeded,
    Iterable<String>? legalActionIds,
  }) {
    if (!_mode.isBranch) return;
    final observer = widget.onSandboxActionApplied;
    if (observer == null) return;
    observer(
      TableAppliedAction(
        seat: seat,
        isHuman: isHuman,
        actionId: actionId,
        succeeded: succeeded,
        snapshot: _controller.toPositionSnapshot(
          savedAt: (widget.clock ?? DateTime.now)(),
        ),
        cpuTier: isHuman ? null : _controller.setup.cpuDifficulty,
        legalActionIds: legalActionIds,
      ),
    );
  }

  /// The single exit route out of a sandbox.
  ///
  /// Pause-leave, the in-app exit control, Android system Back and browser
  /// Back all land here, so "confirm only after divergence" is one policy
  /// rather than four that drift.
  void _requestSandboxExit() {
    widget.onSandboxExit?.call();
  }

  /// Web Back-button guard: confirm before leaving an in-progress match.
  Future<void> _confirmLeaveMatch() async {
    final leave = await showLeaveMatchConfirmation(
      context,
      highContrast: widget.preferences.highContrastCards,
    );
    if (!mounted || leave != true) {
      return;
    }
    _returnToMainMenu();
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
    final isHumanSeat = _controller.currentSeat == humanSeat;
    final isHumanTurn = isHumanSeat && _canAcceptHumanInput;
    final actionGate = _tableActionGate(isHumanTurn: isHumanTurn);
    // Track turn passage on EVERY build (CPU turns rebuild the table too),
    // not inside the coach path: that path only runs on the human's turn, so
    // the seat compare never saw the CPU seats in between and the counter
    // stalled — a stage note's "for the turn it first appears in" hold then
    // stretched across every human turn of the round.
    if (_controller.currentSeat != _coachTurnSeat) {
      _coachTurnSeat = _controller.currentSeat;
      _coachTurnCounter += 1;
    }
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
    final meldSuggestions = tableInteraction.meldSuggestions();
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
    // Seat-only on purpose: [isHumanTurn] folds in the transient input locks
    // (_canAcceptHumanInput — CPU runner, deal choreography, pending action),
    // and tying the RECOMPUTE to those reintroduces the stale-cache window
    // compute-then-gate exists to close. Transient conditions only gate the
    // display below.
    // A sandbox inherits its coach from the archived match and nothing else:
    // `coachWasEnabled` is the only eligibility source, and the toggle it
    // exposes lives for the session only. The stored preference is read on a
    // live table and deliberately not consulted here, so a player who turned
    // coaching off since cannot lose the help the archived match had — and,
    // more importantly, one who was never eligible cannot gain it.
    final coachAllowed = _mode.isBranch
        ? widget.session.branchCoachEligible && widget.sandboxCoachEnabled
        : strictness.showsProactiveHints &&
              widget.preferences.coachingTipsEnabled;
    final coachComputes =
        _mode.capabilities.coachSurface == TableCoachSurface.live &&
        coachAllowed &&
        isHumanSeat;
    if (coachComputes) {
      // The fact the summary records is that coaching was available and
      // enabled — not that it happened to produce a hint. A quiet round with
      // nothing to say is still a round the player had help in, so this is set
      // here rather than where an insight is emitted.
      _coachWasEnabled = true;
    }
    final coachActive =
        coachComputes &&
        // The transient input locks (CPU runner / opening deal / pending
        // action) hide the callout exactly as before — they just no longer
        // freeze the data.
        _canAcceptHumanInput &&
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
    final coachHighlighting = _mode.isPractice
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
      // Everything (playfield, chrome, coach, flights) lays out on the
      // playing surface inside the rail, sharing one coordinate space so
      // flights still land on their slots.
      insetChild: true,
      child: JokerDisplayScope(
        display: jokerDisplay,
        cueDuration: _activeJokerVisualCueDuration(strictness),
        child: Stack(
          children: [
            PhysicalTablePlayfield(
              theme: theme,
              centerStock: true,
              seatScores: _mode.isPractice
                  ? const <PlayerSeat, int>{}
                  : _controller.scores,
              eliminationScore: _controller.rules.eliminationScore,
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
              revealedHands: _revealedHands(),
              onExpandRevealedHand: (seat) =>
                  setState(() => _expandedStudySeat = seat),
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
                // A sandbox floors its chrome at the 44 dp target B63 requires.
                //
                // Applied to the whole row rather than to the exit alone: a
                // 44 dp close button beside a 30 dp pause button is not a
                // consistent surface, and the two sit inside one Row where the
                // odd one out reads as a mistake. Scoped to the sandbox
                // deliberately — the live and practice tables keep the corner
                // geometry earlier sprints accepted, and nothing here changes
                // for them.
                final chromeFloor = _mode.isBranch ? 44.0 : 0.0;
                final buttonSize = math.max(
                  chromeFloor,
                  isLarge
                      ? 44.0
                      : isTablet
                      ? 38.0
                      : 30.0,
                );
                final iconSize = isLarge
                    ? 20.0
                    : isTablet
                    ? 18.0
                    : 16.0;
                // The chrome now sits on the playing surface inside the rail,
                // so it needs only a hairline of breathing room.
                final edgeInset = isLarge
                    ? 10.0
                    : isTablet
                    ? 8.0
                    : 6.0;
                // Side safe-insets are deliberately ignored: in landscape the
                // OS pads an entire short edge for a punch-hole that actually
                // sits vertically centered (and for system bars hidden by
                // immersive mode), which pushed the corner buttons visibly
                // off the edges while the stock pile and open-need pill sat
                // flush. The top corners are clear on side-cutout devices, so
                // the chrome matches the rest of the table: cosmetic inset
                // only.
                // One slim lounge capsule in the top-end corner holds every
                // table control (design contract 8, HUD): it takes a single
                // corner instead of two and reads as part of the table rather
                // than loose app buttons. Each segment keeps its own tooltip,
                // key and accessible name.
                final segments = <Widget>[
                  if (_mode.isPractice)
                    _TableChromeButton(
                      key: const ValueKey('practice-exit'),
                      tooltip: strings.practiceBackToList,
                      icon: Icons.close_rounded,
                      diameter: buttonSize,
                      iconSize: iconSize,
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  else
                    _TableChromeButton(
                      tooltip: strings.scores,
                      icon: Icons.leaderboard_rounded,
                      diameter: buttonSize,
                      iconSize: iconSize,
                      onPressed: () => setState(() => _scoreOpen = true),
                    ),
                  if (!_mode.isPractice && _canShowFastForwardRound())
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
                  // In-app Back out of a sandbox. One of the four exit routes
                  // B46 keeps on a single policy; it asks the host, which
                  // confirms only after divergence.
                  if (_mode.isBranch)
                    _TableChromeButton(
                      key: const ValueKey('branch-exit'),
                      tooltip: strings.branchExitSandbox,
                      semanticsLabel: strings.branchExitSandbox,
                      icon: Icons.close_rounded,
                      diameter: buttonSize,
                      iconSize: iconSize,
                      onPressed: _requestSandboxExit,
                    ),
                  // Guided practice has no match to pause (its own close
                  // button exits to the hub), so pause is hidden in a lesson.
                  if (!_mode.isPractice)
                    _TableChromeButton(
                      tooltip: strings.pauseTable,
                      icon: Icons.pause_rounded,
                      diameter: buttonSize,
                      iconSize: iconSize,
                      onPressed: () => setState(() => _pauseOpen = true),
                    ),
                ];
                final capsuleWidth = segments.length * buttonSize + 8;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // End-side corner; the coach card docks on the start side,
                    // so in a right-to-left table the two swap together and
                    // never overlap.
                    PositionedDirectional(
                      top: safe.top + edgeInset,
                      end: edgeInset,
                      child: _TableHudCapsule(children: segments),
                    ),
                    if (_cues.feedback != null)
                      PositionedDirectional(
                        top: safe.top + edgeInset,
                        start: edgeInset + 70,
                        end: edgeInset + capsuleWidth + 14,
                        child: Align(
                          alignment: AlignmentDirectional.topStart,
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
                child: _CardFlightOverlay(flight: flight, theme: theme),
              ),
            for (final meld in _meldFlight.activeFlights)
              Positioned.fill(
                key: ValueKey('meld-flight-${meld.serial}'),
                child: MeldFlightOverlay(flight: meld, theme: theme),
              ),
            if (_fiftyStrikeVisible)
              Positioned.fill(
                key: ValueKey('fifty-strike-$_fiftyStrikeSerial'),
                child: FiftyStrike(
                  onDone: () {
                    if (mounted) setState(() => _fiftyStrikeVisible = false);
                  },
                ),
              ),
          ],
        ),
      ),
    );

    return PopScope(
      // Practice rides a pushed route under the hub; the system back simply
      // pops to it. A real match owns the root stack and exits to home. A
      // sandbox intercepts instead, so Android system Back and browser Back
      // reach the same exit policy as pause-leave and the in-app control
      // rather than dropping the player out of an undiscarded experiment.
      canPop: _mode.isPractice,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_mode.isBranch) {
          _requestSandboxExit();
          return;
        }
        // On web the browser Back button lands here mid-match; confirm before
        // leaving so an accidental Back doesn't yank the player off the table
        // (the match is saved, so this is courtesy, not a data guard). Native
        // keeps its existing direct return-to-menu behavior.
        if (kIsWeb) {
          unawaited(_confirmLeaveMatch());
        } else {
          _returnToMainMenu();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Web desktop scales the whole table up to fill the window; native
            // keeps its validated per-device layout. Full-screen modal overlays
            // (score/pause/etc.) stay outside this and render at true size.
            // Positioned.fill so the scaler gets tight full-screen constraints
            // (a non-positioned Stack child is loose, which would let the
            // FittedBox collapse to the design canvas size in the corner).
            Positioned.fill(
              child: ImpactShake(
                serial: _fiftyStrikeSerial,
                child: _ZoomToFillTable(child: body),
              ),
            ),
            _AnimatedOverlaySlot(
              visible: _scoreOpen,
              overlayKey: 'score-overlay',
              duration: _scaledDelay(LoungeTokens.motionQuick),
              child: ScoreOverlay(
                transcript: () => _recorder?.transcript,
                eliminationScore: _controller.rules.eliminationScore,
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
              duration: _scaledDelay(LoungeTokens.motionQuick),
              // A sandbox gets its own pause panel rather than the live one
              // with rows switched off. The live panel's every setting row is
              // an `onPreferencesChanged` call, and a sandbox must not be able
              // to change a stored preference at all — so the surface that
              // could is simply not built, instead of built and guarded.
              child: _mode.isBranch
                  ? _BranchPauseOverlay(
                      onResume: () => setState(() => _pauseOpen = false),
                      onRestart: () {
                        setState(() => _pauseOpen = false);
                        widget.onSandboxRestart?.call();
                      },
                      onLeave: () {
                        setState(() => _pauseOpen = false);
                        _requestSandboxExit();
                      },
                      coachEnabled: widget.sandboxCoachEnabled,
                      onCoachChanged: widget.session.branchCoachEligible
                          ? widget.onSandboxCoachToggled
                          : null,
                    )
                  : PauseOverlay(
                      scores: _controller.scores,
                      eliminationScore: _controller.rules.eliminationScore,
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
                      onHighContrastCardsChanged: (v) =>
                          widget.onPreferencesChanged(
                            widget.preferences.copyWith(highContrastCards: v),
                          ),
                      showCoachingTips: strictness.showsProactiveHints,
                      coachingTipsEnabled:
                          widget.preferences.coachingTipsEnabled,
                      onCoachingTipsChanged: (v) => widget.onPreferencesChanged(
                        widget.preferences.copyWith(coachingTipsEnabled: v),
                      ),
                      onResume: () => setState(() => _pauseOpen = false),
                      onReportTableIssue: () {
                        setState(() => _pauseOpen = false);
                        unawaited(_exportActiveMatchReport());
                      },
                      onLeave: _mode.isPractice
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
            if (_expandedStudySeat != null &&
                _mode.capabilities.revealsAllHands)
              _StudyHandOverlay(
                seat: _expandedStudySeat!,
                cards: _revealedHands()[_expandedStudySeat!] ?? const [],
                theme: theme,
                onClose: () => setState(() => _expandedStudySeat = null),
              ),
            _AnimatedOverlaySlot(
              visible: _practiceComplete,
              overlayKey: 'practice-completion-overlay-slot',
              duration: _scaledDelay(LoungeTokens.motionStandard),
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
              duration: _scaledDelay(LoungeTokens.motionStandard),
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
              duration: _scaledDelay(LoungeTokens.motionStandard),
              child: _roundResultPresentation == null
                  ? const SizedBox.shrink()
                  : _RoundResultOverlay(
                      eliminationScore: _controller.rules.eliminationScore,
                      presentation: _roundResultPresentation!,
                      onContinueNow:
                          _roundResultPresentation!.nextSnapshot == null
                          ? null
                          : () => _advanceToNextRound(
                              _roundResultPresentation!.nextSnapshot!,
                            ),
                      // A sandbox never offers a route to the main menu: its
                      // completion overlay owns both of its exits.
                      onReturnToMenu:
                          _mode.isBranch ||
                              _roundResultPresentation!.progress.matchWinner ==
                                  null
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
                  // A finished sandbox offers two things and no others. The
                  // live overlay's rematch would deal a fresh real match and
                  // its export would hand out a report for a game that never
                  // happened, so the sandbox does not build that surface at
                  // all rather than building it with two buttons disabled.
                  : _mode.isBranch
                  ? _BranchCompletionOverlay(
                      progress: _matchOverPresentation!.progress,
                      roundsPlayed: _controller.roundNumber,
                      highContrast: widget.preferences.highContrastCards,
                      onReturnToReplay: _requestSandboxExit,
                      onRestart: () => widget.onSandboxRestart?.call(),
                    )
                  : MatchOverOverlay(
                      result: _matchOverPresentation!.result,
                      progress: _matchOverPresentation!.progress,
                      roundsPlayed: _controller.roundNumber,
                      eliminatedRound: Map<PlayerSeat, int>.unmodifiable(
                        _matchEliminatedRoundBySeat,
                      ),
                      highContrast: widget.preferences.highContrastCards,
                      onRematch: _restartMatchSameSetup,
                      archiveSaveFailed: _archiveSaveFailed,
                      onRetryArchive: _retryingArchive ? null : _retryArchive,
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
      _resetBoardPresentation();
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
    if (_mode.isPractice) return;
    final newJokers = _consumeJokerPlacements();
    if (newJokers.isEmpty) return;
    if (needsSetState && !mounted) return;
    _cues.enqueueJokerCues(newJokers);
  }

  TableFeedbackMessage _jokerCueMessage(
    ({PlayerSeat seat, CardIdentity identity}) cue,
  ) {
    final strings = context.strings;
    final text = cue.seat == PlayerSeat.south
        ? strings.youDeclaredJoker(cue.identity)
        : strings.jokerDeclaredBySeat(cue.seat, cue.identity);
    return TableFeedbackMessage(text: text, isError: false);
  }

  void _onJokerCueStart(({PlayerSeat seat, CardIdentity identity}) cue) {
    if (!mounted) return;
    final message = _jokerCueMessage(cue);
    unawaited(_audio.play(TableSoundEvent.jokerDeclared));
    // The choreographer pumps this for both the first cue (synchronously
    // from enqueueAll) and every subsequent cue (synchronously from the
    // dwell timer); calling setFeedbackUnmanaged keeps both paths consistent
    // and notifies listeners exactly once per pump.
    _cues.setFeedbackUnmanaged(message);
  }

  void _onJokerCueEnd(({PlayerSeat seat, CardIdentity identity}) cue) {
    if (!mounted) return;
    // Withdraw this cue's message only if it still owns the feedback line;
    // the next cue's start callback (if any) fires immediately after this
    // and will publish its own message via setFeedbackUnmanaged.
    _cues.withdrawFeedbackIf(_jokerCueMessage(cue));
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
    _capturePlacedJokersForAction(actionId);
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
    _notifySandboxAction(
      seat: PlayerSeat.south,
      isHuman: true,
      actionId: actionId,
      succeeded: result.isSuccess,
    );
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
    // A Fifty claim, by any seat, is the table's loudest moment.
    if (event == TableSoundEvent.fiftyClaim) _triggerFiftyStrike();
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
        onActionApplied: (decision, applyResult) => _notifySandboxAction(
          seat: decision.seat,
          isHuman: false,
          actionId: decision.actionId,
          succeeded: applyResult.isSuccess,
          legalActionIds: decision.legalActionIds,
        ),
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
    if (!_mode.capabilities.runsCpuTurns) {
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
      // Divergence is reported from inside the run, at each successful apply,
      // rather than from here. Waiting for the loop to return would leave a
      // window — one dwell plus the next CPU decision — in which the board has
      // already left its historical line while the sandbox still believes it
      // has not, and leaving through the pause overlay in that window would
      // discard real work with no confirmation.
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
      final shouldAutoRestart =
          hitCpuSafetyLimit &&
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

  /// Advances the match, then applies whatever durable effect that advance
  /// implies — if this surface has any.
  ///
  /// The two used to be one method, which is why "does this table cross
  /// rounds?" and "does this table write to storage?" were the same question.
  /// A branch sandbox needs the first without the second: it deals the next
  /// round, eliminates seats and reaches a winner exactly as live play does,
  /// and reaches no repository because it holds none.
  Future<bool> _persistAndMaybeFinish() async {
    final persistencePlan = _advanceProgression();
    // Practice drives the table from a lesson script and has its own
    // completion overlay, so the round-result / next-round pipeline would
    // fight it. Replay review advances nothing by itself.
    if (persistencePlan == null) {
      return true;
    }
    final totalWatch = Stopwatch()..start();
    final persistencePath = persistencePlan.logPath;
    final persistenceSucceeded = await _applyDurableEffect(persistencePlan);
    if (mounted &&
        persistencePlan.action ==
            ClassicHareegTablePersistenceAction.archiveCompletedMatch) {
      setState(() => _archiveSaveFailed = !persistenceSucceeded);
    }
    totalWatch.stop();
    _debugTableLog(
      'persist end success=$persistenceSucceeded path=$persistencePath '
      'elapsed=${totalWatch.elapsedMilliseconds}ms roundOver=${_controller.isRoundOver}',
    );
    if (!mounted) return persistenceSucceeded;
    final resultPresentation = persistencePlan.roundResultPresentation;
    if (resultPresentation != null &&
        (persistenceSucceeded ||
            persistencePlan.action ==
                ClassicHareegTablePersistenceAction.archiveCompletedMatch)) {
      _debugTableLog('round result overlay requested');
      _showRoundResultOverlay(resultPresentation);
    }
    return persistenceSucceeded;
  }

  /// In-memory match progression: round result, next-round snapshot and the
  /// presentation the overlay needs.
  ///
  /// Touches no storage. Returns null on a surface that does not run match
  /// progression at all, per [TableModeCapabilities.runsMatchProgression].
  ClassicHareegTablePersistencePlan? _advanceProgression() {
    if (!_mode.capabilities.runsMatchProgression) {
      return null;
    }
    final isRoundOver = _controller.isRoundOver;
    // Once the human is eliminated the match is over for them: don't deal a
    // CPU-only next round (which would also persist as a resumable spectator
    // match). A null next-round snapshot makes the persistence plan abandon the
    // match and the round-advance plan open match-over.
    final shouldDealNextRound = isRoundOver && !_controller.isHumanEliminated;
    _debugTableLog(
      'persist start roundOver=$isRoundOver '
      'current=${_controller.currentSeat.name} phase=${_controller.turnPhase} '
      'stock=${_controller.stockCount} discard=${_controller.discardPile.length} '
      'counts=${_debugSeatCounts(_controller)}',
    );
    return ClassicHareegTablePersistencePlanner.plan(
      isRoundOver: isRoundOver,
      activeSnapshot: isRoundOver ? null : _controller.toPositionSnapshot(),
      nextRoundSnapshot: shouldDealNextRound
          ? _controller.nextRoundSnapshot()
          : null,
      roundResult: _controller.roundResult,
      scoreView: _controller.scoreView,
    );
  }

  /// Applies [plan]'s durable effect, if this surface has durable storage.
  ///
  /// Exhaustive over the sealed persistence variants with no `default`, so a
  /// third variant added later is a compile error rather than a silent write.
  /// The ephemeral arm has **no repository in scope at all** — the write
  /// methods are not expressible there, which is what makes a sandbox write
  /// impossible rather than merely skipped.
  Future<bool> _applyDurableEffect(
    ClassicHareegTablePersistencePlan plan,
  ) async {
    switch (widget.session.persistence) {
      case EphemeralTablePersistence():
        return true;
      case DurableTablePersistence(
        :final matchRepository,
        :final historyRepository,
      ):
        return _writeDurableEffect(plan, matchRepository, historyRepository);
    }
  }

  Future<bool> _writeDurableEffect(
    ClassicHareegTablePersistencePlan plan,
    MatchRepository matches,
    MatchHistoryRepository history,
  ) async {
    final persistencePath = plan.logPath;
    try {
      switch (plan.action) {
        case ClassicHareegTablePersistenceAction.saveActiveMatch:
        case ClassicHareegTablePersistenceAction.saveNextRound:
          final snapshot = plan.snapshotToSave;
          if (snapshot == null) {
            throw StateError('Persistence plan is missing a snapshot.');
          }
          await matches.saveActiveMatch(
            await _checkpointFor(snapshot, history),
          );
          _recorder?.recordPersistence(
            type: 'saved',
            roundNumber: _controller.roundNumber,
            // Read off the plan, not the controller: the planner branches on
            // exactly this, so the diagnostic cannot drift from the decision
            // it is describing.
            data: {
              'roundOver':
                  plan.scenario !=
                  ClassicHareegTablePersistenceScenario.activeRound,
            },
          );
        case ClassicHareegTablePersistenceAction.abandonActiveMatch:
          await matches.abandonActiveMatch();
        case ClassicHareegTablePersistenceAction.archiveCompletedMatch:
          await _archiveCompletedMatch(plan, matches, history);
      }
    } catch (error, stackTrace) {
      _debugTableLog('persist failed path=$persistencePath error=$error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.couldNotSaveTable)),
        );
      }
      return false;
    }
    return true;
  }

  void _showRoundResultOverlay(
    ClassicHareegRoundResultPresentation presentation,
  ) {
    if (_roundResultPresentation != null) {
      return;
    }
    _rememberEliminatedRoundsFromController();
    if (presentation.result.type == RoundOutcomeType.fiftyFinish) {
      _triggerFiftyStrike();
    }
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

  /// Records the completed match to history.
  ///
  /// The terminal checkpoint is saved **before** publication starts, so a kill
  /// between here and the summary write leaves a record the next launch can
  /// finish rather than a match that silently never happened.
  Future<void> _archiveCompletedMatch(
    ClassicHareegTablePersistencePlan plan,
    MatchRepository matches,
    MatchHistoryRepository history,
  ) async {
    final progress = plan.roundResultPresentation?.progress;
    final winner = progress?.matchWinner;
    if (winner == null) {
      // A malformed plan must not delete the only recovery source or report
      // a successful durable effect. The caller surfaces this as a failure.
      throw StateError(
        'Cannot archive a match without its winner presentation.',
      );
    }

    _rememberEliminatedRoundsFromController();

    final facts =
        _checkpoint?.terminalFacts ??
        MatchTerminalFacts(
          completedAt: DateTime.now(),
          winner: winner,
          finalScores: progress!.scores,
          roundCount: _controller.roundNumber,
          eliminationRounds: Map<PlayerSeat, int>.of(
            _matchEliminatedRoundBySeat,
          ),
          // Only migrated/ineligible matches can lack pre-resume history. Missing
          // rounds are recorded as unknown, not invented from the current round.
          unknownEliminationSeats: {
            if (_checkpoint?.replayIneligible == true)
              for (final seat in PlayerSeat.values)
                if (seat != winner &&
                    !progress.activeSeats.contains(seat) &&
                    !_matchEliminatedRoundBySeat.containsKey(seat))
                  seat,
          },
          seats: PlayerSeat.values,
        );

    final terminal = _checkpoint?.isTerminal == true
        ? _checkpoint!
        : (await _checkpointFor(
            _controller.toSnapshot(),
            history,
          )).terminalize(facts);
    _checkpoint = terminal;

    await matches.saveActiveMatch(terminal);
    final outcome = await history.archiveCompletedMatch(terminal);

    _recorder?.recordPersistence(
      type: 'archived',
      roundNumber: _controller.roundNumber,
      data: {'outcome': outcome.runtimeType.toString()},
    );

    if (outcome is MatchArchivePublishFailed) {
      // The pending record survives, so the next launch retries. Surfacing it
      // as a save failure keeps the existing "couldn't save" path honest.
      throw StateError('Archive failed: ${outcome.failure}');
    }
  }

  /// Builds the durable checkpoint for [snapshot].
  ///
  /// The recorder state and the match-wide elimination map travel with the
  /// snapshot because neither can be reconstructed after a restart: the
  /// recorder used to be recreated on resume, losing every earlier action, and
  /// the controller only ever knows about eliminations from its own round.
  Future<MatchCheckpoint> _checkpointFor(
    ClassicHareegMatchSnapshot snapshot,
    MatchHistoryRepository history,
  ) async {
    _rememberEliminatedRoundsFromController();
    final matchId = await _ensureMatchId(history);
    final existing = _checkpoint;
    final base =
        existing ?? MatchCheckpoint(matchId: matchId, snapshot: snapshot);
    final updated = base
        .withProgress(
          snapshot: snapshot,
          recorderState: _recorder?.toState(),
          eliminationRounds: Map<PlayerSeat, int>.of(
            _matchEliminatedRoundBySeat,
          ),
        )
        .withCoachEnabled(_coachWasEnabled);
    _checkpoint = updated;
    return updated;
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
    _stopCuesAndDeal();
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
    if (_archiveSaveFailed || _retryingArchive) return;
    // Settings may have been retuned mid-match via the pause overlay; mirror
    // what just played, exactly like the old route-based rematch did.
    final setup = _controller.setup;
    _stopCuesAndDeal();
    _matchEliminatedRoundBySeat.clear();

    // A rematch is a *new* match, so every match-lifetime fact has to go with
    // the old one. Carrying the id and checkpoint over would save the rematch
    // under the finished match's identity — and because the old checkpoint is
    // terminal and `withProgress` preserves its terminal facts, the rematch
    // would be stored as an already-completed match: unresumable, and its own
    // completion would resolve as "already published" instead of producing a
    // second history entry.
    _matchId = null;
    _resumedMatchId = null;
    _checkpoint = null;
    _coachWasEnabled = false;

    final recorder = _mode.isPractice ? null : MatchRecorder();
    _recorder = recorder;
    setState(() {
      _controller = ClassicHareegGameController.fromRound(
        ClassicHareegRound.deal(setup: setup),
        recorder: recorder,
        now: widget.clock,
      );
      // Fresh banner history + turn tracking: the rematch restarts at round
      // 1, so the old flow's per-round seen-keys would suppress the new
      // match's stage banners.
      _coachInsightFlow = CoachInsightFlow();
      _coachTurnSeat = null;
      _coachTurnCounter = 0;
      _resetBoardPresentation();
      _dealChoreography = _buildDealChoreography();
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

  Future<void> _retryArchive() async {
    if (_retryingArchive) return;
    final plan = _advanceProgression();
    if (plan == null ||
        plan.action !=
            ClassicHareegTablePersistenceAction.archiveCompletedMatch) {
      return;
    }
    setState(() => _retryingArchive = true);
    final saved = await _applyDurableEffect(plan);
    if (!mounted) return;
    setState(() {
      _archiveSaveFailed = !saved;
      _retryingArchive = false;
    });
  }

  void _advanceToNextRound(ClassicHareegMatchSnapshot snapshot) {
    _rememberEliminatedRoundsFromController();
    _stopCuesAndDeal();
    setState(() {
      _controller = ClassicHareegGameController.fromSnapshot(
        snapshot,
        recorder: _recorder,
        now: widget.clock,
      );
      _resetBoardPresentation();
      _dealChoreography = _buildDealChoreography();
    });
    _ensureFiftyTicker();
    _scheduleTurnFlow();
  }

  /// Drains every cue timer and the fifty ticker and drops any opening deal,
  /// so no stale dwell can fire against the next board.
  void _stopCuesAndDeal() {
    _cues.resetAll();
    _cues.stopFiftyTicker();
    _dealChoreography?.dispose();
    _dealChoreography = null;
  }

  /// Resets the per-board presentation state after [_controller] has been
  /// swapped for a fresh board. Call inside `setState`, after the swap.
  void _resetBoardPresentation() {
    // The coach memo is tied to the previous controller instance; drop it so
    // the new board computes fresh insights instead of risking a stale cache
    // hit on a matching situation signature.
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
