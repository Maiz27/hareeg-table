import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/brand/app_brand_mark.dart';
import '../../../core/panels/lounge_medallion.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../../shared/medallion_backdrop.dart';
import 'meta_pill.dart';

/// Attribution + license screen reached from Settings -> About.
class LicensesScreen extends StatefulWidget {
  /// Creates the licenses screen.
  const LicensesScreen({super.key, required this.themes});

  /// Bundled card themes shown in the attribution list.
  final List<HareegCardTheme> themes;

  @override
  State<LicensesScreen> createState() => _LicensesScreenState();
}

class _LicensesScreenState extends State<LicensesScreen> {
  @override
  void initState() {
    super.initState();
    AppOrientation.usePortrait();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Scaffold(
      backgroundColor: LoungeTokens.feltGreen,
      appBar: AppBar(title: Text(strings.aboutLicenses)),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const MedallionBackdrop(
              top: -36,
              right: -48,
              opacity: 0.05,
              size: 220,
            ),
            ListView(
              padding: const EdgeInsets.fromLTRB(
                LoungeTokens.space5,
                LoungeTokens.space5,
                LoungeTokens.space5,
                LoungeTokens.space8,
              ),
              // Each part of the page is a card on the felt: the intro lit
              // as the hero, the story and each licence group on quieter
              // surfaces (design contract section 8).
              children: [
                const _AboutCard(hero: true, child: _AboutIntro()),
                const _AboutCard(child: _OriginStory()),
                _AboutCard(child: _LicenseSection(themes: widget.themes)),
                const _AboutCard(child: _SoundLicenseSection()),
                const _AboutCard(child: _FontLicenseSection()),
                const SizedBox(height: LoungeTokens.space2),
                Text(
                  strings.licensesFooter,
                  textAlign: TextAlign.center,
                  style: LoungeTokens.bodyMuted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.child, this.hero = false});

  final Widget child;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: LoungeTokens.space4),
      padding: const EdgeInsets.all(LoungeTokens.space5),
      decoration: hero
          ? loungeLitPanel(strength: 0.16)
          : loungeLitPanel(
              strength: 0.04,
              edge: LoungeTokens.sandLine.withValues(alpha: 0.18),
            ).copyWith(boxShadow: const []),
      child: child,
    );
  }
}

class _AboutIntro extends StatelessWidget {
  const _AboutIntro();

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
              Text(strings.aboutHeader, style: LoungeTokens.display),
              const SizedBox(height: LoungeTokens.space2),
              Text(strings.aboutBody, style: LoungeTokens.body),
              const SizedBox(height: LoungeTokens.space4),
              Wrap(
                spacing: LoungeTokens.space2,
                runSpacing: LoungeTokens.space2,
                children: [
                  MetaPill(
                    icon: Icons.offline_bolt_outlined,
                    label: strings.offlineFirst,
                  ),
                  MetaPill(
                    icon: Icons.favorite_border,
                    label: strings.noAdsOrPaidLocks,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OriginStory extends StatelessWidget {
  const _OriginStory();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const LoungeMedallion(
              icon: Icons.local_fire_department_outlined,
              size: 34,
              tone: LoungeMedallionTone.lit,
            ),
            const SizedBox(width: LoungeTokens.space3),
            Expanded(
              child: Text(
                strings.whyThisExistsHeader,
                style: LoungeTokens.heading,
              ),
            ),
          ],
        ),
        const SizedBox(height: LoungeTokens.space4),
        Text(strings.whyThisExistsBody, style: LoungeTokens.body),
      ],
    );
  }
}

class _LicenseSection extends StatelessWidget {
  const _LicenseSection({required this.themes});

  final List<HareegCardTheme> themes;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const LoungeMedallion(
              icon: Icons.style_outlined,
              size: 34,
              tone: LoungeMedallionTone.lit,
            ),
            const SizedBox(width: LoungeTokens.space3),
            Expanded(
              child: Text(
                strings.licensesThemesHeader,
                style: LoungeTokens.heading,
              ),
            ),
          ],
        ),
        const SizedBox(height: LoungeTokens.space4),
        for (var i = 0; i < themes.length; i++) ...[
          _ThemeLicenseRow(theme: themes[i]),
          if (i < themes.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: LoungeTokens.space3),
              child: _RuleDivider(),
            ),
        ],
      ],
    );
  }
}

class _ThemeLicenseRow extends StatelessWidget {
  const _ThemeLicenseRow({required this.theme});

  final HareegCardTheme theme;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          theme.source == CardThemeAssetSource.codeRendered
              ? Icons.brush_outlined
              : Icons.collections_bookmark_outlined,
          size: 20,
          color: LoungeTokens.goldAccent,
        ),
        const SizedBox(width: LoungeTokens.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(theme.label, style: LoungeTokens.titleSmall),
              const SizedBox(height: 3),
              Text(
                theme.licenseAttribution ?? strings.licenseNotDeclared,
                style: LoungeTokens.bodyMuted,
              ),
              if (theme.sourceUrl != null) ...[
                const SizedBox(height: LoungeTokens.space2),
                Text(theme.sourceUrl!, style: LoungeTokens.bodyMuted),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SoundLicenseSection extends StatelessWidget {
  const _SoundLicenseSection();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const LoungeMedallion(
              icon: Icons.graphic_eq,
              size: 34,
              tone: LoungeMedallionTone.lit,
            ),
            const SizedBox(width: LoungeTokens.space3),
            Expanded(
              child: Text(
                strings.licensesSoundsHeader,
                style: LoungeTokens.heading,
              ),
            ),
          ],
        ),
        const SizedBox(height: LoungeTokens.space4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.volume_up_outlined,
              size: 20,
              color: LoungeTokens.goldAccent,
            ),
            const SizedBox(width: LoungeTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.kenneyCasinoAudio,
                    style: LoungeTokens.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    strings.kenneyCasinoAudioAttribution,
                    style: LoungeTokens.bodyMuted,
                  ),
                  const SizedBox(height: LoungeTokens.space2),
                  Text(
                    strings.kenneyCasinoAudioUrl,
                    style: LoungeTokens.bodyMuted,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FontLicenseSection extends StatelessWidget {
  const _FontLicenseSection();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const LoungeMedallion(
              icon: Icons.text_fields,
              size: 34,
              tone: LoungeMedallionTone.lit,
            ),
            const SizedBox(width: LoungeTokens.space3),
            Expanded(
              child: Text(
                strings.licensesFontsHeader,
                style: LoungeTokens.heading,
              ),
            ),
          ],
        ),
        const SizedBox(height: LoungeTokens.space4),
        for (final line in [
          strings.fontReemKufiAttribution,
          strings.fontPlexArabicAttribution,
        ]) ...[
          Text(line, style: LoungeTokens.bodyMuted),
          const SizedBox(height: LoungeTokens.space2),
        ],
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
      color: LoungeTokens.sandLine.withValues(alpha: 0.14),
    );
  }
}
