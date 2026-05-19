import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../l10n/app_strings.dart';

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
        title: AppStrings.helpSetupTitle,
        body: AppStrings.helpSetupBody,
      ),
      const _HelpSectionData(
        title: AppStrings.helpTurnFlowTitle,
        body: AppStrings.helpTurnFlowBody,
      ),
      const _HelpSectionData(
        title: AppStrings.helpOpeningTitle,
        body: AppStrings.helpOpeningBody,
      ),
      const _HelpSectionData(
        title: AppStrings.helpCoversTitle,
        body: AppStrings.helpCoversBody,
      ),
      const _HelpSectionData(
        title: AppStrings.helpJokersTitle,
        body: AppStrings.helpJokersBody,
      ),
      const _HelpSectionData(
        title: AppStrings.helpFiftyTitle,
        body: AppStrings.helpFiftyBody,
      ),
      const _HelpSectionData(
        title: AppStrings.helpScoringTitle,
        body: AppStrings.helpScoringBody,
      ),
      const _HelpSectionData(
        title: AppStrings.helpMistakePresetsTitle,
        body: AppStrings.helpMistakePresetsBody,
      ),
      const _HelpSectionData(
        title: AppStrings.helpPauseResumeTitle,
        body: AppStrings.helpPauseResumeBody,
      ),
      const _HelpSectionData(
        title: AppStrings.helpPlannedModesTitle,
        body: AppStrings.helpPlannedModesBody,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.helpTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final section in sections)
              _HelpSection(title: section.title, body: section.body),
          ],
        ),
      ),
    );
  }
}

class _HelpSectionData {
  const _HelpSectionData({required this.title, required this.body});

  final String title;
  final String body;
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(body),
        ],
      ),
    );
  }
}
