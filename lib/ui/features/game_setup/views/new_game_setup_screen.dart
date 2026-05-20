import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../app/app_routes.dart';
import '../../../../data/persistence/preferences_repository.dart';
import '../../../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Classic Hareeg pre-game setup flow.
class NewGameSetupScreen extends StatefulWidget {
  /// Creates the setup screen.
  const NewGameSetupScreen({required this.preferencesRepository, super.key});

  /// Saved app preferences.
  final PreferencesRepository preferencesRepository;

  @override
  State<NewGameSetupScreen> createState() => _NewGameSetupScreenState();
}

class _NewGameSetupScreenState extends State<NewGameSetupScreen> {
  ClassicHareegSetup _setup = ClassicHareegSetup.defaults();
  GamePreferences _preferences = GamePreferences.defaults();

  @override
  void initState() {
    super.initState();
    AppOrientation.usePortrait();
    _loadPreferences();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoungeTokens.feltGreen,
      appBar: AppBar(title: const Text(AppStrings.setupTitle)),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _SetupBackdrop(),
            ListView(
              padding: const EdgeInsets.fromLTRB(
                LoungeTokens.space5,
                LoungeTokens.space5,
                LoungeTokens.space5,
                LoungeTokens.space8,
              ),
              children: [
                const _SetupIntro(),
                const _SectionBreak(),
                _SetupSection(
                  title: 'Players & turn order',
                  subtitle:
                      'Sets who starts and how sharp the CPU table feels.',
                  icon: Icons.groups_outlined,
                  children: [
                    _SettingDropdown<CpuDifficulty>(
                      title: 'CPU difficulty',
                      description:
                          'Changes opponent decision quality and reaction timing.',
                      value: _setup.cpuDifficulty,
                      values: CpuDifficulty.values,
                      labelFor: (value) => value.label,
                      onChanged: (value) =>
                          _update(_setup.copyWith(cpuDifficulty: value)),
                    ),
                    const _ThinDivider(),
                    _SettingDropdown<StarterMode>(
                      title: 'First starter',
                      description:
                          'The starter receives 15 cards and skips the first draw.',
                      value: _setup.starterMode,
                      values: StarterMode.values,
                      labelFor: (value) => value.label,
                      onChanged: (value) =>
                          _update(_setup.copyWith(starterMode: value)),
                    ),
                  ],
                ),
                const _SectionBreak(),
                _SetupSection(
                  title: 'Classic table rules',
                  subtitle:
                      'These values affect legality, scoring, and the pressure to open.',
                  icon: Icons.tune_outlined,
                  children: [
                    _SettingDropdown<int>(
                      title: 'Opening requirement',
                      description:
                          'Minimum meld value needed before you can add covers.',
                      value: _setup.openingRequirement,
                      values: const [51, 75],
                      labelFor: (value) => '$value',
                      onChanged: (value) =>
                          _update(_setup.copyWith(openingRequirement: value)),
                    ),
                    const _ThinDivider(),
                    _SettingDropdown<int>(
                      title: 'Deck count',
                      description:
                          'More decks add card copies without changing Classic rules.',
                      value: _setup.deckCount,
                      values: const [2, 3, 4],
                      labelFor: (value) => '$value decks',
                      onChanged: (value) =>
                          _update(_setup.copyWith(deckCount: value)),
                    ),
                    const _ThinDivider(),
                    _SettingDropdown<int>(
                      title: 'Jokers',
                      description:
                          'Jokers can stand in melds and may later be replaced.',
                      value: _setup.jokerCount,
                      values: const [0, 1, 2, 3, 4],
                      labelFor: (value) => '$value',
                      onChanged: (value) =>
                          _update(_setup.copyWith(jokerCount: value)),
                    ),
                  ],
                ),
                const _SectionBreak(),
                _SetupSection(
                  title: 'Pressure & penalties',
                  subtitle:
                      'Controls the Fifty window and how strict mistakes should feel.',
                  icon: Icons.local_fire_department_outlined,
                  children: [
                    _SettingDropdown<int>(
                      title: 'Fifty timer',
                      description:
                          'How long the next player has to claim a valid Fifty.',
                      value: _setup.fiftyTimerSeconds,
                      values: const [2, 3, 4, 5, 6],
                      labelFor: (value) => '${value}s',
                      onChanged: (value) =>
                          _update(_setup.copyWith(fiftyTimerSeconds: value)),
                    ),
                    const _ThinDivider(),
                    _SettingDropdown<RulePreset>(
                      title: 'Rule preset',
                      description:
                          'Assisted blocks mistakes; table presets allow penalties.',
                      value: _setup.rulePreset,
                      values: RulePreset.values,
                      labelFor: (value) => value.label,
                      onChanged: (value) =>
                          _update(_setup.copyWith(rulePreset: value)),
                    ),
                    const SizedBox(height: LoungeTokens.space3),
                    _RulePresetNote(description: _setup.rulePreset.description),
                  ],
                ),
                const SizedBox(height: LoungeTokens.space6),
                FilledButton.icon(
                  onPressed: () => Navigator.of(
                    context,
                  ).pushNamed(AppRoutes.table, arguments: _setup),
                  icon: const Icon(Icons.table_bar_outlined),
                  label: const Text(AppStrings.startTable),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _update(ClassicHareegSetup setup) {
    setState(() {
      _setup = setup;
      _preferences = _preferences.copyWith(setup: setup);
    });
    widget.preferencesRepository.savePreferences(_preferences);
  }

  Future<void> _loadPreferences() async {
    var preferences = GamePreferences.defaults();
    try {
      preferences = await widget.preferencesRepository.loadPreferences();
    } catch (error, stackTrace) {
      debugPrint('Failed to load setup preferences: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _preferences = preferences;
      _setup = preferences.setup;
    });
  }
}

class _SetupBackdrop extends StatelessWidget {
  const _SetupBackdrop();

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

class _SetupIntro extends StatelessWidget {
  const _SetupIntro();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox.square(
          dimension: 50,
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
            children: const [
              Text(AppStrings.setupTitle, style: LoungeTokens.display),
              SizedBox(height: LoungeTokens.space2),
              Text(
                'Choose the table rhythm before the first deal. These preferences are saved for next time.',
                style: LoungeTokens.bodyMuted,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SetupSection extends StatelessWidget {
  const _SetupSection({
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

class _SettingDropdown<T> extends StatelessWidget {
  const _SettingDropdown({
    required this.title,
    required this.description,
    required this.value,
    required this.values,
    required this.labelFor,
    required this.onChanged,
  });

  final String title;
  final String description;
  final T value;
  final List<T> values;
  final String Function(T value) labelFor;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: LoungeTokens.titleSmall),
        const SizedBox(height: 3),
        Text(description, style: LoungeTokens.bodyMuted),
        const SizedBox(height: LoungeTokens.space3),
        _DropdownSetting<T>(
          label: title,
          value: value,
          values: values,
          labelFor: labelFor,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _RulePresetNote extends StatelessWidget {
  const _RulePresetNote({required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline,
          size: 18,
          color: LoungeTokens.goldAccent,
        ),
        const SizedBox(width: LoungeTokens.space2),
        Expanded(child: Text(description, style: LoungeTokens.bodyMuted)),
      ],
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
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
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
