import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../app/app_routes.dart';
import '../../../../data/persistence/match_history_repository.dart';
import '../../../../data/persistence/match_repository.dart';
import '../../../../domain/classic_hareeg/history/match_history_outcomes.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/showcase_card_fan.dart';
import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Main menu and navigation shell.
class HomeScreen extends StatefulWidget {
  /// Creates the main menu.
  const HomeScreen({
    required this.matchRepository,
    required this.historyRepository,
    super.key,
  });

  /// Active match persistence.
  final MatchRepository matchRepository;

  /// Completed-match history.
  ///
  /// Consulted on load so an archive interrupted by a crash finishes before a
  /// terminal checkpoint could be offered as a game to continue.
  final MatchHistoryRepository historyRepository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  MatchCheckpoint? _savedMatch;
  var _loadingSavedMatch = true;
  var _recoveryFailed = false;
  var _damagedSave = false;

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
                  onNewGame: _requestNewGame,
                  onContinue: _savedMatch == null
                      ? null
                      : () => _openAndRefresh(
                          AppRoutes.table,
                          arguments: _savedMatch,
                        ),
                  onAbandon: _abandonSavedMatch,
                  onDiscardDamaged: _damagedSave
                      ? _confirmDiscardDamaged
                      : null,
                  onPractice: () =>
                      Navigator.of(context).pushNamed(AppRoutes.practice),
                  onHistory: () =>
                      Navigator.of(context).pushNamed(AppRoutes.history),
                  onStatistics: () =>
                      Navigator.of(context).pushNamed(AppRoutes.statistics),
                  // Half of a narrow screen leaves too little room for the
                  // History label, which would ellipsize rather than wrap.
                  stackSecondaryActions:
                      constraints.maxWidth - horizontalPadding * 2 < 340,
                  tilesAcross:
                      constraints.maxWidth - horizontalPadding * 2 >= 330,
                  heroHeight: _heroHeight(
                    constraints,
                    horizontalPadding: horizontalPadding,
                    short: shortViewport,
                  ),
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

  /// Card-fan stage height: about a third of a tall screen, never wider
  /// than the content column allows for the fan's aspect.
  static double _heroHeight(
    BoxConstraints constraints, {
    required double horizontalPadding,
    required bool short,
  }) {
    if (short) return 150;
    final byWidth =
        (constraints.maxWidth - horizontalPadding * 2) / 1.75 / 0.85;
    final byHeight = constraints.maxHeight * 0.3;
    return (byWidth < byHeight ? byWidth : byHeight).clamp(150.0, 280.0);
  }

