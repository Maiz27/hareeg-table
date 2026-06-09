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
///
/// Because the table is landscape-locked, the panel spreads into the width:
/// settings sit in a scrollable left column while Resume / Report / Leave live
/// in a pinned right rail that never scrolls, so the primary affordances stay
/// put and the settings stop cramming vertically. On a very narrow landscape
/// the layout folds back to a single column with the action row beneath.
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
    required this.onReportTableIssue,
    required this.onLeave,
    this.showCoachingTips = false,
    this.coachingTipsEnabled = false,
    this.onCoachingTipsChanged,
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
  final VoidCallback onReportTableIssue;
  final VoidCallback onLeave;

  /// Whether to show the "Coaching tips" toggle. True only on the coaching
  /// tier, where proactive hints are available.
  final bool showCoachingTips;

  /// Current state of the coaching-tips preference.
  final bool coachingTipsEnabled;

  /// Called when the coaching-tips toggle changes. Null when not shown.
  final ValueChanged<bool>? onCoachingTipsChanged;

  /// Below this content width the two-column layout would squeeze the settings
  /// and the action rail too tightly, so the panel folds to a single column.
  static const double _twoColumnMinWidth = 560;

  /// Fixed width of the pinned action rail in the two-column layout.
  static const double _railWidth = 248;

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
                child: Padding(
                  // The padding sits outside the absorbing gesture detector so
                  // taps in this margin fall through to the scrim and dismiss
                  // the overlay, even when a wide panel fills the viewport.
                  padding: const EdgeInsets.symmetric(
                    horizontal: LoungeTokens.space4,
                    vertical: LoungeTokens.space3,
                  ),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 820,
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
                            Flexible(
                              fit: FlexFit.loose,
                              child: LayoutBuilder(
                                builder: (context, bodyConstraints) {
                                  final twoColumn =
                                      bodyConstraints.maxWidth >=
                                      _twoColumnMinWidth;
                                  return twoColumn
                                      ? _TwoColumnBody(
                                          settings: _settingsList(strings),
                                          actions: _ActionRail(
                                            strings: strings,
                                            onResume: onResume,
                                            onReportTableIssue:
                                                onReportTableIssue,
                                            onLeave: onLeave,
                                          ),
                                          highContrast: highContrastCards,
                                        )
                                      : _SingleColumnBody(
                                          settings: _settingsList(strings),
                                          strings: strings,
                                          onResume: onResume,
                                          onReportTableIssue: onReportTableIssue,
                                          onLeave: onLeave,
                                        );
                                },
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

  /// The ergonomic settings, shared by both the two-column and single-column
  /// layouts. Spacing carries the grouping — a quiet rhythm rather than a stack
  /// of full-width rules — so the list reads calmly instead of cramped.
  Widget _settingsList(AppStrings strings) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showCoachingTips && onCoachingTipsChanged != null) ...[
          _OverlayToggle(
            icon: Icons.assistant_direction_outlined,
            title: strings.coachingTips,
            subtitle: strings.coachingTipsDescription,
            value: coachingTipsEnabled,
            onChanged: onCoachingTipsChanged!,
          ),
          const _SettingsRule(),
        ],
        _OverlaySection(
          icon: Icons.timer_outlined,
          title: strings.motionSpeedLabel,
          child: SegmentedButton<MotionSpeed>(
            segments: [
              ButtonSegment(
                value: MotionSpeed.normal,
                label: Text(strings.normal),
              ),
              ButtonSegment(value: MotionSpeed.fast, label: Text(strings.fast)),
              ButtonSegment(
                value: MotionSpeed.reduced,
                label: Text(strings.reduced),
              ),
            ],
            selected: {motionSpeed},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                onMotionSpeedChanged(selection.first),
          ),
        ),
        const SizedBox(height: LoungeTokens.space4),
        _OverlayToggle(
          icon: Icons.speed_outlined,
          title: strings.fastCpuTurns,
          subtitle: strings.fastCpuTurnsDescription,
          value: fastCpuTurns,
          onChanged: onFastCpuTurnsChanged,
        ),
        const SizedBox(height: LoungeTokens.space4),
        _OverlayToggle(
          icon: Icons.contrast_outlined,
          title: strings.highContrastCards,
          subtitle: strings.highContrastCardsDescription,
          value: highContrastCards,
          onChanged: onHighContrastCardsChanged,
        ),
        const SizedBox(height: LoungeTokens.space4),
        _OverlayToggle(
          icon: Icons.vibration,
          title: strings.hapticsLabel,
          subtitle: strings.hapticsHelp,
          value: hapticsEnabled,
          onChanged: onHapticsChanged,
        ),
        const SizedBox(height: LoungeTokens.space4),
        _OverlayToggle(
          icon: Icons.graphic_eq_outlined,
          title: strings.soundLabel,
          subtitle: strings.soundHelp,
          value: soundEnabled,
          onChanged: onSoundChanged,
        ),
      ],
    );
  }
}

