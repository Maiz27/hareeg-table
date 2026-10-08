import 'package:flutter/material.dart';

import '../../../../data/persistence/preferences_repository.dart';
import '../../../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/motion/motion_speed.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../../replay/widgets/analysis_coach_panel.dart' show verbosityLabel;
import 'settings_labels.dart';

/// Gold-on-felt look shared by the segmented pickers.
final ButtonStyle _segmentedStyle = ButtonStyle(
  backgroundColor: WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.selected)) {
      return LoungeTokens.goldAccent;
    }
    return LoungeTokens.coffeeCharcoal.withValues(alpha: 0.74);
  }),
  foregroundColor: WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.selected)) {
      return LoungeTokens.coffeeCharcoal;
    }
    return LoungeTokens.offWhiteText;
  }),
  side: WidgetStateProperty.all(
    BorderSide(color: LoungeTokens.sandLine.withValues(alpha: 0.42)),
  ),
  textStyle: WidgetStateProperty.all(LoungeTokens.titleSmall),
);

/// Faint rule between the controls inside one settings section.
class SettingsDivider extends StatelessWidget {
  /// Creates a divider.
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: LoungeTokens.space5,
      color: LoungeTokens.sandLine.withValues(alpha: 0.14),
    );
  }
}

/// Labelled dropdown over a fixed list of [values].
class SettingsDropdown<T> extends StatelessWidget {
  /// Creates a dropdown setting.
  const SettingsDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.labelFor,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T value) labelFor;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      dropdownColor: LoungeTokens.coffeeCharcoal,
      items: [
        for (final item in values)
          DropdownMenuItem<T>(value: item, child: Text(labelFor(item))),
      ],
      onChanged: (next) {
        if (next != null) {
          onChanged(next);
        }
      },
    );
  }
}

/// On/off setting with an icon, a title and a one-line explanation.
class SettingsSwitch extends StatelessWidget {
  /// Creates a switch setting.
  const SettingsSwitch({
    super.key,
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
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, color: LoungeTokens.goldAccent),
      title: Text(title, style: LoungeTokens.titleSmall),
      subtitle: Text(subtitle, style: LoungeTokens.bodyMuted),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Radio list of table strictness tiers, locked during an active match.
class StrictnessPicker extends StatelessWidget {
  /// Creates a strictness picker.
  const StrictnessPicker({
    super.key,
    required this.value,
    required this.locked,
    required this.onChanged,
  });

  final TableStrictness value;
  final bool locked;
  final ValueChanged<TableStrictness> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Opacity(
      opacity: locked ? 0.64 : 1,
      child: Column(
        children: [
          for (final tier in TableStrictness.values) ...[
            _RadioRow<TableStrictness>(
              value: tier,
              groupValue: value,
              icon: switch (tier) {
                TableStrictness.coaching => Icons.assistant_direction_outlined,
                TableStrictness.standard => Icons.route_outlined,
                TableStrictness.strict => Icons.gavel_outlined,
                TableStrictness.table => Icons.table_restaurant_outlined,
              },
              title: strings.tableStrictnessLabel(tier),
              subtitle: strings.tableStrictnessDescription(tier),
              onChanged: locked ? null : onChanged,
            ),
            if (tier != TableStrictness.values.last) const SettingsDivider(),
          ],
          if (locked)
            Padding(
              padding: const EdgeInsets.only(top: LoungeTokens.space3),
              child: Text(
                strings.strictnessLockedActiveMatch,
                style: LoungeTokens.bodyMuted,
              ),
            ),
        ],
      ),
    );
  }
}

/// Radio list of the hand sort modes.
class HandSortPicker extends StatelessWidget {
  /// Creates a hand sort picker.
  const HandSortPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final HandSortMode value;
  final ValueChanged<HandSortMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Column(
      children: [
        for (final mode in HandSortMode.values) ...[
          _RadioRow<HandSortMode>(
            value: mode,
            groupValue: value,
            icon: switch (mode) {
              HandSortMode.manual => Icons.drag_indicator,
              HandSortMode.byRank => Icons.sort_outlined,
              HandSortMode.bySuit => Icons.style_outlined,
            },
            title: handSortModeLabel(mode, strings),
            subtitle: _description(mode, strings),
            onChanged: onChanged,
          ),
          if (mode != HandSortMode.values.last) const SettingsDivider(),
        ],
      ],
    );
  }

  static String _description(HandSortMode mode, AppStrings strings) {
    return switch (mode) {
      HandSortMode.manual => strings.sortManualDescription,
      HandSortMode.byRank => strings.sortByRankDescription,
      HandSortMode.bySuit => strings.sortBySuitDescription,
    };
  }
}

class _RadioRow<T> extends StatelessWidget {
  const _RadioRow({
    required this.value,
    required this.groupValue,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  final T value;
  final T groupValue;
  final IconData icon;
  final String title;
  final String subtitle;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    final tap = onChanged;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: tap == null ? null : () => tap(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: LoungeTokens.space2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected
                    ? LoungeTokens.goldAccent
                    : LoungeTokens.mutedText,
              ),
              const SizedBox(width: LoungeTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 17, color: LoungeTokens.sandLine),
                        const SizedBox(width: LoungeTokens.space2),
                        Expanded(
                          child: Text(title, style: LoungeTokens.titleSmall),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle, style: LoungeTokens.bodyMuted),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segmented choice of card motion speed.
class MotionSpeedPicker extends StatelessWidget {
  /// Creates a motion speed picker.
  const MotionSpeedPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final MotionSpeed value;
  final ValueChanged<MotionSpeed> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return SegmentedButton<MotionSpeed>(
      style: _segmentedStyle,
      segments: [
        ButtonSegment(value: MotionSpeed.normal, label: Text(strings.normal)),
        ButtonSegment(value: MotionSpeed.fast, label: Text(strings.fast)),
        ButtonSegment(value: MotionSpeed.reduced, label: Text(strings.reduced)),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

/// Chooses how much the replay analysis coach says.
///
/// Matches the other settings pickers rather than introducing a fourth control
/// idiom on the same screen.
class VerbosityPicker extends StatelessWidget {
  /// Creates a verbosity picker.
  const VerbosityPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final AnalysisVerbosity value;
  final ValueChanged<AnalysisVerbosity> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return SegmentedButton<AnalysisVerbosity>(
      style: _segmentedStyle,
      segments: [
        for (final verbosity in AnalysisVerbosity.values)
          ButtonSegment(
            value: verbosity,
            label: Text(verbosityLabel(strings, verbosity)),
          ),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
