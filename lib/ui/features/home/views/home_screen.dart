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
    this.onDiscardDamaged,
    required this.onPractice,
    required this.onHistory,
    required this.onStatistics,
    required this.stackSecondaryActions,
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
          onPressed: loadingSavedMatch ? null : onNewGame,
          icon: const Icon(Icons.table_bar_outlined),
          label: Text(strings.newGame),
        ),
        const SizedBox(height: LoungeTokens.space3),
        _ContinueButton(enabled: hasSavedMatch, onPressed: onContinue),
        const SizedBox(height: LoungeTokens.space3),
        // Third member of the action stack: same full-width shape as the
        // buttons above, one emphasis tier down (muted instead of gold), so
        // play -> resume -> learn reads as one column.
        OutlinedButton.icon(
          onPressed: onPractice,
          icon: const Icon(Icons.school_outlined, size: 20),
          label: Text(strings.practiceTitle),
          style: OutlinedButton.styleFrom(
            foregroundColor: LoungeTokens.mutedText,
            side: BorderSide(
              color: LoungeTokens.sandLine.withValues(alpha: 0.28),
              width: 1.2,
            ),
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
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(height: LoungeTokens.space3),
        // Secondary row, one emphasis tier below the play/resume/learn stack:
        // these are places to look back at finished matches, not ways to start
        // one. Side by side rather than two more full-width buttons so the
        // hero column still fits a short viewport.
        //
        // Below a narrow threshold the pair stacks instead. Half of a 320-wide
        // screen leaves roughly 86 logical pixels for a label, and "History"
        // alone needs about 97 — side by side there, it would ellipsize. A
        // clipped label is worse than a taller menu.
        if (stackSecondaryActions)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SecondaryAction(
                icon: Icons.history,
                label: strings.historyMenuLabel,
                onPressed: onHistory,
              ),
              const SizedBox(height: LoungeTokens.space2),
              _SecondaryAction(
                icon: Icons.insights_outlined,
                label: strings.statisticsMenuLabel,
                onPressed: onStatistics,
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: _SecondaryAction(
                  icon: Icons.history,
                  label: strings.historyMenuLabel,
                  onPressed: onHistory,
                ),
              ),
              const SizedBox(width: LoungeTokens.space2),
              Expanded(
                child: _SecondaryAction(
                  icon: Icons.insights_outlined,
                  label: strings.statisticsMenuLabel,
                  onPressed: onStatistics,
                ),
              ),
            ],
          ),
        SizedBox(
          height: hasSavedMatch ? LoungeTokens.space2 : LoungeTokens.space4,
        ),
        // One status slot under the stack: the abandon action when a match
        // is saved, otherwise the caption explaining the disabled Continue.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
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
                      textStyle: const TextStyle(
                        fontSize: 13,
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

/// Compact secondary menu control.
///
/// Sized from [LoungeTokens.tapTargetCardShort] rather than the primary
/// 48-pixel target: one tier down in emphasis, still comfortably tappable.
/// [Text.softWrap] is off and the style is fixed so the label's fit can be
/// measured rather than assumed.
class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1),
      style: OutlinedButton.styleFrom(
        foregroundColor: LoungeTokens.mutedText,
        side: BorderSide(color: LoungeTokens.sandLine.withValues(alpha: 0.22)),
        padding: const EdgeInsets.symmetric(
          horizontal: LoungeTokens.space3,
          vertical: LoungeTokens.space2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
        ),
        minimumSize: const Size.fromHeight(LoungeTokens.tapTargetCardShort),
        textStyle: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    final borderColor = enabled
        ? LoungeTokens.goldAccent.withValues(alpha: 0.6)
        : LoungeTokens.sandLine.withValues(alpha: 0.18);
    final backgroundColor = enabled
        ? LoungeTokens.coffeeCharcoal.withValues(alpha: 0.4)
        : Colors.transparent;
    final foregroundColor = enabled
        ? LoungeTokens.goldAccent
        : LoungeTokens.mutedText.withValues(alpha: 0.55);

    return OutlinedButton.icon(
      onPressed: onPressed,
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
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }
}
