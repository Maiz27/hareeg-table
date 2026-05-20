import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../app/app_routes.dart';
import '../../../../data/persistence/preferences_repository.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/aids/table_aids.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/motion/motion_speed.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../../../core/theme/table_surface_theme.dart';
import '../../game_table/widgets/table_background.dart';
import '../models/settings_section.dart';
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
    this.initialSection,
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

  /// Section to expand on first frame, e.g. when the Start screen deep-links
  /// here from the "Edit in Settings" affordance.
  final SettingsSection? initialSection;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Map<SettingsSection, GlobalKey> _sectionKeys = {
    for (final section in SettingsSection.values) section: GlobalKey(),
  };
  SettingsSection? _openSection;

  @override
  void initState() {
    super.initState();
    AppOrientation.usePortrait();
    _openSection = widget.initialSection;
    if (widget.initialSection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollSectionIntoView(widget.initialSection!);
      });
    }
  }

  GamePreferences get _preferences => widget.preferences;

  void _save(GamePreferences next) => widget.onUpdate(next);

  void _toggle(SettingsSection section) {
    setState(() {
      _openSection = _openSection == section ? null : section;
    });
    if (_openSection == section) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollSectionIntoView(section);
      });
    }
  }

  void _scrollSectionIntoView(SettingsSection section) {
    final ctx = _sectionKeys[section]?.currentContext;
    if (ctx == null) {
      return;
    }
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.08,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final selectedCardTheme = widget.cardThemes.firstWhere(
      (theme) => theme.id == _preferences.cardThemeId,
      orElse: () => widget.cardThemes.first,
    );

    return Scaffold(
      backgroundColor: LoungeTokens.feltGreen,
      appBar: AppBar(title: Text(strings.settingsTitle)),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _SettingsBackdrop(),
            ListView(
              padding: const EdgeInsets.fromLTRB(
                LoungeTokens.space5,
                LoungeTokens.space4,
                LoungeTokens.space5,
                LoungeTokens.space8 * 2,
              ),
              children: [
                _AccordionSection(
                  key: _sectionKeys[SettingsSection.tableRules],
                  icon: Icons.tune_outlined,
                  title: strings.tableRules,
                  description: strings.tableRulesDescription,
                  preview: [
                    strings.decksValue(_preferences.setup.deckCount),
                    strings.fiftySecondsValue(
                      _preferences.setup.fiftyTimerSeconds,
                    ),
                  ],
                  expanded: _openSection == SettingsSection.tableRules,
                  onToggle: () => _toggle(SettingsSection.tableRules),
                  child: Column(
                    children: [
                      _DropdownSetting<int>(
                        label: strings.deckCount,
                        value: _preferences.setup.deckCount,
                        values: const [2, 3, 4],
                        labelFor: strings.decksValue,
                        onChanged: (value) => _save(
                          _preferences.copyWith(
                            setup: _preferences.setup.copyWith(
                              deckCount: value,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: LoungeTokens.space4),
                      _DropdownSetting<int>(
                        label: strings.fiftyTimer,
                        value: _preferences.setup.fiftyTimerSeconds,
                        values: const [2, 3, 4, 5, 6],
                        labelFor: strings.fiftySecondsValue,
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
                ),
                _AccordionSection(
                  key: _sectionKeys[SettingsSection.assistance],
                  icon: Icons.visibility_outlined,
                  title: strings.assistance,
                  description: strings.assistanceDescription,
                  preview: [
                    _aidsLabel(_preferences.tableAids, strings),
                    if (_preferences.autoSort) strings.autoSort,
                  ],
                  expanded: _openSection == SettingsSection.assistance,
                  onToggle: () => _toggle(SettingsSection.assistance),
                  child: Column(
                    children: [
                      _AidsPicker(
                        value: _preferences.tableAids,
                        onChanged: (value) =>
                            _save(_preferences.copyWith(tableAids: value)),
                      ),
                      const _ThinDivider(),
                      _SwitchSetting(
                        icon: Icons.sort_outlined,
                        title: strings.autoSortHand,
                        subtitle: strings.autoSortHandDescription,
                        value: _preferences.autoSort,
                        onChanged: (value) =>
                            _save(_preferences.copyWith(autoSort: value)),
                      ),
                      const _ThinDivider(),
                      _SwitchSetting(
                        icon: Icons.casino_outlined,
                        title: strings.memoryJokerDisplay,
                        subtitle: strings.memoryJokerDisplayDescription,
                        value: _preferences.memoryJokerDisplay,
                        onChanged: (value) => _save(
                          _preferences.copyWith(memoryJokerDisplay: value),
                        ),
                      ),
                    ],
                  ),
                ),
                _AccordionSection(
                  key: _sectionKeys[SettingsSection.look],
                  icon: Icons.style_outlined,
                  title: strings.look,
                  description: strings.lookDescription,
                  preview: [
                    selectedCardTheme.label,
                    _surfaceLabel(_preferences.tableSurfaceTheme, strings),
                  ],
                  expanded: _openSection == SettingsSection.look,
                  onToggle: () => _toggle(SettingsSection.look),
                  child: Column(
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
                ),
                _AccordionSection(
                  key: _sectionKeys[SettingsSection.feel],
                  icon: Icons.touch_app_outlined,
                  title: strings.feel,
                  description: strings.feelDescription,
                  preview: [
                    _motionLabel(_preferences.motionSpeed, strings),
                    strings.hapticsLabel,
                    if (_preferences.soundEnabled) strings.soundLabel,
                  ],
                  expanded: _openSection == SettingsSection.feel,
                  onToggle: () => _toggle(SettingsSection.feel),
                  child: Column(
                    children: [
                      _MotionSpeedPicker(
                        value: _preferences.motionSpeed,
                        onChanged: (value) =>
                            _save(_preferences.copyWith(motionSpeed: value)),
                      ),
                      const SizedBox(height: LoungeTokens.space4),
                      _SwitchSetting(
                        icon: Icons.vibration_outlined,
                        title: strings.hapticsLabel,
                        subtitle: strings.hapticsHelp,
                        value: _preferences.hapticsEnabled,
                        onChanged: (value) =>
                            _save(_preferences.copyWith(hapticsEnabled: value)),
                      ),
                      const _ThinDivider(),
                      _SwitchSetting(
                        icon: Icons.volume_up_outlined,
                        title: strings.soundLabel,
                        subtitle: strings.soundHelp,
                        value: _preferences.soundEnabled,
                        onChanged: (value) =>
                            _save(_preferences.copyWith(soundEnabled: value)),
                      ),
                    ],
                  ),
                ),
                _AccordionSection(
                  key: _sectionKeys[SettingsSection.language],
                  icon: Icons.language_outlined,
                  title: strings.language,
                  description: strings.languageDescription,
                  preview: [_languageLabel(_preferences.language, strings)],
                  expanded: _openSection == SettingsSection.language,
                  onToggle: () => _toggle(SettingsSection.language),
                  isLast: true,
                  child: _DropdownSetting<AppLanguage>(
                    label: strings.language,
                    value: _preferences.language,
                    values: AppLanguage.values,
                    labelFor: (value) => _languageLabel(value, strings),
                    onChanged: (value) =>
                        _save(_preferences.copyWith(language: value)),
                  ),
                ),
                const SizedBox(height: LoungeTokens.space5),
                _AboutLink(
                  onTap: () =>
                      Navigator.of(context).pushNamed(AppRoutes.licenses),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _motionLabel(MotionSpeed speed, AppStrings strings) {
    return switch (speed) {
      MotionSpeed.normal => strings.normalMotion,
      MotionSpeed.fast => strings.fastMotion,
      MotionSpeed.reduced => strings.reducedMotion,
    };
  }

  static String _aidsLabel(TableAids aid, AppStrings strings) {
    return switch (aid) {
      TableAids.guided => strings.guided,
      TableAids.standard => strings.standard,
      TableAids.tableMode => strings.tableMode,
    };
  }

  static String _languageLabel(AppLanguage language, AppStrings strings) {
    return switch (language) {
      AppLanguage.english => strings.englishLanguage,
      AppLanguage.arabic => strings.arabicLanguage,
    };
  }

  static String _surfaceLabel(TableSurfaceTheme surface, AppStrings strings) {
    return switch (surface) {
      TableSurfaceTheme.felt => strings.darkFelt,
      TableSurfaceTheme.wood => strings.lightWood,
      TableSurfaceTheme.sapphire => strings.midnightSapphire,
      TableSurfaceTheme.clay => strings.crimsonClay,
    };
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

class _AccordionSection extends StatelessWidget {
  const _AccordionSection({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.preview,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<String> preview;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: LoungeTokens.space3,
                horizontal: LoungeTokens.space2,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(icon, color: LoungeTokens.goldAccent, size: 20),
                  ),
                  const SizedBox(width: LoungeTokens.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: LoungeTokens.heading),
                        const SizedBox(height: 3),
                        Text(description, style: LoungeTokens.bodyMuted),
                        if (preview.isNotEmpty && !expanded) ...[
                          const SizedBox(height: LoungeTokens.space2),
                          Wrap(
                            spacing: LoungeTokens.space2,
                            runSpacing: LoungeTokens.space1,
                            children: [
                              for (final pill in preview) _PreviewPill(pill),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: LoungeTokens.space2),
                  _RotatingChevron(expanded: expanded),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: ClipRect(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              opacity: expanded ? 1 : 0,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(
                        LoungeTokens.space2,
                        LoungeTokens.space2,
                        LoungeTokens.space2,
                        LoungeTokens.space5,
                      ),
                      child: child,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            color: LoungeTokens.sandLine.withValues(alpha: 0.18),
          ),
      ],
    );
  }
}

class _PreviewPill extends StatelessWidget {
  const _PreviewPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.22),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LoungeTokens.space2,
          vertical: 3,
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: LoungeTokens.offWhiteText,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

class _RotatingChevron extends StatelessWidget {
  const _RotatingChevron({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: expanded ? 0.5 : 0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Transform.rotate(
          angle: value * 3.141592653589793,
          child: const Icon(
            Icons.expand_more,
            color: LoungeTokens.sandLine,
            size: 22,
          ),
        );
      },
    );
  }
}

class _AboutLink extends StatelessWidget {
  const _AboutLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: LoungeTokens.space3,
            horizontal: LoungeTokens.space2,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.article_outlined,
                size: 18,
                color: LoungeTokens.goldAccent,
              ),
              const SizedBox(width: LoungeTokens.space3),
              Expanded(
                child: Text(
                  strings.aboutLicenses,
                  style: LoungeTokens.titleSmall,
                ),
              ),
              const Icon(Icons.chevron_right, color: LoungeTokens.sandLine),
            ],
          ),
        ),
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

class _AidsPicker extends StatelessWidget {
  const _AidsPicker({required this.value, required this.onChanged});

  final TableAids value;
  final ValueChanged<TableAids> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

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
            title: _SettingsScreenState._aidsLabel(aid, strings),
            subtitle: _aidDescription(aid, strings),
            onChanged: onChanged,
          ),
          if (aid != TableAids.values.last) const _ThinDivider(),
        ],
      ],
    );
  }

  static String _aidDescription(TableAids aid, AppStrings strings) {
    return switch (aid) {
      TableAids.guided => strings.aidGuidedDescription,
      TableAids.standard => strings.aidStandardDescription,
      TableAids.tableMode => strings.aidTableModeDescription,
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
    final strings = context.strings;

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

class _SurfaceSetting extends StatelessWidget {
  const _SurfaceSetting({required this.value, required this.onChanged});

  final TableSurfaceTheme value;
  final ValueChanged<TableSurfaceTheme> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

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
              Text(strings.tableSurface, style: LoungeTokens.titleSmall),
              const SizedBox(height: 3),
              Text(
                strings.tableSurfaceDescription,
                style: LoungeTokens.bodyMuted,
              ),
              const SizedBox(height: LoungeTokens.space3),
              Wrap(
                spacing: LoungeTokens.space2,
                runSpacing: LoungeTokens.space3,
                children: [
                  for (final surface in TableSurfaceTheme.values)
                    _SurfaceTile(
                      surface: surface,
                      selected: surface == value,
                      onTap: () => onChanged(surface),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SurfaceTile extends StatelessWidget {
  const _SurfaceTile({
    required this.surface,
    required this.selected,
    required this.onTap,
  });

  final TableSurfaceTheme surface;
  final bool selected;
  final VoidCallback onTap;

  static const _tileWidth = 152.0;
  static const _previewHeight = 92.0;
  // Source canvas matches a landscape mobile aspect so motifs and frame
  // padding read at thumbnail scale instead of collapsing to single pixels.
  static const _sourceWidth = 520.0;
  static const _sourceHeight = 312.0;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final surfaceLabel = _SettingsScreenState._surfaceLabel(surface, strings);
    final borderColor = selected
        ? LoungeTokens.goldAccent
        : LoungeTokens.sandLine.withValues(alpha: 0.28);
    return Semantics(
      button: true,
      selected: selected,
      label: surfaceLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
          child: SizedBox(
            width: _tileWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: _tileWidth,
                  height: _previewHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      LoungeTokens.radiusButton,
                    ),
                    border: Border.all(
                      color: borderColor,
                      width: selected ? 2 : 1,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: LoungeTokens.goldAccent.withValues(
                                alpha: 0.32,
                              ),
                              blurRadius: 14,
                              spreadRadius: -2,
                            ),
                          ]
                        : null,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FittedBox(
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: _sourceWidth,
                          height: _sourceHeight,
                          child: TableBackground(surface: surface),
                        ),
                      ),
                      if (selected)
                        const Positioned(
                          top: 6,
                          right: 6,
                          child: _SelectedBadge(),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: LoungeTokens.space2),
                Text(
                  surfaceLabel,
                  style: TextStyle(
                    color: selected
                        ? LoungeTokens.goldAccent
                        : LoungeTokens.offWhiteText,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedBadge extends StatelessWidget {
  const _SelectedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        color: LoungeTokens.coffeeCharcoal,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.check_circle,
        color: LoungeTokens.goldAccent,
        size: 18,
      ),
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
    final strings = context.strings;
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
          Padding(
            padding: const EdgeInsets.only(top: LoungeTokens.space3),
            child: Text(
              strings.themeLockedActiveMatch,
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
    final strings = context.strings;

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
                                ? strings.codeRendered
                                : strings.bundledAsset,
                          ),
                          _MetaPill(
                            icon: theme.readableOnCompactLayouts
                                ? Icons.check_circle_outline
                                : Icons.visibility_off_outlined,
                            label: theme.readableOnCompactLayouts
                                ? strings.smallTableReady
                                : strings.compactQaPending,
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
