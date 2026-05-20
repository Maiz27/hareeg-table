import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../app/app_routes.dart';
import '../../../../data/persistence/match_repository.dart';
import '../../../../domain/classic_hareeg/rules/classic_hareeg_rules.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Main menu and navigation shell.
class HomeScreen extends StatefulWidget {
  /// Creates the main menu.
  const HomeScreen({required this.matchRepository, super.key});

  /// Active match persistence.
  final MatchRepository matchRepository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ClassicHareegMatchSnapshot? _savedMatch;
  var _loadingSavedMatch = true;

  @override
  void initState() {
    super.initState();
    AppOrientation.usePortrait();
    _loadSavedMatch();
  }

  @override
  Widget build(BuildContext context) {
    final rules = ClassicHareegRules.defaults();

    return Scaffold(
      backgroundColor: LoungeTokens.feltGreen,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth >= 520
                ? LoungeTokens.space8
                : LoungeTokens.space5;

            return Stack(
              fit: StackFit.expand,
              children: [
                const _MenuBackdrop(),
                ListView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    LoungeTokens.space6,
                    horizontalPadding,
                    LoungeTokens.space8,
                  ),
                  children: [
                    _BrandHeader(rules: rules),
                    const SizedBox(height: LoungeTokens.space8),
                    FilledButton.icon(
                      onPressed: () => _openAndRefresh(AppRoutes.newGame),
                      icon: const Icon(Icons.table_bar_outlined),
                      label: const Text(AppStrings.newGame),
                    ),
                    const SizedBox(height: LoungeTokens.space3),
                    _CommandStack(
                      children: [
                        _CommandRow(
                          icon: Icons.play_circle_outline,
                          label: AppStrings.continueGame,
                          subtitle: _savedMatch == null
                              ? (_loadingSavedMatch
                                    ? AppStrings.checkingSavedMatch
                                    : AppStrings.noSavedMatch)
                              : AppStrings.resumeSavedMatch,
                          onTap: _savedMatch == null
                              ? null
                              : () => _openAndRefresh(
                                  AppRoutes.table,
                                  arguments: _savedMatch,
                                ),
                        ),
                        _CommandRow(
                          icon: Icons.settings_outlined,
                          label: AppStrings.settings,
                          onTap: () => Navigator.of(
                            context,
                          ).pushNamed(AppRoutes.settings),
                        ),
                        _CommandRow(
                          icon: Icons.menu_book_outlined,
                          label: AppStrings.rulesHelp,
                          onTap: () => Navigator.of(
                            context,
                          ).pushNamed(AppRoutes.rulesHelp),
                        ),
                      ],
                    ),
                    if (_savedMatch != null) ...[
                      const SizedBox(height: LoungeTokens.space2),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _abandonSavedMatch,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text(AppStrings.abandonSavedMatch),
                        ),
                      ),
                    ],
                    const SizedBox(height: LoungeTokens.space8),
                    const _ClassicContext(),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _loadSavedMatch() async {
    ClassicHareegMatchSnapshot? savedMatch;
    try {
      savedMatch = await widget.matchRepository.loadActiveMatch();
    } catch (error, stackTrace) {
      debugPrint('Failed to load saved match: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _savedMatch = savedMatch;
      _loadingSavedMatch = false;
    });
  }

  Future<void> _openAndRefresh(String route, {Object? arguments}) async {
    await Navigator.of(context).pushNamed(route, arguments: arguments);
    if (!mounted) {
      return;
    }
    await _loadSavedMatch();
  }

  Future<void> _abandonSavedMatch() async {
    await widget.matchRepository.abandonActiveMatch();
    if (!mounted) {
      return;
    }

    setState(() {
      _savedMatch = null;
      _loadingSavedMatch = false;
    });
  }
}

class _MenuBackdrop extends StatelessWidget {
  const _MenuBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -48,
          right: -46,
          child: LoungeMotif(
            variant: LoungeMotifVariant.medallion,
            opacity: 0.07,
            strokeWidth: 1.0,
            density: 4,
            size: const Size.square(230),
          ),
        ),
        Positioned(
          bottom: 18,
          left: -58,
          child: LoungeMotif(
            variant: LoungeMotifVariant.medallion,
            opacity: 0.055,
            strokeWidth: 1.0,
            density: 5,
            size: const Size.square(190),
          ),
        ),
      ],
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.rules});

  final ClassicHareegRules rules;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 380;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(child: _BrandCopy()),
                if (!compact) ...[
                  const SizedBox(width: LoungeTokens.space4),
                  const _MenuCardFan(width: 112, height: 84),
                ],
              ],
            ),
            if (compact) ...[
              const SizedBox(height: LoungeTokens.space5),
              const Center(child: _MenuCardFan(width: 138, height: 82)),
            ],
            const SizedBox(height: LoungeTokens.space5),
            _RuleLine(rules: rules),
          ],
        );
      },
    );
  }
}

