import 'package:flutter/material.dart';

import '../data/persistence/app_repositories.dart';
import '../data/persistence/match_repository.dart';
import '../data/persistence/preferences_repository.dart';
import '../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../l10n/app_strings.dart';
import '../ui/features/game_setup/views/new_game_setup_screen.dart';
import '../ui/features/game_table/views/game_table_screen.dart';
import '../ui/features/help/views/rules_help_screen.dart';
import '../ui/core/theme/app_theme.dart';
import '../ui/features/home/views/home_screen.dart';
import '../ui/features/round_summary/views/round_summary_screen.dart';
import '../ui/features/settings/views/settings_screen.dart';
import 'app_routes.dart';

/// Root Flutter application for Hareeg Table.
///
/// This stays thin so navigation, theming, localization, and feature screens can
/// evolve independently of the platform entry point in `main.dart`.
class HareegTableApp extends StatelessWidget {
  /// Creates the Hareeg Table app shell.
  const HareegTableApp({
    this.preferencesRepository,
    this.matchRepository,
    super.key,
  });

  /// Preferences storage dependency.
  final PreferencesRepository? preferencesRepository;

  /// Active match storage dependency.
  final MatchRepository? matchRepository;

  @override
  Widget build(BuildContext context) {
    final preferences = preferencesRepository ?? AppRepositories.preferences;
    final matches = matchRepository ?? AppRepositories.matches;

    return MaterialApp(
      title: AppStrings.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      initialRoute: AppRoutes.home,
      routes: {
        AppRoutes.home: (context) => HomeScreen(matchRepository: matches),
        AppRoutes.newGame: (context) =>
            NewGameSetupScreen(preferencesRepository: preferences),
        AppRoutes.settings: (context) =>
            SettingsScreen(preferencesRepository: preferences),
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
              matchRepository: matches,
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
              onContinue: () => Navigator.of(
                context,
              ).popUntil(ModalRoute.withName(AppRoutes.home)),
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