/// Two-column body: a scrollable settings column on the left and a pinned
/// action rail on the right, divided by a quiet sand hairline. Both columns
/// stretch to the same height so the rail's actions stay vertically centred
/// against the settings.
class _TwoColumnBody extends StatelessWidget {
  const _TwoColumnBody({
    required this.settings,
    required this.actions,
    required this.highContrast,
  });

  final Widget settings;
  final Widget actions;
  final bool highContrast;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(right: LoungeTokens.space5),
            child: settings,
          ),
        ),
        Container(
          width: 1,
          color: LoungeTokens.sandLine.withValues(
            alpha: highContrast ? 0.45 : 0.18,
          ),
        ),
        SizedBox(
          width: PauseOverlay._railWidth,
          child: Padding(
            padding: const EdgeInsets.only(left: LoungeTokens.space5),
            child: actions,
          ),
        ),
      ],
    );
  }
}

/// Pinned vertical action rail used in the two-column layout. Resume is the
/// gold hero; Report and Leave sit beneath it as quieter outlined actions.
class _ActionRail extends StatelessWidget {
  const _ActionRail({
    required this.strings,
    required this.onResume,
    required this.onReportTableIssue,
    required this.onLeave,
  });

  final AppStrings strings;
  final VoidCallback onResume;
  final VoidCallback onReportTableIssue;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RailButton(
          icon: Icons.play_arrow,
          label: strings.resumeTable,
          onTap: onResume,
          tone: LoungePanelActionTone.primary,
        ),
        const SizedBox(height: LoungeTokens.space5),
        _RailButton(
          icon: Icons.bug_report_outlined,
          label: strings.reportTableIssue,
          onTap: onReportTableIssue,
          tone: LoungePanelActionTone.neutral,
        ),
        const SizedBox(height: LoungeTokens.space3),
        _RailButton(
          icon: Icons.exit_to_app,
          label: strings.leaveTable,
          onTap: onLeave,
          tone: LoungePanelActionTone.danger,
        ),
      ],
    );
  }
}

/// Full-width rail button. Mirrors the [LoungePanelActions] tone language
/// (gold-filled primary, sand-outlined neutral, deep-red-outlined danger) but
/// stacks vertically for the rail.
class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final LoungePanelActionTone tone;

  @override
  Widget build(BuildContext context) {
    if (tone == LoungePanelActionTone.primary) {
      return FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: LoungeTokens.goldAccent,
          foregroundColor: LoungeTokens.coffeeCharcoal,
          padding: const EdgeInsets.symmetric(
            horizontal: LoungeTokens.space4,
            vertical: LoungeTokens.space4,
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
          ),
        ),
        icon: Icon(icon, size: 20),
        label: Text(label),
      );
    }
    final isDanger = tone == LoungePanelActionTone.danger;
    final accent = isDanger ? LoungeTokens.deepRed : LoungeTokens.sandLine;
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: LoungeTokens.offWhiteText,
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
      icon: Icon(icon, size: 20, color: accent),
      label: Text(label),
    );
  }
}

/// Single-column fallback for very narrow landscapes: scrollable settings with
/// the standard action row pinned beneath them.
class _SingleColumnBody extends StatelessWidget {
  const _SingleColumnBody({
    required this.settings,
    required this.strings,
    required this.onResume,
    required this.onReportTableIssue,
    required this.onLeave,
  });

  final Widget settings;
  final AppStrings strings;
  final VoidCallback onResume;
  final VoidCallback onReportTableIssue;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: SingleChildScrollView(child: settings),
        ),
        const SizedBox(height: LoungeTokens.space4),
        LoungePanelActions(
          primary: LoungePanelAction(
            icon: Icons.play_arrow,
            label: strings.resumeTable,
            onTap: onResume,
            tone: LoungePanelActionTone.primary,
          ),
          tertiary: LoungePanelAction(
            icon: Icons.bug_report_outlined,
            label: strings.reportTableIssue,
            onTap: onReportTableIssue,
            tone: LoungePanelActionTone.neutral,
          ),
          secondary: LoungePanelAction(
            icon: Icons.exit_to_app,
            label: strings.leaveTable,
            onTap: onLeave,
            tone: LoungePanelActionTone.danger,
          ),
        ),
      ],
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

/// Quiet sand hairline used to separate the contextual coaching toggle from the
/// always-available ergonomic settings beneath it.
class _SettingsRule extends StatelessWidget {
  const _SettingsRule();

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
