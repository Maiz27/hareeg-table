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
  static const homeSubtitle = 'Offline Classic Hareeg';

  /// Main menu primary action.
  static const newGame = 'New Game';

  /// Disabled resume action.
  static const continueGame = 'Continue';

  /// Settings action.
  static const settings = 'Settings';

  /// Rules/help action.
  static const rulesHelp = 'Rules / Help';

  /// Disabled resume explanation.
  static const noSavedMatch = 'No saved match yet';

  /// Coming-soon section title.
  static const plannedModes = 'Planned modes';

  /// Hareeg 14 planned mode label.
  static const hareeg14 = 'Hareeg 14';

  /// Fifties planned mode label.
  static const fifties = 'Fifties';

  /// Coming-soon label.
  static const comingSoon = 'Coming soon';

  /// Label for the default Classic Hareeg mode.
  static const classicModeTitle = 'Classic Hareeg';

  /// Compact summary of the default Classic Hareeg experience.
  static const classicModeDescription =
      'Four seats, anti-clockwise turns, 51 opening, covers, jokers, and Fifty.';

  /// Setup screen title.
  static const setupTitle = 'Classic Hareeg setup';

  /// Start table action.
  static const startTable = 'Start Table';

  /// Live table screen title.
  static const tableTitle = 'Classic Hareeg Table';

  /// Human player label.
  static const humanSeat = 'You';

  /// Stock area label.
  static const stock = 'Stock';

  /// Discard area label.
  static const discard = 'Discard';

  /// Empty meld zone label.
  static const meldZone = 'Meld area';

  /// Draw action.
  static const drawStock = 'Draw Stock';

  /// Discard action.
  static const discardCard = 'Discard';

  /// Take discard action.
  static const takeDiscard = 'Take Discard';

  /// Return a pending discard and draw from stock.
  static const returnDiscard = 'Return + Draw';

  /// Pending discard status label.
  static const pendingDiscard = 'Pending discard';

  /// Auto-sort hand action.
  static const autoSort = 'Auto-sort';

  /// Placeholder settings title.
  static const settingsTitle = 'Settings';

  /// Rules help title.
  static const helpTitle = 'Classic Hareeg rules';

  /// Status line confirming that rules code is isolated from Flutter widgets.
  static const rulesReady = 'Pure Dart rules core';

  /// Status line confirming that CPU logic has a separate boundary.
  static const cpuReady = 'CPU strategy boundary';

  /// Status line confirming that local preferences have a persistence boundary.
  static const persistenceReady = 'Local preferences boundary';
}
