import 'package:flutter/material.dart';

import '../../../../cpu/classic_hareeg/coaching/analysis_coach_settings.dart';
import '../../../../cpu/classic_hareeg/coaching/review_insight.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/panels/lounge_medallion.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../../game_table/table_mode.dart';
import '../review_insight_presenter.dart';

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
    this.inset = false,
    super.key,
  });

  /// Whether the region sits inside a card that already paints the surface.
  final bool inset;

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
      inset: inset,
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
    this.inset = false,
    super.key,
  });

  /// Whether the panel sits inside a card that already paints the surface
  /// (the replay card), rather than standing as its own band.
  final bool inset;

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

    // Standing alone it paints its own band with a brass top edge; inside
    // the replay card the card paints the surface and the band goes clear.
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: inset
            ? null
            : RadialGradient(
                center: const AlignmentDirectional(
                  -0.9,
                  -1.4,
                ).resolve(Directionality.of(context)),
                radius: 1.6,
                colors: [
                  Color.lerp(
                    LoungeTokens.coffeeCharcoal,
                    LoungeTokens.goldAccent,
                    0.1,
                  )!.withValues(alpha: 0.97),
                  LoungeTokens.coffeeCharcoal.withValues(alpha: 0.97),
                ],
              ),
        border: Border(
          top: BorderSide(
            color: inset
                ? Colors.transparent
                : LoungeTokens.goldAccent.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The coach's medallion, lit like the live coach card's badge.
              // Shorter than the verbosity control beside it, so the row is
              // still that control's height. Left out inside the replay card,
              // which is too narrow to give it the title's room.
              if (!inset) ...[
                const LoungeMedallion(
                  icon: Icons.insights,
                  size: 30,
                  tone: LoungeMedallionTone.lit,
                ),
                const SizedBox(width: LoungeTokens.space2),
              ],
              // The title yields space to the verbosity control rather than
              // claiming its full intrinsic width. Inflexible, it overflowed a
              // narrow phone by 89 px — the control was pushed off the right
              // edge. One line either way.
              Expanded(
                child: Text(
                  strings.replayCoachTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LoungeTokens.body.copyWith(
                    fontFamily: LoungeTokens.displayFamily,
                    fontWeight: FontWeight.w700,
                    fontVariations: LoungeTokens.displayWeight(700),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              // Flexible, not intrinsic: the control's natural width is its
              // longest localized level name, which is wider than the narrow
              // replay card. Both yield to the constraints they are given,
              // and both stay one line.
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
            Text(
              strings.replayOverrideNote,
              style: LoungeTokens.bodyMuted.copyWith(
                color: LoungeTokens.goldAccent,
              ),
            ),
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
                // Each finding hangs off a gold rule at its start edge, the
                // way the live coach card carries its accent.
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: BorderDirectional(
                      start: BorderSide(
                        color: LoungeTokens.goldAccent.withValues(alpha: 0.7),
                        width: 2,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: LoungeTokens.space3,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          presenter.sentenceFor(insight),
                          style: LoungeTokens.body,
                        ),
                        // The evidence is shown, not just used. A reviewer
                        // learning to read the table needs to see which
                        // visible fact the conclusion came from.
                        ...presenter
                            .evidenceLines(insight)
                            .map(
                              (line) => Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  top: 2,
                                  start: 8,
                                ),
                                child: Text(
                                  line,
                                  style: LoungeTokens.bodyMuted,
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
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

    // The closed control keeps its original row and height. Only the popup
    // sizes to its contents, with viewport constraints and wrapping labels.
    // DropdownButton ties menu width to the anchor; its wider-menu option can
    // position a wide RTL menu outside the viewport on supported Flutter SDKs.
    return Tooltip(
      message: strings.replayVerbosityLabel,
      excludeFromSemantics: true,
      child: MergeSemantics(
        child: Semantics(
          button: true,
          label: strings.replayVerbosityLabel,
          child: PopupMenuButton<AnalysisVerbosity>(
            // The outer tooltip already supplies the localized pointer hint
            // without duplicating the merged accessibility label.
            tooltip: '',
            initialValue: settings.verbosity,
            color: LoungeTokens.coffeeCharcoal,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
              side: BorderSide(
                color: LoungeTokens.sandLine.withValues(alpha: 0.32),
              ),
            ),
            onSelected: (value) =>
                onChanged(settings.copyWith(verbosity: value)),
            itemBuilder: (context) => [
              for (final verbosity in AnalysisVerbosity.values)
                PopupMenuItem(
                  value: verbosity,
                  child: Text(
                    verbosityLabel(strings, verbosity),
                    style: LoungeTokens.bodyMuted,
                  ),
                ),
            ],
            // The full 48 dp stays the target; the pill segment inside it is
            // what the eye reads, the same pill the live table's chips use.
            child: SizedBox(
              height: kMinInteractiveDimension,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(
                      LoungeTokens.radiusPill,
                    ),
                    border: Border.all(
                      color: LoungeTokens.sandLine.withValues(alpha: 0.32),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: LoungeTokens.space2,
                      end: 2,
                      top: LoungeTokens.space1,
                      bottom: LoungeTokens.space1,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            verbosityLabel(strings, settings.verbosity),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LoungeTokens.bodyMuted.copyWith(
                              color: LoungeTokens.offWhiteText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.arrow_drop_down,
                          size: 24,
                          color: LoungeTokens.goldAccent,
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
          child: MergeSemantics(
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
