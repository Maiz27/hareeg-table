import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../app/app_routes.dart';
import '../../../../data/persistence/preferences_repository.dart';
import '../../../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/aids/table_aids.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/motion/motion_speed.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../../../core/theme/table_surface_theme.dart';
import 'card_theme_preview.dart';

/// Settings screen.
///
/// Receives prefs and a setter so the app shell can update [MotionScope] /
/// [AidsScope] / [CardThemeScope] / [HapticsScope] immediately when the user
/// toggles them. The screen itself is a thin form - it does not own any of
/// those scopes.
class SettingsScreen extends StatefulWidget {
  /// Creates the settings screen.
  const SettingsScreen({
    super.key,
    required this.preferences,
    required this.onUpdate,
    required this.cardThemes,
    required this.isMatchActive,
  });

  /// Current preferences (driven by the app shell).
  final GamePreferences preferences;

  /// Called when the user changes a preference.
  final ValueChanged<GamePreferences> onUpdate;

  /// Available card themes shown in the picker.
  final List<HareegCardTheme> cardThemes;

  /// True when a match is in progress; some controls (card theme) are locked
  /// in that case.
  final bool isMatchActive;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    AppOrientation.usePortrait();
  }

  GamePreferences get _preferences => widget.preferences;

  void _save(GamePreferences next) => widget.onUpdate(next);

  @override
  Widget build(BuildContext context) {
    final selectedTheme = widget.cardThemes.firstWhere(
      (theme) => theme.id == _preferences.cardThemeId,
      orElse: () => widget.cardThemes.first,
    );

    return Scaffold(
      backgroundColor: LoungeTokens.feltGreen,
      appBar: AppBar(title: const Text(AppStrings.settingsTitle)),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _SettingsBackdrop(),
            ListView(
              padding: const EdgeInsets.fromLTRB(
                LoungeTokens.space5,
                LoungeTokens.space5,
                LoungeTokens.space5,
                LoungeTokens.space8 * 4,
              ),
              children: [
                _SettingsIntro(
                  aids: _preferences.tableAids,
                  themeLabel: selectedTheme.label,
                ),
                const _SectionBreak(),
                _SettingsSection(
                  title: 'Match defaults',
                  subtitle: 'Used when a new Classic table is created.',
                  icon: Icons.tune_outlined,
                  children: [
                    _DropdownSetting<CpuDifficulty>(
                      label: 'CPU difficulty',
                      value: _preferences.setup.cpuDifficulty,
                      values: CpuDifficulty.values,
                      labelFor: (value) => value.label,
                      onChanged: (value) => _save(
                        _preferences.copyWith(
                          setup: _preferences.setup.copyWith(
                            cpuDifficulty: value,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: LoungeTokens.space4),
                    _DropdownSetting<RulePreset>(
                      label: 'Rule preset',
                      value: _preferences.setup.rulePreset,
                      values: RulePreset.values,
                      labelFor: (value) => value.label,
                      onChanged: (value) => _save(
                        _preferences.copyWith(
                          setup: _preferences.setup.copyWith(rulePreset: value),
                        ),
                      ),
                    ),
                    const SizedBox(height: LoungeTokens.space4),
                    _DropdownSetting<int>(
                      label: 'Opening requirement',
                      value: _preferences.setup.openingRequirement,
                      values: const [51, 75],
                      labelFor: (value) => '$value',
                      onChanged: (value) => _save(
                        _preferences.copyWith(
                          setup: _preferences.setup.copyWith(
                            openingRequirement: value,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: LoungeTokens.space4),
                    _DropdownSetting<int>(
                      label: 'Deck count',
                      value: _preferences.setup.deckCount,
                      values: const [2, 3, 4],
                      labelFor: (value) => '$value decks',
                      onChanged: (value) => _save(
                        _preferences.copyWith(
                          setup: _preferences.setup.copyWith(deckCount: value),
                        ),
                      ),
                    ),
                    const SizedBox(height: LoungeTokens.space4),
                    _DropdownSetting<int>(
                      label: 'Jokers',
                      value: _preferences.setup.jokerCount,
                      values: const [0, 1, 2, 3, 4],
                      labelFor: (value) => '$value',
                      onChanged: (value) => _save(
                        _preferences.copyWith(
                          setup: _preferences.setup.copyWith(jokerCount: value),
                        ),
                      ),
                    ),
                    const SizedBox(height: LoungeTokens.space4),
                    _DropdownSetting<int>(
                      label: 'Fifty timer',
                      value: _preferences.setup.fiftyTimerSeconds,
                      values: const [2, 3, 4, 5, 6],
                      labelFor: (value) => '${value}s',
                      onChanged: (value) => _save(
                        _preferences.copyWith(
                          setup: _preferences.setup.copyWith(
                            fiftyTimerSeconds: value,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const _SectionBreak(),
                _SettingsSection(
                  title: AppStrings.aidsLabel,
                  subtitle: AppStrings.aidsHelp,
                  icon: Icons.visibility_outlined,
                  children: [
                    _AidsPicker(
                      value: _preferences.tableAids,
                      onChanged: (value) =>
                          _save(_preferences.copyWith(tableAids: value)),
                    ),
                  ],
                ),
                const _SectionBreak(),
                _SettingsSection(
                  title: 'Language',
                  subtitle: 'English ships first; Arabic is already planned.',
                  icon: Icons.language_outlined,
                  children: [
                    _DropdownSetting<AppLanguage>(
                      label: 'Language',
                      value: _preferences.language,
                      values: AppLanguage.values,
                      labelFor: (value) => value.label,
                      onChanged: (value) =>
                          _save(_preferences.copyWith(language: value)),
                    ),
                  ],
                ),
                const _SectionBreak(),
                _SettingsSection(
                  title: 'Motion, sound & feel',
                  subtitle: 'Fast feedback without idle animation loops.',
                  icon: Icons.touch_app_outlined,
                  children: [
                    _MotionSpeedPicker(
                      value: _preferences.motionSpeed,
                      onChanged: (value) => _save(
                        _preferences.copyWith(
                          motionSpeed: value,
                          reducedMotion: value == MotionSpeed.reduced,
                        ),
                      ),
                    ),
                    const SizedBox(height: LoungeTokens.space4),
                    _SwitchSetting(
                      icon: Icons.vibration_outlined,
                      title: AppStrings.hapticsLabel,
                      subtitle: AppStrings.hapticsHelp,
                      value: _preferences.hapticsEnabled,
                      onChanged: (value) =>
                          _save(_preferences.copyWith(hapticsEnabled: value)),
                    ),
                    const _ThinDivider(),
                    _SwitchSetting(
                      icon: Icons.volume_up_outlined,
                      title: AppStrings.soundLabel,
                      subtitle: AppStrings.soundHelp,
                      value: _preferences.soundEnabled,
                      onChanged: (value) =>
                          _save(_preferences.copyWith(soundEnabled: value)),
                    ),
                  ],
                ),
                const _SectionBreak(),
                _SettingsSection(
                  title: 'Hand & joker',
                  subtitle: 'Card handling preferences used during play.',
                  icon: Icons.back_hand_outlined,
                  children: [
                    _SwitchSetting(
                      icon: Icons.sort_outlined,
                      title: 'Auto-sort hand',
                      subtitle: 'Keep cards grouped during play.',
                      value: _preferences.autoSort,
                      onChanged: (value) =>
                          _save(_preferences.copyWith(autoSort: value)),
                    ),
                    const _ThinDivider(),
                    _SwitchSetting(
                      icon: Icons.casino_outlined,
                      title: 'Memory joker display',
                      subtitle: 'Briefly show represented joker identities.',
                      value: _preferences.memoryJokerDisplay,
                      onChanged: (value) => _save(
                        _preferences.copyWith(memoryJokerDisplay: value),
                      ),
                    ),
                  ],
                ),
                const _SectionBreak(),
                _SettingsSection(
                  title: 'Cards & table surface',
                  subtitle: AppStrings.cardThemeHelp,
                  icon: Icons.style_outlined,
                  children: [
                    _CardThemePicker(
                      themes: widget.cardThemes,
                      value: _preferences.cardThemeId,
                      locked: widget.isMatchActive,
                      onChanged: (id) =>
                          _save(_preferences.copyWith(cardThemeId: id)),
                    ),
                    const _ThinDivider(),
                    _SurfaceSetting(
                      value: _preferences.tableSurfaceTheme,
                      onChanged: (value) => _save(
                        _preferences.copyWith(tableSurfaceTheme: value),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsBackdrop extends StatelessWidget {
  const _SettingsBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 24,
          right: -54,
          child: LoungeMotif(
            variant: LoungeMotifVariant.medallion,
            opacity: 0.05,
            strokeWidth: 1.0,
            density: 4,
            size: const Size.square(210),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 18,
          child: SizedBox(
            height: 30,
            child: CustomPaint(
              painter: const GeometricMotifPainter(
                variant: LoungeMotifVariant.border,
                opacity: 0.08,
                strokeWidth: 1.0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsIntro extends StatelessWidget {
  const _SettingsIntro({required this.aids, required this.themeLabel});

  final TableAids aids;
  final String themeLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox.square(
          dimension: 48,
          child: CustomPaint(
            painter: GeometricMotifPainter(
              variant: LoungeMotifVariant.medallion,
              opacity: 0.38,
              strokeWidth: 1.0,
              density: 3,
            ),
          ),
        ),
        const SizedBox(width: LoungeTokens.space4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(AppStrings.settingsTitle, style: LoungeTokens.display),
              const SizedBox(height: LoungeTokens.space2),
              const Text(
                'Tune the table before play. Rule-changing choices lock once a match starts.',
                style: LoungeTokens.bodyMuted,
              ),
              const SizedBox(height: LoungeTokens.space4),
              Wrap(
                spacing: LoungeTokens.space2,
                runSpacing: LoungeTokens.space2,
                children: [
                  _MetaPill(icon: Icons.visibility_outlined, label: aids.label),
                  _MetaPill(icon: Icons.style_outlined, label: themeLabel),
                ],
              ),
              const SizedBox(height: LoungeTokens.space3),
              _IntroLink(
                icon: Icons.article_outlined,
                label: AppStrings.aboutLicenses,
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.licenses),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: LoungeTokens.goldAccent, size: 20),
            const SizedBox(width: LoungeTokens.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: LoungeTokens.heading),
                  const SizedBox(height: 3),
                  Text(subtitle, style: LoungeTokens.bodyMuted),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: LoungeTokens.space4),
        ...children,
      ],
    );
  }
}

class _SectionBreak extends StatelessWidget {
  const _SectionBreak();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LoungeTokens.space5),
      child: Divider(
        height: 1,
        color: LoungeTokens.sandLine.withValues(alpha: 0.24),
      ),
    );
  }
}

class _ThinDivider extends StatelessWidget {
  const _ThinDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: LoungeTokens.space5,
      color: LoungeTokens.sandLine.withValues(alpha: 0.14),
    );
  }
}

class _DropdownSetting<T> extends StatelessWidget {
  const _DropdownSetting({
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

class _SwitchSetting extends StatelessWidget {
  const _SwitchSetting({
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

class _IntroLink extends StatelessWidget {
  const _IntroLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: LoungeTokens.space3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: LoungeTokens.goldAccent),
              const SizedBox(width: LoungeTokens.space2),
              Text(label, style: LoungeTokens.titleSmall),
              const SizedBox(width: LoungeTokens.space1),
              const Icon(Icons.chevron_right, color: LoungeTokens.sandLine),
            ],
          ),
        ),
      ),
    );
  }
}

class _AidsPicker extends StatelessWidget {
  const _AidsPicker({required this.value, required this.onChanged});

  final TableAids value;
  final ValueChanged<TableAids> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final aid in TableAids.values) ...[
          _RadioRow<TableAids>(
            value: aid,
            groupValue: value,
            icon: switch (aid) {
              TableAids.guided => Icons.assistant_direction_outlined,
              TableAids.standard => Icons.route_outlined,
              TableAids.tableMode => Icons.table_restaurant_outlined,
            },
            title: aid.label,
            subtitle: _aidDescription(aid),
            onChanged: onChanged,
          ),
          if (aid != TableAids.values.last) const _ThinDivider(),
        ],
      ],
    );
  }

  static String _aidDescription(TableAids aid) {
    return switch (aid) {
      TableAids.guided => AppStrings.aidGuidedDescription,
      TableAids.standard => AppStrings.aidStandardDescription,
      TableAids.tableMode => AppStrings.aidTableModeDescription,
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
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(value),
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

class _MotionSpeedPicker extends StatelessWidget {
  const _MotionSpeedPicker({required this.value, required this.onChanged});

  final MotionSpeed value;
  final ValueChanged<MotionSpeed> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<MotionSpeed>(
      style: ButtonStyle(
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
      ),
      segments: const [
        ButtonSegment(value: MotionSpeed.normal, label: Text('Normal')),
        ButtonSegment(value: MotionSpeed.fast, label: Text('Fast')),
        ButtonSegment(value: MotionSpeed.reduced, label: Text('Reduced')),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _SurfaceSetting extends StatelessWidget {
  const _SurfaceSetting({required this.value, required this.onChanged});

  final TableSurfaceTheme value;
  final ValueChanged<TableSurfaceTheme> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.table_restaurant_outlined,
          color: LoungeTokens.goldAccent,
        ),
        const SizedBox(width: LoungeTokens.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Table surface', style: LoungeTokens.titleSmall),
              const SizedBox(height: 3),
              const Text(
                'Sets the material under the cards and meld zones. Rules and card art stay unchanged.',
                style: LoungeTokens.bodyMuted,
              ),
              const SizedBox(height: LoungeTokens.space3),
              _DropdownSetting<TableSurfaceTheme>(
                label: 'Surface style',
                value: value,
                values: TableSurfaceTheme.values,
                labelFor: (surface) => surface.label,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CardThemePicker extends StatelessWidget {
  const _CardThemePicker({
    required this.themes,
    required this.value,
    required this.locked,
    required this.onChanged,
  });

  final List<HareegCardTheme> themes;
  final String value;
  final bool locked;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final theme in themes) ...[
          _CardThemeRow(
            theme: theme,
            selected: theme.id == value,
            enabled: !locked && theme.available,
            onTap: () => onChanged(theme.id),
          ),
          if (theme != themes.last) const _ThinDivider(),
        ],
        if (locked)
          const Padding(
            padding: EdgeInsets.only(top: LoungeTokens.space3),
            child: Text(
              'Theme picker is locked during an active match.',
              style: LoungeTokens.bodyMuted,
            ),
          ),
      ],
    );
  }
}

class _CardThemeRow extends StatelessWidget {
  const _CardThemeRow({
    required this.theme,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final HareegCardTheme theme;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.64,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: LoungeTokens.space2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CardThemePreview(theme: theme),
                const SizedBox(width: LoungeTokens.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(theme.label, style: LoungeTokens.titleSmall),
                      const SizedBox(height: 2),
                      Text(theme.description, style: LoungeTokens.bodyMuted),
                      const SizedBox(height: LoungeTokens.space2),
                      Wrap(
                        spacing: LoungeTokens.space2,
                        runSpacing: LoungeTokens.space2,
                        children: [
                          _MetaPill(
                            icon:
                                theme.source ==
                                    CardThemeAssetSource.codeRendered
                                ? Icons.brush_outlined
                                : Icons.collections_bookmark_outlined,
                            label:
                                theme.source ==
                                    CardThemeAssetSource.codeRendered
                                ? 'Code-rendered'
                                : 'Bundled asset',
                          ),
                          _MetaPill(
                            icon: theme.readableOnCompactLayouts
                                ? Icons.check_circle_outline
                                : Icons.visibility_off_outlined,
                            label: theme.readableOnCompactLayouts
                                ? 'Small-table ready'
                                : 'Compact QA pending',
                          ),
                        ],
                      ),
                      if (theme.unavailableReason != null) ...[
                        const SizedBox(height: LoungeTokens.space2),
                        Text(
                          theme.unavailableReason!,
                          style: const TextStyle(
                            color: LoungeTokens.goldAccent,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: LoungeTokens.space2),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected
                      ? LoungeTokens.goldAccent
                      : LoungeTokens.mutedText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.22),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LoungeTokens.space2,
          vertical: LoungeTokens.space1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: LoungeTokens.goldAccent),
            const SizedBox(width: LoungeTokens.space1),
            Text(label, style: LoungeTokens.bodyMuted),
          ],
        ),
      ),
    );
  }
}
