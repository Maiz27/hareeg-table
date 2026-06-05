import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../app/app_routes.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/brand/app_brand_mark.dart';
import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Player-facing Classic Hareeg help.
class RulesHelpScreen extends StatefulWidget {
  /// Creates the help screen.
  const RulesHelpScreen({super.key});

  @override
  State<RulesHelpScreen> createState() => _RulesHelpScreenState();
}

class _RulesHelpScreenState extends State<RulesHelpScreen> {
  @override
  void initState() {
    super.initState();
    AppOrientation.usePortrait();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final sections = [
      _HelpSectionData(
        icon: Icons.groups_outlined,
        title: strings.helpSetupTitle,
        body: strings.helpSetupBody,
      ),
      _HelpSectionData(
        icon: Icons.swap_horiz_outlined,
        title: strings.helpTurnFlowTitle,
        body: strings.helpTurnFlowBody,
      ),
      _HelpSectionData(
        icon: Icons.flag_outlined,
        title: strings.helpOpeningTitle,
        body: strings.helpOpeningBody,
      ),
      _HelpSectionData(
        icon: Icons.add_circle_outline,
        title: strings.helpCoversTitle,
        body: strings.helpCoversBody,
      ),
      _HelpSectionData(
        icon: Icons.casino_outlined,
        title: strings.helpJokersTitle,
        body: strings.helpJokersBody,
      ),
      _HelpSectionData(
        icon: Icons.local_fire_department_outlined,
        title: strings.helpFiftyTitle,
        body: strings.helpFiftyBody,
      ),
      _HelpSectionData(
        icon: Icons.scoreboard_outlined,
        title: strings.helpScoringTitle,
        body: strings.helpScoringBody,
      ),
      _HelpSectionData(
        icon: Icons.warning_amber_outlined,
        title: strings.helpMistakePresetsTitle,
        body: strings.helpMistakePresetsBody,
      ),
      _HelpSectionData(
        icon: Icons.pause_circle_outline,
        title: strings.helpPauseResumeTitle,
        body: strings.helpPauseResumeBody,
      ),
      _HelpSectionData(
        icon: Icons.lock_clock_outlined,
        title: strings.helpPlannedModesTitle,
        body: strings.helpPlannedModesBody,
      ),
    ];

    return Scaffold(
      backgroundColor: LoungeTokens.feltGreen,
      appBar: AppBar(title: Text(strings.helpTitle)),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _HelpBackdrop(),
            ListView(
              padding: const EdgeInsets.fromLTRB(
                LoungeTokens.space5,
                LoungeTokens.space5,
                LoungeTokens.space5,
                LoungeTokens.space8,
              ),
              children: [
                const _HelpIntro(),
                const SizedBox(height: LoungeTokens.space5),
                const _LearningEntryCard(),
                const SizedBox(height: LoungeTokens.space5),
                for (var i = 0; i < sections.length; i++) ...[
                  _HelpSection(section: sections[i]),
                  if (i < sections.length - 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: LoungeTokens.space4,
                      ),
                      child: _RuleDivider(),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpBackdrop extends StatelessWidget {
  const _HelpBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -44,
          right: -48,
          child: LoungeMotif(
            variant: LoungeMotifVariant.medallion,
            opacity: 0.052,
            strokeWidth: 1.0,
            density: 4,
            size: const Size.square(220),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 18,
          child: SizedBox(
            height: 30,
            child: CustomPaint(
              painter: const GeometricMotifPainter(
                variant: LoungeMotifVariant.border,
                opacity: 0.08,
                strokeWidth: 1.0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HelpIntro extends StatelessWidget {
  const _HelpIntro();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppBrandMark(semanticLabel: strings.appTitle),
        const SizedBox(width: LoungeTokens.space4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.helpTitle, style: LoungeTokens.display),
              const SizedBox(height: LoungeTokens.space2),
              Text(strings.helpIntro, style: LoungeTokens.bodyMuted),
            ],
          ),
        ),
      ],
    );
  }
}

/// Entry points back into the teaching layer: guided practice and the
/// first-run onboarding intro.
class _LearningEntryCard extends StatelessWidget {
  const _LearningEntryCard();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Container(
      padding: const EdgeInsets.all(LoungeTokens.space4),
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
        border: Border.all(
          color: LoungeTokens.goldAccent.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.school_outlined,
                color: LoungeTokens.goldAccent,
                size: 20,
              ),
              const SizedBox(width: LoungeTokens.space3),
              Text(strings.helpLearningTitle, style: LoungeTokens.heading),
            ],
          ),
          const SizedBox(height: LoungeTokens.space2),
          Text(strings.helpLearningBody, style: LoungeTokens.bodyMuted),
          const SizedBox(height: LoungeTokens.space3),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRoutes.practice),
                icon: const Icon(Icons.play_arrow_outlined, size: 18),
                label: Text(strings.practiceTitle),
                style: OutlinedButton.styleFrom(
                  foregroundColor: LoungeTokens.goldAccent,
                  side: BorderSide(
                    color: LoungeTokens.goldAccent.withValues(alpha: 0.5),
                  ),
                  visualDensity: VisualDensity.compact,
                  // The theme minimum is full-width; shrink to row content.
                  minimumSize: const Size(0, 40),
                ),
              ),
              const SizedBox(width: LoungeTokens.space3),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRoutes.onboarding),
                style: TextButton.styleFrom(
                  foregroundColor: LoungeTokens.mutedText,
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 40),
                ),
                child: Text(strings.practiceReplayIntro),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HelpSectionData {
  const _HelpSectionData({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({required this.section});

  final _HelpSectionData section;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(section.icon, color: LoungeTokens.goldAccent, size: 20),
        const SizedBox(width: LoungeTokens.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(section.title, style: LoungeTokens.heading),
              const SizedBox(height: LoungeTokens.space2),
              Text(
                section.body,
                style: LoungeTokens.body.copyWith(height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RuleDivider extends StatelessWidget {
  const _RuleDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: LoungeTokens.sandLine.withValues(alpha: 0.22),
    );
  }
}
