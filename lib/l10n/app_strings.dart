/// Temporary string catalog for user-facing copy.
///
/// Keeping strings outside widgets from the first slice makes it easier to
/// replace this class with generated localization delegates later.
abstract final class AppStrings {
  /// App title used by the platform shell and main screen.
  static const appTitle = 'Hareeg Table';

  /// Primary title shown on the app's first screen.
  static const homeTitle = 'Hareeg Table';

  /// Short subtitle for the current foundation shell.
  static const homeSubtitle = 'Classic Hareeg foundation';

  /// Label for the default Classic Hareeg mode.
  static const classicModeTitle = 'Classic Hareeg';

  /// Compact summary of the default Classic Hareeg experience.
  static const classicModeDescription =
      'Four seats, anti-clockwise turns, 51 opening, covers, jokers, and Fifty.';

  /// Status line confirming that rules code is isolated from Flutter widgets.
  static const rulesReady = 'Pure Dart rules core';

  /// Status line confirming that CPU logic has a separate boundary.
  static const cpuReady = 'CPU strategy boundary';

  /// Status line confirming that local preferences have a persistence boundary.
  static const persistenceReady = 'Local preferences boundary';
}
