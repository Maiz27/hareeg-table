import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../cpu/classic_hareeg/coaching/replay_analysis_coach.dart';
import '../../../../cpu/classic_hareeg/coaching/review_insight.dart';
import '../../../../data/persistence/match_history_repository.dart';
import '../../../../data/persistence/preferences_repository.dart';
import '../../../../domain/classic_hareeg/history/match_history_outcomes.dart';
import '../../../../domain/classic_hareeg/history/match_history_summary.dart';
import '../../../../domain/classic_hareeg/replay/match_replay_timeline.dart';
import '../../../../domain/classic_hareeg/replay/replay_branch_seed.dart';
import '../../../../domain/classic_hareeg/replay/replay_review_state.dart';
import '../../../../domain/classic_hareeg/replay/review_observation.dart';
import '../../../../domain/classic_hareeg/reporting/match_action_transcript.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/scopes/app_scopes.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../../game_table/table_mode.dart';
import '../../game_table/widgets/table_background.dart';
import '../replay_hud_layout.dart';
import '../replay_viewer_view_state.dart';
import '../review_insight_presenter.dart';
import '../widgets/analysis_coach_panel.dart';
import '../widgets/branch_entry_sheet.dart';
import 'branch_sandbox_host.dart';
import '../widgets/replay_hud_clusters.dart';
import '../widgets/replay_scrub_bar.dart';
import '../widgets/replay_review_controls.dart';
import '../widgets/review_table_playfield.dart';

/// Steps through a finished match on the real table.
///
/// Review is passive by construction. This screen is handed a history
/// repository and the player's analysis settings, and nothing that could write
/// match state — no match repository, no recorder, no archive path — so there
/// is no write to guard against rather than a guard at each write.
class MatchReplayScreen extends StatefulWidget {
  /// Creates the replay viewer.
  const MatchReplayScreen({
    required this.summary,
    required this.historyRepository,
    required this.analysisCoach,
    super.key,
    this.preferences,
    this.clock,
  });

  /// The match being reviewed.
  final MatchHistorySummary summary;

  /// Completed-match storage.
  final MatchHistoryRepository historyRepository;

  /// The player's saved analysis-coach default.
  ///
  /// Changes made while reviewing apply to this session only; this screen never
  /// writes preferences back.
  final AnalysisCoachSettings analysisCoach;

  /// Presentation preferences a branch sandbox reads, or null for the
  /// defaults.
  ///
  /// Read only. Review itself has no settings surface, and a sandbox has no
  /// route back to a preferences store, so nothing downstream of this writes.
  final GamePreferences? preferences;

  /// Clock a branch sandbox runs on, or null for the wall clock.
  final DateTime Function()? clock;

  /// The mode this surface runs as. Fixed, and read rather than assumed.
  static const mode = TableMode.replayReview;

  @override
  State<MatchReplayScreen> createState() => _MatchReplayScreenState();
}

class _MatchReplayScreenState extends State<MatchReplayScreen> {
  ReplayViewerViewState _state = const ReplayViewerLoading();
  IncrementalTimelineBuild? _build;
  late AnalysisCoachSettings _settings = widget.analysisCoach;
  int _openAttempts = 0;

  @override
  void initState() {
    super.initState();
    AppOrientation.useLandscape();
    _load();
  }

  @override
  void dispose() {
    // A long match is still rebuilding when a player changes their mind and
    // leaves. Abandoning the drain here is what stops it finishing into a
    // disposed widget.
    _build?.cancel();
    AppOrientation.usePortrait();
    super.dispose();
  }

  bool get _isOverridden => _settings != widget.analysisCoach;

