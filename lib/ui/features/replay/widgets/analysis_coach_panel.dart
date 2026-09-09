import 'package:flutter/material.dart';

import '../../../../cpu/classic_hareeg/coaching/analysis_coach_settings.dart';
import '../../../../cpu/classic_hareeg/coaching/review_insight.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../../game_table/table_mode.dart';
import '../review_insight_presenter.dart';
import 'replay_hud_clusters.dart';

/// Decides whether a coach is shown here at all, and which one.
///
/// The decision is read from the table mode's single coach-surface field
/// rather than assumed by the screen, so "only the analysis coach appears in
/// review" is a property of the mode table rather than of this widget. A mode
/// whose surface is the live coach or none renders nothing here — the live
/// coach belongs to the live table and has no business in a replay.
class ReviewAnalysisRegion extends StatelessWidget {
  /// Creates the analysis region for [mode].
  const ReviewAnalysisRegion({
    required this.mode,
    required this.insights,
    required this.presenter,
    required this.settings,
    required this.isOverridden,
    required this.onSettingsChanged,
    required this.reviewable,
    super.key,
  });

  /// Mode this surface is running as.
  final TableMode mode;

  /// Insights for the current frame.
  final List<ReviewInsight> insights;

  /// Turns insights into sentences.
  final ReviewInsightPresenter presenter;

  /// Settings in force for this replay.
  final AnalysisCoachSettings settings;

  /// Whether [settings] differs from the saved default.
  final bool isOverridden;

  /// Requests a settings change for this replay only.
  final ValueChanged<AnalysisCoachSettings> onSettingsChanged;

  /// Whether the current frame is a played move.
  final bool reviewable;

  @override
  Widget build(BuildContext context) {
    if (mode.capabilities.coachSurface != TableCoachSurface.analysis) {
      return const SizedBox.shrink();
    }
    return AnalysisCoachPanel(
      insights: insights,
      presenter: presenter,
      settings: settings,
      isOverridden: isOverridden,
      onSettingsChanged: onSettingsChanged,
      reviewable: reviewable,
    );
  }
}

/// The short layout's analysis surface: a one-line chip that opens into a
/// bounded, scrollable card.
///
/// The expanded analysis popover.
///
/// Sticky on purpose. Stepping updates the contents in place and leaves the
/// card open, because comparing one decision against the next is the review
/// task — collapsing after every step would defeat it. Transport shares the
/// card's [replayHudTapGroup], so only an explicit dismissal or a tap on the
/// table closes it.
///
/// The wide headline chip this used to collapse into is withdrawn: the
/// collapsed affordance is now the 44 x 44 Analysis button in the physical-left
/// rail, and the rendered measurements showed the chip covering opponent cards
/// under RTL. When the card is closed this widget renders nothing at all.
class ReviewAnalysisCard extends StatelessWidget {
  /// Creates the popover surface.
  const ReviewAnalysisCard({
    required this.mode,
    required this.insights,
    required this.presenter,
    required this.settings,
    required this.isOverridden,
    required this.onSettingsChanged,
    required this.reviewable,
    required this.expanded,
    required this.onDismiss,
    super.key,
  });

  /// The surface this runs as.
  final TableMode mode;

  /// Insights for the current frame.
  final List<ReviewInsight> insights;

  /// Turns insights into sentences.
  final ReviewInsightPresenter presenter;

  /// Settings in force for this replay.
  final AnalysisCoachSettings settings;

  /// Whether [settings] differs from the saved default.
  final bool isOverridden;

  /// Requests a settings change.
  final ValueChanged<AnalysisCoachSettings> onSettingsChanged;

  /// Whether the frame is a played move.
  final bool reviewable;

  /// Whether the card is open.
  final bool expanded;

  /// Closes it.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    // Read from the mode's single coach-surface field rather than assumed, so
    // a surface that should show no coach cannot grow one here.
    if (mode.capabilities.coachSurface != TableCoachSurface.analysis) {
      return const SizedBox.shrink();
    }

    if (!expanded) {
      return const SizedBox.shrink();
    }

    final strings = context.strings;

    return TapRegion(
      // Observation, not a barrier. Nothing full-screen participates in hit
      // testing, so a tap outside collapses the card *and* still reaches
      // whatever it landed on. The group is what keeps transport "inside".
      groupId: replayHudTapGroup,
      onTapOutside: (_) => onDismiss(),
      child: Padding(
        // The popover rectangle the collision map handed down is exact; this
        // inset keeps the card's own border off the boundary it was measured
        // against rather than growing past it.
        padding: const EdgeInsets.only(right: 4, bottom: 4),
        child: Container(
          decoration: BoxDecoration(
            color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: LoungeTokens.sandLine.withValues(alpha: 0.65),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Tooltip(
                  message: strings.close,
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    color: LoungeTokens.sandLine,
                    onPressed: onDismiss,
                    constraints: const BoxConstraints(
                      minWidth: LoungeTokens.tapTargetCardShort,
                      minHeight: LoungeTokens.tapTargetCardShort,
                    ),
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: AnalysisCoachPanel(
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
          ),
        ),
      ),
    );
  }
}

/// The only coach shown while reviewing.
///
/// The live coaching overlay never appears here — that is decided by the table
/// mode's single coach-surface field, not by this widget — so a reviewer sees
/// evidence-bound analysis and nothing else.
class AnalysisCoachPanel extends StatelessWidget {
  /// Creates the panel.
  const AnalysisCoachPanel({
    required this.insights,
    required this.presenter,
    required this.settings,
    required this.isOverridden,
    required this.onSettingsChanged,
    required this.reviewable,
    super.key,
  });

