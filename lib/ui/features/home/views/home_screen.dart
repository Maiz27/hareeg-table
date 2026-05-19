import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../app/app_routes.dart';
import '../../../../data/persistence/match_repository.dart';
import '../../../../domain/classic_hareeg/rules/classic_hareeg_rules.dart';
import '../../../../l10n/app_strings.dart';

/// Main menu and navigation shell.
class HomeScreen extends StatefulWidget {
  /// Creates the main menu.
  const HomeScreen({required this.matchRepository, super.key});

  /// Active match persistence.
  final MatchRepository matchRepository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ClassicHareegMatchSnapshot? _savedMatch;
  var _loadingSavedMatch = true;

  @override
  void initState() {
    super.initState();
    AppOrientation.usePortrait();
    _loadSavedMatch();
  }

  @override
  Widget build(BuildContext context) {
    final rules = ClassicHareegRules.defaults();
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(AppStrings.homeTitle, style: textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(AppStrings.homeSubtitle, style: textTheme.bodySmall),
            const SizedBox(height: 24),
            _MenuButton(
              icon: Icons.add_circle_outline,
              label: AppStrings.newGame,
              onPressed: () => _openAndRefresh(AppRoutes.newGame),
            ),
            const SizedBox(height: 12),
            _MenuButton(
              icon: Icons.play_circle_outline,
              label: AppStrings.continueGame,
              subtitle: _savedMatch == null
                  ? (_loadingSavedMatch
                        ? 'Checking saved match...'
                        : AppStrings.noSavedMatch)
                  : 'Resume saved Classic Hareeg table',
              onPressed: _savedMatch == null
                  ? null
                  : () => _openAndRefresh(
                      AppRoutes.table,
                      arguments: _savedMatch,
                    ),
            ),
            if (_savedMatch != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _abandonSavedMatch,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Abandon saved match'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _MenuButton(
              icon: Icons.settings_outlined,
              label: AppStrings.settings,
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.settings),
            ),
            const SizedBox(height: 12),
            _MenuButton(
              icon: Icons.menu_book_outlined,
              label: AppStrings.rulesHelp,
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.rulesHelp),
            ),
            const SizedBox(height: 24),
            _ClassicSummary(rules: rules),
            const SizedBox(height: 16),
            const _PlannedModes(),
          ],
        ),
      ),
    );
  }

  Future<void> _loadSavedMatch() async {
    final savedMatch = await widget.matchRepository.loadActiveMatch();
    if (!mounted) {
      return;
    }

    setState(() {
      _savedMatch = savedMatch;
      _loadingSavedMatch = false;
    });
  }

  Future<void> _openAndRefresh(String route, {Object? arguments}) async {
    await Navigator.of(context).pushNamed(route, arguments: arguments);
    if (!mounted) {
      return;
    }
    await _loadSavedMatch();
  }

  Future<void> _abandonSavedMatch() async {
    await widget.matchRepository.abandonActiveMatch();
    if (!mounted) {
      return;
    }

    setState(() {
      _savedMatch = null;
      _loadingSavedMatch = false;
    });
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.label,
    this.subtitle,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      height: subtitle == null ? 58 : 72,
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: enabled ? colors.onSecondaryContainer : null,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassicSummary extends StatelessWidget {
  const _ClassicSummary({required this.rules});

  final ClassicHareegRules rules;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppStrings.classicModeTitle, style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              AppStrings.classicModeDescription,
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FactChip(label: 'Seats', value: '${rules.seatCount}'),
                _FactChip(
                  label: 'Opening',
                  value: '${rules.openingRequirement}',
                ),
                _FactChip(label: 'Fifty', value: '${rules.fiftyClaimSeconds}s'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label $value'));
  }
}

class _PlannedModes extends StatelessWidget {
  const _PlannedModes();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppStrings.plannedModes, style: textTheme.titleMedium),
        const SizedBox(height: 8),
        const _PlannedModeTile(title: AppStrings.hareeg14),
        const SizedBox(height: 8),
        const _PlannedModeTile(title: AppStrings.fifties),
      ],
    );
  }
}

class _PlannedModeTile extends StatelessWidget {
  const _PlannedModeTile({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.lock_clock_outlined),
      title: Text(title),
      trailing: const Text(AppStrings.comingSoon),
      enabled: false,
    );
  }
}