  Future<void> _loadSavedMatch() async {
    if (mounted) setState(() => _loadingSavedMatch = true);
    MatchCheckpoint? savedMatch;
    var recoveryFailed = false;
    var damagedSave = false;

    // Finish any archive interrupted by a crash before deciding what is
    // resumable, so a completed-but-unpublished match is published here rather
    // than offered as a game to continue.
    //
    // Failing to recover must not stop the menu loading the resumable match:
    // the pending record survives for the next launch, whereas hiding Continue
    // would look to the player like their game had been lost.
    try {
      recoveryFailed =
          await widget.historyRepository.recoverPendingArchive()
              is MatchArchivePublishFailed;
    } catch (error, stackTrace) {
      recoveryFailed = true;
      debugPrint('Failed to recover a pending archive: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    try {
      final outcome = await widget.matchRepository.loadActiveMatch();
      damagedSave =
          outcome is ActiveMatchUnreadable &&
          outcome.failure.kind == MatchHistoryFailureKind.corrupt;
      if (outcome is ActiveMatchUnreadable ||
          (outcome is ActiveMatchLoaded && outcome.checkpoint.isTerminal)) {
        recoveryFailed = true;
      }
      if (outcome is ActiveMatchLoaded && !outcome.checkpoint.isTerminal) {
        savedMatch = outcome.checkpoint;
      }
    } catch (error, stackTrace) {
      recoveryFailed = true;
      debugPrint('Failed to load saved match: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _savedMatch = savedMatch;
      _recoveryFailed = recoveryFailed;
      _damagedSave = damagedSave;
      _loadingSavedMatch = false;
    });
  }

  Future<void> _requestNewGame() async {
    if (_loadingSavedMatch) return;
    await _loadSavedMatch();
    if (!mounted) return;
    if (_recoveryFailed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _damagedSave
                ? context.strings.discardDamagedSaveWarning
                : context.strings.archiveRecoveryRequired,
          ),
          action: SnackBarAction(
            label: _damagedSave
                ? context.strings.discardDamagedSave
                : context.strings.historyRetry,
            onPressed: _damagedSave ? _confirmDiscardDamaged : _loadSavedMatch,
          ),
        ),
      );
      return;
    }
    await _openAndRefresh(AppRoutes.newGame);
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

  Future<void> _confirmDiscardDamaged() async {
    final strings = context.strings;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.discardDamagedSave),
        content: Text(strings.discardDamagedSaveWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.historyCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.abandonSavedMatch),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      await widget.matchRepository.abandonActiveMatch();
    } catch (error, stackTrace) {
      debugPrint('Failed to discard damaged save: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.couldNotDiscardSave)));
      }
    }
    if (mounted) await _loadSavedMatch();
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

  static final _brandTitle = LoungeTokens.displayLarge.copyWith(
    fontSize: 36,
    height: 1.05,
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
    this.onDiscardDamaged,
    required this.onPractice,
    required this.onHistory,
    required this.onStatistics,
    required this.stackSecondaryActions,
    required this.tilesAcross,
    required this.heroHeight,
  });

  final MatchCheckpoint? savedMatch;
  final bool loadingSavedMatch;
  final VoidCallback onNewGame;
  final VoidCallback? onContinue;
  final Future<void> Function() onAbandon;
  final VoidCallback? onDiscardDamaged;
  final VoidCallback onPractice;
  final VoidCallback onHistory;
  final VoidCallback onStatistics;

  /// Whether History and Statistics must stack instead of sharing a row.
  ///
  /// Decided by the caller from the real available width, because this widget
  /// sits inside an [IntrinsicHeight] and a [LayoutBuilder] here would throw
  /// when the column computes its intrinsic dimensions.
  final bool stackSecondaryActions;

  /// Whether practice, history, and stats fit as three tiles in one row.
  final bool tilesAcross;

  /// Height of the card-fan stage.
  final double heroHeight;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final hasSavedMatch = savedMatch != null;

    // Design contract 9.2: one primary action that adapts. A saved match
    // makes Continue the gold call to action and New Game the alternative;
    // otherwise New Game leads and Continue waits, disabled, underneath.
    final newGame = hasSavedMatch
        ? _OutlinedAction(
            icon: Icons.table_bar_outlined,
            label: strings.newGame,
            onPressed: loadingSavedMatch ? null : onNewGame,
          )
        : FilledButton.icon(
            onPressed: loadingSavedMatch ? null : onNewGame,
            icon: const Icon(Icons.table_bar_outlined),
            label: Text(strings.newGame),
          );
    final continueGame = hasSavedMatch
        ? FilledButton.icon(
            onPressed: onContinue,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(strings.continueGame),
          )
        : const _DisabledContinueButton();

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Idle loop keeps the home fan subtly alive while the user is on
        // the menu. Tests opt out by flipping
        // `ShowcaseCardFan.disableLoopingMotionForTesting` so their
        // `pumpAndSettle` calls don't hang on the infinite controller.
        _HeroStage(height: heroHeight),
        const SizedBox(height: LoungeTokens.space5),
        if (hasSavedMatch) ...[
          continueGame,
          const SizedBox(height: LoungeTokens.space3),
          newGame,
        ] else ...[
          newGame,
          const SizedBox(height: LoungeTokens.space3),
          continueGame,
        ],
        const SizedBox(height: LoungeTokens.space5),
        const _MotifDivider(),
        const SizedBox(height: LoungeTokens.space4),
        // Places to learn and to look back, one tier below play: tiles in a
        // row where three fit, otherwise practice gets its own row. Below a
        // narrow threshold the history / stats pair stacks as well, because
        // a clipped label is worse than a taller menu.
        Builder(
          builder: (context) {
            final practice = _MenuTile(
              icon: Icons.school_outlined,
              label: strings.practiceTitle,
              onPressed: onPractice,
            );
            final history = _MenuTile(
              icon: Icons.history,
              label: strings.historyMenuLabel,
              onPressed: onHistory,
            );
            final stats = _MenuTile(
              icon: Icons.insights_outlined,
              label: strings.statisticsMenuLabel,
              onPressed: onStatistics,
            );
            const gap = SizedBox.square(dimension: LoungeTokens.space2);
            if (tilesAcross) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: practice),
                    gap,
                    Expanded(child: history),
                    gap,
                    Expanded(child: stats),
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                practice,
                gap,
                if (stackSecondaryActions) ...[
                  history,
                  gap,
                  stats,
                ] else
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: history),
                        gap,
                        Expanded(child: stats),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        SizedBox(
          height: hasSavedMatch ? LoungeTokens.space2 : LoungeTokens.space4,
        ),
        // One status slot under the stack: the abandon action when a match
        // is saved, otherwise the caption explaining the disabled Continue.
        AnimatedSwitcher(
          duration: LoungeTokens.motionStandard,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: onDiscardDamaged != null
              ? TextButton.icon(
                  onPressed: onDiscardDamaged,
                  icon: const Icon(Icons.warning_amber),
                  label: Text(strings.discardDamagedSave),
                )
              : hasSavedMatch
              ? Align(
                  key: const ValueKey('abandon'),
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    onPressed: onAbandon,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(strings.abandonSavedMatch),
                    style: TextButton.styleFrom(
                      foregroundColor: LoungeTokens.mutedText,
                      textStyle: LoungeTokens.titleSmall.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                )
              : Text(
                  key: const ValueKey('no-match-caption'),
                  loadingSavedMatch
                      ? strings.checkingSavedMatch
                      : strings.noSavedMatch,
                  textAlign: TextAlign.center,
                  style: LoungeTokens.bodyMuted.copyWith(
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
        ),
      ],
    );
  }
}

