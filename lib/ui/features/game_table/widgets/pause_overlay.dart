import 'package:flutter/material.dart';

import '../../../../l10n/app_strings.dart';
import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/motion/motion_speed.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Landscape pause overlay.
///
/// Table-safe ergonomic controls only (motion speed, CPU pace, card contrast,
/// haptics, sound, resume, leave). Strictness and Opponents are locked at
/// match start — to change them, leave the table and start a new game.
/// Visually anchored to the home menu's coffee-charcoal panel + sand-line
/// border language so pausing reads as the same product, not a stock dialog.
class PauseOverlay extends StatelessWidget {
  /// Creates the pause overlay.
  const PauseOverlay({
    super.key,
    required this.motionSpeed,
    required this.fastCpuTurns,
    required this.hapticsEnabled,
    required this.soundEnabled,
    required this.highContrastCards,
    required this.onMotionSpeedChanged,
    required this.onFastCpuTurnsChanged,
    required this.onHapticsChanged,
    required this.onSoundChanged,
    required this.onHighContrastCardsChanged,
    required this.onResume,
    required this.onLeave,
  });

  /// Current motion speed.
  final MotionSpeed motionSpeed;

  /// Whether CPU turns use shorter pauses.
  final bool fastCpuTurns;

  /// Whether haptics are enabled.
  final bool hapticsEnabled;

  /// Whether sound is enabled.
  final bool soundEnabled;

  /// Whether card faces use the high-contrast accessibility renderer.
  final bool highContrastCards;

  /// Callbacks.
  final ValueChanged<MotionSpeed> onMotionSpeedChanged;
  final ValueChanged<bool> onFastCpuTurnsChanged;
  final ValueChanged<bool> onHapticsChanged;
  final ValueChanged<bool> onSoundChanged;
  final ValueChanged<bool> onHighContrastCardsChanged;
  final VoidCallback onResume;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onResume,
      child: ColoredBox(
        color: highContrastCards
            ? Colors.black.withValues(alpha: 0.72)
            : LoungeTokens.overlayScrim,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxHeight = (constraints.maxHeight - LoungeTokens.space5)
                  .clamp(160.0, constraints.maxHeight);
              return Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LoungeTokens.space4,
                      vertical: LoungeTokens.space3,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 540,
                        maxHeight: maxHeight,
                      ),
                      child: _LoungePanel(
                        highContrast: highContrastCards,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _PanelHeader(
                              icon: Icons.pause_circle_outline,
                              title: strings.pauseTitle,
                              subtitle: strings.pauseInMatchControls,
                              onClose: onResume,
                              closeTooltip: strings.resumeTable,
                            ),
                            const SizedBox(height: LoungeTokens.space4),
                            // Sections scroll if the available height is
                            // tighter than the content (compact Android
                            // landscape). Header and actions stay pinned so
                            // the primary affordances never disappear.
                            Flexible(
                              fit: FlexFit.loose,
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _OverlaySection(
                                      icon: Icons.timer_outlined,
                                      title: strings.motionSpeedLabel,
                                      child: SegmentedButton<MotionSpeed>(
                                        segments: [
                                          ButtonSegment(
                                            value: MotionSpeed.normal,
                                            label: Text(strings.normal),
                                          ),
                                          ButtonSegment(
                                            value: MotionSpeed.fast,
                                            label: Text(strings.fast),
                                          ),
                                          ButtonSegment(
                                            value: MotionSpeed.reduced,
                                            label: Text(strings.reduced),
                                          ),
                                        ],
                                        selected: {motionSpeed},
                                        showSelectedIcon: false,
                                        onSelectionChanged: (selection) =>
                                            onMotionSpeedChanged(
                                              selection.first,
                                            ),
                                      ),
                                    ),
                                    const _PanelDivider(),
                                    _OverlayToggle(
                                      icon: Icons.speed_outlined,
                                      title: strings.fastCpuTurns,
                                      subtitle: strings.fastCpuTurnsDescription,
                                      value: fastCpuTurns,
                                      onChanged: onFastCpuTurnsChanged,
                                    ),
                                    const _PanelDivider(),
                                    _OverlayToggle(
                                      icon: Icons.contrast_outlined,
                                      title: strings.highContrastCards,
                                      subtitle:
                                          strings.highContrastCardsDescription,
                                      value: highContrastCards,
                                      onChanged: onHighContrastCardsChanged,
                                    ),
                                    const _PanelDivider(),
                                    _OverlayToggle(
                                      icon: Icons.vibration,
                                      title: strings.hapticsLabel,
                                      subtitle: strings.hapticsHelp,
                                      value: hapticsEnabled,
                                      onChanged: onHapticsChanged,
                                    ),
                                    const _PanelDivider(),
                                    _OverlayToggle(
                                      icon: Icons.graphic_eq_outlined,
                                      title: strings.soundLabel,
                                      subtitle: strings.soundHelp,
                                      value: soundEnabled,
                                      onChanged: onSoundChanged,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: LoungeTokens.space4),
                            _PanelActions(
                              primary: _PanelAction(
                                icon: Icons.play_arrow,
                                label: strings.resumeTable,
                                onTap: onResume,
                                tone: _ActionTone.primary,
                              ),
                              secondary: _PanelAction(
                                icon: Icons.exit_to_app,
                                label: strings.leaveTable,
                                onTap: onLeave,
                                tone: _ActionTone.danger,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

}

class _LoungePanel extends StatelessWidget {
  const _LoungePanel({required this.highContrast, required this.child});

  final bool highContrast;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: highContrast
              ? Colors.black.withValues(alpha: 0.98)
              : LoungeTokens.coffeeCharcoal.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
          border: Border.all(
            color: highContrast
                ? const Color(0xFFFFD400)
                : LoungeTokens.sandLine.withValues(alpha: 0.32),
            width: highContrast ? 2 : 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
          child: Stack(
            children: [
              // Quiet corner medallion echoes the home menu backdrop so the
              // panel reads as the same product, not a stock dialog.
              Positioned(
                top: -34,
                right: -42,
                child: IgnorePointer(
                  child: SizedBox.square(
                    dimension: 168,
                    child: CustomPaint(
                      painter: const GeometricMotifPainter(
                        variant: LoungeMotifVariant.medallion,
                        opacity: 0.05,
                        strokeWidth: 1.0,
                        density: 4,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(LoungeTokens.space5),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
    required this.closeTooltip,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderBadge(icon: icon),
        const SizedBox(width: LoungeTokens.space4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: LoungeTokens.display.copyWith(fontSize: 22)),
              const SizedBox(height: 4),
              Text(subtitle, style: LoungeTokens.bodyMuted),
            ],
          ),
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close),
          tooltip: closeTooltip,
          color: LoungeTokens.mutedText,
        ),
      ],
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: LoungeTokens.feltRaised,
        borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
        border: Border.all(color: LoungeTokens.sandLine.withValues(alpha: 0.4)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: LoungeTokens.goldAccent, size: 22),
    );
  }
}

class _OverlaySection extends StatelessWidget {
  const _OverlaySection({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: LoungeTokens.goldAccent, size: 18),
            const SizedBox(width: LoungeTokens.space2),
            Text(title, style: LoungeTokens.titleSmall),
          ],
        ),
        const SizedBox(height: LoungeTokens.space3),
        child,
      ],
    );
  }
}

class _OverlayToggle extends StatelessWidget {
  const _OverlayToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: LoungeTokens.goldAccent, size: 18),
        const SizedBox(width: LoungeTokens.space2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: LoungeTokens.titleSmall),
              const SizedBox(height: 2),
              Text(subtitle, style: LoungeTokens.bodyMuted),
            ],
          ),
        ),
        const SizedBox(width: LoungeTokens.space3),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: LoungeTokens.goldAccent,
          activeTrackColor: LoungeTokens.goldAccent.withValues(alpha: 0.45),
          inactiveThumbColor: LoungeTokens.mutedText,
          inactiveTrackColor: LoungeTokens.feltRaised,
        ),
      ],
    );
  }
}

