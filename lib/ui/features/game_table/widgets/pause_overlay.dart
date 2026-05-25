import 'package:flutter/material.dart';

import '../../../../l10n/app_strings.dart';
import '../../../core/motion/motion_speed.dart';
import '../../../core/panels/lounge_panel.dart';
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
                      child: LoungePanel(
                        highContrast: highContrastCards,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            LoungePanelHeader(
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
                            LoungePanelActions(
                              primary: LoungePanelAction(
                                icon: Icons.play_arrow,
                                label: strings.resumeTable,
                                onTap: onResume,
                                tone: LoungePanelActionTone.primary,
                              ),
                              secondary: LoungePanelAction(
                                icon: Icons.exit_to_app,
                                label: strings.leaveTable,
                                onTap: onLeave,
                                tone: LoungePanelActionTone.danger,
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
