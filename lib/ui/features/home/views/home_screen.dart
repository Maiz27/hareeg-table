import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../app/app_routes.dart';
import '../../../../data/persistence/match_repository.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/showcase_card_fan.dart';
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
    return Scaffold(
      backgroundColor: LoungeTokens.feltGreen,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _MenuBackdrop(),
            LayoutBuilder(
              builder: (context, constraints) {
                final horizontalPadding = constraints.maxWidth >= 520
                    ? LoungeTokens.space8
                    : LoungeTokens.space5;
                final shortViewport = constraints.maxHeight < 460;
                final hero = _HeroSection(
                  savedMatch: _savedMatch,
                  loadingSavedMatch: _loadingSavedMatch,
                  onNewGame: () => _openAndRefresh(AppRoutes.newGame),
                  onContinue: _savedMatch == null
                      ? null
                      : () => _openAndRefresh(
                          AppRoutes.table,
                          arguments: _savedMatch,
                        ),
                  onAbandon: _abandonSavedMatch,
                );
                final content = Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    LoungeTokens.space5,
                    horizontalPadding,
                    LoungeTokens.space6,
                  ),
                  child: Column(
                    mainAxisSize: shortViewport
                        ? MainAxisSize.min
                        : MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _BrandHeader(
                        onSettings: () =>
                            Navigator.of(context).pushNamed(AppRoutes.settings),
                        onRulesHelp: () => Navigator.of(
                          context,
                        ).pushNamed(AppRoutes.rulesHelp),
                      ),
                      if (shortViewport) ...[
                        const SizedBox(height: LoungeTokens.space6),
                        hero,
                      ] else
                        Expanded(child: hero),
                    ],
                  ),
                );
                if (shortViewport) {
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: content,
                  );
                }
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(child: content),
                  ),
                );
              },
            ),
          ],
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
  const _BrandHeader({required this.onSettings, required this.onRulesHelp});

  final VoidCallback onSettings;
  final VoidCallback onRulesHelp;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: LoungeTokens.space2),
                child: Text(strings.homeTitle, style: _brandTitle),
              ),
            ),
            const SizedBox(width: LoungeTokens.space2),
            _ChromeIconButton(
              icon: Icons.menu_book_outlined,
              tooltip: strings.rulesHelp,
              onPressed: onRulesHelp,
            ),
            _ChromeIconButton(
              icon: Icons.settings_outlined,
              tooltip: strings.settings,
              onPressed: onSettings,
            ),
          ],
        ),
        const SizedBox(height: LoungeTokens.space3),
        Padding(
          padding: const EdgeInsets.only(right: LoungeTokens.space4),
          child: Text(
            strings.classicModeDescription,
            style: const TextStyle(
              color: LoungeTokens.mutedText,
              fontSize: 14.5,
              height: 1.45,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ],
    );
  }

  static const _brandTitle = TextStyle(
    color: LoungeTokens.offWhiteText,
    fontSize: 34,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.1,
    height: 1.0,
  );
}

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      tooltip: tooltip,
      color: LoungeTokens.mutedText,
      splashRadius: 22,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        foregroundColor: LoungeTokens.mutedText,
        backgroundColor: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.55),
        side: BorderSide(color: LoungeTokens.sandLine.withValues(alpha: 0.18)),
        shape: const CircleBorder(),
        padding: const EdgeInsets.all(LoungeTokens.space2),
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.savedMatch,
    required this.loadingSavedMatch,
    required this.onNewGame,
    required this.onContinue,
    required this.onAbandon,
  });

  final ClassicHareegMatchSnapshot? savedMatch;
  final bool loadingSavedMatch;
  final VoidCallback onNewGame;
  final VoidCallback? onContinue;
  final Future<void> Function() onAbandon;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final hasSavedMatch = savedMatch != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Idle loop keeps the home fan subtly alive while the user is on
        // the menu. Tests opt out by flipping
        // `ShowcaseCardFan.disableLoopingMotionForTesting` so their
        // `pumpAndSettle` calls don't hang on the infinite controller.
        const Center(
          child: ShowcaseCardFan(
            width: 232,
            height: 134,
            motion: ShowcaseFanMotion.idle,
          ),
        ),
        // Extra breathing room between the fan and the action stack so the
        // cards don't visually crowd the New Game button.
        const SizedBox(height: LoungeTokens.space8 + LoungeTokens.space5),
        FilledButton.icon(
          onPressed: onNewGame,
          icon: const Icon(Icons.table_bar_outlined),
          label: Text(strings.newGame),
        ),
        const SizedBox(height: LoungeTokens.space3),
        _ContinueButton(
          enabled: hasSavedMatch,
          loading: loadingSavedMatch,
          onPressed: onContinue,
        ),
        SizedBox(
          height: hasSavedMatch ? LoungeTokens.space2 : LoungeTokens.space5,
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: hasSavedMatch
              ? Align(
                  key: const ValueKey('abandon'),
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    onPressed: onAbandon,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(strings.abandonSavedMatch),
                    style: TextButton.styleFrom(
                      foregroundColor: LoungeTokens.mutedText,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('no-abandon')),
        ),
      ],
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({
    required this.enabled,
    required this.loading,
    required this.onPressed,
  });

  final bool enabled;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final caption = enabled
        ? null
        : (loading ? strings.checkingSavedMatch : strings.noSavedMatch);

    final borderColor = enabled
        ? LoungeTokens.goldAccent.withValues(alpha: 0.6)
        : LoungeTokens.sandLine.withValues(alpha: 0.18);
    final backgroundColor = enabled
        ? LoungeTokens.coffeeCharcoal.withValues(alpha: 0.4)
        : Colors.transparent;
    final foregroundColor = enabled
        ? LoungeTokens.goldAccent
        : LoungeTokens.mutedText.withValues(alpha: 0.55);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(
            Icons.play_circle_outline,
            color: foregroundColor,
            size: 20,
          ),
          label: Text(
            strings.continueGame,
            style: TextStyle(
              color: foregroundColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: foregroundColor,
            disabledForegroundColor: foregroundColor,
            backgroundColor: backgroundColor,
            side: BorderSide(color: borderColor, width: 1.2),
            padding: const EdgeInsets.symmetric(
              horizontal: LoungeTokens.space5,
              vertical: LoungeTokens.space3,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
            ),
            minimumSize: const Size.fromHeight(LoungeTokens.tapTargetPrimary),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: caption == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: LoungeTokens.space2),
                  child: Text(
                    caption,
                    textAlign: TextAlign.center,
                    style: LoungeTokens.bodyMuted.copyWith(
                      fontSize: 12,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
