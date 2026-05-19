/// Named routes used by the Hareeg Table app shell.
abstract final class AppRoutes {
  /// Main menu.
  static const home = '/';

  /// Classic Hareeg setup flow.
  static const newGame = '/new-game';

  /// Live Classic Hareeg table.
  static const table = '/table';

  /// End-of-round summary shown after the live table reports a round outcome.
  static const roundSummary = '/round-summary';

  /// Local settings surface.
  static const settings = '/settings';

  /// Player-facing rules and help reference.
  static const rulesHelp = '/rules-help';
}
