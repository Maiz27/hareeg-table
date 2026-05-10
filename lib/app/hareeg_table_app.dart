import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../ui/core/theme/app_theme.dart';
import '../ui/features/home/views/home_screen.dart';

/// Root Flutter application for Hareeg Table.
///
/// This stays thin so navigation, theming, localization, and feature screens can
/// evolve independently of the platform entry point in `main.dart`.
class HareegTableApp extends StatelessWidget {
  /// Creates the Hareeg Table app shell.
  const HareegTableApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const HomeScreen(),
    );
  }
}
