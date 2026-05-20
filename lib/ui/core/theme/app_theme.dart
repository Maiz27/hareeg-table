import 'package:flutter/material.dart';

import 'lounge_tokens.dart';

/// Theme factory for the Warm Sudanese Lounge visual direction.
///
/// Pulls its palette and typography from [LoungeTokens] so colour/text
/// updates flow from one source. Buttons, dialogs, dividers, and selection
/// controls are tuned to match the lounge look without each screen
/// re-declaring them locally.
abstract final class AppTheme {
  /// Dark table-first theme used by the current app shell.
  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: LoungeTokens.goldAccent,
      brightness: Brightness.dark,
      surface: LoungeTokens.coffeeCharcoal,
      primary: LoungeTokens.goldAccent,
      secondary: LoungeTokens.sandLine,
      tertiary: LoungeTokens.fiftyFlame,
      error: LoungeTokens.deepRed,
    );

    final textTheme = const TextTheme(
      displaySmall: LoungeTokens.display,
      headlineMedium: LoungeTokens.heading,
      titleMedium: LoungeTokens.heading,
      titleSmall: LoungeTokens.titleSmall,
      bodyMedium: LoungeTokens.body,
      bodySmall: LoungeTokens.bodyMuted,
      labelLarge: LoungeTokens.titleSmall,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: LoungeTokens.feltGreen,
      canvasColor: LoungeTokens.coffeeCharcoal,
      dividerColor: LoungeTokens.sandLine.withValues(alpha: 0.3),
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: LoungeTokens.coffeeCharcoal,
        foregroundColor: LoungeTokens.offWhiteText,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: LoungeTokens.heading,
      ),
      cardTheme: CardThemeData(
        color: LoungeTokens.coffeeCharcoal,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
          side: BorderSide(
            color: LoungeTokens.sandLine.withValues(alpha: 0.45),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: LoungeTokens.goldAccent,
          foregroundColor: LoungeTokens.coffeeCharcoal,
          minimumSize: const Size.fromHeight(LoungeTokens.tapTargetPrimary),
          padding: const EdgeInsets.symmetric(
            horizontal: LoungeTokens.space4,
            vertical: LoungeTokens.space3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
          ),
          textStyle: LoungeTokens.titleSmall,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: LoungeTokens.offWhiteText,
          minimumSize: const Size.fromHeight(LoungeTokens.tapTargetPrimary),
          side: const BorderSide(color: LoungeTokens.sandLine),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
          ),
          textStyle: LoungeTokens.titleSmall,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: LoungeTokens.goldAccent,
          minimumSize: const Size.fromHeight(LoungeTokens.tapTargetPrimary),
          padding: const EdgeInsets.symmetric(
            horizontal: LoungeTokens.space3,
            vertical: LoungeTokens.space2,
          ),
          textStyle: LoungeTokens.titleSmall,
        ),
      ),
      iconTheme: const IconThemeData(color: LoungeTokens.offWhiteText),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: LoungeTokens.offWhiteText,
          minimumSize: const Size.square(LoungeTokens.tapTargetPrimary),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: LoungeTokens.goldAccent,
        inactiveTrackColor: LoungeTokens.sandLine,
        thumbColor: LoungeTokens.goldAccent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? LoungeTokens.goldAccent
              : LoungeTokens.mutedText,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? LoungeTokens.goldAccent.withValues(alpha: 0.4)
              : LoungeTokens.mutedText.withValues(alpha: 0.3),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: LoungeTokens.coffeeCharcoal,
        labelStyle: const TextStyle(color: LoungeTokens.mutedText),
        floatingLabelStyle: const TextStyle(color: LoungeTokens.goldAccent),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
          borderSide: BorderSide(
            color: LoungeTokens.sandLine.withValues(alpha: 0.45),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
          borderSide: BorderSide(
            color: LoungeTokens.sandLine.withValues(alpha: 0.45),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
          borderSide: const BorderSide(
            color: LoungeTokens.goldAccent,
            width: 1.6,
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: LoungeTokens.coffeeCharcoal,
        modalBackgroundColor: LoungeTokens.coffeeCharcoal,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: LoungeTokens.coffeeCharcoal,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
          side: BorderSide(
            color: LoungeTokens.sandLine.withValues(alpha: 0.4),
          ),
        ),
        titleTextStyle: LoungeTokens.heading,
        contentTextStyle: LoungeTokens.body,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: LoungeTokens.coffeeCharcoal,
        contentTextStyle: LoungeTokens.body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
          side: BorderSide(
            color: LoungeTokens.sandLine.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }

  /// Light fallback theme for platform previews. The dark theme is the
  /// canonical experience.
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: LoungeTokens.goldAccent),
    );
  }
}
