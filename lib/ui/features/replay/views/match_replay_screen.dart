import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../data/persistence/match_history_repository.dart';
import '../../../../data/persistence/preferences_repository.dart';
import '../../../../domain/classic_hareeg/history/match_history_outcomes.dart';
import '../../../../domain/classic_hareeg/history/match_history_summary.dart';
import '../../../../domain/classic_hareeg/replay/match_replay_timeline.dart';
import '../../../../domain/classic_hareeg/replay/replay_branch_seed.dart';
import '../../../../domain/classic_hareeg/replay/replay_review_state.dart';
import '../../../../domain/classic_hareeg/reporting/match_action_transcript.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/panels/lounge_medallion.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../../game_table/table_mode.dart';
import '../../game_table/widgets/table_background.dart';
import '../replay_viewer_view_state.dart';
import '../review_insight_presenter.dart';
import '../widgets/branch_entry_sheet.dart';
import 'branch_sandbox_host.dart';
import 'replay_review_body.dart';

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

  /// The mode this surface runs as. Fixed, and read rather than assumed.
  static const mode = TableMode.replayReview;

  @override
  State<MatchReplayScreen> createState() => _MatchReplayScreenState();
}

class _MatchReplayScreenState extends State<MatchReplayScreen> {
  ReplayViewerViewState _state = const ReplayViewerLoading();
  IncrementalTimelineBuild? _build;
  late AnalysisCoachSettings _settings = widget.analysisCoach;

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
  /// Lives here rather than in the review body, so the capsule's Branch
  /// segment is one route into the sandbox whichever arrangement it sits in.
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    // A rebuilt match is the table itself, edge to edge, with its exit in the
    // HUD capsule like the live table's. Loading and failure states keep the
    // header, or there would be no way out of them.
    if (_state case ReplayViewerReady(:final review)) {
      return Scaffold(
        backgroundColor: LoungeTokens.coffeeCharcoal,
        body: ReplayReviewBody(
          review: review,
          settings: _settings,
          isOverridden: _isOverridden,
          onSettingsChanged: (value) => setState(() => _settings = value),
          onSeek: _seek,
          branchLabel: _branchLabel(strings),
          onBranch: _onBranch,
        ),
      );
    }

    return Scaffold(
      backgroundColor: LoungeTokens.coffeeCharcoal,
      appBar: AppBar(
        backgroundColor: LoungeTokens.coffeeCharcoal,
        // Lacquered like the table's HUD capsule, with a brass hairline where
        // the bar meets the rail.
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(
                  LoungeTokens.coffeeCharcoal,
                  LoungeTokens.sandLine,
                  0.08,
                )!,
                LoungeTokens.coffeeCharcoal,
              ],
            ),
          ),
        ),
        shape: Border(
          bottom: BorderSide(
            color: LoungeTokens.sandLine.withValues(alpha: 0.32),
          ),
        ),
        titleSpacing: LoungeTokens.space4,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LoungeMedallion(
              icon: Icons.history_rounded,
              size: 32,
              tone: LoungeMedallionTone.lit,
            ),
            const SizedBox(width: LoungeTokens.space3),
            Flexible(
              child: Text(
                strings.replayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: TableBackground(child: SafeArea(child: _body(context))),
    );
  }

  Widget _body(BuildContext context) {
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
      ReplayViewerFailed(:final isRetryable) => _MessageBody(
        title: context.strings.replayUnavailableTitle,
        body: isRetryable
            ? context.strings.replayLoadFailedRetryable
            : context.strings.replayLoadFailedCorrupt,
        // Retrying a corrupt read just reads the same bytes again, so only a
        // retryable failure gets the affordance.
        onRetry: isRetryable ? _load : null,
        retryLabel: context.strings.replayRetry,
      ),
      // Rendered by [build] directly.
      ReplayViewerReady() => const SizedBox.shrink(),
    };
  }

  /// The branch control's label: the offer, or why this frame refuses it.
  ///
  /// The refusal is stated in the label rather than left as a silently dead
  /// button: a decided match has nothing left to play out, and that is worth
  /// saying out loud.
  String _branchLabel(AppStrings strings) => _branchRefusal == null
      ? strings.branchStart
      : strings.branchUnavailableComplete;

  /// Starts a branch, or null when the current frame refuses one.
  VoidCallback? get _onBranch =>
      _branchRefusal == null ? () => unawaited(_startBranch()) : null;
}

/// The lit lounge card the loading and message states sit on, centred on the
/// felt: the same panel the practice overlays and the About card use.
class _StateCard extends StatelessWidget {
  const _StateCard({required this.children, this.glow});

  final List<Widget> children;

  /// Tint of the panel's light, gold by default.
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(LoungeTokens.space6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DecoratedBox(
            decoration: loungeLitPanel(
              glow: glow ?? LoungeTokens.goldAccent,
              strength: 0.12,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LoungeTokens.space5,
                vertical: LoungeTokens.space6,
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: children),
            ),
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
    return _StateCard(
      children: [
        // The medallion with a thin gold ring turning around it: the match
        // being dealt back out, rather than a bare stock spinner.
        const SizedBox.square(
          dimension: 64,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.square(
                dimension: 64,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: LoungeTokens.goldAccent,
                ),
              ),
              LoungeMedallion(
                icon: Icons.history_rounded,
                size: 48,
                tone: LoungeMedallionTone.lit,
              ),
            ],
          ),
        ),
        const SizedBox(height: LoungeTokens.space4),
        Text(
          context.strings.replayLoading,
          style: LoungeTokens.heading,
          textAlign: TextAlign.center,
        ),
        if (frames > 0) ...[
          const SizedBox(height: LoungeTokens.space2),
          Text(
            context.strings.replayLoadingFrames(frames),
            style: LoungeTokens.bodyMuted.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({
    required this.title,
    required this.body,
    this.onRetry,
    this.retryLabel,
  });

  final String title;
  final String body;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    return _StateCard(
      glow: LoungeTokens.deepRed,
      children: [
        const LoungeMedallion(
          icon: Icons.history_toggle_off_rounded,
          size: 56,
          tone: LoungeMedallionTone.alert,
        ),
        const SizedBox(height: LoungeTokens.space4),
        Text(
          title,
          style: LoungeTokens.display.copyWith(fontSize: 22),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: LoungeTokens.space2),
        Text(body, style: LoungeTokens.bodyMuted, textAlign: TextAlign.center),
        if (onRetry != null) ...[
          const SizedBox(height: LoungeTokens.space5),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: Text(retryLabel!),
          ),
        ],
      ],
    );
  }
}