class _BrandCopy extends StatelessWidget {
  const _BrandCopy();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          const TextSpan(
            children: [
              TextSpan(text: 'Hareeg ', style: _brandTitle),
              TextSpan(text: 'Table', style: _brandTitleGold),
            ],
          ),
        ),
        const SizedBox(height: LoungeTokens.space2),
        const Text(
          AppStrings.homeSubtitle,
          style: TextStyle(
            color: LoungeTokens.mutedText,
            fontSize: 15,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  static const _brandTitle = TextStyle(
    color: LoungeTokens.offWhiteText,
    fontSize: 36,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.1,
    height: 1.0,
  );

  static const _brandTitleGold = TextStyle(
    color: LoungeTokens.goldAccent,
    fontSize: 36,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.1,
    height: 1.0,
  );
}

class _RuleLine extends StatelessWidget {
  const _RuleLine({required this.rules});

  final ClassicHareegRules rules;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: LoungeTokens.space2,
      runSpacing: LoungeTokens.space2,
      children: [
        _InlineFact(label: '${rules.seatCount} seats'),
        _InlineFact(label: '${rules.openingRequirement} opening'),
        _InlineFact(label: 'Fifty ${rules.fiftyClaimSeconds}s'),
      ],
    );
  }
}

class _InlineFact extends StatelessWidget {
  const _InlineFact({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LoungeTokens.space3,
          vertical: LoungeTokens.space2,
        ),
        child: Text(label, style: LoungeTokens.bodyMuted),
      ),
    );
  }
}

class _MenuCardFan extends StatelessWidget {
  const _MenuCardFan({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _MenuCardFanPainter()),
    );
  }
}

class _MenuCardFanPainter extends CustomPainter {
  static const _cardCount = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final cardWidth = size.width * 0.34;
    final cardHeight = size.height * 0.92;
    final center = Offset(size.width / 2, size.height * 0.98);

    for (var i = 0; i < _cardCount; i++) {
      final t = (i - (_cardCount - 1) / 2) / (_cardCount - 1);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(t * 0.54);
      canvas.translate(-cardWidth / 2, -cardHeight);

      final rect = Rect.fromLTWH(0, 0, cardWidth, cardHeight);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      canvas.drawRRect(
        rrect.shift(const Offset(0, 2)),
        Paint()
          ..color = const Color(0x560B0A08)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      canvas.drawRRect(rrect, Paint()..color = LoungeTokens.cardIvory);
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = LoungeTokens.sandLine
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      canvas.restore();
    }

    canvas.drawCircle(
      Offset(size.width * 0.74, size.height * 0.37),
      math.min(size.width, size.height) * 0.08,
      Paint()..color = LoungeTokens.fiftyFlame,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CommandStack extends StatelessWidget {
  const _CommandStack({required this.children});

  final List<_CommandRow> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
        border: Border.all(color: LoungeTokens.sandLine.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                color: LoungeTokens.sandLine.withValues(alpha: 0.18),
              ),
          ],
        ],
      ),
    );
  }
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LoungeTokens.space4,
            vertical: LoungeTokens.space4,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: enabled
                    ? LoungeTokens.goldAccent
                    : LoungeTokens.mutedText,
              ),
              const SizedBox(width: LoungeTokens.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: LoungeTokens.titleSmall.copyWith(
                        fontSize: 15,
                        color: enabled
                            ? LoungeTokens.offWhiteText
                            : LoungeTokens.mutedText,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!, style: LoungeTokens.bodyMuted),
                    ],
                  ],
                ),
              ),
              if (enabled)
                const Icon(Icons.chevron_right, color: LoungeTokens.sandLine),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassicContext extends StatelessWidget {
  const _ClassicContext();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: LoungeTokens.sandLine.withValues(alpha: 0.28)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: LoungeTokens.space5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(
                  Icons.style_outlined,
                  color: LoungeTokens.goldAccent,
                  size: 18,
                ),
                SizedBox(width: LoungeTokens.space2),
                Text(AppStrings.classicModeTitle, style: LoungeTokens.heading),
              ],
            ),
            const SizedBox(height: LoungeTokens.space2),
            const Text(
              AppStrings.classicModeDescription,
              style: LoungeTokens.body,
            ),
          ],
        ),
      ),
    );
  }
}
