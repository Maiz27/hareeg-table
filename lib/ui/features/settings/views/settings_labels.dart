import '../../../../data/persistence/preferences_repository.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/motion/motion_speed.dart';
import '../../../core/theme/table_surface_theme.dart';

/// Localized name of a motion speed.
String motionSpeedLabel(MotionSpeed speed, AppStrings strings) {
  return switch (speed) {
    MotionSpeed.normal => strings.normalMotion,
    MotionSpeed.fast => strings.fastMotion,
    MotionSpeed.reduced => strings.reducedMotion,
  };
}

/// Localized name of an app language.
String appLanguageLabel(AppLanguage language, AppStrings strings) {
  return switch (language) {
    AppLanguage.english => strings.englishLanguage,
    AppLanguage.arabic => strings.arabicLanguage,
  };
}

/// Localized name of a table surface.
String tableSurfaceLabel(TableSurfaceTheme surface, AppStrings strings) {
  return switch (surface) {
    TableSurfaceTheme.sandline => strings.sandlineLounge,
    TableSurfaceTheme.felt => strings.darkFelt,
    TableSurfaceTheme.wood => strings.lightWood,
    TableSurfaceTheme.sapphire => strings.midnightSapphire,
    TableSurfaceTheme.clay => strings.crimsonClay,
  };
}

/// Localized name of a hand sort mode.
String handSortModeLabel(HandSortMode mode, AppStrings strings) {
  return switch (mode) {
    HandSortMode.manual => strings.sortManual,
    HandSortMode.byRank => strings.sortByRank,
    HandSortMode.bySuit => strings.sortBySuit,
  };
}