  Future<void> _load() async {
    setState(() => _state = const ReplayViewerLoading());
    _openAttempts += 1;

    final MatchReplayOpenOutcome outcome;
    try {
      outcome = await widget.historyRepository.openReplay(
        widget.summary.matchId,
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to open replay: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) {
        return;
      }
      setState(
        () => _state = ReplayViewerFailed(
          MatchHistoryFailure(
            kind: MatchHistoryFailureKind.retryable,
            matchId: widget.summary.matchId,
            message: 'Opening the replay threw.',
            cause: error,
          ),
        ),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    if (outcome is! MatchReplayOpened) {
      setState(() => _state = ReplayViewerViewState.fromOpenOutcome(outcome));
      return;
    }

    await _rebuild(outcome.record.transcript);
  }

  Future<void> _rebuild(MatchActionTranscript transcript) async {
    // Drained in bounded chunks rather than in one pass: a full match is
    // roughly seventeen hundred positions, and rebuilding them all before the
    // next frame would freeze the app for as long as it took.
    final build = IncrementalTimelineBuild(
      transcript,
      chunkSize: 24,
      timeBudget: const Duration(milliseconds: 8),
      onProgress: (frames) {
        if (mounted) {
          setState(() => _state = ReplayViewerLoading(rebuiltFrames: frames));
        }
      },
    );
    _build = build;

    final outcome = await build.run();
    // Null means the drain was abandoned because this screen went away.
    if (outcome == null || !mounted) {
      return;
    }

    switch (outcome) {
      case ReplayTimelineBuilt(:final timeline):
        setState(
          () => _state = ReplayViewerReady(ReplayReviewState.atStart(timeline)),
        );
      case ReplayTimelineFailed(:final failure):
        await _repairAndReport(failure);
    }
  }

  /// A replay that decoded but cannot be rebuilt is a dead link, and it would
  /// stay one: the repository reports success as soon as bytes decode. Telling
  /// history about it here is what makes the entry stop offering a replay it
  /// cannot deliver.
  Future<void> _repairAndReport(ReplayTimelineFailure failure) async {
    final reason = ReplayViewerViewState.reasonFor(failure.kind);

    final MatchReplayRepairOutcome repair;
    try {
      repair = await widget.historyRepository.repairUnusableReplay(
        matchId: widget.summary.matchId,
        // Diagnostic detail, stored rather than shown.
        reason: failure.message,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(
        () => _state = ReplayViewerFailed(
          MatchHistoryFailure(
            kind: MatchHistoryFailureKind.retryable,
            matchId: widget.summary.matchId,
            message: 'Repairing the replay threw.',
            cause: error,
          ),
        ),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _state = switch (repair) {
        MatchReplayRepaired() => ReplayViewerUnavailable(reason),
        // The replay is unusable either way, but saying "this entry is fixed"
        // when the fix did not land would send the player back to a list that
        // still offers the same dead link.
        MatchReplayRepairFailed(:final failure) => ReplayViewerFailed(failure),
      };
    });
  }

  void _seek(int index) {
    final state = _state;
    if (state is! ReplayViewerReady) {
      return;
    }
    setState(() => _state = ReplayViewerReady(state.review.seekTo(index)));
  }

  /// The frame a branch would start from, or null while nothing is rebuilt.
  ReplayFrame? get _branchFrame {
    final state = _state;
    return state is ReplayViewerReady ? state.review.frame : null;
  }

  /// The timeline position after the branch frame, or null at the end.
  ///
  /// A round-end frame is only playable when the recording contains the next
  /// round's deal, and that is the frame the sandbox actually starts from, so
  /// the seed needs both.
  ReplayFrame? get _branchNextFrame {
    final state = _state;
    if (state is! ReplayViewerReady) {
      return null;
    }
    final next = state.review.cursor + 1;
    return next < state.review.length
        ? state.review.timeline.frameAt(next)
        : null;
  }

  /// Why the current frame cannot be branched from, or null when it can.
  ///
  /// Asked of the domain rather than re-derived here, so the affordance and
  /// the seed builder cannot disagree about which frames are playable. A frame
  /// that does not exist yet refuses for the same reason a decided one does:
  /// there is nothing to play out.
  ReplayBranchRefusal? get _branchRefusal {
    final frame = _branchFrame;
    return frame == null
        ? ReplayBranchRefusal.matchAlreadyComplete
        : ReplayBranchSeed.refusalFor(frame, nextFrame: _branchNextFrame);
  }

  /// Opens the visibility chooser and, on a choice, pushes the sandbox.
  ///
  /// Lives here rather than in either layout so the two entry points — the
  /// short HUD rail and the docked app bar — are one route into the sandbox
  /// rather than two that could drift.
  ///
  /// Returns to this exact frame afterwards, because the sandbox is a pushed
  /// route over an untouched review: popping it restores the cursor without
  /// this screen having to remember or restore anything.
  Future<void> _startBranch() async {
    final frame = _branchFrame;
    final nextFrame = _branchNextFrame;
    if (frame == null ||
        ReplayBranchSeed.refusalFor(frame, nextFrame: nextFrame) != null) {
      return;
    }
    final visibility = await showBranchEntrySheet(
      context,
      highContrast: widget.preferences?.highContrastCards ?? false,
    );
    if (!mounted || visibility == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BranchSandboxHost(
          frame: frame,
          nextFrame: nextFrame,
          visibility: visibility,
          coachEligible: widget.summary.coachWasEnabled,
          preferences: widget.preferences ?? GamePreferences.defaults(),
          clock: widget.clock,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final media = MediaQuery.of(context);

    // Resolved once, here, and handed to both the branch and the HUD. Nothing
    // recomputes after branching, so the collision map and the rendered rails
    // cannot disagree about where anything is.
    //
    // `padding`, not `viewPadding`: the body below is a `SafeArea`, which
    // consumes exactly `padding`. Routing on the other one would classify a
    // body the screen never builds.
    final decision = ReplayHudLayout.resolveFor(
      screen: media.size,
      safeInsets: media.padding,
    );

    // The app bar goes only when a rebuilt match is actually on screen in the
    // short layout, where Back lives in the HUD instead. Loading and failure
    // states keep it, or there would be no way out of them.
    final isShort =
        decision.mode == ReplayLayoutMode.short && _state is ReplayViewerReady;

    return Scaffold(
      backgroundColor: LoungeTokens.coffeeCharcoal,
      appBar: isShort
          ? null
          : AppBar(
              backgroundColor: LoungeTokens.coffeeCharcoal,
              title: Text(strings.replayTitle),
              actions: [
                // The docked layout's branch entry. It lives here rather than
                // in the transport strip because that strip already overflows
                // at 320 dp with six controls, and a seventh would push a
                // frozen-oracle anchor. The bar is full width at every docked
                // size, so this is the one place a tenth affordance costs no
                // measured geometry.
                if (_state is ReplayViewerReady)
                  _BranchAppBarAction(
                    // The refusal is stated in the label rather than left as a
                    // silently dead button: a decided match has nothing left
                    // to play out, and that is worth saying out loud.
                    label: _branchRefusal == null
                        ? strings.branchStart
                        : strings.branchUnavailableComplete,
                    onPressed: _branchRefusal == null
                        ? () => unawaited(_startBranch())
                        : null,
                  ),
              ],
            ),
      body: TableBackground(child: SafeArea(child: _body(context, decision))),
    );
  }

  Widget _body(BuildContext context, ReplayLayoutDecision decision) {
    return switch (_state) {
      ReplayViewerLoading(:final rebuiltFrames) => _LoadingBody(
        frames: rebuiltFrames,
      ),
      ReplayViewerUnavailable(:final reason) => _MessageBody(
        title: context.strings.replayUnavailableTitle,
        body: ReviewInsightPresenter(
          strings: context.strings,
          cards: const {},
        ).unavailableReason(reason),
      ),
      ReplayViewerFailed(:final failure, :final isRetryable) => _MessageBody(
        title: context.strings.replayUnavailableTitle,
        body: isRetryable
            ? context.strings.replayLoadFailedRetryable
            : context.strings.replayLoadFailedCorrupt,
        // Retrying a corrupt read just reads the same bytes again, so only a
        // retryable failure gets the affordance.
        onRetry: isRetryable ? _load : null,
        retryLabel: context.strings.replayRetry,
        semanticFailureKind: failure.kind.name,
      ),
      ReplayViewerReady(:final review) => _ReadyBody(
        decision: decision,
        review: review,
        settings: _settings,
        isOverridden: _isOverridden,
        onSettingsChanged: (value) => setState(() => _settings = value),
        onSeek: _seek,
        branchLabel: _branchRefusal == null
            ? context.strings.branchStart
            : context.strings.branchUnavailableComplete,
        onBranch: _branchRefusal == null
            ? () => unawaited(_startBranch())
            : null,
      ),
    };
  }

  /// Exposed for tests that need to know a retry really re-opened the record.
  @visibleForTesting
  int get openAttempts => _openAttempts;
}

/// The docked layout's branch entry, in the app bar.
///
/// Icon-only, which makes the tooltip and the semantics label load-bearing
/// rather than decorative: without them a screen reader announces an unnamed
/// button.
///
/// **The tooltip is on the wrapper, not on the `IconButton`.** Giving
/// `IconButton` a `tooltip` *and* wrapping it in a labelled `Semantics` merges
/// two names onto one node, and the browser then announces "Play on from here
/// Play on from here". Found on the real web build; the arrangement below is
/// the one `ReplayRailButton` already uses, and it yields exactly one name.
class _BranchAppBarAction extends StatelessWidget {
  const _BranchAppBarAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: MergeSemantics(
        child: Semantics(
          label: label,
          button: true,
          enabled: onPressed != null,
          // Deliberately unkeyed. Sprint 05's frozen docked oracle collects
          // every `ValueKey<String>`-bearing render box as an anchor, so a key
          // here would add a twenty-third anchor to a layout the oracle
          // freezes at twenty-two — and that file is not this sprint's to
          // rewrite. The localized semantics label is the handle, which is the
          // one a screen reader uses anyway.
          child: IconButton(
            icon: const Icon(Icons.alt_route),
            color: LoungeTokens.sandLine,
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody({required this.frames});
  final int frames;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(context.strings.replayLoading, style: LoungeTokens.bodyMuted),
          if (frames > 0)
            Text(
              context.strings.replayLoadingFrames(frames),
              style: LoungeTokens.bodyMuted,
            ),
        ],
      ),
    );
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({
    required this.title,
    required this.body,
    this.onRetry,
    this.retryLabel,
    this.semanticFailureKind,
  });

  final String title;
  final String body;
  final VoidCallback? onRetry;
  final String? retryLabel;
  final String? semanticFailureKind;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: LoungeTokens.body.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: LoungeTokens.bodyMuted,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: Text(retryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReadyBody extends StatefulWidget {
  const _ReadyBody({
    required this.decision,
    required this.review,
    required this.settings,
    required this.isOverridden,
    required this.onSettingsChanged,
    required this.onSeek,
    required this.branchLabel,
    required this.onBranch,
  });

  final ReplayLayoutDecision decision;
  final ReplayReviewState review;
  final AnalysisCoachSettings settings;
  final bool isOverridden;
  final ValueChanged<AnalysisCoachSettings> onSettingsChanged;
  final ValueChanged<int> onSeek;

  /// Localized label for the branch control — the offer, or why it is refused.
  final String branchLabel;

  /// Starts a branch from the current frame, or null when this frame refuses.
  final VoidCallback? onBranch;

  @override
  State<_ReadyBody> createState() => _ReadyBodyState();
}

class _ReadyBodyState extends State<_ReadyBody> {
  /// Sticky by design: stepping updates the card's contents in place and
  /// leaves it open. Comparing adjacent decisions is the whole review task, so
  /// collapsing after every step would undo it.
  bool _analysisExpanded = false;
  bool _scrubOpen = false;

  ReplayReviewState get review => widget.review;
  AnalysisCoachSettings get settings => widget.settings;
  bool get isOverridden => widget.isOverridden;
  ValueChanged<AnalysisCoachSettings> get onSettingsChanged =>
      widget.onSettingsChanged;
  ValueChanged<int> get onSeek => widget.onSeek;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = CardThemeScope.of(context);
    final frame = review.frame;
    final previous = review.previousFrame;
    final presenter = ReviewInsightPresenter.forFrame(
      strings: strings,
      frame: frame,
      // The pre-action position is what can still name a card that was taken
      // off the pile by this very action.
      previous: previous,
    );

    final reviewable =
        frame.kind == ReplayFrameKind.actionApplied && previous != null;

    // Only a played move has something to review: the deal and a round start
    // are positions, not decisions.
    final insights = <ReviewInsight>[];
    if (reviewable) {
      final observation = ReviewObservation.fromFrames(
        previous: previous,
        applied: frame,
      );
      insights.addAll(
        ReplayAnalysisCoach.review(
          observation: observation,
          action: ReviewedAction.fromEntry(frame.appliedEntry!),
          settings: settings,
        ),
      );
    }

    if (widget.decision.mode == ReplayLayoutMode.short) {
      return _shortLayout(
        context,
        frame: frame,
        theme: theme,
        insights: insights,
        presenter: presenter,
        reviewable: reviewable,
      );
    }

    // The table is the thing being reviewed, so it keeps the larger share and
    // the commentary is capped. Letting the panel size itself to its content
    // squeezed the table to zero height on a real device — which surfaced both
    // as an overflow stripe and as a layout exception from the playfield.
    return LayoutBuilder(
      builder: (context, constraints) {
        final analysisMaxHeight = constraints.maxHeight * 0.34;

        return Column(
          children: [
            Expanded(
              child: ReviewTablePlayfield(
                mode: MatchReplayScreen.mode,
                snapshot: frame.snapshot,
                theme: theme,
                fiftySecondsRemaining: frame.fiftySecondsRemaining,
              ),
            ),
            ReplayReviewControls(
              review: review,
              positionLabel: strings.replayPosition(
                review.roundNumber,
                review.stepNumber,
                review.length,
              ),
              frameDescription: presenter.describeFrame(frame),
              onSeek: onSeek,
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: analysisMaxHeight),
              child: SingleChildScrollView(
                child: ReviewAnalysisRegion(
                  mode: MatchReplayScreen.mode,
                  insights: insights,
                  presenter: presenter,
                  settings: settings,
                  isOverridden: isOverridden,
                  onSettingsChanged: onSettingsChanged,
                  reviewable: reviewable,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Full-bleed table with two fixed 44 dp edge rails over it.
  ///
  /// Nothing here permanently subtracts height from the table: every affordance
  /// is an overlay in the same stack, so the table keeps the whole body.
  ///
  /// The rails are anchored to **physical** edges, not directional ones, and
  /// they do not mirror. The table itself does not mirror — the playfield
  /// positions every seat with non-directional `left`/`right` — so the two
  /// columns are not interchangeable: the stock pile sits in the bottom-left
  /// corner and leaves that column two slots short of the six the transport
  /// rail needs. Mirroring would put the transport somewhere it does not fit.
  /// Logical behaviour is unaffected: next still advances the timeline.
  Widget _shortLayout(
    BuildContext context, {
    required ReplayFrame frame,
    required HareegCardTheme theme,
    required List<ReviewInsight> insights,
    required ReviewInsightPresenter presenter,
    required bool reviewable,
  }) {
    final strings = context.strings;
    final rails = widget.decision.rails;
    final positionLabel = strings.replayPosition(
      review.roundNumber,
      review.stepNumber,
      review.length,
    );

    // Every rectangle below came from the one collision map the branch was
    // taken on, so a rendered control cannot land anywhere the guard did not
    // clear. `isComplete` and a non-null scrub are guaranteed by that guard:
    // a body that cannot seat them is never classified short.
    final leading = rails.leading;
    final trailing = rails.trailing;

    return Stack(
      children: [
        Positioned.fill(
          child: ReviewTablePlayfield(
            mode: MatchReplayScreen.mode,
            snapshot: frame.snapshot,
            theme: theme,
            fiftySecondsRemaining: frame.fiftySecondsRemaining,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ReplayProgressHairline(
            progress: review.length <= 1
                ? 0
                : review.cursor / (review.length - 1),
          ),
        ),
        Positioned.fill(
          child: TapRegion(
            // One group for the whole HUD. Transport is part of the review
            // interaction, so stepping keeps the analysis card open; a tap on
            // the table is outside the group, so it dismisses *and* still
            // reaches the table. Nothing full-screen participates in hit
            // testing here: the stack's children are all positioned, so the
            // fill is inert everywhere they are not.
            groupId: replayHudTapGroup,
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Stack(
                children: [
                  _slot(
                    0,
                    leading[0],
                    ReplayRailButton(
                      icon: Icons.arrow_back,
                      label: strings.replayBack,
                      // The one glyph here that *should* mirror: leaving is
                      // route navigation, not a move along the timeline.
                      glyphDirection: ReplayGlyphDirection.locale,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  _slot(
                    1,
                    leading[1],
                    ReplayRailButton(
                      icon: Icons.first_page,
                      label: strings.replayFirst,
                      onPressed: review.canStepBack ? () => onSeek(0) : null,
                    ),
                  ),
                  _slot(
                    2,
                    leading[2],
                    ReplayRailButton(
                      icon: Icons.insights,
                      label: strings.replayCoachTitle,
                      onPressed: () => setState(
                        () => _analysisExpanded = !_analysisExpanded,
                      ),
                    ),
                  ),
                  _slot(
                    3,
                    leading[3],
                    ReplayRailButton(
                      key: const ValueKey('replay-branch-control'),
                      icon: Icons.alt_route,
                      // The refusal is stated in the label, not left as a
                      // silently dead button: a decided match has nothing to
                      // play out, and that is worth saying.
                      label: widget.branchLabel,
                      // Route navigation, not a move along the timeline.
                      glyphDirection: ReplayGlyphDirection.locale,
                      onPressed: widget.onBranch,
                    ),
                  ),
                  _slot(
                    4,
                    trailing[0],
                    ReplayRailButton(
                      icon: Icons.skip_previous,
                      label: strings.replayPreviousRound,
                      onPressed: review.canGoPreviousRound
                          ? () => onSeek(review.previousRound().cursor)
                          : null,
                    ),
                  ),
                  _slot(
                    5,
                    trailing[1],
                    ReplayRailButton(
                      icon: Icons.chevron_left,
                      label: strings.replayPrevious,
                      onPressed: review.canStepBack
                          ? () => onSeek(review.cursor - 1)
                          : null,
                    ),
                  ),
                  _slot(
                    6,
                    trailing[2],
                    ReplayRailButton(
                      icon: Icons.chevron_right,
                      label: strings.replayNext,
                      onPressed: review.canStepForward
                          ? () => onSeek(review.cursor + 1)
                          : null,
                    ),
                  ),
                  _slot(
                    7,
                    trailing[3],
                    ReplayRailButton(
                      icon: Icons.skip_next,
                      label: strings.replayNextRound,
                      onPressed: review.canGoNextRound
                          ? () => onSeek(review.nextRound().cursor)
                          : null,
                    ),
                  ),
                  _slot(
                    8,
                    trailing[4],
                    ReplayRailButton(
                      icon: Icons.last_page,
                      label: strings.replayLast,
                      onPressed: review.canStepForward
                          ? () => onSeek(review.length - 1)
                          : null,
                    ),
                  ),
                  _slot(
                    9,
                    rails.scrub!,
                    ReplayScrubTarget(
                      // The position value the withdrawn readout used to show.
                      // It is carried here rather than dropped, and it is not a
                      // second seek affordance: this is the only one.
                      label: '${strings.replaySeek} — $positionLabel',
                      onTap: () => setState(() => _scrubOpen = true),
                    ),
                  ),
                  if (rails.popover != null)
                    Positioned(
                      left: rails.popover!.left,
                      top: rails.popover!.top,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: rails.popover!.width,
                          maxHeight: rails.popover!.height,
                        ),
                        child: ReviewAnalysisCard(
                          mode: MatchReplayScreen.mode,
                          insights: insights,
                          presenter: presenter,
                          settings: settings,
                          isOverridden: isOverridden,
                          onSettingsChanged: onSettingsChanged,
                          reviewable: reviewable,
                          expanded: _analysisExpanded,
                          onDismiss: () =>
                              setState(() => _analysisExpanded = false),
                        ),
                      ),
                    ),
                  if (_scrubOpen && rails.scrubOverlay != null)
                    Positioned.fromRect(
                      // Bounded to the band the collision map cleared inside
                      // the South hand. A full-width bottom strip would cross
                      // the stock, both side meld lanes, Last and the scrub
                      // target, and the hand is the only surface this overlay
                      // is allowed to cover.
                      rect: rails.scrubOverlay!,
                      child: ReplayScrubOverlay(
                        cursor: review.cursor,
                        length: review.length,
                        onSeek: onSeek,
                        onDismiss: () => setState(() => _scrubOpen = false),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Pins one affordance to the exact rectangle the collision map cleared, and
  /// fixes its place in the traversal order.
  ///
  /// Focus order is stated here rather than inferred from tree order: leading
  /// rail top to bottom, then trailing rail top to bottom, then the scrub.
  Widget _slot(int order, Rect rect, Widget child) {
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: FocusTraversalOrder(
        order: NumericFocusOrder(order.toDouble()),
        child: child,
      ),
    );
  }
}
