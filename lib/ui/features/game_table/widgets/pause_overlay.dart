import 'package:flutter/material.dart';

import '../../../../l10n/app_strings.dart';
import '../../../core/aids/table_aids.dart';
import '../../../core/motion/motion_speed.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Landscape pause overlay.
///
/// Table-safe controls only (motion speed, aids, haptics, sound, resume,
/// leave). The full settings surface lives in the main-menu Settings route.
class PauseOverlay extends StatelessWidget {
  /// Creates the pause overlay.
  const PauseOverlay({
    super.key,
    required this.aids,
    required this.motionSpeed,
    required this.hapticsEnabled,
    required this.soundEnabled,
    required this.onAidsChanged,
    required this.onMotionSpeedChanged,
    required this.onHapticsChanged,
    required this.onSoundChanged,
    required this.onResume,
    required this.onLeave,
  });

  /// Current aid level.
  final TableAids aids;

  /// Current motion speed.
  final MotionSpeed motionSpeed;

  /// Whether haptics are enabled.
  final bool hapticsEnabled;

  /// Whether sound is enabled.
  final bool soundEnabled;

  /// Callbacks.
  final ValueChanged<TableAids> onAidsChanged;
  final ValueChanged<MotionSpeed> onMotionSpeedChanged;
  final ValueChanged<bool> onHapticsChanged;
  final ValueChanged<bool> onSoundChanged;
  final VoidCallback onResume;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onResume,
      child: ColoredBox(
        color: LoungeTokens.overlayScrim,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Material(
                color: LoungeTokens.coffeeCharcoal,
                borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(LoungeTokens.space5),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                AppStrings.pauseTitle,
                                style: LoungeTokens.heading,
                              ),
                            ),
                            IconButton(
                              onPressed: onResume,
                              icon: const Icon(Icons.close),
                              tooltip: AppStrings.resumeTable,
                            ),
                          ],
                        ),
                        const SizedBox(height: LoungeTokens.space2),
                        const Text(
                          AppStrings.pauseInMatchControls,
                          style: LoungeTokens.bodyMuted,
                        ),
                        const SizedBox(height: LoungeTokens.space4),
                        _Section(
                          title: AppStrings.aidsLabel,
                          child: SegmentedButton<TableAids>(
                            segments: [
                              for (final aid in TableAids.values)
                                ButtonSegment(
                                  value: aid,
                                  label: Text(aid.label),
                                ),
                            ],
                            selected: {aids},
                            onSelectionChanged: (selection) =>
                                onAidsChanged(selection.first),
                          ),
                        ),
                        _Section(
                          title: AppStrings.motionSpeedLabel,
                          child: SegmentedButton<MotionSpeed>(
                            segments: const [
                              ButtonSegment(
                                value: MotionSpeed.normal,
                                label: Text('Normal'),
                              ),
                              ButtonSegment(
                                value: MotionSpeed.fast,
                                label: Text('Fast'),
                              ),
                              ButtonSegment(
                                value: MotionSpeed.reduced,
                                label: Text('Reduced'),
                              ),
                            ],
                            selected: {motionSpeed},
                            onSelectionChanged: (selection) =>
                                onMotionSpeedChanged(selection.first),
                          ),
                        ),
                        _ToggleSection(
                          title: AppStrings.hapticsLabel,
                          subtitle: AppStrings.hapticsHelp,
                          value: hapticsEnabled,
                          onChanged: onHapticsChanged,
                        ),
                        _ToggleSection(
                          title: AppStrings.soundLabel,
                          subtitle: AppStrings.soundHelp,
                          value: soundEnabled,
                          onChanged: onSoundChanged,
                        ),
                        const SizedBox(height: LoungeTokens.space3),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: onResume,
                                icon: const Icon(Icons.play_arrow),
                                label: const Text(AppStrings.resumeTable),
                              ),
                            ),
                            const SizedBox(width: LoungeTokens.space2),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: onLeave,
                                icon: const Icon(Icons.exit_to_app),
                                label: const Text(AppStrings.leaveTable),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LoungeTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: LoungeTokens.titleSmall),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _ToggleSection extends StatelessWidget {
  const _ToggleSection({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LoungeTokens.space2),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: LoungeTokens.titleSmall),
        subtitle: Text(subtitle, style: LoungeTokens.bodyMuted),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
