import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../data/persistence/learning_progress_repository.dart';
import '../../../../domain/classic_hareeg/models/table_strictness.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/theme/lounge_tokens.dart';

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
  static const lessonId = 'strictness-tiers';

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
      final progress = await widget.learningRepository.loadProgress();
      await widget.learningRepository.saveProgress(
        progress.withLessonStatus(
          StrictnessExplainerScreen.lessonId,
          PracticeLessonStatus.completed,
        ),
      );
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            LoungeTokens.space5,
            LoungeTokens.space5,
            LoungeTokens.space5,
            LoungeTokens.space8,
          ),
          children: [
            Text(strings.practiceTiersIntro, style: LoungeTokens.bodyMuted),
            const SizedBox(height: LoungeTokens.space5),
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

    return Container(
      padding: const EdgeInsets.all(LoungeTokens.space4),
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: LoungeTokens.goldAccent),
          const SizedBox(width: LoungeTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.tableStrictnessLabel(tier),
                  style: LoungeTokens.body.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: LoungeTokens.space2),
                Text(body, style: LoungeTokens.bodyMuted.copyWith(height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
