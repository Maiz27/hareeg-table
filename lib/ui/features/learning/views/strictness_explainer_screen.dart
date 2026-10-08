import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../data/persistence/learning_progress_repository.dart';
import '../../../../domain/classic_hareeg/models/table_strictness.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/panels/lounge_medallion.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../../shared/medallion_backdrop.dart';
import '../models/practice_catalog.dart';
import '../models/practice_lesson_registry.dart';
import '../progress/learning_progress_workflow.dart';

/// Concise strictness-tier explainer: the practice checklist's
/// `strictness-tiers` entry, presented as a reading panel rather than a
/// scripted hand. "Got it" marks the lesson complete.
class StrictnessExplainerScreen extends StatefulWidget {
  /// Creates the explainer.
  const StrictnessExplainerScreen({
    required this.learningRepository,
    super.key,
  });

  /// Stable checklist lesson id this panel completes.
  static const lessonId = PracticeLessonRegistry.strictnessTiersLessonId;

  /// Practice progress persistence.
  final LearningProgressRepository learningRepository;

  @override
  State<StrictnessExplainerScreen> createState() =>
      _StrictnessExplainerScreenState();
}

class _StrictnessExplainerScreenState extends State<StrictnessExplainerScreen> {
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
      ).completeLesson(StrictnessExplainerScreen.lessonId);
    } catch (error, stackTrace) {
      debugPrint('Failed to save explainer completion: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    if (navigator.mounted) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Scaffold(
      backgroundColor: LoungeTokens.feltGreen,
      appBar: AppBar(title: Text(strings.practiceStrictnessTitle)),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const MedallionBackdrop(
              top: -44,
              right: -48,
              opacity: 0.052,
              size: 220,
              borderStrip: false,
            ),
            ListView(
              padding: const EdgeInsets.fromLTRB(
                LoungeTokens.space5,
                LoungeTokens.space5,
                LoungeTokens.space5,
                LoungeTokens.space8,
              ),
              // A lesson page: the intro lit as the hero under the lesson's
              // checklist number, then one quieter card per tier (design
              // contract section 8).
              children: [
                _TiersIntro(text: strings.practiceTiersIntro),
                const SizedBox(height: LoungeTokens.space4),
                for (final tier in TableStrictness.values) ...[
                  _TierCard(tier: tier),
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
          ],
        ),
      ),
    );
  }
}

/// The lit lead card: the lesson's checklist number on a medallion beside
/// the intro line, as the practice checklist shows it.
class _TiersIntro extends StatelessWidget {
  const _TiersIntro({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final number =
        PracticeCatalog.lessonIds.indexOf(StrictnessExplainerScreen.lessonId) +
        1;
    return Container(
      padding: const EdgeInsets.all(LoungeTokens.space4),
      decoration: loungeLitPanel(
        strength: 0.14,
      ).copyWith(boxShadow: LoungeTokens.elevationL2),
      child: Row(
        children: [
          ExcludeSemantics(
            child: number > 0
                ? LoungeMedallion.label(
                    label: '$number',
                    tone: LoungeMedallionTone.lit,
                  )
                : const LoungeMedallion(
                    icon: Icons.tune,
                    tone: LoungeMedallionTone.lit,
                  ),
          ),
          const SizedBox(width: LoungeTokens.space4),
          Expanded(
            child: Text(text, style: LoungeTokens.body.copyWith(fontSize: 15)),
          ),
        ],
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({required this.tier});

  final TableStrictness tier;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final (icon, body) = switch (tier) {
      TableStrictness.coaching => (
        Icons.assistant_direction_outlined,
        strings.practiceTierCoachingBody,
      ),
      TableStrictness.standard => (
        Icons.route_outlined,
        strings.practiceTierStandardBody,
      ),
      TableStrictness.strict => (
        Icons.gavel_outlined,
        strings.practiceTierStrictBody,
      ),
      TableStrictness.table => (
        Icons.table_restaurant_outlined,
        strings.practiceTierTableBody,
      ),
    };

    // A quiet lounge card per tier: the tier's icon on a medallion, its name
    // as the card title, and the one-line description under it.
    return Container(
      padding: const EdgeInsets.all(LoungeTokens.space4),
      decoration: loungeLitPanel(
        strength: 0.05,
        edge: LoungeTokens.sandLine.withValues(alpha: 0.18),
      ).copyWith(boxShadow: LoungeTokens.elevationL2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LoungeMedallion(icon: icon, size: 36),
          const SizedBox(width: LoungeTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: LoungeTokens.space1),
                Text(
                  strings.tableStrictnessLabel(tier),
                  style: LoungeTokens.heading.copyWith(fontSize: 16),
                ),
                const SizedBox(height: LoungeTokens.space1),
                Text(body, style: LoungeTokens.bodyMuted.copyWith(height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
