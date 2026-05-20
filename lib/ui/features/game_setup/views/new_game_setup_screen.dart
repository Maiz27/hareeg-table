import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../app/app_routes.dart';
import '../../../../data/persistence/preferences_repository.dart';
import '../../../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/aids/table_aids.dart';
import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../../settings/models/settings_section.dart';

/// Classic Hareeg pre-game setup flow.
///
/// Shows only the rules a player tends to re-decide each game: CPU difficulty,
/// who starts, rule preset, opening requirement, and joker count. Deck count,
/// fifty timer, aids, and visuals live on the Settings screen and are
/// summarised in the "House rules" footer.
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
    final strings = context.strings;

    return Scaffold(
      backgroundColor: LoungeTokens.feltGreen,
      appBar: AppBar(title: Text(strings.setupTitle)),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _SetupBackdrop(),
            ListView(
              padding: const EdgeInsets.fromLTRB(
                LoungeTokens.space5,
                LoungeTokens.space4,
                LoungeTokens.space5,
                LoungeTokens.space8,
              ),
              children: [
                _StartChoice<CpuDifficulty>(
                  icon: Icons.smart_toy_outlined,
                  title: strings.cpuDifficulty,
                  segments: [
                    ButtonSegment(
                      value: CpuDifficulty.beginner,
                      label: Text(strings.beginner),
                    ),
                    ButtonSegment(
                      value: CpuDifficulty.casual,
                      label: Text(strings.casual),
                    ),
                    ButtonSegment(
                      value: CpuDifficulty.skilled,
                      label: Text(strings.skilled),
                    ),
                    ButtonSegment(
                      value: CpuDifficulty.expert,
                      label: Text(strings.expert),
                    ),
                  ],
                  value: _setup.cpuDifficulty,
                  onChanged: (value) =>
                      _update(_setup.copyWith(cpuDifficulty: value)),
                ),
                const SizedBox(height: LoungeTokens.space5),
                _StartChoice<StarterMode>(
                  icon: Icons.flag_outlined,
                  title: strings.firstStarter,
                  segments: [
                    ButtonSegment(
                      value: StarterMode.human,
                      label: Text(strings.youStart),
                    ),
                    ButtonSegment(
                      value: StarterMode.random,
                      label: Text(strings.random),
                    ),
                  ],
                  value: _setup.starterMode,
                  onChanged: (value) =>
                      _update(_setup.copyWith(starterMode: value)),
                ),
                const SizedBox(height: LoungeTokens.space5),
                _StartChoice<RulePreset>(
                  icon: Icons.gavel_outlined,
                  title: strings.rulePreset,
                  segments: [
                    ButtonSegment(
                      value: RulePreset.assisted,
                      label: Text(strings.assisted),
                    ),
                    ButtonSegment(
                      value: RulePreset.tablePenalties,
                      label: Text(strings.penalties),
                    ),
                    ButtonSegment(
                      value: RulePreset.hardTable17,
                      label: Text(strings.hard17),
                    ),
                  ],
                  value: _setup.rulePreset,
                  onChanged: (value) =>
                      _update(_setup.copyWith(rulePreset: value)),
                  note: _rulePresetDescription(_setup.rulePreset, strings),
                ),
                const SizedBox(height: LoungeTokens.space5),
                _StartChoice<int>(
                  icon: Icons.timeline_outlined,
                  title: strings.openingRequirement,
                  segments: const [
                    ButtonSegment(value: 51, label: Text('51')),
                    ButtonSegment(value: 75, label: Text('75')),
                  ],
                  value: _setup.openingRequirement,
                  onChanged: (value) =>
                      _update(_setup.copyWith(openingRequirement: value)),
                ),
                const SizedBox(height: LoungeTokens.space5),
                _StartChoice<int>(
                  icon: Icons.casino_outlined,
                  title: strings.jokers,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('0')),
                    ButtonSegment(value: 1, label: Text('1')),
                    ButtonSegment(value: 2, label: Text('2')),
                    ButtonSegment(value: 3, label: Text('3')),
                    ButtonSegment(value: 4, label: Text('4')),
                  ],
                  value: _setup.jokerCount,
                  onChanged: (value) =>
                      _update(_setup.copyWith(jokerCount: value)),
                ),
                const SizedBox(height: LoungeTokens.space6),
                _HouseRulesFooter(
                  deckCount: _setup.deckCount,
                  fiftyTimerSeconds: _setup.fiftyTimerSeconds,
                  aidsLabel: _aidsLabel(_preferences.tableAids, strings),
                  onEdit: () => Navigator.of(context).pushNamed(
                    AppRoutes.settings,
                    arguments: const SettingsRouteArguments(
                      initialSection: SettingsSection.tableRules,
                    ),
                  ),
                ),
                const SizedBox(height: LoungeTokens.space6),
                FilledButton.icon(
                  onPressed: () => Navigator.of(
                    context,
                  ).pushNamed(AppRoutes.table, arguments: _setup),
                  icon: const Icon(Icons.table_bar_outlined),
                  label: Text(strings.startTable),
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

  static String _aidsLabel(TableAids aid, AppStrings strings) {
    return switch (aid) {
      TableAids.guided => strings.guided,
      TableAids.standard => strings.standard,
      TableAids.tableMode => strings.tableMode,
    };
  }

  static String _rulePresetDescription(RulePreset preset, AppStrings strings) {
    if (!strings.isRtl) {
      return preset.description;
    }
    return switch (preset) {
      RulePreset.assisted => 'يمنع الحركات غير القانونية أثناء التعلم.',
      RulePreset.tablePenalties => 'يسمح بأخطاء محددة مع +3.',
      RulePreset.hardTable17 => 'يسمح بأخطاء محددة مع +17.',
    };
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

class _StartChoice<T> extends StatelessWidget {
  const _StartChoice({
    required this.icon,
    required this.title,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.note,
  });

  final IconData icon;
  final String title;
  final List<ButtonSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: LoungeTokens.goldAccent),
            const SizedBox(width: LoungeTokens.space2),
            Text(title, style: LoungeTokens.titleSmall),
          ],
        ),
        const SizedBox(height: LoungeTokens.space3),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<T>(
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
                BorderSide(
                  color: LoungeTokens.sandLine.withValues(alpha: 0.42),
                ),
              ),
              textStyle: WidgetStateProperty.all(
                const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(
                  horizontal: LoungeTokens.space3,
                  vertical: LoungeTokens.space2,
                ),
              ),
            ),
            showSelectedIcon: false,
            segments: segments,
            selected: {value},
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: LoungeTokens.space2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline,
                size: 14,
                color: LoungeTokens.sandLine,
              ),
              const SizedBox(width: LoungeTokens.space2),
              Expanded(child: Text(note!, style: LoungeTokens.bodyMuted)),
            ],
          ),
        ],
      ],
    );
  }
}

class _HouseRulesFooter extends StatelessWidget {
  const _HouseRulesFooter({
    required this.deckCount,
    required this.fiftyTimerSeconds,
    required this.aidsLabel,
    required this.onEdit,
  });

  final int deckCount;
  final int fiftyTimerSeconds;
  final String aidsLabel;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.18),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LoungeTokens.space4,
          LoungeTokens.space3,
          LoungeTokens.space2,
          LoungeTokens.space3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(strings.houseRules, style: LoungeTokens.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    strings.houseRulesSummary(
                      deckCount: deckCount,
                      fiftyTimerSeconds: fiftyTimerSeconds,
                      aidsLabel: aidsLabel,
                    ),
                    style: LoungeTokens.bodyMuted,
                  ),
                ],
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: LoungeTokens.space3,
                    vertical: LoungeTokens.space2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.tune,
                        size: 16,
                        color: LoungeTokens.goldAccent,
                      ),
                      const SizedBox(width: LoungeTokens.space2),
                      Text(
                        strings.edit,
                        style: const TextStyle(
                          color: LoungeTokens.goldAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
