import 'package:flutter/material.dart';

import '../../../../cpu/classic_hareeg/coaching/replay_analysis_coach.dart';
import '../../../../cpu/classic_hareeg/coaching/review_insight.dart';
import '../../../../data/persistence/preferences_repository.dart';
import '../../../../domain/classic_hareeg/replay/match_replay_timeline.dart';
import '../../../../domain/classic_hareeg/replay/replay_review_state.dart';
import '../../../../domain/classic_hareeg/replay/review_observation.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/scopes/app_scopes.dart';
import '../replay_hud_layout.dart';
import '../review_insight_presenter.dart';
import '../widgets/analysis_coach_panel.dart';
import '../widgets/replay_hud_clusters.dart';
import '../widgets/replay_review_controls.dart';
import '../widgets/replay_scrub_bar.dart';
import '../widgets/review_table_playfield.dart';
import 'match_replay_screen.dart';

/// A rebuilt match under review, in whichever layout the collision map chose.
///
/// Docked: table, transport strip and a capped analysis panel stacked in
/// bands. Short: a full-bleed table with two edge rails over it.
class ReplayReviewBody extends StatefulWidget {
  /// Creates the review body.
  const ReplayReviewBody({
    super.key,
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
  State<ReplayReviewBody> createState() => _ReplayReviewBodyState();
}

class _ReplayReviewBodyState extends State<ReplayReviewBody> {
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
            Expanded(child: _playfield(frame, theme)),
            ReplayReviewControls(
              review: review,
              positionLabel: _positionLabel(strings),
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
    final positionLabel = _positionLabel(strings);

    // Every rectangle below came from the one collision map the branch was
    // taken on, so a rendered control cannot land anywhere the guard did not
    // clear. `isComplete` and a non-null scrub are guaranteed by that guard:
    // a body that cannot seat them is never classified short.
    final leading = rails.leading;
    final trailing = rails.trailing;

    return Stack(
      children: [
        Positioned.fill(child: _playfield(frame, theme)),
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

  /// The passive table both layouts review on.
  Widget _playfield(ReplayFrame frame, HareegCardTheme theme) {
    return ReviewTablePlayfield(
      mode: MatchReplayScreen.mode,
      snapshot: frame.snapshot,
      theme: theme,
      fiftySecondsRemaining: frame.fiftySecondsRemaining,
    );
  }

  /// The localized "Round r · s of n" readout for the cursor.
  String _positionLabel(AppStrings strings) {
    return strings.replayPosition(
      review.roundNumber,
      review.stepNumber,
      review.length,
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
