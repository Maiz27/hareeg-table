import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../app/app_routes.dart';
import '../../../../data/persistence/preferences_repository.dart';
import '../../../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../../../l10n/app_strings.dart';

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
      appBar: AppBar(title: const Text(AppStrings.setupTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _DropdownSetting<CpuDifficulty>(
              label: 'CPU difficulty',
              value: _setup.cpuDifficulty,
              values: CpuDifficulty.values,
              labelFor: (value) => value.label,
              onChanged: (value) =>
                  _update(_setup.copyWith(cpuDifficulty: value)),
            ),
            const SizedBox(height: 16),
            _DropdownSetting<StarterMode>(
              label: 'First starter',
              value: _setup.starterMode,
              values: StarterMode.values,
              labelFor: (value) => value.label,
              onChanged: (value) =>
                  _update(_setup.copyWith(starterMode: value)),
            ),
            const SizedBox(height: 16),
            _DropdownSetting<int>(
              label: 'Opening requirement',
              value: _setup.openingRequirement,
              values: const [51, 75],
              labelFor: (value) => '$value',
              onChanged: (value) =>
                  _update(_setup.copyWith(openingRequirement: value)),
            ),
            const SizedBox(height: 16),
            _DropdownSetting<int>(
              label: 'Deck count',
              value: _setup.deckCount,
              values: const [2, 3, 4],
              labelFor: (value) => '$value decks',
              onChanged: (value) => _update(_setup.copyWith(deckCount: value)),
            ),
            const SizedBox(height: 16),
            _DropdownSetting<int>(
              label: 'Jokers',
              value: _setup.jokerCount,
              values: const [0, 1, 2, 3, 4],
              labelFor: (value) => '$value',
              onChanged: (value) => _update(_setup.copyWith(jokerCount: value)),
            ),
            const SizedBox(height: 16),
            _DropdownSetting<int>(
              label: 'Fifty timer',
              value: _setup.fiftyTimerSeconds,
              values: const [2, 3, 4, 5, 6],
              labelFor: (value) => '${value}s',
              onChanged: (value) =>
                  _update(_setup.copyWith(fiftyTimerSeconds: value)),
            ),
            const SizedBox(height: 16),
            _DropdownSetting<RulePreset>(
              label: 'Rule preset',
              value: _setup.rulePreset,
              values: RulePreset.values,
              labelFor: (value) => value.label,
              onChanged: (value) => _update(_setup.copyWith(rulePreset: value)),
            ),
            const SizedBox(height: 8),
            Text(
              _setup.rulePreset.description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => Navigator.of(
                context,
              ).pushNamed(AppRoutes.table, arguments: _setup),
              icon: const Icon(Icons.table_bar_outlined),
              label: const Text(AppStrings.startTable),
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
