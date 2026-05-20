import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/theme/lounge_tokens.dart';

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
            const _LicensesBackdrop(),
            ListView(
              padding: const EdgeInsets.fromLTRB(
                LoungeTokens.space5,
                LoungeTokens.space5,
                LoungeTokens.space5,
                LoungeTokens.space8,
              ),
              children: [
                const _AboutIntro(),
                const _SectionBreak(),
                _LicenseSection(themes: widget.themes),
                const _SectionBreak(),
                Text(strings.licensesFooter, style: LoungeTokens.bodyMuted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LicensesBackdrop extends StatelessWidget {
  const _LicensesBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -36,
          right: -48,
          child: LoungeMotif(
            variant: LoungeMotifVariant.medallion,
            opacity: 0.05,
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

class _AboutIntro extends StatelessWidget {
  const _AboutIntro();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

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
            children: [
              Text(strings.aboutHeader, style: LoungeTokens.display),
              const SizedBox(height: LoungeTokens.space2),
              Text(strings.aboutBody, style: LoungeTokens.body),
              const SizedBox(height: LoungeTokens.space4),
              Wrap(
                spacing: LoungeTokens.space2,
                runSpacing: LoungeTokens.space2,
                children: [
                  _LicensePill(
                    icon: Icons.offline_bolt_outlined,
                    label: strings.offlineFirst,
                  ),
                  _LicensePill(
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
            const Icon(Icons.style_outlined, color: LoungeTokens.goldAccent),
            const SizedBox(width: LoungeTokens.space2),
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

class _LicensePill extends StatelessWidget {
  const _LicensePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.22),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LoungeTokens.space2,
          vertical: LoungeTokens.space1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: LoungeTokens.goldAccent),
            const SizedBox(width: LoungeTokens.space1),
            Text(label, style: LoungeTokens.bodyMuted),
          ],
        ),
      ),
    );
  }
}

class _SectionBreak extends StatelessWidget {
  const _SectionBreak();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LoungeTokens.space5),
      child: Divider(
        height: 1,
        color: LoungeTokens.sandLine.withValues(alpha: 0.24),
      ),
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
