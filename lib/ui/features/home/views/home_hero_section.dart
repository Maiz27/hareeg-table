import 'package:flutter/material.dart';

import '../../../../data/persistence/match_repository.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/showcase_card_fan.dart';
import '../../../core/theme/lounge_tokens.dart';

/// The menu body under the brand header: the card-fan stage, the adaptive
/// New Game / Continue pair, and the practice, history and statistics tiles.
class HomeHeroSection extends StatelessWidget {
  /// Creates the hero section.
  const HomeHeroSection({
    super.key,
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
