import 'package:flutter/material.dart';

/// Theme factory for the warm Sudanese lounge visual direction.
abstract final class AppTheme {
  static const _feltGreen = Color(0xFF12382F);
  static const _coffeeCharcoal = Color(0xFF15110E);
  static const _cardIvory = Color(0xFFF8F0DD);
  static const _sandLine = Color(0xFFD7BD83);
  static const _goldAccent = Color(0xFFD69B35);
  static const _offWhiteText = Color(0xFFF5EFE3);
  static const _mutedText = Color(0xFFB8AA91);

  /// Dark table-first theme used by the current app shell.
  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _goldAccent,
      brightness: Brightness.dark,
      surface: _coffeeCharcoal,
      primary: _goldAccent,
      secondary: _sandLine,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _feltGreen,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: _offWhiteText,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(color: _cardIvory, fontWeight: FontWeight.w700),
        bodyMedium: TextStyle(color: _offWhiteText),
        bodySmall: TextStyle(color: _mutedText),
      ),
      cardTheme: CardThemeData(
        color: _coffeeCharcoal,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: _sandLine),
        ),
      ),
    );
  }

  /// Light fallback theme for platform previews and future settings.
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _goldAccent),
    );
  }
}
