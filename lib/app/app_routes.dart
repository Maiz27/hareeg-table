/// Named routes used by the Hareeg Table app shell.
abstract final class AppRoutes {
  /// Splash screen shown on first frame before the home menu.
  static const splash = '/splash';

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

  /// About + asset/theme licenses surface.
  static const licenses = '/licenses';

  /// Player-facing rules and help reference.
  static const rulesHelp = '/rules-help';
}
