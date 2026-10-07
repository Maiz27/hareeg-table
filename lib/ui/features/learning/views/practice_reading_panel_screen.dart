import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../data/persistence/learning_progress_repository.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/cards/card_view.dart';
import '../../../core/panels/lounge_medallion.dart';
import '../../../core/scopes/app_scopes.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../models/practice_reading_panels.dart';
import '../progress/learning_progress_workflow.dart';

/// Generic conceptual reference panel for the Fundamentals pack.
///
/// Renders the [PracticeReadingPanel] content keyed by [lessonId] — a title
/// and a list of headed/unheaded sections — over the shared felt-green
/// scaffold. "Got it" marks the lesson complete and pops, mirroring
/// [StrictnessExplainerScreen]. The bespoke `strictness-tiers` panel keeps its
/// own screen with hand-built tier cards.
class PracticeReadingPanelScreen extends StatefulWidget {
  /// Creates the reading panel for [lessonId].
  const PracticeReadingPanelScreen({
    required this.lessonId,
    required this.learningRepository,
    super.key,
  });

  /// Stable checklist lesson id this panel completes.
  final String lessonId;

  /// Practice progress persistence.
  final LearningProgressRepository learningRepository;

  @override
  State<PracticeReadingPanelScreen> createState() =>
      _PracticeReadingPanelScreenState();
}

class _PracticeReadingPanelScreenState
    extends State<PracticeReadingPanelScreen> {
  @override
  void initState() {
    super.initState();
    AppOrientation.usePortrait();
  }

  Future<void> _gotIt() async {
    final navigator = Navigator.of(context);
    try {
      await LearningProgressWorkflow(
        widget.learningRepository,
      ).completeLesson(widget.lessonId);
    } catch (error, stackTrace) {
      debugPrint('Failed to save reading-panel completion: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    if (navigator.mounted) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final panel = PracticeReadingPanels.byId(widget.lessonId);

    if (panel == null) {
      // Defensive: routing only sends keyed lesson ids here. An unknown id
      // gets a quiet bail-out rather than a crash.
      return Scaffold(
        backgroundColor: LoungeTokens.feltGreen,
        appBar: AppBar(title: Text(strings.practiceTitle)),
        body: const SizedBox.shrink(),
      );
    }

    return Scaffold(
      backgroundColor: LoungeTokens.feltGreen,
      appBar: AppBar(title: Text(panel.title(strings))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            LoungeTokens.space5,
            LoungeTokens.space5,
            LoungeTokens.space5,
            LoungeTokens.space8,
          ),
          children: [
            for (final (i, section) in panel.sections.indexed) ...[
              _SectionCard(
                section: section,
                number: panel.sections
                    .take(i + 1)
                    .where((s) => s.heading != null)
                    .length,
                lead: i == 0 && section.heading == null,
              ),
              const SizedBox(height: LoungeTokens.space3),
            ],
            const SizedBox(height: LoungeTokens.space3),
            FilledButton.icon(
              onPressed: _gotIt,
              icon: const Icon(Icons.check_outlined),
              label: Text(strings.practiceTiersGotIt),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.number,
    required this.lead,
  });

  final PracticeReadingSection section;

  /// Position among the panel's headed sections, shown on its medallion.
  final int number;

  /// Whether this is the panel's unheaded opening paragraph, set as a lead.
  final bool lead;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final heading = section.heading;
    final theme = CardThemeScope.of(context);

    return Container(
      padding: const EdgeInsets.all(LoungeTokens.space4),
      decoration: loungeLitPanel(
        strength: lead ? 0.12 : 0.05,
        edge: lead
            ? LoungeTokens.goldAccent.withValues(alpha: 0.45)
            : LoungeTokens.sandLine.withValues(alpha: 0.18),
      ).copyWith(boxShadow: lead ? LoungeTokens.elevationL2 : const []),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heading != null) ...[
            Row(
              children: [
                LoungeMedallion.label(
                  label: '$number',
                  size: 28,
                  tone: LoungeMedallionTone.lit,
                ),
                const SizedBox(width: LoungeTokens.space3),
                Expanded(
                  child: Text(heading(strings), style: LoungeTokens.title),
                ),
              ],
            ),
            const SizedBox(height: LoungeTokens.space3),
          ],
          for (var i = 0; i < section.lines.length; i++) ...[
            if (i > 0) const SizedBox(height: LoungeTokens.space2),
            Text(
              section.lines[i](strings),
              style: lead
                  ? LoungeTokens.body.copyWith(fontSize: 15, height: 1.45)
                  : LoungeTokens.bodyMuted.copyWith(height: 1.4),
            ),
          ],
          for (final row in section.cardRows) ...[
            const SizedBox(height: LoungeTokens.space3),
            _CardRowView(row: row, theme: theme),
          ],
        ],
      ),
    );
  }
}

/// Renders one [PracticeCardRow]: real card faces in a horizontal row with an
/// optional localized caption beside them. The cards are the centerpiece, so
/// they sit at a comfortable teaching size with small gaps.
class _CardRowView extends StatelessWidget {
  const _CardRowView({required this.row, required this.theme});

  /// Card teaching size — wide enough to read pips, compact enough that a
  /// five-card ace run still fits a portrait section card.
  static const _cardSize = Size(46, 66);

  final PracticeCardRow row;
  final HareegCardTheme theme;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final caption = row.caption;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Wrap(
          spacing: LoungeTokens.space1,
          runSpacing: LoungeTokens.space1,
          children: [
            for (final card in row.cards)
              HareegCardView(
                theme: theme,
                card: card,
                variant: CardVariant.picker,
                size: _cardSize,
              ),
          ],
        ),
        if (caption != null) ...[
          const SizedBox(width: LoungeTokens.space3),
          Flexible(
            child: Text(
              caption(strings),
              style: LoungeTokens.body.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }
}
