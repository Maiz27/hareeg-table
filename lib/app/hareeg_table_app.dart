import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../data/persistence/app_repositories.dart';
import '../data/persistence/learning_progress_repository.dart';
import '../data/persistence/match_repository.dart';
import '../data/persistence/preferences_repository.dart';
import '../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../l10n/app_strings.dart';
import '../ui/core/audio/table_audio.dart';
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
import '../ui/features/learning/views/onboarding_screen.dart';
import '../ui/features/learning/views/practice_checklist_screen.dart';
import '../ui/features/match_over/views/match_over_screen.dart';
import '../ui/features/settings/models/settings_section.dart';
import '../ui/features/settings/views/licenses_screen.dart';
import '../ui/features/settings/views/settings_screen.dart';
import '../ui/features/splash/views/splash_screen.dart';
import 'app_routes.dart';

/// Root Flutter application for Hareeg Table.
///
/// Owns the app-wide preference subscription so [MotionScope],
/// [StrictnessScope], [CardThemeScope], [HapticsScope], and [AudioScope]
/// always reflect saved settings. The scopes wrap the [Navigator] so every
/// route picks up the live values without re-loading preferences itself.
class HareegTableApp extends StatefulWidget {
  /// Creates the Hareeg Table app shell.
  const HareegTableApp({
    this.preferencesRepository,
    this.matchRepository,
    this.learningProgressRepository,
    this.initialRouteOverride,
    super.key,
  });

  /// Preferences storage dependency.
  final PreferencesRepository? preferencesRepository;

  /// Active match storage dependency.
  final MatchRepository? matchRepository;

  /// Onboarding and guided practice progress storage dependency.
  final LearningProgressRepository? learningProgressRepository;

  /// Test hook: bypass the splash screen and start at a specific route. When
  /// null the app shell starts at [AppRoutes.splash].
  final String? initialRouteOverride;

  @override
  State<HareegTableApp> createState() => _HareegTableAppState();
}

class _HareegTableAppState extends State<HareegTableApp> {
  late final PreferencesRepository _preferences;
  late final MatchRepository _matches;
  late final LearningProgressRepository _learning;
  late final Future<LearningProgress> _learningFuture;
  late final TableHaptics _haptics;
  late final TableAudio _audio;
  GamePreferences _values = GamePreferences.defaults();

  @override
  void initState() {
    super.initState();
    _preferences = widget.preferencesRepository ?? AppRepositories.preferences;
    _matches = widget.matchRepository ?? AppRepositories.matches;
    _learning = widget.learningProgressRepository ?? AppRepositories.learning;
    // Kicked off at startup so the splash hand-off can decide between home
    // and first-run onboarding without a visible wait. Errors and stalled
    // reads fall back to defaults; failing to read progress must never block
    // the menu.
    _learningFuture = _learning
        .loadProgress()
        .timeout(const Duration(seconds: 2))
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('Failed to load learning progress in app shell: $error');
          debugPrintStack(stackTrace: stackTrace);
          return LearningProgress.defaults();
        });
    _haptics = TableHaptics(enabled: _values.hapticsEnabled);
    _audio = TableAudio(enabled: _values.soundEnabled);
    _loadPreferences();
  }

  /// Splash hand-off: first launch goes to onboarding, later launches go
  /// straight to the home menu.
  Future<void> _continueFromSplash(BuildContext context) async {
    final navigator = Navigator.of(context);
    final progress = await _learningFuture;
    if (!navigator.mounted) {
      return;
    }
    if (progress.onboardingCompleted) {
      // Path-based initial route generation already placed home beneath the
      // splash, so popping reveals the menu without stacking a second home.
      if (navigator.canPop()) {
        navigator.pop();
      } else {
        unawaited(navigator.pushReplacementNamed(AppRoutes.home));
      }
      return;
    }
    // Path-based initial route generation already placed home beneath the
    // splash, so replacing the splash leaves onboarding sitting on top of the
    // menu. The argument only switches the final-page copy to first-run.
    unawaited(
      navigator.pushReplacementNamed(
        AppRoutes.onboarding,
        arguments: OnboardingScreen.firstRunArgument,
      ),
    );
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
        _audio.enabled = values.soundEnabled;
      });
      if (values.soundEnabled) {
        unawaited(_audio.warmUp());
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to load preferences in app shell: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _updatePreferences(GamePreferences next) async {
    setState(() {
      _values = next;
      _haptics.enabled = next.hapticsEnabled;
      _audio.enabled = next.soundEnabled;
    });
    if (next.soundEnabled) {
      unawaited(_audio.warmUp());
    }
    try {
      await _preferences.savePreferences(next);
    } catch (error, stackTrace) {
      debugPrint('Failed to save preferences: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  void dispose() {
    unawaited(
      _audio.dispose().catchError((Object error, StackTrace stackTrace) {
        debugPrint('Failed to dispose audio gateway: $error');
        debugPrintStack(stackTrace: stackTrace);
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeTheme = CardThemeRegistry.byId(_values.cardThemeId);
    final strings = AppStrings.forLanguageCode(_values.language.code);

    return MaterialApp(
      title: strings.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      locale: Locale(_values.language.code),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      initialRoute: widget.initialRouteOverride ?? AppRoutes.splash,
      builder: (context, child) {
        final osReduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        final motion = MotionSettings(
          speed: _values.motionSpeed,
          osReducedMotion: osReduced,
        );
        return MotionScope(
          settings: motion,
          child: CardContrastScope(
            highContrast: _values.highContrastCards,
            child: StrictnessScope(
              strictness: _values.setup.tableStrictness,
              child: CardThemeScope(
                theme: activeTheme,
                child: HapticsScope(
                  haptics: _haptics,
                  child: AudioScope(
                    audio: _audio,
                    child: AppStringsScope(
                      strings: strings,
                      child: Directionality(
                        textDirection: strings.textDirection,
                        child: child ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      routes: {
        AppRoutes.splash: (context) => SplashScreen(
          onContinue: () => unawaited(_continueFromSplash(context)),
        ),
        AppRoutes.home: (context) => HomeScreen(matchRepository: _matches),
        AppRoutes.newGame: (context) =>
            NewGameSetupScreen(preferencesRepository: _preferences),
        AppRoutes.licenses: (context) =>
            LicensesScreen(themes: CardThemeRegistry.all()),
        AppRoutes.rulesHelp: (context) => const RulesHelpScreen(),
        AppRoutes.onboarding: (context) =>
            OnboardingScreen(learningRepository: _learning),
        AppRoutes.practice: (context) =>
            PracticeChecklistScreen(learningRepository: _learning),
      },
      onGenerateRoute: (settings) {
        if (settings.name == AppRoutes.settings) {
          final args = settings.arguments;
          final initialSection = args is SettingsRouteArguments
              ? args.initialSection
              : null;
          return MaterialPageRoute<void>(
            builder: (context) => SettingsScreen(
              preferences: _values,
              onUpdate: _updatePreferences,
              cardThemes: CardThemeRegistry.all(),
              isMatchActive: false,
              initialSection: initialSection,
            ),
            settings: settings,
          );
        }

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

        if (settings.name == AppRoutes.matchOver) {
          final args = settings.arguments;
          if (args is! MatchOverArguments) {
            return null;
          }
          return MaterialPageRoute<void>(
            builder: (context) => MatchOverScreen(arguments: args),
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

/// Reads the active [TableStrictness] from the nearest [StrictnessScope].
TableStrictness activeStrictness(BuildContext context) =>
    StrictnessScope.of(context);
