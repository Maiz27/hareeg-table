import 'package:flutter/material.dart';

import '../../../../cpu/classic_hareeg/coaching/replay_analysis_coach.dart';
import '../../../../cpu/classic_hareeg/coaching/review_insight.dart';
import '../../../../data/persistence/preferences_repository.dart';
import '../../../../domain/classic_hareeg/replay/match_replay_timeline.dart';
import '../../../../domain/classic_hareeg/replay/replay_review_state.dart';
import '../../../../domain/classic_hareeg/replay/review_observation.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/panels/lounge_medallion.dart';
import '../../../core/scopes/app_scopes.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../../game_table/widgets/table_background.dart';
import '../../game_table/widgets/table_hud_capsule.dart';
import '../replay_card_layout.dart';
import '../review_insight_presenter.dart';
import '../widgets/analysis_coach_panel.dart';
import '../widgets/replay_card.dart';
import '../widgets/review_table_playfield.dart';
import 'match_replay_screen.dart';

/// A rebuilt match under review: the live table, its HUD capsule and the
/// replay card (design contract 7.6).
///
/// Landscape is the live table exactly — inset inside the rail, the stock at
/// the centre, seat plates with scores — with the capsule in the top-end
/// corner and the card docked in the top-start corner where the live coach
/// card docks. A portrait body puts the same table on top and the same card
/// docked full width under it.
class ReplayReviewBody extends StatefulWidget {
  /// Creates the review body.
  const ReplayReviewBody({
    super.key,
    required this.review,
    required this.settings,
    required this.isOverridden,
    required this.onSettingsChanged,
    required this.onSeek,
    required this.branchLabel,
    required this.onBranch,
  });

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
  /// Sticky by design: stepping updates the section's contents in place and
  /// leaves it open. Comparing adjacent decisions is the whole review task, so
  /// collapsing after every step would undo it.
  bool _analysisOpen = false;

  ReplayReviewState get review => widget.review;

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
          settings: widget.settings,
        ),
      );
    }

    Widget card(ReplayCardArrangement arrangement, double maxHeight) {
      return ReplayCard(
        key: const ValueKey('replay-card'),
        arrangement: arrangement,
        maxHeight: maxHeight,
        review: review,
        positionLabel: strings.replayPosition(
          review.roundNumber,
          review.stepNumber,
          review.length,
        ),
        narration: presenter.describeFrame(frame),
        onSeek: widget.onSeek,
        analysisOpen: _analysisOpen,
        analysis: ReviewAnalysisRegion(
          mode: MatchReplayScreen.mode,
          insights: insights,
          presenter: presenter,
          settings: widget.settings,
          isOverridden: widget.isOverridden,
          onSettingsChanged: widget.onSettingsChanged,
          reviewable: reviewable,
          inset: true,
        ),
      );
    }

    final playfield = ReviewTablePlayfield(
      mode: MatchReplayScreen.mode,
      snapshot: frame.snapshot,
      theme: theme,
      fiftySecondsRemaining: frame.fiftySecondsRemaining,
    );

    return LayoutBuilder(
      builder: (context, screen) {
        if (screen.maxHeight > screen.maxWidth) {
          return _portrait(context, playfield: playfield, card: card);
        }
        return TableBackground(
          // The live table's own surface: everything lays out on the playing
          // surface inside the rail, in one coordinate space.
          insetChild: true,
          child: LayoutBuilder(
            builder: (context, table) {
              final safe = MediaQuery.paddingOf(context);
              final placement = ReplayCardPlacement.resolve(
                table: table.biggest,
                direction: strings.textDirection,
                textScaler: MediaQuery.textScalerOf(context),
                safeTop: safe.top,
              );
              final metrics = TableHudMetrics.forViewport(
                table.maxWidth,
                floor: ReplayCardMetrics.tapTarget,
              );
              return Stack(
                children: [
                  Positioned.fill(child: playfield),
                  Positioned(
                    left: placement.left,
                    top: placement.top,
                    width: placement.width,
                    child: card(
                      placement.arrangement,
                      _analysisOpen
                          ? placement.expandedMaxHeight
                          : placement.restingMaxHeight,
                    ),
                  ),
                  // End-side corner, exactly where the live table's capsule
                  // sits; the card docks on the start side, so in a
                  // right-to-left table the two swap together.
                  PositionedDirectional(
                    top: safe.top + metrics.edgeInset,
                    end: metrics.edgeInset,
                    child: _capsule(context, metrics),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// The table on top, the card docked full width under it.
  ///
  /// The card takes its natural height, up to half the body, and the table
  /// takes the rest. The capsule rides in a slim header over the table's
  /// top-end corner: on a table this narrow the north seat's plate fills the
  /// corner the capsule would otherwise sit in.
  Widget _portrait(
    BuildContext context, {
    required Widget playfield,
    required Widget Function(ReplayCardArrangement, double) card,
  }) {
    final strings = context.strings;
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, body) {
          final metrics = TableHudMetrics.forViewport(
            body.maxWidth,
            floor: ReplayCardMetrics.tapTarget,
          );
          final headerHeight = metrics.buttonSize + metrics.edgeInset * 2;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: headerHeight,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: metrics.edgeInset + LoungeTokens.space1,
                  ),
                  child: Row(
                    children: [
                      const LoungeMedallion(
                        icon: Icons.history_rounded,
                        size: 32,
                        tone: LoungeMedallionTone.lit,
                      ),
                      const SizedBox(width: LoungeTokens.space3),
                      Expanded(
                        child: Text(
                          strings.replayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LoungeTokens.title.copyWith(
                            fontFamily: LoungeTokens.displayFamily,
                            fontVariations: LoungeTokens.displayWeight(700),
                          ),
                        ),
                      ),
                      _capsule(context, metrics),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: TableBackground(insetChild: true, child: playfield),
              ),
              Padding(
                padding: const EdgeInsets.all(LoungeTokens.space2),
                child: card(
                  ReplayCardArrangement.portrait,
                  (body.maxHeight - headerHeight) * 0.5,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The replay's HUD capsule: Analysis (a switch), Branch, Exit — the live
  /// table's Score | Pause capsule with the replay's own segments.
  Widget _capsule(BuildContext context, TableHudMetrics metrics) {
    final strings = context.strings;
    return TableHudCapsule(
      key: const ValueKey('replay-hud-capsule'),
      children: [
        TableChromeButton(
          key: const ValueKey('replay-analysis-toggle'),
          tooltip: strings.replayCoachTitle,
          semanticsLabel: strings.replayCoachTitle,
          icon: Icons.insights,
          diameter: metrics.buttonSize,
          iconSize: metrics.iconSize,
          toggled: _analysisOpen,
          onPressed: () => setState(() => _analysisOpen = !_analysisOpen),
        ),
        TableChromeButton(
          key: const ValueKey('replay-branch-control'),
          // The refusal is stated in the label, not left as a silently dead
          // button: a decided match has nothing to play out.
          tooltip: widget.branchLabel,
          semanticsLabel: widget.branchLabel,
          icon: Icons.alt_route,
          diameter: metrics.buttonSize,
          iconSize: metrics.iconSize,
          emphasized: true,
          onPressed: widget.onBranch,
        ),
        TableChromeButton(
          key: const ValueKey('replay-exit'),
          tooltip: strings.replayBack,
          semanticsLabel: strings.replayBack,
          icon: Icons.close_rounded,
          diameter: metrics.buttonSize,
          iconSize: metrics.iconSize,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}