/// The card fan resting on a pool of lamp light on the felt, with the faint
/// outline of the table's edge beneath it.
class _HeroStage extends StatelessWidget {
  const _HeroStage({required this.height});

  /// Stage height; the fan scales with it so tall phones aren't left with
  /// an empty band above a small fan.
  final double height;

  @override
  Widget build(BuildContext context) {
    final fanHeight = height * 0.85;
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _HeroStagePainter()),
            ),
          ),
          ShowcaseCardFan(
            width: fanHeight * 1.75,
            height: fanHeight,
            motion: ShowcaseFanMotion.idle,
          ),
        ],
      ),
    );
  }
}

class _HeroStagePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.56);
    final pool = Rect.fromCenter(
      center: center,
      width: size.width * 1.05,
      height: size.height * 1.05,
    );
    canvas.drawOval(
      pool,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFD99A).withValues(alpha: 0.16),
            LoungeTokens.goldAccent.withValues(alpha: 0.05),
            Colors.transparent,
          ],
          stops: const [0, 0.5, 1],
        ).createShader(pool),
    );
    // The table edge: two concentric ellipses, rail and brass inlay.
    final edge = Rect.fromCenter(
      center: center.translate(0, size.height * 0.16),
      width: size.width * 0.92,
      height: size.height * 0.42,
    );
    canvas.drawOval(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = LoungeTokens.sandLine.withValues(alpha: 0.14),
    );
    canvas.drawOval(
      edge.inflate(7),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.black.withValues(alpha: 0.07),
    );
  }

  @override
  bool shouldRepaint(covariant _HeroStagePainter oldDelegate) => false;
}

/// A sand hairline broken by a small diamond: the lounge's section break.
class _MotifDivider extends StatelessWidget {
  const _MotifDivider();

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Container(
        height: 1,
        color: LoungeTokens.sandLine.withValues(alpha: 0.18),
      ),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: LoungeTokens.space3),
          child: Transform.rotate(
            angle: 0.785398,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                border: Border.all(
                  color: LoungeTokens.sandLine.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
        ),
        line,
      ],
    );
  }
}

/// Secondary full-width action (New Game while a match is saved).
class _OutlinedAction extends StatelessWidget {
  const _OutlinedAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: LoungeTokens.offWhiteText,
        backgroundColor: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.35),
        side: BorderSide(color: LoungeTokens.sandLine.withValues(alpha: 0.4)),
        minimumSize: const Size.fromHeight(LoungeTokens.tapTargetPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
        ),
        textStyle: LoungeTokens.title,
      ),
    );
  }
}

/// A tile for a place to go: icon over label on a raised lounge surface.
class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: LoungeTokens.offWhiteText,
        backgroundColor: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.42),
        side: BorderSide(color: LoungeTokens.sandLine.withValues(alpha: 0.2)),
        padding: const EdgeInsets.symmetric(
          horizontal: LoungeTokens.space2,
          vertical: LoungeTokens.space3,
        ),
        minimumSize: const Size.fromHeight(66),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusButton + 2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: LoungeTokens.goldAccent),
          const SizedBox(height: LoungeTokens.space2),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: LoungeTokens.titleSmall.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: LoungeTokens.offWhiteText.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }
}

/// Continue, shown disabled under New Game while there is no saved match.
class _DisabledContinueButton extends StatelessWidget {
  const _DisabledContinueButton();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    final borderColor = LoungeTokens.sandLine.withValues(alpha: 0.18);
    const backgroundColor = Colors.transparent;
    final foregroundColor = LoungeTokens.mutedText.withValues(alpha: 0.55);

    return OutlinedButton.icon(
      onPressed: null,
      icon: Icon(Icons.play_circle_outline, color: foregroundColor, size: 20),
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
          fontFamily: LoungeTokens.uiFamily,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
