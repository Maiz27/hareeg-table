import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../data/persistence/preferences_repository.dart';
import '../../../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../../../l10n/app_strings.dart';

/// Settings entry point for persisted game preferences.
class SettingsScreen extends StatefulWidget {
  /// Creates the settings screen.
  const SettingsScreen({required this.preferencesRepository, super.key});

  /// Saved app preferences.
  final PreferencesRepository preferencesRepository;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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
      appBar: AppBar(title: const Text(AppStrings.settingsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _DropdownSetting<CpuDifficulty>(
              label: 'CPU difficulty',
              value: _preferences.setup.cpuDifficulty,
              values: CpuDifficulty.values,
              labelFor: (value) => value.label,
              onChanged: (value) => _save(
                _preferences.copyWith(
                  setup: _preferences.setup.copyWith(cpuDifficulty: value),
                ),
              ),
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            _DropdownSetting<int>(
              label: 'Opening requirement',
              value: _preferences.setup.openingRequirement,
              values: const [51, 75],
              labelFor: (value) => '$value',
              onChanged: (value) => _save(
                _preferences.copyWith(
                  setup: _preferences.setup.copyWith(openingRequirement: value),
                ),
              ),
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            _DropdownSetting<int>(
              label: 'Fifty timer',
              value: _preferences.setup.fiftyTimerSeconds,
              values: const [2, 3, 4, 5, 6],
              labelFor: (value) => '${value}s',
              onChanged: (value) => _save(
                _preferences.copyWith(
                  setup: _preferences.setup.copyWith(fiftyTimerSeconds: value),
                ),
              ),
            ),
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-sort hand'),
              subtitle: const Text('Keep cards grouped during play.'),
              value: _preferences.autoSort,
              onChanged: (value) =>
                  _save(_preferences.copyWith(autoSort: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reduced motion'),
              subtitle: const Text('Limit nonessential table animation later.'),
              value: _preferences.reducedMotion,
              onChanged: (value) =>
                  _save(_preferences.copyWith(reducedMotion: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Memory joker display'),
              subtitle: const Text(
                'Briefly show represented joker identities.',
              ),
              value: _preferences.memoryJokerDisplay,
              onChanged: (value) =>
                  _save(_preferences.copyWith(memoryJokerDisplay: value)),
            ),
            const Divider(height: 32),
            _DropdownSetting<AppLanguage>(
              label: 'Language',
              value: _preferences.language,
              values: AppLanguage.values,
              labelFor: (value) => value.label,
              onChanged: (value) =>
                  _save(_preferences.copyWith(language: value)),
            ),
            const SizedBox(height: 16),
            _DropdownSetting<VisualStyle>(
              label: 'Visual style',
              value: _preferences.visualStyle,
              values: VisualStyle.values,
              labelFor: (value) => value.label,
              onChanged: (value) =>
                  _save(_preferences.copyWith(visualStyle: value)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadPreferences() async {
    try {
      final preferences = await widget.preferencesRepository.loadPreferences();
      if (!mounted) {
        return;
      }

      setState(() {
        _preferences = preferences;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load settings preferences: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) {
        return;
      }
      setState(() {
        _preferences = GamePreferences.defaults();
      });
    }
  }

  void _save(GamePreferences preferences) {
    setState(() {
      _preferences = preferences;
    });
    widget.preferencesRepository.savePreferences(preferences);
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
      decoration: InputDecoration(labelText: label),
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
