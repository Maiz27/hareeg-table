import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../app/app_routes.dart';
import '../../../../data/persistence/preferences_repository.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/motion/motion_speed.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../../replay/widgets/analysis_coach_panel.dart' show verbosityLabel;
import '../models/settings_section.dart';
import 'settings_accordion_section.dart';
import 'settings_controls.dart';
import 'settings_labels.dart';
import 'settings_look_pickers.dart';

/// Settings screen.
///
/// Receives prefs and a setter so the app shell can update [MotionScope] /
/// [StrictnessScope] / [CardThemeScope] / [HapticsScope] immediately when the
/// user toggles them. The screen itself is a thin form - it does not own any
/// of those scopes.
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
                SettingsAccordionSection(
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
                      SettingsDropdown<int>(
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
                      SettingsDropdown<int>(
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
                SettingsAccordionSection(
                  key: _sectionKeys[SettingsSection.handSort],
                  icon: Icons.sort_outlined,
                  title: strings.handSort,
                  description: strings.handSortDescription,
                  preview: [
                    handSortModeLabel(_preferences.handSortMode, strings),
                  ],
                  expanded: _openSection == SettingsSection.handSort,
                  onToggle: () => _toggle(SettingsSection.handSort),
                  child: HandSortPicker(
                    value: _preferences.handSortMode,
                    onChanged: (value) =>
                        _save(_preferences.copyWith(handSortMode: value)),
                  ),
                ),
                SettingsAccordionSection(
                  key: _sectionKeys[SettingsSection.assistance],
                  icon: Icons.gavel_outlined,
                  title: strings.tableStrictnessTitle,
                  description: strings.tableStrictnessSectionDescription,
                  preview: [
                    strings.tableStrictnessLabel(
                      _preferences.setup.tableStrictness,
                    ),
                  ],
                  expanded: _openSection == SettingsSection.assistance,
                  onToggle: () => _toggle(SettingsSection.assistance),
                  child: Column(
                    children: [
                      StrictnessPicker(
                        value: _preferences.setup.tableStrictness,
                        locked: widget.isMatchActive,
                        onChanged: (value) => _save(
                          _preferences.copyWith(
                            setup: _preferences.setup.copyWith(
                              tableStrictness: value,
                            ),
                          ),
                        ),
                      ),
                      const SettingsDivider(),
                      SettingsSwitch(
                        icon: Icons.assistant_direction_outlined,
                        title: strings.coachingTips,
                        subtitle: strings.coachingTipsDescription,
                        value: _preferences.coachingTipsEnabled,
                        onChanged: (value) => _save(
                          _preferences.copyWith(coachingTipsEnabled: value),
                        ),
                      ),
                    ],
                  ),
                ),
                SettingsAccordionSection(
                  key: _sectionKeys[SettingsSection.look],
                  icon: Icons.style_outlined,
                  title: strings.look,
                  description: strings.lookDescription,
                  preview: [
                    selectedCardTheme.label,
                    if (_preferences.highContrastCards)
                      strings.highContrastCards,
                    tableSurfaceLabel(_preferences.tableSurfaceTheme, strings),
                  ],
                  expanded: _openSection == SettingsSection.look,
                  onToggle: () => _toggle(SettingsSection.look),
                  child: Column(
                    children: [
                      CardThemePicker(
                        themes: widget.cardThemes,
                        value: _preferences.cardThemeId,
                        locked: widget.isMatchActive,
                        onChanged: (id) =>
                            _save(_preferences.copyWith(cardThemeId: id)),
                      ),
                      const SettingsDivider(),
                      SettingsSwitch(
                        icon: Icons.contrast_outlined,
                        title: strings.highContrastCards,
                        subtitle: strings.highContrastCardsDescription,
                        value: _preferences.highContrastCards,
                        onChanged: (value) => _save(
                          _preferences.copyWith(highContrastCards: value),
                        ),
                      ),
                      const SettingsDivider(),
                      TableSurfacePicker(
                        value: _preferences.tableSurfaceTheme,
                        onChanged: (value) => _save(
                          _preferences.copyWith(tableSurfaceTheme: value),
                        ),
                      ),
                    ],
                  ),
                ),
                SettingsAccordionSection(
                  key: _sectionKeys[SettingsSection.feel],
                  icon: Icons.touch_app_outlined,
                  title: strings.feel,
                  description: strings.feelDescription,
                  preview: [
                    motionSpeedLabel(_preferences.motionSpeed, strings),
                    if (_preferences.fastCpuTurns) strings.fastCpuTurns,
                    strings.hapticsLabel,
                    if (_preferences.soundEnabled) strings.soundLabel,
                  ],
                  expanded: _openSection == SettingsSection.feel,
                  onToggle: () => _toggle(SettingsSection.feel),
                  child: Column(
                    children: [
                      MotionSpeedPicker(
                        value: _preferences.motionSpeed,
                        onChanged: (value) =>
                            _save(_preferences.copyWith(motionSpeed: value)),
                      ),
                      const SettingsDivider(),
                      SettingsSwitch(
                        icon: Icons.speed_outlined,
                        title: strings.fastCpuTurns,
                        subtitle: strings.fastCpuTurnsDescription,
                        value: _preferences.fastCpuTurns,
                        onChanged: (value) =>
                            _save(_preferences.copyWith(fastCpuTurns: value)),
                      ),
                      const SettingsDivider(),
                      SettingsSwitch(
                        icon: Icons.vibration_outlined,
                        title: strings.hapticsLabel,
                        subtitle: strings.hapticsHelp,
                        value: _preferences.hapticsEnabled,
                        onChanged: (value) =>
                            _save(_preferences.copyWith(hapticsEnabled: value)),
                      ),
                      const SettingsDivider(),
                      SettingsSwitch(
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
                SettingsAccordionSection(
                  key: _sectionKeys[SettingsSection.review],
                  icon: Icons.replay_outlined,
                  title: strings.settingsReviewTitle,
                  description: strings.settingsReviewSubtitle,
                  preview: [
                    verbosityLabel(
                      strings,
                      _preferences.analysisCoach.verbosity,
                    ),
                  ],
                  expanded: _openSection == SettingsSection.review,
                  onToggle: () => _toggle(SettingsSection.review),
                  child: Column(
                    children: [
                      VerbosityPicker(
                        value: _preferences.analysisCoach.verbosity,
                        onChanged: (value) => _save(
                          _preferences.copyWith(
                            analysisCoach: _preferences.analysisCoach.copyWith(
                              verbosity: value,
                            ),
                          ),
                        ),
                      ),
                      const SettingsDivider(),
                      SettingsSwitch(
                        icon: Icons.warning_amber_outlined,
                        title: strings.replayCardDeathWarnings,
                        subtitle:
                            strings.settingsReviewCardDeathWarningsDescription,
                        value: _preferences.analysisCoach.cardDeathWarnings,
                        onChanged: (value) => _save(
                          _preferences.copyWith(
                            analysisCoach: _preferences.analysisCoach.copyWith(
                              cardDeathWarnings: value,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SettingsAccordionSection(
                  key: _sectionKeys[SettingsSection.language],
                  icon: Icons.language_outlined,
                  title: strings.language,
                  description: strings.languageDescription,
                  preview: [appLanguageLabel(_preferences.language, strings)],
                  expanded: _openSection == SettingsSection.language,
                  onToggle: () => _toggle(SettingsSection.language),
                  isLast: true,
                  child: SettingsDropdown<AppLanguage>(
                    label: strings.language,
                    value: _preferences.language,
                    values: AppLanguage.values,
                    labelFor: (value) => appLanguageLabel(value, strings),
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