class _PanelDivider extends StatelessWidget {
  const _PanelDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LoungeTokens.space4),
      child: Divider(
        height: 1,
        thickness: 1,
        color: LoungeTokens.sandLine.withValues(alpha: 0.18),
      ),
    );
  }
}

enum _ActionTone { primary, danger }

class _PanelAction {
  const _PanelAction({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final _ActionTone tone;
}

class _PanelActions extends StatelessWidget {
  const _PanelActions({required this.primary, required this.secondary});

  final _PanelAction primary;
  final _PanelAction secondary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _buildAction(primary, isPrimary: true)),
        const SizedBox(width: LoungeTokens.space3),
        Expanded(child: _buildAction(secondary, isPrimary: false)),
      ],
    );
  }

  Widget _buildAction(_PanelAction action, {required bool isPrimary}) {
    if (isPrimary) {
      return FilledButton.icon(
        onPressed: action.onTap,
        style: FilledButton.styleFrom(
          backgroundColor: LoungeTokens.goldAccent,
          foregroundColor: LoungeTokens.coffeeCharcoal,
          padding: const EdgeInsets.symmetric(
            horizontal: LoungeTokens.space4,
            vertical: LoungeTokens.space3,
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
          ),
        ),
        icon: Icon(action.icon, size: 20),
        label: Text(action.label),
      );
    }
    final isDanger = action.tone == _ActionTone.danger;
    final accent = isDanger ? LoungeTokens.deepRed : LoungeTokens.sandLine;
    return OutlinedButton.icon(
      onPressed: action.onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: isDanger
            ? LoungeTokens.offWhiteText
            : LoungeTokens.offWhiteText,
        side: BorderSide(color: accent.withValues(alpha: 0.55)),
        padding: const EdgeInsets.symmetric(
          horizontal: LoungeTokens.space4,
          vertical: LoungeTokens.space3,
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
        ),
      ),
      icon: Icon(action.icon, size: 20, color: accent),
      label: Text(action.label),
    );
  }
}
