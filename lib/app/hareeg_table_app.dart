import 'package:flutter/material.dart';

import '../data/persistence/app_repositories.dart';
import '../data/persistence/match_repository.dart';
import '../data/persistence/preferences_repository.dart';
import '../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../l10n/app_strings.dart';
import '../ui/core/aids/table_aids.dart';
import '../ui/core/cards/card_theme.dart';
import '../ui/core/cards/card_theme_registry.dart';
import '../ui/core/haptics/table_haptics.dart';
import '../ui/core/motion/motion_speed.dart';
import '../ui/core/scopes/app_scopes.dart';
import '../ui/core/theme/app_theme.dart';
import '../ui/features/game_setup/views/new_game_setup_screen.dart';
import '../ui/features/game_table/views/game_table_screen.dart';
import '../ui/features/help/views/rules_help_screen.dart';
import '../ui/features/home/views/home_screen.dart';
import '../ui/features/round_summary/views/round_summary_screen.dart';
import '../ui/features/settings/views/licenses_screen.dart';
import '../ui/features/settings/views/settings_screen.dart';
import '../ui/features/splash/views/splash_screen.dart';
import 'app_routes.dart';

/// Root Flutter application for Hareeg Table.
///
/// Owns the app-wide preference subscription so [MotionScope], [AidsScope],
/// [CardThemeScope], and [HapticsScope] always reflect saved settings. The
/// scopes wrap the [Navigator] so every route picks up the live values
/// without re-loading preferences itself.
class HareegTableApp extends StatefulWidget {
  /// Creates the Hareeg Table app shell.
  const HareegTableApp({
    this.preferencesRepository,
    this.matchRepository,
    this.initialRouteOverride,
    super.key,
  });

  /// Preferences storage dependency.
  final PreferencesRepository? preferencesRepository;

  /// Active match storage dependency.
  final MatchRepository? matchRepository;

  /// Test hook: bypass the splash screen and start at a specific route. When
  /// null the app shell starts at [AppRoutes.splash].
  final String? initialRouteOverride;

  @override
  State<HareegTableApp> createState() => _HareegTableAppState();
}

class _HareegTableAppState extends State<HareegTableApp> {
  late final PreferencesRepository _preferences;
  late final MatchRepository _matches;
  late final TableHaptics _haptics;
  GamePreferences _values = GamePreferences.defaults();

  @override
  void initState() {
    super.initState();
    _preferences = widget.preferencesRepository ?? AppRepositories.preferences;
    _matches = widget.matchRepository ?? AppRepositories.matches;
    _haptics = TableHaptics(enabled: _values.hapticsEnabled);
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final values = await _preferences.loadPreferences();
      if (!mounted) {
        return;
      }
      setState(() {
        _values = values;
        _haptics.enabled = values.hapticsEnabled;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load preferences in app shell: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _updatePreferences(GamePreferences next) async {
    setState(() {
      _values = next;
      _haptics.enabled = next.hapticsEnabled;
    });
    try {
      await _preferences.savePreferences(next);
    } catch (error, stackTrace) {
      debugPrint('Failed to save preferences: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTheme = CardThemeRegistry.byId(_values.cardThemeId);

    return MaterialApp(
      title: AppStrings.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      initialRoute: widget.initialRouteOverride ?? AppRoutes.splash,
      builder: (context, child) {
        final osReduced =
            MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        final motion = MotionSettings(
          speed: _values.motionSpeed,
          osReducedMotion: osReduced,
        );
        return MotionScope(
          settings: motion,
          child: CardThemeScope(
            theme: activeTheme,
            child: AidsScope(
              aids: _values.tableAids,
              child: HapticsScope(
                haptics: _haptics,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
      routes: {
        AppRoutes.splash: (context) => SplashScreen(
          onContinue: () =>
              Navigator.of(context).pushReplacementNamed(AppRoutes.home),
        ),
        AppRoutes.home: (context) => HomeScreen(matchRepository: _matches),
        AppRoutes.newGame: (context) => NewGameSetupScreen(
          preferencesRepository: _preferences,
        ),
        AppRoutes.settings: (context) => SettingsScreen(
          preferences: _values,
          onUpdate: _updatePreferences,
          cardThemes: CardThemeRegistry.all(),
          isMatchActive: false,
        ),
        AppRoutes.licenses: (context) => LicensesScreen(
          themes: CardThemeRegistry.all(),
        ),
        AppRoutes.rulesHelp: (context) => const RulesHelpScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == AppRoutes.table) {
          final arguments = settings.arguments;
          final snapshot = arguments is ClassicHareegMatchSnapshot
              ? arguments
              : null;
          final setup = arguments is ClassicHareegSetup
              ? arguments
              : snapshot?.setup ?? ClassicHareegSetup.defaults();
          return MaterialPageRoute<void>(
            builder: (context) => GameTableScreen(
              setup: setup,
              initialSnapshot: snapshot,
              matchRepository: _matches,
              preferences: _values,
              onPreferencesChanged: _updatePreferences,
            ),
            settings: settings,
          );
        }

        if (settings.name == AppRoutes.roundSummary) {
          final args = settings.arguments;
          if (args is! RoundSummaryArguments) {
            return null;
          }
          return MaterialPageRoute<void>(
            builder: (context) => RoundSummaryScreen(
              result: args.result,
              progress: args.progress,
              previousScores: args.previousScores,
              onContinue: args.nextSnapshot == null
                  ? null
                  : () => Navigator.of(context).pushReplacementNamed(
                      AppRoutes.table,
                      arguments: args.nextSnapshot,
                    ),
              onReturnToMenu: () => Navigator.of(
                context,
              ).popUntil(ModalRoute.withName(AppRoutes.home)),
            ),
            settings: settings,
          );
        }

        return null;
      },
    );
  }
}

/// Reads the active [HareegCardTheme] from the nearest [CardThemeScope].
HareegCardTheme activeCardTheme(BuildContext context) =>
    CardThemeScope.of(context);

/// Reads the active [TableAids] from the nearest [AidsScope].
TableAids activeAids(BuildContext context) => AidsScope.of(context);