  /// Insights for the current frame, already filtered by [settings].
  final List<ReviewInsight> insights;

  /// Turns insights into sentences.
  final ReviewInsightPresenter presenter;

  /// Settings in force for this replay.
  final AnalysisCoachSettings settings;

  /// Whether [settings] differs from the player's saved default.
  final bool isOverridden;

  /// Requests a settings change for this replay only.
  final ValueChanged<AnalysisCoachSettings> onSettingsChanged;

  /// Whether the current frame is a played move at all.
  ///
  /// The deal and a round start are positions, not decisions, so there is
  /// nothing to review on them — which is different from having reviewed a
  /// move and found nothing worth saying.
  final bool reviewable;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.94),
        border: const Border(
          top: BorderSide(color: LoungeTokens.sandLine, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The title yields space to the verbosity control rather than
              // claiming its full intrinsic width. Inflexible, it overflowed a
              // narrow docked phone by 89 px — the control was pushed off the
              // right edge, so the panel was unusable at exactly the width the
              // layout falls back to. One line either way, so the panel's
              // height is unchanged.
              Expanded(
                child: Text(
                  strings.replayCoachTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LoungeTokens.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: LoungeTokens.sandLine,
                  ),
                ),
              ),
              // Flexible, not intrinsic: the control's natural width is its
              // longest localized level name, which is wider than the whole
              // popover. Left inflexible it overflowed by 134 px there, in
              // exactly the way the title used to overflow the narrow docked
              // phone. Both now yield to the constraints they are given, and
              // both stay one line, so the panel's height is unchanged.
              Flexible(
                child: _VerbosityMenu(
                  settings: settings,
                  onChanged: onSettingsChanged,
                ),
              ),
            ],
          ),
          if (isOverridden) ...[
            const SizedBox(height: 2),
            Text(strings.replayOverrideNote, style: LoungeTokens.bodyMuted),
          ],
          const SizedBox(height: 8),
          if (!reviewable)
            Text(
              strings.replayCoachNothingToReview,
              style: LoungeTokens.bodyMuted,
            )
          else if (insights.isEmpty)
            Text(strings.replayCoachQuiet, style: LoungeTokens.bodyMuted)
          else
            ...insights.map(
              (insight) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      presenter.sentenceFor(insight),
                      style: LoungeTokens.body,
                    ),
                    // The evidence is shown, not just used. A reviewer learning
                    // to read the table needs to see which visible fact the
                    // conclusion came from.
                    ...presenter
                        .evidenceLines(insight)
                        .map(
                          (line) => Padding(
                            padding: const EdgeInsets.only(top: 2, left: 8),
                            child: Text(line, style: LoungeTokens.bodyMuted),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          _CardDeathToggle(settings: settings, onChanged: onSettingsChanged),
        ],
      ),
    );
  }
}

class _VerbosityMenu extends StatelessWidget {
  const _VerbosityMenu({required this.settings, required this.onChanged});

  final AnalysisCoachSettings settings;
  final ValueChanged<AnalysisCoachSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Semantics(
      label: strings.replayCoachTitle,
      child: DropdownButton<AnalysisVerbosity>(
        value: settings.verbosity,
        dropdownColor: LoungeTokens.coffeeCharcoal,
        style: LoungeTokens.bodyMuted,
        underline: const SizedBox.shrink(),
        // Fills whatever width it is given instead of demanding its intrinsic
        // one, and ellipsizes the level name rather than pushing the icon off
        // the edge. The full value stays reachable through the semantics label
        // and the open menu.
        isExpanded: true,
        onChanged: (value) {
          if (value != null) {
            onChanged(settings.copyWith(verbosity: value));
          }
        },
        items: [
          for (final verbosity in AnalysisVerbosity.values)
            DropdownMenuItem(
              value: verbosity,
              child: Text(
                verbosityLabel(strings, verbosity),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

class _CardDeathToggle extends StatelessWidget {
  const _CardDeathToggle({required this.settings, required this.onChanged});

  final AnalysisCoachSettings settings;
  final ValueChanged<AnalysisCoachSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Row(
      children: [
        Expanded(
          child: Text(
            strings.replayCardDeathWarnings,
            style: LoungeTokens.bodyMuted,
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: LoungeTokens.tapTargetCardShort,
            minHeight: LoungeTokens.tapTargetCardShort,
          ),
          child: Semantics(
            label: strings.replayCardDeathWarnings,
            toggled: settings.cardDeathWarnings,
            child: Switch(
              value: settings.cardDeathWarnings,
              onChanged: (value) =>
                  onChanged(settings.copyWith(cardDeathWarnings: value)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Localized name for a verbosity level.
///
/// Shared with the settings screen so the two surfaces cannot drift into
/// calling the same level different things.
String verbosityLabel(AppStrings strings, AnalysisVerbosity verbosity) {
  return switch (verbosity) {
    AnalysisVerbosity.narrateAll => strings.replayVerbosityNarrateAll,
    AnalysisVerbosity.keyMoments => strings.replayVerbosityKeyMoments,
    AnalysisVerbosity.clearMistakes => strings.replayVerbosityClearMistakes,
  };
}
