import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../l10n/app_strings.dart';
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
    final sections = [
      const _HelpSectionData(
        icon: Icons.groups_outlined,
        title: AppStrings.helpSetupTitle,
        body: AppStrings.helpSetupBody,
      ),
      const _HelpSectionData(
        icon: Icons.swap_horiz_outlined,
        title: AppStrings.helpTurnFlowTitle,
        body: AppStrings.helpTurnFlowBody,
      ),
      const _HelpSectionData(
        icon: Icons.flag_outlined,
        title: AppStrings.helpOpeningTitle,
        body: AppStrings.helpOpeningBody,
      ),
      const _HelpSectionData(
        icon: Icons.add_circle_outline,
        title: AppStrings.helpCoversTitle,
        body: AppStrings.helpCoversBody,
      ),
      const _HelpSectionData(
        icon: Icons.casino_outlined,
        title: AppStrings.helpJokersTitle,
        body: AppStrings.helpJokersBody,
      ),
      const _HelpSectionData(
        icon: Icons.local_fire_department_outlined,
        title: AppStrings.helpFiftyTitle,
        body: AppStrings.helpFiftyBody,
      ),
      const _HelpSectionData(
        icon: Icons.scoreboard_outlined,
        title: AppStrings.helpScoringTitle,
        body: AppStrings.helpScoringBody,
      ),
      const _HelpSectionData(
        icon: Icons.warning_amber_outlined,
        title: AppStrings.helpMistakePresetsTitle,
        body: AppStrings.helpMistakePresetsBody,
      ),
      const _HelpSectionData(
        icon: Icons.pause_circle_outline,
        title: AppStrings.helpPauseResumeTitle,
        body: AppStrings.helpPauseResumeBody,
      ),
      const _HelpSectionData(
        icon: Icons.lock_clock_outlined,
        title: AppStrings.helpPlannedModesTitle,
        body: AppStrings.helpPlannedModesBody,
      ),
    ];

    return Scaffold(
      backgroundColor: LoungeTokens.feltGreen,
      appBar: AppBar(title: const Text(AppStrings.helpTitle)),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox.square(
          dimension: 50,
          child: CustomPaint(
            painter: GeometricMotifPainter(
              variant: LoungeMotifVariant.medallion,
              opacity: 0.38,
              strokeWidth: 1.0,
              density: 3,
            ),
          ),
        ),
        const SizedBox(width: LoungeTokens.space4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(AppStrings.helpTitle, style: LoungeTokens.display),
              SizedBox(height: LoungeTokens.space2),
              Text(
                'A quick table reference for Classic Hareeg rules, scoring, Fifty, and resume behavior.',
                style: LoungeTokens.bodyMuted,
              ),
            ],
          ),
        ),
      ],
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
