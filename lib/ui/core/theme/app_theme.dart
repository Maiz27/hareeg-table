import 'package:flutter/material.dart';

import 'lounge_tokens.dart';

/// Theme factory for the Hareeg Table visual direction: charcoal ground, ember
/// accent, sand lines, ivory paper; felt only on the table.
///
/// Pulls its roles and typography from [LoungeTokens] so colour/text
/// updates flow from one source. Buttons, dialogs, dividers, and selection
/// controls are tuned to match the lounge look without each screen
/// re-declaring them locally.
abstract final class AppTheme {
  /// Dark table-first theme used by the current app shell.
  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: LoungeTokens.accent,
      brightness: Brightness.dark,
      surface: LoungeTokens.panel,
      primary: LoungeTokens.accent,
      secondary: LoungeTokens.line,
      tertiary: LoungeTokens.fiftyHeat,
      error: LoungeTokens.danger,
    );

    final textTheme = TextTheme(
      displayLarge: LoungeTokens.displayLarge,
      displaySmall: LoungeTokens.display,
      titleLarge: LoungeTokens.display.copyWith(fontSize: 22),
      headlineMedium: LoungeTokens.heading,
      titleMedium: LoungeTokens.heading,
      titleSmall: LoungeTokens.titleSmall,
      bodyMedium: LoungeTokens.body,
      bodySmall: LoungeTokens.bodyMuted,
      labelLarge: LoungeTokens.titleSmall,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: LoungeTokens.uiFamily,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: LoungeTokens.surface,
      canvasColor: LoungeTokens.surface,
      dividerColor: LoungeTokens.line.withValues(alpha: 0.3),
      textTheme: textTheme,
      // Screen header (design contract section 8): the header sits on the
      // screen's own ground instead of a stock black bar, titled in the
      // display face. It darkens slightly only once content scrolls beneath it.
      appBarTheme: AppBarTheme(
        backgroundColor: LoungeTokens.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        foregroundColor: LoungeTokens.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: LoungeTokens.display.copyWith(fontSize: 22),
      ),
      cardTheme: CardThemeData(
        color: LoungeTokens.panel,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
          side: BorderSide(color: LoungeTokens.line.withValues(alpha: 0.45)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: LoungeTokens.accent,
          foregroundColor: LoungeTokens.onAccent,
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
          foregroundColor: LoungeTokens.textPrimary,
          minimumSize: const Size.fromHeight(LoungeTokens.tapTargetPrimary),
          side: const BorderSide(color: LoungeTokens.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
          ),
          textStyle: LoungeTokens.titleSmall,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: LoungeTokens.accent,
          minimumSize: const Size.fromHeight(LoungeTokens.tapTargetPrimary),
          padding: const EdgeInsets.symmetric(
            horizontal: LoungeTokens.space3,
            vertical: LoungeTokens.space2,
          ),
          textStyle: LoungeTokens.titleSmall,
        ),
      ),
      iconTheme: const IconThemeData(color: LoungeTokens.textPrimary),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: LoungeTokens.textPrimary,
          minimumSize: const Size.square(LoungeTokens.tapTargetPrimary),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: LoungeTokens.accent,
        inactiveTrackColor: LoungeTokens.line,
        thumbColor: LoungeTokens.accent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? LoungeTokens.accent
              : LoungeTokens.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? LoungeTokens.accent.withValues(alpha: 0.4)
              : LoungeTokens.textMuted.withValues(alpha: 0.3),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: LoungeTokens.panel,
        labelStyle: const TextStyle(color: LoungeTokens.textMuted),
        floatingLabelStyle: const TextStyle(color: LoungeTokens.accent),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
          borderSide: BorderSide(
            color: LoungeTokens.line.withValues(alpha: 0.45),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
          borderSide: BorderSide(
            color: LoungeTokens.line.withValues(alpha: 0.45),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
          borderSide: const BorderSide(color: LoungeTokens.accent, width: 1.6),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: LoungeTokens.panel,
        modalBackgroundColor: LoungeTokens.panel,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: LoungeTokens.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
          side: BorderSide(color: LoungeTokens.line.withValues(alpha: 0.4)),
        ),
        titleTextStyle: LoungeTokens.heading,
        contentTextStyle: LoungeTokens.body,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: LoungeTokens.panel,
        contentTextStyle: LoungeTokens.body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
          side: BorderSide(color: LoungeTokens.line.withValues(alpha: 0.4)),
        ),
      ),
    );
  }

  /// Light fallback theme for platform previews. The dark theme is the
  /// canonical experience.
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: LoungeTokens.accent),
    );
  }
}
