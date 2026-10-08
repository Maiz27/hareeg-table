import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../app/app_routes.dart';
import '../../../../data/persistence/match_history_repository.dart';
import '../../../../data/persistence/match_repository.dart';
import '../../../../domain/classic_hareeg/history/match_history_outcomes.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/theme/lounge_tokens.dart';
import 'home_hero_section.dart';

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
                final hero = HomeHeroSection(
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
