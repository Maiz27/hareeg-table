import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/rules/classic_hareeg_rules.dart';
import '../../../../l10n/app_strings.dart';

/// First screen shown by the foundation shell.
///
/// This is intentionally lightweight until the main menu and navigation issue
/// builds the real route structure.
class HomeScreen extends StatelessWidget {
  /// Creates the foundation home screen.
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rules = ClassicHareegRules.defaults();
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 2,
                        child: _HeroSummary(textTheme: textTheme),
                      ),
                      const SizedBox(width: 20),
                      Expanded(flex: 3, child: _ClassicModeCard(rules: rules)),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HeroSummary extends StatelessWidget {
  const _HeroSummary({required this.textTheme});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppStrings.homeTitle, style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(AppStrings.homeSubtitle, style: textTheme.bodySmall),
        const SizedBox(height: 24),
        const _FoundationStatus(),
      ],
    );
  }
}

class _ClassicModeCard extends StatelessWidget {
  const _ClassicModeCard({required this.rules});

  final ClassicHareegRules rules;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppStrings.classicModeTitle, style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              AppStrings.classicModeDescription,
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            _RuleFact(label: 'Seats', value: '${rules.seatCount}'),
            _RuleFact(label: 'Opening', value: '${rules.openingRequirement}'),
            _RuleFact(
              label: 'Fifty timer',
              value: '${rules.fiftyClaimSeconds}s',
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleFact extends StatelessWidget {
  const _RuleFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _FoundationStatus extends StatelessWidget {
  const _FoundationStatus();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusLine(text: AppStrings.rulesReady),
        _StatusLine(text: AppStrings.cpuReady),
        _StatusLine(text: AppStrings.persistenceReady),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(
            Icons.check_circle,
            color: Theme.of(context).colorScheme.primary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
