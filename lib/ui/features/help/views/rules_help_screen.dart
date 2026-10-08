import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../app/app_routes.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/brand/app_brand_mark.dart';
import '../../../core/panels/lounge_medallion.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../../shared/medallion_backdrop.dart';

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
            const MedallionBackdrop(
              top: -44,
              right: -48,
              opacity: 0.052,
              size: 220,
            ),
            ListView(
              padding: const EdgeInsets.fromLTRB(
                LoungeTokens.space5,
                LoungeTokens.space5,
                LoungeTokens.space5,
                LoungeTokens.space8,
              ),
              // Same order as ever, each part now a card on the felt: the
              // intro lit as the hero, the way into practice lit gold, and
              // each rule on a quieter surface (design contract section 8).
              children: [
                const _HelpCard(hero: true, child: _HelpIntro()),
                const _HelpCard(accent: true, child: _LearningEntry()),
                for (final section in sections)
                  _HelpCard(child: _HelpSection(section: section)),
              ],
            ),
          ],
        ),
      ),
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

/// One part of the help page as a lounge card, like the licences screen's.
class _HelpCard extends StatelessWidget {
  const _HelpCard({
    required this.child,
    this.hero = false,
    this.accent = false,
  });

  final Widget child;

  /// The page's lead card, lit warmest and lifted.
  final bool hero;

  /// A gold-edged call to action, a step quieter than the hero.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final decoration = hero
        ? loungeLitPanel(strength: 0.16)
        : accent
        ? loungeLitPanel(
            strength: 0.09,
          ).copyWith(boxShadow: LoungeTokens.elevationL2)
        : loungeLitPanel(
            strength: 0.04,
            edge: LoungeTokens.sandLine.withValues(alpha: 0.18),
          ).copyWith(boxShadow: const []);
    return Container(
      margin: const EdgeInsets.only(bottom: LoungeTokens.space4),
      padding: EdgeInsets.all(hero ? LoungeTokens.space5 : LoungeTokens.space4),
      decoration: decoration,
      child: child,
    );
  }
}

/// A card heading: the section's icon on a lit medallion beside its title.
class _MedallionHeading extends StatelessWidget {
  const _MedallionHeading({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        LoungeMedallion(icon: icon, size: 34, tone: LoungeMedallionTone.lit),
        const SizedBox(width: LoungeTokens.space3),
        Expanded(child: Text(title, style: LoungeTokens.heading)),
      ],
    );
  }
}

/// Entry points back into the teaching layer: guided practice and the
/// first-run onboarding intro.
class _LearningEntry extends StatelessWidget {
  const _LearningEntry();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MedallionHeading(
          icon: Icons.school_outlined,
          title: strings.helpLearningTitle,
        ),
        const SizedBox(height: LoungeTokens.space3),
        Text(strings.helpLearningBody, style: LoungeTokens.bodyMuted),
        const SizedBox(height: LoungeTokens.space3),
        Wrap(
          spacing: LoungeTokens.space3,
          runSpacing: LoungeTokens.space2,
          crossAxisAlignment: WrapCrossAlignment.center,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MedallionHeading(icon: section.icon, title: section.title),
        const SizedBox(height: LoungeTokens.space3),
        Text(section.body, style: LoungeTokens.body.copyWith(height: 1.45)),
      ],
    );
  }
}
